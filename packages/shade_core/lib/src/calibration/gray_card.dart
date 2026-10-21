import 'package:meta/meta.dart';
import 'package:shade_core/src/calibration/color_correction_matrix.dart';
import 'package:shade_core/src/capture/camera_rgb.dart';
import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';

/// The per-capture correction derived from the neutral card next to the tooth.
///
/// Two separate jobs, often confused:
///
/// * the **gains** remove the colour of the light, by forcing the card to read
///   neutral in camera space;
/// * the **exposure scale** fixes absolute lightness, by forcing the card's
///   luminance to its known reflectance.
///
/// The second is what makes two captures of the same tooth under different
/// lights and different shutter speeds produce the same `L*`.
@immutable
final class GrayCardCorrection {
  const GrayCardCorrection({
    required this.gains,
    required this.exposureScale,
    required this.cardMeasurement,
    required this.cardReflectanceY,
  });

  /// Derives the correction from a card measurement.
  ///
  /// [cardMedian] should be the per-channel median of the card region, not its
  /// mean: dust, scratches and the odd specular fleck leave the median alone.
  ///
  /// The gains are anchored on green because the Bayer pattern samples green
  /// twice as often as red or blue, so green has the best signal to noise and
  /// anchoring there amplifies noise the least.
  factory GrayCardCorrection.fromMeasurement({
    required CameraRgb cardMedian,
    double cardReflectanceY = kGrayCardReflectanceY,
  }) {
    if (cardMedian.minChannel <= 0) {
      throw ArgumentError.value(
        cardMedian,
        'cardMedian',
        'every channel must carry signal to derive gains',
      );
    }
    if (cardReflectanceY <= 0 || cardReflectanceY > 1) {
      throw ArgumentError.value(
        cardReflectanceY,
        'cardReflectanceY',
        'must be within 0 .. 1 relative to a perfect diffuser',
      );
    }
    return GrayCardCorrection(
      gains: Vec3(
        cardMedian.green / cardMedian.red,
        1,
        cardMedian.green / cardMedian.blue,
      ),
      exposureScale: cardReflectanceY / cardMedian.green,
      cardMeasurement: cardMedian,
      cardReflectanceY: cardReflectanceY,
    );
  }

  /// Per-channel von Kries gains in camera space. The green gain is always 1.
  final Vec3 gains;

  /// Scale that puts the card's luminance at [cardReflectanceY].
  final double exposureScale;

  final CameraRgb cardMeasurement;
  final double cardReflectanceY;

  /// The card after the gains, which is neutral by construction.
  CameraRgb get balancedCard => cardMeasurement.withGains(gains);

  @override
  String toString() => 'GrayCardCorrection(gains: $gains, '
      'exposureScale: $exposureScale)';
}

/// The single linear map from camera space to tristimulus values for one
/// capture: `T = exposureScale * ccm * diag(gains)`, optionally pre-multiplied
/// by the relative mode correction.
///
/// One transform per capture, shared by every region of it. That is the only
/// reason the three tooth bands can be compared with each other and with the
/// shade tab in the same frame.
@immutable
final class CaptureTransform {
  const CaptureTransform({
    required this.matrix,
    required this.ccm,
    required this.grayCard,
    required this.hasRelativeModeCorrection,
  });

  /// Composes the transform.
  ///
  /// [relativeModeCorrection] comes from
  /// `ChromaticAdaptation.coneRatioCorrection` and is applied last, in
  /// tristimulus space, because it corrects a residual of the whole capture
  /// rather than a camera channel imbalance.
  factory CaptureTransform.from({
    required ColorCorrectionMatrix ccm,
    required GrayCardCorrection grayCard,
    Mat3? relativeModeCorrection,
  }) {
    final base = ccm.matrix * Mat3.diagonal(grayCard.gains);
    final scaled = base.scaled(grayCard.exposureScale);
    return CaptureTransform(
      matrix: relativeModeCorrection == null
          ? scaled
          : relativeModeCorrection * scaled,
      ccm: ccm,
      grayCard: grayCard,
      hasRelativeModeCorrection: relativeModeCorrection != null,
    );
  }

  final Mat3 matrix;
  final ColorCorrectionMatrix ccm;
  final GrayCardCorrection grayCard;
  final bool hasRelativeModeCorrection;

  XyzColor toXyz(CameraRgb rgb) => XyzColor.fromVec3(matrix.apply(rgb.asVec3));

  /// The luminance this transform assigns to a camera triple.
  double luminanceOf(CameraRgb rgb) => toXyz(rgb).y;

  /// Whether the chain is self-consistent: feeding the grey card back through
  /// the transform must return exactly the card's own reflectance.
  ///
  /// Note that `matrix.rowSums.y` is *not* the luminance of a perfect diffuser
  /// here, which is an easy mistake to make. The row sums are the image of the
  /// camera triple `(1, 1, 1)`, and after the von Kries gains that triple is no
  /// longer neutral. The perfect diffuser in camera space is the card
  /// measurement divided by its reflectance.
  bool get isSelfConsistent =>
      (luminanceOf(grayCard.cardMeasurement) - grayCard.cardReflectanceY)
          .abs() <=
      kWhitePointPreservationTolerance;

  @override
  String toString() => 'CaptureTransform(${ccm.source.name}, '
      'relative: $hasRelativeModeCorrection)';
}
