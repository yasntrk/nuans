import CoreVideo
import Foundation

/// Which colour each cell of a 2x2 Bayer block carries.
///
/// Offsets are indices into the block, laid out as `y * 2 + x`, so cell 0 is
/// top-left, 1 top-right, 2 bottom-left and 3 bottom-right.
enum BayerPattern {
    case rggb
    case bggr
    case grbg
    case gbrg

    init?(pixelFormat: OSType) {
        switch pixelFormat {
        case kCVPixelFormatType_14Bayer_RGGB: self = .rggb
        case kCVPixelFormatType_14Bayer_BGGR: self = .bggr
        case kCVPixelFormatType_14Bayer_GRBG: self = .grbg
        case kCVPixelFormatType_14Bayer_GBRG: self = .gbrg
        default: return nil
        }
    }

    /// Cell indices of the four samples of one superpixel.
    var offsets: (red: Int, green1: Int, green2: Int, blue: Int) {
        switch self {
        case .rggb: return (red: 0, green1: 1, green2: 2, blue: 3)
        case .bggr: return (red: 3, green1: 1, green2: 2, blue: 0)
        case .grbg: return (red: 1, green1: 0, green2: 3, blue: 2)
        case .gbrg: return (red: 2, green1: 0, green2: 3, blue: 1)
        }
    }
}

/// Black and white levels of one sensor readout.
///
/// Black level is per cell of the Bayer block, because sensors do not share one
/// pedestal across channels and DNG publishes it per channel. Using a single
/// averaged value would tint the shadows, which is exactly where the shadow
/// rejection threshold lives.
struct SensorLevels {
    /// Per-cell black levels, indexed as `y * 2 + x`.
    let black: (Double, Double, Double, Double)

    /// Saturation level, the same for every cell.
    let white: Double

    /// Whether these came from the file's own metadata rather than a fallback.
    let isFromMetadata: Bool

    init(black: (Double, Double, Double, Double), white: Double, isFromMetadata: Bool) {
        self.black = black
        self.white = white
        self.isFromMetadata = isFromMetadata
    }

    /// A uniform pedestal, used when metadata carries a single black level.
    init(uniformBlack: Double, white: Double, isFromMetadata: Bool) {
        self.init(
            black: (uniformBlack, uniformBlack, uniformBlack, uniformBlack),
            white: white,
            isFromMetadata: isFromMetadata
        )
    }

    func blackLevel(atCell cell: Int) -> Double {
        switch cell {
        case 0: return black.0
        case 1: return black.1
        case 2: return black.2
        default: return black.3
        }
    }

    /// Normalises one raw sample to `0 ... 1`.
    func normalise(_ raw: UInt16, cell: Int) -> Double {
        let pedestal = blackLevel(atCell: cell)
        let range = white - pedestal
        guard range > 0 else { return 0 }
        let value = (Double(raw) - pedestal) / range
        return value < 0 ? 0 : (value > 1 ? 1 : value)
    }

    /// The raw value at which a cell counts as clipped.
    func clippingLevel(atCell cell: Int, threshold: Double) -> Double {
        let pedestal = blackLevel(atCell: cell)
        return pedestal + threshold * (white - pedestal)
    }
}

/// A rectangle in sensor-normalised coordinates, `0 ... 1`, mirroring the
/// Pigeon type but free of it so the pixel code stays testable on its own.
struct NormalisedRectangle {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    init(_ rect: NormalizedRect) {
        self.init(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height
        )
    }
}

/// A rectangle in superpixel coordinates: whole 2x2 Bayer blocks.
struct SuperpixelRectangle {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var count: Int { width * height }

    /// Maps a normalised rectangle onto the superpixel grid of a frame.
    ///
    /// Superpixel `i` always starts at pixel `2 * i`, so every block stays
    /// aligned to the colour filter array by construction; cropping can never
    /// shift the pattern.
    static func from(
        _ rect: NormalisedRectangle,
        frameWidth: Int,
        frameHeight: Int
    ) throws -> SuperpixelRectangle {
        let gridWidth = frameWidth / 2
        let gridHeight = frameHeight / 2
        guard gridWidth > 0, gridHeight > 0 else {
            throw ShadeCameraFailure(
                .captureFailed,
                "frame is too small to hold a single Bayer block"
            )
        }
        let x = Int((rect.left * Double(gridWidth)).rounded(.down))
        let y = Int((rect.top * Double(gridHeight)).rounded(.down))
        let width = Int((rect.width * Double(gridWidth)).rounded(.down))
        let height = Int((rect.height * Double(gridHeight)).rounded(.down))
        let clampedX = max(0, min(x, gridWidth - 1))
        let clampedY = max(0, min(y, gridHeight - 1))
        let clampedWidth = max(1, min(width, gridWidth - clampedX))
        let clampedHeight = max(1, min(height, gridHeight - clampedY))
        guard
            rect.width > 0, rect.height > 0,
            rect.left >= 0, rect.top >= 0,
            rect.left + rect.width <= 1.000001,
            rect.top + rect.height <= 1.000001
        else {
            throw ShadeCameraFailure(
                .roiOutOfBounds,
                "normalised rectangle must lie inside the unit square"
            )
        }
        return SuperpixelRectangle(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

/// A locked planar 16-bit Bayer frame.
///
/// Deliberately a plain value over a raw pointer: the reducer can then be
/// exercised from a unit test with a synthetic buffer, with no capture session
/// and no device.
struct BayerFrame {
    let samples: UnsafePointer<UInt16>

    /// Row stride in `UInt16` units, not in bytes.
    let rowStride: Int
    let width: Int
    let height: Int

    func sample(x: Int, y: Int) -> UInt16 {
        samples[y * rowStride + x]
    }
}
