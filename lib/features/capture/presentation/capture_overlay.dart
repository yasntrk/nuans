import 'package:flutter/material.dart';
import 'package:shade_core/shade_core.dart';

/// Where the grey card sits relative to the tooth.
///
/// Switchable because a right-handed clinician holding a retractor cannot
/// always put the card on the same side, and forcing them to would be answered
/// by tilting the phone instead - which breaks the perpendicularity the
/// measurement depends on.
enum CardSide { left, right }

/// The geometry of the capture overlay, in fractions of the preview.
///
/// Everything is normalised so the same model drives the painter, the hit
/// testing and the regions sent to the native layer. A pixel anywhere in here
/// would have to be converted three times and would eventually disagree with
/// itself.
@immutable
class CaptureOverlayModel {
  const CaptureOverlayModel({
    this.toothRect = const Rect.fromLTWH(0.34, 0.26, 0.32, 0.48),
    this.cardSide = CardSide.right,
    this.showShadeTabSlot = true,
    this.bandInsets = const [0.0, 0.0, 0.0],
  });

  /// The tooth silhouette: the box the three bands are cut from.
  ///
  /// Centred by default, because lens shading is worst at the edges and the
  /// protocol requires both the tooth and the card to sit in the middle of the
  /// frame.
  final Rect toothRect;

  final CardSide cardSide;
  final bool showShadeTabSlot;

  /// Per-band vertical nudges the clinician has dragged, as fractions of the
  /// band height, in cervical, body, incisal order.
  final List<double> bandInsets;

  /// Share of the band's width the region of interest occupies.
  ///
  /// Protocol: the middle half of the width and three fifths of the height.
  /// Narrower than the band so the region never touches the gingival margin or
  /// the incisal edge, where the measurement would pick up gum or background.
  static const double regionWidthFraction = 0.50;
  static const double regionHeightFraction = 0.60;

  /// The three bands, top to bottom.
  Rect bandRect(ToothRegion region) {
    final height = toothRect.height / 3;
    final index = region.index;
    final top = toothRect.top + height * index;
    return Rect.fromLTWH(toothRect.left, top, toothRect.width, height);
  }

  /// The measured region inside a band, after any drag.
  Rect regionRect(ToothRegion region) {
    final band = bandRect(region);
    final width = band.width * regionWidthFraction;
    final height = band.height * regionHeightFraction;
    final inset = bandInsets[region.index] * band.height;
    final top = (band.top + (band.height - height) / 2 + inset)
        .clamp(band.top, band.bottom - height);
    return Rect.fromLTWH(
      band.left + (band.width - width) / 2,
      top,
      width,
      height,
    );
  }

  /// The grey card slot, beside the tooth on [cardSide].
  Rect get cardRect {
    const width = 0.17;
    final height = toothRect.height * 0.42;
    final left = cardSide == CardSide.right
        ? (toothRect.right + 0.04).clamp(0.0, 1.0 - width)
        : (toothRect.left - 0.04 - width).clamp(0.0, 1.0 - width);
    return Rect.fromLTWH(
      left,
      toothRect.top + toothRect.height * 0.08,
      width,
      height,
    );
  }

  /// The shade tab slot, on the opposite side from the card.
  Rect get shadeTabRect {
    const width = 0.15;
    final height = toothRect.height * 0.42;
    final left = cardSide == CardSide.right
        ? (toothRect.left - 0.04 - width).clamp(0.0, 1.0 - width)
        : (toothRect.right + 0.04).clamp(0.0, 1.0 - width);
    return Rect.fromLTWH(
      left,
      toothRect.top + toothRect.height * 0.50,
      width,
      height,
    );
  }

  CaptureOverlayModel copyWith({
    Rect? toothRect,
    CardSide? cardSide,
    bool? showShadeTabSlot,
    List<double>? bandInsets,
  }) =>
      CaptureOverlayModel(
        toothRect: toothRect ?? this.toothRect,
        cardSide: cardSide ?? this.cardSide,
        showShadeTabSlot: showShadeTabSlot ?? this.showShadeTabSlot,
        bandInsets: bandInsets ?? this.bandInsets,
      );

  /// Which region's handle a normalised point is on, or `null`.
  ToothRegion? regionAt(Offset point) {
    for (final region in ToothRegion.values) {
      if (regionRect(region).inflate(0.02).contains(point)) return region;
    }
    return null;
  }
}

/// Draws the capture overlay.
///
/// Deliberately monochrome apart from the traffic lights. The screen is the
/// second-brightest thing in front of the patient, so any colour on it reflects
/// off the tooth and into the measurement, and any large bright area pushes the
/// clinician's own chromatic adaptation around while they are judging a shade.
/// So: a neutral dark grey ground, light grey lines, and colour used only where
/// a red or green decision has to be unmissable.
class CaptureOverlayPainter extends CustomPainter {
  const CaptureOverlayPainter({
    required this.model,
    required this.statuses,
    required this.theme,
    this.activeRegion,
    this.focusPoint,
  });

  final CaptureOverlayModel model;

  /// Per-region pass state, used only to tint the region outlines.
  final Map<ToothRegion, bool> statuses;

  final CaptureOverlayTheme theme;

  /// The region being dragged, drawn with a thicker outline.
  final ToothRegion? activeRegion;

  /// Where the clinician last tapped to focus, in normalised coordinates.
  final Offset? focusPoint;

  @override
  void paint(Canvas canvas, Size size) {
    Rect scale(Rect r) => Rect.fromLTWH(
          r.left * size.width,
          r.top * size.height,
          r.width * size.width,
          r.height * size.height,
        );

    _paintVignette(canvas, size, scale(model.toothRect));
    _paintToothSilhouette(canvas, scale(model.toothRect));
    _paintBands(canvas, size, scale);
    _paintSlot(canvas, scale(model.cardRect), theme.cardSlotColor);
    if (model.showShadeTabSlot) {
      _paintSlot(canvas, scale(model.shadeTabRect), theme.tabSlotColor);
    }
    _paintCentreMarks(canvas, size);
    if (focusPoint != null) {
      _paintFocusRing(
        canvas,
        Offset(focusPoint!.dx * size.width, focusPoint!.dy * size.height),
      );
    }
  }

  /// Dims everything outside the working area.
  ///
  /// Not decoration: it is the distance and framing guide. The tooth has to
  /// fill the silhouette, and a dimmed surround makes "too far away" obvious
  /// without a number.
  void _paintVignette(Canvas canvas, Size size, Rect tooth) {
    final outside = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          tooth.inflate(size.shortestSide * 0.06),
          Radius.circular(size.shortestSide * 0.08),
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = theme.vignetteColor);
  }

  void _paintToothSilhouette(Canvas canvas, Rect tooth) {
    // A central incisor: straight sides, a rounded cervical shoulder and a
    // nearly flat incisal edge.
    final path = Path()
      ..moveTo(tooth.left, tooth.top + tooth.height * 0.14)
      ..quadraticBezierTo(
        tooth.left + tooth.width * 0.10,
        tooth.top,
        tooth.center.dx,
        tooth.top,
      )
      ..quadraticBezierTo(
        tooth.right - tooth.width * 0.10,
        tooth.top,
        tooth.right,
        tooth.top + tooth.height * 0.14,
      )
      ..lineTo(
        tooth.right - tooth.width * 0.02,
        tooth.bottom - tooth.height * 0.06,
      )
      ..quadraticBezierTo(
        tooth.center.dx,
        tooth.bottom,
        tooth.left + tooth.width * 0.02,
        tooth.bottom - tooth.height * 0.06,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.silhouetteStrokeWidth
        ..color = theme.silhouetteColor,
    );
  }

  void _paintBands(Canvas canvas, Size size, Rect Function(Rect) scale) {
    for (final region in ToothRegion.values) {
      final band = scale(model.bandRect(region));
      // Band divider, drawn only between bands.
      if (region != ToothRegion.cervical) {
        canvas.drawLine(
          Offset(band.left, band.top),
          Offset(band.right, band.top),
          Paint()
            ..color = theme.bandDividerColor
            ..strokeWidth = 1,
        );
      }
      final region2 = scale(model.regionRect(region));
      final passing = statuses[region] ?? false;
      final isActive = activeRegion == region;
      canvas.drawRect(
        region2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              isActive ? theme.regionStrokeWidth * 2 : theme.regionStrokeWidth
          ..color = passing ? theme.regionPassColor : theme.regionIdleColor,
      );
      // Drag handles, top and bottom centre.
      for (final handle in [
        Offset(region2.center.dx, region2.top),
        Offset(region2.center.dx, region2.bottom),
      ]) {
        canvas.drawCircle(
          handle,
          theme.handleRadius,
          Paint()..color = theme.handleColor,
        );
      }
    }
  }

  void _paintSlot(Canvas canvas, Rect slot, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = theme.regionStrokeWidth
      ..color = color;
    // Dashed, so a slot is never mistaken for a measured region.
    const dash = 8.0;
    const gap = 6.0;
    for (final edge in [
      [slot.topLeft, slot.topRight],
      [slot.bottomLeft, slot.bottomRight],
      [slot.topLeft, slot.bottomLeft],
      [slot.topRight, slot.bottomRight],
    ]) {
      final start = edge[0];
      final end = edge[1];
      final total = (end - start).distance;
      final direction = (end - start) / total;
      var travelled = 0.0;
      while (travelled < total) {
        final segmentEnd = (travelled + dash).clamp(0.0, total);
        canvas.drawLine(
          start + direction * travelled,
          start + direction * segmentEnd,
          paint,
        );
        travelled = segmentEnd + gap;
      }
    }
  }

  /// Short marks at the frame centre.
  ///
  /// The protocol keeps the tooth and the card in the middle of the frame
  /// because lens shading grows towards the corners; these make the centre
  /// visible so the clinician can aim rather than guess.
  void _paintCentreMarks(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = theme.centreMarkColor
      ..strokeWidth = 1;
    const arm = 10.0;
    canvas
      ..drawLine(centre.translate(-arm, 0), centre.translate(arm, 0), paint)
      ..drawLine(centre.translate(0, -arm), centre.translate(0, arm), paint);
  }

  void _paintFocusRing(Canvas canvas, Offset centre) {
    canvas.drawCircle(
      centre,
      theme.focusRingRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = theme.focusRingColor,
    );
  }

  @override
  bool shouldRepaint(CaptureOverlayPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.activeRegion != activeRegion ||
      oldDelegate.focusPoint != focusPoint ||
      !_sameStatuses(oldDelegate.statuses);

  bool _sameStatuses(Map<ToothRegion, bool> other) {
    for (final region in ToothRegion.values) {
      if (statuses[region] != other[region]) return false;
    }
    return true;
  }
}

/// Colours and metrics of the overlay.
///
/// A separate object so the camera screen's palette is stated in one place and
/// a golden test can pin it. The values are deliberately desaturated: a
/// coloured overlay reflects off the tooth.
@immutable
class CaptureOverlayTheme {
  const CaptureOverlayTheme({
    this.vignetteColor = const Color(0xCC121212),
    this.silhouetteColor = const Color(0xFFBDBDBD),
    this.bandDividerColor = const Color(0x66BDBDBD),
    this.regionIdleColor = const Color(0xFF9E9E9E),
    this.regionPassColor = const Color(0xFF4CAF50),
    this.cardSlotColor = const Color(0xFFE0E0E0),
    this.tabSlotColor = const Color(0xFF9E9E9E),
    this.handleColor = const Color(0xFFE0E0E0),
    this.centreMarkColor = const Color(0x8899AAB7),
    this.focusRingColor = const Color(0xFFE0E0E0),
    this.silhouetteStrokeWidth = 2,
    this.regionStrokeWidth = 1.5,
    this.handleRadius = 5,
    this.focusRingRadius = 28,
  });

  /// The neutral dark grey the whole camera screen sits on.
  static const Color screenBackground = Color(0xFF121212);

  final Color vignetteColor;
  final Color silhouetteColor;
  final Color bandDividerColor;
  final Color regionIdleColor;
  final Color regionPassColor;
  final Color cardSlotColor;
  final Color tabSlotColor;
  final Color handleColor;
  final Color centreMarkColor;
  final Color focusRingColor;
  final double silhouetteStrokeWidth;
  final double regionStrokeWidth;
  final double handleRadius;
  final double focusRingRadius;
}
