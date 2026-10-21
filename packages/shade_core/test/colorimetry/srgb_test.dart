import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected values computed by `tools/spec_oracle/fixtures.py`.
void main() {
  group('sRGB transfer function', () {
    test('decodes mid grey', () {
      expect(Srgb.decode(0.5), closeTo(0.214041140482, 1e-12));
    });

    test('is continuous across the breakpoint', () {
      const breakpoint = kSrgbDecodeBreakpoint;
      final below = Srgb.decode(breakpoint - 1e-9);
      final above = Srgb.decode(breakpoint + 1e-9);
      expect((above - below).abs(), lessThan(1e-7));
    });

    test('pins the endpoints', () {
      expect(Srgb.decode(0), 0);
      expect(Srgb.decode(1), closeTo(1, 1e-15));
      expect(Srgb.encode(0), 0);
      expect(Srgb.encode(1), closeTo(1, 1e-15));
    });

    test('encode is the inverse of decode', () {
      for (final value in [0.0, 0.002, 0.01, 0.2, 0.5, 0.8, 1.0]) {
        expect(Srgb.encode(Srgb.decode(value)), closeTo(value, 1e-12));
      }
    });

    test('decodes an 8-bit triple', () {
      final v = Srgb.decode8Bit(255, 128, 0);
      expect(v.x, closeTo(1, 1e-15));
      expect(v.y, closeTo(Srgb.decode(128 / 255), 1e-15));
      expect(v.z, 0);
    });
  });

  group('sRGB matrix derived from primaries', () {
    test('maps a neutral exactly onto the white point', () {
      final sums = Srgb.linearToXyzD65.rowSums;
      expect(sums.x, closeTo(WhitePoint.d65.xyz.x, 1e-15));
      expect(sums.y, closeTo(WhitePoint.d65.xyz.y, 1e-15));
      expect(sums.z, closeTo(WhitePoint.d65.xyz.z, 1e-15));
    });

    test('agrees with the published seven-digit matrix', () {
      final derived = Srgb.linearToXyzD65.toRowMajor();
      final published = Srgb.publishedLinearToXyzD65.toRowMajor();
      for (var i = 0; i < 9; i++) {
        expect(derived[i], closeTo(published[i], 5e-8));
      }
    });

    test('the published matrix does NOT preserve the white point exactly', () {
      // This is why the matrix is derived rather than copied: the published
      // rounding would make encoded white convert to L* = 100.0000039.
      expect(
        Srgb.publishedLinearToXyzD65.rowSums.y,
        isNot(closeTo(1, 1e-9)),
      );
      expect(Srgb.publishedLinearToXyzD65.rowSums.y, closeTo(1, 1e-6));
    });

    test('round trips linear RGB through XYZ', () {
      const linear = Vec3(0.2, 0.5, 0.8);
      final back = Srgb.xyzD65ToLinear.apply(
        Srgb.linearToXyzD65.apply(linear),
      );
      expect(back.x, closeTo(linear.x, 1e-12));
      expect(back.y, closeTo(linear.y, 1e-12));
      expect(back.z, closeTo(linear.z, 1e-12));
    });
  });
}
