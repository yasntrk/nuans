import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// The Lab values below are synthetic, not shade guide reference data.
void main() {
  ShadeEntry entry(String code, double l, double a, double b) => ShadeEntry(
        code: code,
        lab: LabColor(l, a, b),
        source: ShadeValueSource.clinicalMeasurement,
        measuredAtUtc: DateTime.utc(2026, 10, 22),
      );

  final library = ShadeLibrary(
    id: 'synthetic',
    system: ShadeSystem.classicalCompatible,
    entries: [
      entry('A1', 78, 0.5, 10),
      entry('A2', 75, 1.2, 14),
      entry('A3', 72, 2, 18),
      entry('A3.5', 70, 2.6, 20),
      entry('A4', 67, 3.2, 23),
      entry('B2', 76, 0.8, 12),
    ],
  );
  final adjacency = ShadeAdjacency.forSystem(
    ShadeSystem.classicalCompatible,
    library.entries.map((e) => e.code).toList(),
  );
  const mixer = ShadeMixer();

  group('the grid', () {
    test('is 21 combinations for a pair and 231 for a triple', () {
      expect(ShadeMixer.compositions(20, 2).length, 21);
      expect(ShadeMixer.compositions(20, 3).length, 231);
    });

    test('every combination sums to the whole', () {
      for (final weights in ShadeMixer.compositions(20, 3)) {
        expect(weights.reduce((a, b) => a + b), 20);
        expect(weights.every((w) => w >= 0), isTrue);
      }
    });
  });

  group('rounding to whole ten per cent', () {
    test('keeps the sum at exactly one', () {
      for (final weights in [
        [0.35, 0.65],
        [0.05, 0.95],
        [0.33, 0.34, 0.33],
        [0.45, 0.25, 0.30],
        [1.0, 0.0],
      ]) {
        final rounded = ShadeMixer.roundWeights(weights);
        expect(rounded.reduce((a, b) => a + b), closeTo(1, 1e-12));
      }
    });

    test('uses largest remainder, not independent rounding', () {
      // Rounding each weight on its own would give 0.3 + 0.3 + 0.3 = 0.9.
      final rounded = ShadeMixer.roundWeights([0.33, 0.34, 0.33]);
      expect(rounded, [0.3, 0.4, 0.3]);
    });

    test('can round a component away entirely', () {
      final rounded = ShadeMixer.roundWeights([0.05, 0.95]);
      expect(rounded, [0.1, 0.9]);
      final smaller = ShadeMixer.roundWeights([0.04, 0.96]);
      expect(smaller, [0.0, 1.0]);
    });

    test('is deterministic when fractions tie', () {
      expect(
        ShadeMixer.roundWeights([0.25, 0.25, 0.5]),
        ShadeMixer.roundWeights([0.25, 0.25, 0.5]),
      );
    });
  });

  group('the gate', () {
    test('declines when the single shade is already imperceptible', () {
      final outcome = mixer.search(
        target: const LabColor(75, 1.2, 14),
        candidates: [library['A2']!],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: 0.4,
      );
      expect(outcome, isA<MixDeclined>());
      expect(
        (outcome as MixDeclined).reason,
        MixRejectionReason.singleShadeAlreadyGoodEnough,
      );
    });

    test('declines when nothing has a structural neighbour', () {
      final lonely = ShadeLibrary(
        id: 'lonely',
        system: ShadeSystem.classicalCompatible,
        entries: [entry('A1', 78, 0.5, 10), entry('C4', 64, 4, 24)],
      );
      final outcome = mixer.search(
        target: const LabColor(71, 2, 17),
        candidates: lonely.entries,
        library: lonely,
        adjacency: ShadeAdjacency.forSystem(
          ShadeSystem.classicalCompatible,
          const ['A1', 'C4'],
        ),
        bestSingleDeltaE: 5,
      );
      expect(outcome, isA<MixDeclined>());
      expect(
        (outcome as MixDeclined).reason,
        MixRejectionReason.noStructuralNeighbours,
      );
    });

    test('offers a mixture that lands between two neighbours', () {
      // Halfway between A2 and A3, where no single shade can reach.
      final target = XyzColor.weightedMean(
        [library['A2']!.lab.toXyz(), library['A3']!.lab.toXyz()],
        const [0.5, 0.5],
      ).toLab();
      const matcher = ShadeMatcher();
      final best = matcher.best(target: target, library: library);
      final outcome = mixer.search(
        target: target,
        candidates: [best.entry],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: best.deltaE2000,
      );
      expect(outcome, isA<MixOffered>());
      final offered = outcome as MixOffered;
      expect(
        offered.result.roundedComponents.map((c) => c.entry.code),
        containsAll(['A2', 'A3']),
      );
      expect(offered.result.roundedDeltaE2000, lessThan(best.deltaE2000));
      expect(offered.improvement, greaterThanOrEqualTo(kMixImprovementMin));
    });

    test('measures the improvement on the rounded mixture', () {
      final target = XyzColor.weightedMean(
        [library['A2']!.lab.toXyz(), library['A3']!.lab.toXyz()],
        const [0.5, 0.5],
      ).toLab();
      const matcher = ShadeMatcher();
      final best = matcher.best(target: target, library: library);
      final offered = mixer.search(
        target: target,
        candidates: [best.entry],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: best.deltaE2000,
      ) as MixOffered;
      // Opening the gate with the optimum and handing over the rounded version
      // would promise a gain that was never delivered.
      expect(
        offered.improvement,
        closeTo(best.deltaE2000 - offered.result.roundedDeltaE2000, 1e-12),
      );
      expect(offered.result.roundingPenalty, greaterThanOrEqualTo(0));
    });
  });

  group('mixture structure', () {
    test('never mixes more than three components', () {
      const target = LabColor(71, 2.3, 19);
      final outcome = mixer.search(
        target: target,
        candidates: [library['A3']!],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: 3,
      );
      if (outcome is MixOffered) {
        expect(
          outcome.result.components.length,
          lessThanOrEqualTo(kMaxMixComponents),
        );
      }
    });

    test('only mixes pairwise adjacent shades', () {
      final outcome = mixer.search(
        target: const LabColor(71, 2.3, 19),
        candidates: library.entries,
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: 3,
      );
      if (outcome is MixOffered) {
        final codes =
            outcome.result.components.map((c) => c.entry.code).toList();
        for (var i = 0; i < codes.length; i++) {
          for (var j = i + 1; j < codes.length; j++) {
            expect(
              adjacency.areNeighbours(codes[i], codes[j]),
              isTrue,
              reason: '${codes[i]} and ${codes[j]} are not adjacent',
            );
          }
        }
      }
    });

    test('components are ordered by share, strongest first', () {
      final target = XyzColor.weightedMean(
        [library['A2']!.lab.toXyz(), library['A3']!.lab.toXyz()],
        const [0.7, 0.3],
      ).toLab();
      final outcome = mixer.search(
        target: target,
        candidates: [library['A2']!],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: 2,
      );
      if (outcome is MixOffered) {
        final weights =
            outcome.result.roundedComponents.map((c) => c.weight).toList();
        for (var i = 1; i < weights.length; i++) {
          expect(weights[i - 1], greaterThanOrEqualTo(weights[i]));
        }
      }
    });

    test('percentages are whole tens', () {
      final target = XyzColor.weightedMean(
        [library['A2']!.lab.toXyz(), library['A3']!.lab.toXyz()],
        const [0.5, 0.5],
      ).toLab();
      final outcome = mixer.search(
        target: target,
        candidates: [library['A2']!],
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: 2,
      ) as MixOffered;
      for (final component in outcome.result.roundedComponents) {
        expect(component.percent % 10, 0);
      }
      expect(
        outcome.result.roundedComponents
            .map((c) => c.percent)
            .reduce((a, b) => a + b),
        100,
      );
    });
  });
}
