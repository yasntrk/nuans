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
import android.os.Looper
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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

    /**
     * The control thread. Every host call is serialised onto it, and the code
     * running there is allowed to block while it waits for the camera.
     */
    private val cameraThread = HandlerThread("nuans-camera").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)

    /**
     * Where the framework delivers device, session and capture state.
     *
     * It has to be a different thread from the control one. Camera2 posts a
     * state callback to a handler of our choosing, and the control flow waits
     * for that callback to arrive; sharing one thread means the wait blocks
     * the thread that has to deliver what it is waiting for, and the camera
     * never opens at all.
     */
    private val callbackThread =
        HandlerThread("nuans-camera-callbacks").apply { start() }
    private val callbackHandler = Handler(callbackThread.looper)

    /**
     * Where frames are copied out of the readers.
     *
     * Separate from both of the above: copying a frame is the one expensive
     * thing on any of these threads, and it must neither delay a state
     * callback nor be delayed by a control thread that is waiting for a frame
     * to arrive.
     */
    private val frameThread = HandlerThread("nuans-camera-frames").apply { start() }
    private val frameHandler = Handler(frameThread.looper)

    /**
     * The platform thread, which is the only one allowed to send on a platform
     * channel. See [emit].
     */
    private val mainHandler = Handler(Looper.getMainLooper())

    private val store = CaptureStore()

    /**
     * Guards the preview frames and [previewFrameCount], which the frame
     * thread writes and the control thread reads.
     */
    private val frameLock = java.lang.Object()

@Volatile
    private var selection: CapabilityProbe.Selection? = null
    @Volatile
    private var cameraDevice: CameraDevice? = null
    @Volatile
    private var session: CameraCaptureSession? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var metricsReader: ImageReader? = null
    private var rawReader: ImageReader? = null

    @Volatile
    private var previewConfig: PreviewConfig? = null
    private var latestPreview: YuvFrame? = null
    private var previousPreview: YuvFrame? = null

    /**
     * Frames seen since the preview started. The exposure solve waits on this
     * rather than on a fixed delay, so it reads a frame that was actually
     * exposed with the settings it just applied.
     */
    private var previewFrameCount = 0L
    private var lastMetricsAt = 0L
    @Volatile
    private var isLocked = false
    @Volatile
    private var lockedIso = 0
    @Volatile
    private var lockedExposureNanos = 0L
    @Volatile
    private var lockedFocusDistance: Float? = null
    private var lockedGains: FloatArray = UNITY_GAINS
    @Volatile
    private var observedAutoGains: FloatArray? = null
    @Volatile
    private var burst: BurstCollector? = null

    /** Set by the plugin so out-of-band failures and progress reach Dart. */
    var events: ShadeCameraFlutterApi? = null

    /**
     * Sends an event to Dart from the platform thread.
     *
     * Sending on a platform channel goes through
     * `FlutterJNI.dispatchPlatformMessage`, whose first act is to assert that
     * it is running on the main thread; an event raised on any of the threads
     * above would throw instead of reaching Dart. A reply to a host call does
     * not need this - that path takes a read lock rather than asserting a
     * thread - so only events are marshalled.
     */
    private fun emit(send: (ShadeCameraFlutterApi) -> Unit) {
        val api = events ?: return
        mainHandler.post { send(api) }
    }

    /**
     * Blocks the calling thread until more than [after] frames have been seen,
     * and returns the newest one.
     *
     * Waiting on the frame count rather than sleeping for a fixed period is
     * what makes the returned frame meaningful: it is one the camera produced
     * after the caller's request went in, not whatever happened to be left
     * over from before.
     */
    private fun awaitPreviewFrameAfter(after: Long, timeoutMillis: Long): YuvFrame {
        val deadlineNanos = System.nanoTime() + timeoutMillis * 1_000_000L
        synchronized(frameLock) {
            while (previewFrameCount <= after) {
                val remaining = (deadlineNanos - System.nanoTime()) / 1_000_000L
                if (remaining <= 0L) {
                    throw ShadeCameraFailure(
                        CameraErrorCode.PREVIEW_NOT_RUNNING,
                        "no preview frame arrived within $timeoutMillis ms",
                        recoverable = true,
                    )
                }
                frameLock.wait(remaining)
            }
            return latestPreview ?: throw ShadeCameraFailure(
                CameraErrorCode.PREVIEW_NOT_RUNNING,
                "the preview frame was released while it was being waited for",
                recoverable = true,
            )
        }
    }

    /**
     * Returns the preview texture, creating it on the platform thread.
     *
     * Registering a texture reaches `FlutterJNI.registerTexture`, whose first
     * instruction is `ensureRunningOnMainThread()`. Called from the control
     * thread it throws, and an exception escaping a HandlerThread ends the
     * process - the application simply vanishes. This is the same main-thread
     * rule that [emit] exists for; the texture registry is the other side of
     * it that was missed.
     *
     * Waiting here is safe: the platform thread posted this work and returned,
     * so it is free to answer.
     */
    private fun requireTextureEntry(): TextureRegistry.SurfaceTextureEntry {
        textureEntry?.let { return it }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return textureRegistry.createSurfaceTexture().also { textureEntry = it }
        }
        val latch = CountDownLatch(1)
        var created: TextureRegistry.SurfaceTextureEntry? = null
        var failure: Throwable? = null
        mainHandler.post {
            try {
                created = textureRegistry.createSurfaceTexture()
            } catch (error: Throwable) {
                failure = error
            } finally {
                latch.countDown()
            }
        }
        if (!latch.await(TEXTURE_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)) {
            throw ShadeCameraFailure(
                CameraErrorCode.CONFIGURATION_FAILED,
                "the platform thread did not create a preview texture within " +
                    "$TEXTURE_TIMEOUT_MILLIS ms",
            )
        }
        failure?.let {
            throw ShadeCameraFailure(
                CameraErrorCode.CONFIGURATION_FAILED,
                it.message ?: "the preview texture could not be created",
            )
        }
        val entry = created ?: throw ShadeCameraFailure(
            CameraErrorCode.CONFIGURATION_FAILED,
            "the platform returned no preview texture",
        )
        textureEntry = entry
        return entry
    }

    /**
     * Releases the preview texture on the platform thread.
     *
     * `unregisterTexture` asserts the main thread exactly as `registerTexture`
     * does, so tearing down from the control thread would crash on the way out
     * instead of on the way in. Not waited on: nothing afterwards depends on
     * it, and dispose is already answering its caller.
     */
    private fun releaseTextureEntry() {
        val entry = textureEntry ?: return
        textureEntry = null
        if (Looper.myLooper() == Looper.getMainLooper()) {
            entry.release()
        } else {
            mainHandler.post { entry.release() }
        }
    }

    /** Tells Dart which stage of a capture is running. */
    private fun reportProgress(
        captureId: String,
        stage: CaptureStage,
        captured: Long,
        requested: Long,
    ) {
        val progress = CaptureProgress(
            captureId = captureId,
            stage = stage,
            capturedFrames = captured,
            requestedFrames = requested,
        )
        emit { it.onCaptureProgress(progress) {} }
    }

    /** Frames seen so far, for pairing with [awaitPreviewFrameAfter]. */
    private fun framesSeen(): Long = synchronized(frameLock) { previewFrameCount }

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
        val latch = CountDownLatch(1)
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
                    emit {
                        it.onSessionInterrupted(
                            SessionInterruption.DEVICE_IN_USE_BY_ANOTHER_CLIENT,
                        ) {}
                    }
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
                        emit { it.onCameraError(raised.toEvent()) {} }
                    } else {
                        failure = raised
                    }
                    latch.countDown()
                }
            },
            callbackHandler,
        )
        if (!latch.await(OPEN_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)) {
            throw ShadeCameraFailure(
                CameraErrorCode.DEVICE_UNAVAILABLE,
                "camera $cameraId did not answer within $OPEN_TIMEOUT_MILLIS ms",
                recoverable = true,
            )
        }
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

    fun startPreview(
        config: PreviewConfig,
        callback: (Result<PreviewSession>) -> Unit,
    ) {
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
                synchronized(frameLock) {
                    previousPreview = null
                    latestPreview = null
                }

                if (session == null) {
                    configureSession(device, probed)
                }
                startRepeating(automatic = !isLocked)
                callback(
                    Result.success(
                        PreviewSession(
                            textureId = textureEntry?.id() ?: 0L,
                            previewWidth = probed.previewSize.width.toLong(),
                            previewHeight = probed.previewSize.height.toLong(),
                            // Only rear cameras are selected, so the frame is
                            // never mirrored and the sensor's own orientation
                            // is the whole of the correction.
                            displayRotationDegrees = probed.characteristics.get(
                                android.hardware.camera2.CameraCharacteristics
                                    .SENSOR_ORIENTATION,
                            )?.toLong() ?: 0L,
                        ),
                    ),
                )
            } catch (failure: ShadeCameraFailure) {
                callback(Result.failure(failure))
            } catch (error: Throwable) {
                // Anything else would escape a HandlerThread and end the
                // process: the application would vanish instead of saying what
                // went wrong. The one that did came from calling a Flutter API
                // off the platform thread; see requireTextureEntry.
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.CAPTURE_FAILED,
                            error.message ?: error.toString(),
                        ),
                    ),
                )
            }
        }
    }

    private fun configureSession(
        device: CameraDevice,
        probed: CapabilityProbe.Selection,
    ) {
        val entry = requireTextureEntry()
        entry.surfaceTexture().setDefaultBufferSize(
            probed.previewSize.width,
            probed.previewSize.height,
        )
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
                    val frame = YuvFrame.copyFrom(image)
                    val previous = synchronized(frameLock) {
                        val before = latestPreview
                        previousPreview = before
                        latestPreview = frame
                        previewFrameCount++
                        // Wakes a control thread waiting in
                        // awaitPreviewFrameAfter.
                        frameLock.notifyAll()
                        before
                    }
                    publishMetricsIfDue(frame, previous)
                } finally {
                    image.close()
                }
            }, frameHandler)
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
                }, frameHandler)
            }
            surfaces.add(rawReader!!.surface)
        }

        val latch = CountDownLatch(1)
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
                    emit {
                        it.onCameraError(
                            ShadeCameraFailure(
                                CameraErrorCode.INTERRUPTED,
                                "the capture session was closed by the system",
                                recoverable = true,
                            ).toEvent(),
                        ) {}
                    }
                }
            },
            callbackHandler,
        )
        if (!latch.await(CONFIGURE_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)) {
            throw ShadeCameraFailure(
                CameraErrorCode.CONFIGURATION_FAILED,
                "the camera did not configure a session within " +
                    "$CONFIGURE_TIMEOUT_MILLIS ms",
                recoverable = true,
            )
        }
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
            callbackHandler,
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
            synchronized(frameLock) {
                latestPreview = null
                previousPreview = null
            }
            callback(Result.success(Unit))
        }
    }

    /**
     * Frames are passed in rather than read back from the fields: the control
     * thread may clear those at any moment, and the frame this call describes
     * has to be the one that triggered it.
     */
    private fun publishMetricsIfDue(frame: YuvFrame, previous: YuvFrame?) {
        val config = previewConfig ?: return
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

        val metrics = PreviewMetrics(
            timestampMillis = now,
            format = selection?.capabilities?.defaultFormat
                ?: CaptureFormat.PROCESSED_LINEARISABLE,
            signalEncoding = SignalEncoding.DISPLAY_REFERRED_SRGB,
            toothSharpness = FrameQualityAnalyzer.laplacianVariance(frame, tooth),
            motionScore = FrameQualityAnalyzer
                .motionScore(frame, previous, tooth) ?: 0.0,
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
        )
        emit { it.onPreviewMetrics(metrics) {} }
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
                callbackHandler,
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
                    val seenBefore = framesSeen()
                    startRepeating(automatic = false)
                    // Two frames, not one: the first to arrive may already
                    // have been exposed when the new request went in, so only
                    // the second is certain to carry the new settings. A fixed
                    // sleep here measured the frame from the previous
                    // iteration and the solver converged on nothing.
                    val frame = awaitPreviewFrameAfter(
                        seenBefore + 1,
                        SETTLE_TIMEOUT_MILLIS,
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
            } catch (error: Throwable) {
                // Anything else would escape a HandlerThread and end the
                // process: the application would vanish instead of saying what
                // went wrong. The one that did came from calling a Flutter API
                // off the platform thread; see requireTextureEntry.
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.CAPTURE_FAILED,
                            error.message ?: error.toString(),
                        ),
                    ),
                )
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
                    // Back onto the control thread: the last frame arrives on
                    // the frame thread, and reducing a megapixel burst there
                    // would stall preview delivery for the whole reduction.
                    cameraHandler.post {
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
                }
                burst = collector

                reportProgress(
                    request.captureId,
                    CaptureStage.CAPTURING_BURST,
                    captured = 0,
                    requested = request.settings.burstFrameCount,
                )

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
                    callbackHandler,
                )
            } catch (failure: ShadeCameraFailure) {
                burst = null
                callback(Result.failure(failure))
            } catch (error: Throwable) {
                // Anything else would escape a HandlerThread and end the
                // process: the application would vanish instead of saying what
                // went wrong. The one that did came from calling a Flutter API
                // off the platform thread; see requireTextureEntry.
                burst = null
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.CAPTURE_FAILED,
                            error.message ?: error.toString(),
                        ),
                    ),
                )
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
        reportProgress(
            request.captureId,
            CaptureStage.SELECTING_FRAMES,
            captured = frames.size.toLong(),
            requested = request.settings.burstFrameCount,
        )

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

        reportProgress(
            request.captureId,
            CaptureStage.REDUCING_ROIS,
            captured = frames.size.toLong(),
            requested = request.settings.burstFrameCount,
        )

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
            } catch (error: Throwable) {
                // Anything else would escape a HandlerThread and end the
                // process: the application would vanish instead of saying what
                // went wrong. The one that did came from calling a Flutter API
                // off the platform thread; see requireTextureEntry.
                callback(
                    Result.failure(
                        ShadeCameraFailure(
                            CameraErrorCode.CAPTURE_FAILED,
                            error.message ?: error.toString(),
                        ),
                    ),
                )
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
            // Cleared before closing, not after: closing is asynchronous, and
            // the session's onClosed callback decides whether to report an
            // interruption by comparing against this field. Leaving it set
            // would report the deliberate teardown as a system interruption.
            val closingSession = session
            session = null
            closingSession?.close()
            val closingDevice = cameraDevice
            cameraDevice = null
            closingDevice?.close()
            metricsReader?.setOnImageAvailableListener(null, null)
            metricsReader?.close()
            metricsReader = null
            rawReader?.setOnImageAvailableListener(null, null)
            rawReader?.close()
            rawReader = null
            previewSurface?.release()
            previewSurface = null
            releaseTextureEntry()
            store.releaseAll()
            synchronized(frameLock) {
                latestPreview = null
                previousPreview = null
                // Anything still waiting for a frame is woken rather than
                // left to time out against a dead reader.
                frameLock.notifyAll()
            }
            isLocked = false
            callback(Result.success(Unit))
            frameThread.quitSafely()
            callbackThread.quitSafely()
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
 * How long to wait for `CameraDevice.StateCallback`.
 *
 * Camera2 gives no upper bound on opening a device, and a device held by
 * another application can leave the callback unanswered indefinitely. Five
 * seconds is far longer than any healthy open takes, so exceeding it means
 * something is wrong and the user is better told than left waiting.
 */
private const val OPEN_TIMEOUT_MILLIS = 5_000L

/** The same reasoning for `CameraCaptureSession.StateCallback`. */
private const val CONFIGURE_TIMEOUT_MILLIS = 5_000L

/**
 * How long to wait for the platform thread to register a preview texture.
 *
 * It is a handful of allocations once the thread is free, so a second is
 * already generous; exceeding it means the platform thread is wedged, which is
 * worth reporting rather than waiting out.
 */
private const val TEXTURE_TIMEOUT_MILLIS = 1_000L

/**
 * How long a settings change may take to show up in a preview frame.
 *
 * At the preview frame rate of 30 this is about forty frames: enough for the
 * request to travel through the pipeline on a slow device, short enough that a
 * stalled preview surfaces as an error rather than a hang.
 */
private const val SETTLE_TIMEOUT_MILLIS = 1_500L

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
