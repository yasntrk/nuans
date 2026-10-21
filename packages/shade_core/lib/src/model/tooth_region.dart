/// The three bands a tooth is measured in.
///
/// Fixed thirds of the silhouette rather than anatomy: there is no segmentation
/// in this version, so comparability comes from the geometry always being the
/// same, not from the bands following the real cervical, body and incisal
/// boundaries of a particular tooth.
enum ToothRegion {
  /// Nearest the gingival margin. Usually the most chromatic.
  cervical,

  /// The middle third, which the single-shade match is normally read from.
  body,

  /// Nearest the incisal edge. Usually the lightest and the most translucent.
  incisal,
}

/// The material the restoration will be made of.
///
/// This decides what a recipe even looks like: a powder layering schedule, a
/// block choice, or a two-layer composite plan.
enum RestorativeMaterial {
  /// Zirconia, monolithic or lightly layered.
  zirconia,

  /// Metal-ceramic: opaque, dentin and incisal powders fired in layers.
  metalCeramic,

  /// Direct composite, placed in dentin and enamel layers.
  composite,
}

/// An FDI tooth number, two digits: quadrant then position.
///
/// Validated rather than stored as a bare string, because a report that names
/// the wrong tooth is worse than one that names none.
extension type const FdiToothNumber._(int value) {
  /// Parses a two-digit FDI number, permanent or deciduous.
  static FdiToothNumber? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length != 2) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return null;
    return tryFrom(parsed);
  }

  static FdiToothNumber? tryFrom(int value) {
    final quadrant = value ~/ 10;
    final position = value % 10;
    final isPermanent =
        quadrant >= 1 && quadrant <= 4 && position >= 1 && position <= 8;
    final isDeciduous =
        quadrant >= 5 && quadrant <= 8 && position >= 1 && position <= 5;
    if (!isPermanent && !isDeciduous) return null;
    return FdiToothNumber._(value);
  }

  /// The upper central incisors, the default target of a shade measurement.
  static const FdiToothNumber upperRightCentral = FdiToothNumber._(11);
  static const FdiToothNumber upperLeftCentral = FdiToothNumber._(21);

  int get quadrant => value ~/ 10;
  int get position => value % 10;
  bool get isDeciduous => quadrant >= 5;

  /// Never translated, and never zero-padded differently per locale.
  String get code => value.toString();
}
