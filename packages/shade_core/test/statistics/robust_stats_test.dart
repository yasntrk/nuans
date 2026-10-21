import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  group('median', () {
    test('odd count returns the central value', () {
      expect(RobustStats.median([3, 1, 2]), 2);
    });

    test('even count averages the two central values', () {
      expect(RobustStats.median([4, 1, 3, 2]), 2.5);
    });

    test('does not reorder the caller list', () {
      final values = [3.0, 1.0, 2.0];
      RobustStats.median(values);
      expect(values, [3.0, 1.0, 2.0]);
    });

    test('ignores an extreme outlier', () {
      expect(RobustStats.median([1, 2, 3, 4, 1000]), 3);
    });

    test('refuses an empty list', () {
      expect(() => RobustStats.median([]), throwsArgumentError);
      expect(() => RobustStats.medianOfSorted([]), throwsArgumentError);
    });
  });

  group('median absolute deviation', () {
    test('is zero for a constant list', () {
      expect(RobustStats.medianAbsoluteDeviation([5, 5, 5, 5]), 0);
    });

    test('is unscaled, not multiplied by 1.4826', () {
      // Deviations from the median 3 are 2, 1, 0, 1, 2 -> median 1.
      expect(RobustStats.medianAbsoluteDeviation([1, 2, 3, 4, 5]), 1);
    });

    test('accepts a precomputed median', () {
      final values = <double>[1, 2, 3, 4, 5];
      expect(
        RobustStats.medianAbsoluteDeviation(values, precomputedMedian: 3),
        RobustStats.medianAbsoluteDeviation(values),
      );
    });

    test('survives a heavy outlier where a standard deviation would not', () {
      final clean = [10.0, 10.1, 9.9, 10.0, 10.05];
      final dirty = [...clean, 90.0];
      expect(
        RobustStats.medianAbsoluteDeviation(dirty),
        closeTo(RobustStats.medianAbsoluteDeviation(clean), 0.06),
      );
      expect(
        RobustStats.standardDeviation(dirty),
        greaterThan(RobustStats.standardDeviation(clean) * 100),
      );
    });
  });

  group('mean and standard deviation', () {
    test('computes the population standard deviation', () {
      // Mean 3, squared deviations 4 + 1 + 0 + 1 + 4 = 10, over n = 5.
      expect(RobustStats.mean([1, 2, 3, 4, 5]), 3);
      expect(
        RobustStats.standardDeviation([1, 2, 3, 4, 5]),
        closeTo(1.4142135624, 1e-9),
      );
    });

    test('is zero for a constant list', () {
      expect(RobustStats.standardDeviation([7, 7, 7]), 0);
    });
  });

  group('trim bounds', () {
    test('10 to 90 per cent of a round hundred', () {
      final bounds = RobustStats.trimBounds(
        count: 100,
        lowFraction: 0.1,
        highFraction: 0.9,
      );
      expect(bounds.low, 10);
      expect(bounds.high, 90);
    });

    test('floors the low bound and ceils the high one', () {
      // 370 accepted samples: 37 and 333, as the reducer fixture expects.
      final bounds = RobustStats.trimBounds(
        count: 370,
        lowFraction: kTrimLowFraction,
        highFraction: kTrimHighFraction,
      );
      expect(bounds.low, 37);
      expect(bounds.high, 333);
    });

    test('never collapses to an empty range', () {
      for (final count in [1, 2, 3, 5, 9]) {
        final bounds = RobustStats.trimBounds(
          count: count,
          lowFraction: 0.1,
          highFraction: 0.9,
        );
        expect(bounds.high, greaterThan(bounds.low));
        expect(bounds.high, lessThanOrEqualTo(count));
      }
    });

    test('rejects nonsense fractions', () {
      expect(
        () => RobustStats.trimBounds(
          count: 10,
          lowFraction: 0.9,
          highFraction: 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RobustStats.trimBounds(
          count: 0,
          lowFraction: 0.1,
          highFraction: 0.9,
        ),
        throwsArgumentError,
      );
    });
  });
}
