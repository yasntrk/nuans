import 'package:meta/meta.dart';

import 'package:shade_core/src/matching/shade_entry.dart';

/// A shade code parsed into the axes its guide is built on.
///
/// Parsing matters because the mixing rules are structural: only shades that
/// are neighbours in the guide's own layout may be mixed, and "neighbour" is a
/// statement about these axes rather than about distance in Lab. A code that
/// cannot be parsed therefore has no neighbours at all, which is the safe
/// outcome: it can still be matched, just never mixed.
@immutable
sealed class ShadeCode {
  const ShadeCode(this.raw);

  /// Parses [raw] according to [system], or returns `null` when it does not fit
  /// that guide's grammar.
  static ShadeCode? tryParse(String raw, ShadeSystem system) =>
      switch (system) {
        ShadeSystem.classicalCompatible => ClassicalShadeCode.tryParse(raw),
        ShadeSystem.threeDimensionalMasterCompatible =>
          MasterShadeCode.tryParse(raw),
      };

  /// The code exactly as the guide prints it. Never translated.
  final String raw;

  @override
  String toString() => raw;
}

/// A classical code: a hue family letter and a chroma step, as in `A3.5`.
@immutable
final class ClassicalShadeCode extends ShadeCode {
  const ClassicalShadeCode._({
    required String raw,
    required this.family,
    required this.chroma,
  }) : super(raw);

  /// The sixteen codes of the guide, grouped by family in chroma order.
  ///
  /// The families are not the same length - A has five steps and D has three -
  /// which is why adjacency is defined by position in this list rather than by
  /// arithmetic on the chroma number.
  static const Map<String, List<String>> familyOrder = {
    'A': ['A1', 'A2', 'A3', 'A3.5', 'A4'],
    'B': ['B1', 'B2', 'B3', 'B4'],
    'C': ['C1', 'C2', 'C3', 'C4'],
    'D': ['D2', 'D3', 'D4'],
  };

  static final RegExp _pattern = RegExp(r'^([ABCD])([1-4](?:\.5)?)$');

  static ClassicalShadeCode? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final family = match.group(1)!;
    final chroma = double.parse(match.group(2)!);
    if (!(familyOrder[family]?.contains(raw.trim()) ?? false)) return null;
    return ClassicalShadeCode._(
      raw: raw.trim(),
      family: family,
      chroma: chroma,
    );
  }

  /// Hue family: `A`, `B`, `C` or `D`.
  final String family;

  /// Chroma step within the family, as printed: 1, 2, 3, 3.5 or 4.
  final double chroma;

  /// Position within the family, counting from the least chromatic.
  int get indexInFamily => familyOrder[family]!.indexOf(raw);
}

/// Hue column of the three-dimensional guide.
enum MasterHue {
  /// Yellower.
  left('L'),

  /// Middle.
  middle('M'),

  /// Redder.
  right('R');

  const MasterHue(this.letter);

  final String letter;

  static MasterHue? fromLetter(String letter) {
    for (final hue in MasterHue.values) {
      if (hue.letter == letter) return hue;
    }
    return null;
  }
}

/// A three-dimensional code: value group, hue column and chroma, as in `3R2.5`.
@immutable
final class MasterShadeCode extends ShadeCode {
  const MasterShadeCode._({
    required String raw,
    required this.valueGroup,
    required this.hue,
    required this.chroma,
  }) : super(raw);

  /// The twenty-nine codes of the guide.
  ///
  /// The grid is deliberately incomplete: the outer value groups carry only the
  /// middle hue column, and the L and R columns carry half steps the M column
  /// does not. Hard-coding the set is what keeps the adjacency graph from
  /// inventing shades that no physical guide holds.
  static const List<String> allCodes = [
    '0M1',
    '0M2',
    '0M3',
    '1M1',
    '1M2',
    '2L1.5',
    '2L2.5',
    '2M1',
    '2M2',
    '2M3',
    '2R1.5',
    '2R2.5',
    '3L1.5',
    '3L2.5',
    '3M1',
    '3M2',
    '3M3',
    '3R1.5',
    '3R2.5',
    '4L1.5',
    '4L2.5',
    '4M1',
    '4M2',
    '4M3',
    '4R1.5',
    '4R2.5',
    '5M1',
    '5M2',
    '5M3',
  ];

  static final RegExp _pattern = RegExp(r'^([0-5])([LMR])([1-3](?:\.5)?)$');

  static MasterShadeCode? tryParse(String raw) {
    final trimmed = raw.trim();
    if (!allCodes.contains(trimmed)) return null;
    final match = _pattern.firstMatch(trimmed);
    if (match == null) return null;
    final hue = MasterHue.fromLetter(match.group(2)!);
    if (hue == null) return null;
    return MasterShadeCode._(
      raw: trimmed,
      valueGroup: int.parse(match.group(1)!),
      hue: hue,
      chroma: double.parse(match.group(3)!),
    );
  }

  /// Value group, 0 for the lightest.
  final int valueGroup;

  final MasterHue hue;

  /// Chroma as printed: 1, 1.5, 2, 2.5 or 3.
  final double chroma;

  /// Whether a code with these axes exists in the physical guide.
  static bool exists({
    required int valueGroup,
    required MasterHue hue,
    required double chroma,
  }) {
    final printed = chroma == chroma.roundToDouble()
        ? chroma.toStringAsFixed(0)
        : chroma.toStringAsFixed(1);
    return allCodes.contains('$valueGroup${hue.letter}$printed');
  }
}
