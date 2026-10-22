import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/data/platform/shade_camera_api.g.dart';
import 'package:nuans/features/capture/application/live_preview_controller.dart';
import 'package:nuans/features/capture/presentation/live_camera_screen.dart';
import 'package:nuans/l10n/app_localizations.dart';

/// A host that answers without a camera.
///
/// Subclassing the generated API rather than hiding it behind an interface of
/// our own: the generated class is the contract, and a parallel interface would
/// be a second place for it to drift.
class _FakeHost extends ShadeCameraHostApi {
  _FakeHost({this.failWith});

  final CameraErrorCode? failWith;

  int initializeCalls = 0;
  int stopCalls = 0;
  double? focusedX;

  /// Every configuration the screen sent, in order. The first goes in before
  /// the frame's shape is known; the last is the one the platform measures by.
  final List<PreviewConfig> configs = [];

  @override
  Future<CameraCapabilities> initialize() async {
    initializeCalls++;
    final code = failWith;
    if (code != null) {
      throw PlatformException(code: code.name);
    }
    return CameraCapabilities(
      tier: CaptureTier.full,
      supportsManualSensor: true,
      supportsBayerRaw: true,
      supportsWhiteBalanceLock: true,
      supportsFocusLock: true,
      minIso: 50,
      maxIso: 3200,
      minExposureSeconds: 1 / 8000,
      maxExposureSeconds: 1 / 10,
      defaultFormat: CaptureFormat.bayerRaw,
      deviceModel: 'test device',
      lensId: '0',
      sensorWidthPixels: 4000,
      sensorHeightPixels: 3000,
      limitationCodes: const [],
    );
  }

  @override
  Future<PreviewSession> startPreview(PreviewConfig config) async {
    configs.add(config);
    // Landscape and a quarter turn: what nearly every phone reports.
    return PreviewSession(
      textureId: 7,
      previewWidth: 1920,
      previewHeight: 1080,
      displayRotationDegrees: 90,
    );
  }

  @override
  Future<void> updatePreviewRois(PreviewConfig config) async =>
      configs.add(config);

  @override
  Future<void> stopPreview() async => stopCalls++;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> focusAndLockAt(double x, double y) async => focusedX = x;
}

PreviewMetrics _metrics() => PreviewMetrics(
      timestampMillis: 1,
      format: CaptureFormat.bayerRaw,
      signalEncoding: SignalEncoding.displayReferredSrgb,
      toothSharpness: 123.4,
      motionScore: 0.012,
      toothClippedFraction: 0.004,
      toothShadowFraction: 0,
      toothRgbMean: Float64List.fromList([0.4, 0.42, 0.39]),
      grayCardClippedFraction: 0,
      grayCardTextureRatio: 0.015,
      grayCardQuadrantRgb: Float64List.fromList(List<double>.filled(12, 0.4)),
      iso: 100,
      exposureSeconds: 1 / 125,
      focusLocked: true,
      exposureLocked: true,
      whiteBalanceLocked: true,
    );

void main() {
  Future<LivePreviewController> pump(
    WidgetTester tester,
    _FakeHost host,
  ) async {
    final controller = LivePreviewController(host: host, bindCallbacks: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LiveCameraScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Takes the screen down inside the test body.
  ///
  /// The binding fails a test that ends with a timer still pending, and it
  /// checks that before any tearDown runs - so the starvation timer has to be
  /// cancelled here, which unmounting the screen does.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('a running preview shows the texture it was given',
      (tester) async {
    await pump(tester, _FakeHost());

    final texture = tester.widget<Texture>(find.byType(Texture));
    expect(texture.textureId, 7);

    // The frame is landscape and turned a quarter: on screen it must be tall.
    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 1);
    final box = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(box.aspectRatio, closeTo(1080 / 1920, 1e-12));
    await close(tester);
  });

  testWidgets("the regions end up in the frame's own coordinates",
      (tester) async {
    final host = _FakeHost();
    await pump(tester, host);

    // Two configurations: the first before the frame's shape was known, the
    // second once it was.
    expect(host.configs, hasLength(2));

    // The default tooth box is taller than it is wide on screen. The first
    // configuration still says so, because nothing better could be known.
    expect(
      host.configs.first.toothRect.width,
      lessThan(host.configs.first.toothRect.height),
    );

    // The one the platform measures by is in the landscape frame, so it has
    // to be wider than it is tall - and the two are each other's transpose.
    final measured = host.configs.last.toothRect;
    expect(measured.width, greaterThan(measured.height));
    expect(
      measured.width,
      closeTo(host.configs.first.toothRect.height, 1e-12),
    );
    await close(tester);
  });

  testWidgets('a refused permission explains how to grant it and retries',
      (tester) async {
    final host = _FakeHost(failWith: CameraErrorCode.permissionDenied);
    await pump(tester, host);

    expect(find.textContaining('has not been granted'), findsOneWidget);
    expect(find.textContaining('Settings'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    expect(host.initializeCalls, 1);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(host.initializeCalls, 2);
    await close(tester);
  });

  testWidgets('metrics replace the waiting state with numbers', (tester) async {
    final controller = await pump(tester, _FakeHost());
    expect(find.textContaining('123.4'), findsNothing);

    controller.onPreviewMetrics(_metrics());
    await tester.pumpAndSettle();

    expect(find.textContaining('123.4'), findsOneWidget);
    expect(find.textContaining('100'), findsOneWidget);
    // The colour-dependent reading is named as missing, not shown as a value.
    expect(find.textContaining('needs a profile'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a session that delivers no frames says so', (tester) async {
    final controller = await pump(tester, _FakeHost());
    expect(find.textContaining('no frames'), findsNothing);

    await tester.pump(LivePreviewController.starvationTimeout);
    await tester.pumpAndSettle();
    expect(find.textContaining('no frames'), findsOneWidget);

    // A frame clears it again.
    controller.onPreviewMetrics(_metrics());
    await tester.pumpAndSettle();
    expect(find.textContaining('no frames'), findsNothing);
    await close(tester);
  });

  testWidgets('there is no shutter on this screen', (tester) async {
    await pump(tester, _FakeHost());
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(find.textContaining('until every check is green'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a tap focuses at that point in the frame', (tester) async {
    final host = _FakeHost();
    await pump(tester, host);

    await tester.tapAt(tester.getCenter(find.byType(Texture)));
    await tester.pumpAndSettle();

    // The centre of the screen is the centre of the frame whatever the
    // rotation, so this is the one point the mapping cannot get wrong.
    expect(host.focusedX, closeTo(0.5, 0.02));
    await close(tester);
  });
}
