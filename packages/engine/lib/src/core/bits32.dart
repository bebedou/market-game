/// 32-bit integer operations with identical results on the Dart VM (64-bit
/// integers) and on the web (where bitwise operators work on 32 bits).
///
/// Inputs and outputs are unsigned 32-bit values.
library;

const int mask32 = 0xFFFFFFFF;

/// `(a × b) mod 2^32`, built from 16-bit halves so no product exceeds 2^53.
int imul32(int a, int b) {
  final aLow = a & 0xFFFF;
  final aHigh = (a >>> 16) & 0xFFFF;
  final bLow = b & 0xFFFF;
  final bHigh = (b >>> 16) & 0xFFFF;
  final cross = ((aHigh * bLow + aLow * bHigh) & 0xFFFF) * 0x10000;
  return (aLow * bLow + cross) & mask32;
}

/// Rotates [x] left by [bits], which must be between 1 and 31.
int rotl32(int x, int bits) => ((x << bits) | (x >>> (32 - bits))) & mask32;
