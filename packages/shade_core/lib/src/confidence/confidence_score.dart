import 'package:meta/meta.dart';

import 'package:shade_core/src/calibration/color_correction_matrix.dart';
import 'package:shade_core/src/statistics/roi_reducer.dart';

/// How far a measurement can be trusted.
enum ConfidenceBand { high, medium, low }

/// Why a measurement was forced to [ConfidenceBand.low] regardless of its
/// weighted score.
enum ConfidenceOverride {
  /// Neither a chart fit nor a manufacturer matrix was available.
  noColorProfile,

  /// The grey card did not validate, so nothing anchors the white point or the
  /// absolute lightness.
  grayCardInvalid,

  /// More than half of a region was discarded.
  excessiveRejection,

  /// Too few samples survived for the robust statistics to be stable.
  tooFewSamples,

  /// No burst frame was accepted.
  noAcceptedFrames,
}

/// The weights of the seven terms.
///
/// The grouping is the argument, not the exact numbers:
///
/// * capture mode, device profile and grey card together carry 0.56, because an
///   error in any of them is a *systematic* bias that no later step can undo;
/// * the region terms carry 0.22, because their error is random and already
///   suppressed by averaging thousands of samples;
/// * the cross-checks carry 0.22, because they are the only mechanism that can
///   catch what the first two groups cannot see.
///
/// The absolute values are uncalibrated and must be treated as placeholders
/// until the field validation of Stage 7 has run.
@immutable
final class ConfidenceWeights {
  const ConfidenceWeights({
    this.captureMode = 0.18,
    this.deviceProfile = 0.20,
    this.grayCard = 0.18,
    this.rejectedFraction = 0.12,
    this.regionHomogeneity = 0.10,
    this.relativeMode = 0.10,
    this.matchResidual = 0.12,
  });

  static const ConfidenceWeights standard = ConfidenceWeights();

  final double captureMode;
  final double deviceProfile;
  final double grayCard;
  final double rejectedFraction;
  final double regionHomogeneity;
  final double relativeMode;
  final double matchResidual;

  double get total =>
      captureMode +
      deviceProfile +
      grayCard +
      rejectedFraction +
      regionHomogeneity +
      relativeMode +
      matchResidual;
}

/// Thresholds separating the three bands.
@immutable
final class ConfidenceBandThresholds {
  const ConfidenceBandThresholds({this.high = 0.80, this.medium = 0.60});

  final double high;
  final double medium;

  ConfidenceBand classify(double score) {
    if (score >= high) return ConfidenceBand.high;
    if (score >= medium) return ConfidenceBand.medium;
    return ConfidenceBand.low;
  }
}

/// How the shade tab of the relative protocol was used.
enum RelativeModeState {
  /// Used, and the tab matched its library value.
  usedAndConsistent,

  /// Used, but the tab disagreed with its library value by too much, so no
  /// correction was applied.
  usedButInconsistent,

  /// Not used. Not an error, but one independent cross-check fewer.
  notUsed,
}

/// One term of the score, kept so the user interface can say *why*.
@immutable
final class ConfidenceTerm {
  const ConfidenceTerm({
    required this.name,
    required this.score,
    required this.weight,
  });

  /// A machine name, mapped to an ARB key by the presentation layer.
  final String name;

  /// The sub-score, `0 .. 1`.
  final double score;

  final double weight;

  double get contribution => score * weight;

  @override
  String toString() => '$name: $score x $weight';
}

/// The confidence of one measurement, with its reasoning attached.
@immutable
final class ConfidenceScore {
  const ConfidenceScore({
    required this.score,
    required this.band,
    required this.terms,
    required this.overrides,
  });

  /// The weighted sum, `0 .. 1`.
  final double score;

  /// The band actually reported, after any override.
  final ConfidenceBand band;

  final List<ConfidenceTerm> terms;

  /// Hard failures that pinned the band to low.
  final Set<ConfidenceOverride> overrides;

  bool get wasOverridden => overrides.isNotEmpty;

  /// The weakest term, which is what the interface should tell the user to fix.
  ConfidenceTerm get weakestTerm =>
      terms.reduce((a, b) => a.score <= b.score ? a : b);

  @override
  String toString() => 'ConfidenceScore($score, ${band.name}, '
      'overrides: ${overrides.map((o) => o.name)})';
}

/// Combines the evidence of a measurement into one reported confidence.
///
/// A weighted sum has a known weakness: a few good terms can mask a fatal one.
/// So the sum is paired with hard overrides, and the two answer different
/// questions. The sum answers "how good is this measurement?" and the overrides
/// answer "is this a measurement at all?".
@immutable
final class ConfidenceScorer {
  const ConfidenceScorer({
    this.weights = ConfidenceWeights.standard,
    this.thresholds = const ConfidenceBandThresholds(),
    this.minAcceptedSamples = 64,
    this.maxRejectedFraction = 0.50,
  });

  final ConfidenceWeights weights;
  final ConfidenceBandThresholds thresholds;
  final int minAcceptedSamples;
  final double maxRejectedFraction;

  /// [profileScore] comes from `DeviceProfile.confidenceScore`,
  /// [grayCardScore] from `GrayCardVerdict.score`.
  ConfidenceScore score({
    required CcmSource captureSource,
    required double profileScore,
    required bool grayCardValid,
    required double grayCardScore,
    required RoiReduction reduction,
    required RelativeModeState relativeMode,
    required double bestMatchDeltaE,
    required int acceptedFrameCount,
  }) {
    final terms = <ConfidenceTerm>[
      ConfidenceTerm(
        name: 'captureMode',
        // A processed frame went through local tone mapping, which no global
        // inverse transfer function undoes. That is not noise, it is a bias.
        score: captureSource == CcmSource.srgbProcessed ? 0.45 : 1.0,
        weight: weights.captureMode,
      ),
      ConfidenceTerm(
        name: 'deviceProfile',
        score: _clamp(profileScore),
        weight: weights.deviceProfile,
      ),
      ConfidenceTerm(
        name: 'grayCard',
        score: grayCardValid ? _clamp(grayCardScore) : 0,
        weight: weights.grayCard,
      ),
      ConfidenceTerm(
        name: 'rejectedFraction',
        // The penalty starts at 12% rather than at zero: the unscaled MAD
        // thresholds discard about 6.7% of a perfectly homogeneous region on
        // their own, so a small rejected share is the baseline and not a fault.
        score: _ramp(reduction.rejectedFraction, good: 0.12, bad: 0.45),
        weight: weights.rejectedFraction,
      ),
      ConfidenceTerm(
        name: 'regionHomogeneity',
        // A real tooth has a genuine gradient, so this spread is not pure
        // noise, which is why it carries little weight.
        score: _ramp(reduction.lightnessStdDev, good: 1.5, bad: 6),
        weight: weights.regionHomogeneity,
      ),
      ConfidenceTerm(
        name: 'relativeMode',
        score: switch (relativeMode) {
          RelativeModeState.usedAndConsistent => 1.0,
          RelativeModeState.usedButInconsistent => 0.3,
          RelativeModeState.notUsed => 0.5,
        },
        weight: weights.relativeMode,
      ),
      ConfidenceTerm(
        name: 'matchResidual',
        // A large residual says something the model cannot see is present:
        // dehydration, translucency, or a library that no longer matches the
        // clinic's physical guide.
        score: _ramp(bestMatchDeltaE, good: 0.8, bad: 4),
        weight: weights.matchResidual,
      ),
    ];

    var weighted = 0.0;
    for (final term in terms) {
      weighted += term.contribution;
    }
    // Normalising by the total weight means a caller may hand in custom weights
    // without the score silently leaving 0 .. 1.
    final normalised = weights.total > 0 ? weighted / weights.total : 0.0;

    final overrides = <ConfidenceOverride>{};
    if (profileScore <= 0) overrides.add(ConfidenceOverride.noColorProfile);
    if (!grayCardValid) overrides.add(ConfidenceOverride.grayCardInvalid);
    if (reduction.rejectedFraction > maxRejectedFraction) {
      overrides.add(ConfidenceOverride.excessiveRejection);
    }
    if (reduction.acceptedSamples < minAcceptedSamples) {
      overrides.add(ConfidenceOverride.tooFewSamples);
    }
    if (acceptedFrameCount <= 0) {
      overrides.add(ConfidenceOverride.noAcceptedFrames);
    }

    return ConfidenceScore(
      score: normalised,
      band: overrides.isEmpty
          ? thresholds.classify(normalised)
          : ConfidenceBand.low,
      terms: List<ConfidenceTerm>.unmodifiable(terms),
      overrides: Set<ConfidenceOverride>.unmodifiable(overrides),
    );
  }

  /// 1 at or below [good], 0 at or above [bad], linear in between.
  static double _ramp(
    double value, {
    required double good,
    required double bad,
  }) {
    if (value <= good) return 1;
    if (value >= bad) return 0;
    return (bad - value) / (bad - good);
  }

  static double _clamp(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);
}
