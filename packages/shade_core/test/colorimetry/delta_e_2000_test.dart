import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

import '../data/sharma_test_data.dart';

void main() {
  LabColor lab(List<double> v) => LabColor(v[0], v[1], v[2]);

  group('published test data', () {
    for (final testCase in sharmaCases) {
      test('Sharma pair ${testCase.index}', () {
        final result = DeltaE2000.between(
          reference: lab(testCase.lab1),
          sample: lab(testCase.lab2),
        );
        expect(result.deltaE, closeTo(testCase.expected, 1e-4));
      });
    }

    test('reports how much of the published table is still missing', () {
      // Not a failure: a reminder that verification is partial until the whole
      // table has been transcribed from the source.
      expect(
        sharmaCases.length,
        lessThanOrEqualTo(sharmaPublishedCaseCount),
        reason: 'more cases than the published table has',
      );
      printOnFailure(
        'transcribed ${sharmaCases.length} of $sharmaPublishedCaseCount '
        'published Sharma cases',
      );
    });
  });

  group('structural properties', () {
    test('a colour has no difference from itself', () {
      const c = LabColor(72.5, 1.4, 14.2);
      expect(DeltaE2000.between(reference: c, sample: c).deltaE, 0);
    });

    test('the scalar is symmetric', () {
      const a = LabColor(60, 5, -3);
      const b = LabColor(61, -4, 8);
      expect(
        DeltaE2000.between(reference: a, sample: b).deltaE,
        closeTo(DeltaE2000.between(reference: b, sample: a).deltaE, 1e-15),
      );
    });

    test('the components change sign when the order is swapped', () {
      const a = LabColor(70, 2, 18);
      const b = LabColor(73, 2, 24);
      final forward = DeltaE2000.between(reference: a, sample: b);
      final backward = DeltaE2000.between(reference: b, sample: a);
      expect(
        forward.weightedLightness,
        closeTo(-backward.weightedLightness, 1e-12),
      );
      expect(forward.weightedChroma, closeTo(-backward.weightedChroma, 1e-12));
    });

    test('a pure lightness difference lands entirely on the lightness term',
        () {
      final result = DeltaE2000.between(
        reference: const LabColor(50, 0, 0),
        sample: const LabColor(55, 0, 0),
      );
      expect(result.deltaE, closeTo(4.9101533927, 1e-9));
      expect(result.weightedLightness, closeTo(4.9101533927, 1e-9));
      expect(result.weightedChroma, 0);
      expect(result.weightedHue, 0);
      expect(result.dominantComponent, DeltaE2000Component.lightness);
    });

    test('two neutrals take the C-prime-is-zero branch without blowing up', () {
      final result = DeltaE2000.between(
        reference: const LabColor(50, 0, 0),
        sample: const LabColor(50, 0, 0),
      );
      expect(result.deltaE, 0);
      expect(result.deltaE.isNaN, isFalse);
    });

    test('crossing the hue origin stays continuous', () {
      // Just either side of 0 degrees: a naive mean hue would average to 180.
      final result = DeltaE2000.between(
        reference: const LabColor(60, 5, -2),
        sample: const LabColor(60, 5, 2),
      );
      expect(result.deltaE, closeTo(3.4677262587, 1e-9));
      expect(result.deltaE.isNaN, isFalse);
      expect(result.dominantComponent, DeltaE2000Component.hue);
    });

    test('an opposite-hue pair resolves to a large hue difference', () {
      final result = DeltaE2000.between(
        reference: const LabColor(40, 30, -40),
        sample: const LabColor(40, -30, 40),
      );
      expect(result.deltaE, closeTo(49.5007035709, 1e-9));
      expect(result.weightedHue, closeTo(-49.5007035709, 1e-9));
    });

    test('a chroma step is carried mostly by chroma', () {
      final result = DeltaE2000.between(
        reference: const LabColor(70, 2, 18),
        sample: const LabColor(70, 2, 24),
      );
      expect(result.deltaE, closeTo(3.1116511083, 1e-9));
      expect(result.weightedChroma, closeTo(3.0516446591, 1e-9));
      expect(result.weightedHue, closeTo(0.6081426592, 1e-9));
      expect(result.dominantComponent, DeltaE2000Component.chroma);
    });

    test('a tooth against a shade tab decomposes as computed', () {
      final result = DeltaE2000.between(
        reference: const LabColor(82.2986328, -0.2668886, 12.7115859),
        sample: const LabColor(80.5, 1.2, 15),
      );
      expect(result.deltaE, closeTo(2.6099352913, 1e-9));
      expect(result.weightedLightness, closeTo(-1.2266605540, 1e-9));
      expect(result.weightedChroma, closeTo(1.4646923653, 1e-9));
      expect(result.weightedHue, closeTo(-1.7781289001, 1e-9));
      // The tooth is darker than the tab, so the lightness term is negative.
      expect(result.weightedLightness, isNegative);
    });

    test('the weighted components reproduce the scalar', () {
      const a = LabColor(72, 1.5, 15);
      const b = LabColor(69, 3, 19);
      final r = DeltaE2000.between(reference: a, sample: b);
      final recomposed = r.weightedLightness * r.weightedLightness +
          r.weightedChroma * r.weightedChroma +
          r.weightedHue * r.weightedHue +
          r.rotationTerm * r.weightedChroma * r.weightedHue;
      expect(r.deltaE * r.deltaE, closeTo(recomposed, 1e-12));
    });

    test('S terms behave as the formula requires', () {
      // SL is smallest at L* 50 and grows away from it.
      final atFifty = DeltaE2000.between(
        reference: const LabColor(50, 0, 0),
        sample: const LabColor(51, 0, 0),
      );
      final atNinety = DeltaE2000.between(
        reference: const LabColor(90, 0, 0),
        sample: const LabColor(91, 0, 0),
      );
      // SL is 1 only exactly at L* 50; half a unit away it is already
      // 1.000833, which is why this is not asserted as closeTo(1, 1e-6).
      expect(atFifty.sLightness, closeTo(1.000833333333, 1e-11));
      expect(atNinety.sLightness, greaterThan(atFifty.sLightness));
      // SC and SH grow with chroma.
      final chromatic = DeltaE2000.between(
        reference: const LabColor(50, 40, 40),
        sample: const LabColor(50, 41, 40),
      );
      expect(chromatic.sChroma, greaterThan(atFifty.sChroma));
    });

    test('the rotation term only matters in the blue region', () {
      final blue = DeltaE2000.between(
        reference: const LabColor(50, 10, -60),
        sample: const LabColor(50, 12, -58),
      );
      final yellow = DeltaE2000.between(
        reference: const LabColor(50, 10, 60),
        sample: const LabColor(50, 12, 58),
      );
      expect(blue.rotationTerm, closeTo(-1.677089830342, 1e-9));
      expect(yellow.rotationTerm.abs(), lessThan(1e-6));
    });

    test('parametric weights scale the terms they name', () {
      const a = LabColor(50, 0, 0);
      const b = LabColor(55, 0, 0);
      final unity = DeltaE2000.between(reference: a, sample: b);
      final halved = DeltaE2000.between(
        reference: a,
        sample: b,
        weights: const ParametricWeights(lightness: 2),
      );
      expect(halved.deltaE, closeTo(unity.deltaE / 2, 1e-12));
    });

    test('the scalar convenience agrees with the full evaluation', () {
      const a = LabColor(72, 1.5, 15);
      const b = LabColor(69, 3, 19);
      expect(
        DeltaE2000.scalar(a, b),
        DeltaE2000.between(reference: a, sample: b).deltaE,
      );
    });
  });
}
