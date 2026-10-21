import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected values computed by `tools/spec_oracle/fixtures.py`, using the
/// matrix derived from the sRGB primaries.
void main() {
  LabColor labOfEncodedSrgb(double r, double g, double b) => XyzColor.fromVec3(
        Srgb.linearToXyzD65.apply(
          Vec3(Srgb.decode(r), Srgb.decode(g), Srgb.decode(b)),
        ),
      ).toLab();

  group('XYZ to Lab', () {
    test('encoded white is exactly L* 100, a* 0, b* 0', () {
      final lab = labOfEncodedSrgb(1, 1, 1);
      expect(lab.lightness, closeTo(100, 1e-12));
      expect(lab.a, closeTo(0, 1e-12));
      expect(lab.b, closeTo(0, 1e-12));
    });

    test('black is the origin', () {
      final lab = labOfEncodedSrgb(0, 0, 0);
      expect(lab.lightness, 0);
      expect(lab.a, 0);
      expect(lab.b, 0);
    });

    test('mid grey is neutral at L* 53.3889647', () {
      final lab = labOfEncodedSrgb(0.5, 0.5, 0.5);
      expect(lab.lightness, closeTo(53.3889647, 1e-6));
      expect(lab.a, closeTo(0, 1e-12));
      expect(lab.b, closeTo(0, 1e-12));
    });

    test('primary red', () {
      final lab = labOfEncodedSrgb(1, 0, 0);
      expect(lab.lightness, closeTo(53.2407889, 1e-6));
      expect(lab.a, closeTo(80.0924943, 1e-6));
      expect(lab.b, closeTo(67.2031914, 1e-6));
    });

    test('a tooth-like colour', () {
      final lab = labOfEncodedSrgb(0.84, 0.80, 0.71);
      expect(lab.lightness, closeTo(82.2986294, 1e-6));
      expect(lab.a, closeTo(-0.2668728, 1e-6));
      expect(lab.b, closeTo(12.7115798, 1e-6));
    });

    test('an 18% neutral sits at L* 49.4961076', () {
      final xyz = XyzColor(
        WhitePoint.d65.xyz.x * 0.18,
        0.18,
        WhitePoint.d65.xyz.z * 0.18,
      );
      expect(xyz.toLab().lightness, closeTo(49.4961076101, 1e-9));
    });

    test('uses the linear segment below the breakpoint', () {
      // Just under epsilon the transfer must be linear, not a cube root.
      const t = kLabEpsilon / 2;
      expect(
        XyzColor.labTransfer(t),
        closeTo((kLabKappa * t + 16) / 116, 1e-15),
      );
      expect(
        XyzColor.labTransfer(kLabEpsilon * 2),
        isNot(closeTo((kLabKappa * kLabEpsilon * 2 + 16) / 116, 1e-9)),
      );
    });

    test('the transfer function and its inverse round trip', () {
      for (final t in [0.0, 1e-5, kLabEpsilon, 0.01, 0.18, 0.5, 1.0, 1.2]) {
        expect(
          XyzColor.inverseLabTransfer(XyzColor.labTransfer(t)),
          closeTo(t, 1e-12),
        );
      }
    });
  });

  group('Lab to XYZ', () {
    test('round trips a tooth-like colour', () {
      const lab = LabColor(82.2986294, -0.2668728, 12.7115798);
      final back = lab.toXyz().toLab();
      expect(back.lightness, closeTo(lab.lightness, 1e-10));
      expect(back.a, closeTo(lab.a, 1e-10));
      expect(back.b, closeTo(lab.b, 1e-10));
    });

    test('round trips a very dark colour through the linear segment', () {
      const lab = LabColor(2, 0.4, -0.3);
      final back = lab.toXyz().toLab();
      expect(back.lightness, closeTo(lab.lightness, 1e-10));
      expect(back.a, closeTo(lab.a, 1e-10));
      expect(back.b, closeTo(lab.b, 1e-10));
    });

    test('white maps to the white point', () {
      final xyz = LabColor.white.toXyz();
      expect(xyz.x, closeTo(WhitePoint.d65.xyz.x, 1e-12));
      expect(xyz.y, closeTo(1, 1e-12));
      expect(xyz.z, closeTo(WhitePoint.d65.xyz.z, 1e-12));
    });
  });

  group('LCh', () {
    test('converts a tooth-like colour and back', () {
      const lab = LabColor(82.2986294, -0.2668728, 12.7115798);
      final lch = lab.toLch();
      expect(lch.lightness, lab.lightness);
      expect(lch.chroma, closeTo(12.7143809170, 1e-9));
      expect(lch.hueDegrees, closeTo(91.2027174746, 1e-9));
      final back = lch.toLab();
      expect(back.a, closeTo(lab.a, 1e-10));
      expect(back.b, closeTo(lab.b, 1e-10));
    });

    test('hue of a neutral is pinned to zero rather than undefined', () {
      expect(const LabColor(50, 0, 0).hueDegrees, 0);
      expect(const LabColor(50, 0, 0).chroma, 0);
    });

    test('hue is reported in 0 .. 360', () {
      expect(const LabColor(50, 1, -1).hueDegrees, closeTo(315, 1e-9));
      expect(const LabColor(50, -1, -1).hueDegrees, closeTo(225, 1e-9));
    });
  });

  group('XyzColor.weightedMean', () {
    test('averages in linear space', () {
      final mean = XyzColor.weightedMean(
        const [XyzColor(0.2, 0.2, 0.2), XyzColor(0.6, 0.6, 0.6)],
        const [0.5, 0.5],
      );
      expect(mean.y, closeTo(0.4, 1e-15));
    });

    test('rejects weights that do not sum to one', () {
      expect(
        () => XyzColor.weightedMean(
          const [XyzColor(0.2, 0.2, 0.2), XyzColor(0.6, 0.6, 0.6)],
          const [0.5, 0.4],
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative weights', () {
      expect(
        () => XyzColor.weightedMean(
          const [XyzColor(0.2, 0.2, 0.2), XyzColor(0.6, 0.6, 0.6)],
          const [1.5, -0.5],
        ),
        throwsArgumentError,
      );
    });
  });
}
