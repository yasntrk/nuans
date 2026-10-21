import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  const scorer = ConfidenceScorer();

  RoiReduction goodReduction() => const RoiReduction(
        xyz: XyzColor(0.47, 0.47, 0.38),
        lab: LabColor(74.2, 7.6, 14.8),
        sampleCount: 400,
        acceptedSamples: 370,
        specularRejected: 20,
        shadowRejected: 10,
        rejectedFraction: 0.075,
        medianLightness: 74.3,
        lightnessMad: 1.73,
        lightnessStdDev: 1.85,
        trimmedSampleCount: 296,
      );

  ConfidenceScore scoreOf({
    CcmSource source = CcmSource.chartFit,
    double profileScore = 1.0,
    bool grayCardValid = true,
    double grayCardScore = 1.0,
    RoiReduction? reduction,
    RelativeModeState relativeMode = RelativeModeState.usedAndConsistent,
    double bestMatchDeltaE = 0.6,
    int acceptedFrameCount = 3,
  }) =>
      scorer.score(
        captureSource: source,
        profileScore: profileScore,
        grayCardValid: grayCardValid,
        grayCardScore: grayCardScore,
        reduction: reduction ?? goodReduction(),
        relativeMode: relativeMode,
        bestMatchDeltaE: bestMatchDeltaE,
        acceptedFrameCount: acceptedFrameCount,
      );

  group('weights', () {
    test('sum to one', () {
      expect(ConfidenceWeights.standard.total, closeTo(1, 1e-12));
    });

    test('the systematic group outweighs the other two together', () {
      const w = ConfidenceWeights.standard;
      final systematic = w.captureMode + w.deviceProfile + w.grayCard;
      final random = w.rejectedFraction + w.regionHomogeneity;
      final crossChecks = w.relativeMode + w.matchResidual;
      expect(systematic, closeTo(0.56, 1e-12));
      expect(random, closeTo(0.22, 1e-12));
      expect(crossChecks, closeTo(0.22, 1e-12));
      expect(systematic, greaterThan(random + crossChecks));
    });
  });

  group('a clean measurement', () {
    test('scores high but not perfect', () {
      final score = scoreOf();
      // Not 1.0, and that is the homogeneity term doing its job: the fixture's
      // lightness spread of 1.85 is past the 1.5 threshold, because a real
      // tooth has a genuine gradient. A fixture that scored a flat 1.0 would
      // be a fixture of something that is not a tooth.
      expect(score.score, closeTo(0.9922222222222222, 1e-12));
      expect(score.band, ConfidenceBand.high);
      expect(score.overrides, isEmpty);
      expect(score.terms, hasLength(7));
      final homogeneity =
          score.terms.firstWhere((t) => t.name == 'regionHomogeneity');
      expect(homogeneity.score, closeTo((6.0 - 1.85) / (6.0 - 1.5), 1e-12));
      expect(score.weakestTerm.name, 'regionHomogeneity');
    });

    test('the baseline rejected share costs nothing', () {
      // The unscaled MAD thresholds discard about 6.7% of a homogeneous region
      // on their own, so 7.5% must not read as a fault.
      final term =
          scoreOf().terms.firstWhere((t) => t.name == 'rejectedFraction');
      expect(term.score, 1);
    });
  });

  group('each term moves the score', () {
    test('a processed capture costs the mode term', () {
      final score = scoreOf(source: CcmSource.srgbProcessed);
      expect(
        score.terms.firstWhere((t) => t.name == 'captureMode').score,
        0.45,
      );
      expect(score.score, lessThan(1));
    });

    test('a manufacturer matrix costs the profile term', () {
      expect(scoreOf(profileScore: 0.3).score, lessThan(scoreOf().score));
    });

    test('not using the relative protocol costs half that term', () {
      final score = scoreOf(relativeMode: RelativeModeState.notUsed);
      expect(
        score.terms.firstWhere((t) => t.name == 'relativeMode').score,
        0.5,
      );
    });

    test('an inconsistent shade tab costs more than not using one', () {
      expect(
        scoreOf(relativeMode: RelativeModeState.usedButInconsistent).score,
        lessThan(scoreOf(relativeMode: RelativeModeState.notUsed).score),
      );
    });

    test('a large match residual costs the cross-check term', () {
      final score = scoreOf(bestMatchDeltaE: 3);
      expect(
        score.terms.firstWhere((t) => t.name == 'matchResidual').score,
        closeTo((4.0 - 3.0) / (4.0 - 0.8), 1e-12),
      );
    });

    test('the weakest term is reported, so the user can be told what to fix',
        () {
      // 0.2 is below the fixture's homogeneity score of 0.922, so the grey
      // card becomes the thing to fix.
      expect(scoreOf(grayCardScore: 0.2).weakestTerm.name, 'grayCard');
    });
  });

  group('hard overrides', () {
    test('no colour profile pins the band to low whatever the sum says', () {
      final score = scoreOf(profileScore: 0);
      expect(score.overrides, contains(ConfidenceOverride.noColorProfile));
      expect(score.band, ConfidenceBand.low);
      // The weighted sum alone would still have been respectable, which is
      // exactly why the override exists.
      expect(score.score, greaterThan(0.6));
    });

    test('an invalid grey card pins the band to low', () {
      final score = scoreOf(grayCardValid: false);
      expect(score.overrides, contains(ConfidenceOverride.grayCardInvalid));
      expect(score.band, ConfidenceBand.low);
    });

    test('excessive rejection pins the band to low', () {
      final score = scoreOf(
        reduction: const RoiReduction.rejected(
          reason: RoiRejectionReason.tooManyRejectedSamples,
          sampleCount: 400,
          acceptedSamples: 370,
          rejectedFraction: 0.6,
        ),
      );
      expect(score.overrides, contains(ConfidenceOverride.excessiveRejection));
      expect(score.band, ConfidenceBand.low);
    });

    test('too few samples pins the band to low', () {
      final score = scoreOf(
        reduction: const RoiReduction.rejected(
          reason: RoiRejectionReason.tooFewSamples,
          sampleCount: 50,
          acceptedSamples: 50,
          rejectedFraction: 0.1,
        ),
      );
      expect(score.overrides, contains(ConfidenceOverride.tooFewSamples));
    });

    test('no accepted frames pins the band to low', () {
      expect(
        scoreOf(acceptedFrameCount: 0).overrides,
        contains(ConfidenceOverride.noAcceptedFrames),
      );
    });

    test('several overrides are all reported', () {
      final score = scoreOf(profileScore: 0, grayCardValid: false);
      expect(score.overrides, hasLength(2));
      expect(score.wasOverridden, isTrue);
    });
  });

  group('bands', () {
    test('classify at the thresholds', () {
      const thresholds = ConfidenceBandThresholds();
      expect(thresholds.classify(0.80), ConfidenceBand.high);
      expect(thresholds.classify(0.799), ConfidenceBand.medium);
      expect(thresholds.classify(0.60), ConfidenceBand.medium);
      expect(thresholds.classify(0.599), ConfidenceBand.low);
    });
  });

  group('custom weights', () {
    test('keep the score inside zero to one', () {
      // Seven equal weights, so the score is the plain mean of the terms.
      const custom = ConfidenceScorer(
        weights: ConfidenceWeights(
          captureMode: 2,
          deviceProfile: 2,
          grayCard: 2,
          rejectedFraction: 2,
          regionHomogeneity: 2,
          relativeMode: 2,
          matchResidual: 2,
        ),
      );
      final score = custom.score(
        captureSource: CcmSource.chartFit,
        profileScore: 1,
        grayCardValid: true,
        grayCardScore: 1,
        reduction: goodReduction(),
        relativeMode: RelativeModeState.usedAndConsistent,
        bestMatchDeltaE: 0.6,
        acceptedFrameCount: 3,
      );
      expect(score.score, closeTo(0.9888888888888889, 1e-12));
      expect(score.score, lessThanOrEqualTo(1));
      expect(score.score, greaterThanOrEqualTo(0));
    });
  });
}
