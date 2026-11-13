import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'districts.dart';
import 'entities.dart';
import 'factory.dart';
import 'national_value.dart';
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

/// What [company] sells for whole: its trading stores and its factories at
/// their asking prices, [values] if given, indexed by [StoreId], plus its cash, less its
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
  for (final factory in world.factories) {
    if (factory.company != company.id) continue;
    price += valueFactory(world, content, factory)?.price ?? Money.zero;
  }
  // Its shops run by formula, across countries and in districts asleep.
  if (world.national case final national?) {
    for (final country in national.countries) {
      for (final block in country.blocks) {
        if (block.company != company.id.index) continue;
        price +=
            valueBlock(content, national, country, block)?.price ?? Money.zero;
      }
    }
  }
  final month = monthsSinceStart(content, world.today);
  for (final sleeper in world.sleepers) {
    for (final shop in sleeper.shops) {
      if (shop.company != company.id) continue;
      price +=
          valueSleepingShop(
            world,
            content,
            sitesOf(world, content, sleeper)[shop.site],
            shop,
            month,
            country: content.neighbourhoods[sleeper.row].country,
          )?.price ??
          Money.zero;
    }
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

/// [factory]'s asking price, by the same excess earnings method as a
/// store's: its fittings, what building it cost worn down with age, plus
/// what a year's earnings beat a fair return on them by, capitalized. Null
/// if it is closed, still being built, or the scenario sells nothing.
Valuation? valueFactory(WorldState world, ContentDb content, Factory factory) {
  final terms = content.acquisitions;
  if (terms == null || !factory.runsOn(world.today)) return null;
  final age = world.today.number - factory.opensOn.number;
  final used = age >= terms.fittingsLifeDays
      ? Fx.one
      : Fx.raw(mulDivRound(age, Fx.scale, terms.fittingsLifeDays));
  final wear = (Fx.one - terms.fittingsResidual) * used;
  final fittings = factory.builtFor.times(Fx.one - wear);
  final earnings = factoryEarnings(world, content, factory);
  if (earnings == null) {
    return (
      stock: Money.zero,
      fittings: fittings,
      earnings: Money.zero,
      price: fittings,
    );
  }
  final excess = earnings - fittings.times(terms.tangibleReturn);
  final price =
      fittings +
      Money(mulDivRound(excess.cents, Fx.scale, terms.capitalization.raw));
  final floor = fittings.times(terms.distressFloor);
  return (
    stock: Money.zero,
    fittings: fittings,
    earnings: earnings,
    price: price > floor ? price : floor,
  );
}

/// A year's earnings for [factory] against buying: what the last
/// [factoryHistoryDays] days' goods sold for beyond their materials and
/// freight, scaled to a year, less a year of today's shifts and site. Null
/// if it isn't making goods or has made them for fewer days than that.
Money? factoryEarnings(WorldState world, ContentDb content, Factory factory) {
  final factories = content.factories;
  if (factories == null || !factory.runsOn(world.today)) return null;
  if (world.today.number - factory.opensOn.number < factoryHistoryDays) {
    return null;
  }
  final kind = factories.kinds[factory.kind.index];
  final economy = world.macroOf(factory.country);
  final shiftDay = kind.shiftWage
      .times(economy.wageIndex)
      .times(content.countries[factory.country.index].service)
      .timesInt(factory.shifts);
  final yesterday = Day(world.today.number - 1);
  return Money(
        mulDivRound(
          factory.recentMargin(yesterday).cents,
          365,
          factoryHistoryDays,
        ),
      ) -
      shiftDay.timesInt(365) -
      kind.site.times(economy.priceIndex).timesInt(12);
}
