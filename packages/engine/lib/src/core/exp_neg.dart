import 'exp_table.g.dart';
import 'fx.dart';
import 'safe_int.dart';

/// `exp(-x)` for `x ≥ 0`, by linear interpolation on a precomputed table.
///
/// Within 0.0001 of `exp(-x)` rounded to four decimals. Returns zero beyond the
/// end of the table, where the true value is below Fx resolution.
Fx expNeg(Fx x) {
  assert(!x.isNegative, 'expNeg needs a non-negative argument, got $x');
  final last = expTable.length - 1;
  if (x.raw >= last * Fx.scale ~/ expTableStepsPerUnit) return Fx.zero;
  final position = x.raw * expTableStepsPerUnit;
  final index = position ~/ Fx.scale;
  final low = expTable[index];
  final high = expTable[index + 1];
  return Fx.raw(low + mulDivRound(high - low, position % Fx.scale, Fx.scale));
}
