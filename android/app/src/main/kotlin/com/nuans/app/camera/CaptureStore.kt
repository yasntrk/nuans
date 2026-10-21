package com.nuans.app.camera

/** The accepted frames of one finished capture, kept for a later re-reduction. */
class RetainedCapture(
    val captureId: String,
    val frames: List<BayerFrame>,
    val qualities: List<FrameQuality>,
    val pattern: BayerPattern,
    val levels: SensorLevels,
    val createdAtMillis: Long = System.currentTimeMillis(),
)

/**
 * Holds the accepted frames of recent captures.
 *
 * Memory here is real: a 12 megapixel 16-bit Bayer frame is about 24 MB and a
 * burst of three is 72 MB. So the store is small, bounded and dropped eagerly.
 * Dart owns the lifetime through `releaseCapture`; the bound and the age limit
 * exist only to survive a Dart side that died before it could release.
 */
class CaptureStore {
    companion object {
        /**
         * Two captures: enough for a clinician to drag the regions of the
         * previous measurement while the next one is already shot.
         */
        const val CAPACITY = 2

        /** Age after which a capture is dropped even without a release. */
        const val MAXIMUM_AGE_MILLIS = 600_000L
    }

    private val captures = ArrayList<RetainedCapture>()

    @Synchronized
    fun store(capture: RetainedCapture) {
        captures.removeAll { it.captureId == capture.captureId }
        captures.add(capture)
        prune()
    }

    @Synchronized
    fun capture(id: String): RetainedCapture? {
        prune()
        return captures.firstOrNull { it.captureId == id }
    }

    @Synchronized
    fun release(id: String) {
        captures.removeAll { it.captureId == id }
    }

    @Synchronized
    fun releaseAll() {
        captures.clear()
    }

    private fun prune() {
        val now = System.currentTimeMillis()
        captures.removeAll { now - it.createdAtMillis > MAXIMUM_AGE_MILLIS }
        while (captures.size > CAPACITY) {
            captures.removeAt(0)
        }
    }
}
