import 'bits32.dart';
import 'safe_int.dart';

/// An incremental 32-bit hash, compatible with MurmurHash3 (x86, 32-bit) over
/// little-endian 32-bit words.
///
/// Used for state hashes and RNG seeding instead of `hashCode`, which differs
/// between runs and platforms.
final class Hash32 {
  Hash32([int seed = 0]) : _hash = seed & mask32;

  int _hash;
  int _length = 0;

  /// Adds one unsigned 32-bit word.
  void addUint32(int word) {
    assert(word >= 0 && word <= mask32, '$word is not an unsigned 32-bit word');
    var k = imul32(word, 0xcc9e2d51);
    k = rotl32(k, 15);
    k = imul32(k, 0x1b873593);
    _hash = rotl32(_hash ^ k, 13);
    _hash = (imul32(_hash, 5) + 0xe6546b64) & mask32;
    _length += 4;
  }

  /// Adds any safe integer as two words: the low 32 bits, then the rest.
  void addInt(int value) {
    assert(isSafeInt(value), '$value is outside the safe integer range');
    final low = value & mask32;
    addUint32(low);
    addUint32(((value - low) ~/ 0x100000000) & mask32);
  }

  /// Adds a byte sequence: its length, then its bytes packed four to a word,
  /// little-endian.
  void addBytes(List<int> bytes) {
    addInt(bytes.length);
    for (var i = 0; i < bytes.length; i += 4) {
      final end = i + 4 < bytes.length ? i + 4 : bytes.length;
      var word = 0;
      for (var j = end - 1; j >= i; j--) {
        word = word * 0x100 + bytes[j];
      }
      addUint32(word);
    }
  }

  /// The hash of everything added so far.
  /// A hash with the same input so far, to continue separately.
  Hash32 copy() => Hash32()
    .._hash = _hash
    .._length = _length;

  int finish() {
    var h = _hash ^ (_length & mask32);
    h ^= h >>> 16;
    h = imul32(h, 0x85ebca6b);
    h ^= h >>> 13;
    h = imul32(h, 0xc2b2ae35);
    return h ^ (h >>> 16);
  }
}
