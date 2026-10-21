import 'package:meta/meta.dart';
import 'package:shade_core/src/calibration/color_correction_matrix.dart';
import 'package:shade_core/src/calibration/gray_card.dart';
import 'package:shade_core/src/capture/camera_rgb.dart';
import 'package:shade_core/src/colorimetry/correlated_color_temperature.dart';
import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/constants.dart';

/// What can be wrong with a grey card reading.
enum GrayCardIssue {
  /// Part of the slot is at or above the clipping threshold.
  clipped,

  /// The slot is not uniform enough to be a flat neutral surface: it is off the
  /// card, on an edge, or in a shadow.
  nonUniform,

  /// Under-exposed, so the gains would amplify noise.
  tooDark,

  /// Over-exposed, so the card is approaching clipping.
  tooBright,

  /// The card's quadrants differ in colour, which means two different lights
  /// are falling on the scene.
  mixedLight,

  /// The implied colour temperature is far from the recommended light, so the
  /// correction would extrapolate well away from the profile's D65 basis.
  implausibleIlluminant,
}

/// Thresholds for grey card validation.
@immutable
final class GrayCardValidatorConfig {
  const GrayCardValidatorConfig({
    this.uniformityMax = kGrayCardUniformityMax,
    this.quadrantDeltaEMax = kGrayCardQuadrantDeltaEMax,
    this.clippedFractionMax = kGrayCardMaxClippedFraction,
    this.signalMin = kExposureGrayLumaMin,
    this.signalMax = kExposureGrayLumaMax,
  });

  final double uniformityMax;
  final double quadrantDeltaEMax;
  final double clippedFractionMax;
  final double signalMin;
  final double signalMax;
}

/// The outcome of validating a grey card reading.
@immutable
final class GrayCardVerdict {
  const GrayCardVerdict({
    required this.issues,
    required this.uniformityRatio,
    required this.clippedFraction,
    required this.medianGreen,
    required this.quadrantMaxDeltaE,
    required this.correlatedColorTemperature,
    required this.uniformityScore,
    required this.mixedLightScore,
  });

  final Set<GrayCardIssue> issues;
  final double uniformityRatio;
  final double clippedFraction;
  final double medianGreen;

  /// Largest pairwise difference between the card's quadrants, or `null` when
  /// fewer than two quadrants were supplied.
  final double? quadrantMaxDeltaE;

  /// McCamy estimate for the capture light, or `null` when it could not be
  /// evaluated.
  final double? correlatedColorTemperature;

  /// 0 .. 1 inputs to the confidence engine.
  final double uniformityScore;
  final double mixedLightScore;

  bool get isValid => issues.isEmpty;

  /// The grey card term of the confidence score: the weaker of the two
  /// sub-scores, because either one failing invalidates the correction.
  double get score =>
      uniformityScore < mixedLightScore ? uniformityScore : mixedLightScore;

  @override
  String toString() => 'GrayCardVerdict(valid: $isValid, issues: $issues)';
}

/// Validates the neutral card slot before a capture is allowed.
///
/// Note what is deliberately *not* checked here: that the card reads `a* = b* =
/// 0` after correction. The gains make the card neutral by definition and a
/// white-point preserving matrix keeps it neutral, so that test passes even if
/// a blue lens cap were photographed instead of the card. It is an invariant of
/// the chain, asserted in the unit tests, not a runtime discriminator. The four
/// checks below are the ones that actually discriminate.
@immutable
final class GrayCardValidator {
  const GrayCardValidator({this.config = const GrayCardValidatorConfig()});

  final GrayCardValidatorConfig config;

  /// [uniformityRatio] is the spatial standard deviation over the mean of the
  /// slot, measured natively. [quadrants] are the linear camera-space means of
  /// the slot's four quarters, used for the mixed-light check.
  GrayCardVerdict validate({
    required CameraRgb median,
    required double uniformityRatio,
    required double clippedFraction,
    required List<CameraRgb> quadrants,
    required ColorCorrectionMatrix ccm,
  }) {
    final issues = <GrayCardIssue>{};

    if (clippedFraction > config.clippedFractionMax) {
      issues.add(GrayCardIssue.clipped);
    }
    if (uniformityRatio > config.uniformityMax) {
      issues.add(GrayCardIssue.nonUniform);
    }
    if (median.green < config.signalMin) {
      issues.add(GrayCardIssue.tooDark);
    }
    if (median.green > config.signalMax) {
      issues.add(GrayCardIssue.tooBright);
    }

    final quadrantMaxDeltaE = _quadrantSpread(
      quadrants: quadrants,
      median: median,
      ccm: ccm,
    );
    if (quadrantMaxDeltaE != null &&
        quadrantMaxDeltaE > config.quadrantDeltaEMax) {
      issues.add(GrayCardIssue.mixedLight);
    }

    final cct = _illuminantCct(median: median, ccm: ccm);
    if (cct != null &&
        !CorrelatedColorTemperature.isPlausibleCaptureIlluminant(cct)) {
      issues.add(GrayCardIssue.implausibleIlluminant);
    }

    return GrayCardVerdict(
      issues: issues,
      uniformityRatio: uniformityRatio,
      clippedFraction: clippedFraction,
      medianGreen: median.green,
      quadrantMaxDeltaE: quadrantMaxDeltaE,
      correlatedColorTemperature: cct,
      uniformityScore: _score(uniformityRatio, config.uniformityMax),
      mixedLightScore: quadrantMaxDeltaE == null
          ? 0.5
          : _score(quadrantMaxDeltaE, config.quadrantDeltaEMax),
    );
  }

  /// Largest pairwise CIEDE2000 between the quadrants, after correcting them
  /// all with the gains of the whole card.
  ///
  /// Correcting with the shared gains is the point: it removes the average
  /// colour of the light, so what is left is the *variation* of the light
  /// across the card.
  double? _quadrantSpread({
    required List<CameraRgb> quadrants,
    required CameraRgb median,
    required ColorCorrectionMatrix ccm,
  }) {
    if (quadrants.length < 2) return null;
    final correction = GrayCardCorrection.fromMeasurement(cardMedian: median);
    final labs = <LabColor>[];
    for (final quadrant in quadrants) {
      if (quadrant.minChannel <= 0) continue;
      labs.add(
        ccm
            .toXyz(quadrant.withGains(correction.gains))
            .toLab(whitePoint: ccm.whitePoint),
      );
    }
    if (labs.length < 2) return null;
    var max = 0.0;
    for (var i = 0; i < labs.length; i++) {
      for (var j = i + 1; j < labs.length; j++) {
        final deltaE = DeltaE2000.between(
          reference: labs[i],
          sample: labs[j],
        ).deltaE;
        if (deltaE > max) max = deltaE;
      }
    }
    return max;
  }

  /// The colour temperature implied by the *uncorrected* card.
  ///
  /// Uncorrected on purpose: after the gains the card is neutral by
  /// construction and would always report the profile's own white point.
  double? _illuminantCct({
    required CameraRgb median,
    required ColorCorrectionMatrix ccm,
  }) {
    final chromaticity = ccm.toXyz(median).chromaticity;
    if (chromaticity == null) return null;
    return CorrelatedColorTemperature.mcCamy(
      x: chromaticity.x,
      y: chromaticity.y,
    );
  }

  static double _score(double value, double limit) {
    if (limit <= 0) return 0;
    final score = 1 - value / limit;
    return score < 0 ? 0 : (score > 1 ? 1 : score);
  }
}
