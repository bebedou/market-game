import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'entities.dart';
import 'history.dart';
import 'store.dart';
import 'world_state.dart';

/// A store's asking price and what it rests on.
typedef Valuation = ({
  /// Its stock at cost.
  Money stock,

  /// Its fittings at the cost of replacing them, worn down with age.
  Money fittings,

  /// A year's profit at its sales of the last weeks and its present rent,
  /// overheads, staff and marketing; zero for a store too new to tell.
  Money earnings,
  Money price,
});

/// What a company sells for at the least, its debts beyond its worth
/// notwithstanding: a symbolic euro.
const Money symbolicPrice = Money(100);

/// [store]'s asking price today, by [AcquisitionDef]'s excess earnings
/// method; null if it is closed or the scenario sells nothing. A store open
/// fewer than [salesHistoryDays] days asks what it holds.
Valuation? valueStore(WorldState world, ContentDb content, Store store) {
  final terms = content.acquisitions;
  if (terms == null || !store.isTrading) return null;
  final level = world.macroAt(content, store.market).priceIndex;
  final site = content.sites[store.site.index];
  final format = content.formats[store.format.index];
  var stock = Money.zero;
  for (final product in store.stock) {
    stock += product.value;
  }
  final age = world.today.number - store.opensOn.number;
  final used = age <= 0
      ? Fx.zero
      : age >= terms.fittingsLifeDays
      ? Fx.one
      : Fx.raw(mulDivRound(age, Fx.scale, terms.fittingsLifeDays));
  final wear = (Fx.one - terms.fittingsResidual) * used;
  final fittings = site.openingCost
      .times(format.fitOut)
      .times(level)
      .times(Fx.one - wear);
  final held = stock + fittings;
  final earnings = storeEarnings(world, content, store);
  if (earnings == null) {
    return (
      stock: stock,
      fittings: fittings,
      earnings: Money.zero,
      price: held,
    );
  }
  final excess = earnings - held.times(terms.tangibleReturn);
  final price =
      held +
      Money(mulDivRound(excess.cents, Fx.scale, terms.capitalization.raw));
  final floor = held.times(terms.distressFloor);
  return (
    stock: stock,
    fittings: fittings,
    earnings: earnings,
    price: price > floor ? price : floor,
  );
}

/// A year's profit for [store]: the last [salesHistoryDays] days' units sold
/// at today's prices, less their cost (the average cost of the stock on
/// hand, or the base cost at today's prices), scaled to a year, less a year
/// of today's wages, salary, marketing, rent and overheads. Null if it is
/// closed or open fewer than [salesHistoryDays] days.
Money? storeEarnings(WorldState world, ContentDb content, Store store) {
  if (!store.isTrading) return null;
  if (world.today.number - store.opensOn.number < salesHistoryDays) {
    return null;
  }
  final macro = world.macroAt(content, store.market);
  final level = macro.priceIndex;
  final site = content.sites[store.site.index];
  final format = content.formats[store.format.index];
  var gross = Money.zero;
  for (var product = 0; product < store.prices.length; product++) {
    final price = store.prices[product];
    if (price == null) continue;
    var units = 0;
    for (var ago = 1; ago <= salesHistoryDays; ago++) {
      units += store.history.at(
        SalesCount.sold,
        ProductId(product),
        Day(world.today.number - ago),
      );
    }
    if (units == 0) continue;
    final onHand = store.stock[product];
    final unitCost = onHand.units > 0
        ? Money(onHand.value.cents ~/ onHand.units)
        : content.products[product].baseCost
              .times(level)
              .times(content.costLevel(content.countryOf(store.market)));
    gross += (price - unitCost).timesInt(units);
  }
  final wageLevel =
      macro.wageIndex * content.markets[store.market.index].wageLevel;
  var daily = content.operations.slotWage
      .times(wageLevel)
      .times(format.wageFactor)
      .timesInt(store.staff.fold(0, (sum, count) => sum + count));
  if (store.manager case final manager?) {
    daily += content.managers.grades[manager.grade.index].salary.times(
      wageLevel,
    );
  }
  daily += store.recentDailySales(world.today).times(store.marketingShare);
  return Money(mulDivRound(gross.cents, 365, salesHistoryDays)) -
      daily.timesInt(365) -
      (site.rentFor(store.area) + format.overheadsFor(store.area))
          .times(level)
          .timesInt(12);
}

/// What [company] sells for whole: its trading stores at their asking
/// prices, [values] if given, indexed by [StoreId], plus its cash, less its
/// bills and loans; never less than [symbolicPrice]. Null if it has been
/// liquidated or the scenario sells nothing.
Money? companyPrice(
  WorldState world,
  ContentDb content,
  Company company, {
  List<Valuation?>? values,
}) {
  if (content.acquisitions == null || !company.isActive) return null;
  var price =
      company.accounts[AccountKind.cash] +
      company.accounts[AccountKind.payables] +
      company.accounts[AccountKind.loans];
  for (final store in world.stores) {
    if (store.company != company.id || !store.isTrading) continue;
    final value = values == null
        ? valueStore(world, content, store)
        : values[store.id.index];
    price += value!.price;
  }
  return price > symbolicPrice ? price : symbolicPrice;
}

/// The company that buys [store] for [price] when its owner sells: one of
/// an AI owner who expands with the store's format, other than the seller,
/// whose company and personal cash together cover the price and the
/// reserve, the best funded first. Null if no one can.
Company? bestBuyer(
  WorldState world,
  ContentDb content,
  Store store,
  Money price,
) {
  final terms = content.acquisitions;
  if (terms == null) return null;
  final seller = world.companies[store.company.index].owner;
  final needed = price + price.times(terms.buyerReserve);
  Company? best;
  var bestFunds = Money.zero;
  for (final company in world.companies) {
    if (!company.isActive ||
        company.owner == seller ||
        company.owner == world.player) {
      continue;
    }
    final setup = content.persons[company.owner.index];
    final strategy = setup.strategy;
    if (strategy == null || setup.local) continue;
    final def = content.strategies[strategy.index];
    if (def.expansionPaybackMonths == 0 || def.format != store.format) {
      continue;
    }
    final funds =
        company.accounts[AccountKind.cash] +
        world.persons[company.owner.index].accounts[AccountKind.cash];
    if (funds < needed) continue;
    if (best == null || funds > bestFunds) {
      best = company;
      bestFunds = funds;
    }
  }
  return best;
}
