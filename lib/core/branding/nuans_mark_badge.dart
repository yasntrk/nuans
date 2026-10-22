import 'package:flutter/material.dart';
import 'package:nuans/core/branding/nuans_mark.dart';

/// The Nüans mark as a small badge, for use inside the application.
///
/// It carries its own ground rather than drawing straight onto the surface it
/// sits on. Two reasons, and the first is not decorative: the tabs are pale
/// warm tones chosen for the icon's dark ground, and on the clinical theme's
/// light surface they would all but disappear. The second is that a badge
/// reads as the application's own mark, where loose tabs would read as an
/// illustration of something.
///
/// Not for the capture screen. That screen is the second-brightest thing in
/// front of the patient and its surfaces are kept at zero saturation on
/// purpose; a warm mark on it would reflect off the tooth and into the
/// reading. The same rule that picked its grey theme keeps the badge out.
class NuansMarkBadge extends StatelessWidget {
  const NuansMarkBadge({super.key, this.size = 28});

  /// The badge's side, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Decorative: the application's name is already beside it, so announcing
    // the badge as well would say the same thing twice.
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _BadgePainter()),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter();

  /// Corner radius as a fraction of the side, matching the squircle most
  /// launchers mask an adaptive icon into.
  static const double _corner = 0.24;

  /// How much of the badge the mark fills.
  ///
  /// Larger than the adaptive icon's share, because nothing is going to mask
  /// this one: the rounded square is the whole of it.
  static const double _inset = 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.shortestSide * _corner),
        ),
      );
    NuansMark.paint(canvas, size, inset: _inset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) => false;
}
