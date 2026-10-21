import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected matrix computed by `tools/spec_oracle/fixtures.py`.
void main() {
  group('Bradford', () {
    test('the computed inverse really is the inverse', () {
      final product =
          (ChromaticAdaptation.bradford * ChromaticAdaptation.bradfordInverse)
              .toRowMajor();
      const identity = [1.0, 0, 0, 0, 1, 0, 0, 0, 1];
      for (var i = 0; i < 9; i++) {
        expect(product[i], closeTo(identity[i], 1e-12));
      }
    });

    test('D50 to D65 maps the source white onto the destination white', () {
      final matrix = ChromaticAdaptation.matrixFor(
        source: WhitePoint.d50,
        destination: WhitePoint.d65,
      );
      final adapted = matrix.apply(WhitePoint.d50.xyz);
      expect(adapted.x, closeTo(WhitePoint.d65.xyz.x, 1e-12));
      expect(adapted.y, closeTo(WhitePoint.d65.xyz.y, 1e-12));
      expect(adapted.z, closeTo(WhitePoint.d65.xyz.z, 1e-12));
    });

    test('D50 to D65 matches the reference matrix', () {
      final matrix = ChromaticAdaptation.matrixFor(
        source: WhitePoint.d50,
        destination: WhitePoint.d65,
      ).toRowMajor();
      const expected = [
        0.9555766150, -0.0230393447, 0.0631636322, //
        -0.0282895442, 1.0099416174, 0.0210076550, //
        0.0122981657, -0.0204830252, 1.3299098264, //
      ];
      for (var i = 0; i < 9; i++) {
        expect(matrix[i], closeTo(expected[i], 1e-9));
      }
    });

    test('adapting to the same white point is a no-op', () {
      const color = XyzColor(0.4, 0.5, 0.3);
      final same = ChromaticAdaptation.adapt(
        color,
        source: WhitePoint.d65,
        destination: WhitePoint.d65,
      );
      expect(same.x, closeTo(color.x, 1e-14));
      expect(same.y, closeTo(color.y, 1e-14));
      expect(same.z, closeTo(color.z, 1e-14));
    });

    test('D50 to D65 and back is the identity', () {
      const color = XyzColor(0.4, 0.5, 0.3);
      final there = ChromaticAdaptation.adapt(
        color,
        source: WhitePoint.d50,
        destination: WhitePoint.d65,
      );
      final back = ChromaticAdaptation.adapt(
        there,
        source: WhitePoint.d65,
        destination: WhitePoint.d50,
      );
      expect(back.x, closeTo(color.x, 1e-12));
      expect(back.y, closeTo(color.y, 1e-12));
      expect(back.z, closeTo(color.z, 1e-12));
    });
  });

  group('relative mode cone ratio correction', () {
    test('maps the measured tab exactly onto its library value', () {
      const measured = XyzColor(0.600, 0.620, 0.520);
      const expected = XyzColor(0.606, 0.625, 0.527);
      final correction = ChromaticAdaptation.coneRatioCorrection(
        measured: measured,
        expected: expected,
      );
      final corrected = correction.apply(measured.asVec3);
      expect(corrected.x, closeTo(expected.x, 1e-12));
      expect(corrected.y, closeTo(expected.y, 1e-12));
      expect(corrected.z, closeTo(expected.z, 1e-12));
    });

    test('clamps a wild discrepancy to plus or minus ten per cent', () {
      const measured = XyzColor(0.600, 0.620, 0.520);
      // Twice as bright: the uncorrected ratio would be 2.0 on every channel.
      final correction = ChromaticAdaptation.coneRatioCorrection(
        measured: measured,
        expected: measured.scaled(2),
      );
      final corrected = correction.apply(measured.asVec3);
      expect(corrected.y / measured.y, closeTo(kRelativeModeGainMax, 1e-9));
      expect(corrected.y / measured.y, lessThan(1.12));
    });

    test('is the identity when the tab already matches', () {
      const measured = XyzColor(0.600, 0.620, 0.520);
      final correction = ChromaticAdaptation.coneRatioCorrection(
        measured: measured,
        expected: measured,
      );
      final product = correction.toRowMajor();
      const identity = [1.0, 0, 0, 0, 1, 0, 0, 0, 1];
      for (var i = 0; i < 9; i++) {
        expect(product[i], closeTo(identity[i], 1e-12));
      }
    });

    test('refuses a black measurement, where a ratio is undefined', () {
      expect(
        () => ChromaticAdaptation.coneRatioCorrection(
          measured: XyzColor.black,
          expected: const XyzColor(0.6, 0.62, 0.52),
        ),
        throwsArgumentError,
      );
    });
  });

  group('correlated colour temperature', () {
    test('D65 chromaticity comes out near 6500 K', () {
      final c = WhitePoint.d65.chromaticity;
      final cct = CorrelatedColorTemperature.mcCamy(x: c.x, y: c.y);
      expect(cct, isNotNull);
      expect(cct, closeTo(6500, 120));
    });

    test('D50 chromaticity comes out near 5000 K', () {
      final c = WhitePoint.d50.chromaticity;
      final cct = CorrelatedColorTemperature.mcCamy(x: c.x, y: c.y);
      expect(cct, closeTo(5000, 100));
    });

    test('knows its own validity range', () {
      expect(
        CorrelatedColorTemperature.isWithinApproximationRange(5500),
        isTrue,
      );
      expect(
        CorrelatedColorTemperature.isWithinApproximationRange(9000),
        isFalse,
      );
      expect(
        CorrelatedColorTemperature.isPlausibleCaptureIlluminant(5500),
        isTrue,
      );
      expect(
        CorrelatedColorTemperature.isPlausibleCaptureIlluminant(3000),
        isFalse,
      );
    });

    test('returns null on the pole of the approximation', () {
      expect(
        CorrelatedColorTemperature.mcCamy(x: 0.4, y: kMcCamyPivotY),
        isNull,
      );
    });
  });
}
