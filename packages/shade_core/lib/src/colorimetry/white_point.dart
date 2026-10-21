import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/vec3.dart';

/// A reference white, normalised so that `Y == 1` for a perfect diffuser.
///
/// Values are the ASTM E308 tristimulus values. CIE 15:2004 lists marginally
/// different numbers (0.95043 / 1.08890 for D65); the difference is about
/// 0.004%, far below anything CIEDE2000 can resolve. What matters is picking
/// one source and staying with it everywhere, which here is ASTM E308.
@immutable
final class WhitePoint {
  const WhitePoint({required this.name, required this.xyz});

  /// D65, 2 degree observer. The measurement space of this application.
  static const WhitePoint d65 = WhitePoint(
    name: 'D65',
    xyz: Vec3(0.95047, 1, 1.08883),
  );

  /// D50, 2 degree observer. Reference charts are often published under it.
  static const WhitePoint d50 = WhitePoint(
    name: 'D50',
    xyz: Vec3(0.96422, 1, 0.82521),
  );

  final String name;
  final Vec3 xyz;

  /// CIE 1931 chromaticity coordinates of this white.
  ({double x, double y}) get chromaticity {
    final sum = xyz.sum;
    return (x: xyz.x / sum, y: xyz.y / sum);
  }

  @override
  bool operator ==(Object other) =>
      other is WhitePoint && other.name == name && other.xyz == xyz;

  @override
  int get hashCode => Object.hash(name, xyz);

  @override
  String toString() => 'WhitePoint($name, $xyz)';
}
