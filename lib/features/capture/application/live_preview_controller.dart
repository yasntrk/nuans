import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nuans/core/l10n/camera_error_strings.dart';
import 'package:nuans/data/platform/shade_camera_api.g.dart';
import 'package:nuans/features/capture/application/preview_geometry.dart';

/// Where the preview is in its lifecycle.
enum LivePreviewStage {
  /// Nothing has been asked of the platform yet.
  idle,

  /// The camera is being opened and the session configured.
  starting,

  /// A texture is live. Frames may or may not be arriving yet; that is what
  /// [LivePreviewController.isStarved] reports.
  running,

  /// Opening or configuring failed. [LivePreviewController.errorCode] says why.
  failed,
}

/// Drives one live preview: opens the camera, holds the texture and publishes
/// the metrics the platform sends.
///
/// Deliberately not a Riverpod notifier. The platform side is a single global
/// resource with a global callback registration, so a provider that could be
/// rebuilt or held twice would be a liability rather than a convenience; one
/// explicit owner, created and disposed by the screen, matches what the camera
/// actually is.
class LivePreviewController extends ChangeNotifier
    implements ShadeCameraFlutterApi {
  LivePreviewController({ShadeCameraHostApi? host, this.bindCallbacks = true})
      : _host = host ?? ShadeCameraHostApi();

  final ShadeCameraHostApi _host;

  /// Tests drive the callbacks directly and must not take over the real
  /// channel, which would outlive the test.
  final bool bindCallbacks;

  LivePreviewStage _stage = LivePreviewStage.idle;
  LivePreviewStage get stage => _stage;

  PreviewSession? _session;

  /// The texture and the frame geometry, once the preview is running.
  PreviewSession? get session => _session;

  /// How the frame relates to the screen, or `null` before it is running.
  PreviewGeometry? get geometry {
    final started = _session;
    if (started == null) return null;
    return PreviewGeometry(
      frameWidth: started.previewWidth,
      frameHeight: started.previewHeight,
      rotationDegrees: started.displayRotationDegrees,
    );
  }

  CameraErrorCode? _errorCode;
  CameraErrorCode? get errorCode => _errorCode;

  CameraCapabilities? _capabilities;
  CameraCapabilities? get capabilities => _capabilities;

  PreviewMetrics? _metrics;

  /// The newest frame's measurements, or `null` while none has arrived.
  PreviewMetrics? get metrics => _metrics;

  SessionInterruption? _interruption;
  SessionInterruption? get interruption => _interruption;

  Timer? _starvationTimer;
  bool _isStarved = false;

  /// True when the session is running but no frame has arrived within
  /// [starvationTimeout].
  ///
  /// Worth surfacing rather than leaving as a blank screen: a session that
  /// configures and then delivers nothing is a distinct failure from one that
  /// never opens, and it is the one a user describes as "the camera does not
  /// work".
  bool get isStarved => _isStarved;

  /// How long a running session may deliver nothing before it is called out.
  /// At the protocol's 100 ms metrics interval this is thirty missed frames.
  static const starvationTimeout = Duration(seconds: 3);

  /// Opens the camera and starts the preview.
  ///
  /// Safe to call again after a failure; calling it while already running is a
  /// no-op, because the platform owns one session at a time.
  Future<void> start(
    PreviewConfig Function(PreviewGeometry? geometry) configure,
  ) async {
    if (_stage == LivePreviewStage.starting ||
        _stage == LivePreviewStage.running) {
      return;
    }
    if (bindCallbacks) ShadeCameraFlutterApi.setUp(this);
    _stage = LivePreviewStage.starting;
    _errorCode = null;
    _interruption = null;
    notifyListeners();
    try {
      _capabilities = await _host.initialize();
      // The first configuration goes in before the frame's shape is known,
      // because the platform only reports it once the preview is running.
      _session = await _host.startPreview(configure(null));
      final shape = geometry;
      if (shape != null && shape.rotationDegrees != 0) {
        // Now the shape is known, the regions are sent again in the frame's
        // own coordinates. Without this they would stay in the screen's, and
        // the platform would measure a rotated rectangle somewhere other than
        // where the clinician put it.
        await _host.updatePreviewRois(configure(shape));
      }
      _stage = LivePreviewStage.running;
      _armStarvationTimer();
    } on PlatformException catch (error) {
      _fail(
        cameraErrorCodeFrom(error.code) ?? CameraErrorCode.configurationFailed,
      );
    } on Object {
      // Anything else is still a failure the user has to be told about; a
      // silent return would leave the screen on "starting" for ever.
      _fail(CameraErrorCode.configurationFailed);
    }
    notifyListeners();
  }

  /// Asks the platform to focus at a normalised point and pin the lens there.
  ///
  /// Focus is the one live control offered without a device profile: it changes
  /// no colour, so it cannot make an uncalibrated preview look more trustworthy
  /// than it is.
  Future<void> focusAt(double x, double y) async {
    if (_stage != LivePreviewStage.running) return;
    try {
      await _host.focusAndLockAt(x, y);
    } on PlatformException {
      // A refused autofocus is not worth taking the screen down for: the
      // metrics keep flowing and the sharpness reading shows the result.
    }
  }

  Future<void> stop() async {
    _starvationTimer?.cancel();
    _starvationTimer = null;
    if (bindCallbacks) ShadeCameraFlutterApi.setUp(null);
    if (_stage == LivePreviewStage.running) {
      try {
        await _host.stopPreview();
        await _host.dispose();
      } on PlatformException {
        // Tearing down is best effort: the platform frees the device when the
        // engine detaches regardless.
      }
    }
    _stage = LivePreviewStage.idle;
    _session = null;
    _metrics = null;
    _isStarved = false;
  }

  void _fail(CameraErrorCode code) {
    _starvationTimer?.cancel();
    _starvationTimer = null;
    _errorCode = code;
    _stage = LivePreviewStage.failed;
    _session = null;
  }

  void _armStarvationTimer() {
    _starvationTimer?.cancel();
    _starvationTimer = Timer(starvationTimeout, () {
      if (_metrics == null && _stage == LivePreviewStage.running) {
        _isStarved = true;
        notifyListeners();
      }
    });
  }

  // region ShadeCameraFlutterApi

  @override
  void onPreviewMetrics(PreviewMetrics metrics) {
    _metrics = metrics;
    if (_isStarved) _isStarved = false;
    _starvationTimer?.cancel();
    _starvationTimer = null;
    notifyListeners();
  }

  @override
  void onCaptureProgress(CaptureProgress progress) {
    // No capture can be started from this screen, so there is no progress to
    // show. Implemented because the contract requires it.
  }

  @override
  void onCameraError(CameraError error) {
    _fail(error.code);
    notifyListeners();
  }

  @override
  void onSessionInterrupted(SessionInterruption reason) {
    _interruption = reason;
    notifyListeners();
  }

  // endregion

  @override
  void dispose() {
    _starvationTimer?.cancel();
    _starvationTimer = null;
    if (bindCallbacks) ShadeCameraFlutterApi.setUp(null);
    super.dispose();
  }
}
