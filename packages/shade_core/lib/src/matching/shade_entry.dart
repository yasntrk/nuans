import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/constants.dart';

/// Which shade guide system a library follows.
///
/// Named for compatibility rather than for the brand: the application states
/// which commercial system its libraries are compatible with, and uses no brand
/// name in its own identity.
enum ShadeSystem {
  /// Sixteen shades, hue family plus chroma step: A1 .. D4.
  classicalCompatible,

  /// Twenty-nine shades on value, hue and chroma axes: 0M1 .. 5M3.
  threeDimensionalMasterCompatible,
}

/// Where an entry's Lab value came from.
enum ShadeValueSource {
  /// A scaffold value: ordered so that the guide's own structure holds, but
  /// never measured and not quoted from a published table.
  ///
  /// The libraries that ship are entirely of this kind. They exist so that the
  /// matching, mixing and reporting paths have something consistent to run on
  /// from the first launch, and so that a clinic can see the shape of a result
  /// before it has calibrated anything. They are not a colorimetric claim
  /// about any physical shade guide, and every screen that shows one says so.
  unverifiedPlaceholder,

  /// Measured in this application from the clinic's own physical guide, which
  /// always takes precedence over literature values.
  clinicalMeasurement,
}

/// One shade of a guide.
@immutable
final class ShadeEntry {
  const ShadeEntry({
    required this.code,
    required this.lab,
    required this.source,
    this.measuredAtUtc,
  });

  /// The guide's own code, never translated: `A3`, `2M2`.
  final String code;

  /// Lab under D65, 2 degree observer.
  final LabColor lab;

  final ShadeValueSource source;

  /// When a clinical measurement was taken. Always UTC; `null` for literature
  /// placeholders.
  final DateTime? measuredAtUtc;

  bool get isPlaceholder => source == ShadeValueSource.unverifiedPlaceholder;

  @override
  bool operator ==(Object other) =>
      other is ShadeEntry &&
      other.code == code &&
      other.lab == lab &&
      other.source == source &&
      other.measuredAtUtc == measuredAtUtc;

  @override
  int get hashCode => Object.hash(code, lab, source, measuredAtUtc);

  @override
  String toString() => 'ShadeEntry($code, $lab, ${source.name})';
}

/// A shade guide: the set of physical tabs a clinic matches against.
@immutable
final class ShadeLibrary {
  /// Validates and copies [entries].
  factory ShadeLibrary({
    required String id,
    required ShadeSystem system,
    required List<ShadeEntry> entries,
  }) {
    if (entries.isEmpty) {
      throw ArgumentError.value(0, 'entries.length', 'must not be empty');
    }
    if (entries.length > kMaxLibraryEntries) {
      throw ArgumentError.value(
        entries.length,
        'entries.length',
        'brute force search is sized for at most $kMaxLibraryEntries entries',
      );
    }
    final byCode = <String, ShadeEntry>{};
    for (final entry in entries) {
      if (byCode.containsKey(entry.code)) {
        throw ArgumentError.value(
          entry.code,
          'code',
          'shade codes must be unique within a library',
        );
      }
      byCode[entry.code] = entry;
    }
    return ShadeLibrary._(
      id: id,
      system: system,
      entries: List<ShadeEntry>.unmodifiable(entries),
      byCode: Map<String, ShadeEntry>.unmodifiable(byCode),
    );
  }

  const ShadeLibrary._({
    required this.id,
    required this.system,
    required this.entries,
    required Map<String, ShadeEntry> byCode,
  }) : _byCode = byCode;

  /// Identifier of this library, e.g. `vita_classical_compatible` or a
  /// clinic-specific identifier for a measured guide.
  final String id;

  final ShadeSystem system;
  final List<ShadeEntry> entries;
  final Map<String, ShadeEntry> _byCode;

  ShadeEntry? operator [](String code) => _byCode[code];

  int get length => entries.length;

  /// Whether any entry is still an unverified literature value.
  bool get containsPlaceholders => entries.any((e) => e.isPlaceholder);

  /// The share of entries measured in this clinic, an input to the confidence
  /// engine: matching against a fully measured guide is a different proposition
  /// from matching against literature averages.
  double get clinicalCoverage =>
      entries.where((e) => !e.isPlaceholder).length / entries.length;

  @override
  String toString() =>
      'ShadeLibrary($id, ${system.name}, ${entries.length} entries)';
}
