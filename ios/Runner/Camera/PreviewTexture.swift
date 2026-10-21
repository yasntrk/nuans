import Flutter
import CoreVideo

/// Publishes preview frames to Flutter as a texture.
///
/// The capture screen draws this texture rather than an `AVCaptureVideoPreviewLayer`
/// in a platform view, because the overlay is a Flutter `CustomPainter` and
/// keeping both in the same render tree is what keeps the region outlines
/// pinned to the image while the user drags them.
final class PreviewTexture: NSObject, FlutterTexture {
    private var latest: CVPixelBuffer?
    private let lock = NSLock()
    private weak var registry: FlutterTextureRegistry?
    private(set) var textureId: Int64 = 0

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
        textureId = registry.register(self)
    }

    func present(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latest = pixelBuffer
        lock.unlock()
        registry?.textureFrameAvailable(textureId)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = latest else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    func unregister() {
        registry?.unregisterTexture(textureId)
        lock.lock()
        latest = nil
        lock.unlock()
    }
}
