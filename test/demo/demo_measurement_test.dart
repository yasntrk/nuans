import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/features/demo/demo_measurement.dart';
import 'package:shade_core/shade_core.dart';

/// Runs the worked example the way the application runs it: through the real
/// engine, against the shade library and rule table that actually ship.
///
/// This is the cheapest end-to-end check there is. Every other test of the
/// engine builds its fixtures in Dart; this one loads the assets, so it fails
/// if a shipped JSON file stops parsing, if a rule table loses its catch-all,
/// or if the library's shade codes stop matching the adjacency graph.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final material in RestorativeMaterial.values) {
    test('the worked example builds for ${material.name}', () async {
      final demo = await DemoMeasurement.build(material: material);

      expect(demo.regions, hasLength(3));
      for (final region in ToothRegion.values) {
        final analysis = demo.regions[region];
        expect(analysis, isNotNull, reason: region.name);
        expect(analysis!.reduction.isValid, isTrue);
        expect(analysis.matches, hasLength(3));
        // The match has to be inside the tooth gamut, or the scaffold library
        // and the sample colours have drifted apart.
        expect(analysis.best.deltaE2000, lessThan(10));
      }
      expect(demo.recipe.material, material);
      expect(demo.recipe.requiresVerification, isTrue);
      expect(demo.recipe.gradientNotes, isNotEmpty);
    });
  }

  test('the shipped library is the 16-shade one and is unverified', () async {
    final demo = await DemoMeasurement.build(
      material: RestorativeMaterial.metalCeramic,
    );
    expect(demo.library.length, 16);
    expect(demo.library.system, ShadeSystem.classicalCompatible);
    // The first screen a clinician ever sees rests on scaffold values, and has
    // to say so.
    expect(demo.library.containsPlaceholders, isTrue);
    expect(demo.library.clinicalCoverage, 0);
  });

  test('a worked example with no profile and no card scores low', () async {
    final demo = await DemoMeasurement.build(
      material: RestorativeMaterial.composite,
    );
    // Two hard overrides, so the band is pinned regardless of the weighted sum.
    expect(demo.confidence.band, ConfidenceBand.low);
    expect(
      demo.confidence.overrides,
      containsAll([
        ConfidenceOverride.noColorProfile,
        ConfidenceOverride.grayCardInvalid,
      ]),
    );
    expect(demo.confidence.wasOverridden, isTrue);
  });

  test('the sample colours describe a plausible anterior tooth', () async {
    final cervical = DemoMeasurement.sampleLab[ToothRegion.cervical]!;
    final body = DemoMeasurement.sampleLab[ToothRegion.body]!;
    final incisal = DemoMeasurement.sampleLab[ToothRegion.incisal]!;
    // Lighter towards the edge, more chromatic towards the neck: if the sample
    // stopped having a gradient, the recipe path would stop being exercised.
    expect(incisal.lightness, greaterThan(body.lightness));
    expect(body.lightness, greaterThan(cervical.lightness));
    expect(cervical.chroma, greaterThan(body.chroma));
    expect(body.chroma, greaterThan(incisal.chroma));
    // And bluer at the edge, which is what drives the enamel rule.
    expect(incisal.b, lessThan(body.b));
  });

  test('the metal-ceramic example produces three layers', () async {
    final demo = await DemoMeasurement.build(
      material: RestorativeMaterial.metalCeramic,
    );
    final recipe = demo.recipe as MetalCeramicRecipe;
    expect(recipe.layers, hasLength(3));
    for (final layer in recipe.layers) {
      expect(layer.components, isNotEmpty);
      // Whole ten per cent shares, or a technician cannot weigh them.
      final total =
          layer.components.map((c) => c.percent).reduce((a, b) => a + b);
      expect(total, 100);
      for (final component in layer.components) {
        expect(component.percent % 10, 0);
      }
    }
  });
}
