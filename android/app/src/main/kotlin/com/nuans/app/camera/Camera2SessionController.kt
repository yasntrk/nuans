package com.nuans.app.camera

import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest as Camera2Request
import android.hardware.camera2.CaptureResult as Camera2Result
import android.hardware.camera2.TotalCaptureResult
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import io.flutter.view.TextureRegistry
import kotlin.math.max
import kotlin.math.min

/**
 * Owns the Camera2 session: device selection, manual control, the burst and the
 * reduction of its regions.
 *
 * The session runs three streams at once - a preview surface, a YUV stream for
 * the live metrics and a full-size RAW stream for the burst. That combination
 * is only a guaranteed one when both non-raw streams stay at preview size,
 * which is why [CapabilityProbe] caps the preview at 1080p.
 */
class Camera2SessionController(
    private val manager: CameraManager,
    private val textureRegistry: TextureRegistry,
) {
    /** Preview frame rate; 30 is plenty for a traffic light. */
    private val previewFrameRate = 30

    private val cameraThread = HandlerThread("nuans-camera").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private val store = CaptureStore()

    private var selection: CapabilityProbe.Selection? = null
    private var cameraDevice: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var metricsReader: ImageReader? = null
    private var rawReader: ImageReader? = null

    private var previewConfig: PreviewConfig? = null
    private var latestPreview: YuvFrame? = null
    private var previousPreview: YuvFrame? = null
    private var lastMetricsAt = 0L
    private var isLocked = false
    private var lockedIso = 0
    private var lockedExposureNanos = 0L
    private var lockedFocusDistance: Float? = null
    private var lockedGains: FloatArray = UNITY_GAINS
    private var observedAutoGains: FloatArray? = null
    private var burst: BurstCollector? = null

    /** Set by the plugin so out-of-band failures and progress reach Dart. */
    var events: ShadeCameraFlutterApi? = null

    // region initialisation

    fun initialize(callback: (Result<CameraCapabilities>) -> Unit) {
        cameraHandler.post {
            try {
                val probed = CapabilityProbe(manager).probe()
                selection = probed
                openCamera(probed.cameraId)
                callback(Result.success(probed.capabilities))
            } catch (failure: ShadeCameraFailure) {
                callback(Result.failure(failure))
            } catch (error: SecurityException) {
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.PERMISSION_DENIED,
                            "camera access has not been granted",
                        ),
                    ),
                )
            } catch (error: Exception) {
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.CONFIGURATION_FAILED,
                            error.message ?: "could not open the camera",
                        ),
                    ),
                )
            }
        }
    }

    private fun openCamera(cameraId: String) {
        val latch = java.util.concurrent.CountDownLatch(1)
        var failure: ShadeCameraFailure? = null
        manager.openCamera(
            cameraId,
            object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    cameraDevice = device
                    latch.countDown()
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    cameraDevice = null
                    events?.onSessionInterrupted(
                        SessionInterruption.DEVICE_IN_USE_BY_ANOTHER_CLIENT,
                    ) {}
                    latch.countDown()
                }

                override fun onError(device: CameraDevice, error: Int) {
                    val opened = latch.count == 0L
                    device.close()
                    cameraDevice = null
                    val raised = ShadeCameraFailure(
                        when (error) {
                            ERROR_CAMERA_IN_USE, ERROR_MAX_CAMERAS_IN_USE ->
                                CameraErrorCode.DEVICE_UNAVAILABLE
                            ERROR_CAMERA_DISABLED -> CameraErrorCode.PERMISSION_DENIED
                            else -> CameraErrorCode.CONFIGURATION_FAILED
                        },
                        "camera $cameraId reported error $error",
                        recoverable = error == ERROR_CAMERA_IN_USE ||
                            error == ERROR_MAX_CAMERAS_IN_USE,
                    )
                    if (opened) {
                        // The device was already open, so nobody is waiting on
                        // a callback: this has to travel out of band or it is
                        // reported to nobody at all.
                        events?.onCameraError(raised.toEvent()) {}
                    } else {
                        failure = raised
                    }
                    latch.countDown()
                }
            },
            cameraHandler,
        )
        latch.await()
        failure?.let { throw it }
        if (cameraDevice == null) {
            throw ShadeCameraFailure(
                CameraErrorCode.DEVICE_UNAVAILABLE,
                "camera $cameraId did not open",
            )
        }
    }

    // endregion

    // region preview

    fun startPreview(config: PreviewConfig, callback: (Result<Long>) -> Unit) {
        cameraHandler.post {
            try {
                val probed = selection ?: throw ShadeCameraFailure(
                    CameraErrorCode.CONFIGURATION_FAILED,
                    "initialize has not run",
                )
                val device = cameraDevice ?: throw ShadeCameraFailure(
                    CameraErrorCode.DEVICE_UNAVAILABLE,
                    "the camera is not open",
                )
                previewConfig = config
                previousPreview = null
                latestPreview = null

                if (session == null) {
                    configureSession(device, probed)
                }
                startRepeating(automatic = !isLocked)
                callback(Result.success(textureEntry?.id() ?: 0L))
            } catch (failure: ShadeCameraFailure) {
                callback(Result.failure(failure))
            }
        }
    }

    private fun configureSession(
        device: CameraDevice,
        probed: CapabilityProbe.Selection,
    ) {
        val entry = textureRegistry.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(
            probed.previewSize.width,
            probed.previewSize.height,
        )
        textureEntry = entry
        previewSurface = Surface(entry.surfaceTexture())

        metricsReader = ImageReader.newInstance(
            probed.previewSize.width,
            probed.previewSize.height,
            ImageFormat.YUV_420_888,
            2,
        ).apply {
            setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    previousPreview = latestPreview
                    latestPreview = YuvFrame.copyFrom(image)
                    publishMetricsIfDue()
                } finally {
                    image.close()
                }
            }, cameraHandler)
        }

        val surfaces = mutableListOf(previewSurface!!, metricsReader!!.surface)
        probed.rawSize?.let { rawSize ->
            rawReader = ImageReader.newInstance(
                rawSize.width,
                rawSize.height,
                ImageFormat.RAW_SENSOR,
                // One more than the burst length, so the reader never has to
                // drop a frame while the previous one is still being copied.
                kBurstFrameCountFallback + 1,
            ).apply {
                setOnImageAvailableListener({ reader ->
                    val image = reader.acquireNextImage() ?: return@setOnImageAvailableListener
                    try {
                        burst?.addFrame(BayerFrame.copyFrom(image))
                    } finally {
                        image.close()
                    }
                }, cameraHandler)
            }
            surfaces.add(rawReader!!.surface)
        }

        val latch = java.util.concurrent.CountDownLatch(1)
        var failure: ShadeCameraFailure? = null
        @Suppress("DEPRECATION")
        device.createCaptureSession(
            surfaces,
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    session = configured
                    latch.countDown()
                }

                override fun onConfigureFailed(configured: CameraCaptureSession) {
                    failure = ShadeCameraFailure(
                        CameraErrorCode.CONFIGURATION_FAILED,
                        "the camera refused the preview, metrics and raw stream combination",
                    )
                    latch.countDown()
                }

                override fun onClosed(closed: CameraCaptureSession) {
                    if (session !== closed) return
                    session = null
                    events?.onCameraError(
                        ShadeCameraFailure(
                            CameraErrorCode.INTERRUPTED,
                            "the capture session was closed by the system",
                            recoverable = true,
                        ).toEvent(),
                    ) {}
                }
            },
            cameraHandler,
        )
        latch.await()
        failure?.let { throw it }
    }

    /**
     * Builds the repeating request.
     *
     * In manual mode every automatic stage is switched off, not merely locked:
     * `CONTROL_MODE_OFF` stops the 3A loops, and noise reduction and edge
     * enhancement are disabled because both are spatial filters that would move
     * energy between neighbouring pixels - exactly what a region average must
     * not have happen before it is taken.
     *
     * Hot pixel correction is the one piece of processing left on. A stuck pixel
     * is a permanent bright outlier, and while the specular filter in Dart would
     * reject it, letting the sensor's own map remove it keeps those samples.
     */
    private fun buildRequest(
        device: CameraDevice,
        targets: List<Surface>,
        automatic: Boolean,
    ): Camera2Request {
        val builder = device.createCaptureRequest(
            if (automatic) CameraDevice.TEMPLATE_PREVIEW else CameraDevice.TEMPLATE_STILL_CAPTURE,
        )
        targets.forEach(builder::addTarget)
        builder.set(Camera2Request.FLASH_MODE, CameraMetadata.FLASH_MODE_OFF)
        builder.set(Camera2Request.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_OFF)
        builder.set(
            Camera2Request.NOISE_REDUCTION_MODE,
            CameraMetadata.NOISE_REDUCTION_MODE_OFF,
        )
        builder.set(Camera2Request.EDGE_MODE, CameraMetadata.EDGE_MODE_OFF)
        builder.set(
            Camera2Request.HOT_PIXEL_MODE,
            CameraMetadata.HOT_PIXEL_MODE_HIGH_QUALITY,
        )
        builder.set(Camera2Request.CONTROL_ENABLE_ZSL, false)

        if (automatic) {
            builder.set(Camera2Request.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
            builder.set(Camera2Request.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
            builder.set(Camera2Request.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_AUTO)
            builder.set(Camera2Request.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
        } else {
            builder.set(Camera2Request.CONTROL_MODE, CameraMetadata.CONTROL_MODE_OFF)
            builder.set(Camera2Request.SENSOR_SENSITIVITY, lockedIso)
            builder.set(Camera2Request.SENSOR_EXPOSURE_TIME, lockedExposureNanos)
            builder.set(
                Camera2Request.SENSOR_FRAME_DURATION,
                max(lockedExposureNanos, 1_000_000_000L / previewFrameRate),
            )
            builder.set(Camera2Request.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_OFF)
            lockedFocusDistance?.let {
                builder.set(Camera2Request.LENS_FOCUS_DISTANCE, it)
            }
            builder.set(Camera2Request.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_OFF)
            builder.set(
                Camera2Request.COLOR_CORRECTION_MODE,
                CameraMetadata.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX,
            )
            builder.set(
                Camera2Request.COLOR_CORRECTION_GAINS,
                android.hardware.camera2.params.RggbChannelVector(
                    lockedGains[0],
                    lockedGains[1],
                    lockedGains[2],
                    lockedGains[3],
                ),
            )
        }
        return builder.build()
    }

    private fun startRepeating(automatic: Boolean) {
        val device = cameraDevice ?: return
        val active = session ?: return
        val targets = listOfNotNull(previewSurface, metricsReader?.surface)
        active.setRepeatingRequest(
            buildRequest(device, targets, automatic),
            object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    captureSession: CameraCaptureSession,
                    request: Camera2Request,
                    result: TotalCaptureResult,
                ) {
                    result.get(Camera2Result.SENSOR_SENSITIVITY)?.let { lockedIso = it }
                    result.get(Camera2Result.SENSOR_EXPOSURE_TIME)?.let {
                        lockedExposureNanos = it
                    }
                    if (automatic) {
                        result.get(Camera2Result.COLOR_CORRECTION_GAINS)?.let { vector ->
                            observedAutoGains = floatArrayOf(
                                vector.red,
                                vector.greenEven,
                                vector.greenOdd,
                                vector.blue,
                            )
                        }
                    }
                }
            },
            cameraHandler,
        )
    }

    fun updatePreviewRois(config: PreviewConfig, callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            previewConfig = config
            callback(Result.success(Unit))
        }
    }

    fun stopPreview(callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            session?.stopRepeating()
            previewConfig = null
            latestPreview = null
            previousPreview = null
            callback(Result.success(Unit))
        }
    }

    private fun publishMetricsIfDue() {
        val config = previewConfig ?: return
        val frame = latestPreview ?: return
        val now = System.currentTimeMillis()
        if (now - lastMetricsAt < config.metricsIntervalMillis) return
        lastMetricsAt = now

        val tooth = PixelRegion.from(config.toothRect, frame.width, frame.height)
        val card = PixelRegion.from(config.grayCardRect, frame.width, frame.height)
        val toothClipping = FrameQualityAnalyzer.clippingFractions(frame, tooth)
        val cardClipping = FrameQualityAnalyzer.clippingFractions(frame, card)
        val toothStats = FrameQualityAnalyzer.channelStatistics(frame, tooth)
        val cardStats = FrameQualityAnalyzer.channelStatistics(frame, card)
        val quadrants = card.quadrants()
            .flatMap { FrameQualityAnalyzer.channelStatistics(frame, it).mean.toList() }
            .toDoubleArray()
        val tabMean = config.shadeTabRect?.let {
            FrameQualityAnalyzer
                .channelStatistics(frame, PixelRegion.from(it, frame.width, frame.height))
                .mean
        }

        events?.onPreviewMetrics(
            PreviewMetrics(
                timestampMillis = now,
                format = selection?.capabilities?.defaultFormat
                    ?: CaptureFormat.PROCESSED_LINEARISABLE,
                signalEncoding = SignalEncoding.DISPLAY_REFERRED_SRGB,
                toothSharpness = FrameQualityAnalyzer.laplacianVariance(frame, tooth),
                motionScore = FrameQualityAnalyzer
                    .motionScore(frame, previousPreview, tooth) ?: 0.0,
                toothClippedFraction = toothClipping.first,
                toothShadowFraction = toothClipping.second,
                toothRgbMean = toothStats.mean,
                grayCardClippedFraction = cardClipping.first,
                grayCardTextureRatio = cardStats.uniformityRatio,
                grayCardQuadrantRgb = quadrants,
                iso = lockedIso.toLong(),
                exposureSeconds = lockedExposureNanos / 1_000_000_000.0,
                focusLocked = lockedFocusDistance != null,
                exposureLocked = isLocked,
                whiteBalanceLocked = isLocked,
                focusDistanceDiopters = lockedFocusDistance?.toDouble(),
                shadeTabRgbMean = tabMean,
            ),
        ) {}
    }

    // endregion

    // region focus and locking

    /**
     * Runs autofocus at a point, then pins the lens there.
     *
     * Pinning matters more than focusing: autofocus hunting between the burst
     * frames changes the magnification slightly, which moves the region
     * outlines relative to the tooth.
     */
    fun focusAndLockAt(x: Double, y: Double, callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            val device = cameraDevice
            val active = session
            val probed = selection
            if (device == null || active == null || probed == null) {
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.PREVIEW_NOT_RUNNING,
                            "focus needs a running preview",
                        ),
                    ),
                )
                return@post
            }
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            listOfNotNull(previewSurface, metricsReader?.surface).forEach(builder::addTarget)
            builder.set(Camera2Request.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
            builder.set(Camera2Request.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_AUTO)
            builder.set(
                Camera2Request.CONTROL_AF_TRIGGER,
                CameraMetadata.CONTROL_AF_TRIGGER_START,
            )
            FocusRegion.metering(probed.characteristics, x, y)?.let {
                builder.set(Camera2Request.CONTROL_AF_REGIONS, arrayOf(it))
            }
            active.capture(
                builder.build(),
                object : CameraCaptureSession.CaptureCallback() {
                    override fun onCaptureCompleted(
                        captureSession: CameraCaptureSession,
                        request: Camera2Request,
                        result: TotalCaptureResult,
                    ) {
                        val state = result.get(Camera2Result.CONTROL_AF_STATE)
                        val settled = state == null ||
                            state == Camera2Result.CONTROL_AF_STATE_FOCUSED_LOCKED ||
                            state == Camera2Result.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
                        if (!settled) return
                        lockedFocusDistance =
                            result.get(Camera2Result.LENS_FOCUS_DISTANCE)
                        if (lockedFocusDistance == null) {
                            callback(
                                Result.failure(
                                    ShadeCameraFailure(
                                        CameraErrorCode.FOCUS_LOCK_FAILED,
                                        "the camera does not report its focus distance, " +
                                            "so focus cannot be pinned",
                                    ),
                                ),
                            )
                            return
                        }
                        callback(Result.success(Unit))
                    }
                },
                cameraHandler,
            )
        }
    }

    /**
     * Pins ISO at the sensor minimum, solves the shutter against the grey card
     * and freezes the white balance gains.
     *
     * The gain values themselves do not matter; only that they stop moving. The
     * real correction comes from the card.
     */
    fun lockCaptureParameters(
        settings: CaptureSettings,
        callback: (Result<ExposureState>) -> Unit,
    ) {
        cameraHandler.post {
            try {
                val probed = selection ?: throw ShadeCameraFailure(
                    CameraErrorCode.CONFIGURATION_FAILED,
                    "initialize has not run",
                )
                val config = previewConfig ?: throw ShadeCameraFailure(
                    CameraErrorCode.PREVIEW_NOT_RUNNING,
                    "the shutter can only be solved against a running preview",
                )
                if (!probed.capabilities.supportsManualSensor) {
                    throw ShadeCameraFailure(
                        CameraErrorCode.EXPOSURE_LOCK_FAILED,
                        "this camera has no manual sensor control",
                    )
                }
                lockedIso = settings.isoOverride?.toInt()
                    ?: probed.capabilities.minIso.toInt()
                // Freeze whatever the automatic white balance had settled on.
                // The value is irrelevant to the measurement - the grey card
                // supplies the real correction - but it has to stop moving, so
                // guessing a daylight-looking vector here would be a magic
                // number pretending to be a calibration. Unity gains are the
                // fallback when the camera does not report the current ones.
                lockedGains = observedAutoGains ?: UNITY_GAINS
                val limits = ExposureSolver.Limits(
                    minDurationSeconds = probed.capabilities.minExposureSeconds,
                    maxDurationSeconds = min(
                        probed.capabilities.maxExposureSeconds,
                        1.0 / previewFrameRate,
                    ),
                )
                var duration = settings.exposureSecondsOverride
                    ?: max(limits.minDurationSeconds, min(1.0 / 120, limits.maxDurationSeconds))

                for (iteration in 0 until ExposureSolver.MAX_ITERATIONS) {
                    lockedExposureNanos = (duration * 1_000_000_000L).toLong()
                    isLocked = true
                    startRepeating(automatic = false)
                    Thread.sleep(150)
                    val frame = latestPreview ?: throw ShadeCameraFailure(
                        CameraErrorCode.PREVIEW_NOT_RUNNING,
                        "no preview frame arrived while solving exposure",
                        recoverable = true,
                    )
                    val card = PixelRegion.from(
                        config.grayCardRect,
                        frame.width,
                        frame.height,
                    )
                    val tooth = PixelRegion.from(
                        config.toothRect,
                        frame.width,
                        frame.height,
                    )
                    val luma = FrameQualityAnalyzer.channelStatistics(frame, card).mean[1]
                    val clipped = FrameQualityAnalyzer.clippingFractions(frame, tooth).first
                    val outcome = ExposureSolver.evaluate(
                        iteration = iteration,
                        current = duration,
                        measuredCardLuma = luma,
                        toothClippedFraction = clipped,
                        targetLuma = settings.grayCardTargetLuma,
                        acceptableLumaRange = 0.20..0.70,
                        maxToothClippedFraction = settings.maxClippedFraction,
                        limits = limits,
                    )
                    duration = outcome.durationSeconds
                    if (outcome is ExposureSolver.Outcome.Retry) continue
                    break
                }
                lockedExposureNanos = (duration * 1_000_000_000L).toLong()
                startRepeating(automatic = false)
                callback(Result.success(exposureState()))
            } catch (failure: ShadeCameraFailure) {
                callback(Result.failure(failure))
            }
        }
    }

    fun unlockCaptureParameters(callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            isLocked = false
            lockedFocusDistance = null
            startRepeating(automatic = true)
            callback(Result.success(Unit))
        }
    }

    private fun exposureState(): ExposureState = ExposureState(
        iso = lockedIso.toLong(),
        exposureSeconds = lockedExposureNanos / 1_000_000_000.0,
        focusLocked = lockedFocusDistance != null,
        exposureLocked = isLocked,
        whiteBalanceLocked = isLocked,
        whiteBalanceGains = doubleArrayOf(
            lockedGains[0].toDouble(),
            lockedGains[1].toDouble(),
            lockedGains[3].toDouble(),
        ),
        focusDistanceDiopters = lockedFocusDistance?.toDouble(),
        colorTemperatureKelvin = null,
    )

    // endregion

    // region capture

    fun capture(request: CaptureRequest, callback: (Result<CaptureResult>) -> Unit) {
        cameraHandler.post {
            try {
                val probed = selection ?: throw ShadeCameraFailure(
                    CameraErrorCode.CONFIGURATION_FAILED,
                    "initialize has not run",
                )
                val device = cameraDevice ?: throw ShadeCameraFailure(
                    CameraErrorCode.DEVICE_UNAVAILABLE,
                    "the camera is not open",
                )
                val active = session ?: throw ShadeCameraFailure(
                    CameraErrorCode.PREVIEW_NOT_RUNNING,
                    "no capture session",
                )
                val reader = rawReader ?: throw ShadeCameraFailure(
                    CameraErrorCode.RAW_UNAVAILABLE,
                    "this camera has no raw stream",
                )
                val pattern = probed.pattern ?: throw ShadeCameraFailure(
                    CameraErrorCode.RAW_UNAVAILABLE,
                    "this camera does not report a Bayer layout",
                )
                if (!isLocked) {
                    throw ShadeCameraFailure(
                        CameraErrorCode.EXPOSURE_LOCK_FAILED,
                        "capture parameters must be locked before a burst",
                        captureId = request.captureId,
                    )
                }
                if (burst != null) {
                    throw ShadeCameraFailure(
                        CameraErrorCode.CAPTURE_FAILED,
                        "a burst is already in flight",
                        recoverable = true,
                        captureId = request.captureId,
                    )
                }

                val expected = request.settings.burstFrameCount.toInt()
                val collector = BurstCollector(expected) { frames, levels ->
                    burst = null
                    try {
                        callback(
                            Result.success(
                                reduce(
                                    frames = frames,
                                    levels = levels ?: staticLevels(probed),
                                    pattern = pattern,
                                    request = request,
                                    probed = probed,
                                ),
                            ),
                        )
                    } catch (failure: ShadeCameraFailure) {
                        callback(Result.failure(failure))
                    }
                }
                burst = collector

                events?.onCaptureProgress(
                    CaptureProgress(
                        captureId = request.captureId,
                        stage = CaptureStage.CAPTURING_BURST,
                        capturedFrames = 0,
                        requestedFrames = request.settings.burstFrameCount,
                    ),
                ) {}

                val still = buildRequest(device, listOf(reader.surface), automatic = false)
                active.captureBurst(
                    List(expected) { still },
                    object : CameraCaptureSession.CaptureCallback() {
                        override fun onCaptureCompleted(
                            captureSession: CameraCaptureSession,
                            completed: Camera2Request,
                            result: TotalCaptureResult,
                        ) {
                            collector.addLevels(dynamicLevels(result, probed))
                        }

                        override fun onCaptureFailed(
                            captureSession: CameraCaptureSession,
                            failed: Camera2Request,
                            failure: android.hardware.camera2.CaptureFailure,
                        ) {
                            collector.markFrameFailed()
                        }
                    },
                    cameraHandler,
                )
            } catch (failure: ShadeCameraFailure) {
                burst = null
                callback(Result.failure(failure))
            }
        }
    }

    /**
     * Per-frame black and white levels when the camera reports them.
     *
     * Preferred over the static pattern because the pedestal drifts with sensor
     * temperature, and the shadow rejection threshold sits exactly where that
     * drift shows. All frames of one locked burst use the first frame's levels:
     * they were taken within a few hundred milliseconds of each other at the
     * same sensitivity, so the drift between them is below a least significant
     * bit.
     */
    private fun dynamicLevels(
        result: TotalCaptureResult,
        probed: CapabilityProbe.Selection,
    ): SensorLevels? {
        val black = result.get(Camera2Result.SENSOR_DYNAMIC_BLACK_LEVEL) ?: return null
        val white = result.get(Camera2Result.SENSOR_DYNAMIC_WHITE_LEVEL)
            ?: probed.characteristics.get(
                android.hardware.camera2.CameraCharacteristics.SENSOR_INFO_WHITE_LEVEL,
            )
            ?: return null
        if (black.size < 4) return null
        return SensorLevels(
            black = DoubleArray(4) { black[it].toDouble() },
            white = white.toDouble(),
            isDynamic = true,
        )
    }

    private fun staticLevels(probed: CapabilityProbe.Selection): SensorLevels {
        val characteristics = probed.characteristics
        val pattern = characteristics.get(
            android.hardware.camera2.CameraCharacteristics.SENSOR_BLACK_LEVEL_PATTERN,
        )
        val white = characteristics.get(
            android.hardware.camera2.CameraCharacteristics.SENSOR_INFO_WHITE_LEVEL,
        ) ?: throw ShadeCameraFailure(
            CameraErrorCode.RAW_UNAVAILABLE,
            "this camera publishes no white level, so raw data cannot be normalised",
        )
        if (pattern == null) {
            return SensorLevels.uniform(0.0, white.toDouble(), isDynamic = false)
        }
        val black = DoubleArray(4)
        for (row in 0 until 2) {
            for (column in 0 until 2) {
                black[row * 2 + column] =
                    pattern.getOffsetForIndex(column, row).toDouble()
            }
        }
        return SensorLevels(black, white.toDouble(), isDynamic = false)
    }

    private fun reduce(
        frames: List<BayerFrame>,
        levels: SensorLevels,
        pattern: BayerPattern,
        request: CaptureRequest,
        probed: CapabilityProbe.Selection,
    ): CaptureResult {
        if (frames.isEmpty()) {
            throw ShadeCameraFailure(
                CameraErrorCode.CAPTURE_FAILED,
                "the burst produced no frames",
                captureId = request.captureId,
            )
        }
        events?.onCaptureProgress(
            CaptureProgress(
                captureId = request.captureId,
                stage = CaptureStage.SELECTING_FRAMES,
                capturedFrames = frames.size.toLong(),
                requestedFrames = request.settings.burstFrameCount,
            ),
        ) {}

        val toothRect = request.rois.firstOrNull { it.kind == RoiKind.TOOTH_BAND }?.rect
            ?: NormalizedRect(left = 0.3, top = 0.3, width = 0.4, height = 0.4)
        val sharpness = frames.map { frame ->
            BayerSharpness.greenLaplacianVariance(
                frame = frame,
                pattern = pattern,
                levels = levels,
                roi = SuperpixelRectangle.from(toothRect, frame.width, frame.height),
            )
        }
        val best = sharpness.maxOrNull() ?: 0.0
        val floor = max(request.settings.minSharpness, best * 0.60)
        val qualities = sharpness.mapIndexed { index, value ->
            FrameQuality(
                frameIndex = index.toLong(),
                sharpness = value,
                motionScore = 0.0,
                clippedFraction = 0.0,
                accepted = value >= floor,
                rejectReason = if (value >= floor) null else FrameRejectReason.LOW_SHARPNESS,
            )
        }
        val accepted = frames.filterIndexed { index, _ -> qualities[index].accepted }
        if (accepted.isEmpty()) {
            throw ShadeCameraFailure(
                CameraErrorCode.CAPTURE_FAILED,
                "every frame of the burst was rejected as unsharp",
                recoverable = true,
                captureId = request.captureId,
            )
        }

        events?.onCaptureProgress(
            CaptureProgress(
                captureId = request.captureId,
                stage = CaptureStage.REDUCING_ROIS,
                capturedFrames = frames.size.toLong(),
                requestedFrames = request.settings.burstFrameCount,
            ),
        ) {}

        val samples = request.rois.map { roi ->
            reduceOne(roi, accepted, pattern, levels, request.settings.sampling)
        }

        store.store(
            RetainedCapture(
                captureId = request.captureId,
                frames = accepted,
                qualities = qualities.filter { it.accepted },
                pattern = pattern,
                levels = levels,
            ),
        )

        return CaptureResult(
            captureId = request.captureId,
            tier = probed.capabilities.tier,
            format = CaptureFormat.BAYER_RAW,
            signalEncoding = SignalEncoding.LINEAR,
            rois = samples,
            frames = qualities,
            acceptedFrameCount = accepted.size.toLong(),
            exposure = exposureState(),
            capturedAtUtcMillis = System.currentTimeMillis(),
            deviceModel = probed.capabilities.deviceModel,
            lensId = probed.capabilities.lensId,
            sensorWhiteLevel = levels.white,
            sensorBlackLevel = levels.blackAt(0),
            previewImagePath = null,
            rawFilePath = null,
            dngMetadata = null,
        )
    }

    private fun reduceOne(
        roi: RoiRequest,
        frames: List<BayerFrame>,
        pattern: BayerPattern,
        levels: SensorLevels,
        sampling: SamplingSettings,
    ): RoiSample {
        val rectangle = SuperpixelRectangle.from(
            roi.rect,
            frames[0].width,
            frames[0].height,
        )
        val budget = if (roi.kind == RoiKind.COLOR_CHECKER_PATCH) {
            min(sampling.maxSamplesPerRoi.toInt(), 512)
        } else {
            sampling.maxSamplesPerRoi.toInt()
        }
        val reduction = BayerReducer.reduce(
            frames = frames,
            pattern = pattern,
            levels = levels,
            roi = rectangle,
            maxSamples = budget,
            clippingThreshold = sampling.clippingThreshold,
        )
        return RoiSample(
            roiId = roi.roiId,
            kind = roi.kind,
            rect = roi.rect,
            rgbSamples = reduction.samples,
            sampleCount = reduction.sampleCount.toLong(),
            totalSuperpixels = reduction.totalSuperpixels.toLong(),
            clippedSuperpixels = reduction.clippedSuperpixels.toLong(),
            decimationStride = reduction.decimationStride.toLong(),
            channelMean = reduction.channelMean,
            channelStdDev = reduction.channelStdDev,
            widthInSuperpixels = reduction.widthInSuperpixels.toLong(),
            heightInSuperpixels = reduction.heightInSuperpixels.toLong(),
            region = roi.region,
            index = roi.index,
        )
    }

    fun resampleRoi(
        captureId: String,
        roi: RoiRequest,
        sampling: SamplingSettings,
        callback: (Result<RoiSample>) -> Unit,
    ) {
        cameraHandler.post {
            val retained = store.capture(captureId)
            if (retained == null) {
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.UNKNOWN_CAPTURE_ID,
                            "no retained capture with this identifier",
                            captureId = captureId,
                        ),
                    ),
                )
                return@post
            }
            try {
                callback(
                    Result.success(
                        reduceOne(
                            roi,
                            retained.frames,
                            retained.pattern,
                            retained.levels,
                            sampling,
                        ),
                    ),
                )
            } catch (failure: ShadeCameraFailure) {
                callback(Result.failure(failure))
            }
        }
    }

    fun releaseCapture(captureId: String, callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            store.release(captureId)
            callback(Result.success(Unit))
        }
    }

    fun dispose(callback: (Result<Unit>) -> Unit) {
        cameraHandler.post {
            session?.close()
            session = null
            cameraDevice?.close()
            cameraDevice = null
            metricsReader?.close()
            metricsReader = null
            rawReader?.close()
            rawReader = null
            previewSurface?.release()
            previewSurface = null
            textureEntry?.release()
            textureEntry = null
            store.releaseAll()
            latestPreview = null
            previousPreview = null
            isLocked = false
            callback(Result.success(Unit))
            cameraThread.quitSafely()
        }
    }

    // endregion

    /** Gathers the frames and levels of one burst and reports once complete. */
    private class BurstCollector(
        private val expected: Int,
        private val onComplete: (List<BayerFrame>, SensorLevels?) -> Unit,
    ) {
        private val frames = ArrayList<BayerFrame>()
        private var levels: SensorLevels? = null
        private var failedFrames = 0
        private var finished = false

        @Synchronized
        fun addFrame(frame: BayerFrame) {
            if (finished) return
            frames.add(frame)
            finishIfDone()
        }

        @Synchronized
        fun addLevels(candidate: SensorLevels?) {
            if (levels == null) levels = candidate
        }

        @Synchronized
        fun markFrameFailed() {
            if (finished) return
            failedFrames++
            finishIfDone()
        }

        private fun finishIfDone() {
            if (frames.size + failedFrames < expected) return
            finished = true
            onComplete(frames.toList(), levels)
        }
    }
}

/** Burst length used to size the raw reader before Dart's settings arrive. */
private const val kBurstFrameCountFallback = 3

/**
 * Neutral channel gains, used only when the camera does not report the gains
 * its automatic white balance had settled on.
 */
private val UNITY_GAINS = floatArrayOf(1f, 1f, 1f, 1f)

/** Turns a normalised tap into a metering rectangle on the active sensor array. */
private object FocusRegion {
    fun metering(
        characteristics: android.hardware.camera2.CameraCharacteristics,
        x: Double,
        y: Double,
    ): android.hardware.camera2.params.MeteringRectangle? {
        val active = characteristics.get(
            android.hardware.camera2.CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE,
        ) ?: return null
        // A tenth of the frame around the tap: wide enough to hold a tooth,
        // narrow enough not to let the gingiva drive the focus.
        val halfWidth = (active.width() * 0.05).toInt().coerceAtLeast(1)
        val halfHeight = (active.height() * 0.05).toInt().coerceAtLeast(1)
        val centreX = (active.left + x * active.width()).toInt()
        val centreY = (active.top + y * active.height()).toInt()
        val left = (centreX - halfWidth).coerceIn(active.left, active.right - 1)
        val top = (centreY - halfHeight).coerceIn(active.top, active.bottom - 1)
        val right = (centreX + halfWidth).coerceIn(left + 1, active.right)
        val bottom = (centreY + halfHeight).coerceIn(top + 1, active.bottom)
        return android.hardware.camera2.params.MeteringRectangle(
            left,
            top,
            right - left,
            bottom - top,
            android.hardware.camera2.params.MeteringRectangle.METERING_WEIGHT_MAX,
        )
    }
}
