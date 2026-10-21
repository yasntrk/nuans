import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuans/l10n/app_localizations.dart';

/// The locale and text-scale matrix every golden test runs over.
///
/// Both languages, because the failure these tests exist to catch is **layout
/// overflow**, not translation. Turkish clinical terms are systematically
/// longer than their English equivalents - "Klinik olarak kabul edilebilir"
/// against "Clinically acceptable", "Belirgin şekilde daha az doygun" against
/// "Markedly less saturated" - so a badge that fits in English is clipped in
/// Turkish, and only a run in both languages shows it.
///
/// Two text scales, because a clinician wearing loupes may well have the system
/// font enlarged, and a result screen that overflows at 1.3 is a result screen
/// that cannot be read in the operatory.
const List<Locale> goldenLocales = [Locale('tr'), Locale('en')];

const List<double> goldenTextScales = [1.0, 1.3];

/// Device sizes the goldens are captured at.
///
/// The small one is deliberately a modest phone: the camera screen has six
/// traffic lights, a shutter and three clinical hints to fit, and it has to fit
/// on the handset a clinic actually owns rather than the newest one.
const List<Size> goldenSizes = [
  Size(360, 690),
  Size(430, 932),
];

/// Loads the application's real fonts into the test binding.
///
/// Without this a widget test renders text in the placeholder font, where every
/// glyph is a filled box of the same width. A golden captured that way cannot
/// show the thing these tests exist to catch: that the Turkish label is longer
/// than the English one and overflows its badge. It also cannot show whether
/// ç, ğ, ı, İ, ö, ş and ü have glyphs at all.
Future<void> loadTestFonts() async {
  for (final family in <String, List<String>>{
    'NotoSans': [
      'assets/fonts/NotoSans-Regular.ttf',
      'assets/fonts/NotoSans-Medium.ttf',
      'assets/fonts/NotoSans-Bold.ttf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final asset in family.value) {
      loader.addFont(
        rootBundle.load(asset).then(
              (data) => ByteData.sublistView(
                data.buffer.asUint8List(),
              ),
            ),
      );
    }
    await loader.load();
  }
}

/// Wraps a widget with everything it needs to render in [locale].
Widget goldenHarness({
  required Widget child,
  required Locale locale,
  required double textScale,
  ThemeData? theme,
}) =>
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        locale: locale,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Scaffold(body: child),
      ),
    );

/// Runs [build] once per locale, text scale and size.
///
/// The golden file name carries all three, so a failure says which combination
/// broke rather than only that something did.
void forEachGoldenVariant(
  String name,
  Widget Function() build, {
  ThemeData? theme,
}) {
  for (final locale in goldenLocales) {
    for (final scale in goldenTextScales) {
      for (final size in goldenSizes) {
        final variant = '${name}_${locale.languageCode}'
            '_x${scale.toStringAsFixed(1)}'
            '_${size.width.toInt()}x${size.height.toInt()}';
        testWidgets(variant, (tester) async {
          await loadTestFonts();
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            goldenHarness(
              child: build(),
              locale: locale,
              textScale: scale,
              theme: theme,
            ),
          );
          await tester.pumpAndSettle();
          // Overflow is an error in the test harness, so a clipped badge fails
          // here rather than being quietly captured into the golden image.
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('images/$variant.png'),
          );
        });
      }
    }
  }
}
