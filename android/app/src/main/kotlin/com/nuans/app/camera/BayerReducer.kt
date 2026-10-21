package com.nuans.app.camera

import kotlin.math.sqrt

/** What the reducer hands back for one region of interest. */
data class SuperpixelReduction(
    val samples: DoubleArray,
    val sampleCount: Int,
    val totalSuperpixels: Int,
    val clippedSuperpixels: Int,
    val decimationStride: Int,
    val channelMean: DoubleArray,
    val channelStdDev: DoubleArray,
    val widthInSuperpixels: Int,
    val heightInSuperpixels: Int,
) {
    override fun equals(other: Any?): Boolean =
        other is SuperpixelReduction &&
            samples.contentEquals(other.samples) &&
            sampleCount == other.sampleCount &&
            totalSuperpixels == other.totalSuperpixels &&
            clippedSuperpixels == other.clippedSuperpixels &&
            decimationStride == other.decimationStride

    override fun hashCode(): Int =
        31 * (31 * samples.contentHashCode() + sampleCount) + clippedSuperpixels
}

/**
 * Turns raw Bayer frames into the decimated sample set that crosses the
 * platform boundary.
 *
 * Line for line the same algorithm as `BayerReducer.swift`, and that is a
 * requirement rather than a coincidence: a device profile is a statement about
 * the pipeline that produced the numbers, so if the two platforms reduced
 * differently the same chart shot would fit two different matrices.
 *
 * 1. subtract the per-cell black level and normalise by the white level;
 * 2. form 2x2 superpixels as `R`, `mean(G1, G2)`, `B`;
 * 3. drop any superpixel whose *raw* samples clip in any accepted frame;
 * 4. return a lattice-decimated subset, plus exact statistics over all of it.
 *
 * No demosaicing, no white balance, no colour matrix, no gamma. See ADR-0001.
 */
object BayerReducer {

    fun reduce(
        frames: List<BayerFrame>,
        pattern: BayerPattern,
        levels: SensorLevels,
        roi: SuperpixelRectangle,
        maxSamples: Int,
        clippingThreshold: Double,
    ): SuperpixelReduction {
        if (frames.isEmpty()) {
            throw ShadeCameraFailure(
                CameraErrorCode.CAPTURE_FAILED,
                "no accepted frames to reduce",
            )
        }
        if (maxSamples <= 0) {
            throw ShadeCameraFailure(
                CameraErrorCode.CONFIGURATION_FAILED,
                "maxSamplesPerRoi must be positive",
            )
        }
        val cells = pattern.cells
        val clipLevels = DoubleArray(4) { levels.clippingLevel(cells[it], clippingThreshold) }

        val total = roi.count
        val stride = latticeStride(total, maxSamples)
        val frameScale = 1.0 / frames.size

        val samples = ArrayList<Double>(minOf(total, maxSamples) * 3)
        val sum = DoubleArray(3)
        val sumOfSquares = DoubleArray(3)
        var accepted = 0
        var clipped = 0

        for (gridY in 0 until roi.height) {
            val onLatticeRow = gridY % stride == 0
            for (gridX in 0 until roi.width) {
                val pixelX = (roi.x + gridX) * 2
                val pixelY = (roi.y + gridY) * 2

                var red = 0.0
                var green = 0.0
                var blue = 0.0
                var isClipped = false

                for (frame in frames) {
                    val raw = IntArray(4) { index ->
                        frame.sample(
                            x = pixelX + cells[index] % 2,
                            y = pixelY + cells[index] / 2,
                        )
                    }
                    // Clipping is tested on the raw samples, before the greens
                    // are averaged: averaging first hides a single clipped
                    // green behind its healthy twin.
                    if (raw[0] > clipLevels[0] || raw[1] > clipLevels[1] ||
                        raw[2] > clipLevels[2] || raw[3] > clipLevels[3]
                    ) {
                        isClipped = true
                        break
                    }
                    red += levels.normalise(raw[0], cells[0])
                    green += 0.5 * (
                        levels.normalise(raw[1], cells[1]) +
                            levels.normalise(raw[2], cells[2])
                        )
                    blue += levels.normalise(raw[3], cells[3])
                }

                if (isClipped) {
                    clipped++
                    continue
                }

                red *= frameScale
                green *= frameScale
                blue *= frameScale

                accepted++
                sum[0] += red
                sum[1] += green
                sum[2] += blue
                sumOfSquares[0] += red * red
                sumOfSquares[1] += green * green
                sumOfSquares[2] += blue * blue

                if (onLatticeRow && gridX % stride == 0) {
                    samples.add(red)
                    samples.add(green)
                    samples.add(blue)
                }
            }
        }

        val mean = DoubleArray(3)
        val stdDev = DoubleArray(3)
        if (accepted > 0) {
            val n = accepted.toDouble()
            for (channel in 0 until 3) {
                mean[channel] = sum[channel] / n
                val variance = sumOfSquares[channel] / n - mean[channel] * mean[channel]
                stdDev[channel] = if (variance > 0.0) sqrt(variance) else 0.0
            }
        }

        return SuperpixelReduction(
            samples = samples.toDoubleArray(),
            sampleCount = samples.size / 3,
            totalSuperpixels = total,
            clippedSuperpixels = clipped,
            decimationStride = stride,
            channelMean = mean,
            channelStdDev = stdDev,
            widthInSuperpixels = roi.width,
            heightInSuperpixels = roi.height,
        )
    }
}

/**
 * Focus measurement taken straight from a Bayer frame.
 *
 * Works on the superpixel grid rather than on raw pixels: neighbouring raw
 * pixels carry different colours, so a Laplacian across them would measure the
 * colour filter array, not the focus.
 */
object BayerSharpness {
    fun greenLaplacianVariance(
        frame: BayerFrame,
        pattern: BayerPattern,
        levels: SensorLevels,
        roi: SuperpixelRectangle,
    ): Double {
        if (roi.width <= 2 || roi.height <= 2) return 0.0
        val g1 = pattern.green1Cell
        val g2 = pattern.green2Cell

        fun green(gridX: Int, gridY: Int): Double {
            val pixelX = (roi.x + gridX) * 2
            val pixelY = (roi.y + gridY) * 2
            val first = frame.sample(pixelX + g1 % 2, pixelY + g1 / 2)
            val second = frame.sample(pixelX + g2 % 2, pixelY + g2 / 2)
            return 0.5 * (levels.normalise(first, g1) + levels.normalise(second, g2))
        }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for (gridY in 1 until roi.height - 1) {
            for (gridX in 1 until roi.width - 1) {
                val laplacian = green(gridX, gridY - 1) +
                    green(gridX, gridY + 1) +
                    green(gridX - 1, gridY) +
                    green(gridX + 1, gridY) -
                    4 * green(gridX, gridY)
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1.0
            }
        }
        if (count <= 0.0) return 0.0
        val mean = sum / count
        val variance = sumOfSquares / count - mean * mean
        // Scaled by the same factor as the iOS side so the two are readable on
        // the same axis in a log.
        return if (variance > 0.0) variance * 1_000_000 else 0.0
    }
}
