import 'package:flutter/material.dart';
import 'package:nuans/core/l10n/clinical_strings.dart';
import 'package:nuans/core/theme/app_theme.dart';
import 'package:nuans/features/analysis/presentation/status_chip.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// The confidence of a measurement, with its reasoning.
///
/// Placed at the top of the result screen and the top of the report, before any
/// shade name. A technician who reads "A3" and starts building has lost the one
/// piece of information that says how much that name is worth.
class ConfidenceBanner extends StatelessWidget {
  const ConfidenceBanner({
    required this.score,
    this.expanded = false,
    super.key,
  });

  final ConfidenceScore score;

  /// Whether to list every term rather than only the weakest.
  final bool expanded;

  static AppStatus statusOf(ConfidenceBand band) => switch (band) {
        ConfidenceBand.high => AppStatus.pass,
        ConfidenceBand.medium => AppStatus.warn,
        ConfidenceBand.low => AppStatus.fail,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(
              status: statusOf(score.band),
              label: '${strings.confidenceLabel}: '
                  '${strings.confidenceBand(score.band)}',
            ),
            const SizedBox(height: 8),
            Text(
              strings.confidenceWeakestTerm(
                strings.confidenceTerm(score.weakestTerm.name),
              ),
              style: textTheme.bodyMedium,
            ),
            // Hard overrides are listed in full. Each one is a reason the
            // measurement cannot be trusted whatever the weighted score says,
            // so none of them may be summarised away.
            for (final reason in score.overrides)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.confidenceOverride(reason),
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (expanded) ...[
              const Divider(height: 20),
              for (final term in score.terms)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.confidenceTerm(term.name),
                          style: textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: LinearProgressIndicator(
                          value: term.score,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
