/// Integer helpers that behave identically on the Dart VM and on the web.
///
/// On the web, integers are JavaScript numbers, exact only within ±2^53.
/// Every value that affects simulation state must stay inside that range.
library;

/// The largest integer that is exact on every platform (2^53 − 1).
const int maxSafeInt = 9007199254740991;

bool isSafeInt(int value) => value >= -maxSafeInt && value <= maxSafeInt;

/// Returns [value], asserting in debug builds that it is within ±2^53.
int checkedSafe(int value) {
  assert(isSafeInt(value), '$value is outside the safe integer range');
  return value;
}

/// The largest integer whose square is at most [n], for a safe [n] ≥ 0.
int isqrt(int n) {
  assert(n >= 0 && isSafeInt(n), 'no integer square root of $n');
  if (n < 2) return n;
  var root = n;
  var next = (root + 1) ~/ 2;
  while (next < root) {
    root = next;
    next = (root + n ~/ root) ~/ 2;
  }
  return root;
}

/// Returns `a × b ÷ d` rounded half away from zero, without any intermediate
/// result leaving the safe range.
///
/// The larger factor is split as `q·d + r`. Where `2·d·min(|a|, |b|)` stays
/// under 2^53, `r` times the smaller factor is divided at once; past that,
/// as a game's sums grow, it is worked out by doubling (see
/// [_productOver]), to the same result. The result itself must be a safe
/// integer.
int mulDivRound(int a, int b, int d) {
  assert(d > 0 && d <= maxSafeInt ~/ 2, 'divisor $d is out of range');
  assert(isSafeInt(a) && isSafeInt(b), 'factors must be safe integers');
  var large = a.abs();
  var small = b.abs();
  if (small > large) {
    final swap = large;
    large = small;
    small = swap;
  }
  final quotient = large ~/ d;
  final remainder = large - quotient * d;
  final int part;
  if (small <= (maxSafeInt - d) ~/ (2 * d)) {
    part = (2 * remainder * small + d) ~/ (2 * d);
  } else {
    final (over, rest) = _productOver(remainder, small, d);
    part = 2 * rest >= d ? over + 1 : over;
  }
  final magnitude = checkedSafe(quotient * small + part);
  return (a < 0) != (b < 0) ? -magnitude : magnitude;
}

/// Returns `a × b ÷ d` truncated toward zero, as `(a * b) ~/ d` is, without
/// any intermediate result leaving the safe range: for shares of a sum by
/// two sums of money, whose product passes 2^53 long before either does.
/// The result itself must be a safe integer.
int mulDivTruncated(int a, int b, int d) {
  assert(d > 0 && d <= maxSafeInt ~/ 2, 'divisor $d is out of range');
  assert(isSafeInt(a) && isSafeInt(b), 'factors must be safe integers');
  var large = a.abs();
  var small = b.abs();
  if (small > large) {
    final swap = large;
    large = small;
    small = swap;
  }
  final quotient = large ~/ d;
  final remainder = large - quotient * d;
  final part = small <= maxSafeInt ~/ d
      ? remainder * small ~/ d
      : _productOver(remainder, small, d).$1;
  final magnitude = checkedSafe(quotient * small + part);
  return (a < 0) != (b < 0) ? -magnitude : magnitude;
}

/// `r × s ÷ d` as a quotient and what remains, for `0 ≤ r < d ≤ 2^52` and
/// a safe `s ≥ 0`, by doubling: the product is built a bit of [s] at a time
/// as a quotient and a remainder below [d], so nothing passes `2·d`. Only
/// `~/`, `+` and comparisons, so it is the same on every platform.
(int, int) _productOver(int r, int s, int d) {
  var bit = 1;
  while (bit <= s ~/ 2) {
    bit *= 2;
  }
  var quotient = 0;
  var rest = 0;
  var left = s;
  for (; bit > 0; bit ~/= 2) {
    quotient *= 2;
    rest *= 2;
    if (rest >= d) {
      rest -= d;
      quotient++;
    }
    if (left >= bit) {
      left -= bit;
      rest += r;
      if (rest >= d) {
        rest -= d;
        quotient++;
      }
    }
  }
  return (quotient, rest);
}
