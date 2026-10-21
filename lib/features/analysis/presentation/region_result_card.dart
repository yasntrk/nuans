import 'package:flutter/material.dart';
import 'package:nuans/core/formatting/clinical_formats.dart';
import 'package:nuans/core/l10n/clinical_strings.dart';
import 'package:nuans/core/theme/app_theme.dart';
import 'package:nuans/features/analysis/presentation/status_chip.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// One tooth region's result: the match, the band, the explanation and the
/// alternatives.
class RegionResultCard extends StatelessWidget {
  const RegionResultCard({required this.analysis, super.key});

  final RegionAnalysis analysis;

  /// The Lab triple, formatted in the reader's locale.
  String _labRow(AppLocalizations strings, String locale) {
    final lab = analysis.reduction.lab;
    String component(double value) =>
        ClinicalFormats.labComponent(value, locale);
    return '${strings.reportFieldLabValues}  '
        '${component(lab.lightness)} / '
        '${component(lab.a)} / '
        '${component(lab.b)}';
  }

  static AppStatus statusOf(AcceptabilityBand band) => switch (band) {
        AcceptabilityBand.imperceptible => AppStatus.pass,
        AcceptabilityBand.acceptable => AppStatus.warn,
        AcceptabilityBand.unacceptable => AppStatus.fail,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final textTheme = Theme.of(context).textTheme;
    final best = analysis.best;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    strings.toothRegion(analysis.region),
                    style: textTheme.titleMedium,
                  ),
                ),
                // The shade code is never translated and never case-converted.
                Text(best.entry.code, style: textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(
                  status: statusOf(best.band),
                  label: strings.deltaEValue(best.deltaE2000),
                  detail: strings.acceptabilityBand(best.band),
                  dense: true,
                ),
                if (best.entry.isPlaceholder)
                  const StatusChip(
                    status: AppStatus.warn,
                    label: '!',
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // The human-language explanation, assembled entirely from ARB
            // templates: no fragment of this sentence is concatenated in Dart.
            Text(strings.shadeComparison(best), style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(_labRow(strings, locale), style: textTheme.bodySmall),
            if (analysis.matches.length > 1) ...[
              const Divider(height: 20),
              Text(strings.alternativesLabel, style: textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final match in analysis.matches.skip(1))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child:
                            Text(match.entry.code, style: textTheme.bodyMedium),
                      ),
                      Expanded(
                        child: Text(
                          strings.deltaEValue(match.deltaE2000),
                          style: textTheme.bodySmall,
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
