import 'dart:math' as math;

import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/constants.dart';

/// The sRGB colour space (IEC 61966-2-1).
///
/// Used on two paths:
///
/// * the processed capture path, where a locked HEIF or JPEG frame has to be
///   linearised before any colour maths can touch it;
/// * display encoding, when a measured colour has to be drawn on screen.
///
/// It is *not* used for RAW captures, which carry their own device matrix.
abstract final class Srgb {
  /// Primary chromaticities of sRGB.
  static const ({double x, double y}) redPrimary = (x: 0.6400, y: 0.3300);
  static const ({double x, double y}) greenPrimary = (x: 0.3000, y: 0.6000);
  static const ({double x, double y}) bluePrimary = (x: 0.1500, y: 0.0600);

  /// Linear sRGB to XYZ under D65.
  ///
  /// Derived from the primaries rather than copied from the published
  /// seven-digit matrix, because the derivation makes `M * (1, 1, 1)` equal the
  /// white point *exactly*. The published matrix does not: its rows sum to
  /// `Y = 1.0000001`, so encoded white would convert to `L* = 100.0000039`
  /// instead of 100, and the white-point preservation invariant that the
  /// absolute lightness chain depends on would hold only approximately. The two
  /// matrices agree to within 5e-8, which a test asserts.
  static final Mat3 linearToXyzD65 = rgbToXyzMatrix(
    red: redPrimary,
    green: greenPrimary,
    blue: bluePrimary,
    whitePoint: WhitePoint.d65,
  );

  /// XYZ under D65 to linear sRGB.
  static final Mat3 xyzD65ToLinear = linearToXyzD65.inverse;

  /// The published matrix, kept only as a cross-check for the derivation.
  static const Mat3 publishedLinearToXyzD65 = Mat3(
    0.4124564, 0.3575761, 0.1804375, //
    0.2126729, 0.7151522, 0.0721750, //
    0.0193339, 0.1191920, 0.9503041, //
  );

  /// Inverse electro-optical transfer function: encoded value to linear.
  ///
  /// Input and output are both in `[0, 1]`.
  static double decode(double encoded) => encoded <= kSrgbDecodeBreakpoint
      ? encoded / kSrgbLinearSlope
      : math
          .pow((encoded + kSrgbOffset) / (1 + kSrgbOffset), kSrgbExponent)
          .toDouble();

  /// Electro-optical transfer function: linear to encoded.
  static double encode(double linear) => linear <= kSrgbEncodeBreakpoint
      ? linear * kSrgbLinearSlope
      : (1 + kSrgbOffset) * math.pow(linear, 1 / kSrgbExponent).toDouble() -
          kSrgbOffset;

  /// Decodes an 8-bit encoded triple to linear.
  static Vec3 decode8Bit(int r, int g, int b) => Vec3(
        decode(r / 255),
        decode(g / 255),
        decode(b / 255),
      );
}

/// Builds the linear-RGB to XYZ matrix from primary chromaticities and a white
/// point, following the standard derivation.
///
/// The result satisfies `M * (1, 1, 1) == whitePoint.xyz` by construction,
/// which is the same invariant the fitted camera matrix is constrained to.
Mat3 rgbToXyzMatrix({
  required ({double x, double y}) red,
  required ({double x, double y}) green,
  required ({double x, double y}) blue,
  required WhitePoint whitePoint,
}) {
  Vec3 primaryXyz(({double x, double y}) c) =>
      Vec3(c.x / c.y, 1, (1 - c.x - c.y) / c.y);

  final r = primaryXyz(red);
  final g = primaryXyz(green);
  final b = primaryXyz(blue);
  final unscaled = Mat3.columns(r, g, b);
  final scale = unscaled.inverse.apply(whitePoint.xyz);
  return Mat3.columns(r * scale.x, g * scale.y, b * scale.z);
}
