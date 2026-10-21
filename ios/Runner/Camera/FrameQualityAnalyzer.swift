import Foundation

/// Sharpness and motion measures.
///
/// These are measurements, not verdicts. The thresholds live in Dart, where
/// they are covered by unit tests and can be tuned per device without a native
/// release; native only ever reports numbers.
enum FrameQualityAnalyzer {
    /// Variance of a four-neighbour Laplacian over a region of a luma plane.
    ///
    /// The Laplacian responds to local contrast, so its variance collapses when
    /// the image is out of focus. The absolute value depends on the sensor, the
    /// lens and the subject, which is why the accept rule in Dart also compares
    /// each frame against the sharpest frame of the same burst.
    static func laplacianVariance(
        plane: UnsafePointer<UInt8>,
        rowStride: Int,
        pixelStride: Int,
        channelOffset: Int,
        region: (x: Int, y: Int, width: Int, height: Int)
    ) -> Double {
        guard region.width > 2, region.height > 2 else { return 0 }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for y in (region.y + 1)..<(region.y + region.height - 1) {
            let row = y * rowStride + channelOffset
            let above = (y - 1) * rowStride + channelOffset
            let below = (y + 1) * rowStride + channelOffset
            for x in (region.x + 1)..<(region.x + region.width - 1) {
                let column = x * pixelStride
                let laplacian = Double(plane[above + column])
                    + Double(plane[below + column])
                    + Double(plane[row + column - pixelStride])
                    + Double(plane[row + column + pixelStride])
                    - 4 * Double(plane[row + column])
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        let variance = sumOfSquares / count - mean * mean
        return variance > 0 ? variance : 0
    }

    /// Mean absolute difference between two luma planes, normalised by the mean
    /// level so that it does not change with exposure.
    ///
    /// Returns `nil` when there is no previous frame to compare against, which
    /// the caller reports as "not yet known" rather than as "no motion".
    static func motionScore(
        current: UnsafePointer<UInt8>,
        previous: UnsafePointer<UInt8>,
        rowStride: Int,
        pixelStride: Int,
        channelOffset: Int,
        region: (x: Int, y: Int, width: Int, height: Int),
        sampleStride: Int = 4
    ) -> Double? {
        guard region.width > 0, region.height > 0, sampleStride > 0 else {
            return nil
        }
        var difference = 0.0
        var level = 0.0
        var count = 0.0
        var y = region.y
        while y < region.y + region.height {
            let row = y * rowStride + channelOffset
            var x = region.x
            while x < region.x + region.width {
                let a = Double(current[row + x * pixelStride])
                let b = Double(previous[row + x * pixelStride])
                difference += abs(a - b)
                level += a
                count += 1
                x += sampleStride
            }
            y += sampleStride
        }
        guard count > 0, level > 0 else { return nil }
        return (difference / count) / (level / count)
    }

    /// Share of samples at or above `highlightLevel`, and at or below
    /// `shadowLevel`, over a region of a luma plane.
    static func clippingFractions(
        plane: UnsafePointer<UInt8>,
        rowStride: Int,
        pixelStride: Int,
        channelOffset: Int,
        region: (x: Int, y: Int, width: Int, height: Int),
        highlightLevel: UInt8,
        shadowLevel: UInt8,
        sampleStride: Int = 2
    ) -> (highlights: Double, shadows: Double) {
        guard region.width > 0, region.height > 0, sampleStride > 0 else {
            return (0, 0)
        }
        var highlights = 0.0
        var shadows = 0.0
        var count = 0.0
        var y = region.y
        while y < region.y + region.height {
            let row = y * rowStride + channelOffset
            var x = region.x
            while x < region.x + region.width {
                let value = plane[row + x * pixelStride]
                if value >= highlightLevel { highlights += 1 }
                if value <= shadowLevel { shadows += 1 }
                count += 1
                x += sampleStride
            }
            y += sampleStride
        }
        guard count > 0 else { return (0, 0) }
        return (highlights / count, shadows / count)
    }

    /// Mean of each of three interleaved channels over a region, normalised to
    /// `0 ... 1`, plus the spatial standard deviation of `referenceChannel`
    /// over its mean.
    ///
    /// The ratio is the uniformity measure of the grey card slot: a flat
    /// neutral surface has a small one, and an edge, a shadow or anything that
    /// is not the card has a large one.
    static func channelStatistics(
        plane: UnsafePointer<UInt8>,
        rowStride: Int,
        pixelStride: Int,
        channelOffsets: (red: Int, green: Int, blue: Int),
        referenceChannel: Int,
        region: (x: Int, y: Int, width: Int, height: Int),
        sampleStride: Int = 2
    ) -> (mean: [Double], uniformityRatio: Double) {
        guard region.width > 0, region.height > 0, sampleStride > 0 else {
            return (mean: [0, 0, 0], uniformityRatio: 0)
        }
        var sums = [0.0, 0.0, 0.0]
        var referenceSquares = 0.0
        var count = 0.0
        let offsets = [channelOffsets.red, channelOffsets.green, channelOffsets.blue]
        var y = region.y
        while y < region.y + region.height {
            let row = y * rowStride
            var x = region.x
            while x < region.x + region.width {
                let column = x * pixelStride
                for channel in 0..<3 {
                    sums[channel] += Double(plane[row + column + offsets[channel]])
                }
                let reference = Double(plane[row + column + offsets[referenceChannel]])
                referenceSquares += reference * reference
                count += 1
                x += sampleStride
            }
            y += sampleStride
        }
        guard count > 0 else { return (mean: [0, 0, 0], uniformityRatio: 0) }
        let mean = sums.map { $0 / count / 255 }
        let referenceMean = sums[referenceChannel] / count
        let variance = referenceSquares / count - referenceMean * referenceMean
        let ratio = referenceMean > 0 && variance > 0
            ? variance.squareRoot() / referenceMean
            : 0
        return (mean: mean, uniformityRatio: ratio)
    }
}
