import 'package:flutter/material.dart';
import 'package:nuans/core/l10n/clinical_strings.dart';
import 'package:nuans/core/theme/app_theme.dart';
import 'package:nuans/features/analysis/presentation/status_chip.dart';
import 'package:nuans/features/capture/application/live_check_machine.dart';
import 'package:nuans/features/capture/presentation/capture_overlay.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// The capture overlay, without a camera behind it.
///
/// Exists so the geometry and the traffic lights can be checked - and dragged -
/// on a real device without a calibrated profile, a grey card or a patient. The
/// camera preview itself needs all three, so a build that only showed the real
/// thing would show nothing at all on a first launch.
class OverlayPreviewScreen extends StatefulWidget {
  const OverlayPreviewScreen({super.key});

  @override
  State<OverlayPreviewScreen> createState() => _OverlayPreviewScreenState();
}

class _OverlayPreviewScreenState extends State<OverlayPreviewScreen> {
  CaptureOverlayModel _model = const CaptureOverlayModel();
  ToothRegion? _dragging;
  Offset? _focusPoint;

  /// Simulated check states, so the traffic lights can be seen in every state.
  final Map<LiveCheck, CheckStatus> _statuses = {
    LiveCheck.exposure: CheckStatus.passing,
    LiveCheck.grayCard: CheckStatus.failing,
    LiveCheck.sharpness: CheckStatus.passing,
    LiveCheck.motion: CheckStatus.passing,
    LiveCheck.mixedLight: CheckStatus.pending,
    LiveCheck.tilt: CheckStatus.passing,
  };

  bool get _ready => _statuses.values.every((s) => s == CheckStatus.passing);

  AppStatus _appStatus(CheckStatus status) => switch (status) {
        CheckStatus.passing => AppStatus.pass,
        CheckStatus.failing => AppStatus.fail,
        CheckStatus.pending => AppStatus.pending,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.capture(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(strings.cameraTitle),
            actions: [
              IconButton(
                tooltip: strings.checkGrayCard,
                icon: const Icon(Icons.flip),
                onPressed: () => setState(() {
                  _model = _model.copyWith(
                    cardSide: _model.cardSide == CardSide.right
                        ? CardSide.left
                        : CardSide.right,
                  );
                }),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    Offset normalise(Offset local) => Offset(
                          (local.dx / size.width).clamp(0.0, 1.0),
                          (local.dy / size.height).clamp(0.0, 1.0),
                        );
                    return GestureDetector(
                      onTapDown: (details) => setState(() {
                        _focusPoint = normalise(details.localPosition);
                      }),
                      onPanStart: (details) => setState(() {
                        _dragging =
                            _model.regionAt(normalise(details.localPosition));
                      }),
                      onPanUpdate: (details) {
                        final region = _dragging;
                        if (region == null) return;
                        setState(() {
                          final band = _model.bandRect(region);
                          final insets = List<double>.of(_model.bandInsets);
                          final delta = details.delta.dy / size.height;
                          insets[region.index] =
                              (insets[region.index] + delta / band.height)
                                  .clamp(-0.4, 0.4);
                          _model = _model.copyWith(bandInsets: insets);
                        });
                      },
                      onPanEnd: (_) => setState(() => _dragging = null),
                      child: ColoredBox(
                        color: CaptureOverlayTheme.screenBackground,
                        child: CustomPaint(
                          size: size,
                          painter: CaptureOverlayPainter(
                            model: _model,
                            statuses: {
                              for (final region in ToothRegion.values)
                                region: _ready,
                            },
                            theme: const CaptureOverlayTheme(),
                            activeRegion: _dragging,
                            focusPoint: _focusPoint,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _statuses.entries)
                          GestureDetector(
                            onTap: () => setState(() {
                              _statuses[entry.key] =
                                  entry.value == CheckStatus.passing
                                      ? CheckStatus.failing
                                      : CheckStatus.passing;
                            }),
                            child: StatusChip(
                              status: _appStatus(entry.value),
                              label: strings.liveCheck(entry.key),
                              dense: true,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // The shutter is a lock, not a warning: an unmeasurable
                    // frame costs the clinician's time twice if it is taken and
                    // then rejected.
                    FilledButton.icon(
                      onPressed: _ready ? () {} : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _ready ? strings.shutterReady : strings.shutterBlocked,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.clinicalTipHydration,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
