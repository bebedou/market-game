import 'decimal.dart';
import 'safe_int.dart';

/// A fixed-point number with four decimal places, stored as an integer.
///
/// Used for rates, shares, probabilities, loyalty and elasticities:
/// `Fx.raw(1500)` is 0.15. Products and quotients round half away from zero.
extension type const Fx.raw(int raw) {
  static const int decimals = 4;
  static const int scale = 10000;
  static const Fx zero = Fx.raw(0);
  static const Fx one = Fx.raw(scale);

  Fx.fromInt(int value) : raw = checkedSafe(value * scale);

  /// Parses text such as `"0.15"`, with at most four decimal places.
  factory Fx.parse(String text) => Fx.raw(parseDecimal(text, decimals));

  Fx operator +(Fx other) => Fx.raw(checkedSafe(raw + other.raw));
  Fx operator -(Fx other) => Fx.raw(checkedSafe(raw - other.raw));
  Fx operator -() => Fx.raw(-raw);
  Fx operator *(Fx other) => Fx.raw(mulDivRound(raw, other.raw, scale));

  /// Division, as a method: the engine bans the `/` operator because on
  /// integers it produces a double.
  Fx div(Fx other) => other.raw < 0
      ? Fx.raw(-mulDivRound(raw, scale, -other.raw))
      : Fx.raw(mulDivRound(raw, scale, other.raw));

  Fx timesInt(int factor) => Fx.raw(checkedSafe(raw * factor));

  /// The nearest integer, rounding half away from zero.
  int roundToInt() => mulDivRound(raw, 1, scale);

  bool operator <(Fx other) => raw < other.raw;
  bool operator <=(Fx other) => raw <= other.raw;
  bool operator >(Fx other) => raw > other.raw;
  bool operator >=(Fx other) => raw >= other.raw;

  bool get isNegative => raw < 0;
  Fx abs() => Fx.raw(raw.abs());

  String toDecimalString() => formatDecimal(raw, decimals);
}
