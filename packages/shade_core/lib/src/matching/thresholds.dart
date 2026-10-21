import 'package:meta/meta.dart';

import 'package:shade_core/src/constants.dart';

/// Clinical bands for a colour difference.
enum AcceptabilityBand {
  /// At or below the 50:50 perceptibility threshold.
  imperceptible,

  /// Perceptible but clinically acceptable.
  acceptable,

  /// Beyond the 50:50 acceptability threshold.
  unacceptable,
}

/// The two published thresholds, as adjustable constants.
///
/// Source: ISO/TR 28642 together with Paravina et al. (2015), 50:50
/// perceptibility and acceptability. They are adjustable because a clinic may
/// want to tighten them, not because the published values are in doubt.
@immutable
final class AcceptabilityThresholds {
  const AcceptabilityThresholds({
    this.imperceptible = kImperceptibleDeltaE,
    this.acceptable = kAcceptableDeltaE,
  });

  final double imperceptible;
  final double acceptable;

  AcceptabilityBand classify(double deltaE2000) {
    if (deltaE2000 <= imperceptible) return AcceptabilityBand.imperceptible;
    if (deltaE2000 <= acceptable) return AcceptabilityBand.acceptable;
    return AcceptabilityBand.unacceptable;
  }
}

/// How large a single weighted deviation component is.
enum ComponentMagnitude {
  /// Not worth mentioning to the user.
  negligible,
  slight,
  moderate,
  pronounced,
}

/// Bands for describing one weighted component.
///
/// The thresholds are in CIEDE2000 units, because the weighted components are
/// already divided by their `S` terms. That puts the 0.8 perceptibility
/// threshold inside the `slight` band, where it belongs.
@immutable
final class ComponentWordingThresholds {
  const ComponentWordingThresholds({
    this.slight = kComponentSlightThreshold,
    this.moderate = kComponentModerateThreshold,
    this.pronounced = kComponentPronouncedThreshold,
  });

  final double slight;
  final double moderate;
  final double pronounced;

  ComponentMagnitude classify(double weightedValue) {
    final magnitude = weightedValue.abs();
    if (magnitude < slight) return ComponentMagnitude.negligible;
    if (magnitude < moderate) return ComponentMagnitude.slight;
    if (magnitude < pronounced) return ComponentMagnitude.moderate;
    return ComponentMagnitude.pronounced;
  }
}
