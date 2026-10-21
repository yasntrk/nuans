import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';
import 'package:shade_core/src/matching/shade_entry.dart';
import 'package:shade_core/src/mixing/shade_adjacency.dart';

/// One component of a mixture: a shade and the share of the mix it takes.
@immutable
final class MixComponent {
  const MixComponent({required this.entry, required this.weight});

  final ShadeEntry entry;

  /// Share of the mixture, in `0 .. 1`.
  final double weight;

  /// The share as a whole percentage, for display.
  int get percent => (weight * 100).round();

  @override
  String toString() => '${entry.code} $percent%';
}

/// A candidate mixture, in both its optimal and its usable form.
@immutable
final class MixResult {
  const MixResult({
    required this.components,
    required this.lab,
    required this.delta,
    required this.roundedComponents,
    required this.roundedLab,
    required this.roundedDelta,
  });

  /// The optimum on the 5% grid, strongest component first.
  final List<MixComponent> components;
  final LabColor lab;
  final DeltaE2000Result delta;

  /// The same mixture rounded to whole 10% steps, which is what a technician
  /// can actually weigh out.
  final List<MixComponent> roundedComponents;
  final LabColor roundedLab;
  final DeltaE2000Result roundedDelta;

  double get deltaE2000 => delta.deltaE;

  /// The difference the clinician will really get.
  double get roundedDeltaE2000 => roundedDelta.deltaE;

  /// What rounding cost. Positive means the rounded mixture is worse.
  double get roundingPenalty => roundedDelta.deltaE - delta.deltaE;

  @override
  String toString() => 'MixResult(${roundedComponents.join(' + ')}, '
      'dE00 ${roundedDelta.deltaE})';
}

/// Why no mixture is being offered.
enum MixRejectionReason {
  /// The best single shade is already imperceptible, so mixing would be work
  /// for no gain.
  singleShadeAlreadyGoodEnough,

  /// No mixture of structural neighbours improves on the best single shade by
  /// enough to be worth weighing out.
  noWorthwhileImprovement,

  /// Nothing in the candidate set has a structural neighbour to mix with.
  noStructuralNeighbours,
}

/// The outcome of asking for a mixture.
@immutable
sealed class MixOutcome {
  const MixOutcome();
}

/// A mixture worth offering.
@immutable
final class MixOffered extends MixOutcome {
  const MixOffered({
    required this.result,
    required this.bestSingleDeltaE,
  });

  final MixResult result;

  /// What the best single shade achieved, so the gain can be shown.
  final double bestSingleDeltaE;

  /// The improvement the clinician will really get, measured on the rounded
  /// mixture rather than on the optimum.
  double get improvement => bestSingleDeltaE - result.roundedDeltaE2000;
}

/// No mixture: the single shade stands.
@immutable
final class MixDeclined extends MixOutcome {
  const MixDeclined({required this.reason, required this.bestSingleDeltaE});

  final MixRejectionReason reason;
  final double bestSingleDeltaE;
}

/// Searches for the mixture of structural neighbours closest to a target.
///
/// Exhaustive on a 5% grid, which is small enough to be exact rather than
/// clever: 21 combinations for a pair and 231 for a triple, and the candidate
/// set is at most a handful of shades. There is nothing here worth optimising
/// and an optimiser would be another thing to keep correct.
///
/// Mixing happens in linear XYZ, never in Lab, because Lab is a non-linear
/// function of the quantity that actually combines.
@immutable
final class ShadeMixer {
  const ShadeMixer({
    this.gridStep = kMixGridStep,
    this.roundingStep = kMixRoundingStep,
    this.maxComponents = kMaxMixComponents,
    this.minImprovement = kMixImprovementMin,
    this.imperceptible = kImperceptibleDeltaE,
  });

  final double gridStep;
  final double roundingStep;
  final int maxComponents;
  final double minImprovement;
  final double imperceptible;

  /// Finds the best mixture for [target], or explains why there is none.
  ///
  /// [candidates] should be the nearest few shades; their structural
  /// neighbours are added here, so the caller does not have to know the graph.
  MixOutcome search({
    required LabColor target,
    required List<ShadeEntry> candidates,
    required ShadeLibrary library,
    required ShadeAdjacency adjacency,
    required double bestSingleDeltaE,
  }) {
    if (bestSingleDeltaE <= imperceptible) {
      return MixDeclined(
        reason: MixRejectionReason.singleShadeAlreadyGoodEnough,
        bestSingleDeltaE: bestSingleDeltaE,
      );
    }

    final pool =
        _pool(candidates: candidates, library: library, adjacency: adjacency);
    if (pool.length < 2) {
      return MixDeclined(
        reason: MixRejectionReason.noStructuralNeighbours,
        bestSingleDeltaE: bestSingleDeltaE,
      );
    }

    MixResult? best;
    for (final group in _connectedGroups(pool, adjacency)) {
      final candidate = _searchGroup(target: target, group: group);
      if (candidate == null) continue;
      if (best == null ||
          candidate.roundedDeltaE2000 < best.roundedDeltaE2000) {
        best = candidate;
      }
    }

    if (best == null) {
      return MixDeclined(
        reason: MixRejectionReason.noStructuralNeighbours,
        bestSingleDeltaE: bestSingleDeltaE,
      );
    }
    // The gate is measured on the rounded mixture, because that is what the
    // clinician will weigh out. Opening the gate with the optimum and then
    // handing over the rounded version would promise an improvement that was
    // never delivered.
    if (bestSingleDeltaE - best.roundedDeltaE2000 < minImprovement) {
      return MixDeclined(
        reason: MixRejectionReason.noWorthwhileImprovement,
        bestSingleDeltaE: bestSingleDeltaE,
      );
    }
    return MixOffered(result: best, bestSingleDeltaE: bestSingleDeltaE);
  }

  /// The candidates plus their structural neighbours, de-duplicated.
  List<ShadeEntry> _pool({
    required List<ShadeEntry> candidates,
    required ShadeLibrary library,
    required ShadeAdjacency adjacency,
  }) {
    final codes = <String>{};
    for (final candidate in candidates) {
      codes
        ..add(candidate.code)
        ..addAll(adjacency.neighboursOf(candidate.code));
    }
    final pool = <ShadeEntry>[];
    for (final code in codes.toList()..sort()) {
      final entry = library[code];
      if (entry != null) pool.add(entry);
    }
    return pool;
  }

  /// Every pair and triple of the pool whose members are all pairwise
  /// adjacent.
  ///
  /// Pairwise rather than merely connected: a chain `A1 - A2 - A3` would let
  /// `A1` and `A3` into one mixture although they are two steps apart, which is
  /// exactly the distance the linear model stops covering.
  Iterable<List<ShadeEntry>> _connectedGroups(
    List<ShadeEntry> pool,
    ShadeAdjacency adjacency,
  ) {
    final groups = <List<ShadeEntry>>[];
    for (var i = 0; i < pool.length; i++) {
      for (var j = i + 1; j < pool.length; j++) {
        if (!adjacency.areNeighbours(pool[i].code, pool[j].code)) continue;
        groups.add([pool[i], pool[j]]);
        if (maxComponents < 3) continue;
        for (var k = j + 1; k < pool.length; k++) {
          if (adjacency.areNeighbours(pool[i].code, pool[k].code) &&
              adjacency.areNeighbours(pool[j].code, pool[k].code)) {
            groups.add([pool[i], pool[j], pool[k]]);
          }
        }
      }
    }
    return groups;
  }

  MixResult? _searchGroup({
    required LabColor target,
    required List<ShadeEntry> group,
  }) {
    final steps = (1 / gridStep).round();
    final xyz = group.map((e) => e.lab.toXyz()).toList(growable: false);
    List<double>? bestWeights;
    var bestDeltaE = double.infinity;

    for (final weights in _compositions(steps, group.length)) {
      final normalised = weights.map((w) => w / steps).toList(growable: false);
      final mixed = XyzColor.weightedMean(xyz, normalised);
      final deltaE = DeltaE2000.between(
        reference: mixed.toLab(),
        sample: target,
      ).deltaE;
      if (deltaE < bestDeltaE) {
        bestDeltaE = deltaE;
        bestWeights = normalised;
      }
    }
    if (bestWeights == null) return null;

    final rounded = roundWeights(bestWeights, step: roundingStep);
    final optimalLab = XyzColor.weightedMean(xyz, bestWeights).toLab();
    final roundedLab = XyzColor.weightedMean(xyz, rounded).toLab();

    List<MixComponent> components(List<double> weights) {
      final parts = <MixComponent>[];
      for (var i = 0; i < group.length; i++) {
        if (weights[i] <= 0) continue;
        parts.add(MixComponent(entry: group[i], weight: weights[i]));
      }
      parts.sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.entry.code.compareTo(b.entry.code);
      });
      return List<MixComponent>.unmodifiable(parts);
    }

    return MixResult(
      components: components(bestWeights),
      lab: optimalLab,
      delta: DeltaE2000.between(reference: optimalLab, sample: target),
      roundedComponents: components(rounded),
      roundedLab: roundedLab,
      roundedDelta: DeltaE2000.between(reference: roundedLab, sample: target),
    );
  }

  /// Every way to split `total` whole units into `parts` non-negative shares.
  ///
  /// For 20 units this yields 21 pairs and 231 triples, which is exactly the
  /// grid the protocol specifies.
  @visibleForTesting
  static Iterable<List<int>> compositions(int total, int parts) =>
      _compositions(total, parts);

  static Iterable<List<int>> _compositions(int total, int parts) sync* {
    if (parts == 1) {
      yield [total];
      return;
    }
    for (var first = 0; first <= total; first++) {
      for (final rest in _compositions(total - first, parts - 1)) {
        yield [first, ...rest];
      }
    }
  }

  /// Rounds weights to whole [step] shares while keeping the sum at exactly 1.
  ///
  /// Largest remainder: floor everything, then hand the leftover units to the
  /// components with the biggest fractional part. Rounding each weight on its
  /// own would let the total drift off 1, which would silently change the
  /// lightness of the mixture rather than its proportions.
  @visibleForTesting
  static List<double> roundWeights(
    List<double> weights, {
    double step = kMixRoundingStep,
  }) {
    final units = (1 / step).round();
    final scaled = weights.map((w) => w * units).toList(growable: false);
    final floors = scaled.map((v) => v.floor()).toList();
    var remaining = units - floors.reduce((a, b) => a + b);
    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final fractionA = scaled[a] - floors[a];
        final fractionB = scaled[b] - floors[b];
        final byFraction = fractionB.compareTo(fractionA);
        return byFraction != 0 ? byFraction : a.compareTo(b);
      });
    var cursor = 0;
    while (remaining > 0 && order.isNotEmpty) {
      floors[order[cursor % order.length]] += 1;
      remaining -= 1;
      cursor += 1;
    }
    return floors.map((v) => v / units).toList(growable: false);
  }
}
