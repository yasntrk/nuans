import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected distances computed by the Stage 2 reference oracle.
///
/// The Lab values below are SYNTHETIC. They are not shade guide reference data
/// and must never be mistaken for it: the point of these tests is the search
/// and the deviation semantics, not the colorimetry of any real guide.
void main() {
  ShadeEntry entry(String code, double l, double a, double b) => ShadeEntry(
        code: code,
        lab: LabColor(l, a, b),
        source: ShadeValueSource.clinicalMeasurement,
        measuredAtUtc: DateTime.utc(2026, 10, 21),
      );

  ShadeLibrary library() => ShadeLibrary(
        id: 'synthetic_test_library',
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

  const matcher = ShadeMatcher();
  const target = LabColor(74.5, 1.3, 14.5);

  group('library', () {
    test('indexes entries by code', () {
      final lib = library();
      expect(lib['A2']?.lab.lightness, 75);
      expect(lib['nope'], isNull);
      expect(lib.length, 6);
    });

    test('rejects duplicate codes', () {
      expect(
        () => ShadeLibrary(
          id: 'dupe',
          system: ShadeSystem.classicalCompatible,
          entries: [entry('A1', 78, 0.5, 10), entry('A1', 77, 0.6, 11)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty library', () {
      expect(
        () => ShadeLibrary(
          id: 'empty',
          system: ShadeSystem.classicalCompatible,
          entries: const [],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a library too large for brute force', () {
      expect(
        () => ShadeLibrary(
          id: 'huge',
          system: ShadeSystem.classicalCompatible,
          entries: List<ShadeEntry>.generate(
            kMaxLibraryEntries + 1,
            (i) => entry('S$i', 70 + i % 10, 1, 12),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('its entry list cannot be mutated from outside', () {
      expect(
        () => library().entries.add(entry('X1', 70, 1, 12)),
        throwsUnsupportedError,
      );
    });

    test('tracks placeholder coverage', () {
      final mixed = ShadeLibrary(
        id: 'mixed',
        system: ShadeSystem.classicalCompatible,
        entries: [
          entry('A1', 78, 0.5, 10),
          const ShadeEntry(
            code: 'A2',
            lab: LabColor(75, 1.2, 14),
            source: ShadeValueSource.unverifiedPlaceholder,
          ),
        ],
      );
      expect(mixed.containsPlaceholders, isTrue);
      expect(mixed.clinicalCoverage, 0.5);
      expect(library().containsPlaceholders, isFalse);
      expect(library().clinicalCoverage, 1);
    });
  });

  group('nearest search', () {
    test('finds the closest shade with the computed distance', () {
      final best = matcher.best(target: target, library: library());
      expect(best.entry.code, 'A2');
      expect(best.deltaE2000, closeTo(0.4863746194, 1e-9));
      expect(best.band, AcceptabilityBand.imperceptible);
    });

    test('returns the top three in order', () {
      final matches = matcher.findNearest(
        target: target,
        library: library(),
      );
      expect(matches.map((m) => m.entry.code), ['A2', 'B2', 'A3']);
      expect(matches[0].deltaE2000, closeTo(0.4863746194, 1e-9));
      expect(matches[1].deltaE2000, closeTo(1.9789392092, 1e-9));
      expect(matches[2].deltaE2000, closeTo(2.8165003406, 1e-9));
    });

    test('bands follow the published thresholds', () {
      final matches = matcher.findNearest(
        target: target,
        library: library(),
        count: 6,
      );
      // A2 at 0.486 is imperceptible; B2 at 1.979 has already passed the 1.8
      // acceptability threshold, so only the closest shade is usable alone.
      expect(matches[0].band, AcceptabilityBand.imperceptible);
      expect(matches[1].band, AcceptabilityBand.unacceptable);
      expect(matches[2].band, AcceptabilityBand.unacceptable);
      expect(
        matches.where((m) => m.band == AcceptabilityBand.imperceptible),
        hasLength(1),
      );
    });

    test('never returns more than the library holds', () {
      final matches = matcher.findNearest(
        target: target,
        library: library(),
        count: 99,
      );
      expect(matches, hasLength(6));
    });

    test('breaks ties by code, so the order is reproducible', () {
      final tied = ShadeLibrary(
        id: 'tied',
        system: ShadeSystem.classicalCompatible,
        entries: [
          entry('Z9', 80, 0, 10),
          entry('Z1', 80, 0, 10),
          entry('M5', 60, 0, 10),
        ],
      );
      final matches = matcher.findNearest(
        target: const LabColor(80, 0, 10),
        library: tied,
      );
      expect(matches[0].deltaE2000, matches[1].deltaE2000);
      expect(matches.map((m) => m.entry.code), ['Z1', 'Z9', 'M5']);
    });

    test('refuses a non-positive count', () {
      expect(
        () => matcher.findNearest(
          target: target,
          library: library(),
          count: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('deviation semantics', () {
    test('a lighter tooth reads as lighter', () {
      final match = matcher.best(
        target: const LabColor(76, 2, 18),
        library: ShadeLibrary(
          id: 'one',
          system: ShadeSystem.classicalCompatible,
          entries: [entry('A3', 72, 2, 18)],
        ),
      );
      expect(match.dominant.component, DeltaE2000Component.lightness);
      expect(
        match.dominant.direction,
        ShadeDeviationDirection.lighter,
      );
      expect(match.dominant.weightedValue, closeTo(2.954410, 1e-6));
      expect(match.dominant.magnitude, ComponentMagnitude.pronounced);
    });

    test('a more saturated tooth reads as more chromatic', () {
      final match = matcher.best(
        target: const LabColor(72, 2, 22),
        library: ShadeLibrary(
          id: 'one',
          system: ShadeSystem.classicalCompatible,
          entries: [entry('A3', 72, 2, 18)],
        ),
      );
      expect(match.dominant.component, DeltaE2000Component.chroma);
      expect(
        match.dominant.direction,
        ShadeDeviationDirection.moreChromatic,
      );
      expect(match.dominant.weightedValue, closeTo(2.079597, 1e-6));
    });

    test('deviations are ordered strongest first', () {
      final match = matcher.best(target: target, library: library());
      final magnitudes =
          match.deviations.map((d) => d.weightedValue.abs()).toList();
      expect(magnitudes[0], greaterThanOrEqualTo(magnitudes[1]));
      expect(magnitudes[1], greaterThanOrEqualTo(magnitudes[2]));
      expect(match.deviations, hasLength(3));
    });

    test('a near-perfect match has nothing worth mentioning', () {
      final match = matcher.best(target: target, library: library());
      // Every component of a 0.49 difference is below the 0.5 wording floor.
      expect(match.notableDeviations, isEmpty);
    });

    test('wording bands classify by magnitude', () {
      const thresholds = ComponentWordingThresholds();
      expect(thresholds.classify(0.2), ComponentMagnitude.negligible);
      expect(thresholds.classify(-0.2), ComponentMagnitude.negligible);
      expect(thresholds.classify(0.7), ComponentMagnitude.slight);
      expect(thresholds.classify(-1.4), ComponentMagnitude.moderate);
      expect(thresholds.classify(3), ComponentMagnitude.pronounced);
    });
  });

  group('hue direction', () {
    test('maps the quadrant and the sign onto a named direction', () {
      // Quadrant 0, red to yellow: this is where teeth live.
      expect(
        ShadeMatcher.hueDirection(45, 1),
        ShadeDeviationDirection.towardYellow,
      );
      expect(
        ShadeMatcher.hueDirection(45, -1),
        ShadeDeviationDirection.towardRed,
      );
      // Quadrant 1, yellow to green.
      expect(
        ShadeMatcher.hueDirection(120, 1),
        ShadeDeviationDirection.towardGreen,
      );
      expect(
        ShadeMatcher.hueDirection(120, -1),
        ShadeDeviationDirection.towardYellow,
      );
      // Quadrant 2, green to blue.
      expect(
        ShadeMatcher.hueDirection(200, 1),
        ShadeDeviationDirection.towardBlue,
      );
      // Quadrant 3, blue back to red.
      expect(
        ShadeMatcher.hueDirection(300, 1),
        ShadeDeviationDirection.towardRed,
      );
      expect(
        ShadeMatcher.hueDirection(300, -1),
        ShadeDeviationDirection.towardBlue,
      );
    });

    test('wraps angles outside 0 to 360', () {
      expect(
        ShadeMatcher.hueDirection(405, 1),
        ShadeMatcher.hueDirection(45, 1),
      );
      expect(
        ShadeMatcher.hueDirection(-315, 1),
        ShadeMatcher.hueDirection(45, 1),
      );
    });
  });

  group('acceptability thresholds', () {
    test('classify at and around the boundaries', () {
      const thresholds = AcceptabilityThresholds();
      expect(thresholds.classify(0), AcceptabilityBand.imperceptible);
      expect(thresholds.classify(0.8), AcceptabilityBand.imperceptible);
      expect(thresholds.classify(0.81), AcceptabilityBand.acceptable);
      expect(thresholds.classify(1.8), AcceptabilityBand.acceptable);
      expect(thresholds.classify(1.81), AcceptabilityBand.unacceptable);
    });

    test('use the published constants by default', () {
      const thresholds = AcceptabilityThresholds();
      expect(thresholds.imperceptible, kImperceptibleDeltaE);
      expect(thresholds.acceptable, kAcceptableDeltaE);
    });
  });
}
