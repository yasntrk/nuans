import 'package:meta/meta.dart';
import 'package:shade_core/src/matching/shade_entry.dart';
import 'package:shade_core/src/matching/shade_match.dart';
import 'package:shade_core/src/mixing/shade_mixer.dart';
import 'package:shade_core/src/model/tooth_region.dart';
import 'package:shade_core/src/recipe/layering_rules.dart';
import 'package:shade_core/src/statistics/roi_reducer.dart';

/// Everything known about one region after measurement and matching.
@immutable
final class RegionAnalysis {
  const RegionAnalysis({
    required this.region,
    required this.reduction,
    required this.matches,
    required this.mix,
  });

  final ToothRegion region;
  final RoiReduction reduction;

  /// Nearest shades, closest first.
  final List<ShadeMatch> matches;

  /// The mixture search outcome for this region.
  final MixOutcome mix;

  ShadeMatch get best => matches.first;

  /// The mixture, when one was offered.
  MixResult? get offeredMix => switch (mix) {
        MixOffered(result: final result) => result,
        MixDeclined() => null,
      };
}

/// How a region's chroma or translucency differs from the body, as a machine
/// code the presentation layer turns into a sentence.
enum GradientNote {
  /// The cervical third is noticeably more chromatic than the body.
  cervicalMoreChromatic,

  /// The incisal third is noticeably lighter than the body.
  incisalLighter,

  /// The incisal third reads darker and bluer: the signature of translucency
  /// with nothing behind the edge.
  incisalMoreTranslucent,

  /// No gradient worth mentioning.
  uniform,
}

/// A layer of a fired ceramic schedule.
@immutable
final class CeramicLayer {
  const CeramicLayer({
    required this.role,
    required this.components,
    this.derivedFrom,
  });

  final CeramicLayerRole role;

  /// One component means a single powder; more than one means a mixture, in
  /// the whole-10% proportions a technician can weigh.
  final List<MixComponent> components;

  /// Which region the layer was derived from, for the report.
  final ToothRegion? derivedFrom;

  bool get isMixture => components.length > 1;

  @override
  String toString() =>
      '${role.name}: ${components.map((c) => c.toString()).join(' + ')}';
}

/// What a ceramic layer is for.
enum CeramicLayerRole {
  /// Masks the metal substructure. Carries no translucency.
  opaque,

  /// The body of the restoration, where the chroma lives.
  dentin,

  /// The incisal third, where the translucency lives.
  incisal,
}

/// A recipe is a starting point, never a final answer.
///
/// Every variant carries [requiresVerification] so that no presentation path
/// can render one without the note that it has to be confirmed with a trial
/// firing or a shade sample. The physical model behind the mixture is a
/// first-order approximation of a subtractive process, and the weights are mass
/// ratios rather than reflectance shares, so the proportions are a place to
/// start from rather than a formula to trust.
@immutable
sealed class Recipe {
  const Recipe({required this.material, required this.gradientNotes});

  final RestorativeMaterial material;

  /// Regional observations worth telling the technician about.
  final List<GradientNote> gradientNotes;

  /// Always true. Present as a field rather than as documentation so that a
  /// renderer has to acknowledge it.
  bool get requiresVerification => true;
}

/// Opaque, dentin and incisal powders for a metal-ceramic restoration.
@immutable
final class MetalCeramicRecipe extends Recipe {
  const MetalCeramicRecipe({
    required this.opaque,
    required this.dentin,
    required this.incisal,
    required super.gradientNotes,
  }) : super(material: RestorativeMaterial.metalCeramic);

  /// Derived from the body match, because the opaque sets the hue family the
  /// whole build sits in.
  final CeramicLayer opaque;

  /// Derived from the body and cervical measurements, which is where the
  /// chroma of the finished crown comes from.
  final CeramicLayer dentin;

  /// Derived from the incisal measurement.
  final CeramicLayer incisal;

  List<CeramicLayer> get layers => [opaque, dentin, incisal];
}

/// A block choice and a staining note for a zirconia restoration.
@immutable
final class ZirconiaRecipe extends Recipe {
  const ZirconiaRecipe({
    required this.block,
    required this.alternatives,
    required super.gradientNotes,
    this.cervicalStain,
  }) : super(material: RestorativeMaterial.zirconia);

  /// The closest block or pre-shaded blank.
  final ShadeEntry block;

  /// Next-best blocks, for when the first is not in stock.
  final List<ShadeEntry> alternatives;

  /// A more chromatic shade to stain the cervical third towards, when the
  /// measurement shows a gradient steep enough to be worth the step.
  final ShadeEntry? cervicalStain;
}

/// A dentin shade and an enamel selection for a direct composite.
@immutable
final class CompositeRecipe extends Recipe {
  const CompositeRecipe({
    required this.dentin,
    required this.enamel,
    required this.ruleId,
    required this.blueShift,
    required super.gradientNotes,
  }) : super(material: RestorativeMaterial.composite);

  /// Chosen on chroma first: a composite dentin that is a step off in
  /// lightness disappears under the enamel, while one that is a step off in
  /// chroma shows through it.
  final ShadeEntry dentin;

  final EnamelKind enamel;

  /// Which rule of the table fired, so the choice can be explained and the
  /// table can be tuned against real cases.
  final String ruleId;

  /// `b*(incisal) - b*(body)`, the quantity the enamel rule turned on.
  final double blueShift;
}
