package com.nuans.app.camera

/**
 * A failure the native capture layer can report.
 *
 * Carries a machine code, never a user-facing sentence: the Dart layer maps
 * [code] onto an ARB key so the same failure reads correctly in Turkish and
 * English. [message] is for logs and bug reports only.
 */
class ShadeCameraFailure(
    val code: CameraErrorCode,
    override val message: String,
    val recoverable: Boolean = false,
    val captureId: String? = null,
) : Exception(message) {

    /** The structured form the Dart side receives through `onCameraError`. */
    fun toEvent(): CameraError = CameraError(
        code = code,
        recoverable = recoverable,
        nativeMessage = message,
        captureId = captureId,
    )

    /**
     * The form Pigeon sends across the channel.
     *
     * Pigeon's generated Kotlin error class is named `FlutterError`; aliasing
     * the construction here means a Pigeon upgrade is a one-line change rather
     * than a sweep through the plugin.
     */
    fun toBridged(): FlutterError = FlutterError(
        code = code.name,
        message = message,
        details = mapOf(
            "recoverable" to recoverable,
            "captureId" to (captureId ?: ""),
        ),
    )
}
