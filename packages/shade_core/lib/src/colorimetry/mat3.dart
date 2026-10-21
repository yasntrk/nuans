import 'package:meta/meta.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/constants.dart';

/// An immutable row-major 3x3 matrix.
///
/// Deliberately minimal: colour science needs multiplication, application to a
/// vector and inversion, and nothing else. Keeping it this small means the
/// whole type is covered by a handful of tests.
@immutable
final class Mat3 {
  const Mat3(
    this.m00,
    this.m01,
    this.m02,
    this.m10,
    this.m11,
    this.m12,
    this.m20,
    this.m21,
    this.m22,
  );

  /// Builds a matrix from nine row-major values.
  factory Mat3.fromRowMajor(List<double> values) {
    if (values.length != 9) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'a Mat3 needs exactly nine row-major values',
      );
    }
    return Mat3(
      values[0], values[1], values[2], //
      values[3], values[4], values[5], //
      values[6], values[7], values[8], //
    );
  }

  /// Builds a diagonal matrix. This is how per-channel gains enter a transform.
  factory Mat3.diagonal(Vec3 diagonal) => Mat3(
        diagonal.x, 0, 0, //
        0, diagonal.y, 0, //
        0, 0, diagonal.z, //
      );

  /// Builds a matrix from three column vectors.
  factory Mat3.columns(Vec3 c0, Vec3 c1, Vec3 c2) => Mat3(
        c0.x, c1.x, c2.x, //
        c0.y, c1.y, c2.y, //
        c0.z, c1.z, c2.z, //
      );

  static const Mat3 identity = Mat3(
    1, 0, 0, //
    0, 1, 0, //
    0, 0, 1, //
  );

  final double m00;
  final double m01;
  final double m02;
  final double m10;
  final double m11;
  final double m12;
  final double m20;
  final double m21;
  final double m22;

  /// Matrix-vector product.
  Vec3 apply(Vec3 v) => Vec3(
        m00 * v.x + m01 * v.y + m02 * v.z,
        m10 * v.x + m11 * v.y + m12 * v.z,
        m20 * v.x + m21 * v.y + m22 * v.z,
      );

  /// Matrix product, `this * other`.
  Mat3 operator *(Mat3 o) => Mat3(
        m00 * o.m00 + m01 * o.m10 + m02 * o.m20,
        m00 * o.m01 + m01 * o.m11 + m02 * o.m21,
        m00 * o.m02 + m01 * o.m12 + m02 * o.m22,
        m10 * o.m00 + m11 * o.m10 + m12 * o.m20,
        m10 * o.m01 + m11 * o.m11 + m12 * o.m21,
        m10 * o.m02 + m11 * o.m12 + m12 * o.m22,
        m20 * o.m00 + m21 * o.m10 + m22 * o.m20,
        m20 * o.m01 + m21 * o.m11 + m22 * o.m21,
        m20 * o.m02 + m21 * o.m12 + m22 * o.m22,
      );

  Mat3 scaled(double s) => Mat3(
        m00 * s, m01 * s, m02 * s, //
        m10 * s, m11 * s, m12 * s, //
        m20 * s, m21 * s, m22 * s, //
      );

  Mat3 get transposed => Mat3(
        m00, m10, m20, //
        m01, m11, m21, //
        m02, m12, m22, //
      );

  double get determinant =>
      m00 * (m11 * m22 - m12 * m21) -
      m01 * (m10 * m22 - m12 * m20) +
      m02 * (m10 * m21 - m11 * m20);

  /// The inverse, computed from the adjugate.
  ///
  /// Throws [StateError] when the matrix is singular. Every inverse this
  /// package takes is of a colour matrix whose determinant is far from zero, so
  /// a singular matrix means corrupt calibration data rather than a hard case
  /// to handle gracefully.
  Mat3 get inverse {
    final det = determinant;
    if (det.abs() < kMinInvertibleDeterminant) {
      throw StateError('matrix is singular, determinant $det');
    }
    return Mat3(
      (m11 * m22 - m12 * m21) / det,
      (m02 * m21 - m01 * m22) / det,
      (m01 * m12 - m02 * m11) / det,
      (m12 * m20 - m10 * m22) / det,
      (m00 * m22 - m02 * m20) / det,
      (m02 * m10 - m00 * m12) / det,
      (m10 * m21 - m11 * m20) / det,
      (m01 * m20 - m00 * m21) / det,
      (m00 * m11 - m01 * m10) / det,
    );
  }

  /// Row sums, i.e. the image of `(1, 1, 1)`.
  ///
  /// For a white-point preserving matrix this equals the white point, which is
  /// the invariant the whole absolute-lightness chain rests on.
  Vec3 get rowSums => Vec3(
        m00 + m01 + m02,
        m10 + m11 + m12,
        m20 + m21 + m22,
      );

  List<double> toRowMajor() => [
        m00, m01, m02, //
        m10, m11, m12, //
        m20, m21, m22, //
      ];

  @override
  bool operator ==(Object other) =>
      other is Mat3 &&
      other.m00 == m00 &&
      other.m01 == m01 &&
      other.m02 == m02 &&
      other.m10 == m10 &&
      other.m11 == m11 &&
      other.m12 == m12 &&
      other.m20 == m20 &&
      other.m21 == m21 &&
      other.m22 == m22;

  @override
  int get hashCode =>
      Object.hashAll([m00, m01, m02, m10, m11, m12, m20, m21, m22]);

  @override
  String toString() => 'Mat3($m00, $m01, $m02, $m10, $m11, $m12, '
      '$m20, $m21, $m22)';
}
