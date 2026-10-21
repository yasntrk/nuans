import 'dart:convert';
import 'dart:io';

import 'package:shade_core/shade_core.dart';
import 'package:test/test.dart';

/// The Lab values below are synthetic, not shade guide reference data.
void main() {
  ShadeEntry entry(String code, double l, double a, double b) => ShadeEntry(
        code: code,
        lab: LabColor(l, a, b),
        source: ShadeValueSource.clinicalMeasurement,
        measuredAtUtc: DateTime.utc(2026, 10, 22),
      );

  final library = ShadeLibrary(
    id: 'synthetic',
    system: ShadeSystem.classicalCompatible,
    entries: [
      entry('A1', 78, 0.5, 10),
      entry('A2', 75, 1.2, 14),
      entry('A3', 72, 2, 18),
      entry('A3.5', 70, 2.6, 20),
      entry('A4', 67, 3.2, 23),
      entry('B2', 76, 0.8, 12),
      entry('B3', 73, 1, 16),
    ],
  );
  final adjacency = ShadeAdjacency.forSystem(
    ShadeSystem.classicalCompatible,
    library.entries.map((e) => e.code).toList(),
  );
  const matcher = ShadeMatcher();
  const mixer = ShadeMixer();
  const builder = RecipeBuilder();

  RoiReduction reductionOf(LabColor lab) => RoiReduction(
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

  RegionAnalysis analysisOf(ToothRegion region, LabColor lab) {
    final matches = matcher.findNearest(target: lab, library: library);
    return RegionAnalysis(
      region: region,
      reduction: reductionOf(lab),
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

  /// A typical anterior tooth: more chromatic at the neck, lighter and bluer at
  /// the edge.
  Map<ToothRegion, RegionAnalysis> typicalTooth() => {
        ToothRegion.cervical: analysisOf(
          ToothRegion.cervical,
          const LabColor(70, 2.8, 21),
        ),
        ToothRegion.body: analysisOf(
          ToothRegion.body,
          const LabColor(73.5, 1.6, 16),
        ),
        ToothRegion.incisal: analysisOf(
          ToothRegion.incisal,
          const LabColor(76.5, 0.6, 10.5),
        ),
      };

  LayeringRuleTable rules() => LayeringRuleTable.fromJson(
        jsonDecode(
          File('../../assets/rules/composite_layering_rules.json')
              .readAsStringSync(),
        ) as Map<String, Object?>,
      );

  group('gradient notes', () {
    test('spots a more chromatic neck and a lighter, bluer edge', () {
      final notes = builder.gradientNotes(
        cervical: typicalTooth()[ToothRegion.cervical]!,
        body: typicalTooth()[ToothRegion.body]!,
        incisal: typicalTooth()[ToothRegion.incisal]!,
      );
      expect(notes, contains(GradientNote.cervicalMoreChromatic));
      expect(notes, contains(GradientNote.incisalLighter));
      expect(notes, contains(GradientNote.incisalMoreTranslucent));
      expect(notes, isNot(contains(GradientNote.uniform)));
    });

    test('reports uniform when there is no gradient to speak of', () {
      const flat = LabColor(73.5, 1.6, 16);
      final notes = builder.gradientNotes(
        cervical: analysisOf(ToothRegion.cervical, flat),
        body: analysisOf(ToothRegion.body, flat),
        incisal: analysisOf(ToothRegion.incisal, flat),
      );
      expect(notes, [GradientNote.uniform]);
    });

    test('the blue shift is incisal minus body', () {
      final regions = typicalTooth();
      expect(
        RecipeBuilder.blueShiftOf(
          body: regions[ToothRegion.body]!,
          incisal: regions[ToothRegion.incisal]!,
        ),
        closeTo(10.5 - 16.0, 1e-12),
      );
    });
  });

  group('metal-ceramic', () {
    test('produces an opaque, a dentin and an incisal layer', () {
      final recipe = builder.build(
        material: RestorativeMaterial.metalCeramic,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
      ) as MetalCeramicRecipe;
      expect(recipe.layers.map((l) => l.role), [
        CeramicLayerRole.opaque,
        CeramicLayerRole.dentin,
        CeramicLayerRole.incisal,
      ]);
      expect(recipe.requiresVerification, isTrue);
    });

    test('the opaque follows the body match, not the blended dentin target',
        () {
      final regions = typicalTooth();
      final recipe = builder.build(
        material: RestorativeMaterial.metalCeramic,
        regions: regions,
        library: library,
        adjacency: adjacency,
      ) as MetalCeramicRecipe;
      expect(recipe.opaque.components, hasLength(1));
      expect(
        recipe.opaque.components.first.entry.code,
        regions[ToothRegion.body]!.best.entry.code,
      );
    });

    test('the dentin target leans on the body but includes the cervical', () {
      // The dentin layer covers both thirds, so a build that ignored the
      // cervical measurement would be lighter than the finished crown.
      final recipe = builder.build(
        material: RestorativeMaterial.metalCeramic,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
      ) as MetalCeramicRecipe;
      final bodyOnly = builder.build(
        material: RestorativeMaterial.metalCeramic,
        regions: {
          ToothRegion.cervical:
              analysisOf(ToothRegion.cervical, const LabColor(73.5, 1.6, 16)),
          ToothRegion.body:
              analysisOf(ToothRegion.body, const LabColor(73.5, 1.6, 16)),
          ToothRegion.incisal:
              analysisOf(ToothRegion.incisal, const LabColor(76.5, 0.6, 10.5)),
        },
        library: library,
        adjacency: adjacency,
      ) as MetalCeramicRecipe;
      expect(
        recipe.dentin.toString(),
        isNot(bodyOnly.dentin.toString()),
      );
    });

    test('every layer records which region it came from', () {
      final recipe = builder.build(
        material: RestorativeMaterial.metalCeramic,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
      ) as MetalCeramicRecipe;
      expect(recipe.incisal.derivedFrom, ToothRegion.incisal);
      expect(recipe.opaque.derivedFrom, ToothRegion.body);
    });
  });

  group('zirconia', () {
    test('is a block choice plus alternatives, not a mixture', () {
      final recipe = builder.build(
        material: RestorativeMaterial.zirconia,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
      ) as ZirconiaRecipe;
      expect(recipe.block.code, isNotEmpty);
      expect(recipe.alternatives, hasLength(2));
      expect(
        recipe.alternatives.map((e) => e.code),
        isNot(contains(recipe.block.code)),
      );
    });

    test('suggests a cervical stain when the neck is more chromatic', () {
      final recipe = builder.build(
        material: RestorativeMaterial.zirconia,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
      ) as ZirconiaRecipe;
      expect(
        recipe.gradientNotes,
        contains(GradientNote.cervicalMoreChromatic),
      );
      expect(recipe.cervicalStain, isNotNull);
    });

    test('suggests no stain for a uniform tooth', () {
      const flat = LabColor(73.5, 1.6, 16);
      final recipe = builder.build(
        material: RestorativeMaterial.zirconia,
        regions: {
          for (final region in ToothRegion.values)
            region: analysisOf(region, flat),
        },
        library: library,
        adjacency: adjacency,
      ) as ZirconiaRecipe;
      expect(recipe.cervicalStain, isNull);
    });
  });

  group('composite', () {
    test('chooses a dentin and an enamel kind with the rule that fired', () {
      final recipe = builder.build(
        material: RestorativeMaterial.composite,
        regions: typicalTooth(),
        library: library,
        adjacency: adjacency,
        layeringRules: rules(),
      ) as CompositeRecipe;
      expect(recipe.dentin.code, isNotEmpty);
      expect(recipe.ruleId, isNotEmpty);
      expect(recipe.blueShift, closeTo(-5.5, 1e-9));
      // L* 76.5 with a 5.5 unit blue shift clears the opalescence rule, which
      // sits above the plain translucency rule: a pronounced blue shift with
      // the value held up is opalescence, not simple translucency.
      expect(recipe.ruleId, 'pronouncedOpalescence');
      expect(recipe.enamel, EnamelKind.opalescent);
    });

    test('weights chroma above the other terms when picking the dentin', () {
      // A target whose chroma matches A3 but whose lightness matches A1.
      final chromaOfA3 = library['A3']!.lab;
      final target = LabColor(
        library['A1']!.lab.lightness,
        chromaOfA3.a,
        chromaOfA3.b,
      );
      final chromaFirst =
          builder.selectCompositeDentin(target: target, library: library);
      const plainNearest = ShadeMatcher();
      final nearest = plainNearest.best(target: target, library: library).entry;
      // The two selections differ, which is the whole point of the weighting.
      expect(chromaFirst.code, 'A3');
      expect(nearest.code, isNot('A3'));
    });

    test('refuses to build without a rule table', () {
      expect(
        () => builder.build(
          material: RestorativeMaterial.composite,
          regions: typicalTooth(),
          library: library,
          adjacency: adjacency,
        ),
        throwsArgumentError,
      );
    });
  });

  group('input validation', () {
    test('refuses a missing region', () {
      expect(
        () => builder.build(
          material: RestorativeMaterial.zirconia,
          regions: {
            ToothRegion.body:
                analysisOf(ToothRegion.body, const LabColor(73, 1.6, 16)),
          },
          library: library,
          adjacency: adjacency,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a region that was rejected during reduction', () {
      final regions = typicalTooth();
      regions[ToothRegion.incisal] = RegionAnalysis(
        region: ToothRegion.incisal,
        reduction: const RoiReduction.rejected(
          reason: RoiRejectionReason.tooFewSamples,
          sampleCount: 40,
          acceptedSamples: 40,
          rejectedFraction: 0.1,
        ),
        matches: regions[ToothRegion.incisal]!.matches,
        mix: regions[ToothRegion.incisal]!.mix,
      );
      expect(
        () => builder.build(
          material: RestorativeMaterial.zirconia,
          regions: regions,
          library: library,
          adjacency: adjacency,
        ),
        throwsArgumentError,
      );
    });
  });
}
