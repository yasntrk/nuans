import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  // A card lit at roughly 5500 K, exposed to the protocol's target.
  const card = CameraRgb(0.5033565720, 0.4500000000, 0.3754552925);
  final quadrants = List<CameraRgb>.filled(4, card);

  final ccm = ColorCorrectionMatrix(
    matrix: Srgb.linearToXyzD65,
    whitePoint: WhitePoint.d65,
    source: CcmSource.chartFit,
  );

  const validator = GrayCardValidator();

  GrayCardVerdict validate({
    CameraRgb median = card,
    double uniformityRatio = 0.02,
    double clippedFraction = 0,
    List<CameraRgb>? quadrantsOverride,
  }) =>
      validator.validate(
        median: median,
        uniformityRatio: uniformityRatio,
        clippedFraction: clippedFraction,
        quadrants: quadrantsOverride ?? quadrants,
        ccm: ccm,
      );

  group('a good reading', () {
    test('passes with no issues', () {
      final verdict = validate();
      expect(verdict.isValid, isTrue);
      expect(verdict.issues, isEmpty);
    });

    test('reports the implied colour temperature', () {
      final verdict = validate();
      expect(verdict.correlatedColorTemperature, closeTo(5499.1958, 1e-3));
    });

    test('scores well on both sub-scores', () {
      final verdict = validate();
      expect(verdict.uniformityScore, closeTo(1 - 0.02 / 0.06, 1e-12));
      expect(verdict.mixedLightScore, 1);
      expect(verdict.score, verdict.uniformityScore);
    });
  });

  group('each check discriminates', () {
    test('flags a non-uniform slot', () {
      final verdict = validate(uniformityRatio: 0.12);
      expect(verdict.issues, contains(GrayCardIssue.nonUniform));
      expect(verdict.isValid, isFalse);
      expect(verdict.uniformityScore, 0);
    });

    test('flags clipping', () {
      final verdict = validate(clippedFraction: 0.05);
      expect(verdict.issues, contains(GrayCardIssue.clipped));
    });

    test('flags an under-exposed card', () {
      final verdict = validate(median: card.scaled(0.3));
      expect(verdict.issues, contains(GrayCardIssue.tooDark));
    });

    test('flags an over-exposed card', () {
      final verdict = validate(median: card.scaled(1.7));
      expect(verdict.issues, contains(GrayCardIssue.tooBright));
    });

    test('flags mixed lighting from the quadrant spread', () {
      // Two quadrants lit warm, two lit cool: the average is fine, the
      // variation is not.
      final mixed = <CameraRgb>[
        CameraRgb(card.red * 1.10, card.green, card.blue * 0.92),
        CameraRgb(card.red * 1.10, card.green, card.blue * 0.92),
        CameraRgb(card.red * 0.90, card.green, card.blue * 1.08),
        CameraRgb(card.red * 0.90, card.green, card.blue * 1.08),
      ];
      final verdict = validate(quadrantsOverride: mixed);
      expect(verdict.quadrantMaxDeltaE, isNotNull);
      expect(
        verdict.quadrantMaxDeltaE,
        greaterThan(kGrayCardQuadrantDeltaEMax),
      );
      expect(verdict.issues, contains(GrayCardIssue.mixedLight));
      expect(verdict.mixedLightScore, 0);
    });

    test('flags an implausible illuminant', () {
      // A strongly red-biased card reading implies a very warm light.
      final verdict = validate(
        median: CameraRgb(card.red * 1.9, card.green, card.blue * 0.5),
      );
      expect(verdict.issues, contains(GrayCardIssue.implausibleIlluminant));
    });
  });

  group('what the validator deliberately does not check', () {
    test('neutrality after correction would pass for anything', () {
      // A blue lens cap instead of the card. The gains force it neutral and a
      // white-point preserving matrix keeps it neutral, so a runtime "a* and
      // b* are zero" check cannot tell the two apart. The four checks above
      // can: this reading is flagged for an implausible illuminant.
      const lensCap = CameraRgb(0.18, 0.30, 0.62);
      final transform = CaptureTransform.from(
        ccm: ccm,
        grayCard: GrayCardCorrection.fromMeasurement(cardMedian: lensCap),
      );
      final lab = transform.toXyz(lensCap).toLab();
      expect(lab.a.abs(), lessThan(1e-12));
      expect(lab.b.abs(), lessThan(1e-12));

      final verdict = validate(median: lensCap);
      expect(verdict.isValid, isFalse);
    });
  });

  group('degenerate input', () {
    test('a single quadrant yields no spread verdict', () {
      final verdict = validate(quadrantsOverride: [card]);
      expect(verdict.quadrantMaxDeltaE, isNull);
      expect(verdict.issues, isNot(contains(GrayCardIssue.mixedLight)));
      // Unknown rather than good: half marks.
      expect(verdict.mixedLightScore, 0.5);
    });

    test('quadrants with dead channels are skipped', () {
      final verdict = validate(
        quadrantsOverride: [card, const CameraRgb(0, 0, 0)],
      );
      expect(verdict.quadrantMaxDeltaE, isNull);
    });
  });
}

// Values asserted above, computed by the Stage 2 reference oracle:
//   good card            ->  5499.20 K  (plausible)
//   red-biased 1.9 / 0.5 ->  3059.32 K  (too warm)
//   blue lens cap        -> 26843.98 K  (far too cool)
//   mixed-light quadrant spread -> dE00 8.956326  (threshold 1.5)
