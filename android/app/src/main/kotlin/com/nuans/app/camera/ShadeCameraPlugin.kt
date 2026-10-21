package com.nuans.app.camera

import android.content.Context
import android.hardware.camera2.CameraManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry

/**
 * The Pigeon host API implementation.
 *
 * Deliberately thin: it forwards to the session controller and translates
 * failures into the machine codes the Dart layer maps onto ARB keys. No camera
 * logic and no colour logic lives here, which is what keeps the parts worth
 * testing reachable without a `FlutterPlugin` binding.
 */
class ShadeCameraPlugin : FlutterPlugin, ShadeCameraHostApi {

    private var controller: Camera2SessionController? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val manager = binding.applicationContext
            .getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val created = Camera2SessionController(
            manager = manager,
            textureRegistry = binding.textureRegistry as TextureRegistry,
        )
        created.events = ShadeCameraFlutterApi(binding.binaryMessenger)
        controller = created
        ShadeCameraHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        controller?.dispose {}
        controller = null
        ShadeCameraHostApi.setUp(binding.binaryMessenger, null)
    }

    // region ShadeCameraHostApi

    override fun initialize(callback: (Result<CameraCapabilities>) -> Unit) =
        withController(callback) { it.initialize(bridge(callback)) }

    override fun startPreview(config: PreviewConfig, callback: (Result<Long>) -> Unit) =
        withController(callback) { it.startPreview(config, bridge(callback)) }

    override fun updatePreviewRois(
        config: PreviewConfig,
        callback: (Result<Unit>) -> Unit,
    ) = withController(callback) { it.updatePreviewRois(config, bridge(callback)) }

    override fun stopPreview(callback: (Result<Unit>) -> Unit) =
        withController(callback) { it.stopPreview(bridge(callback)) }

    override fun focusAndLockAt(x: Double, y: Double, callback: (Result<Unit>) -> Unit) =
        withController(callback) { it.focusAndLockAt(x, y, bridge(callback)) }

    override fun lockCaptureParameters(
        settings: CaptureSettings,
        callback: (Result<ExposureState>) -> Unit,
    ) = withController(callback) { it.lockCaptureParameters(settings, bridge(callback)) }

    override fun unlockCaptureParameters(callback: (Result<Unit>) -> Unit) =
        withController(callback) { it.unlockCaptureParameters(bridge(callback)) }

    override fun capture(
        request: CaptureRequest,
        callback: (Result<CaptureResult>) -> Unit,
    ) = withController(callback) { it.capture(request, bridge(callback)) }

    override fun resampleRoi(
        captureId: String,
        roi: RoiRequest,
        sampling: SamplingSettings,
        callback: (Result<RoiSample>) -> Unit,
    ) = withController(callback) {
        it.resampleRoi(captureId, roi, sampling, bridge(callback))
    }

    override fun releaseCapture(captureId: String, callback: (Result<Unit>) -> Unit) =
        withController(callback) { it.releaseCapture(captureId, bridge(callback)) }

    override fun dispose(callback: (Result<Unit>) -> Unit) =
        withController(callback) { it.dispose(bridge(callback)) }

    // endregion

    private inline fun <T> withController(
        callback: (Result<T>) -> Unit,
        body: (Camera2SessionController) -> Unit,
    ) {
        val active = controller
        if (active == null) {
            callback(
                Result.failure(
                    ShadeCameraFailure(
                        CameraErrorCode.CONFIGURATION_FAILED,
                        "the camera plugin is not attached to an engine",
                    ).toBridged(),
                ),
            )
            return
        }
        body(active)
    }

    /**
     * Wraps a callback so every [ShadeCameraFailure] reaches Dart as a platform
     * error carrying its machine code.
     *
     * An unexpected exception is reported as `CAPTURE_FAILED` rather than
     * swallowed: a measurement that silently did not happen is worse than one
     * that says it failed for an unclear reason.
     */
    private fun <T> bridge(callback: (Result<T>) -> Unit): (Result<T>) -> Unit = { result ->
        result.fold(
            onSuccess = { callback(Result.success(it)) },
            onFailure = { error ->
                val failure = error as? ShadeCameraFailure
                    ?: ShadeCameraFailure(
                        CameraErrorCode.CAPTURE_FAILED,
                        error.message ?: "the capture layer failed",
                    )
                callback(Result.failure(failure.toBridged()))
            },
        )
    }
}
