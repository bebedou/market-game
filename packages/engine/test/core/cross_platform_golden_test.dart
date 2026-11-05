import 'package:engine/engine.dart';
import 'package:engine/src/core/exp_neg.dart';
import 'package:engine/src/core/hash32.dart';
import 'package:engine/src/core/rng.dart';
import 'package:test/test.dart';

/// Runs every core primitive over many generated inputs and hashes the
/// results. The committed digest must match on the VM and on Node: if it
/// changes, either a primitive's behavior changed (update the digest
/// deliberately) or a platform difference crept in (fix it).
void main() {
  test('core primitives produce the committed digest', () {
    final digest = Hash32();
    for (var day = 0; day < 2000; day++) {
      final rng = Rng.keyed(20261026, 7, day, day * 31);
      final price = Money(
        rng.nextInt(0x200000) * 0x100000000 + rng.nextUint32(),
      );
      final rate = Fx.raw(rng.nextInt(2 * Fx.scale)) - Fx.one;
      final share = rng.nextFx();
      digest
        ..addInt(price.times(rate).cents)
        ..addInt(Money(price.cents ~/ 1000).timesInt(rng.nextInt(1000)).cents)
        ..addInt((rate * share).raw)
        ..addInt(share.raw == 0 ? 0 : rate.div(share).raw)
        ..addInt(expNeg(rate.abs().timesInt(9)).raw)
        ..addInt(rate.roundToInt())
        ..addInt(rng.chance(share) ? 1 : 0);
    }
    expect(digest.finish(), 0xcf49013a);
  });
}
