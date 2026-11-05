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
/// The larger factor is split as `q·d + r`, so the smaller factor must satisfy
/// `2·d·min(|a|, |b|) < 2^53`. The result itself must be a safe integer.
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
  assert(
    small <= (maxSafeInt - d) ~/ (2 * d),
    'factor $small is too large for divisor $d',
  );
  final quotient = large ~/ d;
  final remainder = large - quotient * d;
  final magnitude = checkedSafe(
    quotient * small + (2 * remainder * small + d) ~/ (2 * d),
  );
  return (a < 0) != (b < 0) ? -magnitude : magnitude;
}
