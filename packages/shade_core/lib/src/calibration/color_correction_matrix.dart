import 'package:meta/meta.dart';

import 'package:shade_core/src/capture/camera_rgb.dart';
import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';

/// Where a colour correction matrix came from, which decides how much the
/// measurement can be trusted.
enum CcmSource {
  /// Fitted in the app from a 24-patch reference chart shot on this device.
  chartFit,

  /// Taken from the RAW file's `ForwardMatrix1`. A manufacturer average from
  /// one sample device, so it carries no unit-to-unit variation.
  dngForwardMatrix,

  /// Inverted from the RAW file's `ColorMatrix1`. Weaker again than a forward
  /// matrix, because the inversion amplifies its own approximation.
  dngColorMatrixInverse,

  /// The standard sRGB matrix, used on the processed capture path where the
  /// values are no longer camera-native.
  srgbProcessed,
}

/// A linear map from camera space to tristimulus values.
@immutable
final class ColorCorrectionMatrix {
  const ColorCorrectionMatrix({
    required this.matrix,
    required this.whitePoint,
    required this.source,
  });

  final Mat3 matrix;
  final WhitePoint whitePoint;
  final CcmSource source;

  XyzColor toXyz(CameraRgb rgb) => XyzColor.fromVec3(matrix.apply(rgb.asVec3));

  /// Whether a neutral camera triple maps onto the white point.
  ///
  /// The whole absolute lightness chain rests on this: it is what makes the
  /// grey card correction produce `a* = b* = 0` exactly, and what lets the
  /// exposure scale be derived from the green channel alone.
  bool get preservesWhitePoint {
    final sums = matrix.rowSums;
    final target = whitePoint.xyz;
    return (sums.x - target.x).abs() <= kWhitePointPreservationTolerance &&
        (sums.y - target.y).abs() <= kWhitePointPreservationTolerance &&
        (sums.z - target.z).abs() <= kWhitePointPreservationTolerance;
  }

  @override
  String toString() =>
      'ColorCorrectionMatrix(${source.name}, ${whitePoint.name})';
}
