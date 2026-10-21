import 'package:shade_core/src/constants.dart';

/// Correlated colour temperature from chromaticity, using McCamy's (1992)
/// cubic approximation.
///
/// Used only as a plausibility check on the capture light. The approximation is
/// valid between roughly 2856 K and 6504 K; outside that range the result is
/// reported as out of range and drives a warning rather than a number, because
/// a figure nobody should trust must not be shown as if it were a measurement.
abstract final class CorrelatedColorTemperature {
  /// McCamy's estimate in kelvin, or `null` when the chromaticity sits on the
  /// pole of the approximation.
  static double? mcCamy({required double x, required double y}) {
    final denominator = kMcCamyPivotY - y;
    if (denominator.abs() < 1e-9) return null;
    final n = (x - kMcCamyPivotX) / denominator;
    return kMcCamyC3 * n * n * n +
        kMcCamyC2 * n * n +
        kMcCamyC1 * n +
        kMcCamyC0;
  }

  /// Whether a McCamy estimate falls inside the range the approximation covers.
  static bool isWithinApproximationRange(double kelvin) =>
      kelvin >= kMcCamyValidMinKelvin && kelvin <= kMcCamyValidMaxKelvin;

  /// Whether the light is plausible for this capture protocol.
  static bool isPlausibleCaptureIlluminant(double kelvin) =>
      kelvin >= kIlluminantCctMin && kelvin <= kIlluminantCctMax;
}
