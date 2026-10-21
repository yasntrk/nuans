import AVFoundation
import CoreVideo

/// One frame kept alive after a burst, so a region can be reduced again without
/// re-shooting.
final class RetainedFrame {
    let pixelBuffer: CVPixelBuffer
    let quality: FrameQuality

    init(pixelBuffer: CVPixelBuffer, quality: FrameQuality) {
        self.pixelBuffer = pixelBuffer
        self.quality = quality
    }
}

/// Everything a finished capture needs to keep in order to answer a later
/// `resampleRoi`.
final class RetainedCapture {
    let captureId: String
    let frames: [RetainedFrame]
    let pattern: BayerPattern
    let levels: SensorLevels
    let createdAt: Date

    init(
        captureId: String,
        frames: [RetainedFrame],
        pattern: BayerPattern,
        levels: SensorLevels,
        createdAt: Date = Date()
    ) {
        self.captureId = captureId
        self.frames = frames
        self.pattern = pattern
        self.levels = levels
        self.createdAt = createdAt
    }
}

/// Holds the accepted frames of recent captures.
///
/// Memory here is real: a 12 megapixel 16-bit Bayer frame is about 24 MB, and
/// three of them is 72 MB per capture. So the store is small, bounded, and
/// dropped eagerly: Dart owns the lifetime through `releaseCapture`, and the
/// bound plus the age limit exist only to survive a Dart side that crashed
/// before it could release.
final class CaptureStore {
    /// How many captures to keep. Two, so that a clinician can drag the regions
    /// of the previous measurement while the next one is already shot.
    static let capacity = 2

    /// Age after which a capture is dropped even without a release.
    static let maximumAge: TimeInterval = 600

    private var captures: [RetainedCapture] = []
    private let lock = NSLock()

    func store(_ capture: RetainedCapture) {
        lock.lock()
        defer { lock.unlock() }
        captures.removeAll { $0.captureId == capture.captureId }
        captures.append(capture)
        pruneLocked()
    }

    func capture(withId id: String) -> RetainedCapture? {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        return captures.first { $0.captureId == id }
    }

    func release(id: String) {
        lock.lock()
        defer { lock.unlock() }
        captures.removeAll { $0.captureId == id }
    }

    func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        captures.removeAll()
    }

    private func pruneLocked() {
        let now = Date()
        captures.removeAll { now.timeIntervalSince($0.createdAt) > Self.maximumAge }
        if captures.count > Self.capacity {
            captures.removeFirst(captures.count - Self.capacity)
        }
    }
}

/// Runs a closure with a pixel buffer locked for reading.
///
/// Every read of raw pixels goes through here so that no path can forget to
/// unlock, which would leak the buffer and eventually stall the capture queue.
func withLockedBayerFrame<T>(
    _ pixelBuffer: CVPixelBuffer,
    _ body: (BayerFrame) throws -> T
) throws -> T {
    guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess
    else {
        throw ShadeCameraFailure(.captureFailed, "could not lock the raw buffer")
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw ShadeCameraFailure(.captureFailed, "raw buffer has no base address")
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let frame = BayerFrame(
        samples: base.assumingMemoryBound(to: UInt16.self),
        rowStride: bytesPerRow / 2,
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer)
    )
    return try body(frame)
}
