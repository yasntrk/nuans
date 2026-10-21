import 'package:flutter/material.dart';
import 'package:nuans/features/analysis/presentation/confidence_banner.dart';
import 'package:nuans/features/analysis/presentation/region_result_card.dart';
import 'package:nuans/features/demo/demo_measurement.dart';
import 'package:nuans/features/recipe/presentation/recipe_card.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// The result screen, running the real engine over a worked example.
///
/// The ordering is the specification's and it is deliberate: confidence first,
/// then the regions, then the recipe, then the warnings. A technician who reads
/// a shade name before the confidence has lost the one piece of information
/// that says what the name is worth.
class ResultScreen extends StatefulWidget {
  const ResultScreen({required this.material, super.key});

  final RestorativeMaterial material;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Future<DemoMeasurement> _measurement;

  @override
  void initState() {
    super.initState();
    _measurement = DemoMeasurement.build(material: widget.material);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.analysisTitle)),
      body: FutureBuilder<DemoMeasurement>(
        future: _measurement,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snapshot.error}'),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ConfidenceBanner(score: data.confidence, expanded: true),
              const SizedBox(height: 16),
              for (final region in ToothRegion.values)
                if (data.regions[region] case final analysis?)
                  RegionResultCard(analysis: analysis),
              RecipeCard(recipe: data.recipe),
              const SizedBox(height: 16),
              // Shown whenever the result rests on library values the clinic
              // has not measured, which on a fresh install is always.
              if (data.library.clinicalCoverage < 1)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      strings.placeholderLibraryWarning,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                strings.appLegalDisclaimer,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
