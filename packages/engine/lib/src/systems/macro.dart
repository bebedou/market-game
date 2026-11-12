import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../state/macro.dart';
import '../state/public_record.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The macro phase, on the first of each month. The business cycle may move
/// on to its next regime; inflation, the regime's nudged by how shelf prices
/// actually moved, compounds into the price index and, with real wage
/// growth, into the wage index; the central bank resets its rate.
///
/// With several countries, they share a cycle: each month it may turn, and
/// each country follows a turn with its own chance, or else may turn on its
/// own (see [CountryDef.follows]). Each country has its own inflation,
/// prices, wages and unemployment, and swings as far as its depth says; one
/// central bank sets the rate for all, from their inflation and output gaps
/// weighted by size.
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
    final content = context.content;
    final def = content.macro;
    final countries = content.countries;
    if (world.cycle case final cycle?) {
      // The shared cycle, drawn as a lone country's would be.
      var shared = def.regimes[cycle.regime.index];
      cycle.monthsInRegime++;
      var turned = false;
      if (context.rng(RngStream.macro, 0).nextInt(shared.meanMonths) == 0) {
        shared = def.regimes[(shared.id.index + 1) % def.regimes.length];
        cycle
          ..regime = shared.id
          ..monthsInRegime = 0;
        turned = true;
      }
      for (final country in countries) {
        _follow(world.macroOf(country.id), country, def, context, (
          turned: turned,
          regime: shared.id,
        ));
      }
      world.regimeLog.add([
        for (final country in countries)
          world.macroOf(country.id).regime.index,
        cycle.regime.index,
      ]);
    } else {
      final macro = world.macro;
      final regime = def.regimes[macro.regime.index];
      macro.monthsInRegime++;
      if (context.rng(RngStream.macro, 0).nextInt(regime.meanMonths) == 0) {
        macro
          ..regime = def.regimes[(regime.id.index + 1) % def.regimes.length].id
          ..monthsInRegime = 0;
      }
    }

    final gaps = <Fx>[];
    for (final country in countries) {
      gaps.add(_prices(world, context, country));
    }
    final policyRate = _policyRate(world, def, countries, gaps);
    for (final country in countries) {
      final macro = world.macroOf(country.id)..policyRate = policyRate;
      final history = world.historyOf(country.id)
        ..add((
          day: context.day,
          regime: macro.regime,
          priceIndex: macro.priceIndex,
          wageIndex: macro.wageIndex,
          inflation: macro.inflation,
          policyRate: macro.policyRate,
          unemployment: macro.unemployment,
        ));
      if (history.length > economicMonthsKept) history.removeAt(0);
    }
  }

  /// [country]'s regime this month: it joins a turn of the shared cycle with
  /// its chance of following, and otherwise may turn on its own, as often as
  /// it doesn't follow.
  static void _follow(
    MacroState macro,
    CountryDef country,
    MacroDef def,
    TickContext context,
    ({bool turned, RegimeId regime}) shared,
  ) {
    macro.monthsInRegime++;
    final rng = context.rng(RngStream.macro, 1 + country.id.index);
    if (shared.turned && macro.regime != shared.regime) {
      if (rng.nextFx() < country.follows) {
        macro
          ..regime = shared.regime
          ..monthsInRegime = 0;
        return;
      }
    }
    if (country.follows == Fx.one) return;
    final regime = def.regimes[macro.regime.index];
    final own = Fx.raw(
      mulDivRound((Fx.one - country.follows).raw, 1, regime.meanMonths),
    );
    if (rng.nextFx() < own) {
      macro
        ..regime = def.regimes[(regime.id.index + 1) % def.regimes.length].id
        ..monthsInRegime = 0;
    }
  }

  /// [country]'s inflation, prices, wages and unemployment for the month;
  /// returns its output gap, for the central bank.
  static Fx _prices(WorldState world, TickContext context, CountryDef country) {
    final def = context.content.macro;
    final macro = world.macroOf(country.id);
    final regime = def.regimes[macro.regime.index];
    var inflation = regime.inflation;
    final level = retailLevel(world, context, country: country.id);
    if (level != null && macro.retailLevel > Fx.zero) {
      var measured = (level.div(macro.retailLevel) - Fx.one).timesInt(12);
      if (measured > measuredCap) measured = measuredCap;
      if (measured < -measuredCap) measured = -measuredCap;
      inflation += def.retailFeedback * (measured - inflation);
    }
    if (level != null) macro.retailLevel = level;
    final gap = country.outputGapIn(regime);
    var wageGrowth = inflation + regime.realWageGrowth;
    if (def.labour case final labour?) {
      final target = labour.unemploymentTarget(gap);
      macro.unemployment += labour.adjustment * (target - macro.unemployment);
      // The wage Phillips curve: slack holds wages back.
      wageGrowth -=
          labour.phillipsSlope *
          (macro.unemployment - labour.naturalUnemployment);
    }
    macro
      ..inflation = inflation
      ..priceIndex += macro.priceIndex * _monthly(inflation)
      ..wageIndex += macro.wageIndex * _monthly(wageGrowth);
    return gap;
  }

  /// The rate for every country, from their inflation and output [gaps]
  /// weighted by size: a lone country's own.
  static Fx _policyRate(
    WorldState world,
    MacroDef def,
    List<CountryDef> countries,
    List<Fx> gaps,
  ) {
    if (countries.length == 1) {
      return def.policyRate(world.macro.inflation, gaps.single);
    }
    var weights = 0;
    var inflation = 0;
    var gap = 0;
    for (final country in countries) {
      final weight = country.weight.raw;
      weights += weight;
      inflation += world.macroOf(country.id).inflation.raw * weight;
      gap += gaps[country.id.index].raw * weight;
    }
    return def.policyRate(
      Fx.raw(mulDivRound(inflation, 1, weights)),
      Fx.raw(mulDivRound(gap, 1, weights)),
    );
  }

  static Fx _monthly(Fx annual) => Fx.raw(mulDivRound(annual.raw, 1, 12));
}

/// Shelf prices over base reference prices: for each product some open store
/// lists, in [country] if given, its average shelf price over its reference,
/// averaged across those products. Null if nothing is listed anywhere.
Fx? retailLevel(WorldState world, TickContext context, {CountryId? country}) {
  final content = context.content;
  var sum = Fx.zero;
  var products = 0;
  for (final product in content.products) {
    var cents = 0;
    var stores = 0;
    final normal = country == null
        ? product.referencePrice
        : content.referenceIn(product, country);
    for (final store in world.stores) {
      final price = store.prices[product.id.index];
      if (store.status != StoreStatus.open || price == null) continue;
      if (country != null && content.countryOf(store.market) != country) {
        continue;
      }
      cents += price.cents;
      stores++;
    }
    if (stores == 0) continue;
    sum += Fx.raw(
      mulDivRound(cents, Fx.scale, stores * normal.cents),
    );
    products++;
  }
  return products == 0 ? null : Fx.raw(sum.raw ~/ products);
}
