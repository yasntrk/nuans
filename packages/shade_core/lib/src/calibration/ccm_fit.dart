import 'package:meta/meta.dart';
import 'package:shade_core/src/calibration/color_correction_matrix.dart';
import 'package:shade_core/src/capture/camera_rgb.dart';
import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';

/// One patch of a reference chart: what the camera measured and what the patch
/// is known to be.
@immutable
final class ChartPatch {
  const ChartPatch({
    required this.id,
    required this.measured,
    required this.reference,
    required this.isNeutral,
  });

  /// Stable identifier, e.g. `patch.19`.
  final String id;

  /// Linear camera-space measurement, black level removed and normalised.
  final CameraRgb measured;

  /// Published tristimulus values under the fit's white point, normalised so
  /// that `Y == 1` is a perfect diffuser. Chart data published as `Y` in
  /// 0 .. 100 under D50 must be divided by 100 and Bradford-adapted before it
  /// reaches this type.
  final XyzColor reference;

  /// Whether this patch belongs to the chart's neutral row, which is what the
  /// channel gains are derived from.
  final bool isNeutral;
}

/// Per-patch residual of a fit.
@immutable
final class PatchResidual {
  const PatchResidual({
    required this.patchId,
    required this.deltaE2000,
    required this.measuredLab,
    required this.referenceLab,
  });

  final String patchId;
  final double deltaE2000;
  final LabColor measuredLab;
  final LabColor referenceLab;
}

/// How well a fitted matrix reproduces the chart.
///
/// This is not a goodness-of-fit nicety. Camera spectral sensitivities are not
/// a linear transform of the CIE observer functions, so the Luther condition
/// does not hold and *no* 3x3 matrix can be exact. The mean residual is the
/// size of that fundamental limit on this device.
@immutable
final class CcmQualityReport {
  const CcmQualityReport({
    required this.meanDeltaE2000,
    required this.maxDeltaE2000,
    required this.residuals,
    required this.gate,
  });

  final double meanDeltaE2000;
  final double maxDeltaE2000;
  final List<PatchResidual> residuals;

  /// Mean residual above which the user is sent back to re-shoot.
  final double gate;

  bool get passes => meanDeltaE2000 <= gate;

  /// A 0 .. 1 score for the confidence engine: full marks at or below 0.5,
  /// zero at the gate.
  double get score {
    if (meanDeltaE2000 <= 0.5) return 1;
    if (meanDeltaE2000 >= gate) return 0;
    return (gate - meanDeltaE2000) / (gate - 0.5);
  }

  @override
  String toString() => 'CcmQualityReport(mean: $meanDeltaE2000, '
      'max: $maxDeltaE2000, passes: $passes)';
}

/// A fitted matrix together with everything needed to judge it.
@immutable
final class CcmFitResult {
  const CcmFitResult({
    required this.ccm,
    required this.quality,
    required this.neutralGains,
    required this.exposureNormalisation,
  });

  final ColorCorrectionMatrix ccm;
  final CcmQualityReport quality;

  /// Channel gains derived from the chart's neutral row.
  final Vec3 neutralGains;

  /// Factor that put the chart measurement on the perfect-diffuser scale.
  final double exposureNormalisation;
}

/// Fits a camera-to-XYZ matrix from a reference chart.
///
/// The fit is a least squares problem with one linear equality constraint per
/// row: the matrix must map a neutral `(1, 1, 1)` onto the white point. Because
/// there is exactly one constraint and it is separable by row, each row has a
/// closed-form solution and no iterative solver, learning rate or convergence
/// check is involved:
///
/// ```text
/// G   = X^T X
/// a_u = G^-1 X^T y            unconstrained row
/// a   = a_u + G^-1 1 * (w_r - 1^T a_u) / (1^T G^-1 1)
/// ```
abstract final class CcmFitter {
  static CcmFitResult fit({
    required List<ChartPatch> patches,
    WhitePoint whitePoint = WhitePoint.d65,
    double gate = kCcmMeanDeltaEGate,
  }) {
    if (patches.length < kMinChartPatches) {
      throw ArgumentError.value(
        patches.length,
        'patches.length',
        'a fit needs at least $kMinChartPatches patches',
      );
    }
    final neutrals = patches.where((p) => p.isNeutral).toList();
    if (neutrals.length < kMinNeutralPatches) {
      throw ArgumentError.value(
        neutrals.length,
        'neutral patches',
        'at least $kMinNeutralPatches are needed to derive channel gains',
      );
    }

    final gains = neutralGainsOf(neutrals);

    // Put the measurement on the perfect-diffuser scale using the brightest
    // neutral patch, which has the best signal to noise of the row.
    final anchor = neutrals.reduce(
      (a, b) => b.reference.y > a.reference.y ? b : a,
    );
    final anchorGreen = anchor.measured.withGains(gains).green;
    if (anchorGreen <= 0) {
      throw ArgumentError.value(
        anchorGreen,
        'anchor patch green channel',
        'must be positive',
      );
    }
    final normalisation = anchor.reference.y / anchorGreen;

    final rows = <Vec3>[];
    for (var channel = 0; channel < 3; channel++) {
      rows.add(
        _fitRow(
          patches: patches,
          gains: gains,
          normalisation: normalisation,
          channel: channel,
          constrainedSum: whitePoint.xyz[channel],
        ),
      );
    }
    final matrix = Mat3(
      rows[0].x, rows[0].y, rows[0].z, //
      rows[1].x, rows[1].y, rows[1].z, //
      rows[2].x, rows[2].y, rows[2].z, //
    );
    final ccm = ColorCorrectionMatrix(
      matrix: matrix,
      whitePoint: whitePoint,
      source: CcmSource.chartFit,
    );

    return CcmFitResult(
      ccm: ccm,
      quality: qualityOf(
        ccm: ccm,
        patches: patches,
        gains: gains,
        normalisation: normalisation,
        gate: gate,
      ),
      neutralGains: gains,
      exposureNormalisation: normalisation,
    );
  }

  /// Channel gains from the neutral row, by least squares.
  ///
  /// Every neutral patch should read `R == G == B`, so for each channel
  /// `k_c = sum(c_jc * c_jG) / sum(c_jc^2)`. Using the whole row rather than a
  /// single white patch means one clipped or dusty patch cannot decide the
  /// result, and the expression naturally weights bright patches more, which is
  /// to say it weights by signal to noise. By construction `k_G == 1`.
  @visibleForTesting
  static Vec3 neutralGainsOf(List<ChartPatch> neutrals) {
    final numerator = <double>[0, 0, 0];
    final denominator = <double>[0, 0, 0];
    for (final patch in neutrals) {
      final c = patch.measured.asVec3;
      for (var channel = 0; channel < 3; channel++) {
        numerator[channel] += c[channel] * c.y;
        denominator[channel] += c[channel] * c[channel];
      }
    }
    for (var channel = 0; channel < 3; channel++) {
      if (denominator[channel] <= 0) {
        throw ArgumentError.value(
          channel,
          'channel',
          'neutral patches carry no signal in this channel',
        );
      }
    }
    return Vec3(
      numerator[0] / denominator[0],
      numerator[1] / denominator[1],
      numerator[2] / denominator[2],
    );
  }

  static Vec3 _fitRow({
    required List<ChartPatch> patches,
    required Vec3 gains,
    required double normalisation,
    required int channel,
    required double constrainedSum,
  }) {
    // Normal equations. Both are accumulated in one pass over the patches.
    final gram = List<List<double>>.generate(3, (_) => <double>[0, 0, 0]);
    final xty = <double>[0, 0, 0];
    for (final patch in patches) {
      final x = patch.measured.withGains(gains).asVec3 * normalisation;
      final y = patch.reference.asVec3[channel];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          gram[i][j] += x[i] * x[j];
        }
        xty[i] += x[i] * y;
      }
    }
    final gramInverse = Mat3.fromRowMajor([
      ...gram[0],
      ...gram[1],
      ...gram[2],
    ]).inverse;

    final unconstrained = gramInverse.apply(Vec3.fromList(xty));
    final gramInverseOnes = gramInverse.apply(Vec3.ones);
    final denominator = gramInverseOnes.sum;
    if (denominator.abs() < kMinInvertibleDeterminant) {
      throw StateError(
        'the constraint is degenerate for channel $channel; the chart '
        'measurement carries no neutral direction',
      );
    }
    final correction = (constrainedSum - unconstrained.sum) / denominator;
    return unconstrained + gramInverseOnes * correction;
  }

  /// Per-patch residuals of a fitted matrix.
  @visibleForTesting
  static CcmQualityReport qualityOf({
    required ColorCorrectionMatrix ccm,
    required List<ChartPatch> patches,
    required Vec3 gains,
    required double normalisation,
    double gate = kCcmMeanDeltaEGate,
  }) {
    final residuals = <PatchResidual>[];
    var sum = 0.0;
    var max = 0.0;
    for (final patch in patches) {
      final corrected = ccm.toXyz(
        patch.measured.withGains(gains).scaled(normalisation),
      );
      final measuredLab = corrected.toLab(whitePoint: ccm.whitePoint);
      final referenceLab = patch.reference.toLab(whitePoint: ccm.whitePoint);
      final deltaE = DeltaE2000.between(
        reference: referenceLab,
        sample: measuredLab,
      ).deltaE;
      residuals.add(
        PatchResidual(
          patchId: patch.id,
          deltaE2000: deltaE,
          measuredLab: measuredLab,
          referenceLab: referenceLab,
        ),
      );
      sum += deltaE;
      if (deltaE > max) max = deltaE;
    }
    return CcmQualityReport(
      meanDeltaE2000: sum / patches.length,
      maxDeltaE2000: max,
      residuals: residuals,
      gate: gate,
    );
  }
}
