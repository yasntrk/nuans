import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/constants.dart';

/// Which of the three CIEDE2000 terms a deviation is carried by.
enum DeltaE2000Component {
  /// `L'`, how much lighter or darker the sample is.
  lightness,

  /// `C'`, how much more or less saturated the sample is.
  chroma,

  /// `H'`, which way round the hue circle the sample sits.
  hue,
}

/// Parametric weighting factors `kL`, `kC`, `kH`.
///
/// Unity for this application. They exist because CIEDE2000 was defined for
/// textile and paint viewing conditions that sometimes call for a different
/// lightness weighting; dentistry's published thresholds assume unity, so
/// changing them would invalidate the acceptability bands.
@immutable
final class ParametricWeights {
  const ParametricWeights({
    this.lightness = 1,
    this.chroma = 1,
    this.hue = 1,
  });

  static const ParametricWeights unity = ParametricWeights();

  final double lightness;
  final double chroma;
  final double hue;

  @override
  bool operator ==(Object other) =>
      other is ParametricWeights &&
      other.lightness == lightness &&
      other.chroma == chroma &&
      other.hue == hue;

  @override
  int get hashCode => Object.hash(lightness, chroma, hue);

  @override
  String toString() =>
      'ParametricWeights(kL: $lightness, kC: $chroma, kH: $hue)';
}

/// A full CIEDE2000 evaluation, not just the scalar.
///
/// The decomposition is what makes a result explainable: a difference of 1.4
/// carried entirely by lightness is a different clinical problem from the same
/// 1.4 carried by hue, and the user interface says which.
@immutable
final class DeltaE2000Result {
  const DeltaE2000Result({
    required this.deltaE,
    required this.weightedLightness,
    required this.weightedChroma,
    required this.weightedHue,
    required this.deltaLPrime,
    required this.deltaCPrime,
    required this.deltaHPrime,
    required this.meanHuePrimeDegrees,
    required this.sLightness,
    required this.sChroma,
    required this.sHue,
    required this.rotationTerm,
  });

  /// The colour difference itself.
  final double deltaE;

  /// `dL' / (kL * SL)`. Positive means the sample is lighter than the
  /// reference. Already in CIEDE2000 units, so it is directly comparable to
  /// the 0.8 perceptibility threshold.
  final double weightedLightness;

  /// `dC' / (kC * SC)`. Positive means the sample is more chromatic.
  final double weightedChroma;

  /// `dH' / (kH * SH)`. Its sign is a direction around the hue circle, which
  /// only means something together with [meanHuePrimeDegrees].
  final double weightedHue;

  final double deltaLPrime;
  final double deltaCPrime;
  final double deltaHPrime;

  /// `h̄'`, the mean hue angle of the pair, in degrees.
  final double meanHuePrimeDegrees;

  final double sLightness;
  final double sChroma;
  final double sHue;

  /// `RT`, the hue-chroma interaction term. Only materially non-zero in the
  /// blue region, which is why it rarely matters for teeth.
  final double rotationTerm;

  /// The term carrying most of the difference.
  DeltaE2000Component get dominantComponent {
    final l = weightedLightness.abs();
    final c = weightedChroma.abs();
    final h = weightedHue.abs();
    if (l >= c && l >= h) return DeltaE2000Component.lightness;
    if (c >= h) return DeltaE2000Component.chroma;
    return DeltaE2000Component.hue;
  }

  /// The weighted value of [component].
  double weightedValueOf(DeltaE2000Component component) => switch (component) {
        DeltaE2000Component.lightness => weightedLightness,
        DeltaE2000Component.chroma => weightedChroma,
        DeltaE2000Component.hue => weightedHue,
      };

  @override
  String toString() => 'DeltaE2000Result(dE00: $deltaE, '
      'l: $weightedLightness, c: $weightedChroma, h: $weightedHue)';
}

/// The CIEDE2000 colour difference formula (CIE 2001, ISO 11664-6).
///
/// Implemented from the formulation of Sharma, Wu and Dalal (2005), which
/// spells out the three discontinuities a naive transcription gets wrong:
///
/// 1. averaging hue across the 0/360 degree boundary;
/// 2. the `C1' * C2' == 0` cases, where hue difference is defined as zero and
///    the mean hue is the plain sum;
/// 3. the seventh powers, where `25^7` is precomputed instead of recomputed.
///
/// Verified against that paper's published test data to 1e-4.
abstract final class DeltaE2000 {
  /// Computes the difference between a [reference] and a [sample].
  ///
  /// The order matters for the component signs, not for
  /// [DeltaE2000Result.deltaE], which is symmetric. In this application the
  /// reference is the candidate shade and the sample is the measured tooth, so
  /// a positive [DeltaE2000Result.weightedLightness] reads as "the tooth is
  /// lighter than this shade".
  static DeltaE2000Result between({
    required LabColor reference,
    required LabColor sample,
    ParametricWeights weights = ParametricWeights.unity,
  }) {
    final l1 = reference.lightness;
    final a1 = reference.a;
    final b1 = reference.b;
    final l2 = sample.lightness;
    final a2 = sample.a;
    final b2 = sample.b;

    // Chroma rolloff near the neutral axis.
    final c1 = math.sqrt(a1 * a1 + b1 * b1);
    final c2 = math.sqrt(a2 * a2 + b2 * b2);
    final meanC = (c1 + c2) / 2;
    final meanC7 = _pow7(meanC);
    final g = 0.5 * (1 - math.sqrt(meanC7 / (meanC7 + kCiede2000Pow25To7)));

    final a1p = (1 + g) * a1;
    final a2p = (1 + g) * a2;
    final c1p = math.sqrt(a1p * a1p + b1 * b1);
    final c2p = math.sqrt(a2p * a2p + b2 * b2);

    final h1p = _hueDegrees(a1p, b1);
    final h2p = _hueDegrees(a2p, b2);

    final deltaLPrime = l2 - l1;
    final deltaCPrime = c2p - c1p;

    final chromaProduct = c1p * c2p;
    final double deltaSmallHue;
    if (chromaProduct == 0) {
      deltaSmallHue = 0;
    } else {
      final raw = h2p - h1p;
      if (raw.abs() <= 180) {
        deltaSmallHue = raw;
      } else if (raw > 180) {
        deltaSmallHue = raw - 360;
      } else {
        deltaSmallHue = raw + 360;
      }
    }
    final deltaHPrime =
        2 * math.sqrt(chromaProduct) * math.sin(_radians(deltaSmallHue) / 2);

    final meanLPrime = (l1 + l2) / 2;
    final meanCPrime = (c1p + c2p) / 2;

    final double meanHPrime;
    if (chromaProduct == 0) {
      meanHPrime = h1p + h2p;
    } else if ((h1p - h2p).abs() <= 180) {
      meanHPrime = (h1p + h2p) / 2;
    } else if (h1p + h2p < 360) {
      meanHPrime = (h1p + h2p + 360) / 2;
    } else {
      meanHPrime = (h1p + h2p - 360) / 2;
    }

    final t = 1 -
        0.17 * math.cos(_radians(meanHPrime - 30)) +
        0.24 * math.cos(_radians(2 * meanHPrime)) +
        0.32 * math.cos(_radians(3 * meanHPrime + 6)) -
        0.20 * math.cos(_radians(4 * meanHPrime - 63));

    final deltaTheta =
        30 * math.exp(-math.pow((meanHPrime - 275) / 25, 2).toDouble());
    final meanCPrime7 = _pow7(meanCPrime);
    final rc = 2 * math.sqrt(meanCPrime7 / (meanCPrime7 + kCiede2000Pow25To7));

    final lightnessOffset = meanLPrime - 50;
    final sl = 1 +
        0.015 *
            lightnessOffset *
            lightnessOffset /
            math.sqrt(20 + lightnessOffset * lightnessOffset);
    final sc = 1 + 0.045 * meanCPrime;
    final sh = 1 + 0.015 * meanCPrime * t;
    final rt = -math.sin(_radians(2 * deltaTheta)) * rc;

    final weightedL = deltaLPrime / (weights.lightness * sl);
    final weightedC = deltaCPrime / (weights.chroma * sc);
    final weightedH = deltaHPrime / (weights.hue * sh);

    return DeltaE2000Result(
      deltaE: math.sqrt(
        weightedL * weightedL +
            weightedC * weightedC +
            weightedH * weightedH +
            rt * weightedC * weightedH,
      ),
      weightedLightness: weightedL,
      weightedChroma: weightedC,
      weightedHue: weightedH,
      deltaLPrime: deltaLPrime,
      deltaCPrime: deltaCPrime,
      deltaHPrime: deltaHPrime,
      meanHuePrimeDegrees: meanHPrime,
      sLightness: sl,
      sChroma: sc,
      sHue: sh,
      rotationTerm: rt,
    );
  }

  /// The scalar difference, when the decomposition is not needed.
  static double scalar(LabColor first, LabColor second) =>
      between(reference: first, sample: second).deltaE;

  /// `h'` in degrees, in `[0, 360)`, with the neutral case pinned to zero.
  static double _hueDegrees(double aPrime, double b) {
    if (aPrime == 0 && b == 0) return 0;
    return (math.atan2(b, aPrime) * 180 / math.pi) % 360;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// `x^7` by repeated multiplication.
  ///
  /// Three multiplications instead of a `pow` call, and exact for the integer
  /// exponent rather than going through `exp(7 * log(x))`.
  static double _pow7(double x) {
    final x2 = x * x;
    final x3 = x2 * x;
    return x3 * x3 * x;
  }
}
