import 'package:engine/src/core/hash32.dart';
import 'package:engine/src/core/rng.dart';
import 'package:test/test.dart';

/// Expected values come from an independent JavaScript implementation built
/// on Math.imul, which also reproduces the published MurmurHash3 and
/// xoshiro128** test vectors.
void main() {
  group('Hash32', () {
    int hashWords(int seed, List<int> words) {
      final hash = Hash32(seed);
      words.forEach(hash.addUint32);
      return hash.finish();
    }

    test('matches the MurmurHash3 x86_32 test vectors', () {
      expect(hashWords(0, []), 0x00000000);
      expect(hashWords(1, []), 0x514e28b7);
      expect(hashWords(0xffffffff, []), 0x81f16f39);
      expect(hashWords(0, [0]), 0x2362f9de);
      expect(hashWords(0, [0x87654321]), 0xf55b516b);
      expect(hashWords(0x5082edee, [0x87654321]), 0x2362f9de);
      expect(hashWords(0x9747b28c, [0x61616161]), 0x5a97808a);
      expect(hashWords(0, [0xffffffff]), 0x76293b50);
    });

    test('hashes negative and large integers identically everywhere', () {
      expect((Hash32()..addInt(-1)).finish(), 0x627564e8);
      expect(
        (Hash32()
              ..addInt(9007199254740991)
              ..addInt(-9007199254740991)
              ..addInt(0)
              ..addInt(4294967296))
            .finish(),
        0x2594e090,
      );
    });
  });

  group('Rng', () {
    List<int> draws(Rng rng, int count) => [
      for (var i = 0; i < count; i++) rng.nextUint32(),
    ];

    test('matches the xoshiro128** reference sequence', () {
      expect(draws(Rng.fromState(1, 2, 3, 4), 10), [
        11520, 0, 5927040, 70819200, 2031721883, //
        1637235492, 1287239034, 3734860849, 3729100597, 4258142804,
      ]);
    });

    test('derives keyed generators from (seed, stream, day, entity)', () {
      expect(draws(Rng.keyed(42, 1, 0, 0), 4), [
        1334654669,
        1592019912,
        2487542033,
        449491425,
      ]);
      expect(draws(Rng.keyed(-7, 3, 3650, 999999), 4), [
        1068848534,
        2658111574,
        3645900232,
        2106657115,
      ]);
      expect(draws(Rng.keyed(9007199254740991, 0, 1, -9007199254740991), 4), [
        1891680827,
        2698561637,
        2540674443,
        446432476,
      ]);
    });

    test('nextInt stays in range and is roughly uniform', () {
      final rng = Rng.keyed(7, 2, 0, 0);
      final counts = List.filled(6, 0);
      for (var i = 0; i < 60000; i++) {
        counts[rng.nextInt(6)]++;
      }
      for (final count in counts) {
        expect(count, inInclusiveRange(9500, 10500));
      }
    });

    test('nextInt covers both ends of its widest range', () {
      final rng = Rng.keyed(7, 3, 0, 0);
      var min = 0x200000, max = -1;
      for (var i = 0; i < 200000; i++) {
        final value = rng.nextInt(0x200000);
        if (value < min) min = value;
        if (value > max) max = value;
      }
      expect(min, lessThan(100));
      expect(max, greaterThan(0x200000 - 100));
      expect(max, lessThan(0x200000));
    });

    test('nextFx stays in [0, 1)', () {
      final rng = Rng.keyed(7, 4, 0, 0);
      for (var i = 0; i < 10000; i++) {
        final value = rng.nextFx().raw;
        expect(value, inInclusiveRange(0, 9999));
      }
    });
  });
}
