import AVFoundation
import CoreVideo

/// Builds the live traffic-light measurements from one preview frame.
///
/// Everything here is a measurement; the thresholds that turn these numbers
/// into a green or red light live in Dart. Two consequences worth stating:
///
/// * the preview stream is a processed, display-referred frame, so the RGB
///   means leave here as `PreviewSignalEncoding.displayReferredSrgb` and Dart
///   linearises them for the live check only;
/// * the grey card verdict that the measurement relies on is computed again
///   from the captured burst, where the values really are linear.
final class PreviewMetricsComputer {
    /// 8-bit level at or above which a preview sample counts as blown.
    static let highlightLevel: UInt8 = 250

    /// 8-bit level at or below which it counts as crushed.
    static let shadowLevel: UInt8 = 4

    /// Channel offsets inside a BGRA pixel.
    private static let bgraOffsets = (red: 2, green: 1, blue: 0)

    /// Green is the sharpness and uniformity channel: it carries most of the
    /// luminance, so it is the strongest focus signal available without
    /// converting the whole frame.
    private static let greenChannel = 1

    private var previousFrame: CVPixelBuffer?

    func reset() {
        previousFrame = nil
    }

    /// Computes metrics for `pixelBuffer`, which must be BGRA.
    func metrics(
        from pixelBuffer: CVPixelBuffer,
        config: PreviewConfig,
        exposure: ExposureState,
        format: CaptureFormat,
        timestampMillis: Int64
    ) -> PreviewMetrics? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess
        else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let plane = base.assumingMemoryBound(to: UInt8.self)
        let rowStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelStride = 4

        let tooth = Self.region(config.toothRect, width: width, height: height)
        let card = Self.region(config.grayCardRect, width: width, height: height)

        let sharpness = FrameQualityAnalyzer.laplacianVariance(
            plane: plane,
            rowStride: rowStride,
            pixelStride: pixelStride,
            channelOffset: Self.bgraOffsets.green,
            region: tooth
        )
        let toothClipping = FrameQualityAnalyzer.clippingFractions(
            plane: plane,
            rowStride: rowStride,
            pixelStride: pixelStride,
            channelOffset: Self.bgraOffsets.green,
            region: tooth,
            highlightLevel: Self.highlightLevel,
            shadowLevel: Self.shadowLevel
        )
        let cardClipping = FrameQualityAnalyzer.clippingFractions(
            plane: plane,
            rowStride: rowStride,
            pixelStride: pixelStride,
            channelOffset: Self.bgraOffsets.green,
            region: card,
            highlightLevel: Self.highlightLevel,
            shadowLevel: Self.shadowLevel
        )
        let toothStats = FrameQualityAnalyzer.channelStatistics(
            plane: plane,
            rowStride: rowStride,
            pixelStride: pixelStride,
            channelOffsets: Self.bgraOffsets,
            referenceChannel: Self.greenChannel,
            region: tooth
        )
        let cardStats = FrameQualityAnalyzer.channelStatistics(
            plane: plane,
            rowStride: rowStride,
            pixelStride: pixelStride,
            channelOffsets: Self.bgraOffsets,
            referenceChannel: Self.greenChannel,
            region: card
        )

        var quadrantMeans: [Double] = []
        for quadrant in Self.quadrants(of: card) {
            let stats = FrameQualityAnalyzer.channelStatistics(
                plane: plane,
                rowStride: rowStride,
                pixelStride: pixelStride,
                channelOffsets: Self.bgraOffsets,
                referenceChannel: Self.greenChannel,
                region: quadrant
            )
            quadrantMeans.append(contentsOf: stats.mean)
        }

        var tabMean: [Double]?
        if let tabRect = config.shadeTabRect {
            let tab = Self.region(tabRect, width: width, height: height)
            tabMean = FrameQualityAnalyzer.channelStatistics(
                plane: plane,
                rowStride: rowStride,
                pixelStride: pixelStride,
                channelOffsets: Self.bgraOffsets,
                referenceChannel: Self.greenChannel,
                region: tab
            ).mean
        }

        var motion = 0.0
        if let previous = previousFrame,
           CVPixelBufferGetBytesPerRow(previous) == rowStride,
           CVPixelBufferGetHeight(previous) == height,
           CVPixelBufferLockBaseAddress(previous, .readOnly) == kCVReturnSuccess
        {
            if let previousBase = CVPixelBufferGetBaseAddress(previous) {
                motion = FrameQualityAnalyzer.motionScore(
                    current: plane,
                    previous: previousBase.assumingMemoryBound(to: UInt8.self),
                    rowStride: rowStride,
                    pixelStride: pixelStride,
                    channelOffset: Self.bgraOffsets.green,
                    region: tooth
                ) ?? 0
            }
            CVPixelBufferUnlockBaseAddress(previous, .readOnly)
        }
        previousFrame = pixelBuffer

        return PreviewMetrics(
            timestampMillis: timestampMillis,
            format: format,
            signalEncoding: .displayReferredSrgb,
            toothSharpness: sharpness,
            motionScore: motion,
            toothClippedFraction: toothClipping.highlights,
            toothShadowFraction: toothClipping.shadows,
            toothRgbMean: Self.typedData(toothStats.mean),
            grayCardClippedFraction: cardClipping.highlights,
            grayCardTextureRatio: cardStats.uniformityRatio,
            grayCardQuadrantRgb: Self.typedData(quadrantMeans),
            iso: exposure.iso,
            exposureSeconds: exposure.exposureSeconds,
            focusLocked: exposure.focusLocked,
            exposureLocked: exposure.exposureLocked,
            whiteBalanceLocked: exposure.whiteBalanceLocked,
            focusDistanceDiopters: exposure.focusDistanceDiopters,
            shadeTabRgbMean: tabMean.map(Self.typedData)
        )
    }

    /// The mean signal of the grey card slot, used by the exposure solver.
    func grayCardLuma(
        from pixelBuffer: CVPixelBuffer,
        rect: NormalizedRect
    ) -> (luma: Double, toothClipped: Double)? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess
        else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let plane = base.assumingMemoryBound(to: UInt8.self)
        let rowStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let region = Self.region(rect, width: width, height: height)
        let stats = FrameQualityAnalyzer.channelStatistics(
            plane: plane,
            rowStride: rowStride,
            pixelStride: 4,
            channelOffsets: Self.bgraOffsets,
            referenceChannel: Self.greenChannel,
            region: region
        )
        let clipping = FrameQualityAnalyzer.clippingFractions(
            plane: plane,
            rowStride: rowStride,
            pixelStride: 4,
            channelOffset: Self.bgraOffsets.green,
            region: region,
            highlightLevel: Self.highlightLevel,
            shadowLevel: Self.shadowLevel
        )
        return (luma: stats.mean[Self.greenChannel], toothClipped: clipping.highlights)
    }

    private static func region(
        _ rect: NormalizedRect,
        width: Int,
        height: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let x = max(0, min(Int(rect.left * Double(width)), width - 1))
        let y = max(0, min(Int(rect.top * Double(height)), height - 1))
        let w = max(1, min(Int(rect.width * Double(width)), width - x))
        let h = max(1, min(Int(rect.height * Double(height)), height - y))
        return (x: x, y: y, width: w, height: h)
    }

    private static func quadrants(
        of region: (x: Int, y: Int, width: Int, height: Int)
    ) -> [(x: Int, y: Int, width: Int, height: Int)] {
        let halfWidth = max(1, region.width / 2)
        let halfHeight = max(1, region.height / 2)
        return [
            (x: region.x, y: region.y, width: halfWidth, height: halfHeight),
            (
                x: region.x + halfWidth, y: region.y,
                width: max(1, region.width - halfWidth), height: halfHeight
            ),
            (
                x: region.x, y: region.y + halfHeight,
                width: halfWidth, height: max(1, region.height - halfHeight)
            ),
            (
                x: region.x + halfWidth, y: region.y + halfHeight,
                width: max(1, region.width - halfWidth),
                height: max(1, region.height - halfHeight)
            ),
        ]
    }

    static func typedData(_ values: [Double]) -> FlutterStandardTypedData {
        FlutterStandardTypedData(
            float64: Data(bytes: values, count: values.count * 8)
        )
    }
}
