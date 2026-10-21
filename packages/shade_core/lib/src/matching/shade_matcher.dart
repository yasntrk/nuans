import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/constants.dart';
import 'package:shade_core/src/matching/shade_entry.dart';
import 'package:shade_core/src/matching/shade_match.dart';
import 'package:shade_core/src/matching/thresholds.dart';

/// Finds the shades closest to a measured colour.
///
/// Brute force on purpose. The libraries that ship hold 16 and 29 entries, so a
/// search is about fifty CIEDE2000 evaluations: there is nothing here worth
/// indexing, and an index would be another thing to keep correct.
@immutable
final class ShadeMatcher {
  const ShadeMatcher({
    this.thresholds = const AcceptabilityThresholds(),
    this.wording = const ComponentWordingThresholds(),
  });

  final AcceptabilityThresholds thresholds;
  final ComponentWordingThresholds wording;

  /// The [count] nearest shades, closest first.
  ///
  /// Ties are broken by shade code so that the same measurement and the same
  /// library always produce the same ordering, whatever the sort algorithm does
  /// with equal keys.
  List<ShadeMatch> findNearest({
    required LabColor target,
    required ShadeLibrary library,
    int count = kDefaultMatchCount,
  }) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least one');
    }
    final matches = library.entries
        .map((entry) => _match(entry, target))
        .toList()
      ..sort((a, b) {
        final byDelta = a.delta.deltaE.compareTo(b.delta.deltaE);
        return byDelta != 0 ? byDelta : a.entry.code.compareTo(b.entry.code);
      });
    return matches.length <= count ? matches : matches.sublist(0, count);
  }

  /// The single closest shade.
  ShadeMatch best({
    required LabColor target,
    required ShadeLibrary library,
  }) =>
      findNearest(target: target, library: library, count: 1).first;

  ShadeMatch _match(ShadeEntry entry, LabColor target) {
    final delta = DeltaE2000.between(reference: entry.lab, sample: target);
    final deviations = <ShadeDeviation>[
      for (final component in DeltaE2000Component.values)
        _deviation(component, delta),
    ]..sort(
        (a, b) => b.weightedValue.abs().compareTo(a.weightedValue.abs()),
      );
    return ShadeMatch(
      entry: entry,
      delta: delta,
      band: thresholds.classify(delta.deltaE),
      deviations: List<ShadeDeviation>.unmodifiable(deviations),
    );
  }

  ShadeDeviation _deviation(
    DeltaE2000Component component,
    DeltaE2000Result delta,
  ) {
    final value = delta.weightedValueOf(component);
    return ShadeDeviation(
      component: component,
      weightedValue: value,
      magnitude: wording.classify(value),
      direction: switch (component) {
        DeltaE2000Component.lightness => value >= 0
            ? ShadeDeviationDirection.lighter
            : ShadeDeviationDirection.darker,
        DeltaE2000Component.chroma => value >= 0
            ? ShadeDeviationDirection.moreChromatic
            : ShadeDeviationDirection.lessChromatic,
        DeltaE2000Component.hue =>
          hueDirection(delta.meanHuePrimeDegrees, value),
      },
    );
  }

  /// Turns a signed hue difference into a named direction.
  ///
  /// The sign of `dH'` alone says nothing nameable: it is a rotation, and which
  /// colour that rotation moves towards depends on where on the hue circle the
  /// pair sits. So the quadrant of the mean hue picks the pair of names and the
  /// sign picks one of them. Positive is counter-clockwise, towards increasing
  /// hue angle.
  ///
  /// Teeth live in the first quadrant, between red at 0 and yellow at 90, so in
  /// practice this resolves to [ShadeDeviationDirection.towardYellow] or
  /// [ShadeDeviationDirection.towardRed]; the other quadrants are handled for
  /// completeness and for the reference chart, which spans the whole circle.
  @visibleForTesting
  static ShadeDeviationDirection hueDirection(
    double meanHuePrimeDegrees,
    double weightedHue,
  ) {
    final quadrant = ((meanHuePrimeDegrees % 360) / 90).floor() % 4;
    const counterClockwise = <ShadeDeviationDirection>[
      ShadeDeviationDirection.towardYellow,
      ShadeDeviationDirection.towardGreen,
      ShadeDeviationDirection.towardBlue,
      ShadeDeviationDirection.towardRed,
    ];
    const clockwise = <ShadeDeviationDirection>[
      ShadeDeviationDirection.towardRed,
      ShadeDeviationDirection.towardYellow,
      ShadeDeviationDirection.towardGreen,
      ShadeDeviationDirection.towardBlue,
    ];
    return weightedHue >= 0 ? counterClockwise[quadrant] : clockwise[quadrant];
  }
}
