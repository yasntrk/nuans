import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Expected values computed by `tools/spec_oracle/fixtures.py`.
///
/// The fixture is 400 lattice samples on a smooth cervical-to-incisal ramp,
/// with 20 specular spikes (every 20th sample, 1.8x) and 10 shadow samples
/// (every 37th that is not already a spike, 0.45x).
void main() {
  /// A transform whose matrix is exactly `diag(D65)`: a synthetic device whose
  /// channels are already aligned with XYZ, so the arithmetic under test is the
  /// reduction rather than the colour conversion.
  final transform = CaptureTransform.from(
    ccm: ColorCorrectionMatrix(
      matrix: Mat3.diagonal(WhitePoint.d65.xyz),
      whitePoint: WhitePoint.d65,
      source: CcmSource.chartFit,
    ),
    grayCard: GrayCardCorrection.fromMeasurement(
      cardMedian: const CameraRgb.neutral(0.18),
    ),
  );

  List<double> fixture({bool withOutliers = true}) {
    final interleaved = <double>[];
    for (var i = 0; i < 400; i++) {
      final y = 0.42 + 0.00025 * i;
      var triple = <double>[y * 1.06, y, y * 0.74];
      if (withOutliers && i % 20 == 0) {
        triple = triple.map((c) => c * 1.8).toList();
      } else if (withOutliers && i % 37 == 0) {
        triple = triple.map((c) => c * 0.45).toList();
      }
      interleaved.addAll(triple);
    }
    return interleaved;
  }

  RoiSampleSet sampleSet({
    bool withOutliers = true,
    int clipped = 0,
    int? total,
  }) =>
      RoiSampleSet(
        interleaved: fixture(withOutliers: withOutliers),
        totalSuperpixels: total ?? 400,
        clippedSuperpixels: clipped,
        decimationStride: 1,
        channelMean: const CameraRgb(0.5181, 0.4888, 0.3617),
        channelStdDev: const CameraRgb(0.1, 0.1, 0.1),
      );

  const reducer = RoiReducer();

  group('the transform under test', () {
    test('is exactly diag(D65) with unit exposure', () {
      expect(transform.matrix.toRowMajor(), [
        WhitePoint.d65.xyz.x, 0, 0, //
        0, 1, 0, //
        0, 0, WhitePoint.d65.xyz.z, //
      ]);
    });
  });

  group('robust reduction', () {
    test('finds the robust centre and spread of lightness', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(result.medianLightness, closeTo(74.2776338111, 1e-9));
      expect(result.lightnessMad, closeTo(1.7314951090, 1e-9));
    });

    test('rejects exactly the injected outliers and nothing else', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(result.specularRejected, 20);
      expect(result.shadowRejected, 10);
      expect(result.acceptedSamples, 370);
      // The ramp itself is smooth, so no clean sample is thrown away.
      expect(result.sampleCount - result.acceptedSamples, 30);
    });

    test('trims 10 to 90 per cent of the survivors', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(result.trimmedSampleCount, 296);
    });

    test('produces the computed colour', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(result.isValid, isTrue);
      expect(result.xyz.x, closeTo(0.473500328029, 1e-12));
      expect(result.xyz.y, closeTo(0.469976351351, 1e-12));
      expect(result.xyz.z, closeTo(0.378676019475, 1e-12));
      expect(result.lab.lightness, closeTo(74.188256432766, 1e-9));
      expect(result.lab.a, closeTo(7.624337318901, 1e-9));
      expect(result.lab.b, closeTo(14.849314544436, 1e-9));
    });

    test('reports the spread of the accepted samples', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(result.lightnessStdDev, closeTo(1.852748142938, 1e-9));
    });

    test('a specular spike cannot pull the result up', () {
      final dirty = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      final clean = reducer.reduce(
        samples: sampleSet(withOutliers: false),
        transform: transform,
      );
      // The filtered result lands within 0.0065 L* of the undisturbed ramp,
      // even though 5% of the samples were 80% too bright and 2.5% were 55%
      // too dark. That is two orders below the 0.8 perceptibility threshold.
      expect(clean.lab.lightness, closeTo(74.181772873, 1e-8));
      expect(
        (dirty.lab.lightness - clean.lab.lightness).abs(),
        lessThan(0.01),
      );
    });

    test('averaging without the filter would be visibly wrong', () {
      // What a plain mean of the same data would produce, for contrast.
      final samples = sampleSet();
      var sumY = 0.0;
      for (var i = 0; i < samples.sampleCount; i++) {
        sumY += transform.toXyz(samples.sampleAt(i)).y;
      }
      final naiveLightness =
          XyzColor(0, sumY / samples.sampleCount, 0).toLab().lightness;
      final filtered =
          reducer.reduce(samples: samples, transform: transform).lab.lightness;
      expect(naiveLightness, closeTo(74.957219084, 1e-8));
      expect((naiveLightness - filtered).abs(), closeTo(0.768962651, 1e-8));
      // Comfortably past the 0.8 / 1.8 decision boundaries once it combines
      // with any other error, which is the point of filtering at all.
      expect((naiveLightness - filtered).abs(), greaterThan(0.7));
    });
  });

  group('rejected fraction', () {
    test('counts clipping and the filter, but not the trim', () {
      final result = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      // 30 of 400 filtered, no clipping: 7.5%. Not 27.5%, which is what
      // counting the trimmed tails would give.
      expect(result.rejectedFraction, closeTo(0.075, 1e-12));
    });

    test('combines clipping with the filter rate', () {
      final result = reducer.reduce(
        samples: sampleSet(clipped: 100, total: 500),
        transform: transform,
      );
      // 100 of 500 clipped, then 30 of the 400 survivors filtered.
      expect(result.rejectedFraction, closeTo(0.2 + 0.8 * 0.075, 1e-12));
    });
  });

  group('rejection', () {
    test('an empty region is rejected', () {
      final result = reducer.reduce(
        samples: RoiSampleSet(
          interleaved: const [],
          totalSuperpixels: 0,
          clippedSuperpixels: 0,
          decimationStride: 1,
          channelMean: const CameraRgb(0, 0, 0),
          channelStdDev: const CameraRgb(0, 0, 0),
        ),
        transform: transform,
      );
      expect(result.isValid, isFalse);
      expect(result.rejection, RoiRejectionReason.noSamples);
    });

    test('too few surviving samples is rejected', () {
      final result = reducer.reduce(
        samples: RoiSampleSet(
          interleaved: List<double>.generate(60 * 3, (i) => 0.5),
          totalSuperpixels: 60,
          clippedSuperpixels: 0,
          decimationStride: 1,
          channelMean: const CameraRgb(0.5, 0.5, 0.5),
          channelStdDev: const CameraRgb(0, 0, 0),
        ),
        transform: transform,
      );
      expect(result.rejection, RoiRejectionReason.tooFewSamples);
      expect(result.acceptedSamples, 60);
    });

    test('just under the gate still produces a measurement', () {
      final result = reducer.reduce(
        samples: sampleSet(clipped: 300, total: 700),
        transform: transform,
      );
      // 300 of 700 clipped, plus 7.5% of the rest, is 47.1%: under the gate.
      expect(result.rejectedFraction, closeTo(0.471428571429, 1e-10));
      expect(result.isValid, isTrue);
    });

    test('too much of the region rejected is rejected', () {
      final result = reducer.reduce(
        samples: sampleSet(clipped: 400, total: 700),
        transform: transform,
      );
      // 400 of 700 clipped, plus 7.5% of the rest, is 60.4%.
      expect(result.rejectedFraction, closeTo(0.603571428571, 1e-10));
      expect(result.rejection, RoiRejectionReason.tooManyRejectedSamples);
      expect(result.rejectedFraction, greaterThan(kMaxRejectedFraction));
    });

    test('a rejected region still carries its counts', () {
      final result = reducer.reduce(
        samples: sampleSet(clipped: 400, total: 700),
        transform: transform,
      );
      expect(result.sampleCount, 400);
      expect(result.acceptedSamples, 370);
      expect(result.lab, LabColor.black);
    });
  });

  group('sample sufficiency', () {
    test('370 accepted samples is ample', () {
      expect(
        reducer
            .reduce(samples: sampleSet(), transform: transform)
            .hasAmpleSamples,
        isTrue,
      );
    });

    test('just over the hard floor is not ample', () {
      final interleaved = <double>[];
      for (var i = 0; i < 100; i++) {
        final y = 0.45 + 0.0001 * i;
        interleaved.addAll([y * 1.06, y, y * 0.74]);
      }
      final result = reducer.reduce(
        samples: RoiSampleSet(
          interleaved: interleaved,
          totalSuperpixels: 100,
          clippedSuperpixels: 0,
          decimationStride: 1,
          channelMean: const CameraRgb(0.5, 0.47, 0.35),
          channelStdDev: const CameraRgb(0.01, 0.01, 0.01),
        ),
        transform: transform,
      );
      expect(result.isValid, isTrue);
      expect(result.hasAmpleSamples, isFalse);
    });
  });

  group('determinism', () {
    test('the same input reduces to the same output', () {
      final first = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      final second = reducer.reduce(
        samples: sampleSet(),
        transform: transform,
      );
      expect(second.lab, first.lab);
      expect(second.xyz, first.xyz);
      expect(second.trimmedSampleCount, first.trimmedSampleCount);
    });
  });
}
