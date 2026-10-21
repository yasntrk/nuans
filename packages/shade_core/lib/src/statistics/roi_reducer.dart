import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:shade_core/src/calibration/gray_card.dart';
import 'package:shade_core/src/capture/roi_sample_set.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';
import 'package:shade_core/src/statistics/robust_stats.dart';

/// Why a region could not be reduced to a usable colour.
enum RoiRejectionReason {
  /// Not enough samples survived for the median and MAD to be stable.
  tooFewSamples,

  /// Most of the region was thrown away, so what is left is no longer the
  /// tooth: wrong placement, or glare across the whole band.
  tooManyRejectedSamples,

  /// The region arrived empty.
  noSamples,
}

/// Thresholds of the robust reduction.
@immutable
final class RobustFilterConfig {
  const RobustFilterConfig({
    this.specularMadFactor = kSpecularMadFactor,
    this.shadowMadFactor = kShadowMadFactor,
    this.trimLowFraction = kTrimLowFraction,
    this.trimHighFraction = kTrimHighFraction,
    this.minAcceptedSamples = kMinAcceptedSamples,
    this.maxRejectedFraction = kMaxRejectedFraction,
  });

  final double specularMadFactor;
  final double shadowMadFactor;
  final double trimLowFraction;
  final double trimHighFraction;
  final int minAcceptedSamples;
  final double maxRejectedFraction;
}

/// One region reduced to a single colour, with the quality evidence kept.
@immutable
final class RoiReduction {
  const RoiReduction({
    required this.xyz,
    required this.lab,
    required this.sampleCount,
    required this.acceptedSamples,
    required this.specularRejected,
    required this.shadowRejected,
    required this.rejectedFraction,
    required this.medianLightness,
    required this.lightnessMad,
    required this.lightnessStdDev,
    required this.trimmedSampleCount,
    this.rejection,
  });

  /// A region that could not be reduced. Carries the counts so the user
  /// interface can explain *why* rather than just refusing.
  const RoiReduction.rejected({
    required RoiRejectionReason reason,
    required this.sampleCount,
    required this.acceptedSamples,
    required this.rejectedFraction,
  })  : xyz = XyzColor.black,
        lab = LabColor.black,
        specularRejected = 0,
        shadowRejected = 0,
        medianLightness = 0,
        lightnessMad = 0,
        lightnessStdDev = 0,
        trimmedSampleCount = 0,
        rejection = reason;

  final XyzColor xyz;
  final LabColor lab;

  /// Samples handed over by the native layer.
  final int sampleCount;

  /// Samples left after the specular and shadow filters.
  final int acceptedSamples;

  final int specularRejected;
  final int shadowRejected;

  /// Estimated share of the whole region that was discarded: natively clipped
  /// superpixels, plus the filter's rejection rate applied to the rest.
  ///
  /// The trimmed mean's 10% tails are *not* counted. Trimming is a fixed-rate
  /// estimator rather than a rejection signal; counting it would make this
  /// number never drop below 20% and carry no information.
  final double rejectedFraction;

  final double medianLightness;
  final double lightnessMad;

  /// Standard deviation of `L*` over the accepted samples. A real tooth has a
  /// genuine gradient, so this is not pure noise.
  final double lightnessStdDev;

  /// Samples that actually entered the mean after trimming.
  final int trimmedSampleCount;

  final RoiRejectionReason? rejection;

  bool get isValid => rejection == null;

  /// Whether the sample count is high enough for full confidence.
  bool get hasAmpleSamples => acceptedSamples >= kLowConfidenceSampleCount;

  @override
  String toString() => isValid
      ? 'RoiReduction($lab, accepted: $acceptedSamples/$sampleCount, '
          'rejected: $rejectedFraction)'
      : 'RoiReduction.rejected(${rejection!.name})';
}

/// Turns a region's camera-space samples into one Lab colour.
///
/// The order of operations is the whole point and is not interchangeable:
///
/// 1. transform every sample with the capture transform, so lightness is
///    colorimetric rather than a raw channel value;
/// 2. reject speculars above `median + 2.5 * MAD` and shadows below
///    `median - 3 * MAD`, on `L*`;
/// 3. take a 10 to 90 per cent trimmed mean **in XYZ**, ordered by `L*`;
/// 4. convert that mean to Lab, once.
///
/// Averaging in Lab instead would bias the result, because Lab is a
/// non-linear function of the radiometric quantity the sensor measured.
@immutable
final class RoiReducer {
  const RoiReducer({
    this.config = const RobustFilterConfig(),
    this.whitePoint = WhitePoint.d65,
  });

  final RobustFilterConfig config;
  final WhitePoint whitePoint;

  RoiReduction reduce({
    required RoiSampleSet samples,
    required CaptureTransform transform,
  }) {
    final count = samples.sampleCount;
    if (count == 0) {
      return const RoiReduction.rejected(
        reason: RoiRejectionReason.noSamples,
        sampleCount: 0,
        acceptedSamples: 0,
        rejectedFraction: 1,
      );
    }

    // Step 1: colorimetric values for every sample.
    final xs = Float64List(count);
    final ys = Float64List(count);
    final zs = Float64List(count);
    final lightness = Float64List(count);
    for (var i = 0; i < count; i++) {
      final xyz = transform.toXyz(samples.sampleAt(i));
      xs[i] = xyz.x;
      ys[i] = xyz.y;
      zs[i] = xyz.z;
      lightness[i] = 116 * XyzColor.labTransfer(xyz.y / whitePoint.xyz.y) - 16;
    }

    // Step 2: robust centre and spread of lightness.
    final lightnessList = List<double>.of(lightness);
    final median = RobustStats.median(lightnessList);
    final mad = RobustStats.medianAbsoluteDeviation(
      lightnessList,
      precomputedMedian: median,
    );
    final upperLimit = median + config.specularMadFactor * mad;
    final lowerLimit = median - config.shadowMadFactor * mad;

    // The order is total, (lightness, index), so trimming is reproducible
    // regardless of whether the sort algorithm happens to be stable.
    final order = List<int>.generate(count, (i) => i, growable: false)
      ..sort((a, b) {
        final byLightness = lightness[a].compareTo(lightness[b]);
        return byLightness != 0 ? byLightness : a.compareTo(b);
      });

    final accepted = <int>[];
    var specular = 0;
    var shadow = 0;
    for (final index in order) {
      final value = lightness[index];
      if (value > upperLimit) {
        specular++;
      } else if (value < lowerLimit) {
        shadow++;
      } else {
        accepted.add(index);
      }
    }

    final sampleRejectionRate = (count - accepted.length) / count;
    final clipped = samples.clippedFraction;
    final rejectedFraction = clipped + (1 - clipped) * sampleRejectionRate;

    if (accepted.length < config.minAcceptedSamples) {
      return RoiReduction.rejected(
        reason: RoiRejectionReason.tooFewSamples,
        sampleCount: count,
        acceptedSamples: accepted.length,
        rejectedFraction: rejectedFraction,
      );
    }
    if (rejectedFraction > config.maxRejectedFraction) {
      return RoiReduction.rejected(
        reason: RoiRejectionReason.tooManyRejectedSamples,
        sampleCount: count,
        acceptedSamples: accepted.length,
        rejectedFraction: rejectedFraction,
      );
    }

    // Step 3: trimmed mean in XYZ. `accepted` is already in ascending
    // lightness order, because it was built by walking `order`.
    final bounds = RobustStats.trimBounds(
      count: accepted.length,
      lowFraction: config.trimLowFraction,
      highFraction: config.trimHighFraction,
    );
    var sumX = 0.0;
    var sumY = 0.0;
    var sumZ = 0.0;
    for (var rank = bounds.low; rank < bounds.high; rank++) {
      final index = accepted[rank];
      sumX += xs[index];
      sumY += ys[index];
      sumZ += zs[index];
    }
    final trimmedCount = bounds.high - bounds.low;
    final meanXyz = XyzColor(
      sumX / trimmedCount,
      sumY / trimmedCount,
      sumZ / trimmedCount,
    );

    final acceptedLightness = List<double>.generate(
      accepted.length,
      (i) => lightness[accepted[i]],
      growable: false,
    );

    // Step 4: one conversion to Lab, at the end.
    return RoiReduction(
      xyz: meanXyz,
      lab: meanXyz.toLab(whitePoint: whitePoint),
      sampleCount: count,
      acceptedSamples: accepted.length,
      specularRejected: specular,
      shadowRejected: shadow,
      rejectedFraction: rejectedFraction,
      medianLightness: median,
      lightnessMad: mad,
      lightnessStdDev: RobustStats.standardDeviation(acceptedLightness),
      trimmedSampleCount: trimmedCount,
    );
  }
}
