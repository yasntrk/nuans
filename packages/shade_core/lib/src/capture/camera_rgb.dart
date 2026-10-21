import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/vec3.dart';

/// A linear camera-space triple: one Bayer 2x2 superpixel, black level removed
/// and normalised by the white level, so every component is in `[0, 1]`.
///
/// This is the only numeric form in which pixel data crosses from the native
/// capture layer into this package. It is *not* a colour yet: it has no
/// colorimetric meaning until a capture transform has been applied to it.
@immutable
final class CameraRgb {
  const CameraRgb(this.red, this.green, this.blue);

  factory CameraRgb.fromVec3(Vec3 v) => CameraRgb(v.x, v.y, v.z);

  const CameraRgb.neutral(double level)
      : red = level,
        green = level,
        blue = level;

  final double red;
  final double green;
  final double blue;

  Vec3 get asVec3 => Vec3(red, green, blue);

  double get maxChannel =>
      red > green ? (red > blue ? red : blue) : (green > blue ? green : blue);

  double get minChannel =>
      red < green ? (red < blue ? red : blue) : (green < blue ? green : blue);

  /// Applies per-channel gains. This is how the grey card correction is
  /// applied.
  CameraRgb withGains(Vec3 gains) => CameraRgb(
        red * gains.x,
        green * gains.y,
        blue * gains.z,
      );

  CameraRgb scaled(double factor) =>
      CameraRgb(red * factor, green * factor, blue * factor);

  @override
  bool operator ==(Object other) =>
      other is CameraRgb &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'CameraRgb($red, $green, $blue)';
}
