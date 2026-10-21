import Flutter
import UIKit

/// The Pigeon host API implementation.
///
/// Deliberately thin: it translates Pigeon types into the native value types,
/// forwards to the session controller, and translates failures back into the
/// machine codes the Dart layer maps onto ARB keys. No camera logic and no
/// colour logic lives here, so the parts that are worth testing are reachable
/// without a `FlutterPluginRegistrar`.
final class ShadeCameraPlugin: NSObject, ShadeCameraHostApi {
    private let controller: CaptureSessionController

    /// Registers the plugin and wires both directions of the channel.
    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = ShadeCameraPlugin(textures: registrar.textures())
        ShadeCameraHostApiSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: plugin
        )
        plugin.controller.events = ShadeCameraFlutterApi(
            binaryMessenger: registrar.messenger()
        )
    }

    init(textures: FlutterTextureRegistry) {
        controller = CaptureSessionController(textureRegistry: textures)
        super.init()
    }

    // MARK: - ShadeCameraHostApi

    func initialize(
        completion: @escaping (Result<CameraCapabilities, Error>) -> Void
    ) {
        controller.initialize(completion: bridge(completion))
    }

    func startPreview(
        config: PreviewConfig,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        controller.startPreview(config: config, completion: bridge(completion))
    }

    func updatePreviewRois(
        config: PreviewConfig,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        controller.updatePreviewRois(config: config, completion: bridge(completion))
    }

    func stopPreview(completion: @escaping (Result<Void, Error>) -> Void) {
        controller.stopPreview(completion: bridge(completion))
    }

    func focusAndLockAt(
        x: Double,
        y: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        controller.focusAndLockAt(x: x, y: y, completion: bridge(completion))
    }

    func lockCaptureParameters(
        settings: CaptureSettings,
        completion: @escaping (Result<ExposureState, Error>) -> Void
    ) {
        controller.lockCaptureParameters(
            settings: settings,
            completion: bridge(completion)
        )
    }

    func unlockCaptureParameters(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        controller.unlockCaptureParameters(completion: bridge(completion))
    }

    func capture(
        request: CaptureRequest,
        completion: @escaping (Result<CaptureResult, Error>) -> Void
    ) {
        controller.capture(request: request, completion: bridge(completion))
    }

    func resampleRoi(
        captureId: String,
        roi: RoiRequest,
        sampling: SamplingSettings,
        completion: @escaping (Result<RoiSample, Error>) -> Void
    ) {
        controller.resampleRoi(
            captureId: captureId,
            roi: roi,
            sampling: sampling,
            completion: bridge(completion)
        )
    }

    func releaseCapture(
        captureId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        controller.releaseCapture(id: captureId, completion: bridge(completion))
    }

    func dispose(completion: @escaping (Result<Void, Error>) -> Void) {
        controller.dispose(completion: bridge(completion))
    }

    // MARK: - Error translation

    /// Wraps a completion so that every `ShadeCameraFailure` reaches Dart as a
    /// platform error carrying its machine code.
    ///
    /// An unexpected error type is reported as `captureFailed` rather than
    /// swallowed: a measurement that silently did not happen is worse than one
    /// that says it failed for an unclear reason.
    private func bridge<T>(
        _ completion: @escaping (Result<T, Error>) -> Void
    ) -> (Result<T, Error>) -> Void {
        { result in
            switch result {
            case let .success(value):
                DispatchQueue.main.async { completion(.success(value)) }
            case let .failure(error):
                let failure = error as? ShadeCameraFailure
                    ?? ShadeCameraFailure(
                        .captureFailed,
                        error.localizedDescription
                    )
                DispatchQueue.main.async {
                    completion(.failure(failure.bridged))
                }
            }
        }
    }
}
