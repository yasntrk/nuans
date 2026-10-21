/// Case conversion and search folding that work in Turkish.
///
/// Dart's `toUpperCase` and `toLowerCase` are locale-insensitive, and Turkish
/// is the language where that breaks. The dotted and dotless i are separate
/// letters: `I` lowercases to `ı` and `İ` lowercases to `i`, while Dart's own
/// implementation maps `I` to `i` and `İ` to `i` followed by a combining dot. A
/// patient code typed as `IK-14` would then never match one stored as `ık-14`,
/// and a name upper-cased for a heading would come out misspelt.
///
/// So: **no programmatic case conversion is applied to text a clinician
/// reads.** Anything that needs to be upper case is written upper case in the
/// ARB file. These helpers exist only for matching and sorting, where the
/// transform is internal and never displayed.
abstract final class TurkishText {
  /// Turkish lower case.
  static String toLowerCase(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      buffer.write(
        switch (rune) {
          0x0049 => 'ı', // I  -> dotless i
          0x0130 => 'i', // İ  -> dotted i
          _ => String.fromCharCode(rune).toLowerCase(),
        },
      );
    }
    return buffer.toString();
  }

  /// Turkish upper case.
  static String toUpperCase(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      buffer.write(
        switch (rune) {
          0x0069 => 'İ', // i  -> dotted I
          0x0131 => 'I', // ı  -> dotless I
          _ => String.fromCharCode(rune).toUpperCase(),
        },
      );
    }
    return buffer.toString();
  }

  /// Folds a string for searching: Turkish lower case, then diacritics removed.
  ///
  /// Diacritic folding is for the search box only. A clinician who typed a code
  /// as `SAG-3` should find `sağ-3`, because they are looking for a record they
  /// created, not performing a linguistic comparison.
  static String foldForSearch(String input) {
    final lowered = toLowerCase(input.trim());
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      buffer.write(
        switch (rune) {
          0x00E7 => 'c', // ç
          0x011F => 'g', // ğ
          0x0131 => 'i', // ı
          0x00F6 => 'o', // ö
          0x015F => 's', // ş
          0x00FC => 'u', // ü
          _ => String.fromCharCode(rune),
        },
      );
    }
    return buffer.toString();
  }

  /// Whether [haystack] contains [needle], folded.
  static bool matches(String haystack, String needle) =>
      foldForSearch(haystack).contains(foldForSearch(needle));

  /// Comparator for a Turkish-ordered list.
  ///
  /// Turkish collation puts ç after c, ğ after g, ı before i, ö after o, ş
  /// after s and ü after u, which code-unit order does not. Good enough for a
  /// patient code list; a full collation would need ICU.
  static int compare(String a, String b) {
    final foldedA = _collationKey(a);
    final foldedB = _collationKey(b);
    return foldedA.compareTo(foldedB);
  }

  static const String _alphabet = 'abcçdefgğhıijklmnoöprsştuüvyz';

  static String _collationKey(String input) {
    final lowered = toLowerCase(input);
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final character = String.fromCharCode(rune);
      final index = _alphabet.indexOf(character);
      // Letters sort by their place in the Turkish alphabet; everything else
      // keeps its code point, after all letters.
      buffer.write(
        index >= 0
            ? String.fromCharCode(0x30 + index)
            : String.fromCharCode(0x80 + (rune & 0x7F)),
      );
    }
    return buffer.toString();
  }
}
