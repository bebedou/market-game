import '../accounting/ledger.dart';
import '../state/brands.dart';
import '../state/entities.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../neighbourhoods/neighbourhood_generator.dart';
import '../observation/outlook.dart';
import '../policies/retail_policy.dart' show closingLoss;
import '../state/sleepers.dart';
import '../state/taxation.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// Months a new shop takes to draw as well as those already known here.
const _settlingMonths = 24;

/// How a shop still settling draws against those already known.
const _settlingDraw = Fx.raw(8000);

/// The chance in a month, for every so many households, that someone is ready
/// to open where it would pay: the more people, the more would-be owners.
const _openingChance = Fx.raw(300);
const _openingHouseholds = 2000;

/// What a shop must have earned in a year, beyond what the extra room would
/// cost, against the works' cost, to enlarge the first time. It takes more each
/// time, by the square: each round of shelves holds what sells less than the
/// last.
const _enlargingReturn = 2;

/// What the shops of a neighbourhood do once settled: unlike a new shop's habits
/// ([ShopHabits]), these were fitted to the same places simulated in full for
/// ten years.
typedef _Settled = ({
  /// What it turns into sales of what households here would buy from it.
  Fx capture,

  /// How it draws shoppers against the others of its trade.
  Fx draw,

  /// What its goods cost beyond the list.
  Fx goodsExtra,

  /// The staff it keeps for its busiest hours, against its average.
  Fx peakStaff,
});

/// What a shop's strategy draws beyond its prices, against a balanced shop's,
/// fitted like [_settled]: a premium shop's late hours, service and advertising
/// win it more than its dearer prices lose, and a discounter's prices win it
/// less than they alone would say.
Fx _beyondPrices(StrategyDef strategy) => switch (strategy.key) {
  'premium' => const Fx.raw(14800),
  'discount' => const Fx.raw(7400),
  _ => Fx.one,
};

_Settled _settled(FormatDef format) => switch (format.key) {
  'supermarket' => const (
    capture: Fx.raw(9500),
    draw: Fx.raw(19000),
    goodsExtra: Fx.raw(-250),
    peakStaff: Fx.raw(10000),
  ),
  'fastfood' => const (
    capture: Fx.raw(8500),
    draw: Fx.one,
    goodsExtra: Fx.raw(1800),
    peakStaff: Fx.raw(15000),
  ),
  'steakhouse' => const (
    capture: Fx.raw(9400),
    draw: Fx.one,
    goodsExtra: Fx.raw(800),
    peakStaff: Fx.raw(14000),
  ),
  'finedining' => const (
    capture: Fx.raw(9450),
    draw: Fx.one,
    goodsExtra: Fx.raw(1800),
    peakStaff: Fx.raw(14400),
  ),
  'electronics' => const (
    capture: Fx.raw(9700),
    draw: Fx.one,
    goodsExtra: Fx.zero,
    peakStaff: Fx.raw(16800),
  ),
  _ => const (
    capture: Fx.raw(9500),
    draw: Fx.one,
    goodsExtra: Fx.raw(-200),
    peakStaff: Fx.raw(13000),
  ),
};

/// The formula gives each shop what a shop like it does, while real shops scatter
/// around that by a few points of margin. So one earning less than this, of its
/// sales, may be closing anyway: with [_shakyChance] a month at no profit,
/// scaling up as its margin falls.
const _shakyMargin = Fx.raw(300);
const _shakyChance = Fx.raw(300);

/// Runs every sleeping neighbourhood by formula, on the first of each month:
/// households come and go; what they spend, at the economy of the day, is shared
/// among the shops of each trade by location, size and price; each shop books
/// its month; those losing money for a year close, as an AI owner would close
/// them, those doing well enlarge, and someone opens on a free site when it
/// would pay back soon enough. The neighbourhoods touch nothing else: no shop
/// in the simulated world feels them, nor any account.
final class SleeperSystem implements TickSystem {
  const SleeperSystem();

  @override
  void run(WorldState world, TickContext context) {
    final content = context.content;
    if (!context.day.isFirstOfMonth || context.day <= content.startDay) return;
    final start = content.startDay.date;
    final now = context.day.date;
    final month = (now.year - start.year) * 12 + now.month - start.month;
    for (final sleeper in world.sleepers) {
      sleeper.sites ??= plannedSites(content, sleeper.row, seed: world.seed);
      final rng = context.rng(RngStream.neighbourhoods, 1000 + sleeper.row);
      _grow(world, content, sleeper);
      _trade(world, content, context.ledger, sleeper, context.day, month);
      _closeAndEnlarge(world, content, context.ledger, sleeper, month, rng);
      _open(world, content, sleeper, month, rng);
    }
  }

  void _grow(
    WorldState world,
    ContentDb content,
    SleepingNeighbourhood sleeper,
  ) {
    final row = content.neighbourhoods[sleeper.row];
    final migration = content
        .macro
        .regimes[world.macroOf(row.country).regime.index]
        .migration;
    for (var s = 0; s < sleeper.households.length; s++) {
      final rate = row.growth[s] + migration;
      final owed =
          sleeper.pending[s] +
          Fx.raw(mulDivRound(sleeper.households[s] * rate.raw, 1, 12));
      final whole = owed.raw ~/ Fx.scale;
      sleeper.pending[s] = owed - Fx.fromInt(whole);
      sleeper.households[s] += whole;
      if (sleeper.households[s] < 0) sleeper.households[s] = 0;
    }
  }

  void _trade(
    WorldState world,
    ContentDb content,
    Ledger ledger,
    SleepingNeighbourhood sleeper,
    Day day,
    int month,
  ) {
    final row = content.neighbourhoods[sleeper.row];
    final macro = world.macroOf(row.country);
    final country = content.countries[row.country.index];
    final regime = content.macro.regimes[macro.regime.index];
    var cycle = country.demandIn(regime);
    if (content.macro.labour case final labour?) {
      cycle *= labour.confidenceFactor(macro.unemployment);
    }
    final sites = sleeper.sites!;
    final byChannel = <int, List<SleepingShop>>{};
    for (final shop in sleeper.shops) {
      (byChannel[content.formatChannels[shop.format.index]] ??= []).add(shop);
    }
    // Channels in order, as a map's would depend on who opened first.
    final channels = byChannel.keys.toList()..sort();
    for (final channel in channels) {
      final shops = byChannel[channel]!;
      final demand = tradeDemand(
        content,
        households: sleeper.households,
        incomeLevel: row.incomeLevel,
        priceLevel: row.priceLevel,
        priceIndex: macro.priceIndex,
        today: day,
        format: content.formats[shops.first.format.index],
        power: content.demand.purchasingPower(
          macro.wageIndex,
          macro.priceIndex,
        ),
        premiumShift: country.premiumShiftIn(regime),
        scale: row.scaleOf(channel),
        costLevel: content.costLevel(row.country),
        references: content.references[row.country.index],
      );
      // What it would sell at the strategy's prices, against normal ones.
      Fx pricing(SleepingShop shop) {
        final strategy = content.strategies[shop.strategy.index];
        return demand.spending <= Money.zero
            ? Fx.one
            : Fx.raw(
                mulDivRound(
                  demand.atLevel.times(Fx.one + strategy.markup).cents,
                  Fx.scale,
                  demand.spending.cents,
                ),
              );
      }

      Fx weight(SleepingShop shop) {
        final site = sites[shop.site];
        var draw =
            shopPull(content, site.location, shop.area) *
            priceDraw(pricing(shop) - Fx.one) *
            _beyondPrices(content.strategies[shop.strategy.index]) *
            _settled(content.formats[shop.format.index]).draw;
        if (month - shop.openedMonth < _settlingMonths &&
            !_knownNearby(world, content, sleeper, shop)) {
          draw *= _settlingDraw;
        }
        return draw;
      }

      var total = Fx.zero;
      for (final shop in shops) {
        total += weight(shop);
      }
      for (final shop in shops) {
        final format = content.formats[shop.format.index];
        final strategy = content.strategies[shop.strategy.index];
        final habits = _settled(format);
        final site = sites[shop.site];
        final served = weight(shop).div(total) * habits.capture * cycle;
        final bought = demand.goods.times(served);
        final sales = demand.atLevel
            .times(Fx.one + strategy.markup)
            .times(served);
        final wages = yearlyWages(
          content,
          format,
          strategy,
          wageIndex: macro.wageIndex,
          wageLevel: row.wageLevel,
          unitsServed: demand.units * served,
          unitsPerVisit: habitsOf(format).unitsPerVisit,
          peak: habits.peakStaff,
        );
        final premises =
            (site.rentFor(shop.area) + format.overheadsFor(shop.area))
                .times(macro.priceIndex)
                .timesInt(12);
        final yearly =
            sales -
            bought -
            bought.times(habits.goodsExtra) -
            sales.times(strategy.marketingShare) -
            wages -
            premises;
        final sold = Money(mulDivRound(sales.cents, 1, 12));
        if (shop.company case final id?) {
          final profit = _book(
              world,
              ledger,
              world.companies[id.index],
              sold: sold,
              goods: bought + bought.times(habits.goodsExtra),
              marketing: sales.times(strategy.marketingShare),
              wages: wages,
              rent: site.rentFor(shop.area).times(macro.priceIndex),
              overheads: format.overheadsFor(shop.area).times(macro.priceIndex),
            );
          shop.remember(sold, profit);
          if (world.cycle != null) {
            recordDistrictMonth(
              world,
              id,
              row.country,
              day.date.year,
              sales: sold,
              profit: profit,
            );
          }
          continue;
        }
        final earned = Money(mulDivRound(yearly.cents, 1, 12));
        shop.remember(sold, earned);
        // After tax it stays in the company until that's well stocked, then
        // goes to its owner; a loss falls on the company, then the owner.
        final taxed = earned > Money.zero
            ? earned - earned.times(_taxRate(content, row.country))
            : earned;
        shop.cash += taxed;
        final reserve = Money(
          mulDivRound(
            (bought + wages + premises).cents,
            strategy.reserveDays,
            365,
          ),
        );
        if (shop.cash > reserve) {
          shop.ownerCash += shop.cash - reserve;
          shop.cash = reserve;
        } else if (shop.cash.isNegative) {
          shop.ownerCash += shop.cash;
          shop.cash = Money.zero;
        }
      }
    }
  }

  Fx _taxRate(ContentDb content, CountryId country) =>
      content.taxesOf(country)?.corporateRate ?? Fx.zero;

  /// Books a month of a chain's shop in [company]'s accounts, against those
  /// it trades with elsewhere: its [sold], and its year's [goods],
  /// [marketing] and [wages] and a month's [rent] and [overheads]. Its tax
  /// is the company's, at the year's end. Returns its month's profit.
  Money _book(
    WorldState world,
    Ledger ledger,
    Company company, {
    required Money sold,
    required Money goods,
    required Money marketing,
    required Money wages,
    required Money rent,
    required Money overheads,
  }) {
    Money month(Money yearly) => Money(mulDivRound(yearly.cents, 1, 12));
    if (sold > Money.zero) {
      ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.revenue,
        amount: sold,
        reason: EntryReason.sale,
      );
    }
    var profit = sold;
    for (final (amount, account, reason) in [
      (month(goods), AccountKind.costOfGoods, EntryReason.costOfSale),
      (month(marketing), AccountKind.marketing, EntryReason.marketing),
      (month(wages), AccountKind.wages, EntryReason.wages),
      (rent, AccountKind.rent, EntryReason.rent),
      (overheads, AccountKind.overheads, EntryReason.overheads),
    ]) {
      if (amount <= Money.zero) continue;
      ledger.pay(
        payer: company,
        payerAccount: account,
        payee: world.elsewhere,
        payeeAccount: AccountKind.revenue,
        amount: amount,
        reason: reason,
      );
      profit -= amount;
    }
    return profit;
  }

  /// Whether [shop]'s brand trades elsewhere in its city already, so that
  /// shoppers know it from the first day.
  bool _knownNearby(
    WorldState world,
    ContentDb content,
    SleepingNeighbourhood sleeper,
    SleepingShop shop,
  ) {
    final brand = shop.brand;
    if (brand == null) return false;
    final city = cityOf(content.neighbourhoods[sleeper.row].name);
    for (final store in world.stores) {
      if (store.brand == brand &&
          store.isTrading &&
          cityOf(content.markets[store.market.index].name) == city) {
        return true;
      }
    }
    for (final other in world.sleepers) {
      if (cityOf(content.neighbourhoods[other.row].name) != city) continue;
      for (final rival in other.shops) {
        if (rival != shop && rival.brand == brand) return true;
      }
    }
    return false;
  }

  void _closeAndEnlarge(
    WorldState world,
    ContentDb content,
    Ledger ledger,
    SleepingNeighbourhood sleeper,
    int month,
    Rng rng,
  ) {
    final sites = sleeper.sites!;
    final expansion = content.expansion;
    final priceIndex = world
        .macroOf(content.neighbourhoods[sleeper.row].country)
        .priceIndex;
    final closing = <SleepingShop>[];
    for (final shop in sleeper.shops) {
      final format = content.formats[shop.format.index];
      final strategy = content.strategies[shop.strategy.index];
      final age = month - shop.openedMonth;
      // A chain's shop goes with its company.
      final chain = switch (shop.company) {
        final id? => world.companies[id.index],
        null => null,
      };
      final broke = chain != null
          ? chain.status != CompanyStatus.active
          : shop.ownerCash.isNegative;
      final losing =
          age >= 24 &&
          shop.sales.length == sleepingMonthsKept &&
          -shop.yearProfit > shop.yearSales.times(closingLoss);
      if (broke || losing || _gaveUp(shop, age, rng)) {
        closing.add(shop);
        continue;
      }
      // Enlarging is for shelves: only a grocer ever runs out of them.
      final sold = content.products
          .where((product) => format.sells[product.category.index])
          .length;
      final site = sites[shop.site];
      final steps = (shop.area - site.area) ~/ expansion.stepArea;
      final slots =
          site.shelfSlots + format.slotBonus + steps * expansion.shelfSlots;
      final cost = expansion.cost(priceIndex);
      // What it must have earned leaves out what the extra room would cost.
      final extra =
          (site.rentFor(shop.area + expansion.stepArea) -
                  site.rentFor(shop.area) +
                  format.overheadsFor(expansion.stepArea))
              .times(priceIndex)
              .timesInt(12);
      if (slots < sold &&
          shop.area + expansion.stepArea <= site.maxArea &&
          (month - shop.enlargedMonth) * 30 >= strategy.expansionIntervalDays &&
          shop.yearProfit - extra >=
              cost.timesInt(_enlargingReturn * (steps + 1) * (steps + 1)) &&
          (chain != null
              ? chain.accounts[AccountKind.cash] >= cost
              : shop.cash + shop.ownerCash >= cost)) {
        shop.area += expansion.stepArea;
        shop.enlargedMonth = month;
        if (chain != null) {
          ledger.pay(
            payer: chain,
            payerAccount: AccountKind.openingCosts,
            payee: world.elsewhere,
            payeeAccount: AccountKind.revenue,
            amount: cost,
            reason: EntryReason.expansion,
          );
          continue;
        }
        shop.cash -= cost;
        if (shop.cash.isNegative) {
          shop.ownerCash += shop.cash;
          shop.cash = Money.zero;
        }
      }
    }
    for (final shop in closing) {
      sleeper.shops.remove(shop);
      sleeper.closed++;
    }
  }

  /// Whether a shop trading near the line, though not over it, closes this month.
  bool _gaveUp(SleepingShop shop, int age, Rng rng) {
    if (age < 24 || shop.sales.length < sleepingMonthsKept) return false;
    final sold = shop.yearSales;
    if (sold <= Money.zero) return false;
    final margin = Fx.raw(
      mulDivRound(shop.yearProfit.cents, Fx.scale, sold.cents),
    );
    if (margin >= _shakyMargin) return false;
    return rng.chance(_shakyChance * (_shakyMargin - margin).div(_shakyMargin));
  }

  /// Now and then, someone ready to open looks over the free sites as an AI
  /// owner would, and takes the one that would pay back soonest, if it would
  /// within what its strategy allows.
  void _open(
    WorldState world,
    ContentDb content,
    SleepingNeighbourhood sleeper,
    int month,
    Rng rng,
  ) {
    final total = sleeper.households.fold(0, (sum, count) => sum + count);
    final chance = Fx.raw(
      mulDivRound(_openingChance.raw, total, _openingHouseholds),
    );
    if (!rng.chance(chance)) return;
    final row = content.neighbourhoods[sleeper.row];
    final sites = sleeper.sites!;
    final macro = world.macroOf(row.country);
    final taken = {for (final shop in sleeper.shops) shop.site};
    FormatDef? bestFormat;
    StrategyDef? bestStrategy;
    PlannedSite? bestSite;
    var bestPayback = 0;
    for (final format in content.formats) {
      final strategy = usualStrategy(content, format);
      if (strategy.expansionPaybackMonths == 0) continue;
      for (final site in sites) {
        if (taken.contains(site.number) || site.area < format.minArea) continue;
        // Each draws by location and size, as shoppers weigh size.
        final mine = shopPull(content, site.location, site.area);
        var pull = mine;
        for (final shop in sleeper.shops) {
          if (content.formatChannels[shop.format.index] ==
              content.formatChannels[format.id.index]) {
            pull += shopPull(content, sites[shop.site].location, shop.area);
          }
        }
        final daily = strategy.marginPerHousehold
            .times(
              macro.priceIndex *
                  row.priceLevel *
                  row.incomeLevel *
                  content.countries[row.country.index].service,
            )
            .timesInt(total)
            .times(
              mine.div(pull) *
                  row.scaleOf(content.formatChannels[format.id.index]),
            );
        final wages = content.operations.slotWage
            .times(macro.wageIndex * row.wageLevel * format.wageFactor)
            .timesInt(strategy.hours.where((open) => open).length);
        final premises = (site.rent + format.overheadsFor(site.area)).times(
          macro.priceIndex,
        );
        final monthly = (daily - wages).timesInt(30) - premises;
        if (monthly <= Money.zero) continue;
        final fitting = site.openingCost
            .times(format.fitOut)
            .times(macro.priceIndex);
        final payback = (fitting.cents + monthly.cents - 1) ~/ monthly.cents;
        if (payback > strategy.expansionPaybackMonths) continue;
        if (bestSite == null || payback < bestPayback) {
          bestFormat = format;
          bestStrategy = strategy;
          bestSite = site;
          bestPayback = payback;
        }
      }
    }
    if (bestSite == null) return;
    final fitting = bestSite.openingCost.times(macro.priceIndex);
    sleeper.shops.add(
      SleepingShop(
        site: bestSite.number,
        format: bestFormat!.id,
        strategy: bestStrategy!.id,
        name: newShopName(content, row.country, bestFormat, rng),
        owner: newOwnerName(content, row.country, rng),
        area: bestSite.area,
        cash: fitting,
        ownerCash: fitting,
        openedMonth: month,
        enlargedMonth: month,
      ),
    );
    sleeper.opened++;
  }
}
