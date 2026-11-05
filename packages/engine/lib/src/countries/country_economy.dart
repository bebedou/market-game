import '../core/calendar.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import 'country_table.dart';

/// Months of figures kept per chain and trade: enough to compare a year with
/// the one before.
const countryMonthsKept = 24;

/// Shares of a trade's sales within one class, in these parts.
const _shareScale = 100000;

/// A chain's books for one month.
final class ChainMonth {
  const ChainMonth({
    required this.start,
    required this.stores,
    required this.sales,
    required this.goods,
    required this.staff,
    required this.premises,
    required this.tax,
    required this.fitOut,
    required this.opened,
    required this.closed,
  });

  final Day start;

  /// Stores trading in the month, before those it opened or closed at its end.
  final int stores;
  final Money sales;
  final Money goods;
  final Money staff;

  /// Rent, energy and everything else that isn't goods or staff.
  final Money premises;
  final Money tax;
  final Money fitOut;
  final int opened;
  final int closed;

  /// Before tax and fit-out, and so comparable with the statistics' gross
  /// operating surplus.
  Money get profit => sales - goods - staff - premises;
}

/// What a trade came to in one country in one month, and what drove it.
final class TradeMonth {
  const TradeMonth({
    required this.start,
    required this.households,
    required this.priceIndex,
    required this.demand,
    required this.market,
  });

  final Day start;
  final int households;
  final Fx priceIndex;
  final Fx demand;

  /// What households spent in the trade.
  final Money market;
}

/// Why a chain's sales moved between two years. The lines add up exactly to
/// [after] less [before].
typedef SalesBreakdown = ({
  Money before,
  Money after,
  Money population,
  Money income,
  Money prices,
  Money economy,
  Money share,
});

/// A chain, or a trade's independents together: a block of identical stores
/// with real books, but no store of its own until someone zooms in.
final class Chain {
  Chain._(this.def, this.pull, this.perStore, this.cash)
    : stores = def.stores,
      price = def.price;

  final ChainDef def;

  /// How much a store draws against the trade's others at equal prices. Fitted
  /// at the start, so that the table's shares come out.
  final Fx pull;

  /// A store's yearly sales at the start, what its fixed costs are sized on.
  final Money perStore;
  int stores;

  /// Its prices against the trade's average.
  Fx price;
  Money cash;

  /// Months in a row with no cash.
  int monthsShort = 0;
  bool failed = false;

  /// The latest last, at most [countryMonthsKept].
  final List<ChainMonth> months = [];

  bool get isTrading => stores > 0;
}

/// A country's economy as it stands.
final class CountryState {
  CountryState._(this.def, this.households, this.spendIndex, this.chains);

  final CountryDef def;

  /// Households per class.
  final List<int> households;

  /// Real spending per household against the table's, per class and trade.
  final List<List<Fx>> spendIndex;
  final List<Chain> chains;
  Fx priceIndex = Fx.one;
  Fx wageIndex = Fx.one;

  /// Yearly real income growth rates added up over this year's months.
  Fx realGrowthThisYear = Fx.zero;

  /// Per trade, the latest last, at most [countryMonthsKept].
  late final List<List<TradeMonth>> tradeMonths = [
    for (final _ in def.trades) [],
  ];

  int get totalHouseholds => households.fold(0, (sum, n) => sum + n);
}

/// Countries run by formula, one month at a time: no shoppers, shops or dice in
/// the demand, only the statistics' households, what they spend and how that
/// divides between chains. Chance only decides when an opening or closing that
/// a rate makes due actually falls. The game doesn't call this yet.
final class CountryEconomy {
  CountryEconomy(this.table, {required this.seed})
    : today = table.startDay,
      regime = table.startRegime {
    countries = [for (final def in table.countries) _start(def)];
  }

  final CountryTable table;
  final int seed;

  /// The first of the month about to be run.
  Day today;

  /// Index of the phase of the shared cycle.
  int regime;
  late final List<CountryState> countries;

  /// A country as its table has it, each chain with the sales its share gives.
  CountryState _start(CountryDef def) {
    final trades = table.trades;
    final households = [for (final row in def.classes) row.households];
    final spendIndex = [
      for (final _ in def.classes) List.filled(trades.length, Fx.one),
    ];
    final chains = <Chain>[];
    for (final (t, _) in trades.indexed) {
      final mine = [
        for (final chain in def.chains)
          if (chain.trade == t) chain,
      ];
      final pulls = _fitPulls(def, t, mine);
      var market = Money.zero;
      for (final (c, row) in def.classes.indexed) {
        market += row.spending[t].timesInt(households[c]);
      }
      for (final (i, chain) in mine.indexed) {
        final sales = market.times(chain.share);
        chains.add(
          Chain._(
            chain,
            pulls[i],
            Money(mulDivRound(sales.cents, 1, chain.stores)),
            // Three weeks of sales: what a grocer turns over, and enough to
            // ride out a bad spell.
            Money(mulDivRound(sales.cents, 1, 18)),
          ),
        );
      }
    }
    return CountryState._(def, households, spendIndex, chains);
  }

  /// The pull per store that gives each of [chains] its share of the trade,
  /// given how its prices sit with each class.
  List<Fx> _fitPulls(CountryDef def, int trade, List<ChainDef> chains) {
    final allStores = chains.fold(0, (sum, c) => sum + c.stores);
    final pulls = [
      for (final chain in chains)
        Fx.raw(mulDivRound(chain.share.raw, allStores, chain.stores)),
    ];
    for (var round = 0; round < 40; round++) {
      final shares = List.filled(chains.length, 0);
      var total = 0;
      for (final (c, row) in def.classes.indexed) {
        final spend = row.spending[trade].timesInt(row.households).cents;
        final weights = [
          for (final (i, chain) in chains.indexed)
            _weight(chain.stores, pulls[i], trade, c, chain.price),
        ];
        final all = weights.fold(0, (sum, w) => sum + w);
        // In thousands of euros, to stay safe in the division.
        final scaled = spend ~/ 100000;
        total += scaled;
        for (final (i, w) in weights.indexed) {
          shares[i] += mulDivRound(
            scaled,
            mulDivRound(w, _shareScale, all),
            _shareScale,
          );
        }
      }
      for (final (i, chain) in chains.indexed) {
        final model = shares[i] == 0 ? 1 : shares[i];
        final target = mulDivRound(chain.share.raw, total, Fx.scale);
        pulls[i] = Fx.raw(
          mulDivRound(pulls[i].raw, target < 1 ? 1 : target, model),
        );
      }
    }
    return pulls;
  }

  /// What a chain's stores draw from a class, given where its prices sit.
  int _weight(int stores, Fx pull, int trade, int incomeClass, Fx price) {
    final def = table.trades[trade];
    final factor = table.classes[incomeClass].priceFactor;
    final gap = price - Fx.one;
    final term = gap.isNegative
        ? Fx.one.div(expNeg(def.cutResponse * factor * -gap))
        : expNeg(def.riseResponse * factor * gap);
    return stores * (pull * term).raw;
  }

  /// Runs the month starting [today] and moves on to the next.
  void advanceMonth() {
    final start = today;
    _turnCycle(start);
    for (final (i, country) in countries.indexed) {
      _macro(country);
      for (final (t, _) in table.trades.indexed) {
        _trade(i, country, t, start);
      }
    }
    final date = start.date;
    if (date.month == 12) {
      for (final country in countries) {
        _newYear(country);
      }
    }
    today = date.month == 12
        ? Day.fromDate(date.year + 1, 1, 1)
        : Day.fromDate(date.year, date.month + 1, 1);
  }

  void _turnCycle(Day start) {
    final rng = Rng.keyed(seed, RngStream.countries, start.number, 0);
    if (rng.nextInt(table.regimes[regime].meanMonths) == 0) {
      regime = (regime + 1) % table.regimes.length;
    }
  }

  /// Prices and wages move each month, on one currency and one central bank;
  /// each country's real income moves with its trend and how it takes the
  /// cycle.
  void _macro(CountryState country) {
    final phase = table.regimes[regime];
    final twelfth = Fx.raw(mulDivRound(phase.inflation.raw, 1, 12));
    final realGap = phase.realWageGrowth - table.meanRealWageGrowth;
    final real = country.def.realGrowth + country.def.cycle * realGap;
    final wages = Fx.raw(mulDivRound((phase.inflation + real).raw, 1, 12));
    country
      ..priceIndex += country.priceIndex * twelfth
      ..wageIndex += country.wageIndex * wages
      ..realGrowthThisYear += real;
  }

  void _newYear(CountryState country) {
    final def = country.def;
    for (final (c, count) in country.households.indexed) {
      country.households[c] =
          count + mulDivRound(count, def.householdGrowth.raw, Fx.scale);
    }
    final real = Fx.raw(mulDivRound(country.realGrowthThisYear.raw, 1, 12));
    for (final row in country.spendIndex) {
      for (final (t, trade) in table.trades.indexed) {
        row[t] += row[t] * (trade.incomeElasticity * real);
      }
    }
    country.realGrowthThisYear = Fx.zero;
  }

  /// What the phase of the cycle does to spending in a trade: the shop-level
  /// game's swing, cut to the size of real ones, as far as the country and the
  /// trade feel it.
  Fx demandIn(CountryDef country, int trade) {
    final swing = table.regimes[regime].demand - Fx.one;
    return Fx.one +
        swing * table.amplitude * country.cycle * table.trades[trade].cycle;
  }

  void _trade(int index, CountryState country, int t, Day start) {
    final def = country.def;
    final chains = [
      for (final chain in country.chains)
        if (chain.def.trade == t) chain,
    ];
    final demand = demandIn(def, t);
    final sales = List.filled(chains.length, Money.zero);
    var market = Money.zero;
    for (final (c, row) in def.classes.indexed) {
      final spend = Money(
        mulDivRound(
          row.spending[t]
              .timesInt(country.households[c])
              .times(country.spendIndex[c][t])
              .times(country.priceIndex)
              .times(demand)
              .cents,
          1,
          12,
        ),
      );
      market += spend;
      _divide(spend, chains, sales, t, c);
    }
    final months = country.tradeMonths[t]
      ..add(
        TradeMonth(
          start: start,
          households: country.totalHouseholds,
          priceIndex: country.priceIndex,
          demand: demand,
          market: market,
        ),
      );
    if (months.length > countryMonthsKept) months.removeAt(0);
    for (final (i, chain) in chains.indexed) {
      _books(index, country, chain, sales[i], chains, start);
    }
  }

  /// Shares out what class [c] spends, in proportion to each chain's stores,
  /// pull and prices as that class sees them. What rounding leaves goes to the
  /// biggest, so the sales add up exactly to the spending.
  void _divide(
    Money spend,
    List<Chain> chains,
    List<Money> sales,
    int trade,
    int c,
  ) {
    final weights = [
      for (final chain in chains)
        _weight(chain.stores, chain.pull, trade, c, chain.price),
    ];
    final all = weights.fold(0, (sum, w) => sum + w);
    if (all == 0) return;
    var given = Money.zero;
    var biggest = 0;
    for (final (i, weight) in weights.indexed) {
      final share = mulDivRound(weight, _shareScale, all);
      final part = Money(mulDivRound(spend.cents, share, _shareScale));
      sales[i] += part;
      given += part;
      if (weight > weights[biggest]) biggest = i;
    }
    sales[biggest] += spend - given;
  }

  /// A chain's month: costs against its sales, then openings and closings as
  /// its margin sits against what's normal in the trade, which over time
  /// brings the margin back.
  void _books(
    int countryIndex,
    CountryState country,
    Chain chain,
    Money sales,
    List<Chain> rivals,
    Day start,
  ) {
    if (!chain.isTrading) return;
    final trade = table.trades[chain.def.trade];
    final row = country.def.trades[chain.def.trade];
    final cheaper = chain.def.price.div(chain.price);
    final storesFull = Money(
      mulDivRound(chain.perStore.cents, 1, 12),
    ).timesInt(chain.stores);
    final goods = sales.times(row.goods).times(cheaper);
    final staff =
        storesFull
            .times(row.staff)
            .times(trade.staffFixed)
            .times(country.wageIndex) +
        sales
            .times(row.staff)
            .times(Fx.one - trade.staffFixed)
            .times(country.wageIndex.div(country.priceIndex))
            .times(cheaper);
    final premises = storesFull.times(row.other).times(country.priceIndex);
    final profit = sales - goods - staff - premises;
    final tax = profit.isNegative
        ? Money.zero
        : profit.times(country.def.corporateTax);

    final rng = Rng.keyed(
      seed,
      RngStream.countries,
      start.number,
      countryIndex * 1000 + country.chains.indexOf(chain) + 1,
    );
    final gap = _margin(profit, sales) - row.normalMargin;
    final due = Fx.raw(
      mulDivRound(
        chain.stores * gap.abs().raw,
        table.storeResponse.raw,
        12 * Fx.scale,
      ),
    );
    var moved = due.raw ~/ Fx.scale;
    if (rng.chance(Fx.raw(due.raw % Fx.scale))) moved++;
    var opened = 0;
    var closed = 0;
    if (gap.isNegative) {
      closed = moved > chain.stores ? chain.stores : moved;
      if (chain.def.independent && closed == chain.stores) closed--;
    } else if (!chain.cash.isNegative) {
      opened = moved;
    }
    final fitOut = chain.perStore
        .times(table.fitOut)
        .times(country.priceIndex)
        .timesInt(opened);
    chain.months.add(
      ChainMonth(
        start: start,
        stores: chain.stores,
        sales: sales,
        goods: goods,
        staff: staff,
        premises: premises,
        tax: tax,
        fitOut: fitOut,
        opened: opened,
        closed: closed,
      ),
    );
    if (chain.months.length > countryMonthsKept) chain.months.removeAt(0);
    chain
      ..stores += opened - closed
      ..cash += profit - tax - fitOut;
    chain.monthsShort = chain.cash.isNegative ? chain.monthsShort + 1 : 0;
    if (chain.monthsShort >= 12 && !chain.def.independent) {
      _fail(chain, rivals);
    }
  }

  /// A year with no cash and the chain is gone: its stores pass to the
  /// independents, under new owners.
  void _fail(Chain chain, List<Chain> rivals) {
    final heirs = rivals.firstWhere((rival) => rival.def.independent);
    heirs.stores += chain.stores;
    chain
      ..stores = 0
      ..failed = true;
  }

  static Fx _margin(Money profit, Money sales) {
    // In euros, to stay safe in the division.
    final whole = sales.cents ~/ 100;
    if (whole == 0) return Fx.zero;
    return Fx.raw(mulDivRound(profit.cents ~/ 100, Fx.scale, whole));
  }

  /// [chain]'s latest twelve months against the twelve before, or null without
  /// two full years. Population, prices and the cycle act on the sales in that
  /// order; income is what's left of the market's move, share what's left of
  /// the chain's.
  SalesBreakdown? yearOnYear(CountryState country, Chain chain) {
    final months = chain.months;
    final market = country.tradeMonths[chain.def.trade];
    if (months.length < 24 || market.length < 24) return null;
    var before = Money.zero;
    var after = Money.zero;
    var population = Money.zero;
    var income = Money.zero;
    var prices = Money.zero;
    var economy = Money.zero;
    var share = Money.zero;
    final last = market.length - months.length;
    for (var i = 0; i < 12; i++) {
      final was = months[months.length - 24 + i];
      final now = months[months.length - 12 + i];
      final tradeWas = market[last + months.length - 24 + i];
      final tradeNow = market[last + months.length - 12 + i];
      var running = was.sales;
      Money step(int to, int from) {
        final moved = Money(mulDivRound(running.cents, to, from));
        final change = moved - running;
        running = moved;
        return change;
      }

      population += step(tradeNow.households, tradeWas.households);
      prices += step(tradeNow.priceIndex.raw, tradeWas.priceIndex.raw);
      economy += step(tradeNow.demand.raw, tradeWas.demand.raw);
      // The market's whole move, in millionths, with the amounts in thousands
      // of euros, to stay safe in the division.
      final moved = mulDivRound(
        tradeNow.market.cents ~/ 100000,
        1000000,
        tradeWas.market.cents ~/ 100000,
      );
      final withMarket = Money(mulDivRound(was.sales.cents, moved, 1000000));
      income += withMarket - running;
      share += now.sales - withMarket;
      before += was.sales;
      after += now.sales;
    }
    return (
      before: before,
      after: after,
      population: population,
      income: income,
      prices: prices,
      economy: economy,
      share: share,
    );
  }
}
