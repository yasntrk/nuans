import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/matching/shade_entry.dart';

/// Reads a shade library from decoded JSON.
///
/// Parsing lives in this package rather than in the app layer so that a
/// malformed asset fails in a unit test rather than on a clinician's screen,
/// and so that the clinical override files a clinic produces go through exactly
/// the same validation as the ones that ship.
abstract final class ShadeLibraryCodec {
  /// The schema version this code understands.
  static const int supportedSchemaVersion = 1;

  /// Parses a library.
  ///
  /// Throws [FormatException] rather than skipping bad entries: a library that
  /// silently lost three shades would still match, just against the wrong set,
  /// and nothing downstream could tell.
  static ShadeLibrary decode(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != supportedSchemaVersion) {
      throw FormatException(
        'unsupported shade library schema version $version, '
        'expected $supportedSchemaVersion',
        json,
      );
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('a shade library needs a non-empty id', json);
    }
    final systemName = json['system'];
    final system = ShadeSystem.values.where((s) => s.name == systemName);
    if (system.isEmpty) {
      throw FormatException('unknown shade system "$systemName"', json);
    }
    // The white point is recorded in the file and checked rather than assumed:
    // a library measured under a different illuminant is not comparable with a
    // measurement taken under D65, and the mistake would be invisible.
    final whitePoint = json['whitePoint'];
    if (whitePoint != 'D65_2deg') {
      throw FormatException(
        'shade libraries must be stated under D65_2deg, found "$whitePoint"',
        json,
      );
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List || rawEntries.isEmpty) {
      throw FormatException('a shade library needs at least one entry', json);
    }

    final entries = <ShadeEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, Object?>) {
        throw FormatException('every shade entry must be an object', json);
      }
      entries.add(_decodeEntry(raw));
    }
    return ShadeLibrary(id: id, system: system.first, entries: entries);
  }

  static ShadeEntry _decodeEntry(Map<String, Object?> json) {
    final code = json['code'];
    if (code is! String || code.isEmpty) {
      throw FormatException('a shade entry needs a non-empty code', json);
    }
    final lab = json['lab'];
    if (lab is! Map<String, Object?>) {
      throw FormatException('shade $code has no lab object', json);
    }
    double component(String key) {
      final value = lab[key];
      if (value is num) return value.toDouble();
      throw FormatException('shade $code has no numeric "$key"', json);
    }

    final sourceName = json['source'];
    final source = ShadeValueSource.values.where((s) => s.name == sourceName);
    if (source.isEmpty) {
      throw FormatException(
        'shade $code has unknown source "$sourceName"',
        json,
      );
    }
    final measuredAt = json['measuredAtUtc'];
    DateTime? parsedDate;
    if (measuredAt is String && measuredAt.isNotEmpty) {
      // Always ISO 8601 in the file, whatever the user's locale: the display
      // layer formats it, the file never does.
      parsedDate = DateTime.parse(measuredAt).toUtc();
    }
    if (source.first == ShadeValueSource.clinicalMeasurement &&
        parsedDate == null) {
      throw FormatException(
        'shade $code claims a clinical measurement but carries no date; a '
        "measurement with no date cannot be judged against the guide's age",
        json,
      );
    }

    return ShadeEntry(
      code: code,
      lab: LabColor(component('l'), component('a'), component('b')),
      source: source.first,
      measuredAtUtc: parsedDate,
    );
  }

  /// Applies a clinic's own measurements over a shipped library.
  ///
  /// Clinical measurements always win: the clinic's physical guide is the thing
  /// the restoration will be compared against, and it has an age, a batch and a
  /// wear history that no shipped table can know. Codes present only in the
  /// override are added, so a clinic may extend a guide.
  static ShadeLibrary applyClinicalOverrides({
    required ShadeLibrary base,
    required List<ShadeEntry> measured,
  }) {
    final byCode = <String, ShadeEntry>{
      for (final entry in base.entries) entry.code: entry,
    };
    for (final entry in measured) {
      if (entry.source != ShadeValueSource.clinicalMeasurement) {
        throw ArgumentError.value(
          entry.code,
          'measured',
          'only clinical measurements may override a shipped library',
        );
      }
      byCode[entry.code] = entry;
    }
    final ordered = byCode.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return ShadeLibrary(id: base.id, system: base.system, entries: ordered);
  }
}
