import 'package:meta/meta.dart';

import 'package:shade_core/src/colorimetry/delta_e_2000.dart';
import 'package:shade_core/src/colorimetry/lab_color.dart';
import 'package:shade_core/src/colorimetry/xyz_color.dart';
import 'package:shade_core/src/constants.dart';
import 'package:shade_core/src/matching/shade_entry.dart';
import 'package:shade_core/src/matching/shade_match.dart';
import 'package:shade_core/src/matching/shade_matcher.dart';
import 'package:shade_core/src/mixing/shade_adjacency.dart';
import 'package:shade_core/src/mixing/shade_mixer.dart';
import 'package:shade_core/src/model/tooth_region.dart';
import 'package:shade_core/src/recipe/layering_rules.dart';
import 'package:shade_core/src/recipe/recipe.dart';

/// Turns three measured regions into a material-specific starting recipe.
///
/// The three materials are not three renderings of one answer: a metal-ceramic
/// build is a layering schedule, a zirconia restoration is a block choice plus
/// a staining note, and a composite is a two-layer plan driven by a rule table.
/// They are derived from the same measurements and share nothing else.
@immutable
final class RecipeBuilder {
  const RecipeBuilder({
    this.matcher = const ShadeMatcher(),
    this.mixer = const ShadeMixer(),
    this.bodyWeight = kDentinBodyWeight,
    this.chromaWeight = kCompositeDentinChromaWeight,
    this.gradientChromaThreshold = kGradientChromaThreshold,
    this.gradientLightnessThreshold = kGradientLightnessThreshold,
    this.blueShiftThreshold = kTranslucencyBlueShiftThreshold,
  });

  final ShadeMatcher matcher;
  final ShadeMixer mixer;
  final double bodyWeight;
  final double chromaWeight;
  final double gradientChromaThreshold;
  final double gradientLightnessThreshold;
  final double blueShiftThreshold;

  /// Builds the recipe for [material].
  ///
  /// [regions] must hold all three regions; a missing one is an error rather
  /// than a default, because every recipe below reads at least two of them and
  /// silently substituting the body for a missing incisal would produce a
  /// plausible-looking recipe for a measurement that was never taken.
  Recipe build({
    required RestorativeMaterial material,
    required Map<ToothRegion, RegionAnalysis> regions,
    required ShadeLibrary library,
    required ShadeAdjacency adjacency,
    LayeringRuleTable? layeringRules,
  }) {
    for (final region in ToothRegion.values) {
      final analysis = regions[region];
      if (analysis == null) {
        throw ArgumentError.value(
          region.name,
          'regions',
          'every region must be measured before a recipe can be built',
        );
      }
      if (!analysis.reduction.isValid) {
        throw ArgumentError.value(
          region.name,
          'regions',
          'region was rejected during reduction and cannot drive a recipe',
        );
      }
    }
    final cervical = regions[ToothRegion.cervical]!;
    final body = regions[ToothRegion.body]!;
    final incisal = regions[ToothRegion.incisal]!;
    final notes = gradientNotes(
      cervical: cervical,
      body: body,
      incisal: incisal,
    );

    return switch (material) {
      RestorativeMaterial.metalCeramic => _metalCeramic(
          cervical: cervical,
          body: body,
          incisal: incisal,
          library: library,
          adjacency: adjacency,
          notes: notes,
        ),
      RestorativeMaterial.zirconia => _zirconia(
          cervical: cervical,
          body: body,
          notes: notes,
        ),
      RestorativeMaterial.composite => _composite(
          cervical: cervical,
          body: body,
          incisal: incisal,
          library: library,
          notes: notes,
          rules: layeringRules,
        ),
    };
  }

  /// Regional observations worth putting in front of a technician.
  @visibleForTesting
  List<GradientNote> gradientNotes({
    required RegionAnalysis cervical,
    required RegionAnalysis body,
    required RegionAnalysis incisal,
  }) {
    final notes = <GradientNote>[];
    final cervicalVsBody = DeltaE2000.between(
      reference: body.reduction.lab,
      sample: cervical.reduction.lab,
    );
    if (cervicalVsBody.weightedChroma > gradientChromaThreshold) {
      notes.add(GradientNote.cervicalMoreChromatic);
    }
    final incisalVsBody = DeltaE2000.between(
      reference: body.reduction.lab,
      sample: incisal.reduction.lab,
    );
    if (incisalVsBody.weightedLightness > gradientLightnessThreshold) {
      notes.add(GradientNote.incisalLighter);
    }
    if (blueShiftOf(body: body, incisal: incisal) < blueShiftThreshold) {
      notes.add(GradientNote.incisalMoreTranslucent);
    }
    if (notes.isEmpty) notes.add(GradientNote.uniform);
    return List<GradientNote>.unmodifiable(notes);
  }

  /// `b*(incisal) - b*(body)`.
  ///
  /// The heuristic stand-in for a translucency measurement this version does
  /// not make: with nothing behind the incisal edge, light that would have come
  /// back as yellow body colour is lost instead, and what returns is bluer.
  /// Because it is a heuristic, every translucency statement derived from it is
  /// labelled as an estimate in the interface.
  @visibleForTesting
  static double blueShiftOf({
    required RegionAnalysis body,
    required RegionAnalysis incisal,
  }) =>
      incisal.reduction.lab.b - body.reduction.lab.b;

  Recipe _metalCeramic({
    required RegionAnalysis cervical,
    required RegionAnalysis body,
    required RegionAnalysis incisal,
    required ShadeLibrary library,
    required ShadeAdjacency adjacency,
    required List<GradientNote> notes,
  }) {
    // The dentin layer covers the cervical and body thirds, so its target is a
    // blend of the two in linear XYZ, leaning on the body.
    final dentinTarget = XyzColor.weightedMean(
      [body.reduction.xyz, cervical.reduction.xyz],
      [bodyWeight, 1 - bodyWeight],
    ).toLab();
    final dentinMatches = matcher.findNearest(
      target: dentinTarget,
      library: library,
      count: 4,
    );
    final dentinMix = mixer.search(
      target: dentinTarget,
      candidates: dentinMatches.map((m) => m.entry).toList(),
      library: library,
      adjacency: adjacency,
      bestSingleDeltaE: dentinMatches.first.deltaE2000,
    );

    return MetalCeramicRecipe(
      // The opaque sets the hue family the whole build sits in, so it follows
      // the body match rather than the blended dentin target.
      opaque: CeramicLayer(
        role: CeramicLayerRole.opaque,
        components: [
          MixComponent(entry: body.best.entry, weight: 1),
        ],
        derivedFrom: ToothRegion.body,
      ),
      dentin: CeramicLayer(
        role: CeramicLayerRole.dentin,
        components: _componentsOf(dentinMix, fallback: dentinMatches.first),
        derivedFrom: ToothRegion.body,
      ),
      incisal: CeramicLayer(
        role: CeramicLayerRole.incisal,
        components: _componentsOf(incisal.mix, fallback: incisal.best),
        derivedFrom: ToothRegion.incisal,
      ),
      gradientNotes: notes,
    );
  }

  Recipe _zirconia({
    required RegionAnalysis cervical,
    required RegionAnalysis body,
    required List<GradientNote> notes,
  }) {
    // A monolithic restoration is one piece of material, so there is nothing to
    // mix: the answer is a block, and the gradient becomes a staining note.
    final alternatives = body.matches.skip(1).map((m) => m.entry).toList();
    final needsStain = notes.contains(GradientNote.cervicalMoreChromatic);
    return ZirconiaRecipe(
      block: body.best.entry,
      alternatives: List<ShadeEntry>.unmodifiable(alternatives),
      cervicalStain: needsStain ? cervical.best.entry : null,
      gradientNotes: notes,
    );
  }

  Recipe _composite({
    required RegionAnalysis cervical,
    required RegionAnalysis body,
    required RegionAnalysis incisal,
    required ShadeLibrary library,
    required List<GradientNote> notes,
    required LayeringRuleTable? rules,
  }) {
    if (rules == null) {
      throw ArgumentError.notNull('layeringRules');
    }
    final dentinTarget = XyzColor.weightedMean(
      [body.reduction.xyz, cervical.reduction.xyz],
      [bodyWeight, 1 - bodyWeight],
    ).toLab();
    final dentin =
        selectCompositeDentin(target: dentinTarget, library: library);

    final blueShift = blueShiftOf(body: body, incisal: incisal);
    final rule = rules.select(
      incisalLightness: incisal.reduction.lab.lightness,
      blueShift: blueShift,
      incisalChroma: incisal.reduction.lab.chroma,
    );
    if (rule == null) {
      throw StateError(
        'the layering rule table has no rule matching this measurement and no '
        'default; a table without a catch-all rule cannot be used',
      );
    }

    return CompositeRecipe(
      dentin: dentin,
      enamel: rule.enamel,
      ruleId: rule.id,
      blueShift: blueShift,
      gradientNotes: notes,
    );
  }

  /// Picks a composite dentin with chroma weighted above the other terms.
  ///
  /// Not a plain nearest-neighbour search: under a translucent enamel a dentin
  /// that is a step off in lightness is masked, while one that is a step off in
  /// chroma shows straight through. The cost function is the usual weighted
  /// CIEDE2000 decomposition with the chroma term multiplied, so it stays in
  /// perceptual units and the weighting is the only change.
  @visibleForTesting
  ShadeEntry selectCompositeDentin({
    required LabColor target,
    required ShadeLibrary library,
  }) {
    ShadeEntry? best;
    var bestCost = double.infinity;
    for (final entry in library.entries) {
      final delta = DeltaE2000.between(reference: entry.lab, sample: target);
      final cost = (chromaWeight * delta.weightedChroma).abs() +
          delta.weightedLightness.abs() +
          delta.weightedHue.abs();
      if (cost < bestCost ||
          (cost == bestCost &&
              best != null &&
              entry.code.compareTo(best.code) < 0)) {
        bestCost = cost;
        best = entry;
      }
    }
    return best!;
  }

  List<MixComponent> _componentsOf(
    MixOutcome outcome, {
    required ShadeMatch fallback,
  }) =>
      switch (outcome) {
        MixOffered(result: final result) => result.roundedComponents,
        MixDeclined() => [MixComponent(entry: fallback.entry, weight: 1)],
      };
}
