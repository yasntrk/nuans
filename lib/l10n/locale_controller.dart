import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The locales this application ships.
const List<Locale> supportedLocales = [Locale('tr'), Locale('en')];

/// What the user chose in Settings.
///
/// `null` means "follow the device", which is the default.
typedef LocaleChoice = Locale?;

/// Resolves and holds the active locale.
///
/// Two rules from the specification live here:
///
/// * the default follows the device, and falls back to English when the device
///   language is neither Turkish nor English;
/// * the language can be changed without restarting the application, which is
///   why this is a notifier the whole widget tree watches rather than a value
///   read once at startup.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => resolve(null);

  /// Follows the device language again.
  void followDevice() => state = resolve(null);

  /// Pins the application to [locale].
  void select(Locale locale) {
    if (!supportedLocales.any((l) => l.languageCode == locale.languageCode)) {
      throw ArgumentError.value(
        locale.toLanguageTag(),
        'locale',
        'not one of the supported locales',
      );
    }
    state = Locale(locale.languageCode);
  }

  /// Whether the active locale came from the device rather than from a choice.
  bool get followsDevice => _choice == null;

  LocaleChoice _choice;

  /// Resolves a choice against the device's preferences.
  ///
  /// Static and pure so the fallback rule is unit testable without a platform.
  static Locale resolve(
    LocaleChoice choice, {
    List<Locale>? deviceLocales,
  }) {
    if (choice != null) return Locale(choice.languageCode);
    final preferred = deviceLocales ?? PlatformDispatcher.instance.locales;
    for (final locale in preferred) {
      for (final supported in supportedLocales) {
        if (locale.languageCode == supported.languageCode) return supported;
      }
    }
    // English rather than Turkish: a clinician whose device is in neither
    // language is more likely to read English, and the specification says so.
    return const Locale('en');
  }
}

/// The active locale.
final localeControllerProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);

/// The locale the PDF report is built in.
///
/// Separate from the interface locale on purpose: a Turkish-speaking clinician
/// sends an English report to a laboratory abroad. Defaults to the interface
/// locale and is overridden per report.
final reportLocaleProvider = StateProvider<Locale?>((ref) => null);
