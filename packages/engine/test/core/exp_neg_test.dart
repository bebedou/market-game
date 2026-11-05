import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:engine/src/core/exp_neg.dart';
import 'package:test/test.dart';

void main() {
  test('expNeg is exact at table points', () {
    expect(expNeg(Fx.zero), Fx.one);
    expect(expNeg(Fx.one), Fx.parse('0.3679'));
    expect(expNeg(Fx.fromInt(2)), Fx.parse('0.1353'));
  });

  test('expNeg is within 0.0001 of exp(-x) and never increases', () {
    var previous = Fx.one;
    for (var raw = 0; raw <= 100000; raw += 7) {
      final x = Fx.raw(raw);
      final actual = expNeg(x);
      final expected = (math.exp(-raw / Fx.scale) * Fx.scale).round();
      expect(actual.raw, closeTo(expected, 1), reason: x.toDecimalString());
      expect(actual <= previous, isTrue, reason: x.toDecimalString());
      previous = actual;
    }
  });

  test('expNeg is zero beyond the table', () {
    expect(expNeg(Fx.fromInt(10)), Fx.zero);
    expect(expNeg(Fx.fromInt(1000000)), Fx.zero);
  });
}
