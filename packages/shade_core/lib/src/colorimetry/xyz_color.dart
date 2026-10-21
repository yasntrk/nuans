import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/constants.dart';

/// CIE 1931 tristimulus values, normalised so that `Y == 1` corresponds to a
/// perfect diffuser under the capture illuminant.
///
/// This is the only space in which this package ever averages or mixes colours.
/// Lab is perceptually non-linear, so averaging there biases the result; XYZ is
/// linear in radiometric power, so a mean of XYZ is the mean of what the sensor
/// actually saw.
@immutable
final class XyzColor {
  const XyzColor(this.x, this.y, this.z);

  /// The weighted mean of several colours, in linear XYZ.
  ///
  /// Weights must be non-negative and sum to one. That is checked rather than
  /// assumed: weights that do not sum to one silently change the lightness of
  /// the result, which would look like a colour error rather than a bug.
  factory XyzColor.weightedMean(
    List<XyzColor> colors,
    List<double> weights,
  ) {
    if (colors.length != weights.length) {
      throw ArgumentError('colors and weights must have the same length');
    }
    if (colors.isEmpty) {
      throw ArgumentError.value(0, 'colors.length', 'must not be empty');
    }
    var weightSum = 0.0;
    for (final w in weights) {
      if (w < 0) {
        throw ArgumentError.value(w, 'weights', 'must be non-negative');
      }
      weightSum += w;
    }
    if ((weightSum - 1).abs() > 1e-9) {
      throw ArgumentError.value(weightSum, 'weights sum', 'must be 1.0');
    }
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    for (var i = 0; i < colors.length; i++) {
      x += colors[i].x * weights[i];
      y += colors[i].y * weights[i];
      z += colors[i].z * weights[i];
    }
    return XyzColor(x, y, z);
  }

  factory XyzColor.fromVec3(Vec3 v) => XyzColor(v.x, v.y, v.z);

  static const XyzColor black = XyzColor(0, 0, 0);

  final double x;
  final double y;
  final double z;

  Vec3 get asVec3 => Vec3(x, y, z);

  /// CIE 1931 chromaticity coordinates. Returns `null` for a black sample,
  /// where chromaticity is undefined rather than zero.
  ({double x, double y})? get chromaticity {
    final sum = x + y + z;
    if (sum <= 0) return null;
    return (x: x / sum, y: y / sum);
  }

  XyzColor scaled(double factor) =>
      XyzColor(x * factor, y * factor, z * factor);

  XyzColor operator +(XyzColor other) =>
      XyzColor(x + other.x, y + other.y, z + other.z);

  /// Converts to CIELAB (CIE 15:2004).
  LabColor toLab({WhitePoint whitePoint = WhitePoint.d65}) {
    final fy = labTransfer(y / whitePoint.xyz.y);
    return LabColor(
      116 * fy - 16,
      500 * (labTransfer(x / whitePoint.xyz.x) - fy),
      200 * (fy - labTransfer(z / whitePoint.xyz.z)),
    );
  }

  /// The CIE 15:2004 lightness transfer function `f(t)`.
  ///
  /// Public because three places need it: this conversion, [LabColor.toXyz] in
  /// the other direction, and the region reducer, which computes `L*` per
  /// sample without building a whole Lab value for each one.
  ///
  /// `dart:math` has no cube root, and `pow` is only defined for a
  /// non-negative base with a fractional exponent. Normalised tristimulus
  /// values are never negative in this pipeline, and the linear segment covers
  /// everything at or below the breakpoint, so `pow` is safe here.
  static double labTransfer(double t) => t > kLabEpsilon
      ? math.pow(t, 1 / 3).toDouble()
      : (kLabKappa * t + 16) / 116;

  /// The inverse of [labTransfer]. Used by [LabColor.toXyz].
  static double inverseLabTransfer(double ft) {
    final cubed = ft * ft * ft;
    return cubed > kLabEpsilon ? cubed : (116 * ft - 16) / kLabKappa;
  }

  @override
  bool operator ==(Object other) =>
      other is XyzColor && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'XyzColor($x, $y, $z)';
}
