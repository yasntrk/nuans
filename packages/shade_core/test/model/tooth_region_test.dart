import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  group('FdiToothNumber', () {
    test('accepts the permanent dentition', () {
      // Quadrants 1 to 4, positions 1 to 8.
      for (var quadrant = 1; quadrant <= 4; quadrant++) {
        for (var position = 1; position <= 8; position++) {
          final code = quadrant * 10 + position;
          expect(
            FdiToothNumber.tryFrom(code),
            isNotNull,
            reason: 'tooth $code should be valid',
          );
        }
      }
    });

    test('accepts the deciduous dentition', () {
      // Quadrants 5 to 8, positions 1 to 5. A shade measurement on a primary
      // tooth is unusual but not invalid, and silently refusing one would send
      // the clinician hunting for a typo that is not there.
      for (var quadrant = 5; quadrant <= 8; quadrant++) {
        for (var position = 1; position <= 5; position++) {
          expect(FdiToothNumber.tryFrom(quadrant * 10 + position), isNotNull);
        }
      }
    });

    test('rejects a ninth position in a permanent quadrant', () {
      expect(FdiToothNumber.tryFrom(19), isNull);
      expect(FdiToothNumber.tryFrom(49), isNull);
    });

    test('rejects positions past the fifth in a deciduous quadrant', () {
      // 55 exists, 56 does not: a primary quadrant has five teeth.
      expect(FdiToothNumber.tryFrom(55), isNotNull);
      expect(FdiToothNumber.tryFrom(56), isNull);
      expect(FdiToothNumber.tryFrom(58), isNull);
    });

    test('rejects a zero quadrant or a zero position', () {
      expect(FdiToothNumber.tryFrom(1), isNull);
      expect(FdiToothNumber.tryFrom(10), isNull);
      expect(FdiToothNumber.tryFrom(50), isNull);
      expect(FdiToothNumber.tryFrom(0), isNull);
    });

    test('rejects a ninth quadrant', () {
      expect(FdiToothNumber.tryFrom(91), isNull);
      expect(FdiToothNumber.tryFrom(99), isNull);
    });

    test('parses a two-digit string', () {
      expect(FdiToothNumber.tryParse('11')?.code, '11');
      expect(FdiToothNumber.tryParse(' 21 ')?.code, '21');
    });

    test('refuses anything that is not two digits', () {
      // A report that names the wrong tooth is worse than one that names none,
      // so the parse is strict rather than forgiving.
      expect(FdiToothNumber.tryParse('1'), isNull);
      expect(FdiToothNumber.tryParse('111'), isNull);
      expect(FdiToothNumber.tryParse('1a'), isNull);
      expect(FdiToothNumber.tryParse(''), isNull);
      expect(FdiToothNumber.tryParse('  '), isNull);
    });

    test('splits into quadrant and position', () {
      final tooth = FdiToothNumber.tryParse('21')!;
      expect(tooth.quadrant, 2);
      expect(tooth.position, 1);
      expect(tooth.isDeciduous, isFalse);
      expect(tooth.code, '21');
    });

    test('knows a deciduous tooth', () {
      expect(FdiToothNumber.tryFrom(61)!.isDeciduous, isTrue);
      expect(FdiToothNumber.tryFrom(11)!.isDeciduous, isFalse);
    });

    test('the default targets are the upper central incisors', () {
      expect(FdiToothNumber.upperRightCentral.code, '11');
      expect(FdiToothNumber.upperLeftCentral.code, '21');
      expect(FdiToothNumber.upperRightCentral.quadrant, 1);
      expect(FdiToothNumber.upperLeftCentral.quadrant, 2);
    });
  });

  group('ToothRegion', () {
    test('is ordered from the gingival margin to the incisal edge', () {
      // The order is load-bearing: the overlay cuts its bands by index, and
      // the report lists the regions in the same order.
      expect(ToothRegion.values, [
        ToothRegion.cervical,
        ToothRegion.body,
        ToothRegion.incisal,
      ]);
      expect(ToothRegion.cervical.index, 0);
      expect(ToothRegion.incisal.index, 2);
    });
  });

  group('RestorativeMaterial', () {
    test('covers the three the application plans for', () {
      expect(RestorativeMaterial.values, hasLength(3));
      expect(
        RestorativeMaterial.values.map((m) => m.name),
        containsAll(['zirconia', 'metalCeramic', 'composite']),
      );
    });
  });
}
