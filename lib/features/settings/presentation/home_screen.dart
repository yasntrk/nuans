import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// The entry point of this build.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: strings.settingsTitle,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(strings.appTagline, style: textTheme.titleMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.onboardingAccuracyTitle,
                          style: textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.onboardingAccuracyBody,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _tile(
            context,
            icon: Icons.flag_outlined,
            title: strings.onboardingWelcomeTitle,
            onTap: () => context.push('/onboarding'),
          ),
          _tile(
            context,
            icon: Icons.photo_camera_outlined,
            title: strings.liveCameraTitle,
            subtitle: strings.deviceProfileMissing,
            onTap: () => context.push('/camera'),
          ),
          _tile(
            context,
            icon: Icons.center_focus_strong_outlined,
            title: strings.overlayWorkbenchTitle,
            subtitle: strings.overlayWorkbenchSubtitle,
            onTap: () => context.push('/overlay'),
          ),
          const Divider(height: 28),
          Text(strings.analysisTitle, style: textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final material in RestorativeMaterial.values)
            _tile(
              context,
              icon: Icons.science_outlined,
              title: _materialLabel(strings, material),
              onTap: () => context.push('/result/${material.name}'),
            ),
          const Divider(height: 28),
          _tile(
            context,
            icon: Icons.menu_book_outlined,
            title: strings.glossaryTitle,
            onTap: () => context.push('/glossary'),
          ),
          const SizedBox(height: 24),
          Text(
            strings.appLegalDisclaimer,
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _materialLabel(
    AppLocalizations strings,
    RestorativeMaterial material,
  ) =>
      switch (material) {
        RestorativeMaterial.zirconia => strings.materialZirconia,
        RestorativeMaterial.metalCeramic => strings.materialMetalCeramic,
        RestorativeMaterial.composite => strings.materialComposite,
      };

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
