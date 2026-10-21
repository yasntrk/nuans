import 'package:meta/meta.dart';
import 'package:shade_core/src/calibration/ccm_fit.dart';
import 'package:shade_core/src/calibration/color_correction_matrix.dart';
import 'package:shade_core/src/colorimetry/mat3.dart';
import 'package:shade_core/src/colorimetry/white_point.dart';

/// A calibration bound to one device and one lens.
///
/// Profiles are per lens, not per device: the same phone's wide and ultra-wide
/// modules have different spectral responses, which is one reason the capture
/// protocol only ever uses the main 1x rear lens.
@immutable
final class DeviceProfile {
  const DeviceProfile({
    required this.deviceModel,
    required this.lensId,
    required this.ccm,
    required this.createdAtUtc,
    this.quality,
    this.grayCardReflectanceY,
  });

  /// A profile built from the manufacturer's RAW metadata rather than from a
  /// chart shot on this unit.
  factory DeviceProfile.fromDngMatrix({
    required String deviceModel,
    required String lensId,
    required Mat3 cameraToXyz,
    required DateTime createdAtUtc,
    required bool isForwardMatrix,
    WhitePoint whitePoint = WhitePoint.d65,
  }) =>
      DeviceProfile(
        deviceModel: deviceModel,
        lensId: lensId,
        ccm: ColorCorrectionMatrix(
          matrix: cameraToXyz,
          whitePoint: whitePoint,
          source: isForwardMatrix
              ? CcmSource.dngForwardMatrix
              : CcmSource.dngColorMatrixInverse,
        ),
        createdAtUtc: createdAtUtc,
      );

  final String deviceModel;
  final String lensId;
  final ColorCorrectionMatrix ccm;

  /// Always UTC. The display layer formats it in the user's locale.
  final DateTime createdAtUtc;

  /// Present only for a chart fit.
  final CcmQualityReport? quality;

  /// The measured luminance factor of the physical card this clinic uses, when
  /// it has been read from the card's data sheet.
  final double? grayCardReflectanceY;

  /// Key under which a profile is stored and looked up.
  String get key => '$deviceModel/$lensId';

  bool get isChartFitted => ccm.source == CcmSource.chartFit;

  /// The profile term of the confidence score.
  ///
  /// A manufacturer matrix is a single-sample average that carries no
  /// unit-to-unit variation, so it is worth markedly less than a chart fit on
  /// this very device, but much more than nothing.
  double get confidenceScore => switch (ccm.source) {
        CcmSource.chartFit => quality?.score ?? 0,
        CcmSource.dngForwardMatrix => 0.3,
        CcmSource.dngColorMatrixInverse => 0.3,
        CcmSource.srgbProcessed => 0,
      };

  @override
  String toString() => 'DeviceProfile($key, ${ccm.source.name})';
}
