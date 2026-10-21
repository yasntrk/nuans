import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';

/// Von Kries chromatic adaptation in the Bradford cone space.
///
/// Two jobs in this application:
///
/// * adapting published reference values from D50 to the D65 measurement
///   space (section 6.4 of the specification);
/// * applying the relative mode correction, where a measured shade tab is
///   compared against its library value and the residual is removed from the
///   whole capture (section 9).
abstract final class ChromaticAdaptation {
  /// The Bradford cone response matrix.
  static const Mat3 bradford = Mat3(
    0.8951, 0.2664, -0.1614, //
    -0.7502, 1.7135, 0.0367, //
    0.0389, -0.0685, 1.0296, //
  );

  /// The inverse Bradford matrix.
  ///
  /// Computed rather than transcribed: a hand-copied inverse is a silent
  /// transcription risk, while `bradford * bradfordInverse == identity` is a
  /// single test.
  static final Mat3 bradfordInverse = bradford.inverse;

  /// The adaptation matrix from [source] to [destination].
  ///
  /// Build it once and reuse it: callers that adapt thousands of samples must
  /// not call this per sample, because it inverts a matrix each time.
  static Mat3 matrixFor({
    required WhitePoint source,
    required WhitePoint destination,
  }) {
    final from = bradford.apply(source.xyz);
    final to = bradford.apply(destination.xyz);
    return bradfordInverse * Mat3.diagonal(to.divideBy(from)) * bradford;
  }

  /// Adapts a single colour. Convenience for one-off conversions.
  static XyzColor adapt(
    XyzColor color, {
    required WhitePoint source,
    required WhitePoint destination,
  }) =>
      XyzColor.fromVec3(
        matrixFor(source: source, destination: destination).apply(color.asVec3),
      );

  /// A correction that maps [measured] onto [expected] in cone space.
  ///
  /// This is the relative mode correction. Per-channel cone ratios are clamped
  /// to [kRelativeModeGainMin] .. [kRelativeModeGainMax] so that a misread
  /// shade tab can shift the capture by at most about 10%.
  ///
  /// The correction is multiplicative because the dominant global error mode is
  /// an illumination or exposure error, which is physically multiplicative.
  /// Subtracting a difference in Lab instead would introduce a hue shift that
  /// corresponds to no physical error at all.
  static Mat3 coneRatioCorrection({
    required XyzColor measured,
    required XyzColor expected,
    double minGain = kRelativeModeGainMin,
    double maxGain = kRelativeModeGainMax,
  }) {
    final from = bradford.apply(measured.asVec3);
    final to = bradford.apply(expected.asVec3);
    if (from.minComponent <= 0) {
      throw ArgumentError.value(
        measured,
        'measured',
        'cone responses must be positive to form a ratio correction',
      );
    }
    final ratios = Vec3(
      _clamp(to.x / from.x, minGain, maxGain),
      _clamp(to.y / from.y, minGain, maxGain),
      _clamp(to.z / from.z, minGain, maxGain),
    );
    return bradfordInverse * Mat3.diagonal(ratios) * bradford;
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}
