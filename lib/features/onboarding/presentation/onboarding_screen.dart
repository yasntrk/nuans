import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nuans/l10n/app_localizations.dart';

/// The four onboarding pages.
///
/// The second page says the device is not a spectrophotometer, before the user
/// has measured anything. That ordering is the point: the limits are part of
/// learning the tool, not a disclaimer appended after a result.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final pages = <({String title, String body, IconData icon})>[
      (
        title: strings.onboardingWelcomeTitle,
        body: strings.onboardingWelcomeBody,
        icon: Icons.colorize_outlined,
      ),
      (
        title: strings.onboardingAccuracyTitle,
        body: strings.onboardingAccuracyBody,
        icon: Icons.rule_outlined,
      ),
      (
        title: strings.onboardingLightingTitle,
        body: strings.onboardingLightingBody,
        icon: Icons.lightbulb_outline,
      ),
      (
        title: strings.onboardingPrivacyTitle,
        body: strings.onboardingPrivacyBody,
        icon: Icons.lock_outline,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(strings.appName)),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) {
                final page = pages[index];
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(page.icon, size: 48),
                      const SizedBox(height: 24),
                      Text(
                        page.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.body,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                const Spacer(),
                if (_page < pages.length - 1)
                  TextButton(
                    onPressed: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: Text(strings.actionContinue),
                  )
                else
                  FilledButton(
                    // pop, not go('/'): this screen was pushed, so popping it
                    // returns to whatever opened it. go('/') would replace the
                    // stack and leave the back button with nowhere to go.
                    onPressed: () => context.pop(),
                    child: Text(strings.actionContinue),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
