package com.nuans.app.camera

import android.media.Image
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * A `YUV_420_888` preview frame, copied out of an [Image].
 *
 * The RGB values this exposes are **display-referred**, not linear: the frame
 * has already been through the device's imaging pipeline. That is why every
 * preview message leaves native tagged `SignalEncoding.DISPLAY_REFERRED_SRGB`
 * and the measurement itself never uses these numbers.
 *
 * The conversion is BT.601 limited range, which is what camera YUV output
 * normally is. It is an approximation of the device's actual matrix, and an
 * acceptable one for a traffic light: the authoritative grey card check runs
 * again on the raw burst.
 */
class YuvFrame(
    private val luma: ByteArray,
    private val chromaU: ByteArray,
    private val chromaV: ByteArray,
    private val lumaRowStride: Int,
    private val chromaRowStride: Int,
    private val chromaPixelStride: Int,
    val width: Int,
    val height: Int,
) {
    /** Unsigned luma at a pixel. */
    fun lumaAt(x: Int, y: Int): Int = luma[y * lumaRowStride + x].toInt() and 0xFF

    /** Display-referred R, G, B in `0 .. 1` at a pixel. */
    fun rgbAt(x: Int, y: Int, into: DoubleArray) {
        val yValue = lumaAt(x, y)
        val chromaIndex = (y / 2) * chromaRowStride + (x / 2) * chromaPixelStride
        val u = (chromaU[chromaIndex].toInt() and 0xFF) - 128
        val v = (chromaV[chromaIndex].toInt() and 0xFF) - 128
        val luminance = 1.164 * (yValue - 16)
        into[0] = clamp01((luminance + 1.596 * v) / 255.0)
        into[1] = clamp01((luminance - 0.392 * u - 0.813 * v) / 255.0)
        into[2] = clamp01((luminance + 2.017 * u) / 255.0)
    }

    private fun clamp01(value: Double): Double =
        if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value

    companion object {
        fun copyFrom(image: Image): YuvFrame {
            val y = image.planes[0]
            val u = image.planes[1]
            val v = image.planes[2]
            fun bytes(buffer: java.nio.ByteBuffer): ByteArray {
                val array = ByteArray(buffer.remaining())
                buffer.get(array)
                return array
            }
            return YuvFrame(
                luma = bytes(y.buffer),
                chromaU = bytes(u.buffer),
                chromaV = bytes(v.buffer),
                lumaRowStride = y.rowStride,
                chromaRowStride = u.rowStride,
                chromaPixelStride = u.pixelStride,
                width = image.width,
                height = image.height,
            )
        }
    }
}

/** A region of a preview frame, in pixels. */
data class PixelRegion(val x: Int, val y: Int, val width: Int, val height: Int) {
    companion object {
        fun from(rect: NormalizedRect, width: Int, height: Int): PixelRegion {
            val x = (rect.left * width).toInt().coerceIn(0, width - 1)
            val y = (rect.top * height).toInt().coerceIn(0, height - 1)
            return PixelRegion(
                x = x,
                y = y,
                width = (rect.width * width).toInt().coerceIn(1, width - x),
                height = (rect.height * height).toInt().coerceIn(1, height - y),
            )
        }
    }

    /** The four quadrants, used for the mixed-lighting check. */
    fun quadrants(): List<PixelRegion> {
        val halfWidth = maxOf(1, width / 2)
        val halfHeight = maxOf(1, height / 2)
        return listOf(
            PixelRegion(x, y, halfWidth, halfHeight),
            PixelRegion(x + halfWidth, y, maxOf(1, width - halfWidth), halfHeight),
            PixelRegion(x, y + halfHeight, halfWidth, maxOf(1, height - halfHeight)),
            PixelRegion(
                x + halfWidth,
                y + halfHeight,
                maxOf(1, width - halfWidth),
                maxOf(1, height - halfHeight),
            ),
        )
    }
}

/**
 * Sharpness, motion and clipping measures over a preview frame.
 *
 * These are measurements, not verdicts. The thresholds live in Dart, where they
 * are unit tested and can be retuned without a native release.
 */
object FrameQualityAnalyzer {
    /** 8-bit level at or above which a preview sample counts as blown. */
    const val HIGHLIGHT_LEVEL = 250

    /** 8-bit level at or below which it counts as crushed. */
    const val SHADOW_LEVEL = 4

    /**
     * Variance of a four-neighbour Laplacian of luma over a region.
     *
     * The Laplacian responds to local contrast, so its variance collapses out
     * of focus. Its absolute value depends on sensor, lens and subject, which
     * is why the accept rule in Dart also compares each frame against the
     * sharpest frame of the same burst.
     */
    fun laplacianVariance(frame: YuvFrame, region: PixelRegion): Double {
        if (region.width <= 2 || region.height <= 2) return 0.0
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for (y in region.y + 1 until region.y + region.height - 1) {
            for (x in region.x + 1 until region.x + region.width - 1) {
                val laplacian = frame.lumaAt(x, y - 1) +
                    frame.lumaAt(x, y + 1) +
                    frame.lumaAt(x - 1, y) +
                    frame.lumaAt(x + 1, y) -
                    4 * frame.lumaAt(x, y)
                sum += laplacian
                sumOfSquares += laplacian.toDouble() * laplacian
                count += 1.0
            }
        }
        if (count <= 0.0) return 0.0
        val mean = sum / count
        val variance = sumOfSquares / count - mean * mean
        return if (variance > 0.0) variance else 0.0
    }

    /**
     * Mean absolute luma difference between two frames, normalised by the mean
     * level so it does not change with exposure.
     *
     * Returns `null` when there is no previous frame, which the caller reports
     * as "not yet known" rather than as "no motion".
     */
    fun motionScore(
        current: YuvFrame,
        previous: YuvFrame?,
        region: PixelRegion,
        sampleStride: Int = 4,
    ): Double? {
        if (previous == null) return null
        if (previous.width != current.width || previous.height != current.height) {
            return null
        }
        var difference = 0.0
        var level = 0.0
        var count = 0.0
        var y = region.y
        while (y < region.y + region.height) {
            var x = region.x
            while (x < region.x + region.width) {
                val a = current.lumaAt(x, y)
                val b = previous.lumaAt(x, y)
                difference += abs(a - b).toDouble()
                level += a.toDouble()
                count += 1.0
                x += sampleStride
            }
            y += sampleStride
        }
        if (count <= 0.0 || level <= 0.0) return null
        return (difference / count) / (level / count)
    }

    /** Share of samples at or above the highlight level, and at or below the shadow level. */
    fun clippingFractions(
        frame: YuvFrame,
        region: PixelRegion,
        sampleStride: Int = 2,
    ): Pair<Double, Double> {
        var highlights = 0.0
        var shadows = 0.0
        var count = 0.0
        var y = region.y
        while (y < region.y + region.height) {
            var x = region.x
            while (x < region.x + region.width) {
                val value = frame.lumaAt(x, y)
                if (value >= HIGHLIGHT_LEVEL) highlights += 1.0
                if (value <= SHADOW_LEVEL) shadows += 1.0
                count += 1.0
                x += sampleStride
            }
            y += sampleStride
        }
        if (count <= 0.0) return 0.0 to 0.0
        return (highlights / count) to (shadows / count)
    }

    /**
     * Mean display-referred RGB of a region, plus the spatial standard
     * deviation of luma over its mean.
     *
     * That ratio is the uniformity measure of the grey card slot: a flat
     * neutral surface has a small one, and an edge, a shadow or anything that
     * is not the card has a large one.
     */
    fun channelStatistics(
        frame: YuvFrame,
        region: PixelRegion,
        sampleStride: Int = 2,
    ): ChannelStatistics {
        val rgb = DoubleArray(3)
        val sums = DoubleArray(3)
        var lumaSum = 0.0
        var lumaSquares = 0.0
        var count = 0.0
        var y = region.y
        while (y < region.y + region.height) {
            var x = region.x
            while (x < region.x + region.width) {
                frame.rgbAt(x, y, rgb)
                for (channel in 0 until 3) sums[channel] += rgb[channel]
                val luma = frame.lumaAt(x, y).toDouble()
                lumaSum += luma
                lumaSquares += luma * luma
                count += 1.0
                x += sampleStride
            }
            y += sampleStride
        }
        if (count <= 0.0) return ChannelStatistics(DoubleArray(3), 0.0)
        val mean = DoubleArray(3) { sums[it] / count }
        val lumaMean = lumaSum / count
        val variance = lumaSquares / count - lumaMean * lumaMean
        val ratio = if (lumaMean > 0.0 && variance > 0.0) sqrt(variance) / lumaMean else 0.0
        return ChannelStatistics(mean, ratio)
    }

    data class ChannelStatistics(val mean: DoubleArray, val uniformityRatio: Double) {
        override fun equals(other: Any?): Boolean =
            other is ChannelStatistics &&
                mean.contentEquals(other.mean) &&
                uniformityRatio == other.uniformityRatio

        override fun hashCode(): Int = 31 * mean.contentHashCode() + uniformityRatio.hashCode()
    }
}
