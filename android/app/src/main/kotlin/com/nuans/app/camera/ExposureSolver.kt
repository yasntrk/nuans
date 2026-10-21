package com.nuans.app.camera

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Solves the shutter time that puts the neutral card on its target signal.
 *
 * A CMOS sensor is linear in exposure over the range this protocol uses, so one
 * measurement gives the whole answer: if the card reads half the target, double
 * the time. The loop exists only because clamping to the device's shutter
 * range, and the card being near clipping, can keep a single step from landing.
 *
 * Pure arithmetic with no capture session in it, so the loop is testable. Same
 * decisions as the iOS solver, including the rule that clipped highlights
 * override the card target.
 */
object ExposureSolver {
    /** Maximum number of measurements before giving up. */
    const val MAX_ITERATIONS = 3

    data class Limits(val minDurationSeconds: Double, val maxDurationSeconds: Double)

    sealed interface Outcome {
        val durationSeconds: Double

        /** The card is on target and nothing clips. */
        data class Solved(override val durationSeconds: Double) : Outcome

        /** Try again with this duration. */
        data class Retry(override val durationSeconds: Double) : Outcome

        /** The device cannot expose this scene within its shutter range. */
        data class OutOfRange(override val durationSeconds: Double) : Outcome
    }

    fun nextDuration(
        current: Double,
        measuredCardLuma: Double,
        targetLuma: Double,
        limits: Limits,
    ): Double {
        // A card reading zero carries no information about the right exposure,
        // so open up by a fixed factor rather than dividing by zero.
        if (measuredCardLuma <= 0.001) {
            return min(current * 4, limits.maxDurationSeconds)
        }
        val scaled = current * (targetLuma / measuredCardLuma)
        return max(limits.minDurationSeconds, min(scaled, limits.maxDurationSeconds))
    }

    fun evaluate(
        iteration: Int,
        current: Double,
        measuredCardLuma: Double,
        toothClippedFraction: Double,
        targetLuma: Double,
        acceptableLumaRange: ClosedFloatingPointRange<Double>,
        maxToothClippedFraction: Double,
        limits: Limits,
    ): Outcome {
        val cardInRange = measuredCardLuma in acceptableLumaRange
        val highlightsSafe = toothClippedFraction <= maxToothClippedFraction
        if (cardInRange && highlightsSafe) return Outcome.Solved(current)
        if (iteration + 1 >= MAX_ITERATIONS) return Outcome.OutOfRange(current)

        // Clipped highlights override the card target: a blown tooth cannot be
        // measured at all, while a slightly dark card only costs signal to
        // noise.
        val next = if (!highlightsSafe) {
            max(limits.minDurationSeconds, current * 0.6)
        } else {
            nextDuration(current, measuredCardLuma, targetLuma, limits)
        }
        if (abs(next - current) / max(current, 1e-9) < 0.02) {
            // The clamp has pinned us; another identical measurement will not
            // help.
            return Outcome.OutOfRange(current)
        }
        return Outcome.Retry(next)
    }
}
