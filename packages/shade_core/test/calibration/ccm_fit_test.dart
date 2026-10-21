import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// Builds a matrix that maps a neutral exactly onto [whitePoint], by spreading
/// each row's shortfall evenly across its three entries.
///
/// Used to synthesise a plausible device: the fitter is constrained to produce
/// such a matrix, so the ground truth it is asked to recover must be one.
Mat3 whitePointPreserving(Mat3 seed, WhitePoint whitePoint) {
  final rows = seed.toRowMajor();
  final target = whitePoint.xyz;
  final fixed = <double>[];
  for (var r = 0; r < 3; r++) {
    final sum = rows[r * 3] + rows[r * 3 + 1] + rows[r * 3 + 2];
    final correction = (target[r] - sum) / 3;
    for (var c = 0; c < 3; c++) {
      fixed.add(rows[r * 3 + c] + correction);
    }
  }
  return Mat3.fromRowMajor(fixed);
}

void main() {
  // A synthetic device. Not a real camera matrix and not real chart data: the
  // point of the test is that the fitter recovers whatever truth it is given.
  final trueMatrix = whitePointPreserving(
    const Mat3(0.72, 0.21, 0.02, 0.28, 0.80, -0.08, 0.01, -0.12, 1.20),
    WhitePoint.d65,
  );
  const trueGains = Vec3(1.45, 1, 1.15);
  const trueExposure = 0.4;

  /// Inverts the forward model to produce what the sensor would have recorded:
  /// `XYZ = exposure * M * diag(gains) * raw`.
  ChartPatch synthesise(
    String id,
    XyzColor reference, {
    required bool isNeutral,
  }) {
    final camera = trueMatrix.inverse.apply(reference.asVec3);
    final raw = Vec3(
          camera.x / trueGains.x,
          camera.y / trueGains.y,
          camera.z / trueGains.z,
        ) *
        (1 / trueExposure);
    return ChartPatch(
      id: id,
      measured: CameraRgb.fromVec3(raw),
      reference: reference,
      isNeutral: isNeutral,
    );
  }

  XyzColor neutralOfLuminance(double y) => XyzColor(
        WhitePoint.d65.xyz.x * y,
        y,
        WhitePoint.d65.xyz.z * y,
      );

  XyzColor fromEncodedSrgb(double r, double g, double b) => XyzColor.fromVec3(
        Srgb.linearToXyzD65.apply(
          Vec3(Srgb.decode(r), Srgb.decode(g), Srgb.decode(b)),
        ),
      );

  List<ChartPatch> buildChart() => [
        // A synthetic neutral row of six steps.
        for (final (i, y) in [0.90, 0.59, 0.36, 0.19, 0.09, 0.03].indexed)
          synthesise('neutral.$i', neutralOfLuminance(y), isNeutral: true),
        // Eighteen chromatic patches, synthesised from in-gamut sRGB values.
        for (final (i, rgb) in <List<double>>[
          [0.45, 0.32, 0.26],
          [0.76, 0.58, 0.51],
          [0.36, 0.48, 0.61],
          [0.35, 0.42, 0.26],
          [0.51, 0.50, 0.69],
          [0.39, 0.74, 0.67],
          [0.89, 0.48, 0.17],
          [0.30, 0.36, 0.64],
          [0.84, 0.41, 0.44],
          [0.35, 0.24, 0.46],
          [0.67, 0.75, 0.25],
          [0.94, 0.64, 0.18],
          [0.21, 0.26, 0.58],
          [0.29, 0.58, 0.31],
          [0.70, 0.24, 0.26],
          [0.94, 0.78, 0.14],
          [0.73, 0.33, 0.57],
          [0.18, 0.50, 0.59],
        ].indexed)
          synthesise(
            'chromatic.$i',
            fromEncodedSrgb(rgb[0], rgb[1], rgb[2]),
            isNeutral: false,
          ),
      ];

  group('neutral gains', () {
    test('recovers the gains from the neutral row', () {
      final gains = CcmFitter.neutralGainsOf(
        buildChart().where((p) => p.isNeutral).toList(),
      );
      expect(gains.x, closeTo(trueGains.x, 1e-12));
      expect(gains.y, 1);
      expect(gains.z, closeTo(trueGains.z, 1e-12));
    });

    test('the green gain is exactly one by construction', () {
      final gains = CcmFitter.neutralGainsOf(
        buildChart().where((p) => p.isNeutral).toList(),
      );
      expect(gains.y, 1);
    });
  });

  group('constrained fit', () {
    test('recovers the synthetic device matrix', () {
      final result = CcmFitter.fit(patches: buildChart());
      final fitted = result.ccm.matrix.toRowMajor();
      final truth = trueMatrix.toRowMajor();
      for (var i = 0; i < 9; i++) {
        expect(fitted[i], closeTo(truth[i], 1e-9));
      }
    });

    test('recovers the exposure normalisation', () {
      final result = CcmFitter.fit(patches: buildChart());
      expect(result.exposureNormalisation, closeTo(trueExposure, 1e-12));
    });

    test('the fitted matrix maps a neutral exactly onto the white point', () {
      final result = CcmFitter.fit(patches: buildChart());
      final sums = result.ccm.matrix.rowSums;
      expect(sums.x, closeTo(WhitePoint.d65.xyz.x, 1e-12));
      expect(sums.y, closeTo(1, 1e-12));
      expect(sums.z, closeTo(WhitePoint.d65.xyz.z, 1e-12));
      expect(result.ccm.preservesWhitePoint, isTrue);
    });

    test('noiseless data fits with essentially zero residual', () {
      final result = CcmFitter.fit(patches: buildChart());
      expect(result.quality.meanDeltaE2000, lessThan(1e-6));
      expect(result.quality.maxDeltaE2000, lessThan(1e-6));
      expect(result.quality.passes, isTrue);
      expect(result.quality.score, 1);
      expect(result.quality.residuals, hasLength(24));
    });

    test('the constraint still holds when the data is noisy', () {
      // Perturb every measurement; the fit degrades but the invariant cannot.
      final noisy = <ChartPatch>[];
      var seed = 1;
      for (final patch in buildChart()) {
        // A tiny deterministic pseudo-random wobble, so the test cannot flake.
        double wobble() {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          return (seed / 0x7fffffff - 0.5) * 0.01;
        }

        noisy.add(
          ChartPatch(
            id: patch.id,
            measured: CameraRgb(
              patch.measured.red * (1 + wobble()),
              patch.measured.green * (1 + wobble()),
              patch.measured.blue * (1 + wobble()),
            ),
            reference: patch.reference,
            isNeutral: patch.isNeutral,
          ),
        );
      }
      final result = CcmFitter.fit(patches: noisy);
      expect(result.ccm.preservesWhitePoint, isTrue);
      expect(result.quality.meanDeltaE2000, greaterThan(0));
    });

    test('the quality score falls to zero at the gate', () {
      const report = CcmQualityReport(
        meanDeltaE2000: 2,
        maxDeltaE2000: 3,
        residuals: [],
        gate: kCcmMeanDeltaEGate,
      );
      expect(report.score, 0);
      expect(report.passes, isTrue);
      const worse = CcmQualityReport(
        meanDeltaE2000: 2.5,
        maxDeltaE2000: 4,
        residuals: [],
        gate: kCcmMeanDeltaEGate,
      );
      expect(worse.passes, isFalse);
      expect(worse.score, 0);
      const middling = CcmQualityReport(
        meanDeltaE2000: 1.25,
        maxDeltaE2000: 2,
        residuals: [],
        gate: kCcmMeanDeltaEGate,
      );
      expect(middling.score, closeTo(0.5, 1e-12));
    });
  });

  group('input validation', () {
    test('refuses too few patches', () {
      expect(
        () => CcmFitter.fit(patches: buildChart().take(6).toList()),
        throwsArgumentError,
      );
    });

    test('refuses a chart with too few neutrals', () {
      final chart = buildChart()
          .map(
            (p) => ChartPatch(
              id: p.id,
              measured: p.measured,
              reference: p.reference,
              isNeutral: p.id == 'neutral.0',
            ),
          )
          .toList();
      expect(() => CcmFitter.fit(patches: chart), throwsArgumentError);
    });
  });
}
