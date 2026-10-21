import 'package:intl/intl.dart';

/// Number and date formatting for the clinical screens.
///
/// Two different rules, deliberately:
///
/// * **on screen**, the user's locale decides. Turkish writes `ΔE00 1,2` and
///   English writes `ΔE00 1.2`, and a clinician reading the wrong separator
///   will misread the magnitude.
/// * **in data** - the database, exported files, JSON, logs - it is always a
///   dot decimal and always ISO 8601. A file whose number format depends on who
///   exported it cannot be parsed back, and a timestamp without an offset
///   cannot be compared across devices.
abstract final class ClinicalFormats {
  /// A colour difference, to one decimal place, in the reader's locale.
  ///
  /// One decimal and no more: the decision thresholds are 0.8 and 1.8, so a
  /// second decimal suggests a precision the measurement does not have.
  static String deltaE(double value, String locale) =>
      NumberFormat('0.0', locale).format(value);

  /// A Lab coordinate, to two decimal places.
  static String labComponent(double value, String locale) =>
      NumberFormat('0.00', locale).format(value);

  /// A share as a whole percentage.
  static String percent(double fraction, String locale) =>
      NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 0)
          .format(fraction);

  /// A date for display.
  static String date(DateTime utc, String locale) =>
      DateFormat.yMMMd(locale).format(utc.toLocal());

  /// A date and time for display.
  static String dateTime(DateTime utc, String locale) =>
      DateFormat.yMMMd(locale).add_Hm().format(utc.toLocal());

  /// The machine form of a number: always a dot, never grouped.
  ///
  /// Used for the database, exports and logs. `toStringAsFixed` is locale
  /// independent, which is exactly why it is the right call here and the wrong
  /// one on screen.
  static String machineNumber(double value, {int decimals = 4}) =>
      value.toStringAsFixed(decimals);

  /// The machine form of an instant: ISO 8601, UTC, with the `Z`.
  static String machineTimestamp(DateTime instant) =>
      instant.toUtc().toIso8601String();
}
