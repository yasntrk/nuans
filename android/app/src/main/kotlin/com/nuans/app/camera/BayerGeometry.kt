package com.nuans.app.camera

import android.hardware.camera2.CameraCharacteristics
import android.media.Image
import java.nio.ByteBuffer
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Which colour each cell of a 2x2 Bayer block carries.
 *
 * Cell indices are `y * 2 + x`, so 0 is top-left, 1 top-right, 2 bottom-left
 * and 3 bottom-right. The same indexing as the iOS side, deliberately: the two
 * reducers have to agree sample for sample or a profile built on one platform
 * would not transfer to the other.
 */
enum class BayerPattern(
    val redCell: Int,
    val green1Cell: Int,
    val green2Cell: Int,
    val blueCell: Int,
) {
    RGGB(0, 1, 2, 3),
    GRBG(1, 0, 3, 2),
    GBRG(2, 0, 3, 1),
    BGGR(3, 1, 2, 0),
    ;

    val cells: IntArray get() = intArrayOf(redCell, green1Cell, green2Cell, blueCell)

    companion object {
        /** Maps the platform's colour filter arrangement constant. */
        fun fromColorFilterArrangement(value: Int?): BayerPattern? = when (value) {
            CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_RGGB -> RGGB
            CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GRBG -> GRBG
            CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GBRG -> GBRG
            CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_BGGR -> BGGR
            else -> null
        }
    }
}

/**
 * Black and white levels of one sensor readout.
 *
 * Black level is per cell because sensors do not share one pedestal across
 * channels. Android publishes both a static pattern and, on most devices, a
 * per-frame dynamic value; the dynamic one is preferred because the pedestal
 * drifts with sensor temperature, and the shadow rejection threshold sits
 * exactly where that drift shows.
 */
data class SensorLevels(
    val black: DoubleArray,
    val white: Double,
    val isDynamic: Boolean,
) {
    init {
        require(black.size == 4) { "black level needs one value per Bayer cell" }
        require(white > black.max()) { "white level must exceed every black level" }
    }

    fun blackAt(cell: Int): Double = black[cell]

    /** Normalises one raw sample to `0 .. 1`. */
    fun normalise(raw: Int, cell: Int): Double {
        val pedestal = black[cell]
        val range = white - pedestal
        if (range <= 0.0) return 0.0
        val value = (raw.toDouble() - pedestal) / range
        return if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value
    }

    /** The raw value at which a cell counts as clipped. */
    fun clippingLevel(cell: Int, threshold: Double): Double =
        black[cell] + threshold * (white - black[cell])

    companion object {
        fun uniform(black: Double, white: Double, isDynamic: Boolean): SensorLevels =
            SensorLevels(doubleArrayOf(black, black, black, black), white, isDynamic)
    }

    override fun equals(other: Any?): Boolean =
        other is SensorLevels &&
            black.contentEquals(other.black) &&
            white == other.white &&
            isDynamic == other.isDynamic

    override fun hashCode(): Int =
        31 * (31 * black.contentHashCode() + white.hashCode()) + isDynamic.hashCode()
}

/** A rectangle in superpixel coordinates: whole 2x2 Bayer blocks. */
data class SuperpixelRectangle(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int,
) {
    val count: Int get() = width * height

    companion object {
        /**
         * Maps a sensor-normalised rectangle onto the superpixel grid.
         *
         * Superpixel `i` always starts at raw pixel `2 * i`, so every block
         * stays aligned to the colour filter array by construction and cropping
         * can never shift the pattern.
         */
        fun from(rect: NormalizedRect, frameWidth: Int, frameHeight: Int): SuperpixelRectangle {
            val gridWidth = frameWidth / 2
            val gridHeight = frameHeight / 2
            if (gridWidth <= 0 || gridHeight <= 0) {
                throw ShadeCameraFailure(
                    CameraErrorCode.CAPTURE_FAILED,
                    "frame is too small to hold a single Bayer block",
                )
            }
            if (rect.width <= 0.0 || rect.height <= 0.0 ||
                rect.left < 0.0 || rect.top < 0.0 ||
                rect.left + rect.width > 1.000001 ||
                rect.top + rect.height > 1.000001
            ) {
                throw ShadeCameraFailure(
                    CameraErrorCode.ROI_OUT_OF_BOUNDS,
                    "normalised rectangle must lie inside the unit square",
                )
            }
            val x = (rect.left * gridWidth).toInt().coerceIn(0, gridWidth - 1)
            val y = (rect.top * gridHeight).toInt().coerceIn(0, gridHeight - 1)
            val width = (rect.width * gridWidth).toInt().coerceIn(1, gridWidth - x)
            val height = (rect.height * gridHeight).toInt().coerceIn(1, gridHeight - y)
            return SuperpixelRectangle(x, y, width, height)
        }
    }
}

/**
 * A 16-bit Bayer frame copied out of an [Image].
 *
 * The copy is deliberate. An `Image` holds a buffer owned by the camera's
 * `ImageReader`, and that buffer has to be handed back promptly or the capture
 * pipeline stalls; a measurement that can be re-reduced minutes later cannot
 * hold one. A 12 megapixel frame is about 24 MB, which is why [CaptureStore]
 * keeps so few.
 */
class BayerFrame(
    val samples: ShortArray,
    val rowStride: Int,
    val width: Int,
    val height: Int,
) {
    /** Unsigned 16-bit value at a raw pixel position. */
    fun sample(x: Int, y: Int): Int = samples[y * rowStride + x].toInt() and 0xFFFF

    companion object {
        /** Copies the single plane of a `RAW_SENSOR` image. */
        fun copyFrom(image: Image): BayerFrame {
            val plane = image.planes[0]
            val buffer: ByteBuffer = plane.buffer
            val rowStrideBytes = plane.rowStride
            val pixelStrideBytes = plane.pixelStride
            if (pixelStrideBytes != 2) {
                throw ShadeCameraFailure(
                    CameraErrorCode.RAW_UNAVAILABLE,
                    "expected a 16-bit raw plane, got a pixel stride of $pixelStrideBytes",
                )
            }
            val rowStride = rowStrideBytes / 2
            val samples = ShortArray(rowStride * image.height)
            val shorts = buffer.asShortBuffer()
            shorts.get(samples, 0, min(samples.size, shorts.remaining()))
            return BayerFrame(samples, rowStride, image.width, image.height)
        }
    }
}

/** Lattice stride for a region, derived from geometry alone. */
fun latticeStride(total: Int, maxSamples: Int): Int {
    if (total <= maxSamples || maxSamples <= 0) return 1
    return max(1, ceil(sqrt(total.toDouble() / maxSamples.toDouble())).toInt())
}
