import 'package:flutter/widgets.dart';
import 'package:nuans/features/capture/application/live_check_machine.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// Turns the machine codes of `shade_core` and the capture layer into localised
/// text.
///
/// This is the only place in the application where an enum from the colour
/// engine meets a sentence. The engine deliberately produces no text at all, so
/// without a mapping like this a screen would be tempted to write
/// `'${region.name}'` and ship an English identifier to a Turkish clinician.
/// Having one file means a new enum value fails to compile here rather than
/// appearing untranslated on screen.
extension ClinicalStrings on AppLocalizations {
  String toothRegion(ToothRegion region) => switch (region) {
        ToothRegion.cervical => regionCervical,
        ToothRegion.body => regionBody,
        ToothRegion.incisal => regionIncisal,
      };

  String material(RestorativeMaterial material) => switch (material) {
        RestorativeMaterial.zirconia => materialZirconia,
        RestorativeMaterial.metalCeramic => materialMetalCeramic,
        RestorativeMaterial.composite => materialComposite,
      };

  String shadeSystem(ShadeSystem system) => switch (system) {
        ShadeSystem.classicalCompatible => shadeSystemClassical,
        ShadeSystem.threeDimensionalMasterCompatible => shadeSystemMaster,
      };

  String acceptabilityBand(AcceptabilityBand band) => switch (band) {
        AcceptabilityBand.imperceptible => bandImperceptible,
        AcceptabilityBand.acceptable => bandAcceptable,
        AcceptabilityBand.unacceptable => bandUnacceptable,
      };

  String acceptabilityExplained(AcceptabilityBand band) => switch (band) {
        AcceptabilityBand.imperceptible => bandImperceptibleExplained,
        AcceptabilityBand.acceptable => bandAcceptableExplained,
        AcceptabilityBand.unacceptable => bandUnacceptableExplained,
      };

  String confidenceBand(ConfidenceBand band) => switch (band) {
        ConfidenceBand.high => confidenceHigh,
        ConfidenceBand.medium => confidenceMedium,
        ConfidenceBand.low => confidenceLow,
      };

  /// Confidence term names, keyed by the machine name the scorer emits.
  String confidenceTerm(String name) => switch (name) {
        'captureMode' => termCaptureMode,
        'deviceProfile' => termDeviceProfile,
        'grayCard' => termGrayCard,
        'rejectedFraction' => termRejectedFraction,
        'regionHomogeneity' => termRegionHomogeneity,
        'relativeMode' => termRelativeMode,
        'matchResidual' => termMatchResidual,
        // A term added to the scorer without a string here must be visible, not
        // silently blank.
        _ => name,
      };

  String confidenceOverride(ConfidenceOverride reason) => switch (reason) {
        ConfidenceOverride.noColorProfile => overrideNoColorProfile,
        ConfidenceOverride.grayCardInvalid => overrideGrayCardInvalid,
        ConfidenceOverride.excessiveRejection => overrideExcessiveRejection,
        ConfidenceOverride.tooFewSamples => overrideTooFewSamples,
        ConfidenceOverride.noAcceptedFrames => overrideNoAcceptedFrames,
      };

  String liveCheck(LiveCheck check) => switch (check) {
        LiveCheck.exposure => checkExposure,
        LiveCheck.grayCard => checkGrayCard,
        LiveCheck.sharpness => checkSharpness,
        LiveCheck.motion => checkMotion,
        LiveCheck.mixedLight => checkMixedLight,
        LiveCheck.tilt => checkTilt,
      };

  /// The reason a check is failing, with its measured value where the message
  /// takes one.
  String liveCheckReason(LiveCheckReason reason, {double? value}) =>
      switch (reason) {
        LiveCheckReason.highlightsClipping => checkExposureClipping,
        LiveCheckReason.tooDark => checkExposureTooDark,
        LiveCheckReason.grayCardMissing => checkGrayCardNotFound,
        LiveCheckReason.grayCardNonUniform => checkGrayCardNonUniform,
        LiveCheckReason.mixedLightDetected => checkMixedLightDetected,
        LiveCheckReason.implausibleIlluminant =>
          checkImplausibleLight((value ?? 0).round()),
        LiveCheckReason.sharpnessLow => checkSharpnessLow,
        LiveCheckReason.motionHigh => checkMotionHigh,
        LiveCheckReason.tiltHigh => checkTiltHigh(value ?? 0),
      };

  String gradientNote(GradientNote note) => switch (note) {
        GradientNote.cervicalMoreChromatic => gradientCervicalMoreChromatic,
        GradientNote.incisalLighter => gradientIncisalLighter,
        GradientNote.incisalMoreTranslucent => gradientIncisalMoreTranslucent,
        GradientNote.uniform => gradientUniform,
      };

  String enamelKind(EnamelKind kind) => switch (kind) {
        EnamelKind.matchingShade => enamelMatchingShade,
        EnamelKind.universal => enamelUniversal,
        EnamelKind.translucent => enamelTranslucent,
        EnamelKind.opalescent => enamelOpalescent,
        EnamelKind.bleach => enamelBleach,
      };

  String ceramicLayerRole(CeramicLayerRole role) => switch (role) {
        CeramicLayerRole.opaque => layerOpaque,
        CeramicLayerRole.dentin => layerDentin,
        CeramicLayerRole.incisal => layerIncisal,
      };

  /// One deviation, as a phrase.
  ///
  /// The magnitude goes in as an ICU select argument rather than being picked
  /// here, so Turkish and English can put the intensifier where their own
  /// grammar wants it.
  String shadeDeviation(ShadeDeviation deviation) {
    final magnitude = deviation.magnitude.name;
    return switch (deviation.direction) {
      ShadeDeviationDirection.lighter => deviationLighter(magnitude),
      ShadeDeviationDirection.darker => deviationDarker(magnitude),
      ShadeDeviationDirection.moreChromatic =>
        deviationMoreChromatic(magnitude),
      ShadeDeviationDirection.lessChromatic =>
        deviationLessChromatic(magnitude),
      ShadeDeviationDirection.towardRed => deviationTowardRed(magnitude),
      ShadeDeviationDirection.towardYellow => deviationTowardYellow(magnitude),
      ShadeDeviationDirection.towardGreen => deviationTowardGreen(magnitude),
      ShadeDeviationDirection.towardBlue => deviationTowardBlue(magnitude),
    };
  }

  /// The whole comparison, as one sentence.
  ///
  /// There is a separate ARB message per number of clauses rather than a joined
  /// list, because joining fragments in Dart is how a sentence ends up with
  /// English word order in Turkish. Three clauses is the maximum, since
  /// CIEDE2000 has exactly three components.
  String shadeComparison(ShadeMatch match) {
    final notable = match.notableDeviations;
    final phrases = notable.map(shadeDeviation).toList();
    return switch (phrases.length) {
      0 => comparisonNone(match.entry.code),
      1 => comparisonOne(match.entry.code, phrases[0]),
      2 => comparisonTwo(match.entry.code, phrases[0], phrases[1]),
      _ => comparisonThree(
          match.entry.code,
          phrases[0],
          phrases[1],
          phrases[2],
        ),
    };
  }

  /// A ceramic layer's composition.
  String ceramicLayerComposition(CeramicLayer layer) {
    final parts = layer.components;
    return switch (parts.length) {
      1 => layerSingleShade(parts[0].entry.code),
      2 => layerMixTwo(
          parts[0].entry.code,
          parts[0].percent,
          parts[1].entry.code,
          parts[1].percent,
        ),
      _ => layerMixThree(
          parts[0].entry.code,
          parts[0].percent,
          parts[1].entry.code,
          parts[1].percent,
          parts[2].entry.code,
          parts[2].percent,
        ),
    };
  }

  /// Why no mixture is offered.
  String mixDeclined(MixRejectionReason reason) => switch (reason) {
        MixRejectionReason.singleShadeAlreadyGoodEnough =>
          mixDeclinedGoodEnough,
        MixRejectionReason.noWorthwhileImprovement => mixDeclinedNoGain,
        MixRejectionReason.noStructuralNeighbours => mixDeclinedNoNeighbours,
      };

  /// A device limitation code reported by the native layer.
  String deviceLimitation(String code) => switch (code) {
        'noManualSensor' => limitationNoManualSensor,
        'noRawSupport' => limitationNoRawSupport,
        'whiteBalanceNotLockable' => limitationWhiteBalanceNotLockable,
        'focusNotLockable' => limitationFocusNotLockable,
        'logicalMultiCamera' => limitationLogicalMultiCamera,
        'exposureNotSolvable' => limitationExposureNotSolvable,
        _ => code,
      };
}

/// Resolves the localisations for an arbitrary locale, outside a widget tree.
///
/// Needed because the report language is chosen independently of the interface
/// language: a Turkish-speaking clinician sends an English report to a
/// laboratory abroad. The report builder therefore cannot take its strings from
/// the ambient `BuildContext`.
Future<AppLocalizations> localizationsFor(Locale locale) =>
    AppLocalizations.delegate.load(locale);
