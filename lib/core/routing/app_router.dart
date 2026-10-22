import 'package:go_router/go_router.dart';
import 'package:nuans/features/analysis/presentation/result_screen.dart';
import 'package:nuans/features/capture/presentation/live_camera_screen.dart';
import 'package:nuans/features/capture/presentation/overlay_preview.dart';
import 'package:nuans/features/onboarding/presentation/onboarding_screen.dart';
import 'package:nuans/features/settings/presentation/glossary_screen.dart';
import 'package:nuans/features/settings/presentation/home_screen.dart';
import 'package:nuans/features/settings/presentation/settings_screen.dart';
import 'package:shade_core/shade_core.dart';

/// The routes this build ships.
///
/// Everything below the home screen is reached with `context.push`, never
/// `context.go`. For a top-level route `go` REPLACES the navigation stack, so
/// there is no previous page: the system back button finds an empty stack and
/// closes the application instead of going back. `push` also earns the AppBar
/// its back arrow without anything being wired for it.
///
///
/// Deliberately short. The capture path needs a calibrated device, a grey card
/// and a patient, none of which exist on a first launch, so this build exposes
/// what can honestly be exercised without them: the onboarding, the overlay,
/// the worked example end to end, the glossary and the language switch.
/// Builds a router.
///
/// A function rather than a single global instance so that a test gets a fresh
/// navigation stack: a shared router carries the route one test left it on into
/// the next one, which is how a navigation regression hides.
GoRouter createAppRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/camera',
          builder: (context, state) => const LiveCameraScreen(),
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

/// The router the application runs on.
final appRouter = createAppRouter();
