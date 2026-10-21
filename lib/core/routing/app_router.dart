import 'package:go_router/go_router.dart';
import 'package:nuans/features/analysis/presentation/result_screen.dart';
import 'package:nuans/features/capture/presentation/overlay_preview.dart';
import 'package:nuans/features/onboarding/presentation/onboarding_screen.dart';
import 'package:nuans/features/settings/presentation/glossary_screen.dart';
import 'package:nuans/features/settings/presentation/home_screen.dart';
import 'package:nuans/features/settings/presentation/settings_screen.dart';
import 'package:shade_core/shade_core.dart';

/// The routes this build ships.
///
/// Deliberately short. The capture path needs a calibrated device, a grey card
/// and a patient, none of which exist on a first launch, so this build exposes
/// what can honestly be exercised without them: the onboarding, the overlay,
/// the worked example end to end, the glossary and the language switch.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/overlay',
      builder: (context, state) => const OverlayPreviewScreen(),
    ),
    GoRoute(
      path: '/result/:material',
      builder: (context, state) => ResultScreen(
        material: RestorativeMaterial.values.firstWhere(
          (m) => m.name == state.pathParameters['material'],
          orElse: () => RestorativeMaterial.metalCeramic,
        ),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/glossary',
      builder: (context, state) => const GlossaryScreen(),
    ),
  ],
);
