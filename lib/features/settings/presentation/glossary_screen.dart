import 'package:flutter/material.dart';
import 'package:nuans/l10n/app_localizations.dart';

/// The clinical glossary.
///
/// Present in the application and not only in the repository, because the pair
/// of terms is fixed and both sides have to use the same one. A technician and
/// a clinician reading different words for the same region is how a shade name
/// gets applied to the wrong third of a tooth.
class GlossaryScreen extends StatelessWidget {
  const GlossaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final entries = <({String term, String? note})>[
      (term: strings.regionCervical, note: null),
      (term: strings.regionBody, note: null),
      (term: strings.regionIncisal, note: null),
      (term: strings.layerDentin, note: null),
      (term: strings.compositeEnamelLabel, note: null),
      (term: strings.layerOpaque, note: null),
      (
        term: strings.glossaryTranslucency,
        note: strings.translucencyEstimated,
      ),
      (term: strings.glossaryHue, note: null),
      (term: strings.glossaryChroma, note: null),
      (term: strings.glossaryValue, note: null),
      (term: strings.glossaryShadeGuide, note: null),
      (term: strings.glossaryTestFiring, note: null),
      (
        term: strings.confidenceLabel,
        note: strings.onboardingAccuracyBody,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(strings.glossaryTitle)),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            title: Text(entry.term),
            subtitle: entry.note == null ? null : Text(entry.note!),
          );
        },
      ),
    );
  }
}
