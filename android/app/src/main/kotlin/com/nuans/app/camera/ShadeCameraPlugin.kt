package com.nuans.app.camera

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/**
 * The Pigeon host API implementation.
 *
 * Deliberately thin: it forwards to the session controller and translates
 * failures into the machine codes the Dart layer maps onto ARB keys. No camera
 * logic and no colour logic lives here, which is what keeps the parts worth
 * testing reachable without a `FlutterPlugin` binding.
 */
class ShadeCameraPlugin :
    FlutterPlugin,
    ActivityAware,
    ShadeCameraHostApi,
    PluginRegistry.RequestPermissionsResultListener {

    private var controller: Camera2SessionController? = null
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    /**
     * The caller waiting for the user's answer to the permission dialog.
     *
     * Held rather than queued: the dialog is modal, so there can only ever be
     * one outstanding request, and a second [initialize] arriving while it is
     * up is a programming error on the Dart side rather than something to
     * serialise.
     */
    private var pendingPermission: ((Boolean) -> Unit)? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
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
        appContext = null
        ShadeCameraHostApi.setUp(binding.binaryMessenger, null)
    }

    // region ActivityAware
    //
    // An Activity is needed for one thing only: Android can ask the user for
    // the camera permission from nowhere else. The camera itself runs off the
    // application context, so losing the Activity on a configuration change
    // does not interrupt a capture.

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        // Nobody can answer the dialog any more, so release the waiter rather
        // than leaving the Dart side without a reply.
        pendingPermission?.also { pendingPermission = null }?.invoke(false)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val waiting = pendingPermission ?: return true
        pendingPermission = null
        waiting(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    // endregion

    /**
     * Runs [onResult] once the camera permission is known to be granted or
     * refused, asking the user if it has not been decided yet.
     *
     * Part of [initialize] rather than a method of its own on the host API, so
     * the Dart side keeps one call that means "give me a camera" and each
     * platform asks in its own way.
     */
    private fun ensureCameraPermission(onResult: (Boolean) -> Unit) {
        val context = appContext
        if (context == null) {
            onResult(false)
            return
        }
        if (
            context.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            onResult(true)
            return
        }
        val activity: Activity? = activityBinding?.activity
        if (activity == null || pendingPermission != null) {
            onResult(false)
            return
        }
        pendingPermission = onResult
        activity.requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
    }

    // region ShadeCameraHostApi

    override fun initialize(callback: (Result<CameraCapabilities>) -> Unit) =
        withController(callback) { active ->
            ensureCameraPermission { granted ->
                if (granted) {
                    active.initialize(bridge(callback))
                } else {
                    callback(
                        Result.failure(
                            ShadeCameraFailure(
                                CameraErrorCode.PERMISSION_DENIED,
                                "the camera permission was not granted",
                                recoverable = true,
                            ).toBridged(),
                        ),
                    )
                }
            }
        }

    override fun startPreview(
        config: PreviewConfig,
        callback: (Result<PreviewSession>) -> Unit,
    ) = withController(callback) { it.startPreview(config, bridge(callback)) }

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

/**
 * Request code for the camera permission dialog.
 *
 * Any value works as long as it is unique within the Activity; this one is
 * chosen to be recognisable in a log line.
 */
private const val CAMERA_PERMISSION_REQUEST = 4201
