import Foundation

/// A failure the native capture layer can report.
///
/// Carries a machine code, never a user-facing sentence: the Dart layer maps
/// `code` onto an ARB key so the same failure reads correctly in Turkish and
/// English. `message` is for logs and bug reports only.
struct ShadeCameraFailure: Error {
    let code: CameraErrorCode
    let message: String
    let recoverable: Bool
    let captureId: String?

    init(
        _ code: CameraErrorCode,
        _ message: String,
        recoverable: Bool = false,
        captureId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
        self.captureId = captureId
    }
}

/// Pigeon's generated error type is named `PigeonError` from version 22 and
/// `FlutterError` before it. Aliasing it in exactly one place means a Pigeon
/// upgrade is a one-line change here instead of a sweep through the plugin.
typealias ShadeCameraBridgeError = PigeonError

extension ShadeCameraFailure {
    /// The form Pigeon sends across the channel.
    var bridged: ShadeCameraBridgeError {
        ShadeCameraBridgeError(
            code: String(describing: code),
            message: message,
            details: [
                "recoverable": recoverable,
                "captureId": captureId ?? "",
            ]
        )
    }

    /// The structured form the Dart side receives through `onCameraError`.
    var event: CameraError {
        CameraError(
            code: code,
            recoverable: recoverable,
            nativeMessage: message,
            captureId: captureId
        )
    }
}
