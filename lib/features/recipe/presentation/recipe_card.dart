import 'package:flutter/material.dart';
import 'package:nuans/core/l10n/clinical_strings.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:shade_core/shade_core.dart';

/// A material-specific recipe.
///
/// The three materials are genuinely different documents - a layering schedule,
/// a block choice, a two-layer plan - so this switches on the recipe type
/// rather than rendering one shape with empty fields.
///
/// Every variant ends with the verification note. `Recipe.requiresVerification`
/// is a field rather than a comment precisely so that a renderer has to
/// acknowledge it, and this is where that is acknowledged.
class RecipeCard extends StatelessWidget {
  const RecipeCard({required this.recipe, super.key});

  final Recipe recipe;

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
            // Both sides flexible, and the material label allowed to wrap.
            // A plain Text here overflowed: "Metal-ceramic" fits on a 360-wide
            // screen and "Metal destekli porselen" does not - by 20 pixels at
            // the default text scale and 117 at 1.3. The bilingual golden
            // tests are what caught it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child:
                      Text(strings.recipeTitle, style: textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.material(recipe.material),
                    style: textTheme.labelLarge,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ..._body(context, strings, textTheme),
            if (recipe.gradientNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final note in recipe.gradientNotes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('· '),
                      Expanded(
                        child: Text(
                          strings.gradientNote(note),
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            // Not optional, and not collapsible.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.recipeDisclaimer,
                    style: textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.recipeMixingModelNote,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppLocalizations strings,
    TextTheme textTheme,
  ) =>
      switch (recipe) {
        MetalCeramicRecipe(:final layers) => [
            for (final layer in layers)
              _row(
                textTheme,
                strings.ceramicLayerRole(layer.role),
                strings.ceramicLayerComposition(layer),
              ),
          ],
        ZirconiaRecipe(
          :final block,
          :final alternatives,
          :final cervicalStain,
        ) =>
          [
            _row(textTheme, strings.zirconiaBlockLabel, block.code),
            if (alternatives.isNotEmpty)
              _row(
                textTheme,
                strings.alternativesLabel,
                alternatives.map((e) => e.code).join(', '),
              ),
            if (cervicalStain != null)
              _row(textTheme, strings.zirconiaStainLabel, cervicalStain.code),
          ],
        CompositeRecipe(:final dentin, :final enamel) => [
            _row(textTheme, strings.compositeDentinLabel, dentin.code),
            _row(
              textTheme,
              strings.compositeEnamelLabel,
              strings.enamelKind(enamel),
            ),
            const SizedBox(height: 4),
            // Mandatory wherever a translucency statement appears: this version
            // infers it from a blue shift and makes no backing measurement.
            Text(
              strings.translucencyEstimated,
              style: textTheme.bodySmall,
            ),
          ],
      };

  Widget _row(TextTheme textTheme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: textTheme.bodySmall),
            ),
            Expanded(
              child: Text(
                value,
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

/// Why no mixture is being offered, when none is.
class MixDeclinedNote extends StatelessWidget {
  const MixDeclinedNote({required this.declined, super.key});

  final MixDeclined declined;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            strings.mixDeclined(declined.reason),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
