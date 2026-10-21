import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected values computed by `tools/spec_oracle/fixtures.py`: a card lit at
/// roughly 5500 K, exposed so that its green channel sits on the protocol's
/// target of 0.45.
void main() {
  const card = CameraRgb(0.5033565720, 0.4500000000, 0.3754552925);

  final ccm = ColorCorrectionMatrix(
    matrix: Srgb.linearToXyzD65,
    whitePoint: WhitePoint.d65,
    source: CcmSource.chartFit,
  );

  group('GrayCardCorrection', () {
    test('derives the von Kries gains', () {
      final correction = GrayCardCorrection.fromMeasurement(cardMedian: card);
      // Computed from the card literal above, not from the unrounded
      // intermediate the fixture generator held: the literal is rounded to ten
      // decimals, and the gain differs from the generator's value in the
      // eleventh.
      expect(correction.gains.x, closeTo(0.8939984596048943, 1e-15));
      expect(correction.gains.y, 1);
      expect(correction.gains.z, closeTo(1.1985448307404005, 1e-15));
    });

    test('the green gain is always exactly one', () {
      // Green is the anchor because the Bayer pattern samples it twice as
      // often, so anchoring there amplifies noise the least.
      for (final measurement in [
        card,
        const CameraRgb(0.2, 0.3, 0.4),
        const CameraRgb(0.7, 0.1, 0.9),
      ]) {
        expect(
          GrayCardCorrection.fromMeasurement(cardMedian: measurement).gains.y,
          1,
        );
      }
    });

    test('the gains make the card neutral in camera space', () {
      final correction = GrayCardCorrection.fromMeasurement(cardMedian: card);
      final balanced = correction.balancedCard;
      expect(balanced.red, closeTo(0.45, 1e-12));
      expect(balanced.green, closeTo(0.45, 1e-12));
      expect(balanced.blue, closeTo(0.45, 1e-12));
    });

    test('derives the exposure scale from the known reflectance', () {
      final correction = GrayCardCorrection.fromMeasurement(cardMedian: card);
      expect(correction.exposureScale, closeTo(0.4, 1e-12));
    });

    test('refuses a measurement with a dead channel', () {
      expect(
        () => GrayCardCorrection.fromMeasurement(
          cardMedian: const CameraRgb(0.4, 0.4, 0),
        ),
        throwsArgumentError,
      );
    });

    test('refuses an impossible reflectance', () {
      expect(
        () => GrayCardCorrection.fromMeasurement(
          cardMedian: card,
          cardReflectanceY: 1.4,
        ),
        throwsArgumentError,
      );
      expect(
        () => GrayCardCorrection.fromMeasurement(
          cardMedian: card,
          cardReflectanceY: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('CaptureTransform', () {
    final transform = CaptureTransform.from(
      ccm: ccm,
      grayCard: GrayCardCorrection.fromMeasurement(cardMedian: card),
    );

    test('the corrected card is neutral at the reflectance lightness', () {
      // This is the invariant the specification calls out: the grey card check
      // "a* and b* are about zero after correction" holds BY CONSTRUCTION, so
      // it belongs here as a test rather than in the runtime validator, where
      // it would also pass for a photograph of a blue lens cap.
      final lab = transform.toXyz(card).toLab();
      expect(lab.lightness, closeTo(49.4961076101, 1e-9));
      expect(lab.a.abs(), lessThan(1e-12));
      expect(lab.b.abs(), lessThan(1e-12));
    });

    test('absolute lightness survives a change of exposure', () {
      // The same scene, two stops darker. The card correction must absorb it.
      final darker = CaptureTransform.from(
        ccm: ccm,
        grayCard: GrayCardCorrection.fromMeasurement(
          cardMedian: card.scaled(0.25),
        ),
      );
      final bright = transform.toXyz(card).toLab();
      final dark = darker.toXyz(card.scaled(0.25)).toLab();
      expect(dark.lightness, closeTo(bright.lightness, 1e-12));
      expect(dark.a, closeTo(bright.a, 1e-12));
      expect(dark.b, closeTo(bright.b, 1e-12));
    });

    test('absolute lightness survives a change of light colour', () {
      // A warmer light: more red, less blue, same green. After the card
      // correction the measured tooth colour must not move.
      final warmCard = CameraRgb(
        card.red * 1.18,
        card.green,
        card.blue * 0.82,
      );
      final warmTransform = CaptureTransform.from(
        ccm: ccm,
        grayCard: GrayCardCorrection.fromMeasurement(cardMedian: warmCard),
      );
      const tooth = CameraRgb(0.62, 0.58, 0.47);
      final warmTooth = CameraRgb(
        tooth.red * 1.18,
        tooth.green,
        tooth.blue * 0.82,
      );
      final neutralLab = transform.toXyz(tooth).toLab();
      final warmLab = warmTransform.toXyz(warmTooth).toLab();
      expect(warmLab.lightness, closeTo(neutralLab.lightness, 1e-12));
      expect(warmLab.a, closeTo(neutralLab.a, 1e-12));
      expect(warmLab.b, closeTo(neutralLab.b, 1e-12));
    });

    test('the card comes back out at its own reflectance', () {
      expect(transform.luminanceOf(card), closeTo(0.18, 1e-12));
      expect(transform.isSelfConsistent, isTrue);
    });

    test('a perfect diffuser reads luminance one', () {
      // The perfect diffuser in camera space is the card divided by its
      // reflectance, NOT the triple (1, 1, 1): after the von Kries gains that
      // triple is no longer neutral, so the matrix row sums are not it.
      expect(
        transform.luminanceOf(card.scaled(1 / 0.18)),
        closeTo(1, 1e-12),
      );
      expect(transform.matrix.rowSums.y, closeTo(0.396714528792, 1e-11));
      expect(transform.matrix.rowSums.y, isNot(closeTo(1, 1e-3)));
    });

    test('the relative mode correction is applied last', () {
      const measuredTab = XyzColor(0.600, 0.620, 0.520);
      const libraryTab = XyzColor(0.606, 0.625, 0.527);
      final withRelative = CaptureTransform.from(
        ccm: ccm,
        grayCard: GrayCardCorrection.fromMeasurement(cardMedian: card),
        relativeModeCorrection: ChromaticAdaptation.coneRatioCorrection(
          measured: measuredTab,
          expected: libraryTab,
        ),
      );
      expect(withRelative.hasRelativeModeCorrection, isTrue);
      expect(transform.hasRelativeModeCorrection, isFalse);
      // The correction shifts the result, and not by nothing.
      const tooth = CameraRgb(0.62, 0.58, 0.47);
      final shifted = withRelative.toXyz(tooth);
      final plain = transform.toXyz(tooth);
      expect(shifted.y, isNot(closeTo(plain.y, 1e-9)));
    });
  });

  group('DeviceProfile', () {
    test('a manufacturer matrix is worth less than a chart fit', () {
      final dng = DeviceProfile.fromDngMatrix(
        deviceModel: 'Synthetic1,1',
        lensId: 'wide',
        cameraToXyz: Srgb.linearToXyzD65,
        createdAtUtc: DateTime.utc(2026, 10, 21),
        isForwardMatrix: true,
      );
      expect(dng.isChartFitted, isFalse);
      expect(dng.confidenceScore, 0.3);
      expect(dng.key, 'Synthetic1,1/wide');

      final fitted = DeviceProfile(
        deviceModel: 'Synthetic1,1',
        lensId: 'wide',
        ccm: ccm,
        createdAtUtc: DateTime.utc(2026, 10, 21),
        quality: const CcmQualityReport(
          meanDeltaE2000: 0.4,
          maxDeltaE2000: 0.9,
          residuals: [],
          gate: kCcmMeanDeltaEGate,
        ),
      );
      expect(fitted.isChartFitted, isTrue);
      expect(fitted.confidenceScore, 1);
      expect(fitted.confidenceScore, greaterThan(dng.confidenceScore));
    });

    test('a chart fit with no quality report scores nothing', () {
      final profile = DeviceProfile(
        deviceModel: 'Synthetic1,1',
        lensId: 'wide',
        ccm: ccm,
        createdAtUtc: DateTime.utc(2026, 10, 21),
      );
      expect(profile.confidenceScore, 0);
    });
  });
}
