import 'decimal.dart';
import 'fx.dart';
import 'safe_int.dart';

/// An amount of money in integer cents.
///
/// Money is only ever multiplied by an [Fx] or a whole number, and the result
/// is rounded to the cent, half away from zero.
extension type const Money(int cents) {
  static const int decimals = 2;
  static const Money zero = Money(0);

  /// Parses text such as `"12.34"`, with at most two decimal places.
  factory Money.parse(String text) => Money(parseDecimal(text, decimals));

  Money operator +(Money other) => Money(checkedSafe(cents + other.cents));
  Money operator -(Money other) => Money(checkedSafe(cents - other.cents));
  Money operator -() => Money(-cents);

  /// This amount scaled by [factor], e.g. a price times a tax rate.
  Money times(Fx factor) => Money(mulDivRound(cents, factor.raw, Fx.scale));

  /// This amount times a whole number, e.g. a unit price times a quantity.
  Money timesInt(int factor) => Money(checkedSafe(cents * factor));

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  bool get isNegative => cents < 0;

  String toDecimalString() => formatDecimal(cents, decimals);
}
