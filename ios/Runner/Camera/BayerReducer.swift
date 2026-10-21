import Foundation

/// What the reducer hands back for one region of interest.
struct SuperpixelReduction {
    /// Interleaved R, G, B triples in linear camera space, `0 ... 1`.
    let samples: [Double]

    let sampleCount: Int
    let totalSuperpixels: Int
    let clippedSuperpixels: Int
    let decimationStride: Int

    /// Exact mean over every non-clipped superpixel, not over the returned
    /// sample. Lets Dart check that decimation introduced no bias.
    let channelMean: [Double]

    /// Exact population standard deviation over every non-clipped superpixel.
    let channelStdDev: [Double]

    let widthInSuperpixels: Int
    let heightInSuperpixels: Int
}

/// Turns raw Bayer frames into the decimated linear sample set that crosses the
/// platform boundary.
///
/// What this does, and nothing more (see ADR-0001):
///
/// 1. subtract the per-cell black level and normalise by the white level;
/// 2. form 2x2 superpixels as `R`, `mean(G1, G2)`, `B`;
/// 3. drop any superpixel whose *raw* samples clip in any accepted frame;
/// 4. return a lattice-decimated subset, plus exact statistics over all of it.
///
/// No demosaicing, no white balance, no colour matrix, no gamma. Demosaicing is
/// an interpolation guess; a superpixel is three channels genuinely measured at
/// the same place. The cost is half the spatial resolution, which does not
/// matter to a region average.
enum BayerReducer {
    /// Lattice stride for a region, derived from geometry alone.
    ///
    /// Geometry alone is the point: deriving it from the surviving superpixel
    /// count would let sensor noise move the lattice between frames of the same
    /// burst, and the per-position average across frames would then be taken
    /// over different positions.
    static func stride(forTotal total: Int, maxSamples: Int) -> Int {
        guard total > maxSamples, maxSamples > 0 else { return 1 }
        let ratio = Double(total) / Double(maxSamples)
        return max(1, Int(ratio.squareRoot().rounded(.up)))
    }

    static func reduce(
        frames: [BayerFrame],
        pattern: BayerPattern,
        levels: SensorLevels,
        roi: SuperpixelRectangle,
        maxSamples: Int,
        clippingThreshold: Double
    ) throws -> SuperpixelReduction {
        guard !frames.isEmpty else {
            throw ShadeCameraFailure(.captureFailed, "no accepted frames to reduce")
        }
        guard maxSamples > 0 else {
            throw ShadeCameraFailure(
                .configurationFailed,
                "maxSamplesPerRoi must be positive"
            )
        }
        let offsets = pattern.offsets
        let cells = [offsets.red, offsets.green1, offsets.green2, offsets.blue]
        let clipLevels = cells.map {
            levels.clippingLevel(atCell: $0, threshold: clippingThreshold)
        }

        let total = roi.count
        let latticeStride = stride(forTotal: total, maxSamples: maxSamples)
        let frameScale = 1.0 / Double(frames.count)

        var samples: [Double] = []
        samples.reserveCapacity(min(total, maxSamples) * 3)

        var sum = [0.0, 0.0, 0.0]
        var sumOfSquares = [0.0, 0.0, 0.0]
        var accepted = 0
        var clipped = 0

        for gridY in 0..<roi.height {
            let onLatticeRow = gridY % latticeStride == 0
            for gridX in 0..<roi.width {
                let pixelX = (roi.x + gridX) * 2
                let pixelY = (roi.y + gridY) * 2

                var red = 0.0
                var green = 0.0
                var blue = 0.0
                var isClipped = false

                for frame in frames {
                    let raw = (
                        frame.sample(x: pixelX + cells[0] % 2, y: pixelY + cells[0] / 2),
                        frame.sample(x: pixelX + cells[1] % 2, y: pixelY + cells[1] / 2),
                        frame.sample(x: pixelX + cells[2] % 2, y: pixelY + cells[2] / 2),
                        frame.sample(x: pixelX + cells[3] % 2, y: pixelY + cells[3] / 2)
                    )
                    // Clipping is tested on the raw samples, before the greens
                    // are averaged: averaging first hides a single clipped
                    // green behind its healthy twin.
                    if Double(raw.0) > clipLevels[0]
                        || Double(raw.1) > clipLevels[1]
                        || Double(raw.2) > clipLevels[2]
                        || Double(raw.3) > clipLevels[3]
                    {
                        isClipped = true
                        break
                    }
                    red += levels.normalise(raw.0, cell: cells[0])
                    green += 0.5 * (
                        levels.normalise(raw.1, cell: cells[1])
                            + levels.normalise(raw.2, cell: cells[2])
                    )
                    blue += levels.normalise(raw.3, cell: cells[3])
                }

                if isClipped {
                    clipped += 1
                    continue
                }

                red *= frameScale
                green *= frameScale
                blue *= frameScale

                accepted += 1
                sum[0] += red
                sum[1] += green
                sum[2] += blue
                sumOfSquares[0] += red * red
                sumOfSquares[1] += green * green
                sumOfSquares[2] += blue * blue

                if onLatticeRow && gridX % latticeStride == 0 {
                    samples.append(red)
                    samples.append(green)
                    samples.append(blue)
                }
            }
        }

        var mean = [0.0, 0.0, 0.0]
        var stdDev = [0.0, 0.0, 0.0]
        if accepted > 0 {
            let n = Double(accepted)
            for channel in 0..<3 {
                mean[channel] = sum[channel] / n
                let variance = sumOfSquares[channel] / n
                    - mean[channel] * mean[channel]
                stdDev[channel] = variance > 0 ? variance.squareRoot() : 0
            }
        }

        return SuperpixelReduction(
            samples: samples,
            sampleCount: samples.count / 3,
            totalSuperpixels: total,
            clippedSuperpixels: clipped,
            decimationStride: latticeStride,
            channelMean: mean,
            channelStdDev: stdDev,
            widthInSuperpixels: roi.width,
            heightInSuperpixels: roi.height
        )
    }
}
