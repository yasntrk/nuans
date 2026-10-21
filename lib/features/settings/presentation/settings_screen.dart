import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:nuans/l10n/locale_controller.dart';

/// Settings. In this build, the language switch and the regulatory note.
///
/// The language changes without a restart, which is why the root watches the
/// locale provider rather than reading it once.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final active = ref.watch(localeControllerProvider);
    final controller = ref.read(localeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(
              strings.settingsLanguage,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          // A RadioGroup ancestor owns the selection; the tiles no longer
          // carry groupValue and onChanged of their own.
          RadioGroup<String>(
            groupValue: active.languageCode,
            onChanged: (code) {
              if (code != null) controller.select(Locale(code));
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'tr',
                  title: Text(strings.settingsLanguageTurkish),
                ),
                RadioListTile<String>(
                  value: 'en',
                  title: Text(strings.settingsLanguageEnglish),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: Text(strings.settingsLanguageSystem),
            onTap: controller.followDevice,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(strings.settingsAbout),
            subtitle: Text(strings.settingsRegulatoryNote),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              strings.appLegalDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
