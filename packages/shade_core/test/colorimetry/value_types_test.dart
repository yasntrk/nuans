import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  group('WhitePoint', () {
    test('reports its chromaticity', () {
      final d65 = WhitePoint.d65.chromaticity;
      // x and y of D65 under the ASTM E308 tristimulus values.
      expect(d65.x, closeTo(0.3127, 1e-4));
      expect(d65.y, closeTo(0.3290, 1e-4));
      final d50 = WhitePoint.d50.chromaticity;
      expect(d50.x, closeTo(0.3457, 1e-4));
      expect(d50.y, closeTo(0.3585, 1e-4));
    });

    test('value equality and printing', () {
      // Deliberately the constructor on one side and the named constant on
      // the other: that is what makes this a test of value equality rather
      // than of identity. use_named_constants would make it a tautology.
      expect(
        // ignore: use_named_constants
        const WhitePoint(name: 'D65', xyz: Vec3(0.95047, 1, 1.08883)),
        WhitePoint.d65,
      );
      expect(WhitePoint.d65, isNot(WhitePoint.d50));
      expect(WhitePoint.d65.hashCode, WhitePoint.d65.hashCode);
      expect(WhitePoint.d65.toString(), contains('D65'));
    });
  });

  group('XyzColor', () {
    test('chromaticity is undefined for black, not zero', () {
      // Returning (0, 0) would place black at a real chromaticity, which the
      // grey card validator would then happily evaluate.
      expect(XyzColor.black.chromaticity, isNull);
      expect(const XyzColor(0.4, 0.5, 0.3).chromaticity, isNotNull);
    });

    test('scales and adds', () {
      const colour = XyzColor(0.2, 0.4, 0.6);
      expect(colour.scaled(2), const XyzColor(0.4, 0.8, 1.2));
      expect(
        colour + const XyzColor(0.1, 0.1, 0.1),
        const XyzColor(0.30000000000000004, 0.5, 0.7),
      );
    });

    test('converts to and from a vector', () {
      const colour = XyzColor(0.2, 0.4, 0.6);
      expect(colour.asVec3, const Vec3(0.2, 0.4, 0.6));
      expect(XyzColor.fromVec3(const Vec3(0.2, 0.4, 0.6)), colour);
    });

    test('value equality and printing', () {
      expect(const XyzColor(1, 2, 3), const XyzColor(1, 2, 3));
      expect(
        const XyzColor(1, 2, 3).hashCode,
        const XyzColor(1, 2, 3).hashCode,
      );
      expect(const XyzColor(1, 2, 3), isNot(const XyzColor(1, 2, 4)));
      expect(const XyzColor(1, 2, 3).toString(), contains('XyzColor'));
    });

    test('refuses a mismatched weight list', () {
      expect(
        () =>
            XyzColor.weightedMean(const [XyzColor(1, 1, 1)], const [0.5, 0.5]),
        throwsArgumentError,
      );
      expect(
        () => XyzColor.weightedMean(const [], const []),
        throwsArgumentError,
      );
    });
  });

  group('LabColor and LchColor', () {
    test('value equality and printing', () {
      expect(const LabColor(50, 1, 2), const LabColor(50, 1, 2));
      expect(
        const LabColor(50, 1, 2).hashCode,
        const LabColor(50, 1, 2).hashCode,
      );
      expect(const LabColor(50, 1, 2), isNot(const LabColor(50, 1, 3)));
      expect(const LabColor(50, 1, 2).toString(), contains('LabColor'));
      expect(const LchColor(50, 1, 2), const LchColor(50, 1, 2));
      expect(
        const LchColor(50, 1, 2).hashCode,
        const LchColor(50, 1, 2).hashCode,
      );
      expect(const LchColor(50, 1, 2), isNot(const LchColor(50, 1, 3)));
      expect(const LchColor(50, 1, 2).toString(), contains('LchColor'));
    });

    test('the named constants are what they say', () {
      expect(LabColor.white.lightness, 100);
      expect(LabColor.white.chroma, 0);
      // ignore: use_named_constants
      expect(LabColor.black, const LabColor(0, 0, 0));
    });
  });

  group('CameraRgb', () {
    test('finds its extremes', () {
      const triple = CameraRgb(0.3, 0.7, 0.5);
      expect(triple.maxChannel, 0.7);
      expect(triple.minChannel, 0.3);
      expect(const CameraRgb(0.9, 0.2, 0.5).maxChannel, 0.9);
      expect(const CameraRgb(0.2, 0.5, 0.9).maxChannel, 0.9);
      expect(const CameraRgb(0.9, 0.5, 0.2).minChannel, 0.2);
      expect(const CameraRgb(0.5, 0.2, 0.9).minChannel, 0.2);
    });

    test('applies gains and scales', () {
      const triple = CameraRgb(0.2, 0.4, 0.5);
      expect(
        triple.withGains(const Vec3(2, 1, 0.5)),
        const CameraRgb(0.4, 0.4, 0.25),
      );
      expect(triple.scaled(2), const CameraRgb(0.4, 0.8, 1));
    });

    test('a neutral has three equal channels', () {
      const neutral = CameraRgb.neutral(0.18);
      expect(neutral.red, 0.18);
      expect(neutral.green, 0.18);
      expect(neutral.blue, 0.18);
      expect(neutral.maxChannel, neutral.minChannel);
    });

    test('converts to and from a vector', () {
      expect(
        CameraRgb.fromVec3(const Vec3(0.2, 0.4, 0.5)),
        const CameraRgb(0.2, 0.4, 0.5),
      );
      expect(const CameraRgb(0.2, 0.4, 0.5).asVec3, const Vec3(0.2, 0.4, 0.5));
    });

    test('value equality and printing', () {
      expect(const CameraRgb(1, 2, 3), const CameraRgb(1, 2, 3));
      expect(
        const CameraRgb(1, 2, 3).hashCode,
        const CameraRgb(1, 2, 3).hashCode,
      );
      expect(const CameraRgb(1, 2, 3), isNot(const CameraRgb(1, 2, 4)));
      expect(const CameraRgb(1, 2, 3).toString(), contains('CameraRgb'));
    });
  });

  group('ParametricWeights', () {
    test('value equality and printing', () {
      // Same reasoning as the white point above.
      // ignore: use_named_constants
      expect(const ParametricWeights(), ParametricWeights.unity);
      expect(
        // ignore: use_named_constants
        const ParametricWeights().hashCode,
        ParametricWeights.unity.hashCode,
      );
      expect(
        const ParametricWeights(lightness: 2),
        isNot(ParametricWeights.unity),
      );
      expect(ParametricWeights.unity.toString(), contains('kL'));
    });
  });
}
