package com.nuans.app.camera

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.StreamConfigurationMap
import android.graphics.ImageFormat
import android.util.Size

/**
 * Picks the camera to measure with and decides what tier it can run at.
 *
 * This is the messiest part of the Android port and the honest reason the app
 * ships on iOS first. Android has no equivalent of
 * `builtInWideAngleCamera`: a device exposes a list of ids, some of them
 * logical cameras that switch physical lenses on their own, with no reliable
 * way to ask "which one is the main sensor?".
 *
 * The heuristic, in order:
 *
 * 1. only rear-facing cameras;
 * 2. prefer one that is not a logical multi-camera, because a logical camera
 *    can swap lenses mid-session and a measurement taken through a different
 *    lens than the profile was built for is not comparable;
 * 3. among those, the largest physical sensor area, which on every current
 *    device is the main wide module;
 * 4. ties go to the lowest id, which is the vendor convention for the main
 *    camera.
 *
 * The chosen id is stored in the device profile key, so if the heuristic picks
 * differently after a system update the profile simply no longer matches and
 * the user is asked to recalibrate, rather than silently measuring through an
 * uncalibrated lens.
 */
class CapabilityProbe(private val manager: CameraManager) {

    data class Selection(
        val cameraId: String,
        val characteristics: CameraCharacteristics,
        val capabilities: CameraCapabilities,
        val rawSize: Size?,
        val previewSize: Size,
        val pattern: BayerPattern?,
    )

    fun probe(): Selection {
        val candidates = manager.cameraIdList.mapNotNull { id ->
            val characteristics = manager.getCameraCharacteristics(id)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing != CameraCharacteristics.LENS_FACING_BACK) null
            else id to characteristics
        }
        if (candidates.isEmpty()) {
            throw ShadeCameraFailure(
                CameraErrorCode.DEVICE_UNAVAILABLE,
                "this device has no rear-facing camera",
            )
        }

        val chosen = candidates.sortedWith(
            compareBy(
                { if (isLogical(it.second)) 1 else 0 },
                { -sensorArea(it.second) },
                { it.first },
            ),
        ).first()

        val characteristics = chosen.second
        val map = characteristics.get(
            CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP,
        ) ?: throw ShadeCameraFailure(
            CameraErrorCode.CONFIGURATION_FAILED,
            "camera ${chosen.first} publishes no stream configuration map",
        )

        val available = characteristics.get(
            CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES,
        ) ?: IntArray(0)
        val hasManualSensor = available.contains(
            CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR,
        )
        val hasRaw = available.contains(
            CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_RAW,
        )
        val rawSize = largestRawSize(map)
        val pattern = BayerPattern.fromColorFilterArrangement(
            characteristics.get(
                CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT,
            ),
        )

        val awbOffSupported = characteristics
            .get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)
            ?.contains(android.hardware.camera2.CameraMetadata.CONTROL_AWB_MODE_OFF)
            ?: false
        val afOffSupported = characteristics
            .get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
            ?.contains(android.hardware.camera2.CameraMetadata.CONTROL_AF_MODE_OFF)
            ?: false

        val limitations = mutableListOf<String>()
        if (!hasManualSensor) limitations.add("noManualSensor")
        if (!hasRaw || rawSize == null || pattern == null) limitations.add("noRawSupport")
        if (!awbOffSupported) limitations.add("whiteBalanceNotLockable")
        if (!afOffSupported) limitations.add("focusNotLockable")
        if (isLogical(characteristics)) limitations.add("logicalMultiCamera")

        val isoRange = characteristics.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
        val exposureRange = characteristics.get(
            CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE,
        )
        val pixelArray = characteristics.get(
            CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE,
        )
        val focalLengths = characteristics.get(
            CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS,
        )

        // "Full mode" means the whole protocol is available. Anything less and
        // the measurement still happens, with a low-confidence badge, because a
        // repeatable relative reading is worth more to a technician than no
        // reading at all.
        val tier = if (limitations.isEmpty()) CaptureTier.FULL else CaptureTier.LIMITED

        val capabilities = CameraCapabilities(
            tier = tier,
            supportsManualSensor = hasManualSensor,
            supportsBayerRaw = hasRaw && rawSize != null && pattern != null,
            supportsWhiteBalanceLock = awbOffSupported,
            supportsFocusLock = afOffSupported,
            minIso = (isoRange?.lower ?: 0).toLong(),
            maxIso = (isoRange?.upper ?: 0).toLong(),
            minExposureSeconds = (exposureRange?.lower ?: 0L) / 1_000_000_000.0,
            maxExposureSeconds = (exposureRange?.upper ?: 0L) / 1_000_000_000.0,
            defaultFormat = if (hasRaw && rawSize != null && pattern != null) {
                CaptureFormat.BAYER_RAW
            } else {
                CaptureFormat.PROCESSED_LINEARISABLE
            },
            deviceModel = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
            lensId = chosen.first,
            sensorWidthPixels = (pixelArray?.width ?: 0).toLong(),
            sensorHeightPixels = (pixelArray?.height ?: 0).toLong(),
            limitationCodes = limitations,
            focalLengthMillimeters = focalLengths?.firstOrNull()?.toDouble(),
        )

        return Selection(
            cameraId = chosen.first,
            characteristics = characteristics,
            capabilities = capabilities,
            rawSize = rawSize,
            previewSize = previewSize(map),
            pattern = pattern,
        )
    }

    private fun isLogical(characteristics: CameraCharacteristics): Boolean =
        characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
            ?.contains(
                CameraCharacteristics
                    .REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA,
            ) ?: false

    private fun sensorArea(characteristics: CameraCharacteristics): Long {
        val size = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            ?: return 0
        return (size.width.toDouble() * size.height.toDouble() * 1000).toLong()
    }

    private fun largestRawSize(map: StreamConfigurationMap): Size? =
        map.getOutputSizes(ImageFormat.RAW_SENSOR)
            ?.maxByOrNull { it.width.toLong() * it.height.toLong() }

    /**
     * Preview size, capped at 1080p.
     *
     * The guaranteed stream combination this session needs - a preview surface,
     * a YUV metrics stream and a full-size RAW stream at once - is only
     * promised when the two non-raw streams are at "preview" size, which the
     * platform defines as at most 1920x1080.
     */
    private fun previewSize(map: StreamConfigurationMap): Size {
        val sizes = map.getOutputSizes(android.graphics.SurfaceTexture::class.java)
            ?: return Size(1280, 720)
        return sizes
            .filter { it.width <= 1920 && it.height <= 1080 }
            .maxByOrNull { it.width.toLong() * it.height.toLong() }
            ?: sizes.minByOrNull { it.width.toLong() * it.height.toLong() }
            ?: Size(1280, 720)
    }
}
