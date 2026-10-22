import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/app.dart';
import 'package:nuans/core/routing/app_router.dart';
import 'package:nuans/features/settings/presentation/home_screen.dart';

/// Every screen must be reachable AND leavable.
///
/// This exists because of a reported bug: opening any menu entry and pressing
/// the system back button closed the application instead of returning to the
/// home screen. The cause was `context.go`, which REPLACES the navigation
/// stack for a top-level route, so there was no previous page and back found
/// an empty stack.
///
/// Two things are asserted per screen, because either alone would have passed
/// throughout the bug:
///   * `Navigator.canPop` is true - something is underneath to go back to.
///   * the system back button actually lands on the home screen again.
void main() {
  /// The exact channel message the engine sends when the Android back button
  /// is pressed, so the test exercises what the user pressed rather than the
  /// AppBar arrow.
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // A fresh router per test: a shared one carries over the route the
        // previous test left it on.
        child: NuansApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool canPop(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).last).canPop();

  /// The home screen is a lazily built [ListView], so a tile below the fold
  /// does not exist until it is scrolled into view.
  Future<Finder> tileWithIcon(WidgetTester tester, IconData icon) async {
    // Unfiltered: evaluating a `.first` finder with no candidates throws.
    final all = find.widgetWithIcon(ListTile, icon);
    if (all.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        all,
        find.byType(ListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(all.first);
    await tester.pumpAndSettle();
    return all.first;
  }

  testWidgets('the home screen is the root and cannot be popped',
      (tester) async {
    await pumpApp(tester);
    expect(canPop(tester), isFalse);
  });

  // Every tile on the home screen, found by its icon so the test does not
  // depend on which language the harness resolves.
  const tiles = <IconData>[
    Icons.flag_outlined, // onboarding
    Icons.photo_camera_outlined, // the live camera
    Icons.center_focus_strong_outlined, // the overlay workbench
    Icons.science_outlined, // a result screen
    Icons.menu_book_outlined, // glossary
  ];

  for (final icon in tiles) {
    testWidgets('tile $icon opens and the system back button returns home',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(await tileWithIcon(tester, icon));
      // Not pumpAndSettle: the result screen computes its worked example, and
      // settling would wait on that work. Reaching the screen is enough.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The assertion the bug failed: there is a page underneath.
      expect(canPop(tester), isTrue, reason: 'nothing to go back to');

      await pressSystemBack(tester);

      // Home again, with an empty stack below it.
      expect(canPop(tester), isFalse, reason: 'did not return home');
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  testWidgets('the settings action opens and the back button returns home',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(canPop(tester), isTrue);
    await pressSystemBack(tester);
    expect(canPop(tester), isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the onboarding finish button returns rather than replacing',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(await tileWithIcon(tester, Icons.flag_outlined));
    await tester.pumpAndSettle();

    // Walk to the last page. The forward button is a TextButton that is only
    // built while a next page exists; on the last page it is replaced by the
    // FilledButton that finishes.
    var guard = 0;
    while (find.byType(TextButton).evaluate().isNotEmpty) {
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      if (++guard > 10) fail('onboarding never reached its last page');
    }
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Back at the home screen, with nothing left on the stack.
    expect(canPop(tester), isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
