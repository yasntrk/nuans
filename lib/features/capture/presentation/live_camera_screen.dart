import 'package:flutter/material.dart';
import 'package:nuans/core/l10n/camera_error_strings.dart';
import 'package:nuans/core/theme/app_theme.dart';
// ToothRegion is hidden: the contract has an enum of that name for the
// native boundary, and the overlay painter takes shade_core's own.
import 'package:nuans/data/platform/shade_camera_api.g.dart' hide ToothRegion;
import 'package:nuans/features/capture/application/live_preview_controller.dart';
import 'package:nuans/features/capture/application/preview_geometry.dart';
import 'package:nuans/features/capture/presentation/capture_overlay.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// The real camera, with the capture overlay on top of it.
///
/// What this screen deliberately does not do is offer a shutter. Without a
/// device profile there is no matrix to turn camera values into colour, so a
/// capture taken here could be displayed but not believed. The preview and the
/// alignment are useful on their own - they are what a clinician needs to learn
/// where to hold the phone - and the measurements shown below it are the ones
/// that need no profile to be meaningful.
class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key, this.controller});

  /// Injected by tests, which have no camera to open.
  ///
  /// The screen takes ownership either way: it is what starts and stops the
  /// preview, so it is what has to stop it when it goes away. An injected
  /// controller left running would keep a camera open behind a screen that is
  /// no longer there.
  final LivePreviewController? controller;

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  late final LivePreviewController _controller;

  /// Fixed on this screen. Dragging the regions belongs to the overlay
  /// workbench, where there is no camera to reconfigure on every frame.
  final CaptureOverlayModel _model = const CaptureOverlayModel();
  Offset? _focusPoint;

  /// The protocol's metrics interval and clipping threshold.
  ///
  /// The interval is the contract's documented value; the threshold is the
  /// specification's tau_clip, above which a channel counts as clipped.
  static const _metricsIntervalMillis = 100;
  static const _clippingThreshold = 0.95;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? LivePreviewController();
    _controller
      ..addListener(_onControllerChanged)
      ..start((geometry) => _configFor(_model, geometry));
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Builds the platform configuration for the current overlay.
  ///
  /// The overlay's rectangles are where the clinician put them on screen; the
  /// platform needs them in the frame's own coordinates, which is what
  /// [PreviewGeometry.toFrame] is for. [geometry] is null on the first call,
  /// before the preview has reported its shape; the controller calls this
  /// again with the shape once it knows it.
  PreviewConfig _configFor(
    CaptureOverlayModel model,
    PreviewGeometry? geometry,
  ) {
    NormalizedRect rect(Rect display) {
      final mapped = geometry?.toFrame(display) ?? display;
      return NormalizedRect(
        left: mapped.left,
        top: mapped.top,
        width: mapped.width,
        height: mapped.height,
      );
    }

    return PreviewConfig(
      metricsIntervalMillis: _metricsIntervalMillis,
      toothRect: rect(model.toothRect),
      grayCardRect: rect(model.cardRect),
      clippingThreshold: _clippingThreshold,
      shadeTabRect: model.showShadeTabSlot ? rect(model.shadeTabRect) : null,
    );
  }

  @override
  void dispose() {
    // Not awaited: dispose cannot be asynchronous, and the platform frees the
    // device when the engine detaches even if this does not land.
    _controller
      ..removeListener(_onControllerChanged)
      ..stop()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.capture(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(strings.liveCameraTitle)),
          body: switch (_controller.stage) {
            LivePreviewStage.idle ||
            LivePreviewStage.starting =>
              _Starting(message: strings.liveCameraStarting),
            LivePreviewStage.failed => _Failed(
                message: cameraErrorMessage(
                  strings,
                  _controller.errorCode ?? CameraErrorCode.configurationFailed,
                ),
                hint: _controller.errorCode == CameraErrorCode.permissionDenied
                    ? strings.liveCameraPermissionBody
                    : null,
                actionLabel: strings.liveCameraRetry,
                onRetry: () => _controller.start(
                  (geometry) => _configFor(_model, geometry),
                ),
              ),
            LivePreviewStage.running => _Running(
                controller: _controller,
                model: _model,
                focusPoint: _focusPoint,
                onTap: _handleTap,
              ),
          },
        ),
      ),
    );
  }

  void _handleTap(Offset normalised) {
    setState(() => _focusPoint = normalised);
    final geometry = _controller.geometry;
    // The platform focuses at a point in the frame, not on the screen.
    final inFrame = geometry == null
        ? normalised
        : geometry
            .toFrame(Rect.fromLTWH(normalised.dx, normalised.dy, 0, 0))
            .topLeft;
    _controller.focusAt(inFrame.dx, inFrame.dy);
  }
}

class _Starting extends StatelessWidget {
  const _Starting({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
    this.hint,
  });

  final String message;
  final String? hint;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              message,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 12),
              Text(
                hint!,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({
    required this.controller,
    required this.model,
    required this.onTap,
    this.focusPoint,
  });

  final LivePreviewController controller;
  final CaptureOverlayModel model;
  final Offset? focusPoint;
  final void Function(Offset normalised) onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = controller.session;
    final geometry = controller.geometry;
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: CaptureOverlayTheme.screenBackground,
            child: Center(
              child: AspectRatio(
                aspectRatio: geometry?.displayAspectRatio ?? 3 / 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      onTapDown: (details) => onTap(
                        Offset(
                          (details.localPosition.dx / size.width)
                              .clamp(0.0, 1.0),
                          (details.localPosition.dy / size.height)
                              .clamp(0.0, 1.0),
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (session != null)
                            // RotatedBox turns the child and swaps its
                            // constraints, which is what a frame written in
                            // the sensor's orientation needs.
                            RotatedBox(
                              quarterTurns: geometry?.quarterTurns ?? 0,
                              child: Texture(textureId: session.textureId),
                            ),
                          CustomPaint(
                            painter: CaptureOverlayPainter(
                              model: model,
                              statuses: {
                                for (final region in ToothRegion.values)
                                  region: false,
                              },
                              theme: const CaptureOverlayTheme(),
                              focusPoint: focusPoint,
                            ),
                          ),
                          if (controller.isStarved)
                            Center(
                              child: _Notice(strings.liveCameraNoFrames),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        _MetricsPanel(metrics: controller.metrics),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}

/// The measurements that mean something without a device profile.
///
/// Sharpness, motion, clipping and the card's spatial uniformity are all
/// geometric or photometric readings of one channel; none of them needs a
/// colour transform. The colour judgements - mixed lighting, the illuminant's
/// plausibility, the shade itself - do, which is why they are named as missing
/// rather than shown as grey.
class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({this.metrics});

  final PreviewMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final live = metrics;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.liveCameraUncalibrated,
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Text(strings.liveMetricsTitle, style: textTheme.labelLarge),
          const SizedBox(height: 6),
          if (live == null)
            Text(strings.checkPending, style: textTheme.bodySmall)
          else
            Table(
              columnWidths: const {1: IntrinsicColumnWidth()},
              children: [
                _row(
                  textTheme,
                  strings.liveMetricSharpness,
                  live.toothSharpness.toStringAsFixed(1),
                ),
                _row(
                  textTheme,
                  strings.liveMetricMotion,
                  live.motionScore.toStringAsFixed(3),
                ),
                _row(
                  textTheme,
                  strings.liveMetricToothClipping,
                  '${(live.toothClippedFraction * 100).toStringAsFixed(1)}%',
                ),
                _row(
                  textTheme,
                  strings.liveMetricCardUniformity,
                  live.grayCardTextureRatio.toStringAsFixed(3),
                ),
                _row(textTheme, strings.liveMetricIso, '${live.iso}'),
                _row(
                  textTheme,
                  strings.liveMetricExposure,
                  '${(live.exposureSeconds * 1000).toStringAsFixed(1)} ms',
                ),
                _row(
                  textTheme,
                  strings.checkMixedLight,
                  strings.liveMetricNeedsProfile,
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            strings.shutterBlocked,
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  TableRow _row(TextTheme textTheme, String label, String value) => TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(label, style: textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              value,
              style: textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
}
