import 'package:meta/meta.dart';
import 'package:shade_core/shade_core.dart';

/// The six conditions that gate the shutter.
enum LiveCheck {
  /// Nothing clipping, and the card inside its signal window.
  exposure,

  /// The neutral card slot really holds a flat neutral surface.
  grayCard,

  /// The tooth is in focus.
  sharpness,

  /// The phone is still enough.
  motion,

  /// One light, not two.
  mixedLight,

  /// Held perpendicular to the surface.
  tilt,
}

/// Where a check currently stands.
enum CheckStatus {
  /// Not enough frames yet to say.
  pending,

  /// Failing now.
  failing,

  /// Passing, and settled.
  passing,
}

/// Why a check is failing, as a machine code the presentation layer maps onto
/// an ARB key.
enum LiveCheckReason {
  highlightsClipping,
  tooDark,
  grayCardMissing,
  grayCardNonUniform,
  mixedLightDetected,
  implausibleIlluminant,
  sharpnessLow,
  motionHigh,
  tiltHigh,
}

/// One check's outcome.
@immutable
final class CheckOutcome {
  const CheckOutcome({
    required this.check,
    required this.status,
    this.reason,
    this.measuredValue,
  });

  final LiveCheck check;
  final CheckStatus status;

  /// Present only while failing.
  final LiveCheckReason? reason;

  /// The number behind the verdict, for the diagnostics panel. Never shown as
  /// the primary message: a clinician needs "hold it still", not a figure.
  final double? measuredValue;

  bool get isPassing => status == CheckStatus.passing;

  @override
  String toString() => '${check.name}: ${status.name}'
      '${reason == null ? '' : ' (${reason!.name})'}';
}

/// What one preview frame contributes, already translated out of the platform
/// types and linearised where it needed to be.
///
/// Note what is *not* here: a verdict. The native layer measures and this
/// evaluator decides, which is what keeps every threshold in a unit test.
@immutable
final class LiveCheckInput {
  const LiveCheckInput({
    required this.toothSharpness,
    required this.motionScore,
    required this.toothClippedFraction,
    required this.grayCardVerdict,
    required this.focusLocked,
    required this.exposureLocked,
    this.tiltDegrees,
    this.burstRelativeSharpness,
  });

  final double toothSharpness;
  final double motionScore;
  final double toothClippedFraction;

  /// The colour judgement, made in shade_core from the linearised preview
  /// values.
  final GrayCardVerdict grayCardVerdict;

  final bool focusLocked;
  final bool exposureLocked;

  /// From the device's own motion sensors, not from the camera.
  final double? tiltDegrees;

  /// Sharpness relative to the sharpest frame seen recently, when known.
  final double? burstRelativeSharpness;
}

/// Thresholds for the live checks.
///
/// Separate from the capture protocol's own constants because these gate a
/// traffic light rather than a measurement: they can be looser, and a device
/// that cannot reach them still has to be able to show a preview.
@immutable
final class LiveCheckThresholds {
  const LiveCheckThresholds({
    this.minSharpness = 40,
    this.maxMotionScore = 0.035,
    this.maxToothClippedFraction = 0.01,
    this.maxTiltDegrees = 5,
    this.framesToSettle = 4,
    this.framesToFail = 2,
  });

  /// **placeholder** - device dependent, to be measured per model.
  final double minSharpness;

  /// **placeholder** - normalised inter-frame difference.
  final double maxMotionScore;

  final double maxToothClippedFraction;

  /// Protocol value: perpendicular to within five degrees.
  final double maxTiltDegrees;

  /// Consecutive good frames before a check turns green.
  ///
  /// Hysteresis is not polish. At 10 Hz a check evaluated frame by frame
  /// flickers on any borderline value, and a flickering traffic light teaches a
  /// clinician to ignore it. Turning green is slow and turning red is fast,
  /// because a false green is the expensive direction.
  final int framesToSettle;

  /// Consecutive bad frames before a green check turns red.
  final int framesToFail;
}

/// The state of all six checks.
@immutable
final class LiveCheckState {
  const LiveCheckState({
    required this.outcomes,
    required this.canCapture,
    required this.becameReady,
  });

  /// The initial state: everything pending, shutter disabled.
  factory LiveCheckState.initial() => LiveCheckState(
        outcomes: {
          for (final check in LiveCheck.values)
            check: CheckOutcome(check: check, status: CheckStatus.pending),
        },
        canCapture: false,
        becameReady: false,
      );

  final Map<LiveCheck, CheckOutcome> outcomes;

  /// True only when every check is passing.
  final bool canCapture;

  /// True on the single frame where the shutter became available, so the haptic
  /// fires once rather than on every frame.
  final bool becameReady;

  List<CheckOutcome> get failing =>
      outcomes.values.where((o) => o.status == CheckStatus.failing).toList();

  @override
  String toString() =>
      'LiveCheckState(canCapture: $canCapture, failing: ${failing.length})';
}

/// Turns a stream of preview measurements into the six traffic lights.
///
/// Stateful by necessity: the hysteresis counters are the state. Everything
/// else is a pure function of one input, so a test can drive a sequence of
/// frames through it and assert on the transitions.
final class LiveCheckMachine {
  LiveCheckMachine({this.thresholds = const LiveCheckThresholds()});

  final LiveCheckThresholds thresholds;

  final Map<LiveCheck, int> _goodFrames = {
    for (final check in LiveCheck.values) check: 0,
  };
  final Map<LiveCheck, int> _badFrames = {
    for (final check in LiveCheck.values) check: 0,
  };
  final Map<LiveCheck, CheckStatus> _status = {
    for (final check in LiveCheck.values) check: CheckStatus.pending,
  };
  bool _wasReady = false;

  /// Resets to the initial state. Called whenever the preview restarts, so a
  /// stale green from the previous session cannot carry over.
  void reset() {
    for (final check in LiveCheck.values) {
      _goodFrames[check] = 0;
      _badFrames[check] = 0;
      _status[check] = CheckStatus.pending;
    }
    _wasReady = false;
  }

  LiveCheckState update(LiveCheckInput input) {
    final raw = _evaluate(input);
    final outcomes = <LiveCheck, CheckOutcome>{};

    for (final check in LiveCheck.values) {
      final failure = raw[check];
      if (failure == null) {
        _goodFrames[check] = _goodFrames[check]! + 1;
        _badFrames[check] = 0;
        if (_goodFrames[check]! >= thresholds.framesToSettle) {
          _status[check] = CheckStatus.passing;
        }
      } else {
        _badFrames[check] = _badFrames[check]! + 1;
        _goodFrames[check] = 0;
        if (_badFrames[check]! >= thresholds.framesToFail ||
            _status[check] == CheckStatus.pending) {
          _status[check] = CheckStatus.failing;
        }
      }
      outcomes[check] = CheckOutcome(
        check: check,
        status: _status[check]!,
        reason: _status[check] == CheckStatus.failing ? failure?.reason : null,
        measuredValue: failure?.value ?? _measuredValueOf(check, input),
      );
    }

    final ready = outcomes.values.every((o) => o.isPassing);
    final becameReady = ready && !_wasReady;
    _wasReady = ready;

    return LiveCheckState(
      outcomes: Map<LiveCheck, CheckOutcome>.unmodifiable(outcomes),
      canCapture: ready,
      becameReady: becameReady,
    );
  }

  /// Per-check failure, or absent when the check is satisfied by this frame.
  Map<LiveCheck, _Failure?> _evaluate(LiveCheckInput input) {
    final issues = input.grayCardVerdict.issues;
    return {
      LiveCheck.exposure: () {
        if (input.toothClippedFraction > thresholds.maxToothClippedFraction) {
          return _Failure(
            LiveCheckReason.highlightsClipping,
            input.toothClippedFraction,
          );
        }
        if (issues.contains(GrayCardIssue.tooDark)) {
          return _Failure(
            LiveCheckReason.tooDark,
            input.grayCardVerdict.medianGreen,
          );
        }
        if (issues.contains(GrayCardIssue.clipped) ||
            issues.contains(GrayCardIssue.tooBright)) {
          return _Failure(
            LiveCheckReason.highlightsClipping,
            input.grayCardVerdict.clippedFraction,
          );
        }
        return null;
      }(),
      LiveCheck.grayCard: () {
        if (issues.contains(GrayCardIssue.nonUniform)) {
          return _Failure(
            LiveCheckReason.grayCardNonUniform,
            input.grayCardVerdict.uniformityRatio,
          );
        }
        // An empty slot reads as a dark, textureless patch, which the
        // uniformity check does not catch on its own.
        if (input.grayCardVerdict.medianGreen <= 0.02) {
          return _Failure(
            LiveCheckReason.grayCardMissing,
            input.grayCardVerdict.medianGreen,
          );
        }
        return null;
      }(),
      LiveCheck.sharpness: () {
        if (!input.focusLocked) {
          return _Failure(LiveCheckReason.sharpnessLow, input.toothSharpness);
        }
        final relative = input.burstRelativeSharpness;
        if (input.toothSharpness < thresholds.minSharpness &&
            (relative == null || relative < 0.6)) {
          return _Failure(LiveCheckReason.sharpnessLow, input.toothSharpness);
        }
        return null;
      }(),
      LiveCheck.motion: input.motionScore > thresholds.maxMotionScore
          ? _Failure(LiveCheckReason.motionHigh, input.motionScore)
          : null,
      LiveCheck.mixedLight: () {
        if (issues.contains(GrayCardIssue.mixedLight)) {
          return _Failure(
            LiveCheckReason.mixedLightDetected,
            input.grayCardVerdict.quadrantMaxDeltaE,
          );
        }
        if (issues.contains(GrayCardIssue.implausibleIlluminant)) {
          return _Failure(
            LiveCheckReason.implausibleIlluminant,
            input.grayCardVerdict.correlatedColorTemperature,
          );
        }
        return null;
      }(),
      LiveCheck.tilt: () {
        final tilt = input.tiltDegrees;
        // An unknown tilt is not a pass. A device with no usable motion sensor
        // would otherwise get a free green on the one check that no amount of
        // image analysis can recover.
        if (tilt == null || tilt.abs() > thresholds.maxTiltDegrees) {
          return _Failure(LiveCheckReason.tiltHigh, tilt);
        }
        return null;
      }(),
    };
  }

  double? _measuredValueOf(LiveCheck check, LiveCheckInput input) =>
      switch (check) {
        LiveCheck.exposure => input.toothClippedFraction,
        LiveCheck.grayCard => input.grayCardVerdict.uniformityRatio,
        LiveCheck.sharpness => input.toothSharpness,
        LiveCheck.motion => input.motionScore,
        LiveCheck.mixedLight => input.grayCardVerdict.quadrantMaxDeltaE,
        LiveCheck.tilt => input.tiltDegrees,
      };
}

@immutable
final class _Failure {
  const _Failure(this.reason, this.value);

  final LiveCheckReason reason;
  final double? value;
}
