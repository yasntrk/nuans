import 'dart:math' as math;

/// Order statistics that tolerate outliers.
///
/// All of these copy their input before sorting: a statistic that reorders the
/// caller's data is a trap, especially here where the same sample list is used
/// for several statistics in a row.
abstract final class RobustStats {
  /// The median. For an even count, the mean of the two central values.
  static double median(List<double> values) {
    if (values.isEmpty) {
      throw ArgumentError.value(0, 'values.length', 'must not be empty');
    }
    final sorted = List<double>.of(values)..sort();
    return medianOfSorted(sorted);
  }

  /// The median of an already ascending list.
  static double medianOfSorted(List<double> sorted) {
    if (sorted.isEmpty) {
      throw ArgumentError.value(0, 'sorted.length', 'must not be empty');
    }
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// The median absolute deviation, **unscaled**.
  ///
  /// Deliberately not multiplied by 1.4826. The rejection factors of the
  /// capture protocol are expressed in raw MAD units, and silently rescaling
  /// here would widen both rejection bands by about 48%.
  static double medianAbsoluteDeviation(
    List<double> values, {
    double? precomputedMedian,
  }) {
    final centre = precomputedMedian ?? median(values);
    final deviations = List<double>.generate(
      values.length,
      (i) => (values[i] - centre).abs(),
      growable: false,
    );
    return median(deviations);
  }

  /// The arithmetic mean.
  static double mean(List<double> values) {
    if (values.isEmpty) {
      throw ArgumentError.value(0, 'values.length', 'must not be empty');
    }
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    return sum / values.length;
  }

  /// The population standard deviation.
  static double standardDeviation(
    List<double> values, {
    double? precomputedMean,
  }) {
    if (values.isEmpty) {
      throw ArgumentError.value(0, 'values.length', 'must not be empty');
    }
    final centre = precomputedMean ?? mean(values);
    var sum = 0.0;
    for (final v in values) {
      final d = v - centre;
      sum += d * d;
    }
    return math.sqrt(sum / values.length);
  }

  /// The index range `[low, high)` of a trimmed mean over `count` ordered
  /// samples.
  ///
  /// Exposed on its own because the trimming has to be applied to tristimulus
  /// values while the *order* comes from lightness, so the caller needs the
  /// bounds rather than a finished mean.
  static ({int low, int high}) trimBounds({
    required int count,
    required double lowFraction,
    required double highFraction,
  }) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be positive');
    }
    if (lowFraction < 0 || highFraction > 1 || lowFraction >= highFraction) {
      throw ArgumentError('trim fractions must satisfy 0 <= low < high <= 1');
    }
    final low = (count * lowFraction).floor();
    final high = (count * highFraction).ceil();
    // With a very small count the two bounds can collapse; keep at least one
    // sample so the caller never divides by zero.
    if (high <= low) {
      return (low: low, high: low + 1 <= count ? low + 1 : count);
    }
    return (low: low, high: high > count ? count : high);
  }
}
