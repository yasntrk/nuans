import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/matching/shade_entry.dart';
import 'package:shade_core/src/matching/thresholds.dart';

/// Which way a measured tooth deviates from a candidate shade.
///
/// Machine codes, not words: the Flutter layer maps each one to an ARB key, so
/// the same deviation reads correctly in Turkish and English and nothing here
/// has to know about either language.
enum ShadeDeviationDirection {
  lighter,
  darker,
  moreChromatic,
  lessChromatic,
  towardRed,
  towardYellow,
  towardGreen,
  towardBlue,
}

/// One component of the difference between a tooth and a candidate shade.
@immutable
final class ShadeDeviation {
  const ShadeDeviation({
    required this.component,
    required this.weightedValue,
    required this.magnitude,
    required this.direction,
  });

  final DeltaE2000Component component;

  /// The component in CIEDE2000 units, signed.
  final double weightedValue;

  final ComponentMagnitude magnitude;
  final ShadeDeviationDirection direction;

  bool get isWorthMentioning => magnitude != ComponentMagnitude.negligible;

  @override
  String toString() => 'ShadeDeviation(${component.name}, ${direction.name}, '
      '${magnitude.name}, $weightedValue)';
}

/// A candidate shade with the full difference to the measured tooth.
@immutable
final class ShadeMatch {
  const ShadeMatch({
    required this.entry,
    required this.delta,
    required this.band,
    required this.deviations,
  });

  final ShadeEntry entry;

  /// The difference, with the reference being [entry] and the sample being the
  /// measured tooth. So a positive weighted lightness means the tooth is
  /// lighter than this shade.
  final DeltaE2000Result delta;

  final AcceptabilityBand band;

  /// The three components, strongest first.
  final List<ShadeDeviation> deviations;

  double get deltaE2000 => delta.deltaE;

  /// The component carrying most of the difference.
  ShadeDeviation get dominant => deviations.first;

  /// The components worth putting in a sentence.
  List<ShadeDeviation> get notableDeviations =>
      deviations.where((d) => d.isWorthMentioning).toList();

  @override
  String toString() =>
      'ShadeMatch(${entry.code}, dE00: ${delta.deltaE}, ${band.name})';
}
