import 'package:meta/meta.dart';

import 'package:shade_core/src/matching/shade_code.dart';
import 'package:shade_core/src/matching/shade_entry.dart';

/// Which shades a given shade may be mixed with.
///
/// The rule is structural, not metric: two shades are neighbours when they sit
/// next to each other in the guide's own layout. The reason is physical rather
/// than aesthetic. Mixing is modelled as a weighted combination in linear XYZ,
/// which is only a first-order approximation of how absorbing and scattering
/// materials actually combine; the approximation holds while the components are
/// close together and stops holding when they are not. Restricting mixtures to
/// structural neighbours is what keeps the model inside its own validity.
@immutable
final class ShadeAdjacency {
  const ShadeAdjacency._(this._neighbours, this.system);

  /// Builds the graph for a guide from its codes alone.
  ///
  /// Codes that do not parse get an empty neighbour set rather than an error:
  /// a clinic may add a shade from another guide to its own library, and that
  /// shade should still be matchable even though nothing can be mixed with it.
  factory ShadeAdjacency.forSystem(ShadeSystem system, List<String> codes) {
    final graph = <String, Set<String>>{};
    final parsed = <String, ShadeCode>{};
    for (final code in codes) {
      final shade = ShadeCode.tryParse(code, system);
      if (shade != null) parsed[code] = shade;
      graph[code] = <String>{};
    }
    // The chroma sequence of each column is read off the codes that actually
    // exist, not assumed. The middle column prints 1, 2, 3 while the flanking
    // columns print 1.5 and 2.5, so a single shared ordering would put two
    // steps between M1 and M2 and leave codes with no chroma neighbour at all.
    final columns = <String, List<double>>{};
    for (final shade in parsed.values) {
      if (shade is! MasterShadeCode) continue;
      final column = '${shade.valueGroup}${shade.hue.letter}';
      (columns[column] ??= <double>[]).add(shade.chroma);
    }
    for (final sequence in columns.values) {
      sequence.sort();
    }

    for (final entry in parsed.entries) {
      for (final other in parsed.entries) {
        if (entry.key == other.key) continue;
        if (_areNeighbours(entry.value, other.value, columns)) {
          graph[entry.key]!.add(other.key);
        }
      }
    }
    return ShadeAdjacency._(
      {
        for (final entry in graph.entries)
          entry.key: Set<String>.unmodifiable(entry.value),
      },
      system,
    );
  }

  final Map<String, Set<String>> _neighbours;
  final ShadeSystem system;

  /// The codes adjacent to [code]; empty when it has none.
  Set<String> neighboursOf(String code) => _neighbours[code] ?? const {};

  bool areNeighbours(String a, String b) => neighboursOf(a).contains(b);

  /// Every code in the graph.
  Iterable<String> get codes => _neighbours.keys;

  /// Total number of edges, counted once per pair. Used by the tests that pin
  /// the shape of each guide's graph.
  int get edgeCount =>
      _neighbours.values.fold<int>(0, (sum, set) => sum + set.length) ~/ 2;

  static bool _areNeighbours(
    ShadeCode a,
    ShadeCode b,
    Map<String, List<double>> columns,
  ) =>
      switch ((a, b)) {
        (final ClassicalShadeCode a, final ClassicalShadeCode b) =>
          _classical(a, b),
        (final MasterShadeCode a, final MasterShadeCode b) =>
          _master(a, b, columns),
        // Codes from different guides are never structural neighbours, whatever
        // their Lab values happen to be.
        _ => false,
      };

  /// Classical: same hue family, adjacent chroma step.
  ///
  /// `A3` and `A3.5` are neighbours; `A3` and `B3` are not, even though a
  /// technician would mix across families in practice. That restriction is the
  /// guide's structure talking, and lifting it is a v2 question rather than a
  /// parameter.
  static bool _classical(ClassicalShadeCode a, ClassicalShadeCode b) {
    if (a.family != b.family) return false;
    return (a.indexInFamily - b.indexInFamily).abs() == 1;
  }

  /// Three-dimensional: adjacent on exactly one of the three axes.
  ///
  /// Each axis needs the guide's actual layout rather than arithmetic on the
  /// printed numbers:
  ///
  /// * **value** - same column, same chroma, neighbouring group.
  /// * **chroma** - neighbouring steps *within that column's own sequence*. The
  ///   middle column prints 1, 2, 3 and the flanking columns print 1.5 and 2.5,
  ///   so `2M1` and `2M2` are neighbours even though 1.5 lies numerically
  ///   between them: there is no `2M1.5` tab to pass through.
  /// * **hue** - neighbouring column, with a chroma difference of at most half
  ///   a step. The half steps exist precisely so that `2L1.5` sits between
  ///   `2M1` and `2M2`, so it is a neighbour of both. Requiring an identical
  ///   chroma code instead would make the hue axis unreachable, because no
  ///   chroma code appears in both the middle and a flanking column.
  static bool _master(
    MasterShadeCode a,
    MasterShadeCode b,
    Map<String, List<double>> columns,
  ) {
    final sameValue = a.valueGroup == b.valueGroup;
    final sameHue = a.hue == b.hue;
    final sameChroma = a.chroma == b.chroma;

    if (sameHue && sameChroma && (a.valueGroup - b.valueGroup).abs() == 1) {
      return true;
    }
    if (sameValue && sameHue) {
      final sequence = columns['${a.valueGroup}${a.hue.letter}'];
      if (sequence != null) {
        final indexA = sequence.indexOf(a.chroma);
        final indexB = sequence.indexOf(b.chroma);
        if (indexA >= 0 && indexB >= 0 && (indexA - indexB).abs() == 1) {
          return true;
        }
      }
    }
    if (sameValue &&
        (a.hue.index - b.hue.index).abs() == 1 &&
        (a.chroma - b.chroma).abs() <= halfStep) {
      return true;
    }
    return false;
  }

  /// The chroma difference a half step represents, which is what makes a
  /// flanking tab a neighbour of the two middle tabs it sits between.
  static const double halfStep = 0.5;
}
