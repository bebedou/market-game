import 'package:engine/src/core/rng.dart';
import 'package:engine/src/core/safe_int.dart';
import 'package:test/test.dart';

/// Exact `round(a × b ÷ d)`, half away from zero, computed with BigInt.
int referenceMulDivRound(int a, int b, int d) {
  final product = BigInt.from(a) * BigInt.from(b);
  final divisor = BigInt.from(d);
  final magnitude =
      (product.abs() * BigInt.two + divisor) ~/ (divisor * BigInt.two);
  return (product.isNegative ? -magnitude : magnitude).toInt();
}

/// A uniform value in `[0, 2^bits)` for `bits` up to 53, built 21 bits at a
/// time so no intermediate exceeds 2^53.
int randomBits(Rng rng, int bits) {
  var value = 0;
  for (var remaining = bits; remaining > 0; remaining -= 21) {
    final take = remaining < 21 ? remaining : 21;
    value = value * (1 << take) + rng.nextInt(1 << take);
  }
  return value;
}

void main() {
  group('mulDivRound', () {
    test('rounds half away from zero', () {
      expect(mulDivRound(5, 1, 2), 3);
      expect(mulDivRound(-5, 1, 2), -3);
      expect(mulDivRound(3, 1, 2), 2);
      expect(mulDivRound(1, 1, 3), 0);
      expect(mulDivRound(2, 1, 3), 1);
      expect(mulDivRound(-2, 1, 3), -1);
      expect(mulDivRound(7, -3, 2), -11);
      expect(mulDivRound(0, -3, 2), 0);
    });

    test('is exact at the edge of the safe range', () {
      expect(mulDivRound(maxSafeInt, 1, 1), maxSafeInt);
      expect(mulDivRound(-maxSafeInt, 1, 1), -maxSafeInt);
      expect(mulDivRound(maxSafeInt, 10000, 10000), maxSafeInt);
      expect(mulDivRound(maxSafeInt - 1, 3, 7), 3860228252031853);
    });

    test('matches a BigInt reference on generated cases', () {
      var checked = 0;
      for (var i = 0; i < 20000; i++) {
        final rng = Rng.keyed(1, 1, 0, i);
        final d = 1 + randomBits(rng, 1 + rng.nextInt(24));
        final limit = (maxSafeInt - d) ~/ (2 * d);
        final large = randomBits(rng, rng.nextInt(54));
        final small = randomBits(rng, rng.nextInt(54)) % (limit + 1);
        final a = rng.nextInt(2) == 0 ? -large : large;
        final b = rng.nextInt(2) == 0 ? -small : small;
        final expected = referenceMulDivRound(a, b, d);
        if (!isSafeInt(expected)) continue;
        expect(mulDivRound(a, b, d), expected, reason: '$a × $b ÷ $d');
        expect(mulDivRound(b, a, d), expected, reason: '$b × $a ÷ $d');
        checked++;
      }
      expect(checked, greaterThan(5000));
    });

    test('asserts when the result leaves the safe range', () {
      expect(
        () => mulDivRound(maxSafeInt, 2, 1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
