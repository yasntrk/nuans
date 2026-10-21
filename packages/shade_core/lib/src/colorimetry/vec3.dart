import 'package:meta/meta.dart';

/// An immutable three-component column vector.
///
/// Used for everything that is three numbers and is not yet a colour: camera
/// channel gains, Bradford cone responses, matrix rows and columns.
@immutable
final class Vec3 {
  const Vec3(this.x, this.y, this.z);

  const Vec3.all(double value)
      : x = value,
        y = value,
        z = value;

  /// Builds a vector from a three-element list.
  factory Vec3.fromList(List<double> values) {
    if (values.length != 3) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'a Vec3 needs exactly three components',
      );
    }
    return Vec3(values[0], values[1], values[2]);
  }

  static const Vec3 zero = Vec3(0, 0, 0);
  static const Vec3 ones = Vec3.all(1);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  Vec3 operator *(double scalar) => Vec3(x * scalar, y * scalar, z * scalar);

  /// Component-wise product. This is how channel gains are applied.
  Vec3 hadamard(Vec3 other) => Vec3(x * other.x, y * other.y, z * other.z);

  /// Component-wise quotient.
  Vec3 divideBy(Vec3 other) => Vec3(x / other.x, y / other.y, z / other.z);

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  double get sum => x + y + z;

  double get maxComponent => x > y ? (x > z ? x : z) : (y > z ? y : z);

  double get minComponent => x < y ? (x < z ? x : z) : (y < z ? y : z);

  double operator [](int index) => switch (index) {
        0 => x,
        1 => y,
        2 => z,
        _ => throw RangeError.index(index, this, 'index', null, 3),
      };

  List<double> toList() => [x, y, z];

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}
