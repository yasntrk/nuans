import 'dart:convert';
import 'dart:io';

import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  LayeringRuleTable shipped() => LayeringRuleTable.fromJson(
        jsonDecode(
          File('../../assets/rules/composite_layering_rules.json')
              .readAsStringSync(),
        ) as Map<String, Object?>,
      );

  group('the shipped table', () {
    test('parses', () {
      final table = shipped();
      expect(table.id, 'composite_layering_v1');
      expect(table.schemaVersion, LayeringRuleTable.supportedSchemaVersion);
      expect(table.enamelRules, isNotEmpty);
    });

    test('ends with a catch-all, so selection can never fail', () {
      final table = shipped();
      final last = table.enamelRules.last;
      expect(
        last.matches(incisalLightness: 0, blueShift: 0, incisalChroma: 0),
        isTrue,
      );
      expect(
        last.matches(incisalLightness: 100, blueShift: 50, incisalChroma: 60),
        isTrue,
      );
    });

    test('selects something for any plausible measurement', () {
      final table = shipped();
      for (final lightness in [60.0, 70.0, 76.0, 84.0]) {
        for (final shift in [-8.0, -3.0, -1.0, 2.0]) {
          for (final chroma in [8.0, 16.0, 28.0]) {
            expect(
              table.select(
                incisalLightness: lightness,
                blueShift: shift,
                incisalChroma: chroma,
              ),
              isNotNull,
              reason: 'L* $lightness, shift $shift, C* $chroma',
            );
          }
        }
      }
    });

    test('ships with an empty brand mapping', () {
      // Filling it means copying names off a manufacturer's chart; inventing
      // them would put made-up product data in front of a technician.
      final table = shipped();
      expect(table.mappedBrands, isEmpty);
      expect(
        table.productName(kind: EnamelKind.translucent, brand: 'anyBrand'),
        isNull,
      );
    });
  });

  group('rule ordering', () {
    test('the first match wins', () {
      final table = LayeringRuleTable.fromJson(const {
        'schemaVersion': 1,
        'id': 'ordering',
        'enamelRules': [
          {
            'id': 'specific',
            'when': {'blueShiftMax': -4.0},
            'enamel': 'opalescent',
          },
          {
            'id': 'general',
            'when': {'blueShiftMax': -1.0},
            'enamel': 'translucent',
          },
          {'id': 'default', 'when': <String, Object?>{}, 'enamel': 'universal'},
        ],
      });
      expect(
        table
            .select(incisalLightness: 75, blueShift: -6, incisalChroma: 12)!
            .id,
        'specific',
      );
      expect(
        table
            .select(incisalLightness: 75, blueShift: -2, incisalChroma: 12)!
            .id,
        'general',
      );
      expect(
        table.select(incisalLightness: 75, blueShift: 1, incisalChroma: 12)!.id,
        'default',
      );
    });
  });

  group('bounds', () {
    test('an absent bound is not a constraint', () {
      const rule = EnamelRule(id: 'open', enamel: EnamelKind.universal);
      expect(
        rule.matches(incisalLightness: -50, blueShift: 100, incisalChroma: 0),
        isTrue,
      );
    });

    test('bounds are inclusive', () {
      const rule = EnamelRule(
        id: 'bounded',
        enamel: EnamelKind.bleach,
        incisalLightnessMin: 82,
        incisalChromaMax: 12,
      );
      expect(
        rule.matches(incisalLightness: 82, blueShift: 0, incisalChroma: 12),
        isTrue,
      );
      expect(
        rule.matches(incisalLightness: 81.9, blueShift: 0, incisalChroma: 12),
        isFalse,
      );
      expect(
        rule.matches(incisalLightness: 82, blueShift: 0, incisalChroma: 12.1),
        isFalse,
      );
    });
  });

  group('validation', () {
    test('rejects an unsupported schema version', () {
      expect(
        () => LayeringRuleTable.fromJson(const {
          'schemaVersion': 99,
          'id': 'future',
          'enamelRules': [
            {'id': 'a', 'enamel': 'universal'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects duplicate rule ids', () {
      expect(
        () => LayeringRuleTable.fromJson(const {
          'schemaVersion': 1,
          'id': 'dupes',
          'enamelRules': [
            {'id': 'a', 'enamel': 'universal'},
            {'id': 'a', 'enamel': 'translucent'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects an unknown enamel kind', () {
      expect(
        () => LayeringRuleTable.fromJson(const {
          'schemaVersion': 1,
          'id': 'unknown',
          'enamelRules': [
            {'id': 'a', 'enamel': 'iridescent'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects an empty rule list', () {
      expect(
        () => LayeringRuleTable.fromJson(const {
          'schemaVersion': 1,
          'id': 'empty',
          'enamelRules': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-numeric bound', () {
      expect(
        () => LayeringRuleTable.fromJson(const {
          'schemaVersion': 1,
          'id': 'bad',
          'enamelRules': [
            {
              'id': 'a',
              'when': {'blueShiftMax': 'very'},
              'enamel': 'universal',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
