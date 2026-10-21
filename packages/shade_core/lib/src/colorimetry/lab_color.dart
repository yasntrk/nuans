import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';

/// CIELAB coordinates under a stated white point, D65 2 degree by default.
///
/// The measurement space of the whole application. Note that this type carries
/// no illuminant of its own: two [LabColor] values are only comparable when
/// they were produced under the same white point, which the pipeline guarantees
/// by using a single capture transform for every region of a capture.
@immutable
final class LabColor {
  const LabColor(this.lightness, this.a, this.b);

  /// Perfect diffuse white under any white point.
  static const LabColor white = LabColor(100, 0, 0);

  static const LabColor black = LabColor(0, 0, 0);

  /// `L*`, 0 for black and 100 for a perfect diffuser.
  final double lightness;

  /// `a*`, positive towards red, negative towards green.
  final double a;

  /// `b*`, positive towards yellow, negative towards blue.
  final double b;

  /// `C*`, the chroma of plain CIELAB.
  ///
  /// Not the `C'` of CIEDE2000, which applies the `G` rolloff first. The
  /// difference matters near the neutral axis, so CIEDE2000 computes its own.
  double get chroma => math.sqrt(a * a + b * b);

  /// `h`, hue angle in degrees, in `[0, 360)`.
  double get hueDegrees {
    if (a == 0 && b == 0) return 0;
    return (math.atan2(b, a) * 180 / math.pi) % 360;
  }

  LchColor toLch() => LchColor(lightness, chroma, hueDegrees);

  /// Converts back to tristimulus values under [whitePoint].
  XyzColor toXyz({WhitePoint whitePoint = WhitePoint.d65}) {
    final fy = (lightness + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;
    return XyzColor(
      XyzColor.inverseLabTransfer(fx) * whitePoint.xyz.x,
      XyzColor.inverseLabTransfer(fy) * whitePoint.xyz.y,
      XyzColor.inverseLabTransfer(fz) * whitePoint.xyz.z,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LabColor &&
      other.lightness == lightness &&
      other.a == a &&
      other.b == b;

  @override
  int get hashCode => Object.hash(lightness, a, b);

  @override
  String toString() => 'LabColor($lightness, $a, $b)';
}

/// The cylindrical form of CIELAB.
///
/// Carried through to the user interface because clinicians think in value,
/// chroma and hue rather than in `a*` and `b*`.
@immutable
final class LchColor {
  const LchColor(this.lightness, this.chroma, this.hueDegrees);

  final double lightness;
  final double chroma;
  final double hueDegrees;

  LabColor toLab() {
    final radians = hueDegrees * math.pi / 180;
    return LabColor(
      lightness,
      chroma * math.cos(radians),
      chroma * math.sin(radians),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LchColor &&
      other.lightness == lightness &&
      other.chroma == chroma &&
      other.hueDegrees == hueDegrees;

  @override
  int get hashCode => Object.hash(lightness, chroma, hueDegrees);

  @override
  String toString() => 'LchColor($lightness, $chroma, $hueDegrees)';
}
