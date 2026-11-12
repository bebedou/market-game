import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/factories.dart';
import '../state/history.dart';
import '../state/store.dart';
import 'observation.dart';

/// A month of a factory at one number of shifts, at the shops' present
/// orders.
typedef FactoryShiftPlan = ({
  int shifts,

  /// What it can make in a month.
  int capacity,

  /// What it would make, and what the shops would still buy from their
  /// wholesalers beyond that.
  int made,
  int boughtIn,

  /// Its capacity used.
  Fx use,

  /// What it would earn a month against buying, and the use at which it
  /// earns nothing.
  Money earned,
  Fx breakEven,
});

/// What a factory of [FactoryOutlook.kind] in [FactoryOutlook.country] would
/// do for the shops of the actor's that would take its goods: built from
/// what anyone may see, at today's prices and wages, from the shops' last
/// four weeks of sales.
final class FactoryOutlook {
  const FactoryOutlook({
    required this.kind,
    required this.country,
    required this.serves,
    required this.buildCost,
    required this.buildDays,
    required this.shops,
    required this.units,
    required this.value,
    required this.plans,
    required this.best,
    required this.recession,
  });

  final FactoryKindId kind;
  final CountryId country;

  /// The countries whose shops it would deliver to, by [CountryId].
  final List<bool> serves;
  final Money buildCost;
  final int buildDays;

  /// The actor's shops that would take its goods.
  final int shops;

  /// What those shops sell of its goods a month, and what they pay their
  /// wholesalers for them.
  final int units;
  final Money value;

  /// A month at each number of shifts, from one.
  final List<FactoryShiftPlan> plans;

  /// The plan that earns most.
  final FactoryShiftPlan best;

  /// [best]'s shifts in the worst of the cycle's phases, when households
  /// buy least.
  final FactoryShiftPlan recession;

  /// Months for [best] to earn back its building, or null if it earns
  /// nothing.
  int? get paybackMonths => best.earned > Money.zero
      ? (buildCost.cents + best.earned.cents - 1) ~/ best.earned.cents
      : null;
}

/// The countries a factory of [kind] in [country] would serve for the
/// actor: its own, and if its goods travel, every other where the actor has
/// a shop selling them.
List<bool> outlookServes(
  Observation view,
  ContentDb content,
  FactoryKindDef kind,
  CountryId country,
) {
  final serves = [
    for (var c = 0; c < content.countries.length; c++) c == country.index,
  ];
  if (!kind.exports) return serves;
  for (final company in view.companies) {
    for (final store in company.stores) {
      if (store.status == StoreStatus.closed ||
          !content.formats[store.format.index].sells[kind.category.index]) {
        continue;
      }
      serves[content.countryOf(store.market).index] = true;
    }
  }
  return serves;
}

/// What a factory of [kindId] built in [country] would make, cost and earn
/// for the actor's shops in the countries it [serves] (by default
/// [outlookServes]), at one to the most shifts.
FactoryOutlook factoryOutlook(
  Observation view,
  ContentDb content,
  FactoryKindId kindId,
  CountryId country, {
  List<bool>? serves,
}) {
  final factories = content.factories!;
  final kind = factories.kinds[kindId.index];
  final served = serves ?? outlookServes(view, content, kind, country);
  final home = view.economy(country);
  // A month, on average: 365 days over 12.
  int monthly(int perDay) => mulDivRound(perDay, 365, 12);
  int monthOf28(int units) => mulDivRound(units, 365, 12 * salesHistoryDays);
  var shops = 0;
  var units = 0;
  var value = Money.zero;
  var margin = Money.zero;
  for (final company in view.companies) {
    for (final store in company.stores) {
      if (store.status == StoreStatus.closed) continue;
      final where = content.countryOf(store.market);
      if (!served[where.index]) continue;
      final level = view.economy(where).priceIndex;
      var sells = false;
      for (final product in content.products) {
        if (!kindMakes(kind, product) ||
            store.prices[product.id.index] == null) {
          continue;
        }
        sells = true;
        final sold = monthOf28(
          store.sales.total(SalesCount.sold, product.id, salesHistoryDays),
        );
        if (sold == 0) continue;
        // About a week's sales an order.
        final order = sold ~/ 4 < kind.minOrderUnits
            ? kind.minOrderUnits
            : sold ~/ 4;
        final quote = marketQuote(content, where, product, order, level);
        if (quote == null) continue;
        final price = quote.price;
        var unit = price - materialsCost(kind, product, home.priceIndex);
        if (where != country) unit -= price.times(factories.freight);
        units += sold;
        value += price.timesInt(sold);
        margin += unit.timesInt(sold);
      }
      if (sells) shops++;
    }
  }
  final shift = kind.shiftWage
      .times(home.wageIndex)
      .times(content.countries[country.index].service);
  final site = kind.site.times(home.priceIndex);
  FactoryShiftPlan plan(int shifts, int wanted, Money wantedMargin) {
    final capacity = monthly(kind.shiftUnits * shifts);
    final made = wanted < capacity ? wanted : capacity;
    final fixed = Money(monthly(shift.cents)).timesInt(shifts) + site;
    final gross = wanted == 0
        ? Money.zero
        : Money(mulDivRound(wantedMargin.cents, made, wanted));
    final perUnit = wanted == 0 ? 0 : wantedMargin.cents ~/ wanted;
    return (
      shifts: shifts,
      capacity: capacity,
      made: made,
      boughtIn: wanted - made,
      use: capacity == 0
          ? Fx.zero
          : Fx.raw(mulDivRound(made, Fx.scale, capacity)),
      earned: gross - fixed,
      breakEven: perUnit <= 0 || capacity == 0
          ? Fx.one
          : Fx.raw(mulDivRound(fixed.cents, Fx.scale, perUnit * capacity)),
    );
  }

  final plans = [
    for (var shifts = 1; shifts <= factories.maxShifts; shifts++)
      plan(shifts, units, margin),
  ];
  var best = plans.first;
  for (final candidate in plans) {
    if (candidate.earned > best.earned) best = candidate;
  }
  var worst = Fx.one;
  for (final regime in content.macro.regimes) {
    if (regime.demand < worst) worst = regime.demand;
  }
  final slumped = mulDivRound(units, worst.raw, Fx.scale);
  return FactoryOutlook(
    kind: kindId,
    country: country,
    serves: List.unmodifiable(served),
    buildCost: kind.buildCost.times(home.priceIndex),
    buildDays: kind.buildDays,
    shops: shops,
    units: units,
    value: value,
    plans: List.unmodifiable(plans),
    best: best,
    recession: plan(
      best.shifts,
      slumped,
      Money(mulDivRound(margin.cents, slumped, units == 0 ? 1 : units)),
    ),
  );
}
