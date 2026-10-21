import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shade_core/src/capture/camera_rgb.dart';
import 'package:shade_core/src/colorimetry/vec3.dart';

/// The reduced content of one region of interest, as the native layer hands it
/// over: a decimated set of linear camera-space superpixels plus exact
/// statistics over the whole non-clipped population.
///
/// Effectively immutable: the interleaved buffer is copied on construction and
/// never exposed, so a caller that reuses its own buffer cannot mutate a set
/// that has already been handed over.
@immutable
final class RoiSampleSet {
  /// Copies [interleaved], which must hold `3 * n` values ordered R, G, B.
  factory RoiSampleSet({
    required List<double> interleaved,
    required int totalSuperpixels,
    required int clippedSuperpixels,
    required int decimationStride,
    required CameraRgb channelMean,
    required CameraRgb channelStdDev,
  }) {
    if (interleaved.length % 3 != 0) {
      throw ArgumentError.value(
        interleaved.length,
        'interleaved.length',
        'must be a multiple of three',
      );
    }
    if (decimationStride < 1) {
      throw ArgumentError.value(
        decimationStride,
        'decimationStride',
        'must be at least one',
      );
    }
    if (clippedSuperpixels < 0 || clippedSuperpixels > totalSuperpixels) {
      throw ArgumentError.value(
        clippedSuperpixels,
        'clippedSuperpixels',
        'must be within 0 .. totalSuperpixels',
      );
    }
    final count = interleaved.length ~/ 3;
    if (count > totalSuperpixels) {
      throw ArgumentError.value(
        count,
        'sampleCount',
        'cannot exceed totalSuperpixels',
      );
    }
    return RoiSampleSet._(
      Float64List.fromList(interleaved),
      totalSuperpixels,
      clippedSuperpixels,
      decimationStride,
      channelMean,
      channelStdDev,
    );
  }

  const RoiSampleSet._(
    this._samples,
    this.totalSuperpixels,
    this.clippedSuperpixels,
    this.decimationStride,
    this.channelMean,
    this.channelStdDev,
  );

  final Float64List _samples;

  /// Superpixels inside the region before any rejection.
  final int totalSuperpixels;

  /// Superpixels dropped natively because a channel exceeded the clipping
  /// threshold in at least one accepted frame.
  final int clippedSuperpixels;

  /// Lattice stride used to reach the sample budget; 1 means no decimation.
  final int decimationStride;

  /// Exact mean over all non-clipped superpixels, not over the returned sample.
  final CameraRgb channelMean;

  /// Exact population standard deviation over all non-clipped superpixels.
  final CameraRgb channelStdDev;

  int get sampleCount => _samples.length ~/ 3;

  bool get isEmpty => sampleCount == 0;

  bool get isDecimated => decimationStride > 1;

  double get clippedFraction =>
      totalSuperpixels == 0 ? 0 : clippedSuperpixels / totalSuperpixels;

  CameraRgb sampleAt(int index) {
    final base = index * 3;
    return CameraRgb(_samples[base], _samples[base + 1], _samples[base + 2]);
  }

  /// Whether the decimated sample looks like an unbiased draw from the whole
  /// population, by checking the sample mean against the exact mean within
  /// three standard errors.
  ///
  /// A failure here does not mean the measurement is wrong; it means the
  /// region is not spatially homogeneous enough for the lattice to represent
  /// it, which the confidence score should know about.
  bool get isSampleUnbiased {
    if (sampleCount == 0) return false;
    if (!isDecimated) return true;
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final s = sampleAt(i);
      sumR += s.red;
      sumG += s.green;
      sumB += s.blue;
    }
    final n = sampleCount;
    final mean = Vec3(sumR / n, sumG / n, sumB / n);
    final tolerance = channelStdDev.asVec3 * (3 / math.sqrt(n));
    final exact = channelMean.asVec3;
    for (var c = 0; c < 3; c++) {
      // A zero standard deviation means a perfectly flat region, where any
      // deviation at all would be a native bug rather than sampling noise.
      final limit = tolerance[c] == 0 ? 1e-12 : tolerance[c];
      if ((mean[c] - exact[c]).abs() > limit) return false;
    }
    return true;
  }
}
