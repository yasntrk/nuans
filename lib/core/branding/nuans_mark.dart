import 'dart:ui';

/// The Nüans mark: three shade tabs on a holder.
///
/// A shade guide is the object this application stands in for, so it is what
/// the mark shows. The three tabs carry almost the same warm tone, a little
/// apart and no more, because telling those apart is the product. *Nüans.*
///
/// The middle tab is the tallest. Not for rhythm: the body third is the one a
/// single-shade match is normally read from, which is written into
/// `ToothRegion.body` and is the reason the middle of a tooth is where the eye
/// should go.
///
/// What the mark deliberately is not: a camera, which would say "photo app",
/// or a colour wheel, which would claim a gamut three channels cannot deliver.
/// A drawn tooth was tried first and abandoned - filled and banded at 48 px it
/// reads as a tin can, and no amount of tuning the taper fixed that.
abstract final class NuansMark {
  /// The ground.
  ///
  /// The clinical theme's seed colour, and a cool neutral on purpose: a shade
  /// is judged against a neutral surround, never against another colour. The
  /// same reasoning that keeps the capture screen grey picks the icon's ground.
  static const Color ground = Color(0xFF37474F);

  /// The holder the tabs hang from. Neutral, and quieter than the tabs.
  static const Color rail = Color(0xFF90A4AE);

  /// Tab tones, cervical to incisal.
  ///
  /// **These are not shade values and must never be presented as any.** They
  /// are decorative: warm, close together, and far enough apart to stay legible
  /// at 48 px, which is a typographic constraint rather than a colorimetric
  /// one. The real shade libraries live in `assets/shade_libraries` and are
  /// themselves marked as an unverified scaffold.
  static const List<Color> tabs = [
    Color(0xFFD8BC93), // the most chromatic, as a cervical third usually is
    Color(0xFFE9D6B8), // the body third
    Color(0xFFF5EADA), // the lightest, where enamel turns translucent
  ];

  /// Tab width, as a fraction of the shortest side.
  static const double _tabWidth = 0.18;

  /// Space between tabs. Narrow enough that three tabs read as one object.
  static const double _gap = 0.045;

  /// The holder's thickness, and how far it overhangs the outer tabs.
  static const double _railHeight = 0.055;

  /// Tab lengths, in the order of [tabs].
  static const List<double> _tabHeights = [0.36, 0.48, 0.40];

  /// How round the hanging end of a tab is, as a fraction of its width.
  static const double _tabCorner = 0.45;

  /// Paints the mark, optionally over [ground].
  ///
  /// [inset] shrinks it, for an adaptive icon's foreground where only the
  /// middle of the canvas is guaranteed to survive the launcher's mask.
  static void paint(
    Canvas canvas,
    Size size, {
    bool withGround = true,
    double inset = 1,
  }) {
    if (withGround) {
      canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    }

    final unit = size.shortestSide * inset;
    final tabWidth = unit * _tabWidth;
    final gap = unit * _gap;
    final railHeight = unit * _railHeight;
    final width = tabWidth * 3 + gap * 2;
    final height = railHeight + unit * _tabHeights.reduce(_larger);
    final left = (size.width - width) / 2;
    final top = (size.height - height) / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left - gap, top, width + gap * 2, railHeight),
        Radius.circular(railHeight / 2),
      ),
      Paint()..color = rail,
    );

    for (var index = 0; index < tabs.length; index++) {
      final tab = Rect.fromLTWH(
        left + (tabWidth + gap) * index,
        top + railHeight,
        tabWidth,
        unit * _tabHeights[index],
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          tab,
          bottomLeft: Radius.circular(tabWidth * _tabCorner),
          bottomRight: Radius.circular(tabWidth * _tabCorner),
        ),
        Paint()..color = tabs[index],
      );
    }
  }

  /// The rectangle the mark actually paints into.
  ///
  /// Exposed so the generator can prove the adaptive icon's foreground stays
  /// inside the circle Android guarantees to show, rather than it being
  /// checked by eye once and then drifting the next time a proportion moves.
  static Rect boundsFor(Size size, {double inset = 1}) {
    final unit = size.shortestSide * inset;
    final width = unit * (_tabWidth * 3 + _gap * 2);
    final height = unit * (_railHeight + _tabHeights.reduce(_larger));
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      // The holder overhangs the outer tabs by one gap on each side.
      width: width + unit * _gap * 2,
      height: height,
    );
  }

  static double _larger(double a, double b) => a > b ? a : b;
}
