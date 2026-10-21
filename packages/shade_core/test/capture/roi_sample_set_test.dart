import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

void main() {
  RoiSampleSet build({
    required List<double> interleaved,
    int? total,
    int clipped = 0,
    int stride = 1,
    CameraRgb mean = const CameraRgb(0.5, 0.5, 0.5),
    CameraRgb stdDev = const CameraRgb(0.01, 0.01, 0.01),
  }) =>
      RoiSampleSet(
        interleaved: interleaved,
        totalSuperpixels: total ?? interleaved.length ~/ 3,
        clippedSuperpixels: clipped,
        decimationStride: stride,
        channelMean: mean,
        channelStdDev: stdDev,
      );

  group('construction', () {
    test('exposes samples as triples', () {
      final set = build(interleaved: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
      expect(set.sampleCount, 2);
      expect(set.sampleAt(0), const CameraRgb(0.1, 0.2, 0.3));
      expect(set.sampleAt(1), const CameraRgb(0.4, 0.5, 0.6));
    });

    test('rejects a buffer that is not a multiple of three', () {
      expect(
        () => build(interleaved: [0.1, 0.2]),
        throwsArgumentError,
      );
    });

    test('rejects a stride below one', () {
      expect(
        () => build(interleaved: [0.1, 0.2, 0.3], stride: 0),
        throwsArgumentError,
      );
    });

    test('rejects a clipped count outside the population', () {
      expect(
        () => build(interleaved: [0.1, 0.2, 0.3], total: 10, clipped: 11),
        throwsArgumentError,
      );
      expect(
        () => build(interleaved: [0.1, 0.2, 0.3], total: 10, clipped: -1),
        throwsArgumentError,
      );
    });

    test('rejects more samples than the population', () {
      expect(
        () => build(interleaved: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6], total: 1),
        throwsArgumentError,
      );
    });

    test('copies the buffer, so later mutation cannot reach it', () {
      final buffer = [0.1, 0.2, 0.3];
      final set = build(interleaved: buffer);
      buffer[0] = 0.9;
      expect(set.sampleAt(0).red, 0.1);
    });
  });

  group('derived figures', () {
    test('clipped fraction', () {
      final set = build(
        interleaved: [0.1, 0.2, 0.3],
        total: 400,
        clipped: 40,
      );
      expect(set.clippedFraction, closeTo(0.1, 1e-15));
    });

    test('an empty region reports a zero clipped fraction, not a division', () {
      final set = build(interleaved: [], total: 0);
      expect(set.isEmpty, isTrue);
      expect(set.clippedFraction, 0);
    });

    test('knows whether it was decimated', () {
      expect(build(interleaved: [0.1, 0.2, 0.3]).isDecimated, isFalse);
      expect(
        build(interleaved: [0.1, 0.2, 0.3], total: 12, stride: 2).isDecimated,
        isTrue,
      );
    });
  });

  group('sampling bias check', () {
    test('an undecimated set is unbiased by definition', () {
      expect(build(interleaved: [0.4, 0.5, 0.6]).isSampleUnbiased, isTrue);
    });

    test('a representative decimated sample passes', () {
      // 100 samples straddling the stated mean.
      final interleaved = <double>[];
      for (var i = 0; i < 100; i++) {
        final v = 0.5 + (i.isEven ? 0.01 : -0.01);
        interleaved.addAll([v, v, v]);
      }
      final set = build(
        interleaved: interleaved,
        total: 400,
        stride: 2,
      );
      expect(set.isSampleUnbiased, isTrue);
    });

    test('a sample far from the exact mean is flagged', () {
      final interleaved = <double>[];
      for (var i = 0; i < 100; i++) {
        interleaved.addAll([0.7, 0.7, 0.7]);
      }
      final set = build(
        interleaved: interleaved,
        total: 400,
        stride: 2,
      );
      expect(set.isSampleUnbiased, isFalse);
    });

    test('an empty set is not unbiased, it is unusable', () {
      expect(build(interleaved: [], total: 0).isSampleUnbiased, isFalse);
    });
  });
}
