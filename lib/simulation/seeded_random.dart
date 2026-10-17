/// Park–Miller PRNG with explicit serializable state. Products stay below 2^53,
/// so integer results also agree in JavaScript-compiled Dart.
class SeededRandom {
  SeededRandom(int seed) : _state = seed % (modulus - 1) + 1;
  SeededRandom.fromState(int state) : _state = state {
    if (state <= 0 || state >= modulus) {
      throw ArgumentError('Invalid random state.');
    }
  }

  static const modulus = 2147483647;
  int _state;
  int get state => _state;

  int nextInt(int upperBound) {
    if (upperBound <= 0) {
      throw ArgumentError('Bound must be positive.');
    }
    _state = _state * 16807 % modulus;
    return (_state - 1) % upperBound;
  }

  int roundRatio(int numerator, int denominator) {
    if (numerator < 0 || denominator <= 0) {
      throw ArgumentError('Invalid ratio.');
    }
    final remainder = numerator % denominator;
    return numerator ~/ denominator +
        (remainder > 0 && nextInt(denominator) < remainder ? 1 : 0);
  }

  void shuffle<T>(List<T> values) {
    for (var i = values.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final value = values[i];
      values[i] = values[j];
      values[j] = value;
    }
  }
}
