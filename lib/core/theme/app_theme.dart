import 'package:flutter/material.dart';
import 'package:nuans/features/capture/presentation/capture_overlay.dart';

/// The two themes this application needs, and why they are two.
///
/// **Clinical** is an ordinary light theme for the forms, the results and the
/// history: the screens a clinician reads at a desk.
///
/// **Capture** is a neutral dark grey theme for the camera screen alone. That
/// is not a style preference. During a measurement the screen is the second-
/// brightest thing in front of the patient: any colour on it reflects off the
/// tooth and into the reading, and any large bright area pushes the clinician's
/// own chromatic adaptation around at the moment they are judging a shade. So
/// the camera theme has zero saturation in its surfaces and spends colour only
/// where a pass or fail has to be unmissable.
abstract final class AppTheme {
  /// Traffic light colours, shared by both themes.
  ///
  /// Chosen to stay distinguishable for the most common colour vision
  /// deficiency: the pass and fail states differ in lightness as well as in
  /// hue, and every indicator carries a label and an icon rather than relying
  /// on colour alone.
  static const Color pass = Color(0xFF2E7D32);
  static const Color warn = Color(0xFFEF6C00);
  static const Color fail = Color(0xFFC62828);
  static const Color pending = Color(0xFF757575);

  static ThemeData clinical() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF37474F),
    );
    return _base(scheme);
  }

  /// The camera screen's theme.
  static ThemeData capture() {
    const surface = CaptureOverlayTheme.screenBackground;
    const scheme = ColorScheme.dark(
      // Deliberately grey rather than tinted: a blue-grey primary would still
      // put a colour cast on the patient's face.
      primary: Color(0xFFBDBDBD),
      onPrimary: Color(0xFF1A1A1A),
      secondary: Color(0xFF9E9E9E),
      onSecondary: Color(0xFF1A1A1A),
      onSurface: Color(0xFFE0E0E0),
      error: fail,
      onError: Color(0xFFFFFFFF),
    );
    return _base(scheme).copyWith(scaffoldBackgroundColor: surface);
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        // Clinical numbers are read, not skimmed: tabular figures keep a column
        // of delta E values aligned so two of them can be compared at a glance.
        textTheme: const TextTheme().apply(fontFamily: 'NotoSans'),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      );

  /// The colour for an acceptability band or a live check state.
  static Color statusColor(AppStatus status) => switch (status) {
        AppStatus.pass => pass,
        AppStatus.warn => warn,
        AppStatus.fail => fail,
        AppStatus.pending => pending,
      };

  /// The icon that carries the same information as the colour.
  ///
  /// Present so that the status survives being printed in greyscale, read by
  /// someone with a colour vision deficiency, or glanced at on a screen angled
  /// away from the viewer.
  static IconData statusIcon(AppStatus status) => switch (status) {
        AppStatus.pass => Icons.check_circle_outline,
        AppStatus.warn => Icons.error_outline,
        AppStatus.fail => Icons.cancel_outlined,
        AppStatus.pending => Icons.more_horiz,
      };
}

/// A three-state status plus "not yet known", shared by the live checks, the
/// acceptability bands and the confidence bands.
enum AppStatus { pass, warn, fail, pending }
