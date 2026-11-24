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
import '../state/credit.dart' show companyEarnings;
import '../countries/shop_bridge.dart' show formatTrades;
import '../state/entities.dart';
import '../state/taxation.dart' show taxGain;
import '../state/software.dart';
import '../state/software_rules.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'factory_sales.dart' show kindMarket;
import 'national.dart' show currentNational;
import 'takeovers.dart';
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
  var fromTable = 0;
  for (final stock in market.stocks) {
    if (stock.table >= 0) fromTable++;
  }
  if (fromTable < def.listings.length ||
      market.exchanges.length < def.exchanges.length ||
      market.raiders.length < def.raiders.length) {
    _open(world, content, def, market, fromTable);
  }
  return market;
}

/// The table's row for company [i] on [market], or for a company of the
/// player's listed during the game, one made from what it keeps.
ListingDef listingOf(StocksDef def, StockMarket market, int i) {
  final stock = market.stocks[i];
  if (stock.table >= 0) return def.listings[stock.table];
  final own = stock.own!;
  return ListingDef(
    ticker: own.ticker,
    name: own.name,
    country: CountryId(own.country),
    sector: own.sector,
    kind: ListingKind.company,
    link: own.company,
    share: 0,
    cap: null,
    shares: stock.shares,
    margin: Fx.zero,
    debt: Fx.zero,
    growth: Fx.zero,
    payout: Fx.zero,
    management: averageManagement,
  );
}

/// The exchange company [i] on [market] is listed on.
int exchangeOfStock(StocksDef def, StockMarket market, int i) {
  final stock = market.stocks[i];
  return stock.table >= 0
      ? def.listingExchange[stock.table]
      : def.exchangeOf(CountryId(stock.own!.country))!;
}

/// Lists every company of the table [market] lacks, at what its books are
/// worth today, or at its cap if the table gives one; and opens every
/// exchange it lacks, its index at the table's base.
void _open(
  WorldState world,
  ContentDb content,
  StocksDef def,
  StockMarket market,
  int fromTable,
) {
  final economy = currentNational(world, content);
  final rules = def.rules;
  for (var t = fromTable; t < def.listings.length; t++) {
    final listing = def.listings[t];
    final i = market.stocks.length;
    final stock = Listing(
      table: t,
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
    market.stocks.add(stock);
    stock.worth = stockWorth(world, content, def, listing, stock, economy);
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
    assert(market.stocks[i] == stock);
  }
  for (var r = market.raiders.length; r < def.raiders.length; r++) {
    market.raiders.add(Raider(cash: def.raiders[r].funds));
  }
  for (var e = market.exchanges.length; e < def.exchanges.length; e++) {
    final (:sum, :unit) = _indexWorth(def, market, e);
    final base = Money(rules.indexBase.raw ~/ 100);
    market.exchanges.add(
      Exchange(
        divisor: Money(sum <= 0 ? 1 : mulDivRound(sum, 100 * unit, base.cents)),
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
        if (!stock.running) continue;
        stock.worth = stockWorth(
          world,
          content,
          def,
          listingOf(def, market, i),
          stock,
          economy,
        );
        // One held whole is worth its books.
        if (!stock.listed) {
          stock
            ..previous = stock.price
            ..price = _price(stock, 0, def.rules);
        }
      }
      _views(world, context, def, market);
      moveRaiders(world, context, def, market);
      bidForPlayers(world, context, def, market);
    }
    _day(world, context, def, market);
    closeBids(world, context, def, market, economy);
    loseControl(market);
    if (first) payShareLoans(world, context, def, market);
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
      if (!stock.running || stock.since == world.today) continue;
      final listing = listingOf(def, market, i);
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
        director: _directorGrade(content, stock),
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
        _capLimit(_listedCap(def, market, e)),
    ];
    for (final (i, stock) in market.stocks.indexed) {
      if (!stock.running || stock.quarterMonths == 0) continue;
      final listing = listingOf(def, market, i);
      // A quarter cut short by its listing counts as a whole one.
      final months = stock.quarterMonths;
      final revenue = Money(mulDivRound(stock.quarterRevenue.cents, 3, months));
      final profit = Money(mulDivRound(stock.quarterProfit.cents, 3, months));
      var dividends = profit > Money.zero
          ? profit.times(stock.payoutLever ?? listing.payout)
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
        final target = (stock.yearProfit + profit).times(
          stock.debtLever ?? listing.debt,
        );
        if (kept > Money.zero && stock.debt > target) {
          final over = stock.debt - target;
          stock.debt -= kept < over ? kept : over;
        } else if (stock.debtLever != null && stock.debt < target) {
          // Borrowing up to what its controller aims for pays out a quarter
          // of the way at a time.
          final more = Money((target - stock.debt).cents ~/ 4);
          stock.debt += more;
          dividends += more;
        }
      }
      if (listing.kind == ListingKind.company) {
        // A company of the player's pays what its owner pays out; its
        // shareholders' part is paid as the player pays it (see
        // `ownerShare`).
        dividends = Money.zero;
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
      if (stock.listed) {
        final e = exchangeOfStock(def, market, i);
        final cap = stock.cap;
        paid[e] += cap > limits[e]
            ? dividends.times(moneyRatio(limits[e], cap))
            : dividends;
      }
      if (dividends > Money.zero) {
        for (final holding in [...market.holdings]) {
          if (holding.index || holding.of != i) continue;
          final part = _portion(dividends, holding.units, stock.shares);
          if (holding.owner == holdingOwner) {
            _payDividend(
              world,
              context,
              market,
              part,
              EntryReason.stockDividend,
            );
          } else {
            payOwner(world, context.ledger, market, holding.owner, part);
          }
        }
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
        if (!stock.running || exchangeOfStock(def, market, i) != e) continue;
        final listing = listingOf(def, market, i);
        stock.bias = _toward(stock.bias, 0, fade) + _scaled(spread, rng);
        // One its controller has given a director is run as they run it.
        if (listing.kind == ListingKind.formula &&
            stock.director == null &&
            rng.chance(change)) {
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
        if (!stock.listed || exchangeOfStock(def, market, i) != e) continue;
        stock.mood = _clampMood(
          _toward(stock.mood, 0, stockFade) + _scaled(stockSpread, rng),
          rules,
        );
        stock
          ..previous = stock.price
          ..price = _price(stock, mood, rules);
      }
      final (:sum, :unit) = _indexWorth(def, market, e);
      exchange
        ..previous = exchange.level
        ..level = Money(mulDivRound(sum, 100 * unit, exchange.divisor.cents));
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
    final percent = (steps > holding.declared ? steps : steps + 1) * stakeStep;
    final up = steps > holding.declared;
    context.events.add(
      isRaider(holding.owner)
          ? RaiderStake(
              raider: raiderOf(holding.owner),
              stock: holding.of,
              percent: percent,
              up: up,
            )
          : StakeCrossed(stock: holding.of, percent: percent, up: up),
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
  final failed = _failed(world, context.content, listingOf(def, market, i));
  final held = market.playersUnits(i) > 0;
  leaveExchange(def, market, i);
  stock.controller = null;
  context.events.add(StockDelisted(stock: i, failed: failed, held: held));
  for (final holding in [...market.holdings]) {
    if (holding.index || holding.of != i) continue;
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
}

/// Puts company [i] back on its exchange's index, which carries on from
/// where it stood.
void joinExchange(StocksDef def, StockMarket market, int i) {
  final stock = market.stocks[i];
  if (stock.listed) return;
  final e = exchangeOfStock(def, market, i);
  final exchange = market.exchanges[e];
  final before = _indexWorth(def, market, e);
  stock.listed = true;
  final after = _indexWorth(def, market, e);
  if (before.sum > 0 && after.sum > 0) {
    exchange.divisor = exchange.divisor.times(_worthRatio(after, before));
  }
}

/// Takes company [i] off its exchange's index, which carries on from where
/// it stood.
void leaveExchange(StocksDef def, StockMarket market, int i) {
  final stock = market.stocks[i];
  if (!stock.listed) return;
  final e = exchangeOfStock(def, market, i);
  final exchange = market.exchanges[e];
  final before = _indexWorth(def, market, e);
  stock.listed = false;
  final after = _indexWorth(def, market, e);
  if (before.sum > 0 && after.sum > 0) {
    exchange.divisor = exchange.divisor.times(_worthRatio(after, before));
  }
}

/// Pays [owner] [amount] from beyond the simulation: the player in person
/// or one of their companies through the books, a raider into its cash.
void payOwner(
  WorldState world,
  Ledger ledger,
  StockMarket market,
  int owner,
  Money amount, {
  EntryReason reason = EntryReason.stockDividend,
  AccountKind account = AccountKind.disposals,
}) {
  if (amount <= Money.zero) return;
  if (isRaider(owner)) {
    market.raiders[raiderOf(owner)].cash += amount;
    return;
  }
  ledger.pay(
    payer: world.elsewhere,
    payerAccount: AccountKind.investments,
    payee: owner == holdingOwner
        ? world.persons[world.player.index]
        : world.companies[owner],
    payeeAccount: account,
    amount: amount,
    reason: reason,
  );
}

/// The cash [owner] has to buy shares with.
Money ownerCash(WorldState world, StockMarket market, int owner) =>
    isRaider(owner)
    ? market.raiders[raiderOf(owner)].cash
    : owner == holdingOwner
    ? world.persons[world.player.index].accounts[AccountKind.cash]
    : world.companies[owner].accounts[AccountKind.cash];

/// [owner] buys [units] of company [of] for [value] and [fee], from beyond
/// the simulation; its holding grows and so does what it cost.
void buyHolding(
  WorldState world,
  Ledger ledger,
  StockMarket market,
  int owner,
  int of,
  int units,
  Money value, {
  Money fee = Money.zero,
  bool index = false,
}) {
  if (isRaider(owner)) {
    market.raiders[raiderOf(owner)].cash -= value + fee;
  } else {
    final payer = owner == holdingOwner
        ? world.persons[world.player.index]
        : world.companies[owner];
    if (value > Money.zero) {
      ledger.pay(
        payer: payer,
        payerAccount: AccountKind.investments,
        payee: world.elsewhere,
        payeeAccount: AccountKind.investments,
        amount: value,
        reason: EntryReason.sharesBought,
      );
    }
    if (fee > Money.zero) {
      ledger.pay(
        payer: payer,
        payerAccount: AccountKind.investments,
        payee: world.services,
        payeeAccount: AccountKind.revenue,
        amount: fee,
        reason: EntryReason.brokerage,
      );
    }
  }
  var held = market.holding(of, index: index, owner: owner);
  if (held == null) {
    held = Holding(index: index, of: of, owner: owner);
    market.holdings.add(held);
  }
  held
    ..units += units
    ..cost += value + fee;
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

/// Sells [units] of [holding] for [proceeds] less [fee]: the player's gain
/// over what they cost is taxed where they live, once past losses are set
/// against it; a company's counts in its profit; a raider's goes to its
/// cash. Removes the holding once empty.
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
  if (holding.owner != holdingOwner) {
    if (isRaider(holding.owner)) {
      market.raiders[raiderOf(holding.owner)].cash += proceeds - fee;
    } else {
      final company = world.companies[holding.owner];
      payOwner(
        world,
        ledger,
        market,
        holding.owner,
        proceeds,
        reason: EntryReason.sharesSold,
      );
      if (cost > Money.zero) {
        ledger.post(
          company,
          debit: AccountKind.disposals,
          credit: AccountKind.investments,
          amount: cost,
          reason: EntryReason.sharesSold,
        );
      }
    }
    holding
      ..units -= units
      ..cost -= cost;
    if (holding.units == 0) market.holdings.remove(holding);
    return;
  }
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
  taxGain(world, content, ledger, player, gain);
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
  ListingKind.company => world.companies[listing.link].isActive,
};

bool _failed(WorldState world, ContentDb content, ListingDef listing) =>
    switch (listing.kind) {
      ListingKind.chain => switch (chainOf(content, world.national, listing)) {
        final chain? => chain.failed || !chain.isTrading,
        null => true,
      },
      ListingKind.software => true,
      ListingKind.company =>
        world.companies[listing.link].status == CompanyStatus.liquidated,
      _ => false,
    };

/// A sum of what companies are worth, in [unit] cents. An exchange's
/// companies together pass 2^53 cents (90 trillion) once a long game's
/// economy has grown, as the owner's did in 2073; its index only divides
/// one such sum by another, so past that it counts in thousands of cents,
/// or more. While the sum fits, the unit is a cent and nothing changes.
typedef _Worth = ({int sum, int unit});

/// [caps] added up, in the smallest unit the sum fits in.
_Worth _summed(List<Money> caps) {
  for (var unit = 1; ; unit *= 1000) {
    var sum = 0;
    var fits = true;
    for (final cap in caps) {
      final part = cap.cents ~/ unit;
      if (sum > maxSafeInt - part) {
        fits = false;
        break;
      }
      sum += part;
    }
    if (fits) return (sum: sum, unit: unit);
  }
}

/// What its listed companies on exchange [e] are worth together.
_Worth _listedCap(StocksDef def, StockMarket market, int e) => _summed([
  for (final (i, stock) in market.stocks.indexed)
    if (stock.listed && exchangeOfStock(def, market, i) == e) stock.cap,
]);

/// The most one company counts for in an index on [total]: [_indexCap] of
/// it, in cents, and never past what any one company can be worth.
Money _capLimit(_Worth total) {
  final limit = mulDivRound(total.sum, _indexCap.raw, Fx.scale);
  return Money(
    limit > maxSafeInt ~/ total.unit ? maxSafeInt : limit * total.unit,
  );
}

/// What exchange [e]'s index stands on: its listed companies' worth, each
/// counting for at most [_indexCap] of all of them, in the unit their
/// worth together is counted in.
_Worth _indexWorth(StocksDef def, StockMarket market, int e) {
  final total = _listedCap(def, market, e);
  final unit = total.unit;
  final limit = mulDivRound(total.sum, _indexCap.raw, Fx.scale);
  var counted = 0;
  for (final (i, stock) in market.stocks.indexed) {
    if (!stock.listed || exchangeOfStock(def, market, i) != e) continue;
    final cap = stock.cap.cents ~/ unit;
    counted += cap > limit ? limit : cap;
  }
  return (sum: counted, unit: unit);
}

/// [after] over [before], in one unit.
Fx _worthRatio(_Worth after, _Worth before) {
  final unit = after.unit > before.unit ? after.unit : before.unit;
  return moneyRatio(
    Money(after.sum ~/ (unit ~/ after.unit)),
    Money(before.sum ~/ (unit ~/ before.unit)),
  );
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
  int? director,
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
        if (director != null && stock.management != director) {
          stock
            ..management = director
            ..managementSince = world.today;
        }
        stock.cycle +=
            (_cycleTarget(world, content, sector, listing.country) -
                stock.cycle) *
            _cycleSmoothing;
        final grade = stock.management - averageManagement;
        final growth =
            listing.growth +
            rules.managementGrowth.timesInt(grade) +
            _growthOf(stock.growthLever);
        stock.share += mulDivRound(stock.share, growth.raw, 12 * Fx.scale);
        if (stock.share > _micro) stock.share = _micro;
        final aim =
            listing.margin +
            rules.managementMargin.timesInt(
              stock.management - listing.management,
            ) +
            _marginOf(stock.growthLever);
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
    case ListingKind.company:
      final company = world.companies[listing.link];
      final own = stock.own!;
      // Its sales account is a credit, so its sales are what it fell by.
      final sales = -company.accounts[AccountKind.revenue];
      final revenue = luck == null
          ? Money.zero
          : (sales - own.revenueMark) > Money.zero
          ? sales - own.revenueMark
          : Money.zero;
      if (luck != null) own.revenueMark = sales;
      final year = companyEarnings(world, content, company.id);
      return (revenue: revenue, profit: afterTax(Money(year.cents ~/ 12)));
  }
}

/// What a controller's pace of investing adds to a company's yearly growth,
/// and to the margin it aims for.
Fx _growthOf(int lever) => switch (lever) {
  < 0 => const Fx.raw(-100),
  > 0 => const Fx.raw(300),
  _ => Fx.zero,
};
Fx _marginOf(int lever) => switch (lever) {
  < 0 => const Fx.raw(50),
  > 0 => const Fx.raw(-100),
  _ => Fx.zero,
};

/// The management grade [stock]'s director runs it as, if it has one: a
/// promoted manager as average, a seasoned director as good, a star as
/// excellent.
int? _directorGrade(ContentDb content, Listing stock) {
  final grade = stock.director;
  final grades = content.directors?.grades.length ?? 0;
  if (grade == null || grades == 0) return null;
  final best = managementGrades.length - 1;
  return best - (grades - 1 - grade);
}

/// What company [i] of [def] is worth by its books: a year's profit times
/// the multiple rates, growth and risk set, or for software a year's sales
/// times its market's multiple; never less than its sales times its
/// sector's floor; plus its cash, less its debt.
Money stockWorth(
  WorldState world,
  ContentDb content,
  StocksDef def,
  ListingDef listing,
  Listing stock,
  CountryEconomy? economy,
) {
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
  if (listing.kind == ListingKind.company && content.software != null) {
    if (softwareOf(world, CompanyId(listing.link)) case final software?) {
      return softwareWorth(world, content, content.software!, software).worth;
    }
  }
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
    ListingKind.company => () {
      final accounts = world.companies[listing.link].accounts;
      return accounts[AccountKind.cash] +
          accounts[AccountKind.payables] +
          accounts[AccountKind.loans];
    }(),
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
  final worth = stock.worth.cents;
  // A company worth so much its mood would carry it past 2^53 cents, as
  // the owner's biggest rivals were by 2074, is priced a share at once.
  final fits =
      factor <= Fx.one ||
      worth.abs() < mulDivRound(maxSafeInt, Fx.scale, factor.raw) - 1;
  final price = fits
      ? Money(mulDivRound(worth, factor.raw, Fx.scale) ~/ stock.shares)
      : Money(mulDivRound(worth, factor.raw, Fx.scale * stock.shares));
  return price > Money.zero ? price : const Money(1);
}

/// What analysts think a share of company [i] is worth: its worth a share,
/// seen through their own view and as much of the moods as they follow.
Money analystPrice(StocksDef def, StockMarket market, int i) {
  final rules = def.rules;
  final stock = market.stocks[i];
  final e = exchangeOfStock(def, market, i);
  final shared = rules.shared.raw;
  final marketMood =
      (market.mood * shared + market.exchanges[e].mood * (Fx.scale - shared)) ~/
      Fx.scale;
  final mood =
      stock.bias +
      (marketMood + stock.mood) * rules.analystsFollow.raw ~/ Fx.scale;
  final factor = expSigned(
    Fx.raw(_clampMood(mood, rules) ~/ 100),
    rules.maxMood,
  );
  return Money(
    mulDivRound(stock.worth.cents, factor.raw, Fx.scale) ~/ stock.shares,
  );
}

/// The log of [a] over [b] in millionths: how far a mood must move for a
/// price of [b] to become [a].
int moodRatio(Money a, Money b) => _lnRatio(a, b);

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

/// Where [company] would be listed, and in which sector: the country and
/// trade of its first shop, or its software's; null if the table has no
/// sector for its business.
({CountryId country, int sector})? listingPlace(
  WorldState world,
  ContentDb content,
  StocksDef def,
  Company company,
) {
  int? sectorWhere(bool Function(SectorDef) test) {
    for (final (s, sector) in def.sectors.indexed) {
      if (test(sector)) return s;
    }
    return null;
  }

  if (softwareOf(world, company.id) case final software?) {
    final sector = sectorWhere((s) => s.software);
    if (sector == null) return null;
    return (country: software.country, sector: sector);
  }
  for (final store in world.stores) {
    if (store.company != company.id || !store.isTrading) continue;
    final format = content.formats[store.format.index];
    final trade = formatTrades[format.key];
    final sector = sectorWhere((s) => s.trade != null && s.trade == trade);
    if (sector == null) return null;
    final market = content.sites[store.site.index].market;
    return (country: content.countryOf(market), sector: sector);
  }
  for (final country in world.national?.countries ?? const <CountryState>[]) {
    for (final block in country.blocks) {
      if (block.company != company.id.index || block.stores == 0) continue;
      final trade = world.national!.table.trades[block.trade].key;
      final sector = sectorWhere((s) => s.trade == trade);
      final game = content.countries.indexWhere(
        (c) => c.national == country.def.key,
      );
      if (sector == null || game < 0) return null;
      return (country: CountryId(game), sector: sector);
    }
  }
  return null;
}

/// Lists [company], one of the player's, at what its books are worth: the
/// player's holding takes every share, and [sold] of them go to the market,
/// new ones if [newShares]. Returns its position on the market.
int listOwnCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  StocksDef def,
  StockMarket market,
  Company company,
  ({CountryId country, int sector}) place,
  Fx sold, {
  required bool newShares,
}) {
  final economy = world.national;
  final rules = def.rules;
  final i = market.stocks.length;
  final stock = Listing(
    table: -1,
    since: world.today,
    shares: 1,
    price: const Money(1),
    worth: Money.zero,
    mood: 0,
    management: averageManagement,
    managementSince: Day(world.today.number - 31 * rules.unprovenMonths),
    share: 0,
    margin: Fx.zero,
    debt: Money.zero,
  );
  final taken = <String>{
    for (final listing in def.listings) listing.ticker,
    for (final other in market.stocks)
      if (other.own case final own?) own.ticker,
  };
  stock.own = OwnListing(
    company: company.id.index,
    ticker: _ticker(company.name, taken),
    name: company.name,
    country: place.country.index,
    sector: place.sector,
  )..revenueMark = -company.accounts[AccountKind.revenue];
  market.stocks.add(stock);
  final listing = listingOf(def, market, i);
  final month = _month(world, content, def, market, listing, stock, economy);
  for (var q = 4; q >= 1; q--) {
    stock.keep(
      Results(
        day: Day(world.today.number - 91 * q),
        revenue: Money.zero,
        profit: month.profit.timesInt(3),
        dividends: Money.zero,
      ),
    );
  }
  stock.worth = stockWorth(world, content, def, listing, stock, economy);
  var shares = stock.worth.cents ~/ _sharePrice.cents;
  if (shares < _fewestShares) shares = _fewestShares;
  if (shares > maxListedShares ~/ 4) shares = maxListedShares ~/ 4;
  stock.shares = shares;
  stock.price = _price(stock, 0, rules);
  stock.previous = stock.price;
  stock.closes
    ..clear()
    ..add(stock.price);
  // The player's holding takes every share, at what they put in.
  final player = world.persons[world.player.index];
  final held = Holding(index: false, of: i, units: shares)
    ..cost = company.injected;
  market.holdings.add(held);
  company.injected = Money.zero;
  // Opening an index's divisor carries on from where it stood.
  stock.listed = false;
  joinExchange(def, market, i);
  if (newShares) {
    // New shares, issued at the price, bring their money into the company.
    final issued = mulDivRound(shares, sold.raw, (Fx.one - sold).raw);
    final money = stock.price.timesInt(issued);
    stock.shares += issued;
    ledger.pay(
      payer: world.elsewhere,
      payerAccount: AccountKind.investments,
      payee: company,
      payeeAccount: AccountKind.equity,
      amount: money,
      reason: EntryReason.sharesSold,
    );
    stock.worth += money;
  } else {
    final units = mulDivRound(shares, sold.raw, Fx.scale);
    sellHolding(
      world,
      content,
      ledger,
      market,
      held,
      units,
      stock.price.timesInt(units),
      fee: Money.zero,
    );
  }
  assert(player.id == world.player);
  return i;
}

/// Up to four letters from [name], none of them [taken].
String _ticker(String name, Set<String> taken) {
  final letters = [
    for (final code in name.toUpperCase().codeUnits)
      if (code >= 65 && code <= 90) String.fromCharCode(code),
  ];
  if (letters.isEmpty) letters.add('X');
  for (var a = 1; a < letters.length; a++) {
    for (var b = a + 1; b < letters.length; b++) {
      for (var c = b + 1; c < letters.length; c++) {
        final code = letters[0] + letters[a] + letters[b] + letters[c];
        if (!taken.contains(code)) return code;
      }
    }
  }
  var n = 1;
  while (taken.contains('${letters[0]}$n')) {
    n++;
  }
  return '${letters[0]}$n';
}

/// Company [company] of the player's listed during the game, if it is
/// still on the market.
int? ownListing(StockMarket? market, CompanyId company) {
  if (market == null) return null;
  for (final (i, stock) in market.stocks.indexed) {
    if (stock.own?.company == company.index && stock.running) return i;
  }
  return null;
}
