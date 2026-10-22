import 'package:nuans/data/platform/shade_camera_api.g.dart';
import 'package:nuans/l10n/app_localizations.dart';

/// Turns a machine error code from the platform into a sentence for the user.
///
/// A function rather than a map so the compiler enforces that every code has a
/// message: a switch over an enum with no default fails to compile when a code
/// is added to the Pigeon contract, which is exactly when a missing message
/// would otherwise ship. `nativeMessage` is never shown - it is an English
/// diagnostic for a log, not a sentence for a clinician.
String cameraErrorMessage(AppLocalizations strings, CameraErrorCode code) =>
    switch (code) {
      CameraErrorCode.permissionDenied => strings.errorPermissionDenied,
      CameraErrorCode.deviceUnavailable => strings.errorDeviceUnavailable,
      CameraErrorCode.configurationFailed => strings.errorConfigurationFailed,
      CameraErrorCode.focusLockFailed => strings.errorFocusLockFailed,
      CameraErrorCode.exposureLockFailed => strings.errorExposureLockFailed,
      CameraErrorCode.whiteBalanceLockFailed =>
        strings.errorWhiteBalanceLockFailed,
      CameraErrorCode.rawUnavailable => strings.errorRawUnavailable,
      CameraErrorCode.captureFailed => strings.errorCaptureFailed,
      CameraErrorCode.roiOutOfBounds => strings.errorRoiOutOfBounds,
      CameraErrorCode.unknownCaptureId => strings.errorUnknownCaptureId,
      CameraErrorCode.captureExpired => strings.errorCaptureExpired,
      CameraErrorCode.previewNotRunning => strings.errorPreviewNotRunning,
      CameraErrorCode.interrupted => strings.errorInterrupted,
    };

/// The code a platform exception carries, or `null` when it is not one of ours.
///
/// Pigeon reports a host failure as a `PlatformException` whose `code` is the
/// string the native side put there; this maps it back onto the enum so the UI
/// has one way of describing a failure however it arrived.
CameraErrorCode? cameraErrorCodeFrom(String? raw) {
  if (raw == null) return null;
  final normalised = raw.replaceAll('_', '').toLowerCase();
  for (final code in CameraErrorCode.values) {
    if (code.name.toLowerCase() == normalised) return code;
  }
  return null;
}
