import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;
import 'package:nuans/core/formatting/clinical_formats.dart';
import 'package:nuans/core/l10n/clinical_strings.dart';
import 'package:nuans/l10n/app_localizations.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shade_core/shade_core.dart';

/// Everything one report needs. Assembled by the report service so that the
/// builder itself touches no repository and can be exercised from a test with
/// a literal.
class ReportData {
  const ReportData({
    required this.patientCode,
    required this.toothNumber,
    required this.material,
    required this.shadeSystem,
    required this.capturedAtUtc,
    required this.regions,
    required this.recipe,
    required this.confidence,
    required this.captureFormat,
    required this.deviceModel,
    required this.lensId,
    required this.libraryId,
    required this.libraryClinicalCoverage,
    this.profileMeanDeltaE,
    this.profileMaxDeltaE,
    this.profileCreatedAtUtc,
    this.imageBytes,
    this.toothVersusTabDeltaE,
  });

  final String patientCode;
  final FdiToothNumber toothNumber;
  final RestorativeMaterial material;
  final ShadeSystem shadeSystem;
  final DateTime capturedAtUtc;
  final Map<ToothRegion, RegionAnalysis> regions;
  final Recipe recipe;
  final ConfidenceScore confidence;

  /// `true` when the capture was Bayer RAW.
  final bool captureFormat;

  final String deviceModel;
  final String lensId;
  final String libraryId;
  final double libraryClinicalCoverage;

  final double? profileMeanDeltaE;

  /// The worst patch of the chart fit. Reported next to the mean because a good
  /// mean with one bad patch is a different situation from an evenly mediocre
  /// fit, and only the second is a reason to re-shoot.
  final double? profileMaxDeltaE;

  final DateTime? profileCreatedAtUtc;

  /// The capture, with the region outlines already drawn on it.
  final Uint8List? imageBytes;

  /// The relative-mode result: the difference between the tooth and the tab the
  /// clinician was holding. Depends on no library, so it is reported first when
  /// it exists.
  final double? toothVersusTabDeltaE;
}

/// Builds the laboratory report.
///
/// Two things make this more than a layout exercise.
///
/// **The language is chosen per report, not per app.** A Turkish-speaking
/// clinician sends an English report to a laboratory abroad, so the builder
/// resolves its own localisations for the requested locale instead of reading
/// them from a widget tree.
///
/// **The font is embedded.** The `pdf` package's built-in standard fonts have
/// no glyphs for ç, ğ, ı, İ, ö, ş or ü, so a Turkish report built on them comes
/// out with holes exactly where the clinical terms are. Noto Sans travels
/// inside the document, so it renders the same on a laboratory's machine that
/// has never heard of it.
class PdfReportBuilder {
  const PdfReportBuilder({this.fontLoader = _loadBundledFonts});

  final Future<ReportFonts> Function() fontLoader;

  /// Renders the report in [locale].
  Future<Uint8List> build({
    required ReportData data,
    required Locale locale,
  }) async {
    final strings = await localizationsFor(locale);
    final fonts = await fontLoader();
    final tag = locale.toLanguageTag();

    final document = pw.Document(
      title: '${strings.appName} - ${data.patientCode}',
      // No author or creator: the document goes to a third party and the
      // clinician's own name is not needed to read it.
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        fontFallback: [fonts.regular],
      ),
    )..addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 48),
          header: (context) => _header(strings, data, tag),
          footer: (context) => _footer(strings, context, tag),
          build: (context) => [
            _confidenceBanner(strings, data, tag),
            pw.SizedBox(height: 12),
            _measurementTable(strings, data, tag),
            pw.SizedBox(height: 16),
            if (data.imageBytes != null) ...[
              pw.Image(
                pw.MemoryImage(data.imageBytes!),
                height: 220,
              ),
              pw.SizedBox(height: 16),
            ],
            _regionsTable(strings, data, tag),
            pw.SizedBox(height: 16),
            _recipeSection(strings, data, tag),
            pw.SizedBox(height: 16),
            _calibrationSection(strings, data, tag),
            pw.SizedBox(height: 16),
            _disclaimers(strings, data),
          ],
        ),
      );
    return Uint8List.fromList(await document.save());
  }

  pw.Widget _header(AppLocalizations strings, ReportData data, String tag) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  strings.appName,
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  strings.appTagline,
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Text(
              ClinicalFormats.dateTime(data.capturedAtUtc, tag),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );

  pw.Widget _footer(
    AppLocalizations strings,
    pw.Context context,
    String tag,
  ) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            strings.reportGeneratedBy(strings.appName, DateTime.now()),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            strings.reportPageOf(context.pageNumber, context.pagesCount),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      );

  /// The confidence, at the top, before any shade name.
  ///
  /// Placed first on purpose. A technician who reads "A3" and starts building
  /// has lost the only information that says how much the name is worth.
  pw.Widget _confidenceBanner(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) {
    final band = data.confidence.band;
    final colour = switch (band) {
      ConfidenceBand.high => PdfColors.green50,
      ConfidenceBand.medium => PdfColors.amber50,
      ConfidenceBand.low => PdfColors.red50,
    };
    final border = switch (band) {
      ConfidenceBand.high => PdfColors.green700,
      ConfidenceBand.medium => PdfColors.amber800,
      ConfidenceBand.low => PdfColors.red700,
    };
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: colour,
        border: pw.Border.all(color: border, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${strings.confidenceLabel}: ${strings.confidenceBand(band)}',
            style: const pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            strings.confidenceWeakestTerm(
              strings.confidenceTerm(data.confidence.weakestTerm.name),
            ),
            style: const pw.TextStyle(fontSize: 8),
          ),
          for (final reason in data.confidence.overrides)
            pw.Text(
              '· ${strings.confidenceOverride(reason)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    );
  }

  pw.Widget _measurementTable(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) =>
      _section(strings.reportHeaderMeasurement, [
        _row(strings.reportFieldPatientCode, data.patientCode),
        _row(strings.reportFieldTooth, data.toothNumber.code),
        _row(strings.reportFieldMaterial, strings.material(data.material)),
        _row(
          strings.reportFieldShadeSystem,
          strings.shadeSystem(data.shadeSystem),
        ),
        _row(
          strings.reportFieldCapturedAt,
          ClinicalFormats.dateTime(data.capturedAtUtc, tag),
        ),
        _row(
          strings.reportFieldCaptureMode,
          data.captureFormat
              ? strings.reportCaptureModeRaw
              : strings.reportCaptureModeProcessed,
        ),
        if (data.toothVersusTabDeltaE != null)
          _row(
            strings.shadeToothVsTab,
            strings.deltaEValue(data.toothVersusTabDeltaE!),
          ),
      ]);

  pw.Widget _regionsTable(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) =>
      _section(strings.reportHeaderRegions, [
        pw.TableHelper.fromTextArray(
          headerStyle: const pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignment: pw.Alignment.centerLeft,
          headers: [
            '',
            strings.reportFieldLabValues,
            strings.bestMatchLabel,
            strings.deltaEValue(0).split(' ').first,
            strings.alternativesLabel,
          ],
          data: [
            for (final region in ToothRegion.values)
              if (data.regions[region] case final analysis?)
                [
                  strings.toothRegion(region),
                  _labCell(analysis.reduction.lab, tag),
                  analysis.best.entry.code,
                  ClinicalFormats.deltaE(analysis.best.deltaE2000, tag),
                  analysis.matches.skip(1).map((m) => m.entry.code).join(', '),
                ],
          ],
        ),
        pw.SizedBox(height: 6),
        for (final region in ToothRegion.values)
          if (data.regions[region] case final analysis?)
            pw.Bullet(
              text: '${strings.toothRegion(region)}: '
                  '${strings.shadeComparison(analysis.best)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
      ]);

  String _labCell(LabColor lab, String tag) =>
      '${ClinicalFormats.labComponent(lab.lightness, tag)} / '
      '${ClinicalFormats.labComponent(lab.a, tag)} / '
      '${ClinicalFormats.labComponent(lab.b, tag)}';

  pw.Widget _recipeSection(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) {
    final recipe = data.recipe;
    final rows = <pw.Widget>[];
    switch (recipe) {
      case MetalCeramicRecipe(:final layers):
        for (final layer in layers) {
          rows.add(
            _row(
              strings.ceramicLayerRole(layer.role),
              strings.ceramicLayerComposition(layer),
            ),
          );
        }
      case ZirconiaRecipe(
          :final block,
          :final alternatives,
          :final cervicalStain,
        ):
        rows.add(_row(strings.zirconiaBlockLabel, block.code));
        if (alternatives.isNotEmpty) {
          rows.add(
            _row(
              strings.alternativesLabel,
              alternatives.map((e) => e.code).join(', '),
            ),
          );
        }
        if (cervicalStain != null) {
          rows.add(_row(strings.zirconiaStainLabel, cervicalStain.code));
        }
      case CompositeRecipe(:final dentin, :final enamel):
        rows
          ..add(_row(strings.compositeDentinLabel, dentin.code))
          ..add(
            _row(strings.compositeEnamelLabel, strings.enamelKind(enamel)),
          )
          ..add(
            pw.Text(
              strings.translucencyEstimated,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          );
    }
    for (final note in recipe.gradientNotes) {
      rows.add(
        pw.Bullet(
          text: strings.gradientNote(note),
          style: const pw.TextStyle(fontSize: 8),
        ),
      );
    }
    rows
      ..add(pw.SizedBox(height: 4))
      ..add(
        pw.Text(
          strings.recipeMixingModelNote,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
      );
    return _section(strings.reportHeaderRecipe, rows);
  }

  /// The provenance of the numbers above.
  ///
  /// Included because a laboratory receiving a shade name has no other way to
  /// know whether it came from a calibrated device and a measured guide, or
  /// from a manufacturer matrix and a scaffold.
  pw.Widget _calibrationSection(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) =>
      _section(strings.reportHeaderCalibration, [
        _row(strings.reportFieldDevice, '${data.deviceModel} / ${data.lensId}'),
        if (data.profileMeanDeltaE != null && data.profileCreatedAtUtc != null)
          _row(
            strings.deviceProfileTitle,
            _profileSummary(strings, data, tag),
          )
        else
          _row(strings.deviceProfileTitle, strings.deviceProfileMissing),
        _row(
          strings.settingsShadeLibraries,
          '${data.libraryId} · '
          '${strings.clinicalCoverage(data.libraryClinicalCoverage)}',
        ),
      ]);

  String _profileSummary(
    AppLocalizations strings,
    ReportData data,
    String tag,
  ) {
    final quality = strings.deviceProfileQuality(
      data.profileMeanDeltaE!,
      // The max, not the mean again.
      data.profileMaxDeltaE ?? data.profileMeanDeltaE!,
    );
    final date = ClinicalFormats.date(data.profileCreatedAtUtc!, tag);
    return '$quality · $date';
  }

  pw.Widget _disclaimers(AppLocalizations strings, ReportData data) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              strings.recipeDisclaimer,
              style: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            if (data.libraryClinicalCoverage < 1)
              pw.Text(
                strings.placeholderLibraryWarning,
                style: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              strings.appLegalDisclaimer,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );

  pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Divider(height: 6, thickness: 0.4),
          ...children,
        ],
      );

  pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(
                label,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
            ),
          ],
        ),
      );
}

/// The fonts a report is built with.
class ReportFonts {
  const ReportFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

/// Loads Noto Sans out of the asset bundle.
///
/// Must be the embedded font and not a standard PDF font: the standard set has
/// no Turkish glyphs, so `Ölçüm` would render as `lçüm` with the accented
/// characters dropped, and nobody reading the report would know a character had
/// gone missing rather than been left out.
Future<ReportFonts> _loadBundledFonts() async => ReportFonts(
      regular: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      ),
      bold: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      ),
    );
