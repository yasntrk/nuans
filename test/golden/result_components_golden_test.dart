import 'package:flutter/material.dart';
import 'package:nuans/core/theme/app_theme.dart';
import 'package:nuans/features/analysis/presentation/confidence_banner.dart';
import 'package:nuans/features/analysis/presentation/region_result_card.dart';
import 'package:nuans/features/analysis/presentation/status_chip.dart';
import 'package:nuans/features/recipe/presentation/recipe_card.dart';
import 'package:shade_core/shade_core.dart';

import 'golden_config.dart';

/// Goldens for the components a clinician reads a result from.
///
/// Captured in both languages at two text scales and two device widths, which
/// is eight images per component. The point is overflow, not translation:
/// Turkish clinical terms are systematically longer than their English
/// equivalents, so a badge that fits in English can be clipped in Turkish, and
/// a result screen that overflows at a 1.3 text scale cannot be read by a
/// clinician wearing loupes.
void main() {
  final library = ShadeLibrary(
    id: 'golden_fixture',
    system: ShadeSystem.classicalCompatible,
    entries: [
      _entry('A1', 78, 0.5, 10),
      _entry('A2', 75, 1.2, 14),
      _entry('A3', 72, 2, 18),
      _entry('A3.5', 70, 2.6, 20),
      _entry('B2', 76, 0.8, 12),
    ],
  );
  final adjacency = ShadeAdjacency.forSystem(
    library.system,
    library.entries.map((e) => e.code).toList(),
  );

  RegionAnalysis analysis(ToothRegion region, LabColor lab) {
    const matcher = ShadeMatcher();
    const mixer = ShadeMixer();
    final matches = matcher.findNearest(target: lab, library: library);
    return RegionAnalysis(
      region: region,
      reduction: RoiReduction(
        xyz: lab.toXyz(),
        lab: lab,
        sampleCount: 400,
        acceptedSamples: 370,
        specularRejected: 20,
        shadowRejected: 10,
        rejectedFraction: 0.075,
        medianLightness: lab.lightness,
        lightnessMad: 1.73,
        lightnessStdDev: 1.85,
        trimmedSampleCount: 296,
      ),
      matches: matches,
      mix: mixer.search(
        target: lab,
        candidates: matches.map((m) => m.entry).toList(),
        library: library,
        adjacency: adjacency,
        bestSingleDeltaE: matches.first.deltaE2000,
      ),
    );
  }

  final regions = {
    ToothRegion.cervical: analysis(
      ToothRegion.cervical,
      const LabColor(70, 2.8, 21),
    ),
    ToothRegion.body: analysis(
      ToothRegion.body,
      const LabColor(73.5, 1.6, 16),
    ),
    ToothRegion.incisal: analysis(
      ToothRegion.incisal,
      const LabColor(76.5, 0.6, 10.5),
    ),
  };

  const scorer = ConfidenceScorer();

  ConfidenceScore scoreFor({required bool good}) => scorer.score(
        captureSource: good ? CcmSource.chartFit : CcmSource.srgbProcessed,
        profileScore: good ? 1 : 0,
        grayCardValid: good,
        grayCardScore: good ? 1 : 0,
        reduction: regions[ToothRegion.body]!.reduction,
        relativeMode: good
            ? RelativeModeState.usedAndConsistent
            : RelativeModeState.notUsed,
        bestMatchDeltaE: regions[ToothRegion.body]!.best.deltaE2000,
        acceptedFrameCount: 3,
      );

  // The worst case for layout: every status chip, both the longest Turkish
  // label and its shorter English counterpart, wrapped at the narrowest width.
  forEachGoldenVariant(
    'status_chips',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(status: AppStatus.pass, label: 'Fark edilemez'),
          SizedBox(height: 8),
          StatusChip(
            status: AppStatus.warn,
            label: 'Klinik olarak kabul edilebilir',
          ),
          SizedBox(height: 8),
          StatusChip(status: AppStatus.fail, label: 'Kabul edilemez'),
          SizedBox(height: 8),
          StatusChip(status: AppStatus.pending, label: 'Bekleniyor'),
        ],
      ),
    ),
    theme: AppTheme.clinical(),
  );

  forEachGoldenVariant(
    'confidence_low',
    () => Padding(
      padding: const EdgeInsets.all(16),
      // The low case carries two hard-override lines, which is the tallest the
      // banner ever gets.
      child: ConfidenceBanner(score: scoreFor(good: false), expanded: true),
    ),
    theme: AppTheme.clinical(),
  );

  forEachGoldenVariant(
    'confidence_high',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: ConfidenceBanner(score: scoreFor(good: true)),
    ),
    theme: AppTheme.clinical(),
  );

  forEachGoldenVariant(
    'region_card',
    () => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: RegionResultCard(analysis: regions[ToothRegion.cervical]!),
    ),
    theme: AppTheme.clinical(),
  );

  for (final material in RestorativeMaterial.values) {
    forEachGoldenVariant(
      'recipe_${material.name}',
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: RecipeCard(
          recipe: _recipeFor(material, regions, library, adjacency),
        ),
      ),
      theme: AppTheme.clinical(),
    );
  }
}

ShadeEntry _entry(String code, double l, double a, double b) => ShadeEntry(
      code: code,
      lab: LabColor(l, a, b),
      source: ShadeValueSource.clinicalMeasurement,
      measuredAtUtc: DateTime.utc(2026, 10, 22),
    );

Recipe _recipeFor(
  RestorativeMaterial material,
  Map<ToothRegion, RegionAnalysis> regions,
  ShadeLibrary library,
  ShadeAdjacency adjacency,
) {
  const builder = RecipeBuilder();
  return builder.build(
    material: material,
    regions: regions,
    library: library,
    adjacency: adjacency,
    layeringRules: _rules,
  );
}

/// A minimal rule table, so the composite golden does not depend on an asset.
final _rules = LayeringRuleTable.fromJson(const {
  'schemaVersion': 1,
  'id': 'golden_fixture',
  'enamelRules': [
    {
      'id': 'pronouncedOpalescence',
      'when': {'incisalLightnessMin': 74.0, 'blueShiftMax': -4.0},
      'enamel': 'opalescent',
    },
    {'id': 'default', 'when': <String, Object?>{}, 'enamel': 'universal'},
  ],
});
