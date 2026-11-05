import '../core/fx.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../state/public_record.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The macro phase, on the first of each month. The business cycle may move
/// on to its next regime; inflation, the regime's nudged by how shelf prices
/// actually moved, compounds into the price index and, with real wage
/// growth, into the wage index; the central bank resets its rate.
final class MacroSystem implements TickSystem {
  const MacroSystem();

  /// Measured shelf-price inflation is capped at this, either way, before
  /// it feeds back.
  static final measuredCap = Fx.parse('0.20');

  @override
  void run(WorldState world, TickContext context) {
    if (!context.day.isFirstOfMonth ||
        context.day <= context.content.startDay) {
      return;
    }
    final def = context.content.macro;
    final macro = world.macro;
    var regime = def.regimes[macro.regime.index];
    macro.monthsInRegime++;
    if (context.rng(RngStream.macro, 0).nextInt(regime.meanMonths) == 0) {
      regime = def.regimes[(regime.id.index + 1) % def.regimes.length];
      macro
        ..regime = regime.id
        ..monthsInRegime = 0;
    }

    var inflation = regime.inflation;
    final level = retailLevel(world, context);
    if (level != null && macro.retailLevel > Fx.zero) {
      var measured = (level.div(macro.retailLevel) - Fx.one).timesInt(12);
      if (measured > measuredCap) measured = measuredCap;
      if (measured < -measuredCap) measured = -measuredCap;
      inflation += def.retailFeedback * (measured - inflation);
    }
    if (level != null) macro.retailLevel = level;
    var wageGrowth = inflation + regime.realWageGrowth;
    if (def.labour case final labour?) {
      final target = labour.unemploymentTarget(regime.outputGap);
      macro.unemployment += labour.adjustment * (target - macro.unemployment);
      // The wage Phillips curve: slack holds wages back.
      wageGrowth -=
          labour.phillipsSlope *
          (macro.unemployment - labour.naturalUnemployment);
    }
    macro
      ..inflation = inflation
      ..priceIndex += macro.priceIndex * _monthly(inflation)
      ..wageIndex += macro.wageIndex * _monthly(wageGrowth)
      ..policyRate = def.policyRate(inflation, regime);
    world.economicHistory.add((
      day: context.day,
      regime: macro.regime,
      priceIndex: macro.priceIndex,
      wageIndex: macro.wageIndex,
      inflation: macro.inflation,
      policyRate: macro.policyRate,
      unemployment: macro.unemployment,
    ));
    if (world.economicHistory.length > economicMonthsKept) {
      world.economicHistory.removeAt(0);
    }
  }

  static Fx _monthly(Fx annual) => Fx.raw(mulDivRound(annual.raw, 1, 12));
}

/// Shelf prices over base reference prices: for each product some open store
/// lists, its average shelf price over its reference, averaged across those
/// products. Null if nothing is listed anywhere.
Fx? retailLevel(WorldState world, TickContext context) {
  var sum = Fx.zero;
  var products = 0;
  for (final product in context.content.products) {
    var cents = 0;
    var stores = 0;
    for (final store in world.stores) {
      final price = store.prices[product.id.index];
      if (store.status != StoreStatus.open || price == null) continue;
      cents += price.cents;
      stores++;
    }
    if (stores == 0) continue;
    sum += Fx.raw(
      mulDivRound(cents, Fx.scale, stores * product.referencePrice.cents),
    );
    products++;
  }
  return products == 0 ? null : Fx.raw(sum.raw ~/ products);
}
