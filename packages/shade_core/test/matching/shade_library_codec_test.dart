import 'dart:convert';
import 'dart:io';

import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> load(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  const classicalPath =
      '../../assets/shade_libraries/vita_classical_compatible.json';
  const masterPath =
      '../../assets/shade_libraries/vita_3d_master_compatible.json';

  Map<String, Object?> minimal({
    Object? version = 1,
    Object? whitePoint = 'D65_2deg',
    Object? system = 'classicalCompatible',
    List<Object?>? entries,
  }) =>
      {
        'schemaVersion': version,
        'id': 'test',
        'system': system,
        'whitePoint': whitePoint,
        'entries': entries ??
            [
              {
                'code': 'A1',
                'lab': {'l': 78.0, 'a': 0.5, 'b': 10.0},
                'source': 'unverifiedPlaceholder',
                'measuredAtUtc': null,
              },
            ],
      };

  group('the shipped libraries', () {
    test('the classical library parses and holds sixteen shades', () {
      final library = ShadeLibraryCodec.decode(load(classicalPath));
      expect(library.length, 16);
      expect(library.system, ShadeSystem.classicalCompatible);
      expect(library['A3.5'], isNotNull);
    });

    test('the three-dimensional library parses and holds twenty-nine shades',
        () {
      final library = ShadeLibraryCodec.decode(load(masterPath));
      expect(library.length, 29);
      expect(library.system, ShadeSystem.threeDimensionalMasterCompatible);
      expect(library['2M2'], isNotNull);
    });

    test('every shipped value is marked unverified', () {
      // The shipped values are a structural scaffold, not measurements. If this
      // fails, something has started claiming a provenance it does not have.
      for (final path in [classicalPath, masterPath]) {
        final library = ShadeLibraryCodec.decode(load(path));
        expect(library.containsPlaceholders, isTrue);
        expect(library.clinicalCoverage, 0);
        for (final entry in library.entries) {
          expect(entry.source, ShadeValueSource.unverifiedPlaceholder);
          expect(entry.measuredAtUtc, isNull);
        }
      }
    });

    test('no two shipped shades are indistinguishable', () {
      // A match between two shades closer than the perceptibility threshold
      // would be arbitrary, which is worse than a coarser library.
      for (final path in [classicalPath, masterPath]) {
        final library = ShadeLibraryCodec.decode(load(path));
        for (var i = 0; i < library.entries.length; i++) {
          for (var j = i + 1; j < library.entries.length; j++) {
            expect(
              DeltaE2000.scalar(
                library.entries[i].lab,
                library.entries[j].lab,
              ),
              greaterThan(kImperceptibleDeltaE),
              reason: '${library.entries[i].code} vs '
                  '${library.entries[j].code}',
            );
          }
        }
      }
    });

    test('the ordering of each family holds', () {
      final library = ShadeLibraryCodec.decode(load(classicalPath));
      // A higher chroma step must really be darker and more chromatic. A
      // scaffold that got this wrong would be worse than useless.
      for (final codes in ClassicalShadeCode.familyOrder.values) {
        for (var i = 1; i < codes.length; i++) {
          final previous = library[codes[i - 1]]!.lab;
          final current = library[codes[i]]!.lab;
          expect(
            current.lightness,
            lessThan(previous.lightness),
            reason: codes[i],
          );
          expect(
            current.chroma,
            greaterThan(previous.chroma),
            reason: codes[i],
          );
        }
      }
    });

    test('the value groups of the three-dimensional guide descend', () {
      final library = ShadeLibraryCodec.decode(load(masterPath));
      for (final chroma in ['M1', 'M2']) {
        for (var group = 1; group <= 4; group++) {
          final lighter = library['${group - 1}$chroma'];
          final darker = library['$group$chroma'];
          if (lighter == null || darker == null) continue;
          expect(
            darker.lab.lightness,
            lessThan(lighter.lab.lightness),
            reason: '$group$chroma',
          );
        }
      }
    });
  });

  group('validation', () {
    test('accepts a minimal library', () {
      expect(ShadeLibraryCodec.decode(minimal()).length, 1);
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => ShadeLibraryCodec.decode(minimal(version: 2)),
        throwsFormatException,
      );
    });

    test('rejects a library stated under another white point', () {
      // A library measured under D50 is not comparable with a D65 measurement,
      // and the mistake would otherwise be invisible.
      expect(
        () => ShadeLibraryCodec.decode(minimal(whitePoint: 'D50_2deg')),
        throwsFormatException,
      );
    });

    test('rejects an unknown system', () {
      expect(
        () => ShadeLibraryCodec.decode(minimal(system: 'myOwnGuide')),
        throwsFormatException,
      );
    });

    test('rejects an entry with no lab values', () {
      expect(
        () => ShadeLibraryCodec.decode(
          minimal(
            entries: [
              {'code': 'A1', 'source': 'unverifiedPlaceholder'},
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects a clinical measurement with no date', () {
      // A measurement with no date cannot be judged against the age of the
      // guide it was taken from.
      expect(
        () => ShadeLibraryCodec.decode(
          minimal(
            entries: [
              {
                'code': 'A1',
                'lab': {'l': 78.0, 'a': 0.5, 'b': 10.0},
                'source': 'clinicalMeasurement',
                'measuredAtUtc': null,
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate codes', () {
      expect(
        () => ShadeLibraryCodec.decode(
          minimal(
            entries: [
              {
                'code': 'A1',
                'lab': {'l': 78.0, 'a': 0.5, 'b': 10.0},
                'source': 'unverifiedPlaceholder',
              },
              {
                'code': 'A1',
                'lab': {'l': 77.0, 'a': 0.6, 'b': 11.0},
                'source': 'unverifiedPlaceholder',
              },
            ],
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('clinical overrides', () {
    test('replace the shipped value and raise the coverage', () {
      final base = ShadeLibraryCodec.decode(load(classicalPath));
      final updated = ShadeLibraryCodec.applyClinicalOverrides(
        base: base,
        measured: [
          ShadeEntry(
            code: 'A2',
            lab: const LabColor(74.1, 1.9, 15.2),
            source: ShadeValueSource.clinicalMeasurement,
            measuredAtUtc: DateTime.utc(2026, 10, 22),
          ),
        ],
      );
      expect(updated.length, base.length);
      expect(updated['A2']!.source, ShadeValueSource.clinicalMeasurement);
      expect(updated['A2']!.lab.lightness, 74.1);
      expect(updated.clinicalCoverage, closeTo(1 / 16, 1e-12));
      // The shipped library is untouched.
      expect(base['A2']!.source, ShadeValueSource.unverifiedPlaceholder);
    });

    test('may extend a guide with a shade the clinic also owns', () {
      final base = ShadeLibraryCodec.decode(load(classicalPath));
      final updated = ShadeLibraryCodec.applyClinicalOverrides(
        base: base,
        measured: [
          ShadeEntry(
            code: 'BL2',
            lab: const LabColor(84, -0.4, 6),
            source: ShadeValueSource.clinicalMeasurement,
            measuredAtUtc: DateTime.utc(2026, 10, 22),
          ),
        ],
      );
      expect(updated.length, base.length + 1);
      expect(updated['BL2'], isNotNull);
    });

    test('refuses an override that is not a clinical measurement', () {
      final base = ShadeLibraryCodec.decode(minimal());
      expect(
        () => ShadeLibraryCodec.applyClinicalOverrides(
          base: base,
          measured: [
            const ShadeEntry(
              code: 'A1',
              lab: LabColor(70, 1, 12),
              source: ShadeValueSource.unverifiedPlaceholder,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
