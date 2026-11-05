/// Decimal text conversion without floating point, for content files and
/// debug output.
library;

import 'safe_int.dart';

final _decimalPattern = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$');

/// Parses text such as `"-12.34"` into an integer count of 10^-[decimals]
/// units. Throws a [FormatException] for malformed text, more than [decimals]
/// decimal places, or a value outside the safe integer range.
int parseDecimal(String text, int decimals) {
  final match = _decimalPattern.firstMatch(text);
  if (match == null) {
    throw FormatException('Not a decimal number', text);
  }
  final fraction = match.group(3) ?? '';
  if (fraction.length > decimals) {
    throw FormatException('More than $decimals decimal places', text);
  }
  final value = int.parse(match.group(2)! + fraction.padRight(decimals, '0'));
  if (!isSafeInt(value)) {
    throw FormatException('Outside the safe integer range', text);
  }
  return match.group(1) == '-' ? -value : value;
}

/// Formats an integer count of 10^-[decimals] units, e.g. `(-1234, 2)` gives
/// `"-12.34"`.
String formatDecimal(int units, int decimals) {
  final digits = units.abs().toString().padLeft(decimals + 1, '0');
  final sign = units < 0 ? '-' : '';
  if (decimals == 0) return '$sign$digits';
  final split = digits.length - decimals;
  return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
}
