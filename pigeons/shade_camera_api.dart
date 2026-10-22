// Nuans - platform contract for the calibrated capture layer.
//
// This is the single source of truth for the Flutter <-> native boundary.
// Regenerate with:
//
//   dart run pigeon --input pigeons/shade_camera_api.dart
//
// Design rules enforced by this contract (see
// docs/architecture/01-architecture.md):
//
//  1. No colour science crosses this boundary. The native side returns LINEAR
//     camera-space RGB triples (black level removed, normalised by white level)
//     plus pixel statistics. Every transform - linearisation of processed
//     images, von Kries gains, CCM, XYZ, Lab, CIEDE2000 - happens in
//     packages/shade_core so that it is unit testable. See ADR-0001.
//  2. No user-facing text crosses this boundary. Native reports machine codes
//     (enums / `limitationCodes`) that the app maps to ARB keys.
//     `nativeMessage` is diagnostic only and must never be rendered.
//  3. Policy travels downwards. Sharpness, motion and clipping thresholds,
//     sample budgets and the gray-card luma target are chosen by Dart and
//     passed in `CaptureSettings`; native only measures and obeys.
//  4. All rectangles are sensor-normalised (0..1). Pixel geometry differs per
//     device and must not leak into the app layer.
//  5. Identity is minted by Dart. `captureId` lets the app ask for a re-reduced
//     ROI from the retained frames (`resampleRoi`) and then free them
//     (`releaseCapture`), making native memory ownership deterministic.
//  6. Nothing is assumed to be linear. Only a Bayer RAW capture is; the
//     preview stream and a processed capture are display-referred, and native
//     never linearises either, because that transform belongs in shade_core
//     where it is tested. `SignalEncoding` carries the fact on both the preview
//     and the capture message, so no field name has to be trusted.
//  7. The preview path gates the shutter; it never measures. Preview values
//     drive the live traffic lights as an approximation, and the grey card
//     validation the measurement relies on runs again on the captured burst.
//
// Pigeon data classes are mutable by construction; the CameraGateway maps them
// onto the immutable value types of shade_core immediately at the boundary.

// `Float64List` and friends come through pigeon's own export: pigeon rejects
// any import but its own, so `dart:typed_data` must not be imported here even
// though the types it defines are used below.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/data/platform/shade_camera_api.g.dart',
    dartPackageName: 'nuans',
    swiftOut: 'ios/Runner/Camera/ShadeCameraApi.g.swift',
    kotlinOut:
        'android/app/src/main/kotlin/com/nuans/app/camera/ShadeCameraApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.nuans.app.camera'),
  ),
)

/// Operating tier of the current camera/lens combination.
///
/// `full` requires manual sensor control (ISO, exposure time), lockable white
/// balance and Bayer RAW output. Anything less is `limited`: the capture still
/// runs with locked processed frames, but the measurement is flagged with a low
/// confidence badge.
enum CaptureTier {
  full,
  limited,
}

/// Pixel format actually used for a capture.
///
/// `bayerRaw` is undemosaiced sensor data. `processedLinearisable` is a locked
/// HEIF/JPEG frame that still carries an sRGB-like transfer function; Dart
/// linearises it and lowers the confidence score.
enum CaptureFormat {
  bayerRaw,
  processedLinearisable,
}

/// What a region of interest represents.
enum RoiKind {
  /// One of the three bands of the target tooth.
  toothBand,

  /// The 18 % neutral gray card in the overlay slot.
  grayCard,

  /// A physical shade guide tab held in the same frame (relative mode).
  shadeTab,

  /// One patch of a 24-patch colour reference chart (device profiling).
  colorCheckerPatch,
}

/// Vertical band of the tooth silhouette. Only meaningful for `toothBand`.
enum ToothRegion {
  cervical,
  body,
  incisal,
}

/// Why native dropped a burst frame. The thresholds themselves come from Dart.
enum FrameRejectReason {
  lowSharpness,
  motion,
  clippedHighlights,
  underexposed,
  readFailed,
}

/// Machine codes for every failure the native layer can report. The app maps
/// each one to a localised message; native never formats text for the user.
enum CameraErrorCode {
  permissionDenied,
  deviceUnavailable,
  configurationFailed,
  focusLockFailed,
  exposureLockFailed,
  whiteBalanceLockFailed,
  rawUnavailable,
  captureFailed,
  roiOutOfBounds,
  unknownCaptureId,
  captureExpired,
  previewNotRunning,
  interrupted,
}

/// Reasons the OS can tear down or throttle an active session.
enum SessionInterruption {
  backgrounded,
  deviceInUseByAnotherClient,
  thermalThrottling,
  hardwareCostExceeded,
  unknown,
}

/// How a message's pixel values are encoded.
///
/// Two paths carry non-linear values and must say so rather than be assumed:
///
/// * the preview stream, which is always a processed, display-referred frame
///   because no platform offers a linear preview on the main capture path;
/// * a capture taken in `CaptureFormat.processedLinearisable`, where the frame
///   went through the platform's imaging pipeline before native saw it.
///
/// A Bayer RAW capture is the only `linear` case. Dart linearises the others
/// with `Srgb.decode` from shade_core, so the transform itself stays unit
/// tested, and lowers the confidence score because a global inverse transfer
/// function does not undo local tone mapping.
enum SignalEncoding {
  /// Display-referred, roughly sRGB-encoded. Needs linearising before use.
  displayReferredSrgb,

  /// Already linear. No platform currently reports this; the case exists so
  /// that a future linear preview path does not need a contract change.
  linear,
}

/// Stage reported while a burst capture is in flight, for progress UI.
enum CaptureStage {
  lockingParameters,
  capturingBurst,
  selectingFrames,
  reducingRois,
  finalising,
}

/// Sensor-normalised rectangle. Origin is the top-left of the active sensor
/// area; all values are in 0..1 and `left + width <= 1`.
class NormalizedRect {
  NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double left;
  double top;
  double width;
  double height;
}

/// A region native must reduce. `region` is set only when [kind] is
/// `RoiKind.toothBand`; `index` identifies the patch for colour charts.
class RoiRequest {
  RoiRequest({
    required this.roiId,
    required this.kind,
    required this.rect,
    this.region,
    this.index,
  });

  /// Stable identifier chosen by Dart, e.g. `tooth.cervical`, `patch.07`.
  String roiId;
  RoiKind kind;
  NormalizedRect rect;
  ToothRegion? region;
  int? index;
}

/// How many superpixels to return per ROI and when to call one clipped.
class SamplingSettings {
  SamplingSettings({
    required this.maxSamplesPerRoi,
    required this.clippingThreshold,
  });

  /// Upper bound on returned triples per ROI. Native decimates on a regular
  /// lattice (stride sampling, never averaging) so the outlier distribution
  /// that Dart's specular filter relies on survives the reduction.
  ///
  /// The stride is derived from ROI GEOMETRY alone - not from the surviving
  /// superpixel count - so the lattice is identical in every frame of the
  /// burst and cross-frame averaging stays aligned sample by sample.
  int maxSamplesPerRoi;

  /// Fraction of the white level above which a Bayer block counts as clipped
  /// and is discarded (protocol value: 0.95).
  double clippingThreshold;
}

/// Everything native needs to lock the sensor and run one burst. Chosen by the
/// app so that every threshold is covered by Dart unit tests.
class CaptureSettings {
  CaptureSettings({
    required this.burstFrameCount,
    required this.preferBayerRaw,
    required this.grayCardTargetLuma,
    required this.minSharpness,
    required this.maxMotionScore,
    required this.maxClippedFraction,
    required this.sampling,
    this.isoOverride,
    this.exposureSecondsOverride,
  });

  /// Frames per burst (protocol value: 3).
  int burstFrameCount;
  bool preferBayerRaw;

  /// Target normalised signal for the gray card when solving the shutter, in
  /// 0..1 of the white level. Keeps both card and tooth clear of clipping.
  double grayCardTargetLuma;

  /// Laplacian-variance floor for accepting a frame.
  double minSharpness;

  /// Normalised inter-frame difference ceiling for accepting a frame.
  double maxMotionScore;

  /// Share of clipped superpixels above which a frame is rejected outright.
  double maxClippedFraction;

  SamplingSettings sampling;

  /// Diagnostics / device-profiling escape hatches. Null means "solve it".
  int? isoOverride;
  double? exposureSecondsOverride;
}

/// One burst request. `captureId` is minted by Dart and owns the lifetime of
/// the retained frames on the native side.
class CaptureRequest {
  CaptureRequest({
    required this.captureId,
    required this.rois,
    required this.settings,
  });

  String captureId;
  List<RoiRequest> rois;
  CaptureSettings settings;
}

/// Live ROI rectangles native should measure for the preview traffic lights.
class PreviewConfig {
  PreviewConfig({
    required this.metricsIntervalMillis,
    required this.toothRect,
    required this.grayCardRect,
    required this.clippingThreshold,
    this.shadeTabRect,
  });

  /// Throttle for `onPreviewMetrics` (protocol value: 100 ms).
  int metricsIntervalMillis;
  NormalizedRect toothRect;
  NormalizedRect grayCardRect;
  double clippingThreshold;
  NormalizedRect? shadeTabRect;
}

/// A started preview: what to display, and at what shape.
class PreviewSession {
  PreviewSession({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    required this.displayRotationDegrees,
  });

  /// The Flutter texture the preview widget renders.
  int textureId;

  /// The frame size the platform chose for the preview stream.
  ///
  /// Part of the contract rather than left for the UI to guess, because every
  /// [NormalizedRect] here is normalised against the frame. A preview drawn at
  /// a different aspect ratio would put the overlay somewhere other than where
  /// the measurement is actually taken, which is the one kind of misalignment
  /// a clinician cannot see and cannot correct for.
  int previewWidth;
  int previewHeight;

  /// Clockwise rotation, in degrees, the preview must be turned by before it
  /// is displayed with the device held upright.
  ///
  /// A camera writes frames in its sensor's orientation, which on nearly every
  /// phone is ninety degrees away from the way the device is held. Reported
  /// rather than assumed, because the value is a property of the hardware and
  /// getting it wrong rotates the overlay away from the regions the native
  /// side is measuring. [previewWidth] and [previewHeight] describe the frame
  /// before this rotation.
  int displayRotationDegrees;
}

/// Sensor state at the moment of capture, recorded in the report and used to
/// prove that the acquisition was locked.
class ExposureState {
  ExposureState({
    required this.iso,
    required this.exposureSeconds,
    required this.focusLocked,
    required this.exposureLocked,
    required this.whiteBalanceLocked,
    required this.whiteBalanceGains,
    this.focusDistanceDiopters,
    this.colorTemperatureKelvin,
  });

  int iso;
  double exposureSeconds;
  bool focusLocked;
  bool exposureLocked;
  bool whiteBalanceLocked;

  /// Locked per-channel device gains, length 3 (R, G, B). Their absolute value
  /// is irrelevant to the measurement; only their stability matters, because
  /// the real correction comes from the gray card.
  Float64List whiteBalanceGains;

  double? focusDistanceDiopters;
  double? colorTemperatureKelvin;
}

/// DNG colour metadata, used only as a fallback when no device profile exists.
/// Dart lowers the confidence score when a measurement relies on it.
class DngColorMetadata {
  DngColorMetadata({
    required this.colorMatrix1,
    required this.asShotNeutral,
    required this.blackLevel,
    required this.whiteLevel,
    this.forwardMatrix1,
    this.calibrationIlluminant1,
  });

  /// Row-major 3x3, length 9.
  Float64List colorMatrix1;

  /// Length 3.
  Float64List asShotNeutral;

  double blackLevel;
  double whiteLevel;

  /// Row-major 3x3, length 9, when the DNG provides it.
  Float64List? forwardMatrix1;

  /// EXIF illuminant code, e.g. 21 for D65.
  int? calibrationIlluminant1;
}

/// The reduced content of one ROI: the only numeric payload Dart needs to
/// perform the full colour pipeline.
class RoiSample {
  RoiSample({
    required this.roiId,
    required this.kind,
    required this.rect,
    required this.rgbSamples,
    required this.sampleCount,
    required this.totalSuperpixels,
    required this.clippedSuperpixels,
    required this.decimationStride,
    required this.channelMean,
    required this.channelStdDev,
    required this.widthInSuperpixels,
    required this.heightInSuperpixels,
    this.region,
    this.index,
  });

  String roiId;
  RoiKind kind;
  NormalizedRect rect;

  /// Interleaved R, G, B triples normalised to 0..1 of the white level, in the
  /// encoding named by `CaptureResult.signalEncoding`. Length is exactly
  /// `3 * sampleCount`.
  ///
  /// On the RAW path each triple is one Bayer 2x2 superpixel - R, mean(G1, G2),
  /// B - averaged across the accepted burst frames at the same lattice
  /// position, and the values are linear camera space. On the processed path
  /// they are display-referred and Dart linearises them.
  ///
  /// A lattice point clipped in ANY accepted frame is absent from all of them,
  /// so every returned triple has the same frame support.
  Float64List rgbSamples;

  int sampleCount;

  /// Superpixels inside the ROI before any rejection.
  int totalSuperpixels;

  /// Superpixels dropped because a channel exceeded the clipping threshold.
  int clippedSuperpixels;

  /// Lattice stride used to reach `maxSamplesPerRoi`, derived from ROI
  /// geometry: `max(1, ceil(sqrt(totalSuperpixels / maxSamplesPerRoi)))`.
  /// 1 means no decimation.
  int decimationStride;

  /// Exact mean over ALL non-clipped superpixels, length 3. Computed on the
  /// full set, not on the returned sample, so Dart can detect decimation bias.
  Float64List channelMean;

  /// Exact population standard deviation over all non-clipped superpixels,
  /// length 3. Feeds the ROI homogeneity term of the confidence score.
  Float64List channelStdDev;

  int widthInSuperpixels;
  int heightInSuperpixels;

  ToothRegion? region;
  int? index;
}

/// Per-frame quality record of the burst, kept for the audit trail.
class FrameQuality {
  FrameQuality({
    required this.frameIndex,
    required this.sharpness,
    required this.motionScore,
    required this.clippedFraction,
    required this.accepted,
    this.rejectReason,
  });

  int frameIndex;

  /// Laplacian variance over the tooth rectangle.
  double sharpness;

  /// Normalised mean absolute difference against the previous frame.
  double motionScore;

  double clippedFraction;
  bool accepted;
  FrameRejectReason? rejectReason;
}

/// Result of one burst. ROI samples are already averaged across the accepted
/// frames in linear camera space.
class CaptureResult {
  CaptureResult({
    required this.captureId,
    required this.tier,
    required this.format,
    required this.signalEncoding,
    required this.rois,
    required this.frames,
    required this.acceptedFrameCount,
    required this.exposure,
    required this.capturedAtUtcMillis,
    required this.deviceModel,
    required this.lensId,
    required this.sensorWhiteLevel,
    required this.sensorBlackLevel,
    this.previewImagePath,
    this.rawFilePath,
    this.dngMetadata,
  });

  String captureId;
  CaptureTier tier;
  CaptureFormat format;

  /// How to read every `RoiSample.rgbSamples` of this capture: `linear` for
  /// `CaptureFormat.bayerRaw`, `displayReferredSrgb` otherwise.
  SignalEncoding signalEncoding;

  List<RoiSample> rois;
  List<FrameQuality> frames;
  int acceptedFrameCount;
  ExposureState exposure;

  /// Capture instant in UTC milliseconds since epoch; the app formats it.
  int capturedAtUtcMillis;

  String deviceModel;
  String lensId;

  /// Levels already applied to `linearRgbSamples`, reported for traceability.
  double sensorWhiteLevel;
  double sensorBlackLevel;

  /// Display/report JPEG written to the app sandbox, with ROI geometry intact.
  String? previewImagePath;

  /// Retained RAW file, when the user enabled raw archiving.
  String? rawFilePath;

  /// Present only when no device profile was active for this lens.
  DngColorMetadata? dngMetadata;
}

/// Live measurements for the capture screen's traffic lights. Every value is a
/// measurement, never a verdict: Dart decides pass/fail.
class PreviewMetrics {
  PreviewMetrics({
    required this.timestampMillis,
    required this.format,
    required this.signalEncoding,
    required this.toothSharpness,
    required this.motionScore,
    required this.toothClippedFraction,
    required this.toothShadowFraction,
    required this.toothRgbMean,
    required this.grayCardClippedFraction,
    required this.grayCardTextureRatio,
    required this.grayCardQuadrantRgb,
    required this.iso,
    required this.exposureSeconds,
    required this.focusLocked,
    required this.exposureLocked,
    required this.whiteBalanceLocked,
    this.focusDistanceDiopters,
    this.shadeTabRgbMean,
  });

  int timestampMillis;
  CaptureFormat format;

  /// How to interpret every RGB triple in this message. Always
  /// `SignalEncoding.displayReferredSrgb` on both platforms today.
  SignalEncoding signalEncoding;

  double toothSharpness;
  double motionScore;
  double toothClippedFraction;

  /// Share of superpixels at or below the black level inside the tooth ROI.
  double toothShadowFraction;

  /// Mean of the tooth ROI, length 3, in the encoding named by
  /// [signalEncoding]. Preview only: never used for a measurement.
  Float64List toothRgbMean;

  double grayCardClippedFraction;

  /// Spatial standard deviation divided by the mean of the gray card ROI. High
  /// values mean the slot is not actually on the card (texture, edge, shadow).
  double grayCardTextureRatio;

  /// Means of the gray card's four quadrants, length 12 (q0.r, q0.g, q0.b,
  /// q1.r, ...), in the encoding named by [signalEncoding]. Dart linearises
  /// them, converts to Lab and flags mixed lighting when the spread across
  /// quadrants is too large - the colour judgement stays testable in
  /// shade_core.
  ///
  /// This drives the live traffic light only. It is an approximation, because
  /// the preview frame has been through the platform's processing pipeline and
  /// a global inverse transfer function does not undo that exactly. The grey
  /// card validation that the measurement actually relies on runs again on the
  /// `grayCard` ROI of [CaptureResult], where the values are linear.
  Float64List grayCardQuadrantRgb;

  int iso;
  double exposureSeconds;
  bool focusLocked;
  bool exposureLocked;
  bool whiteBalanceLocked;
  double? focusDistanceDiopters;

  /// Mean of the shade tab slot, length 3, in the encoding named by
  /// [signalEncoding], when a tab slot is configured.
  Float64List? shadeTabRgbMean;
}

/// Progress of an in-flight burst.
class CaptureProgress {
  CaptureProgress({
    required this.captureId,
    required this.stage,
    required this.capturedFrames,
    required this.requestedFrames,
  });

  String captureId;
  CaptureStage stage;
  int capturedFrames;
  int requestedFrames;
}

/// A native failure, as a code plus diagnostics. Never rendered verbatim.
class CameraError {
  CameraError({
    required this.code,
    required this.recoverable,
    this.nativeMessage,
    this.captureId,
  });

  CameraErrorCode code;

  /// True when retrying the same call can succeed (e.g. transient AF failure).
  bool recoverable;

  /// Log-only diagnostic string, not localised, not for display.
  String? nativeMessage;

  String? captureId;
}

/// What the current camera and lens can do, probed once per session.
class CameraCapabilities {
  CameraCapabilities({
    required this.tier,
    required this.supportsManualSensor,
    required this.supportsBayerRaw,
    required this.supportsWhiteBalanceLock,
    required this.supportsFocusLock,
    required this.minIso,
    required this.maxIso,
    required this.minExposureSeconds,
    required this.maxExposureSeconds,
    required this.defaultFormat,
    required this.deviceModel,
    required this.lensId,
    required this.sensorWidthPixels,
    required this.sensorHeightPixels,
    required this.limitationCodes,
    this.focalLengthMillimeters,
  });

  CaptureTier tier;
  bool supportsManualSensor;
  bool supportsBayerRaw;
  bool supportsWhiteBalanceLock;
  bool supportsFocusLock;

  int minIso;
  int maxIso;
  double minExposureSeconds;
  double maxExposureSeconds;

  CaptureFormat defaultFormat;

  /// Stable identifiers used as the device-profile key, e.g. `iPhone15,2` and
  /// `builtInWideAngleCamera`. Only the main 1x rear lens is ever selected.
  String deviceModel;
  String lensId;

  int sensorWidthPixels;
  int sensorHeightPixels;

  /// Machine codes such as `noManualSensor`, `noRawSupport`,
  /// `whiteBalanceNotLockable`, each mapped to an ARB key by the app.
  List<String> limitationCodes;

  double? focalLengthMillimeters;
}

/// Flutter -> native. Every call is async and throws a `CameraError`-shaped
/// platform error on failure.
@HostApi()
abstract class ShadeCameraHostApi {
  /// Selects the main rear 1x lens, probes it and decides the tier. Ultra-wide
  /// lenses and digital zoom are never selected.
  @async
  CameraCapabilities initialize();

  /// Starts the preview and the metrics stream.
  @async
  PreviewSession startPreview(PreviewConfig config);

  /// Applies new live ROI rectangles after the user drags the overlay.
  @async
  void updatePreviewRois(PreviewConfig config);

  @async
  void stopPreview();

  /// Runs autofocus at a sensor-normalised point, then locks focus there.
  @async
  void focusAndLockAt(double x, double y);

  /// Locks ISO at the sensor minimum, solves and locks the shutter against
  /// `grayCardTargetLuma` without clipping the card or the tooth, and locks
  /// white balance at fixed gains. Disables flash and all computational
  /// pipelines (HDR, night mode, fusion).
  @async
  ExposureState lockCaptureParameters(CaptureSettings settings);

  @async
  void unlockCaptureParameters();

  /// Captures the burst, selects frames, reduces every ROI and retains the
  /// accepted frames under `captureId` until `releaseCapture`.
  @async
  CaptureResult capture(CaptureRequest request);

  /// Re-reduces one ROI from the retained frames of `captureId`, so dragging an
  /// ROI on the analysis screen never requires a new acquisition.
  @async
  RoiSample resampleRoi(
    String captureId,
    RoiRequest roi,
    SamplingSettings sampling,
  );

  /// Frees the retained frames. Mandatory when leaving the analysis screen.
  @async
  void releaseCapture(String captureId);

  @async
  void dispose();
}

/// Native -> Flutter callbacks.
@FlutterApi()
abstract class ShadeCameraFlutterApi {
  /// Throttled by `PreviewConfig.metricsIntervalMillis`.
  void onPreviewMetrics(PreviewMetrics metrics);

  void onCaptureProgress(CaptureProgress progress);

  void onCameraError(CameraError error);

  void onSessionInterrupted(SessionInterruption reason);
}
