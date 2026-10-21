import 'package:meta/meta.dart';

/// The kind of enamel layer a rule selects.
///
/// Brand-independent on purpose. A commercial enamel is identified by a product
/// name that differs per manufacturer and per product line, so the engine
/// decides what *kind* of enamel the measurement calls for and a separate
/// mapping table translates that into whatever the clinic actually stocks.
enum EnamelKind {
  /// Use an enamel of the same shade family as the dentin.
  matchingShade,

  /// A general-purpose enamel, neither notably translucent nor opaque.
  universal,

  /// A translucent enamel, for an incisal third that reads darker and bluer
  /// than the body.
  translucent,

  /// An opalescent enamel, for a pronounced blue shift with the lightness held
  /// up.
  opalescent,

  /// A high-value enamel for bleached teeth.
  bleach,
}

/// One rule of the composite layering table.
///
/// All bounds are optional and inclusive; an absent bound is not a constraint.
/// A rule with no bounds at all matches everything, which is how the table's
/// last entry acts as a default.
@immutable
final class EnamelRule {
  const EnamelRule({
    required this.id,
    required this.enamel,
    this.incisalLightnessMin,
    this.incisalLightnessMax,
    this.blueShiftMin,
    this.blueShiftMax,
    this.incisalChromaMax,
  });

  /// Parses one rule from decoded JSON.
  ///
  /// Parsing lives here rather than in the app layer so that a malformed rule
  /// table fails in a unit test rather than in a clinic.
  factory EnamelRule.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('a layering rule needs a non-empty id', json);
    }
    final kindName = json['enamel'];
    final kind = EnamelKind.values.where((k) => k.name == kindName);
    if (kind.isEmpty) {
      throw FormatException(
        'unknown enamel kind "$kindName" in rule $id',
        json,
      );
    }
    final when = json['when'];
    final bounds =
        when is Map<String, Object?> ? when : const <String, Object?>{};
    double? number(String key) {
      final value = bounds[key];
      if (value == null) return null;
      if (value is num) return value.toDouble();
      throw FormatException('$key of rule $id must be a number', json);
    }

    return EnamelRule(
      id: id,
      enamel: kind.first,
      incisalLightnessMin: number('incisalLightnessMin'),
      incisalLightnessMax: number('incisalLightnessMax'),
      blueShiftMin: number('blueShiftMin'),
      blueShiftMax: number('blueShiftMax'),
      incisalChromaMax: number('incisalChromaMax'),
    );
  }

  final String id;
  final EnamelKind enamel;

  final double? incisalLightnessMin;
  final double? incisalLightnessMax;

  /// Bounds on the blue shift, defined as `b*(incisal) - b*(body)`.
  ///
  /// Negative means the incisal third is bluer than the body, which is what
  /// translucency looks like when there is nothing but air behind the edge.
  final double? blueShiftMin;
  final double? blueShiftMax;

  final double? incisalChromaMax;

  bool matches({
    required double incisalLightness,
    required double blueShift,
    required double incisalChroma,
  }) {
    if (incisalLightnessMin != null &&
        incisalLightness < incisalLightnessMin!) {
      return false;
    }
    if (incisalLightnessMax != null &&
        incisalLightness > incisalLightnessMax!) {
      return false;
    }
    if (blueShiftMin != null && blueShift < blueShiftMin!) return false;
    if (blueShiftMax != null && blueShift > blueShiftMax!) return false;
    if (incisalChromaMax != null && incisalChroma > incisalChromaMax!) {
      return false;
    }
    return true;
  }

  @override
  String toString() => 'EnamelRule($id -> ${enamel.name})';
}

/// The composite layering rule table.
///
/// Rules are evaluated in file order and the first match wins, so the table is
/// read from most specific to least. That ordering is data, not code: a clinic
/// can reorder or extend the table without a release.
@immutable
final class LayeringRuleTable {
  const LayeringRuleTable({
    required this.schemaVersion,
    required this.id,
    required this.enamelRules,
    required this.brandMapping,
  });

  factory LayeringRuleTable.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != supportedSchemaVersion) {
      throw FormatException(
        'unsupported layering rule schema version $version, '
        'expected $supportedSchemaVersion',
        json,
      );
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('a rule table needs a non-empty id', json);
    }
    final rules = json['enamelRules'];
    if (rules is! List || rules.isEmpty) {
      throw FormatException(
        'a rule table needs at least one enamel rule',
        json,
      );
    }
    final parsed = <EnamelRule>[];
    final seen = <String>{};
    for (final raw in rules) {
      if (raw is! Map<String, Object?>) {
        throw FormatException('every enamel rule must be an object', json);
      }
      final rule = EnamelRule.fromJson(raw);
      if (!seen.add(rule.id)) {
        throw FormatException('duplicate rule id "${rule.id}"', json);
      }
      parsed.add(rule);
    }

    final mapping = <String, Map<String, String>>{};
    final rawMapping = json['brandMapping'];
    if (rawMapping is Map<String, Object?>) {
      final kinds = EnamelKind.values.map((k) => k.name).toSet();
      for (final entry in rawMapping.entries) {
        // Only real enamel kinds are mapping entries. Without this check a
        // documentation key such as `_comment`, whose value is a `{tr, en}`
        // object, parses as a brand mapping and `mappedBrands` reports `tr`
        // and `en` as brands. Rejecting unknown keys also catches a typo in a
        // clinic's own table, which would otherwise silently map nothing.
        if (!kinds.contains(entry.key)) {
          if (entry.key.startsWith('_')) continue;
          throw FormatException(
            'brandMapping key "${entry.key}" is not an enamel kind',
            json,
          );
        }
        final value = entry.value;
        if (value is! Map<String, Object?>) continue;
        mapping[entry.key] = {
          for (final brand in value.entries)
            if (brand.value is String) brand.key: brand.value! as String,
        };
      }
    }

    return LayeringRuleTable(
      schemaVersion: supportedSchemaVersion,
      id: id,
      enamelRules: List<EnamelRule>.unmodifiable(parsed),
      brandMapping: Map<String, Map<String, String>>.unmodifiable(mapping),
    );
  }

  /// The schema version this code understands.
  static const int supportedSchemaVersion = 1;

  final int schemaVersion;
  final String id;
  final List<EnamelRule> enamelRules;

  /// Generic enamel kind to the product name a given brand prints on the jar.
  ///
  /// Ships empty. Filling it in means copying names off a manufacturer's own
  /// chart, and inventing those names would put made-up product data in front
  /// of a technician who is about to order materials.
  final Map<String, Map<String, String>> brandMapping;

  /// The first rule that matches, or `null` when the table has no default.
  EnamelRule? select({
    required double incisalLightness,
    required double blueShift,
    required double incisalChroma,
  }) {
    for (final rule in enamelRules) {
      if (rule.matches(
        incisalLightness: incisalLightness,
        blueShift: blueShift,
        incisalChroma: incisalChroma,
      )) {
        return rule;
      }
    }
    return null;
  }

  /// The product name a brand uses for [kind], when the mapping knows it.
  String? productName({required EnamelKind kind, required String brand}) =>
      brandMapping[kind.name]?[brand];

  /// Brands the mapping has entries for.
  Set<String> get mappedBrands => {
        for (final entry in brandMapping.values) ...entry.keys,
      };
}
