import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shade_core/shade_core.dart';

/// A worked example, computed on the device by the real engine.
///
/// Not a mock. The Lab values below stand in for a capture, and everything
/// after that - matching, the mixture search, the recipe, the confidence score
/// - is the shipping code path running against the shipping shade library. So
/// this screen is also the cheapest end-to-end check that the engine works on
/// the device it was built for, which matters because every other test of it
/// runs on a desktop.
///
/// The three Lab values are a plausible anterior tooth: more chromatic at the
/// neck, lighter and bluer at the edge. They are a worked example and are
/// labelled as one in the interface.
class DemoMeasurement {
  const DemoMeasurement({
    required this.regions,
    required this.recipe,
    required this.confidence,
    required this.library,
  });

  static const Map<ToothRegion, LabColor> sampleLab = {
    ToothRegion.cervical: LabColor(70, 2.8, 21),
    ToothRegion.body: LabColor(73.5, 1.6, 16),
    ToothRegion.incisal: LabColor(76.5, 0.6, 10.5),
  };

  final Map<ToothRegion, RegionAnalysis> regions;
  final Recipe recipe;
  final ConfidenceScore confidence;
  final ShadeLibrary library;

  /// Builds the example for [material], loading the shipped assets.
  static Future<DemoMeasurement> build({
    required RestorativeMaterial material,
  }) async {
    final library = ShadeLibraryCodec.decode(
      jsonDecode(
        await rootBundle.loadString(
          'assets/shade_libraries/vita_classical_compatible.json',
        ),
      ) as Map<String, Object?>,
    );
    final rules = LayeringRuleTable.fromJson(
      jsonDecode(
        await rootBundle
            .loadString('assets/rules/composite_layering_rules.json'),
      ) as Map<String, Object?>,
    );
    final adjacency = ShadeAdjacency.forSystem(
      library.system,
      library.entries.map((e) => e.code).toList(),
    );

    const matcher = ShadeMatcher();
    const mixer = ShadeMixer();
    final regions = <ToothRegion, RegionAnalysis>{};
    for (final entry in sampleLab.entries) {
      final matches =
          matcher.findNearest(target: entry.value, library: library);
      regions[entry.key] = RegionAnalysis(
        region: entry.key,
        reduction: _reductionOf(entry.value),
        matches: matches,
        mix: mixer.search(
          target: entry.value,
          candidates: matches.map((m) => m.entry).toList(),
          library: library,
          adjacency: adjacency,
          bestSingleDeltaE: matches.first.deltaE2000,
        ),
      );
    }

    const builder = RecipeBuilder();
    final recipe = builder.build(
      material: material,
      regions: regions,
      library: library,
      adjacency: adjacency,
      layeringRules: rules,
    );

    const scorer = ConfidenceScorer();
    final confidence = scorer.score(
      // No device profile and no grey card in a worked example, so the score
      // comes out low with two hard overrides - which is the honest result and
      // a useful thing to show on the first screen a clinician ever sees.
      captureSource: CcmSource.srgbProcessed,
      profileScore: 0,
      grayCardValid: false,
      grayCardScore: 0,
      reduction: regions[ToothRegion.body]!.reduction,
      relativeMode: RelativeModeState.notUsed,
      bestMatchDeltaE: regions[ToothRegion.body]!.best.deltaE2000,
      acceptedFrameCount: 3,
    );

    return DemoMeasurement(
      regions: regions,
      recipe: recipe,
      confidence: confidence,
      library: library,
    );
  }

  /// A reduction standing in for a capture of this colour.
  static RoiReduction _reductionOf(LabColor lab) => RoiReduction(
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
      );
}
