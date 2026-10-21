import Foundation

/// Solves the shutter time that puts the neutral card on its target signal.
///
/// A CMOS sensor is linear in exposure over the range this protocol uses, so
/// one measurement gives the whole answer: if the card reads half the target,
/// double the time. The loop exists only because clamping to the device's
/// shutter range, and the card being near clipping, can keep a single step
/// from landing.
///
/// Pure arithmetic with no capture session in it, so the loop is testable.
enum ExposureSolver {
    struct Limits {
        let minDuration: Double
        let maxDuration: Double

        init(minDuration: Double, maxDuration: Double) {
            self.minDuration = minDuration
            self.maxDuration = maxDuration
        }
    }

    enum Outcome: Equatable {
        /// The card is on target and nothing clips.
        case solved(duration: Double)

        /// Try again with this duration.
        case retry(duration: Double)

        /// The device cannot expose this scene within its shutter range.
        case outOfRange(duration: Double)
    }

    /// Maximum number of measurements before giving up.
    static let maxIterations = 3

    /// The next shutter time to try.
    static func nextDuration(
        current: Double,
        measuredCardLuma: Double,
        targetLuma: Double,
        limits: Limits
    ) -> Double {
        // A card reading zero carries no information about the right exposure,
        // so open up by a fixed factor rather than dividing by zero.
        guard measuredCardLuma > 0.001 else {
            return min(current * 4, limits.maxDuration)
        }
        let scaled = current * (targetLuma / measuredCardLuma)
        return max(limits.minDuration, min(scaled, limits.maxDuration))
    }

    /// Whether a measurement is good enough to lock.
    static func evaluate(
        iteration: Int,
        current: Double,
        measuredCardLuma: Double,
        toothClippedFraction: Double,
        targetLuma: Double,
        acceptableLumaRange: ClosedRange<Double>,
        maxToothClippedFraction: Double,
        limits: Limits
    ) -> Outcome {
        let cardInRange = acceptableLumaRange.contains(measuredCardLuma)
        let highlightsSafe = toothClippedFraction <= maxToothClippedFraction
        if cardInRange && highlightsSafe {
            return .solved(duration: current)
        }
        guard iteration + 1 < maxIterations else {
            return .outOfRange(duration: current)
        }
        // Clipped highlights override the card target: a blown tooth cannot be
        // measured at all, while a slightly dark card only costs signal to
        // noise. So when the tooth clips, shorten the exposure even if that
        // takes the card below its window.
        let next: Double
        if !highlightsSafe {
            next = max(limits.minDuration, current * 0.6)
        } else {
            next = nextDuration(
                current: current,
                measuredCardLuma: measuredCardLuma,
                targetLuma: targetLuma,
                limits: limits
            )
        }
        if abs(next - current) / max(current, 1e-9) < 0.02 {
            // The clamp has pinned us; another identical measurement will not
            // help.
            return .outOfRange(duration: current)
        }
        return .retry(duration: next)
    }
}
