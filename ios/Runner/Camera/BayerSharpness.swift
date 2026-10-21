import Foundation

/// Focus measurement taken straight from a Bayer frame.
///
/// The preview path measures sharpness on the green channel of a processed
/// frame; the burst path has no processed frame to measure, so it works on the
/// green cells of the mosaic directly. Both are a four-neighbour Laplacian
/// variance, so a burst frame and a preview frame are at least measuring the
/// same quantity, even though their absolute scales differ and are never
/// compared with each other.
enum BayerSharpness {
    /// Variance of the Laplacian of the green superpixel channel over a region.
    ///
    /// Works on the superpixel grid rather than on raw pixels: neighbouring raw
    /// pixels carry different colours, so a Laplacian across them would measure
    /// the colour filter array, not the focus.
    static func greenLaplacianVariance(
        frame: BayerFrame,
        pattern: BayerPattern,
        levels: SensorLevels,
        roi: SuperpixelRectangle
    ) -> Double {
        guard roi.width > 2, roi.height > 2 else { return 0 }
        let offsets = pattern.offsets
        let g1 = offsets.green1
        let g2 = offsets.green2

        func green(gridX: Int, gridY: Int) -> Double {
            let pixelX = (roi.x + gridX) * 2
            let pixelY = (roi.y + gridY) * 2
            let first = frame.sample(
                x: pixelX + g1 % 2,
                y: pixelY + g1 / 2
            )
            let second = frame.sample(
                x: pixelX + g2 % 2,
                y: pixelY + g2 / 2
            )
            return 0.5 * (
                levels.normalise(first, cell: g1) + levels.normalise(second, cell: g2)
            )
        }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for gridY in 1..<(roi.height - 1) {
            for gridX in 1..<(roi.width - 1) {
                let laplacian = green(gridX: gridX, gridY: gridY - 1)
                    + green(gridX: gridX, gridY: gridY + 1)
                    + green(gridX: gridX - 1, gridY: gridY)
                    + green(gridX: gridX + 1, gridY: gridY)
                    - 4 * green(gridX: gridX, gridY: gridY)
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        let variance = sumOfSquares / count - mean * mean
        // Normalised values make the variance tiny, so it is scaled into a
        // range a human can read in a log without changing its meaning.
        return variance > 0 ? variance * 1_000_000 : 0
    }
}
