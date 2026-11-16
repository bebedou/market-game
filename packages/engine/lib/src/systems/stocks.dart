import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../countries/country_table.dart';
import '../state/software.dart';
import '../state/software_rules.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'factory_sales.dart' show kindMarket;
import 'national.dart' show currentNational;
import 'tick_system.dart';

/// Millionths, the scale moods are kept in.
const _micro = 1000000;

/// ln 2 in millionths, for half-lives.
const _ln2 = 693147;

/// How much of the way a company's sales move to where the cycle puts them
/// each month.
const _cycleSmoothing = Fx.raw(3000);

/// What a company by formula pays over the central bank's rate on its debt.
const _borrowSpread = Fx.raw(200);

/// Months for long rates to follow the central bank's most of the way.
const _longRateMonths = 24;

/// The most of an index any one company counts for, as indices cap theirs.
const _indexCap = Fx.raw(1500);

/// The fewest shares a company is split into when the table leaves it to
/// the game, and the price a share is set near.
const _fewestShares = 1000000;
const _sharePrice = Money(4000);

/// The stock market of [world], opened from [content]'s table the first
/// time it is needed, and gaining any company the table has added since;
/// null if the content has no stock market.
StockMarket? currentStocks(WorldState world, ContentDb content) {
  final def = content.stocks;
  if (def == null) return null;
  final market = world.stocks ??= StockMarket(
    exchanges: [],
    stocks: [],
    trends: List.filled(content.countries.length * def.sectors.length, Fx.one),
    // The rate in a normal year.
    longRate: content.macro.neutralRate + content.macro.inflationTarget,
  );
  if (market.stocks.length < def.listings.length ||
      market.exchanges.length < def.exchanges.length) {
    _open(world, content, def, market);
  }
  return market;
}

/// Lists every company of the table [market] lacks, at what its books are
/// worth today, or at its cap if the table gives one; and opens every
/// exchange it lacks, its index at the table's base.
void _open(
  WorldState world,
  ContentDb content,
  StocksDef def,
  StockMarket market,
) {
  final economy = currentNational(world, content);
  final rules = def.rules;
  for (var i = market.stocks.length; i < def.listings.length; i++) {
    final listing = def.listings[i];
    final stock = Listing(
      since: world.today,
      shares: 1,
      price: const Money(1),
      worth: Money.zero,
      mood: 0,
      management: listing.management,
      managementSince: Day(world.today.number - 31 * rules.unprovenMonths),
      share: listing.share,
      margin: listing.margin,
      debt: Money.zero,
    );
    final sector = def.sectors[listing.sector];
    if (sector.byFormula) {
      stock.cycle = _cycleTarget(world, content, sector, listing.country);
    }
    // A month of its books now stands for each of its last four quarters.
    final month = _month(world, content, def, market, listing, stock, economy);
    if (listing.kind == ListingKind.formula && month.profit > Money.zero) {
      stock.debt = month.profit.timesInt(12).times(listing.debt);
    }
    for (var q = 4; q >= 1; q--) {
      final profit = month.profit.timesInt(3);
      stock.keep(
        Results(
          day: Day(world.today.number - 91 * q),
          revenue: month.revenue.timesInt(3),
          profit: profit,
          dividends: profit > Money.zero
              ? profit.times(listing.payout)
              : Money.zero,
        ),
      );
    }
    stock.worth = stockWorth(world, content, def, i, stock, economy);
    final worth = stock.worth;
    var shares = worth.cents ~/ _sharePrice.cents;
    if (shares < _fewestShares) shares = _fewestShares;
    if (shares > maxListedShares ~/ 2) shares = maxListedShares ~/ 2;
    stock.shares = listing.shares ?? shares;
    final cap = listing.cap ?? worth;
    stock.mood = _clampMood(_lnRatio(cap, worth), rules);
    stock.price = _price(stock, 0, rules);
    stock.previous = stock.price;
    stock.closes
      ..clear()
      ..add(stock.price);
    stock.listed = _stillListed(world, content, listing, economy);
    market.stocks.add(stock);
  }
  for (var e = market.exchanges.length; e < def.exchanges.length; e++) {
    final total = _indexWorth(def, market, e);
    final base = Money(rules.indexBase.raw ~/ 100);
    market.exchanges.add(
      Exchange(
        divisor: Money(
          total.cents <= 0 ? 1 : mulDivRound(total.cents, 100, base.cents),
        ),
        level: base,
      ),
    );
  }
}

/// Runs the stock market: on the first of the month, every company's month
/// is booked and it is valued again, and at the start of each quarter
/// results are published and dividends paid; every day, moods wander and
/// prices follow.
final class StockMarketSystem implements TickSystem {
  const StockMarketSystem();

  @override
  void run(WorldState world, TickContext context) {
    final content = context.content;
    final def = content.stocks;
    if (def == null) return;
    final market = currentStocks(world, content)!;
    final economy = currentNational(world, content);
    final day = context.day;
    final first = day.isFirstOfMonth;
    if (first) {
      _bookMonth(world, context, def, market, economy);
      if ((day.date.month - 1) % 3 == 0) {
        _quarter(world, context, def, market, economy);
      }
      for (final (i, stock) in market.stocks.indexed) {
        if (!stock.listed) continue;
        stock.worth = stockWorth(world, content, def, i, stock, economy);
      }
      _views(world, context, def, market);
    }
    _day(world, context, def, market);
    _stakes(context, market);
    if (first) {
      for (final stock in market.stocks) {
        if (stock.listed) stock.close(stock.multiple);
      }
      for (final exchange in market.exchanges) {
        exchange.close();
      }
    }
  }

  /// Books every listed company's month just ended, and takes off the
  /// exchange those bought whole or failed.
  void _bookMonth(
    WorldState world,
    TickContext context,
    StocksDef def,
    StockMarket market,
    CountryEconomy? economy,
  ) {
    final content = context.content;
    market.longRate += Fx.raw(
      (world.macro.policyRate - market.longRate).raw ~/ _longRateMonths,
    );
    // Each sector's real growth in each country.
    for (var c = 0; c < content.countries.length; c++) {
      final real = _realGrowth(content, CountryId(c));
      for (final (s, sector) in def.sectors.indexed) {
        if (!sector.byFormula) continue;
        final at = c * def.sectors.length + s;
        final rate = real + sector.growth;
        market.trends[at] += Fx.raw(
          mulDivRound(market.trends[at].raw, rate.raw, 12 * Fx.scale),
        );
      }
    }
    for (final (i, stock) in market.stocks.indexed) {
      // Its first month is already in the results it was listed with.
      if (!stock.listed || stock.since == world.today) continue;
      final listing = def.listings[i];
      if (!_stillListed(world, content, listing, economy)) {
        _delist(world, context, def, market, i);
        continue;
      }
      final month = _month(
        world,
        content,
        def,
        market,
        listing,
        stock,
        economy,
        luck: context.rng(RngStream.stocks, 4000 + i),
      );
      stock
        ..quarterRevenue = stock.quarterRevenue + month.revenue
        ..quarterProfit = stock.quarterProfit + month.profit
        ..quarterMonths += 1;
      if (listing.kind == ListingKind.formula && month.profit.isNegative) {
        stock.debt -= month.profit;
      }
    }
  }

  /// Publishes every listed company's quarter: its dividends paid, its
  /// debt paid down from what it kept, and its price moved by how far it
  /// beat or missed what was expected.
  void _quarter(
    WorldState world,
    TickContext context,
    StocksDef def,
    StockMarket market,
    CountryEconomy? economy,
  ) {
    final content = context.content;
    final rules = def.rules;
    // What the companies on each exchange pay an index's holders, each as
    // much as it counts in the index.
    final paid = List.filled(def.exchanges.length, Money.zero);
    final limits = [
      for (var e = 0; e < def.exchanges.length; e++)
        _listedCap(def, market, e).times(_indexCap),
    ];
    for (final (i, stock) in market.stocks.indexed) {
      if (!stock.listed || stock.quarterMonths == 0) continue;
      final listing = def.listings[i];
      // A quarter cut short by its listing counts as a whole one.
      final months = stock.quarterMonths;
      final revenue = Money(mulDivRound(stock.quarterRevenue.cents, 3, months));
      final profit = Money(mulDivRound(stock.quarterProfit.cents, 3, months));
      var dividends = profit > Money.zero
          ? profit.times(listing.payout)
          : Money.zero;
      if (listing.kind == ListingKind.chain) {
        final chain = chainOf(content, economy, listing)!;
        final last = chain.months.isEmpty ? null : chain.months.last;
        final reserve = last == null
            ? Money.zero
            : (last.staff + last.premises).timesInt(rules.chainReserveMonths);
        final spare = chain.cash - reserve;
        if (dividends > spare) {
          dividends = spare > Money.zero ? spare : Money.zero;
        }
        chain.cash -= dividends;
      }
      if (listing.kind == ListingKind.formula) {
        final kept = profit - dividends;
        final target = (stock.yearProfit + profit).times(listing.debt);
        if (kept > Money.zero && stock.debt > target) {
          final over = stock.debt - target;
          stock.debt -= kept < over ? kept : over;
        }
      }
      // What was expected: the same quarter a year before, grown as the
      // latest quarter grew on its own a year before.
      final sector = def.sectors[listing.sector];
      final expected = _expected(stock, sector.growth + rules.inflation);
      var base = expected.magnitude;
      final floor = revenue.times(const Fx.raw(200));
      if (base < floor) base = floor;
      if (base > Money.zero) {
        var surprise = moneyRatio(profit - expected, base);
        if (surprise > rules.maxSurprise) surprise = rules.maxSurprise;
        if (surprise < -rules.maxSurprise) surprise = -rules.maxSurprise;
        stock.mood = _clampMood(
          stock.mood + (rules.reaction * surprise).raw * 100,
          rules,
        );
      }
      stock
        ..keep(
          Results(
            day: context.day,
            revenue: revenue,
            profit: profit,
            dividends: dividends,
          ),
        )
        ..quarterRevenue = Money.zero
        ..quarterProfit = Money.zero
        ..quarterMonths = 0;
      final e = def.listingExchange[i];
      final cap = stock.cap;
      paid[e] += cap > limits[e]
          ? dividends.times(moneyRatio(limits[e], cap))
          : dividends;
      if (market.holding(i) case final holding? when dividends > Money.zero) {
        _payDividend(
          world,
          context,
          market,
          _portion(dividends, holding.units, stock.shares),
          EntryReason.stockDividend,
        );
      }
    }
    for (final (e, exchange) in market.exchanges.indexed) {
      final holding = market.holding(e, index: true);
      if (holding == null || paid[e] <= Money.zero) continue;
      // An index unit's share of what its companies paid.
      final perUnit = Money(
        mulDivRound(paid[e].cents, 100, exchange.divisor.cents),
      );
      _payDividend(
        world,
        context,
        market,
        perUnit.timesInt(holding.units),
        EntryReason.stockDividend,
      );
    }
  }

  /// Analysts' views drift and companies by formula may change their
  /// management, as the month turns.
  void _views(
    WorldState world,
    TickContext context,
    StocksDef def,
    StockMarket market,
  ) {
    final rules = def.rules;
    final fade = _ln2 ~/ rules.analystHalfLife;
    final change = Fx.raw(rules.managementChange.raw ~/ 12);
    final spread = rules.analystSpread.raw * 100;
    for (var e = 0; e < def.exchanges.length; e++) {
      final rng = context.rng(RngStream.stocks, 1000 + e);
      for (final (i, stock) in market.stocks.indexed) {
        final listing = def.listings[i];
        if (def.listingExchange[i] != e || !stock.listed) continue;
        stock.bias = _toward(stock.bias, 0, fade) + _scaled(spread, rng);
        if (listing.kind == ListingKind.formula && rng.chance(change)) {
          stock
            ..management = _grade(rng)
            ..managementSince = context.day;
          context.events.add(ManagementChanged(stock: i));
        }
      }
    }
  }

  /// A day on the exchanges: the whole market's mood, each exchange's and
  /// each company's wander, and its price is its worth a share times them.
  void _day(
    WorldState world,
    TickContext context,
    StocksDef def,
    StockMarket market,
  ) {
    final content = context.content;
    final rules = def.rules;
    final marketFade = _ln2 ~/ rules.marketHalfLife;
    final stockFade = _ln2 ~/ rules.stockHalfLife;
    final marketSpread = rules.marketSpread.raw * 100;
    final stockSpread = rules.stockSpread.raw * 100;
    final shared = rules.shared.raw;
    final cycle = world.cycle;
    final whole = _target(
      rules,
      content,
      cycle?.regime ?? world.macro.regime,
      cycle?.monthsInRegime ?? world.macro.monthsInRegime,
    );
    market.mood =
        _toward(market.mood, whole, marketFade) +
        _scaled(marketSpread, context.rng(RngStream.stocks, 0));
    for (final (e, exchange) in market.exchanges.indexed) {
      final country = def.exchanges[e].country;
      final macro = world.macroOf(country);
      final target = _target(
        rules,
        content,
        macro.regime,
        macro.monthsInRegime,
      );
      final rng = context.rng(RngStream.stocks, 1 + e);
      exchange.mood =
          _toward(exchange.mood, target, marketFade) +
          _scaled(marketSpread, rng);
      final mood =
          (market.mood * shared + exchange.mood * (Fx.scale - shared)) ~/
          Fx.scale;
      for (final (i, stock) in market.stocks.indexed) {
        if (def.listingExchange[i] != e || !stock.listed) continue;
        stock.mood = _clampMood(
          _toward(stock.mood, 0, stockFade) + _scaled(stockSpread, rng),
          rules,
        );
        stock
          ..previous = stock.price
          ..price = _price(stock, mood, rules);
      }
      final total = _indexWorth(def, market, e);
      exchange
        ..previous = exchange.level
        ..level = Money(mulDivRound(total.cents, 100, exchange.divisor.cents));
    }
  }
}

/// Makes public each of the player's stakes that crossed a multiple of
/// [stakeStep] percent since it was last, either way; a stake sold whole
/// is made public as it goes.
void _stakes(TickContext context, StockMarket market) {
  for (final holding in market.released) {
    if (!market.stocks[holding.of].listed) continue;
    context.events.add(
      StakeCrossed(stock: holding.of, percent: stakeStep, up: false),
    );
  }
  market.released.clear();
  for (final holding in market.holdings) {
    if (holding.index) continue;
    final shares = market.stocks[holding.of].shares;
    final steps = holding.units * 100 ~/ (stakeStep * shares);
    if (steps == holding.declared) continue;
    context.events.add(
      StakeCrossed(
        stock: holding.of,
        percent: (steps > holding.declared ? steps : steps + 1) * stakeStep,
        up: steps > holding.declared,
      ),
    );
    holding.declared = steps;
  }
}

/// Takes company [i] off its exchange: bought whole, its holders are paid
/// its price; failed, they get nothing. Its exchange's index carries on
/// from where it stood.
void _delist(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
  int i,
) {
  final stock = market.stocks[i];
  final e = def.listingExchange[i];
  final exchange = market.exchanges[e];
  final before = _indexWorth(def, market, e);
  final failed = _failed(world, context.content, def.listings[i]);
  stock.listed = false;
  final after = _indexWorth(def, market, e);
  if (before > Money.zero && after > Money.zero) {
    exchange.divisor = exchange.divisor.times(moneyRatio(after, before));
  }
  final holding = market.holding(i);
  context.events.add(
    StockDelisted(stock: i, failed: failed, held: holding != null),
  );
  if (holding == null) return;
  sellHolding(
    world,
    context.content,
    context.ledger,
    market,
    holding,
    holding.units,
    failed ? Money.zero : stock.price.timesInt(holding.units),
    fee: Money.zero,
  );
}

/// Pays the player [amount] of dividends from beyond the simulation, taxed
/// where they live.
void _payDividend(
  WorldState world,
  TickContext context,
  StockMarket market,
  Money amount,
  EntryReason reason,
) {
  if (amount <= Money.zero) return;
  final player = world.persons[world.player.index];
  context.ledger.pay(
    payer: world.elsewhere,
    payerAccount: AccountKind.dividends,
    payee: player,
    payeeAccount: AccountKind.dividends,
    amount: amount,
    reason: reason,
  );
  final year = context.day.date.year;
  if (market.dividendsYear != year) {
    market
      ..dividendsYear = year
      ..dividends = Money.zero;
  }
  market.dividends += amount;
  context.events.add(DividendsReceived(amount: amount));
  final content = context.content;
  if (content.taxesOf(world.residence(content, player.id)) case final taxes?) {
    final tax = amount.times(taxes.dividendRate);
    if (tax > Money.zero) {
      context.ledger.pay(
        payer: player,
        payerAccount: AccountKind.taxes,
        payee: world.government,
        payeeAccount: AccountKind.revenue,
        amount: tax,
        reason: EntryReason.dividendTax,
      );
    }
  }
}

/// Sells [units] of [holding] for [proceeds] less [fee]: the gain over what
/// they cost is taxed where the player lives, once past losses are set
/// against it. Removes the holding once empty.
void sellHolding(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  StockMarket market,
  Holding holding,
  int units,
  Money proceeds, {
  required Money fee,
}) {
  final player = world.persons[world.player.index];
  final cost = holding.units == units
      ? holding.cost
      : _portion(holding.cost, units, holding.units);
  if (proceeds > Money.zero) {
    ledger.pay(
      payer: world.elsewhere,
      payerAccount: AccountKind.investments,
      payee: player,
      payeeAccount: AccountKind.disposals,
      amount: proceeds,
      reason: EntryReason.sharesSold,
    );
  }
  if (cost > Money.zero) {
    ledger.post(
      player,
      debit: AccountKind.disposals,
      credit: AccountKind.investments,
      amount: cost,
      reason: EntryReason.sharesSold,
    );
  }
  if (fee > Money.zero) {
    ledger.pay(
      payer: player,
      payerAccount: AccountKind.spending,
      payee: world.services,
      payeeAccount: AccountKind.revenue,
      amount: fee,
      reason: EntryReason.brokerage,
    );
  }
  holding
    ..units -= units
    ..cost -= cost;
  if (holding.units == 0) {
    market.holdings.remove(holding);
    if (holding.declared > 0) market.released.add(holding);
  }
  var gain = proceeds - fee - cost;
  if (gain.isNegative) {
    market.gainsLoss -= gain;
    return;
  }
  final setOff = gain < market.gainsLoss ? gain : market.gainsLoss;
  market.gainsLoss -= setOff;
  gain -= setOff;
  if (content.taxesOf(world.residence(content, player.id)) case final taxes?
      when gain > Money.zero) {
    final tax = gain.times(taxes.dividendRate);
    if (tax > Money.zero) {
      ledger.pay(
        payer: player,
        payerAccount: AccountKind.taxes,
        payee: world.government,
        payeeAccount: AccountKind.revenue,
        amount: tax,
        reason: EntryReason.capitalGainsTax,
      );
    }
  }
}

/// What [units] of [whole] are of [amount], kept safe for share counts in
/// the billions.
Money _portion(Money amount, int units, int whole) {
  if (whole <= 0 || units <= 0) return Money.zero;
  if (units >= whole) return amount;
  // A share's part in millionths of a cent, then the units' part of that.
  final each = mulDivRound(amount.cents, _micro, whole);
  return Money(mulDivRound(each, units, _micro));
}

/// The national chain [listing] is, if it is one.
Chain? chainOf(ContentDb content, CountryEconomy? economy, ListingDef listing) {
  if (listing.kind != ListingKind.chain || economy == null) return null;
  final key = content.countries[listing.country.index].national;
  for (final country in economy.countries) {
    if (country.def.key == key) return country.chains[listing.link];
  }
  return null;
}

/// Whether [listing]'s business still trades on its own.
bool _stillListed(
  WorldState world,
  ContentDb content,
  ListingDef listing,
  CountryEconomy? economy,
) => switch (listing.kind) {
  ListingKind.formula => true,
  ListingKind.chain => switch (chainOf(content, economy, listing)) {
    final chain? => !chain.failed && chain.boughtBy == null && chain.isTrading,
    null => false,
  },
  ListingKind.software =>
    world.softwareMarket?.rivals[listing.link].status != RivalStatus.folded,
  ListingKind.producer => listing.link < world.producers.length,
};

bool _failed(WorldState world, ContentDb content, ListingDef listing) =>
    switch (listing.kind) {
      ListingKind.chain => switch (chainOf(content, world.national, listing)) {
        final chain? => chain.failed || !chain.isTrading,
        null => true,
      },
      ListingKind.software => true,
      _ => false,
    };

/// What its listed companies on exchange [e] are worth together.
Money _listedCap(StocksDef def, StockMarket market, int e) {
  var total = Money.zero;
  for (final (i, stock) in market.stocks.indexed) {
    if (stock.listed && def.listingExchange[i] == e) total += stock.cap;
  }
  return total;
}

/// What exchange [e]'s index stands on: its listed companies' worth, each
/// counting for at most [_indexCap] of all of them.
Money _indexWorth(StocksDef def, StockMarket market, int e) {
  final total = _listedCap(def, market, e);
  final limit = total.times(_indexCap);
  var counted = Money.zero;
  for (final (i, stock) in market.stocks.indexed) {
    if (!stock.listed || def.listingExchange[i] != e) continue;
    final cap = stock.cap;
    counted += cap > limit ? limit : cap;
  }
  return counted;
}

/// [listing]'s sales and its profit after interest and tax for a month at
/// today's figures; given [luck], its books by formula move on a month too,
/// its margin wandering by that luck.
({Money revenue, Money profit}) _month(
  WorldState world,
  ContentDb content,
  StocksDef def,
  StockMarket market,
  ListingDef listing,
  Listing stock,
  CountryEconomy? economy, {
  Rng? luck,
}) {
  final sector = def.sectors[listing.sector];
  final rate = content.taxesOf(listing.country)?.corporateRate ?? Fx.zero;
  Money afterTax(Money profit) =>
      profit > Money.zero ? profit - profit.times(rate) : profit;
  switch (listing.kind) {
    case ListingKind.formula:
      final rules = def.rules;
      final macro = world.macroOf(listing.country);
      if (luck != null) {
        stock.cycle +=
            (_cycleTarget(world, content, sector, listing.country) -
                stock.cycle) *
            _cycleSmoothing;
        final grade = stock.management - averageManagement;
        final growth = listing.growth + rules.managementGrowth.timesInt(grade);
        stock.share += mulDivRound(stock.share, growth.raw, 12 * Fx.scale);
        if (stock.share > _micro) stock.share = _micro;
        final aim =
            listing.margin +
            rules.managementMargin.timesInt(
              stock.management - listing.management,
            );
        stock.margin +=
            (aim - stock.margin) * rules.managementPull +
            Fx.raw(
              _scaled(
                    stock.margin.abs().raw *
                        rules.marginSpread.raw ~/
                        Fx.scale *
                        100,
                    luck,
                  ) ~/
                  100,
            );
      }
      final trend = market
          .trends[listing.country.index * def.sectors.length + listing.sector];
      final year = sector.output![listing.country.index]
          .times(macro.priceIndex)
          .times(trend)
          .times(stock.cycle);
      final revenue = Money(mulDivRound(year.cents, stock.share, 12 * _micro));
      final margin =
          stock.margin * (Fx.one + sector.leverage * (stock.cycle - Fx.one));
      var profit = revenue.times(margin);
      final interest = stock.debt > Money.zero
          ? macro.policyRate + _borrowSpread
          : macro.policyRate;
      profit -= Money(
        mulDivRound(stock.debt.cents, interest.raw, 12 * Fx.scale),
      );
      return (revenue: revenue, profit: afterTax(profit));
    case ListingKind.chain:
      final chain = chainOf(content, economy, listing);
      final last = chain == null || chain.months.isEmpty
          ? null
          : chain.months.last;
      if (last == null) return (revenue: Money.zero, profit: Money.zero);
      return (revenue: last.sales, profit: last.profit - last.tax);
    case ListingKind.software:
      final software = content.software;
      final rival = world.softwareMarket?.rivals[listing.link];
      if (software == null || rival == null || !rival.selling) {
        return (revenue: Money.zero, profit: Money.zero);
      }
      final revenue = softwareReferencePrice(
        world,
        software,
      ).times(rival.price).timesInt(rival.customers);
      final profit =
          revenue.times(sector.margin - rival.marketingShare) -
          rival.marketingBudget;
      return (revenue: revenue, profit: afterTax(profit));
    case ListingKind.producer:
      if (listing.link >= world.producers.length) {
        return (revenue: Money.zero, profit: Money.zero);
      }
      final producer = world.producers[listing.link];
      var capacity = producer.capacity;
      // A producer is sized at its first month: until then, as it will be.
      final factories = content.factories;
      final sales = factories?.sales;
      if (capacity <= Money.zero &&
          economy != null &&
          factories != null &&
          sales != null) {
        capacity = kindMarket(
          content,
          factories,
          economy,
          producer.country,
          producer.kind,
        ).times(sales.producerCapacity);
      }
      var used = capacity - producer.freeOn(world.today);
      final least = capacity.times(def.rules.producerUse);
      if (used < least) used = least;
      // Better goods sell dearer; a keener discount earns less.
      final margin =
          sector.margin +
          producer.lead * const Fx.raw(5000) -
          producer.discount;
      return (revenue: used, profit: afterTax(used.times(margin)));
  }
}

/// What company [i] of [def] is worth by its books: a year's profit times
/// the multiple rates, growth and risk set, or for software a year's sales
/// times its market's multiple; never less than its sales times its
/// sector's floor; plus its cash, less its debt.
Money stockWorth(
  WorldState world,
  ContentDb content,
  StocksDef def,
  int i,
  Listing stock,
  CountryEconomy? economy,
) {
  final listing = def.listings[i];
  final sector = def.sectors[listing.sector];
  final revenue = stock.yearRevenue;
  // Investors look ahead: half its last year's profit, half a year at its
  // latest quarter's pace; and for one by formula, half of that what it
  // earns in a normal year, as its management runs it.
  var profit = stock.yearProfit;
  if (stock.results.isNotEmpty) {
    profit = Money((profit.cents + stock.results.last.profit.cents * 4) ~/ 2);
  }
  if (listing.kind == ListingKind.formula) {
    profit = Money(
      (profit.cents +
              _normalProfit(world, content, def, listing, stock).cents) ~/
          2,
    );
  }
  var business = Money.zero;
  if (listing.kind == ListingKind.software && content.software != null) {
    business = revenue.times(_softwareMultiple(world, content, stock));
  } else if (profit > Money.zero) {
    business = profit.times(earningsMultiple(world, content, def, listing));
  }
  final floor = revenue.times(sector.floor);
  if (business < floor) business = floor;
  final cash = switch (listing.kind) {
    ListingKind.formula => -stock.debt,
    ListingKind.chain => chainOf(content, economy, listing)?.cash ?? Money.zero,
    _ => Money.zero,
  };
  final worth = business + cash;
  final least = floor.times(const Fx.raw(500));
  if (worth < least) return least > Money(100) ? least : const Money(100);
  return worth;
}

/// What company [listing] by formula earns in a normal year after interest
/// and tax: its last year's sales with the cycle taken out, at the margin
/// its management aims for.
Money _normalProfit(
  WorldState world,
  ContentDb content,
  StocksDef def,
  ListingDef listing,
  Listing stock,
) {
  final rules = def.rules;
  final cycle = stock.cycle > Fx.zero ? stock.cycle : Fx.one;
  final sales = stock.yearRevenue.times(Fx.one.div(cycle));
  final aim =
      listing.margin +
      rules.managementMargin.timesInt(stock.management - listing.management);
  final macro = world.macroOf(listing.country);
  final interest = stock.debt > Money.zero
      ? macro.policyRate + _borrowSpread
      : macro.policyRate;
  final profit = sales.times(aim) - stock.debt.times(interest);
  final rate = content.taxesOf(listing.country)?.corporateRate ?? Fx.zero;
  return profit > Money.zero ? profit - profit.times(rate) : profit;
}

/// The multiple of a year's profit [listing] is worth: one over long rates
/// plus the premium for its risk, less the growth it can keep; between the
/// rules' least and most.
Fx earningsMultiple(
  WorldState world,
  ContentDb content,
  StocksDef def,
  ListingDef listing,
) {
  final rules = def.rules;
  final sector = def.sectors[listing.sector];
  final asked =
      world.stocks!.longRate +
      rules.termPremium +
      rules.equityPremium * sector.risk -
      rules.inflation -
      _realGrowth(content, listing.country) -
      sector.growth -
      listing.growth;
  final least = Fx.one.div(rules.maxEarningsMultiple);
  final multiple = Fx.one.div(asked > least ? asked : least);
  if (multiple < rules.minEarningsMultiple) return rules.minEarningsMultiple;
  if (multiple > rules.maxEarningsMultiple) return rules.maxEarningsMultiple;
  return multiple;
}

/// A software rival's multiple of a year's sales, as investors set the
/// player's own: it grows with its growth and falls with the economy.
Fx _softwareMultiple(WorldState world, ContentDb content, Listing stock) {
  final def = content.software!;
  var growth = def.growth;
  if (stock.results.length >= 8) {
    var before = Money.zero;
    for (var q = 0; q < 4; q++) {
      before += stock.results[q].revenue;
    }
    if (before > Money.zero) {
      growth = moneyRatio(stock.yearRevenue, before) - Fx.one;
    }
  }
  var multiple =
      def.baseMultiple +
      def.growthMultiple * (growth > Fx.zero ? growth : Fx.zero);
  if (multiple > def.maxMultiple) multiple = def.maxMultiple;
  final economy =
      Fx.one + def.valuationCycle * (softwareDemand(world, content) - Fx.one);
  multiple = multiple * (economy > Fx.zero ? economy : Fx.zero);
  return multiple < def.minMultiple ? def.minMultiple : multiple;
}

/// What [stock]'s next quarter is expected to earn: the same quarter a
/// year before, grown as its latest quarter grew on its year, or by
/// [growth] while it has too few results to tell.
Money _expected(Listing stock, Fx growth) {
  final results = stock.results;
  final n = results.length;
  if (n < 4) return n == 0 ? Money.zero : results.last.profit;
  final yearAgo = results[n - 4].profit;
  var trend = growth;
  if (n >= 5) {
    final then = results[n - 5].profit;
    if (then > Money.zero) {
      trend = moneyRatio(results[n - 1].profit - then, then);
      const most = Fx.raw(5000);
      if (trend > most) trend = most;
      if (trend < -most) trend = -most;
    }
  }
  return yearAgo + yearAgo.magnitude.times(trend);
}

/// [country]'s yearly real growth in the national table, or none.
Fx _realGrowth(ContentDb content, CountryId country) {
  final key = content.countries[country.index].national;
  for (final row in content.national?.countries ?? const <NationalCountry>[]) {
    if (row.key == key) return row.realGrowth;
  }
  return Fx.zero;
}

/// Where the cycle puts [sector]'s sales in [country] against normal.
Fx _cycleTarget(
  WorldState world,
  ContentDb content,
  SectorDef sector,
  CountryId country,
) {
  final regime = content.macro.regimes[world.macroOf(country).regime.index];
  final gap = content.countries[country.index].outputGapIn(regime);
  final target = Fx.one + sector.cycle * gap;
  return target < const Fx.raw(2000) ? const Fx.raw(2000) : target;
}

/// Where a mood heads in [regime], [months] into it, in millionths: an
/// expansion's grows more euphoric the longer it lasts.
int _target(
  StockRulesDef rules,
  ContentDb content,
  RegimeId regime,
  int months,
) {
  final mood = rules.moods[regime.index];
  if (mood <= Fx.zero) return mood.raw * 100;
  var euphoria = rules.euphoria.timesInt(months);
  if (euphoria > rules.maxEuphoria) euphoria = rules.maxEuphoria;
  return (mood + euphoria).raw * 100;
}

/// [mood] after a day's fade toward [target], [fade] millionths of the way.
int _toward(int mood, int target, int fade) =>
    mood + mulDivRound(target - mood, fade, _micro);

/// A normal draw from [rng] times [spread], both in millionths.
int _scaled(int spread, Rng rng) {
  var sum = 0;
  for (var k = 0; k < 4; k++) {
    sum += rng.nextInt(_micro);
  }
  // Four uniform draws less their mean, scaled to one standard deviation.
  final z = mulDivRound(sum - 2 * _micro, 1732, 1000);
  return mulDivRound(z, spread, _micro);
}

int _clampMood(int mood, StockRulesDef rules) {
  final most = rules.maxMood.raw * 100;
  return mood > most
      ? most
      : mood < -most
      ? -most
      : mood;
}

/// A share's price: its worth a share times e to the [market]'s mood and
/// its own, at least a cent.
Money _price(Listing stock, int market, StockRulesDef rules) {
  final mood = _clampMood(market + stock.mood, rules);
  final factor = expSigned(Fx.raw(mood ~/ 100), rules.maxMood);
  final each = Money(mulDivRound(stock.worth.cents, factor.raw, Fx.scale));
  final price = Money(each.cents ~/ stock.shares);
  return price > Money.zero ? price : const Money(1);
}

/// The natural log of [a] over [b] in millionths, found by halving.
int _lnRatio(Money a, Money b) {
  if (a <= Money.zero || b <= Money.zero) return 0;
  var low = -3 * _micro;
  var high = 3 * _micro;
  final target = moneyRatio(a, b);
  for (var step = 0; step < 24; step++) {
    final middle = (low + high) ~/ 2;
    if (expSigned(Fx.raw(middle ~/ 100), Fx.fromInt(3)) < target) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) ~/ 2;
}

/// A management grade drawn as companies' are: average most often.
int _grade(Rng rng) {
  final draw = rng.nextInt(100);
  return draw < 10
      ? 0
      : draw < 30
      ? 1
      : draw < 70
      ? 2
      : draw < 90
      ? 3
      : 4;
}
