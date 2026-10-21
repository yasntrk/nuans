import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  group('classical codes', () {
    test('parses the sixteen codes of the guide', () {
      for (final codes in ClassicalShadeCode.familyOrder.values) {
        for (final code in codes) {
          final parsed = ClassicalShadeCode.tryParse(code);
          expect(parsed, isNotNull, reason: code);
          expect(parsed!.raw, code);
        }
      }
    });

    test('keeps the half step', () {
      final parsed = ClassicalShadeCode.tryParse('A3.5')!;
      expect(parsed.family, 'A');
      expect(parsed.chroma, 3.5);
      expect(parsed.indexInFamily, 3);
    });

    test('rejects codes the guide does not print', () {
      // B3.5 and D1 look plausible and do not exist.
      expect(ClassicalShadeCode.tryParse('B3.5'), isNull);
      expect(ClassicalShadeCode.tryParse('D1'), isNull);
      expect(ClassicalShadeCode.tryParse('A5'), isNull);
      expect(ClassicalShadeCode.tryParse('E1'), isNull);
      expect(ClassicalShadeCode.tryParse(''), isNull);
    });
  });

  group('three-dimensional codes', () {
    test('parses all twenty-nine codes', () {
      expect(MasterShadeCode.allCodes, hasLength(29));
      for (final code in MasterShadeCode.allCodes) {
        expect(MasterShadeCode.tryParse(code), isNotNull, reason: code);
      }
    });

    test('splits the three axes', () {
      final parsed = MasterShadeCode.tryParse('3R2.5')!;
      expect(parsed.valueGroup, 3);
      expect(parsed.hue, MasterHue.right);
      expect(parsed.chroma, 2.5);
    });

    test('rejects codes the grid does not hold', () {
      // The grid is deliberately incomplete: the outer value groups carry only
      // the middle column, and the flanking columns carry only half steps.
      expect(MasterShadeCode.tryParse('0L1.5'), isNull);
      expect(MasterShadeCode.tryParse('2M1.5'), isNull);
      expect(MasterShadeCode.tryParse('5R2.5'), isNull);
      expect(MasterShadeCode.tryParse('6M1'), isNull);
    });

    test('knows which axes combinations exist', () {
      expect(
        MasterShadeCode.exists(
          valueGroup: 2,
          hue: MasterHue.left,
          chroma: 1.5,
        ),
        isTrue,
      );
      expect(
        MasterShadeCode.exists(
          valueGroup: 2,
          hue: MasterHue.middle,
          chroma: 1.5,
        ),
        isFalse,
      );
    });
  });

  group('classical adjacency', () {
    final adjacency = ShadeAdjacency.forSystem(
      ShadeSystem.classicalCompatible,
      [for (final codes in ClassicalShadeCode.familyOrder.values) ...codes],
    );

    test('has one edge per adjacent chroma step within each family', () {
      // A has five steps, B and C four, D three: 4 + 3 + 3 + 2 = 12.
      expect(adjacency.edgeCount, 12);
    });

    test('A3 sits between A2 and A3.5', () {
      expect(adjacency.neighboursOf('A3'), {'A2', 'A3.5'});
    });

    test('the ends of a family have one neighbour', () {
      expect(adjacency.neighboursOf('A1'), {'A2'});
      expect(adjacency.neighboursOf('A4'), {'A3.5'});
      expect(adjacency.neighboursOf('D2'), {'D3'});
    });

    test('families never connect to each other', () {
      // A technician does mix across families in practice; the guide's own
      // structure does not say they are adjacent, so v1 does not either.
      expect(adjacency.areNeighbours('A3', 'B3'), isFalse);
      expect(adjacency.areNeighbours('A2', 'C2'), isFalse);
      expect(adjacency.areNeighbours('C4', 'D4'), isFalse);
    });

    test('no shade is isolated', () {
      for (final code in adjacency.codes) {
        expect(adjacency.neighboursOf(code), isNotEmpty, reason: code);
      }
    });
  });

  group('three-dimensional adjacency', () {
    final adjacency = ShadeAdjacency.forSystem(
      ShadeSystem.threeDimensionalMasterCompatible,
      MasterShadeCode.allCodes,
    );

    test('has the expected number of edges', () {
      // 21 on the value axis, 17 on chroma, 24 on hue.
      expect(adjacency.edgeCount, 62);
    });

    test('the middle of the grid is adjacent on all three axes', () {
      expect(adjacency.neighboursOf('2M2'), {
        '1M2', '3M2', // value
        '2M1', '2M3', // chroma, within the middle column's own sequence
        '2L1.5', '2L2.5', '2R1.5', '2R2.5', // hue, the flanking half steps
      });
    });

    test('adjacent chroma uses the column sequence, not the printed numbers',
        () {
      // 1.5 lies numerically between 1 and 2, but there is no 2M1.5 tab to
      // pass through, so M1 and M2 are neighbours.
      expect(adjacency.areNeighbours('2M1', '2M2'), isTrue);
      expect(adjacency.areNeighbours('2M1', '2M3'), isFalse);
      expect(adjacency.areNeighbours('2L1.5', '2L2.5'), isTrue);
    });

    test('a flanking half step neighbours the two middle tabs it sits between',
        () {
      expect(adjacency.neighboursOf('2L1.5'), containsAll(['2M1', '2M2']));
      expect(adjacency.areNeighbours('2L1.5', '2M3'), isFalse);
    });

    test('the flanking columns never reach each other directly', () {
      // L to R would be two hue steps, which is more than the linear mixing
      // model covers.
      expect(adjacency.areNeighbours('2L1.5', '2R1.5'), isFalse);
    });

    test('the bleached group connects upward only', () {
      expect(adjacency.neighboursOf('0M1'), {'0M2', '1M1'});
      expect(adjacency.neighboursOf('0M3'), {'0M2'});
    });

    test('no shade is isolated', () {
      for (final code in adjacency.codes) {
        expect(adjacency.neighboursOf(code), isNotEmpty, reason: code);
      }
    });
  });

  group('unparseable codes', () {
    test('get no neighbours rather than an error', () {
      // A clinic may add a shade from another guide to its own library. It must
      // stay matchable, and it must never be mixed.
      final adjacency = ShadeAdjacency.forSystem(
        ShadeSystem.classicalCompatible,
        const ['A1', 'A2', 'CLINIC-SPECIAL'],
      );
      expect(adjacency.neighboursOf('CLINIC-SPECIAL'), isEmpty);
      expect(adjacency.neighboursOf('A1'), {'A2'});
    });

    test('codes from different guides are never neighbours', () {
      final adjacency = ShadeAdjacency.forSystem(
        ShadeSystem.classicalCompatible,
        const ['A1', 'A2', '2M2'],
      );
      expect(adjacency.areNeighbours('A1', '2M2'), isFalse);
    });
  });
}
