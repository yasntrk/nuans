import AVFoundation
import ImageIO

/// Sensor levels and colour metadata read out of a captured RAW photo.
///
/// Levels are read from the file's own DNG tags whenever possible. When they
/// are missing the reducer still works, but on a bit-depth guess rather than on
/// measured values, and `levels.isFromMetadata` is false so that Dart can lower
/// the confidence score instead of quietly trusting it.
struct RawPhotoMetadata {
    let levels: SensorLevels
    let colorMatrix1: [Double]?
    let forwardMatrix1: [Double]?
    let asShotNeutral: [Double]?
    let calibrationIlluminant1: Int?

    /// Default saturation level for a 14-bit Bayer readout, used only when the
    /// DNG carries no white level.
    static let fallbackWhiteLevel14Bit = 16383.0

    static func read(from photo: AVCapturePhoto) -> RawPhotoMetadata {
        guard
            let data = photo.fileDataRepresentation(),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let dng = properties[kCGImagePropertyDNGDictionary] as? [CFString: Any]
        else {
            return RawPhotoMetadata(
                levels: SensorLevels(
                    uniformBlack: 0,
                    white: fallbackWhiteLevel14Bit,
                    isFromMetadata: false
                ),
                colorMatrix1: nil,
                forwardMatrix1: nil,
                asShotNeutral: nil,
                calibrationIlluminant1: nil
            )
        }

        let white = doubles(dng[kCGImagePropertyDNGWhiteLevel])?.first
            ?? fallbackWhiteLevel14Bit
        let blackValues = doubles(dng[kCGImagePropertyDNGBlackLevel]) ?? [0]
        let levels: SensorLevels
        if blackValues.count >= 4 {
            levels = SensorLevels(
                black: (blackValues[0], blackValues[1], blackValues[2], blackValues[3]),
                white: white,
                isFromMetadata: true
            )
        } else {
            levels = SensorLevels(
                uniformBlack: blackValues.first ?? 0,
                white: white,
                isFromMetadata: true
            )
        }

        return RawPhotoMetadata(
            levels: levels,
            colorMatrix1: doubles(dng[kCGImagePropertyDNGColorMatrix1]),
            forwardMatrix1: doubles(dng[kCGImagePropertyDNGForwardMatrix1]),
            asShotNeutral: doubles(dng[kCGImagePropertyDNGAsShotNeutral]),
            calibrationIlluminant1: doubles(dng[kCGImagePropertyDNGCalibrationIlluminant1])?
                .first
                .map { Int($0) }
        )
    }

    /// The Pigeon form, or `nil` when the file carried no usable colour tags.
    ///
    /// Only sent when the device has no chart-fitted profile, because a
    /// manufacturer matrix is a single-sample average with no unit-to-unit
    /// variation in it: a fallback, not an equal.
    var bridged: DngColorMetadata? {
        guard let colorMatrix1, colorMatrix1.count == 9 else { return nil }
        return DngColorMetadata(
            colorMatrix1: FlutterStandardTypedData(
                float64: Data(bytes: colorMatrix1, count: colorMatrix1.count * 8)
            ),
            asShotNeutral: FlutterStandardTypedData(
                float64: Data(
                    bytes: asShotNeutral ?? [1, 1, 1],
                    count: (asShotNeutral ?? [1, 1, 1]).count * 8
                )
            ),
            blackLevel: levels.blackLevel(atCell: 0),
            whiteLevel: levels.white,
            forwardMatrix1: (forwardMatrix1?.count == 9)
                ? FlutterStandardTypedData(
                    float64: Data(bytes: forwardMatrix1!, count: 72)
                )
                : nil,
            calibrationIlluminant1: calibrationIlluminant1.map { Int64($0) }
        )
    }

    private static func doubles(_ value: Any?) -> [Double]? {
        if let numbers = value as? [NSNumber] {
            return numbers.map(\.doubleValue)
        }
        if let number = value as? NSNumber {
            return [number.doubleValue]
        }
        return nil
    }
}
