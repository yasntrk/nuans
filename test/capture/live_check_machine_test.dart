import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/features/capture/application/live_check_machine.dart';
import 'package:shade_core/shade_core.dart';

void main() {
  final ccm = ColorCorrectionMatrix(
    matrix: Srgb.linearToXyzD65,
    whitePoint: WhitePoint.d65,
    source: CcmSource.chartFit,
  );
  const validator = GrayCardValidator();
  // A card lit at roughly 5500 K and exposed to the protocol's target.
  const card = CameraRgb(0.5033565720, 0.4500000000, 0.3754552925);

  GrayCardVerdict verdict({
    CameraRgb median = card,
    double uniformityRatio = 0.02,
    double clippedFraction = 0,
    List<CameraRgb>? quadrants,
  }) =>
      validator.validate(
        median: median,
        uniformityRatio: uniformityRatio,
        clippedFraction: clippedFraction,
        quadrants: quadrants ?? List<CameraRgb>.filled(4, median),
        ccm: ccm,
      );

  LiveCheckInput goodFrame({
    double sharpness = 120,
    double motion = 0.004,
    double clipped = 0,
    double? tilt = 1.5,
    GrayCardVerdict? card,
    bool focusLocked = true,
  }) =>
      LiveCheckInput(
        toothSharpness: sharpness,
        motionScore: motion,
        toothClippedFraction: clipped,
        grayCardVerdict: card ?? verdict(),
        focusLocked: focusLocked,
        exposureLocked: true,
        tiltDegrees: tilt,
      );

  LiveCheckState settle(
    LiveCheckMachine machine,
    LiveCheckInput frame, {
    int frames = 4,
  }) {
    var state = LiveCheckState.initial();
    for (var i = 0; i < frames; i++) {
      state = machine.update(frame);
    }
    return state;
  }

  group('settling', () {
    test('nothing is green before the first frame', () {
      final state = LiveCheckState.initial();
      expect(state.canCapture, isFalse);
      expect(
        state.outcomes.values.every((o) => o.status == CheckStatus.pending),
        isTrue,
      );
    });

    test('a good frame does not turn a check green on its own', () {
      final machine = LiveCheckMachine();
      final afterOne = machine.update(goodFrame());
      expect(afterOne.canCapture, isFalse);
      // Turning green is deliberately slow: at 10 Hz a per-frame verdict
      // flickers on any borderline value, and a flickering traffic light
      // teaches a clinician to ignore it.
      expect(
        afterOne.outcomes[LiveCheck.sharpness]!.status,
        CheckStatus.pending,
      );
    });

    test('four good frames turn everything green', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame());
      expect(state.canCapture, isTrue);
      expect(state.failing, isEmpty);
    });

    test('the ready transition is reported once, not on every frame', () {
      final machine = LiveCheckMachine();
      final first = settle(machine, goodFrame());
      expect(first.becameReady, isTrue);
      final second = machine.update(goodFrame());
      expect(second.canCapture, isTrue);
      expect(second.becameReady, isFalse);
    });

    test('turning red is faster than turning green', () {
      final machine = LiveCheckMachine();
      settle(machine, goodFrame());
      final afterOneBad = machine.update(goodFrame(motion: 0.2));
      // One bad frame is not yet enough...
      expect(
        afterOneBad.outcomes[LiveCheck.motion]!.status,
        CheckStatus.passing,
      );
      final afterTwoBad = machine.update(goodFrame(motion: 0.2));
      // ...but two are, where four were needed in the other direction.
      expect(
        afterTwoBad.outcomes[LiveCheck.motion]!.status,
        CheckStatus.failing,
      );
      expect(afterTwoBad.canCapture, isFalse);
    });

    test('a reset clears a stale green', () {
      final machine = LiveCheckMachine();
      expect(settle(machine, goodFrame()).canCapture, isTrue);
      machine.reset();
      expect(machine.update(goodFrame()).canCapture, isFalse);
    });
  });

  group('each check gates the shutter', () {
    test('clipped highlights block capture', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(clipped: 0.05));
      expect(state.canCapture, isFalse);
      expect(
        state.outcomes[LiveCheck.exposure]!.reason,
        LiveCheckReason.highlightsClipping,
      );
    });

    test('an unfocused frame blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(focusLocked: false));
      expect(
        state.outcomes[LiveCheck.sharpness]!.reason,
        LiveCheckReason.sharpnessLow,
      );
    });

    test('a low sharpness value blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(sharpness: 5));
      expect(
        state.outcomes[LiveCheck.sharpness]!.reason,
        LiveCheckReason.sharpnessLow,
      );
    });

    test('motion blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(motion: 0.2));
      expect(
        state.outcomes[LiveCheck.motion]!.reason,
        LiveCheckReason.motionHigh,
      );
    });

    test('an empty card slot blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(
        machine,
        goodFrame(card: verdict(median: const CameraRgb(0.01, 0.01, 0.01))),
      );
      expect(state.canCapture, isFalse);
      expect(
        state.outcomes[LiveCheck.grayCard]!.reason,
        LiveCheckReason.grayCardMissing,
      );
    });

    test('a non-uniform card slot blocks capture', () {
      final machine = LiveCheckMachine();
      final state =
          settle(machine, goodFrame(card: verdict(uniformityRatio: 0.2)));
      expect(
        state.outcomes[LiveCheck.grayCard]!.reason,
        LiveCheckReason.grayCardNonUniform,
      );
    });

    test('mixed lighting blocks capture', () {
      final machine = LiveCheckMachine();
      final mixed = [
        CameraRgb(card.red * 1.10, card.green, card.blue * 0.92),
        CameraRgb(card.red * 1.10, card.green, card.blue * 0.92),
        CameraRgb(card.red * 0.90, card.green, card.blue * 1.08),
        CameraRgb(card.red * 0.90, card.green, card.blue * 1.08),
      ];
      final state = settle(machine, goodFrame(card: verdict(quadrants: mixed)));
      expect(
        state.outcomes[LiveCheck.mixedLight]!.reason,
        LiveCheckReason.mixedLightDetected,
      );
    });

    test('an implausible light colour blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(
        machine,
        goodFrame(
          card: verdict(
            median: CameraRgb(card.red * 1.9, card.green, card.blue * 0.5),
          ),
        ),
      );
      expect(
        state.outcomes[LiveCheck.mixedLight]!.reason,
        LiveCheckReason.implausibleIlluminant,
      );
    });

    test('excessive tilt blocks capture', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(tilt: 12));
      expect(
        state.outcomes[LiveCheck.tilt]!.reason,
        LiveCheckReason.tiltHigh,
      );
    });

    test('an unknown tilt is not a pass', () {
      // A device with no usable motion sensor would otherwise get a free green
      // on the one check no amount of image analysis can recover.
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(tilt: null));
      expect(state.canCapture, isFalse);
      expect(
        state.outcomes[LiveCheck.tilt]!.reason,
        LiveCheckReason.tiltHigh,
      );
    });
  });

  group('diagnostics', () {
    test('every outcome carries the number behind the verdict', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame());
      expect(
        state.outcomes[LiveCheck.sharpness]!.measuredValue,
        closeTo(120, 1e-9),
      );
      expect(
        state.outcomes[LiveCheck.motion]!.measuredValue,
        closeTo(0.004, 1e-9),
      );
    });

    test('a failing check names only its own reason', () {
      final machine = LiveCheckMachine();
      final state = settle(machine, goodFrame(motion: 0.2));
      expect(state.failing, hasLength(1));
      expect(state.failing.single.check, LiveCheck.motion);
    });
  });
}
