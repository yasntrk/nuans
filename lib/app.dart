import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuans/core/routing/app_router.dart';
import 'package:nuans/core/theme/app_theme.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:nuans/l10n/locale_controller.dart';

/// The application root.
///
/// Watches the locale rather than reading it once, which is what lets Settings
/// change the language without a restart.
class NuansApp extends ConsumerWidget {
  const NuansApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.clinical(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
