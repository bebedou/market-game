import 'bits32.dart';
import 'fx.dart';
import 'hash32.dart';

/// Random stream identifiers for [Rng.keyed]. Never renumber one: that
/// changes every result drawn from it.
abstract final class RngStream {
  /// One household cohort's choices on a shopping trip.
  static const shopping = 1;

  /// The order in which a day's shoppers reach the stores.
  static const shoppingOrder = 2;

  /// Where households live relative to each site and when they like to
  /// shop, drawn once at the start.
  static const homes = 3;

  /// The errors in one market study.
  static const research = 4;

  /// The business cycle's turns.
  static const macro = 5;

  /// How far a store manager's judgment is off in one week.
  static const manager = 6;

  /// Which cohorts households join or leave each month.
  static const population = 7;

  /// Where each cohort's households stand in their segment's incomes.
  static const income = 8;

  /// How far households live from a site added to a saved game.
  static const sites = 9;

  /// Where a category added to a saved game starts each household's need.
  static const needs = 10;

  /// How far a director misjudges a site in one month.
  static const director = 11;

  /// The shared cycle's turns and when chains' openings and closings fall,
  /// in the countries run by formula.
  static const countries = 12;
}

/// Deterministic random numbers (xoshiro128**).
///
/// Generators are keyed by `(seed, stream, day, entity)` rather than drawn
/// from one shared sequence. Results then don't depend on iteration order, and
/// adding an entity or a system doesn't shift anyone else's draws.
final class Rng {
  Rng.fromState(int s0, int s1, int s2, int s3)
    : _s0 = s0 & mask32,
      _s1 = s1 & mask32,
      _s2 = s2 & mask32,
      _s3 = s3 & mask32 {
    if ((_s0 | _s1 | _s2 | _s3) == 0) {
      throw ArgumentError('xoshiro128** state must not be all zero');
    }
  }

  /// A generator for one entity on one day. [stream] identifies the subsystem
  /// and must be a stable constant: renumbering it changes every result.
  factory Rng.keyed(int seed, int stream, int day, int entity) {
    // The four words share their key, hashed once.
    final key = Hash32()
      ..addInt(seed)
      ..addInt(stream)
      ..addInt(day)
      ..addInt(entity);
    int word(int index) => (key.copy()..addUint32(index)).finish();
    final s0 = word(0), s1 = word(1), s2 = word(2), s3 = word(3);
    return Rng.fromState((s0 | s1 | s2 | s3) == 0 ? 1 : s0, s1, s2, s3);
  }

  int _s0, _s1, _s2, _s3;

  /// A uniformly distributed unsigned 32-bit integer.
  int nextUint32() {
    final result = imul32(rotl32(imul32(_s1, 5), 7), 9);
    final t = (_s1 << 9) & mask32;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = rotl32(_s3, 11);
    return result;
  }

  /// A uniformly distributed integer in `[0, bound)`, without modulo bias.
  /// [bound] must be between 1 and 2^21 so `draw × bound` stays below 2^53.
  int nextInt(int bound) {
    assert(bound > 0 && bound <= 0x200000, 'bound $bound is out of range');
    var product = nextUint32() * bound;
    var low = product % 0x100000000;
    if (low < bound) {
      final threshold = (0x100000000 - bound) % bound;
      while (low < threshold) {
        product = nextUint32() * bound;
        low = product % 0x100000000;
      }
    }
    return product ~/ 0x100000000;
  }

  /// A uniformly distributed value in `[0, 1)`.
  Fx nextFx() => Fx.raw(nextInt(Fx.scale));

  /// True with probability [p].
  bool chance(Fx p) => nextFx() < p;
}
