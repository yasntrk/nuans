/// The colour engine of Nuans: CIE colorimetry, camera calibration, robust
/// region statistics and shade matching.
///
/// Pure Dart. No Flutter, no file system, no clock, no randomness, no
/// user-facing text. Every function is deterministic, so the same input always
/// produces the same output and the whole package is unit testable.
///
/// Specification: `docs/architecture/02-algorithms.md`.
library;

export 'src/calibration/ccm_fit.dart';
export 'src/calibration/color_correction_matrix.dart';
export 'src/calibration/device_profile.dart';
export 'src/calibration/gray_card.dart';
export 'src/calibration/gray_card_validator.dart';
export 'src/capture/camera_rgb.dart';
export 'src/capture/roi_sample_set.dart';
export 'src/colorimetry/chromatic_adaptation.dart';
export 'src/colorimetry/correlated_color_temperature.dart';
export 'src/colorimetry/delta_e_2000.dart';
export 'src/colorimetry/lab_color.dart';
export 'src/colorimetry/mat3.dart';
export 'src/colorimetry/srgb.dart';
export 'src/colorimetry/vec3.dart';
export 'src/colorimetry/white_point.dart';
export 'src/colorimetry/xyz_color.dart';
export 'src/confidence/confidence_score.dart';
export 'src/constants.dart';
export 'src/model/tooth_region.dart';
export 'src/statistics/robust_stats.dart';
export 'src/statistics/roi_reducer.dart';
