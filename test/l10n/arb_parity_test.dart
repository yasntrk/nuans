import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the two ARB files against each other.
///
/// The generator makes drift impossible by construction, so this test is the
/// belt to that braces: it fails if someone edits an ARB file by hand, or adds
/// a locale without going through the generator.
void main() {
  Map<String, Object?> load(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;

  late Map<String, Object?> tr;
  late Map<String, Object?> en;

  setUpAll(() {
    tr = load('tr');
    en = load('en');
  });

  Set<String> messageKeys(Map<String, Object?> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  final placeholderPattern = RegExp(r'\{\s*(\w+)\s*[,}]');

  test('both locales declare themselves', () {
    expect(tr['@@locale'], 'tr');
    expect(en['@@locale'], 'en');
  });

  test('the key sets are identical', () {
    final trKeys = messageKeys(tr);
    final enKeys = messageKeys(en);
    expect(
      trKeys.difference(enKeys),
      isEmpty,
      reason: 'keys present only in Turkish',
    );
    expect(
      enKeys.difference(trKeys),
      isEmpty,
      reason: 'keys present only in English',
    );
  });

  test('no message is empty in either locale', () {
    for (final key in messageKeys(en)) {
      expect((tr[key] as String?)?.isNotEmpty, isTrue, reason: 'tr: $key');
      expect((en[key] as String?)?.isNotEmpty, isTrue, reason: 'en: $key');
    }
  });

  test('every message carries a description for the translator', () {
    for (final key in messageKeys(en)) {
      final meta = en['@$key'];
      expect(meta, isA<Map<String, Object?>>(), reason: key);
      final description = (meta! as Map<String, Object?>)['description'];
      expect(description, isA<String>(), reason: key);
      expect((description! as String).isNotEmpty, isTrue, reason: key);
    }
  });

  test('declared placeholders appear in both languages', () {
    // The failure this catches is a sentence with a hole in it, in one language
    // only, which is exactly the kind of bug that reaches a clinician.
    for (final key in messageKeys(en)) {
      final meta = en['@$key'] as Map<String, Object?>?;
      final placeholders = meta?['placeholders'];
      if (placeholders is! Map<String, Object?>) continue;
      final trUsed = placeholderPattern
          .allMatches(tr[key]! as String)
          .map((m) => m.group(1))
          .toSet();
      final enUsed = placeholderPattern
          .allMatches(en[key]! as String)
          .map((m) => m.group(1))
          .toSet();
      for (final name in placeholders.keys) {
        expect(trUsed, contains(name), reason: 'tr: $key misses {$name}');
        expect(enUsed, contains(name), reason: 'en: $key misses {$name}');
      }
    }
  });

  test('ICU select and plural branches match across locales', () {
    final icuPattern = RegExp(r'\{\s*(\w+)\s*,\s*(select|plural)\s*,');
    for (final key in messageKeys(en)) {
      final trMessage = tr[key]! as String;
      final enMessage = en[key]! as String;
      final trIcu = icuPattern.firstMatch(trMessage);
      final enIcu = icuPattern.firstMatch(enMessage);
      expect(
        trIcu == null,
        enIcu == null,
        reason: '$key is ICU in one locale only',
      );
      if (trIcu == null || enIcu == null) continue;
      expect(trIcu.group(1), enIcu.group(1), reason: '$key argument name');
      expect(trIcu.group(2), enIcu.group(2), reason: '$key ICU kind');
    }
  });

  test('the generated files say not to edit them', () {
    for (final arb in [tr, en]) {
      expect(arb['@@context'], contains('generate.py'));
    }
  });

  test('no message hard-codes a brand name in the product identity', () {
    // Brand names may appear in a compatibility statement and nowhere else.
    const compatibilityKeys = {'shadeSystemClassical', 'shadeSystemMaster'};
    for (final key in messageKeys(en)) {
      if (compatibilityKeys.contains(key)) continue;
      for (final message in [tr[key]! as String, en[key]! as String]) {
        expect(
          message.toLowerCase(),
          isNot(contains('vita')),
          reason: '$key names a brand outside a compatibility statement',
        );
      }
    }
  });
}
