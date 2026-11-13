import '../core/calendar.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';
import 'country_table.dart';

/// Parts a region's weights are counted in.
const _ppm = 1000000;

/// Months a new shop draws less, while it wins its custom.
const youngMonths = 24;

/// What a shop in its first [youngMonths] draws against a settled one, in
/// thousandths.
const _youngDraw = 800;

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
  Chain._(this.def, this.pull, this.perStore, this.cash, this.spread)
    : regional = _apportion(def.stores, spread),
      price = def.price;

  final ChainDef def;

  /// How its shops spread over its country's regions, in parts per million.
  final List<int> spread;

  /// How much a store draws against the trade's others at equal prices. Fitted
  /// at the start, so that the table's shares come out.
  final Fx pull;

  /// A store's yearly sales at the start, what its fixed costs are sized on.
  final Money perStore;

  /// Its shops in each region: spread by [spread] at the start, then where
  /// it opened and closed them.
  final List<int> regional;

  int get stores => regional.fold(0, (sum, n) => sum + n);

  /// Its prices against the trade's average.
  Fx price;
  Money cash;

  /// Months in a row with no cash.
  int monthsShort = 0;
  bool failed = false;

  /// The company that bought it, by the game's company index, whose shops
  /// its were; null while it trades on its own.
  int? boughtBy;

  /// The latest last, at most [countryMonthsKept].
  final List<ChainMonth> months = [];

  bool get isTrading => stores > 0;

  /// Its shops in each region.
  List<int> get regionalStores => regional;
}

/// A month of a company's shops in one trade of one country.
final class BlockMonth {
  const BlockMonth({
    required this.start,
    required this.stores,
    required this.sales,
    required this.goods,
    required this.marketing,
    required this.staff,
    required this.premises,
    required this.opened,
    required this.closed,
  });

  BlockMonth.read(StateReader reader)
    : start = Day(reader.readInt()),
      stores = reader.readInt(),
      sales = Money(reader.readInt()),
      goods = Money(reader.readInt()),
      marketing = Money(reader.readInt()),
      staff = Money(reader.readInt()),
      premises = Money(reader.readInt()),
      opened = reader.readInt(),
      closed = reader.readInt();

  final Day start;

  /// Shops trading in the month.
  final int stores;
  final Money sales;
  final Money goods;
  final Money marketing;
  final Money staff;
  final Money premises;

  /// Shops that started trading, and closed, at the month's start.
  final int opened;
  final int closed;

  Money get profit => sales - goods - marketing - staff - premises;

  void write(StateWriter writer) {
    writer
      ..writeInt(start.number)
      ..writeInt(stores)
      ..writeInt(sales.cents)
      ..writeInt(goods.cents)
      ..writeInt(marketing.cents)
      ..writeInt(staff.cents)
      ..writeInt(premises.cents)
      ..writeInt(opened)
      ..writeInt(closed);
  }
}

/// What a company's shops run by formula spend, as shares of sales: goods
/// and marketing of what they sell, staff and premises of what a settled
/// shop sold at the start (staff partly as they sell, as the trade's are).
/// Staff and premises are at the country's average wages and rents, which
/// each region's own scale.
typedef ShopCosts = ({Fx goods, Fx marketing, Fx staff, Fx premises});

/// The save version from which chains keep their shops by region, and the
/// national scale's later state.
const _placedVersion = 30;

/// A chain's offer to buy a company's shops run by formula across a
/// country, until [expires]. Its [block] is found again by its company,
/// trade, format and name when the offer is read from a save.
final class NationalOffer {
  NationalOffer({
    required this.number,
    required this.country,
    required this.block,
    required this.chain,
    required this.price,
    required this.expires,
  });

  final int number;

  /// The country's place in the national table.
  final int country;
  final CompanyBlock block;
  final Chain chain;
  final Money price;
  final Day expires;
}

/// The most of its sales a company spends on marketing across a country.
const maxNationalMarketing = Fx.raw(800);

/// A company's shops in one region: those settled, those in their first two
/// years by the month they opened, those still being fitted out, and the
/// last twelve months' sales and profit.
final class BlockRegion {
  BlockRegion()
    : young = List.filled(youngMonths, 0),
      sales = List.filled(12, Money.zero),
      profit = List.filled(12, Money.zero);

  BlockRegion.read(StateReader reader)
    : settled = reader.readInt(),
      pending = reader.readInt(),
      young = [for (var i = 0; i < youngMonths; i++) reader.readInt()],
      sales = [for (var i = 0; i < 12; i++) Money(reader.readInt())],
      profit = [for (var i = 0; i < 12; i++) Money(reader.readInt())];

  int settled = 0;

  /// Opened this month, trading from the next.
  int pending = 0;

  /// Shops in their first [youngMonths], by the month they started trading.
  final List<int> young;

  /// Each of the last twelve months, by month.
  final List<Money> sales;
  final List<Money> profit;

  int get youngStores => young.fold(0, (sum, n) => sum + n);

  /// Shops trading.
  int get trading => settled + youngStores;

  /// Shops trading or being fitted out.
  int get stores => trading + pending;

  /// What its shops draw against settled ones, in thousandths of a shop.
  int get drawMilli => settled * 1000 + youngStores * _youngDraw;

  Money get yearSales => sales.fold(Money.zero, (sum, m) => sum + m);
  Money get yearProfit => profit.fold(Money.zero, (sum, m) => sum + m);

  void write(StateWriter writer) {
    writer
      ..writeInt(settled)
      ..writeInt(pending);
    young.forEach(writer.writeInt);
    for (final money in sales) {
      writer.writeInt(money.cents);
    }
    for (final money in profit) {
      writer.writeInt(money.cents);
    }
  }
}

/// A company's shops of one kind in one trade of one country, run by
/// formula region by region: they draw their region's spending against the
/// chains there, as a chain's do, each a little less the more of them a
/// region holds, and keep real books.
final class CompanyBlock {
  CompanyBlock({
    required this.company,
    required this.trade,
    required this.format,
    required this.strategy,
    required this.pull,
    required this.price,
    required this.costs,
    required this.perStore,
    required int regions,
    this.name,
  }) : regions = [for (var i = 0; i < regions; i++) BlockRegion()],
       marketing = costs.marketing;

  CompanyBlock.read(StateReader reader)
    : company = reader.readInt(),
      trade = reader.readInt(),
      format = reader.readInt(),
      strategy = reader.readInt(),
      pull = Fx.raw(reader.readInt()),
      price = Fx.raw(reader.readInt()),
      costs = (
        goods: Fx.raw(reader.readInt()),
        marketing: Fx.raw(reader.readInt()),
        staff: Fx.raw(reader.readInt()),
        premises: Fx.raw(reader.readInt()),
      ),
      perStore = Money(reader.readInt()),
      regions = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          BlockRegion.read(reader),
      ],
      marketing = Fx.zero {
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      months.add(BlockMonth.read(reader));
    }
    if (reader.version >= _placedVersion) {
      discount = Fx.raw(reader.readInt());
      goodwill = Money(reader.readInt());
      marketing = Fx.raw(reader.readInt());
      name = reader.readBool() ? reader.readString() : null;
      cost = Money(reader.readInt());
    } else {
      marketing = costs.marketing;
    }
  }

  /// Whose they are, by the game's company index.
  final int company;
  final int trade;

  /// The kind of shop, by the game's format index.
  final int format;

  /// How they are run, by the game's strategy index.
  int strategy;

  /// What a settled shop draws against the trade's others at equal prices.
  final Fx pull;

  /// Its prices against the trade's average.
  Fx price;

  /// What they spend, as shares of sales.
  ShopCosts costs;

  /// A shop's yearly sales at the start: what its fixed costs are sized on.
  final Money perStore;

  /// What its suppliers take off its goods: its company's buying terms.
  Fx discount = Fx.zero;

  /// What its marketing across the country has built, losing some each
  /// month (see `BrandTuning`).
  Money goodwill = Money.zero;

  /// The share of its sales it spends on marketing: its director's choice,
  /// or else its strategy's.
  Fx marketing;

  /// The chain it was bought from, whose name it trades under; null for the
  /// company's own shops, the only ones its director opens.
  String? name;

  /// What the company paid for that chain, carried as a business asset.
  Money cost = Money.zero;

  final List<BlockRegion> regions;

  /// The latest last, at most [countryMonthsKept].
  final List<BlockMonth> months = [];

  int get stores => regions.fold(0, (sum, r) => sum + r.stores);
  int get trading => regions.fold(0, (sum, r) => sum + r.trading);

  void write(StateWriter writer) {
    writer
      ..writeInt(company)
      ..writeInt(trade)
      ..writeInt(format)
      ..writeInt(strategy)
      ..writeInt(pull.raw)
      ..writeInt(price.raw)
      ..writeInt(costs.goods.raw)
      ..writeInt(costs.marketing.raw)
      ..writeInt(costs.staff.raw)
      ..writeInt(costs.premises.raw)
      ..writeInt(perStore.cents)
      ..writeInt(regions.length);
    for (final region in regions) {
      region.write(writer);
    }
    writer.writeInt(months.length);
    for (final month in months) {
      month.write(writer);
    }
    writer
      ..writeInt(discount.raw)
      ..writeInt(goodwill.cents)
      ..writeInt(marketing.raw)
      ..writeBool(name != null);
    if (name case final name?) writer.writeString(name);
    writer.writeInt(cost.cents);
  }
}

/// [total] shared out by [weights], whole, adding up exactly: the largest
/// remainders get the units rounding leaves, the first of equals first.
List<int> _apportion(int total, List<int> weights) {
  final sum = weights.fold(0, (a, w) => a + w);
  if (sum == 0) return List.filled(weights.length, 0);
  final parts = [for (final w in weights) mulDivRound(total, w, sum)];
  var given = parts.fold(0, (a, p) => a + p);
  // Rounding may have given one too many or too few to several regions.
  final order = [for (var i = 0; i < weights.length; i++) i]
    ..sort((a, b) {
      final byWeight = weights[b].compareTo(weights[a]);
      return byWeight != 0 ? byWeight : a - b;
    });
  var i = 0;
  while (given != total && order.isNotEmpty) {
    final r = order[i % order.length];
    if (given < total) {
      parts[r]++;
      given++;
    } else if (parts[r] > 0) {
      parts[r]--;
      given--;
    }
    i++;
  }
  return parts;
}

/// What a region offers a shop of one trade, as last month had it: each
/// class's spending that month, what everyone else there draws from each
/// class, every shop of the trade there, and the region's wages and rents
/// against the country's.
typedef RegionMarket = ({
  List<Money> spend,
  List<int> others,
  int stores,
  Fx wageLevel,
  Fx rentLevel,
});

/// A country's economy as it stands.
final class CountryState {
  CountryState._(
    this.def,
    this.households,
    this.spendIndex,
    this.chains,
    this.regionWeights,
    this.wageLevels,
    this.rentLevels,
    this.costLevels,
  ) : regionSpend = [
        for (final _ in regionWeights)
          [
            for (final _ in regionWeights.first)
              List.filled(households.length, Money.zero),
          ],
      ];

  final NationalCountry def;

  /// How each trade's spending spreads over the regions, in parts per million,
  /// by trade then region: by people, and by their income as far as the
  /// trade follows income. One region for a country taken whole.
  final List<List<int>> regionWeights;

  /// Each region's wages and rents against the country's, by region.
  final List<Fx> wageLevels;
  final List<Fx> rentLevels;

  /// What a shop of each trade costs to run and to fit out in each region
  /// against the country's, by trade then region: its wages and rents,
  /// weighted as the trade spends on staff it keeps whatever it sells and on
  /// premises. Shops are as many in a region as its spending over this
  /// level: fewer and busier where they cost more, as they would be where
  /// anyone may open until a shop only earns what's normal.
  final List<List<Fx>> costLevels;

  /// Last month's spending, by trade, region and class.
  final List<List<List<Money>>> regionSpend;

  /// Companies' shops run by formula, in the order they first opened.
  final List<CompanyBlock> blocks = [];

  int get regionCount => regionWeights.first.length;

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
/// a rate makes due actually falls. The game runs it from its own start,
/// [start], with each country's phase of the cycle given month by month (see
/// [advanceMonth]).
final class CountryEconomy {
  CountryEconomy(this.table, {required this.seed, Day? start})
    : today = start ?? table.startDay,
      regime = table.startRegime {
    countries = [for (final def in table.countries) _start(def)];
  }

  final CountryTable table;
  final int seed;

  /// The first of the month about to be run.
  Day today;

  /// Months run since the start.
  int monthsRun = 0;

  /// Index of the phase of the shared cycle.
  int regime;

  /// Each country's own phase of the cycle, by [countries], when the game
  /// gives them; null for all in [regime].
  List<int>? countryRegimes;
  late final List<CountryState> countries;

  /// The phase [country] is in.
  int regimeOf(NationalCountry country) => switch (countryRegimes) {
    final regimes? => regimes[table.countries.indexOf(country)],
    null => regime,
  };

  /// A country as its table has it, each chain with the sales its share gives.
  CountryState _start(NationalCountry def) {
    final trades = table.trades;
    final tuning = table.regional;
    final households = [for (final row in def.classes) row.households];
    final spendIndex = [
      for (final _ in def.classes) List.filled(trades.length, Fx.one),
    ];
    final levels = def.regions.isEmpty ? [Fx.one] : def.incomeLevels;
    final regionWeights = [
      for (final trade in trades)
        def.regions.isEmpty
            ? [_ppm]
            : _apportion(_ppm, [
                for (final (r, region) in def.regions.indexed)
                  mulDivRound(
                    region.population,
                    (Fx.one + trade.incomeElasticity * (levels[r] - Fx.one))
                        .raw,
                    Fx.scale,
                  ),
              ]),
    ];
    Fx level(Fx response, Fx income, Fx floor) {
      final value = Fx.one + response * (income - Fx.one);
      return value < floor ? floor : value;
    }

    final wageLevels = [
      for (final income in levels) level(tuning.wages, income, Fx.parse('0.5')),
    ];
    final rentLevels = [
      for (final income in levels) level(tuning.rents, income, Fx.parse('0.5')),
    ];
    final costLevels = [
      for (final (t, trade) in trades.indexed)
        () {
          final row = def.trades[t];
          final staff = row.staff * trade.staffFixed;
          final fixed = staff + row.other;
          return [
            for (final (r, wages) in wageLevels.indexed)
              fixed <= Fx.zero
                  ? Fx.one
                  : (staff * wages + row.other * rentLevels[r]).div(fixed),
          ];
        }(),
    ];
    final chains = <Chain>[];
    for (final (t, _) in trades.indexed) {
      final mine = [
        for (final chain in def.chains)
          if (chain.trade == t) chain,
      ];
      // Shops where the spending is, fewer where they cost more to run.
      final stores = [
        for (final (r, weight) in regionWeights[t].indexed)
          mulDivRound(weight, Fx.scale, costLevels[t][r].raw),
      ];
      final spreads = [
        for (final chain in mine)
          _apportion(_ppm, [
            for (final (r, weight) in stores.indexed)
              chain.home.contains(r)
                  ? mulDivRound(weight, tuning.home.raw, Fx.scale)
                  : weight,
          ]),
      ];
      final pulls = _fitPulls(def, t, mine, regionWeights[t], spreads);
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
            spreads[i],
          ),
        );
      }
    }
    return CountryState._(
      def,
      households,
      spendIndex,
      chains,
      regionWeights,
      wageLevels,
      rentLevels,
      costLevels,
    );
  }

  /// The pull per store that gives each of [chains] its share of the trade,
  /// given how its prices sit with each class.
  List<Fx> _fitPulls(
    NationalCountry def,
    int trade,
    List<ChainDef> chains,
    List<int> regionWeights,
    List<List<int>> spreads,
  ) {
    final allStores = chains.fold(0, (sum, c) => sum + c.stores);
    final pulls = [
      for (final chain in chains)
        Fx.raw(mulDivRound(chain.share.raw, allStores, chain.stores)),
    ];
    final regional = [
      for (final (i, chain) in chains.indexed)
        _apportion(chain.stores, spreads[i]),
    ];
    for (var round = 0; round < 40; round++) {
      final shares = List.filled(chains.length, 0);
      var total = 0;
      for (final (c, row) in def.classes.indexed) {
        final spend = row.spending[trade].timesInt(row.households).cents;
        for (final (r, part) in regionWeights.indexed) {
          final weights = [
            for (final (i, chain) in chains.indexed)
              _weight(regional[i][r], pulls[i], trade, c, chain.price),
          ];
          final all = weights.fold(0, (sum, w) => sum + w);
          if (all == 0) continue;
          // In thousands of euros, to stay safe in the division.
          final scaled = mulDivRound(spend ~/ 100000, part, _ppm);
          total += scaled;
          for (final (i, w) in weights.indexed) {
            shares[i] += mulDivRound(
              scaled,
              mulDivRound(w, _shareScale, all),
              _shareScale,
            );
          }
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

  /// Runs the month starting [today] and moves on to the next: in each
  /// country's phase of [regimes], by [countries], if given, or else in the
  /// shared cycle's, which may turn first.
  void advanceMonth({List<int>? regimes}) {
    final start = today;
    if (regimes != null) {
      countryRegimes = regimes;
    } else {
      _turnCycle(start);
    }
    for (final (i, country) in countries.indexed) {
      _macro(country);
      final opened = [for (final block in country.blocks) _age(block)];
      for (final (t, _) in table.trades.indexed) {
        _trade(i, country, t, start, opened);
      }
    }
    monthsRun++;
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
    final phase = table.regimes[regimeOf(country.def)];
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
  Fx demandIn(NationalCountry country, int trade) {
    final swing = table.regimes[regimeOf(country)].demand - Fx.one;
    return Fx.one +
        swing * table.amplitude * country.cycle * table.trades[trade].cycle;
  }

  void _trade(
    int index,
    CountryState country,
    int t,
    Day start,
    List<int> opened,
  ) {
    final def = country.def;
    final chains = [
      for (final chain in country.chains)
        if (chain.def.trade == t) chain,
    ];
    final blocks = [
      for (final block in country.blocks)
        if (block.trade == t) block,
    ];
    final regional = [for (final chain in chains) chain.regionalStores];
    final regions = country.regionCount;
    final demand = demandIn(def, t);
    final sales = List.filled(chains.length, Money.zero);
    final chainSales = [
      for (final _ in chains) List.filled(regions, Money.zero),
    ];
    final blockSales = [
      for (final _ in blocks) List.filled(regions, Money.zero),
    ];
    // What a store of each company's draws, its brand counted.
    final pulls = [
      for (final block in blocks) block.pull * brandFactor(country, t, block),
    ];
    // What a company's shops draw in each region, crowding as they fill it.
    final draws = [
      for (final block in blocks)
        [
          for (var r = 0; r < regions; r++)
            _crowded(
              block.regions[r].drawMilli,
              _tradeStores(regional, blocks, r),
            ),
        ],
    ];
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
      final parts = _apportion(spend.cents, country.regionWeights[t]);
      for (var r = 0; r < regions; r++) {
        final part = Money(parts[r]);
        country.regionSpend[t][r][c] = part;
        _divide(
          part,
          [
            for (final (i, chain) in chains.indexed)
              _weight(regional[i][r], chain.pull, t, c, chain.price),
            for (final (b, block) in blocks.indexed)
              _blockWeight(draws[b][r], pulls[b], t, c, block.price),
          ],
          (i, money) {
            if (i < chains.length) {
              sales[i] += money;
              chainSales[i][r] += money;
            } else {
              blockSales[i - chains.length][r] += money;
            }
          },
        );
      }
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
      _books(index, country, chain, sales[i], chainSales[i], chains, start);
    }
    for (final (b, block) in blocks.indexed) {
      _blockBooks(country, block, blockSales[b], start, opened);
    }
  }

  /// Every shop of trade [t] in region [r]: the chains' and the companies'.
  static int _tradeStores(
    List<List<int>> regional,
    List<CompanyBlock> blocks,
    int r,
  ) {
    var total = 0;
    for (final stores in regional) {
      total += stores[r];
    }
    for (final block in blocks) {
      total += block.regions[r].trading;
    }
    return total;
  }

  /// What [drawMilli] thousandths of a company's shops draw in a region of
  /// [stores] shops of the trade: each less as they fill it, half as much
  /// once they are [RegionalTuning.saturation] of them.
  int _crowded(int drawMilli, int stores) {
    if (drawMilli == 0) return 0;
    final room = mulDivRound(
      stores * 1000,
      table.regional.saturation.raw,
      Fx.scale,
    );
    if (room == 0) return drawMilli;
    return mulDivRound(drawMilli, room, room + drawMilli);
  }

  /// A company's shops' weight against the chains', [drawMilli] being
  /// thousandths of a shop.
  int _blockWeight(int drawMilli, Fx pull, int trade, int c, Fx price) =>
      mulDivRound(drawMilli, _weight(1, pull, trade, c, price), 1000);

  /// Shares out [spend] in proportion to [weights], each part handed to
  /// [give] by index. What rounding leaves goes to the biggest, so the parts
  /// add up exactly to the spending.
  void _divide(
    Money spend,
    List<int> weights,
    void Function(int index, Money part) give,
  ) {
    final all = weights.fold(0, (sum, w) => sum + w);
    if (all == 0) return;
    var given = Money.zero;
    var biggest = 0;
    for (final (i, weight) in weights.indexed) {
      if (weight == 0) continue;
      final share = mulDivRound(weight, _shareScale, all);
      final part = Money(mulDivRound(spend.cents, share, _shareScale));
      give(i, part);
      given += part;
      if (weight > weights[biggest]) biggest = i;
    }
    give(biggest, spend - given);
  }

  /// Moves [block]'s shops on a month: those trading for two years settle,
  /// and those opened last month start trading. Returns how many started.
  int _age(CompanyBlock block) {
    final slot = monthsRun % youngMonths;
    var started = 0;
    for (final region in block.regions) {
      region
        ..settled += region.young[slot]
        ..young[slot] = region.pending;
      started += region.pending;
      region.pending = 0;
    }
    return started;
  }

  /// A company's month in one trade: each region's sales against its goods
  /// and marketing, its staff at the region's wages and its premises at the
  /// region's rents. A region that has lost more than [_closingLoss] of its sales
  /// over a year closes a settled shop.
  void _blockBooks(
    CountryState country,
    CompanyBlock block,
    List<Money> sales,
    Day start,
    List<int> opened,
  ) {
    final trade = table.trades[block.trade];
    final costs = block.costs;
    final monthly = Money(mulDivRound(block.perStore.cents, 1, 12));
    final slot = monthsRun % 12;
    var total = Money.zero;
    var goods = Money.zero;
    var marketing = Money.zero;
    var staff = Money.zero;
    var premises = Money.zero;
    var stores = 0;
    var closed = 0;
    for (final (r, region) in block.regions.indexed) {
      final trading = region.trading;
      stores += trading;
      final sold = sales[r];
      final regionGoods = sold
          .times(costs.goods)
          .times(Fx.one - block.discount);
      final regionMarketing = sold.times(block.marketing);
      final wages = country.wageIndex * country.wageLevels[r];
      final regionStaff =
          monthly
              .timesInt(trading)
              .times(costs.staff)
              .times(trade.staffFixed)
              .times(wages) +
          sold
              .times(costs.staff)
              .times(Fx.one - trade.staffFixed)
              .times(wages.div(country.priceIndex));
      final regionPremises = monthly
          .timesInt(trading)
          .times(costs.premises)
          .times(country.priceIndex)
          .times(country.rentLevels[r]);
      region.sales[slot] = sold;
      region.profit[slot] =
          sold - regionGoods - regionMarketing - regionStaff - regionPremises;
      total += sold;
      goods += regionGoods;
      marketing += regionMarketing;
      staff += regionStaff;
      premises += regionPremises;
      if (region.settled > 0 &&
          region.yearProfit.isNegative &&
          -region.yearProfit > region.yearSales.times(_closingLoss)) {
        region.settled--;
        closed++;
      }
    }
    block.goodwill =
        block.goodwill.times(Fx.one - table.brands.decay) + marketing;
    block.months.add(
      BlockMonth(
        start: start,
        stores: stores,
        sales: total,
        goods: goods,
        marketing: marketing,
        staff: staff,
        premises: premises,
        opened: opened[country.blocks.indexOf(block)],
        closed: closed,
      ),
    );
    if (block.months.length > countryMonthsKept) block.months.removeAt(0);
  }

  /// The share of a year's sales a region of a company's shops may lose
  /// before it closes one.
  static final _closingLoss = Fx.parse('0.03');

  /// A chain's month: costs against its sales, then openings and closings as
  /// its margin sits against what's normal in the trade, which over time
  /// brings the margin back.
  void _books(
    int countryIndex,
    CountryState country,
    Chain chain,
    Money sales,
    List<Money> regionSales,
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
    _place(country, chain, regionSales, opened: opened, closed: closed);
    chain.cash += profit - tax - fitOut;
    chain.monthsShort = chain.cash.isNegative ? chain.monthsShort + 1 : 0;
    if (chain.monthsShort >= 12 && !chain.def.independent) {
      _fail(chain, rivals);
    }
  }

  /// A year with no cash and the chain is gone: its stores pass to the
  /// independents, under new owners.
  void _fail(Chain chain, List<Chain> rivals) {
    final heirs = rivals.firstWhere((rival) => rival.def.independent);
    for (var r = 0; r < chain.regional.length; r++) {
      heirs.regional[r] += chain.regional[r];
      chain.regional[r] = 0;
    }
    chain.failed = true;
  }

  /// Where [chain]'s [opened] new shops go and its [closed] shops come
  /// from, by its sales in each region last month ([regionSales]): each new
  /// one where it would pay back soonest, at what it would add once it takes
  /// its share from the chain's own shops there and its fitting out at the
  /// region's cost level; each closing where a shop earns least. So rivals
  /// open where shops pay, the player's included, and leave where they
  /// don't.
  void _place(
    CountryState country,
    Chain chain,
    List<Money> regionSales, {
    required int opened,
    required int closed,
  }) {
    if (opened == 0 && closed == 0) return;
    final t = chain.def.trade;
    final trade = table.trades[t];
    final row = country.def.trades[t];
    final regions = chain.regional.length;
    final levels = country.costLevels[t];
    final cheaper = chain.def.price.div(chain.price);
    // What a euro of sales leaves once its goods and the staff that come
    // with sales are paid.
    final margin =
        Fx.one -
        (row.goods + row.staff * (Fx.one - trade.staffFixed)) * cheaper;
    final monthly = Money(mulDivRound(chain.perStore.cents, 1, 12));
    Money fixed(int r) =>
        monthly
            .times(row.staff * trade.staffFixed * country.wageIndex)
            .times(country.wageLevels[r]) +
        monthly
            .times(row.other)
            .times(country.priceIndex)
            .times(country.rentLevels[r]);
    final sold = [...regionSales];
    var total = Money.zero;
    for (final money in sold) {
      total += money;
    }
    final all = chain.stores;
    // A shop's month in region [r]: its own there, or else the chain's
    // average shop at the region's level.
    Money perShop(int r) => chain.regional[r] > 0
        ? Money(mulDivRound(sold[r].cents, 1, chain.regional[r]))
        : all == 0
        ? Money.zero
        : Money(mulDivRound(total.cents, 1, all)).times(levels[r]);
    int perLevel(Money profit, int r) =>
        mulDivRound(profit.cents, Fx.scale, levels[r].raw);
    for (var k = 0; k < closed; k++) {
      var worst = -1;
      var worstValue = 0;
      for (var r = 0; r < regions; r++) {
        if (chain.regional[r] == 0) continue;
        final value = perLevel(perShop(r).times(margin) - fixed(r), r);
        if (worst < 0 || value < worstValue) {
          worst = r;
          worstValue = value;
        }
      }
      if (worst < 0) break;
      sold[worst] -= perShop(worst);
      chain.regional[worst]--;
    }
    for (var k = 0; k < opened; k++) {
      var best = 0;
      var bestValue = 0;
      Money bestAdds = Money.zero;
      for (var r = 0; r < regions; r++) {
        final spend = country.regionSpend[t][r].fold(
          Money.zero,
          (sum, m) => sum + m,
        );
        // What it already has of the region's spending, it takes again.
        final kept = spend.cents < 100
            ? Fx.one
            : Fx.raw(
                mulDivRound(sold[r].cents ~/ 100, Fx.scale, spend.cents ~/ 100),
              );
        final adds = perShop(r).times(Fx.one - (kept > Fx.one ? Fx.one : kept));
        final value = perLevel(adds.times(margin) - fixed(r), r);
        if (r == 0 || value > bestValue) {
          best = r;
          bestValue = value;
          bestAdds = adds;
        }
      }
      sold[best] += bestAdds;
      chain.regional[best]++;
    }
  }

  static Fx _margin(Money profit, Money sales) {
    // In euros, to stay safe in the division.
    final whole = sales.cents ~/ 100;
    if (whole == 0) return Fx.zero;
    return Fx.raw(mulDivRound(profit.cents ~/ 100, Fx.scale, whole));
  }

  /// The block of [company]'s own shops of [format] in trade [trade] of
  /// [country], if it has opened any: not those of a chain it bought.
  CompanyBlock? blockOf(
    CountryState country, {
    required int company,
    required int trade,
    required int format,
  }) {
    for (final block in country.blocks) {
      if (block.company == company &&
          block.trade == trade &&
          block.format == format &&
          block.name == null) {
        return block;
      }
    }
    return null;
  }

  /// How much more a store of [block] draws in trade [trade] of [country]
  /// for what its marketing has built (see [BrandTuning]): one with no
  /// goodwill draws as its pull says.
  Fx brandFactor(CountryState country, int trade, CompanyBlock block) {
    final brands = table.brands;
    final half = _brandHalf(country, trade);
    if (brands.pull == Fx.zero || block.goodwill <= Money.zero || half == 0) {
      return Fx.one;
    }
    // In euros, to stay safe in the division.
    final goodwill = block.goodwill.cents ~/ 100;
    return Fx.one +
        brands.pull * Fx.raw(mulDivRound(goodwill, Fx.scale, goodwill + half));
  }

  /// The goodwill, in euros, at which a brand pulls half what it can in
  /// trade [trade] of [country]: [BrandTuning.half] of its latest month's
  /// market, a year of it.
  int _brandHalf(CountryState country, int trade) {
    final month = country.tradeMonths[trade].lastOrNull;
    if (month == null) return 0;
    return mulDivRound(
      month.market.cents ~/ 100 * 12,
      table.brands.half.raw,
      Fx.scale,
    );
  }

  /// The share of its sales [block] should spend on marketing across trade
  /// [trade] of [country]: what pays back the most, as a shop's manager
  /// works it out (see `StorePlan.bestMarketingShare`), with [m] what a
  /// euro of sales leaves after goods and the staff that come with sales,
  /// and its latest month's sales; never below [floor] nor above
  /// [maxNationalMarketing], in half percents.
  Fx bestMarketing(
    CountryState country,
    int trade,
    CompanyBlock block, {
    required Fx floor,
  }) {
    final brands = table.brands;
    final sales = block.months.lastOrNull?.sales ?? Money.zero;
    final half = _brandHalf(country, trade);
    if (brands.pull == Fx.zero || sales <= Money.zero || half == 0) {
      return floor;
    }
    final def = table.trades[trade];
    final m =
        Fx.one -
        block.costs.goods * (Fx.one - block.discount) -
        block.costs.staff * (Fx.one - def.staffFixed);
    if (m <= Fx.zero) return floor;
    // In thousands of euros, a month, to stay safe: one more euro of
    // marketing pays back a euro at G = √(m·w·H·R/δ) − H.
    final monthly = sales.cents ~/ 100000;
    final halfK = half ~/ 1000;
    final scaled = mulDivRound(
      mulDivRound(halfK * monthly, (m * brands.pull).raw, Fx.scale),
      Fx.scale,
      brands.decay.raw,
    );
    final goodwill = isqrt(scaled) - halfK;
    if (goodwill <= 0 || monthly == 0) return floor;
    var share = Fx.raw(mulDivRound(goodwill, brands.decay.raw, monthly));
    // In half percents.
    share = Fx.raw(share.raw ~/ 50 * 50);
    if (share < floor) return floor;
    return share > maxNationalMarketing ? maxNationalMarketing : share;
  }

  /// Opens [count] of [company]'s shops of [format] in [region] of the
  /// country at [index]: they are fitted out this month and trade from the
  /// next. Its first shops of that kind there make its block, whose settled
  /// shops then sell about [perStore] a year at today's prices where the
  /// trade's shops usually are.
  CompanyBlock open(
    int index, {
    required int company,
    required int trade,
    required int format,
    required int strategy,
    required int region,
    required int count,
    required Money perStore,
    required Fx price,
    required ShopCosts costs,
  }) {
    final country = countries[index];
    var block = blockOf(
      country,
      company: company,
      trade: trade,
      format: format,
    );
    if (block == null) {
      block = CompanyBlock(
        company: company,
        trade: trade,
        format: format,
        strategy: strategy,
        pull: pullFor(country, trade, perStore),
        price: price,
        costs: costs,
        perStore: perStore,
        regions: country.regionCount,
      );
      country.blocks.add(block);
    }
    block
      ..strategy = strategy
      ..price = price
      ..costs = costs;
    block.regions[region].pending += count;
    return block;
  }

  /// What one more settled shop of [company]'s [format] in [region] of the
  /// country at [index] would add to its sales and profit a year: as its
  /// shops there draw already, or as a first one would.
  ({Money sales, Money profit}) outlookFor(
    int index, {
    required int company,
    required int trade,
    required int format,
    required int region,
    required Money perStore,
    required Fx price,
    required ShopCosts costs,
    Fx discount = Fx.zero,
  }) {
    final country = countries[index];
    final block = blockOf(
      country,
      company: company,
      trade: trade,
      format: format,
    );
    return newShopOutlook(
      country,
      trade,
      regionMarket(country, trade, region, company: company, format: format),
      pull: block == null
          ? pullFor(country, trade, perStore)
          : block.pull * brandFactor(country, trade, block),
      price: price,
      costs: (
        goods: costs.goods * (Fx.one - (block?.discount ?? discount)),
        marketing: block?.marketing ?? costs.marketing,
        staff: costs.staff,
        premises: costs.premises,
      ),
      perStore: perStore,
      drawMilli: block?.regions[region].drawMilli ?? 0,
    );
  }

  /// [company] buys [chain] of the country at [index], for [cost]: its
  /// shops become the company's, region by region, run as [strategy] has
  /// shops of [format], under the chain's name, with the chain's pull,
  /// prices and costs. The chain trades no more.
  CompanyBlock buyChain(
    int index,
    Chain chain, {
    required int company,
    required int format,
    required int strategy,
    required Money cost,
  }) {
    final country = countries[index];
    final t = chain.def.trade;
    final row = country.def.trades[t];
    final cheaper = chain.def.price.div(chain.price);
    final block = CompanyBlock(
      company: company,
      trade: t,
      format: format,
      strategy: strategy,
      pull: chain.pull,
      price: chain.price,
      costs: (
        goods: row.goods * cheaper,
        marketing: Fx.zero,
        staff: row.staff,
        premises: row.other,
      ),
      perStore: chain.perStore,
      regions: country.regionCount,
      name: chain.def.name,
    )..cost = cost;
    for (var r = 0; r < chain.regional.length; r++) {
      block.regions[r].settled = chain.regional[r];
      chain.regional[r] = 0;
    }
    chain
      ..boughtBy = company
      ..cash = Money.zero;
    country.blocks.add(block);
    return block;
  }

  /// [buyer], a chain of the country at [index], buys [block] for [price]:
  /// its shops, settled or not, become the chain's in their regions.
  void sellBlock(int index, CompanyBlock block, Chain buyer, Money price) {
    final country = countries[index];
    for (var r = 0; r < block.regions.length; r++) {
      buyer.regional[r] += block.regions[r].stores;
    }
    buyer.cash -= price;
    country.blocks.remove(block);
    offers.removeWhere((offer) => offer.block == block);
  }

  /// Chains' offers for companies' shops run by formula, the latest last.
  final List<NationalOffer> offers = [];

  /// The number the next offer gets.
  int nextOffer = 1;

  /// Takes away [company]'s shops run by formula, everywhere: it has been
  /// wound up.
  void closeCompany(int company) {
    for (final country in countries) {
      country.blocks.removeWhere((block) => block.company == company);
    }
    offers.removeWhere((offer) => offer.block.company == company);
  }

  /// The pull that has a settled shop sell [perStore] a year at today's
  /// prices, where the trade's shops are on average: from last month's
  /// spending and the chains' draw there.
  Fx pullFor(CountryState country, int trade, Money perStore) {
    final chains = [
      for (final chain in country.chains)
        if (chain.def.trade == trade) chain,
    ];
    final regional = [for (final chain in chains) chain.regionalStores];
    var weighted = 0;
    var stores = 0;
    for (var r = 0; r < country.regionCount; r++) {
      var here = 0;
      var sold = 0;
      for (final (c, spend) in country.regionSpend[trade][r].indexed) {
        var others = 0;
        for (final (i, chain) in chains.indexed) {
          others += _weight(regional[i][r], chain.pull, trade, c, chain.price);
        }
        final one = _weight(1, Fx.one, trade, c, Fx.one);
        if (others + one == 0) continue;
        sold += mulDivRound(spend.cents, one, others + one);
      }
      for (final stores in regional) {
        here += stores[r];
      }
      // In euros, weighted by shops, to stay safe in the products.
      weighted += sold ~/ 100 * here;
      stores += here;
    }
    final monthly = stores == 0 ? 0 : weighted ~/ stores;
    if (monthly == 0) return Fx.one;
    final wanted = mulDivRound(
      perStore.times(country.priceIndex).cents ~/ 100,
      1,
      12,
    );
    return Fx.raw(mulDivRound(wanted, Fx.scale, monthly));
  }

  /// What region [r] of [country] offers a shop of trade [trade], as last
  /// month had it: each class's spending, and what everyone but [company]'s
  /// block of [format] draws there.
  RegionMarket regionMarket(
    CountryState country,
    int trade,
    int r, {
    int? company,
    int? format,
  }) {
    final chains = [
      for (final chain in country.chains)
        if (chain.def.trade == trade) chain,
    ];
    final blocks = [
      for (final block in country.blocks)
        if (block.trade == trade) block,
    ];
    final regional = [for (final chain in chains) chain.regionalStores];
    final stores = _tradeStores(regional, blocks, r);
    final others = [
      for (final (c, _) in country.def.classes.indexed)
        () {
          var weight = 0;
          for (final (i, chain) in chains.indexed) {
            weight += _weight(
              regional[i][r],
              chain.pull,
              trade,
              c,
              chain.price,
            );
          }
          for (final block in blocks) {
            if (block.company == company && block.format == format) continue;
            weight += _blockWeight(
              _crowded(block.regions[r].drawMilli, stores),
              block.pull,
              trade,
              c,
              block.price,
            );
          }
          return weight;
        }(),
    ];
    return (
      spend: List<Money>.unmodifiable(country.regionSpend[trade][r]),
      others: List<int>.unmodifiable(others),
      stores: stores,
      wageLevel: country.wageLevels[r],
      rentLevel: country.rentLevels[r],
    );
  }

  /// What one more settled shop would add to a block's sales and profit a
  /// year in a region offering [market], its shops there drawing [drawMilli]
  /// thousandths of a shop already: what it takes from everyone, and from the
  /// block's own shops as the region fills, less its goods, marketing,
  /// staff and premises.
  ({Money sales, Money profit}) newShopOutlook(
    CountryState country,
    int trade,
    RegionMarket market, {
    required Fx pull,
    required Fx price,
    required ShopCosts costs,
    required Money perStore,
    int drawMilli = 0,
  }) {
    final before = _crowded(drawMilli, market.stores);
    final after = _crowded(drawMilli + 1000, market.stores + 1);
    var monthly = 0;
    for (final (c, spend) in market.spend.indexed) {
      final others = market.others[c];
      int sold(int draw) {
        final weight = _blockWeight(draw, pull, trade, c, price);
        return others + weight == 0
            ? 0
            : mulDivRound(spend.cents, weight, others + weight);
      }

      monthly += sold(after) - sold(before);
    }
    final sales = Money(monthly).timesInt(12);
    final def = table.trades[trade];
    final wages = country.wageIndex * market.wageLevel;
    final staff =
        perStore.times(costs.staff).times(def.staffFixed).times(wages) +
        sales
            .times(costs.staff)
            .times(Fx.one - def.staffFixed)
            .times(wages.div(country.priceIndex));
    final premises = perStore
        .times(costs.premises)
        .times(country.priceIndex)
        .times(market.rentLevel);
    return (
      sales: sales,
      profit:
          sales -
          sales.times(costs.goods) -
          sales.times(costs.marketing) -
          staff -
          premises,
    );
  }

  /// Writes what changes as the months run, for a saved game: the tables'
  /// own figures and the chains' pull are worked out again on reading.
  void write(StateWriter writer) {
    writer
      ..writeInt(today.number)
      ..writeInt(regime)
      ..writeInt(monthsRun)
      ..writeBool(countryRegimes != null);
    if (countryRegimes case final regimes?) {
      writer.writeInt(regimes.length);
      regimes.forEach(writer.writeInt);
    }
    for (final country in countries) {
      country.households.forEach(writer.writeInt);
      for (final row in country.spendIndex) {
        for (final index in row) {
          writer.writeInt(index.raw);
        }
      }
      writer
        ..writeInt(country.priceIndex.raw)
        ..writeInt(country.wageIndex.raw)
        ..writeInt(country.realGrowthThisYear.raw);
      for (final months in country.tradeMonths) {
        writer.writeInt(months.length);
        for (final month in months) {
          writer
            ..writeInt(month.start.number)
            ..writeInt(month.households)
            ..writeInt(month.priceIndex.raw)
            ..writeInt(month.demand.raw)
            ..writeInt(month.market.cents);
        }
      }
      for (final trade in country.regionSpend) {
        for (final region in trade) {
          for (final spend in region) {
            writer.writeInt(spend.cents);
          }
        }
      }
      for (final chain in country.chains) {
        writer.writeInt(chain.regional.length);
        chain.regional.forEach(writer.writeInt);
        writer
          ..writeInt(chain.price.raw)
          ..writeInt(chain.cash.cents)
          ..writeInt(chain.monthsShort)
          ..writeBool(chain.failed)
          ..writeNullableInt(chain.boughtBy)
          ..writeInt(chain.months.length);
        for (final month in chain.months) {
          writer
            ..writeInt(month.start.number)
            ..writeInt(month.stores)
            ..writeInt(month.sales.cents)
            ..writeInt(month.goods.cents)
            ..writeInt(month.staff.cents)
            ..writeInt(month.premises.cents)
            ..writeInt(month.tax.cents)
            ..writeInt(month.fitOut.cents)
            ..writeInt(month.opened)
            ..writeInt(month.closed);
        }
      }
      writer.writeInt(country.blocks.length);
      for (final block in country.blocks) {
        block.write(writer);
      }
    }
    writer
      ..writeInt(nextOffer)
      ..writeInt(offers.length);
    for (final offer in offers) {
      final country = countries[offer.country];
      writer
        ..writeInt(offer.number)
        ..writeInt(offer.country)
        ..writeInt(country.blocks.indexOf(offer.block))
        ..writeInt(country.chains.indexOf(offer.chain))
        ..writeInt(offer.price.cents)
        ..writeInt(offer.expires.number);
    }
  }

  /// Reads what [write] wrote over this economy, made afresh from the same
  /// table and seed.
  void read(StateReader reader) {
    today = Day(reader.readInt());
    regime = reader.readInt();
    monthsRun = reader.readInt();
    countryRegimes = reader.readBool()
        ? [for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt()]
        : null;
    for (final country in countries) {
      for (var c = 0; c < country.households.length; c++) {
        country.households[c] = reader.readInt();
      }
      for (final row in country.spendIndex) {
        for (var t = 0; t < row.length; t++) {
          row[t] = Fx.raw(reader.readInt());
        }
      }
      country
        ..priceIndex = Fx.raw(reader.readInt())
        ..wageIndex = Fx.raw(reader.readInt())
        ..realGrowthThisYear = Fx.raw(reader.readInt());
      for (final months in country.tradeMonths) {
        months.clear();
        for (var i = 0, n = reader.readInt(); i < n; i++) {
          months.add(
            TradeMonth(
              start: Day(reader.readInt()),
              households: reader.readInt(),
              priceIndex: Fx.raw(reader.readInt()),
              demand: Fx.raw(reader.readInt()),
              market: Money(reader.readInt()),
            ),
          );
        }
      }
      for (final trade in country.regionSpend) {
        for (final region in trade) {
          for (var c = 0; c < region.length; c++) {
            region[c] = Money(reader.readInt());
          }
        }
      }
      for (final chain in country.chains) {
        // Saves before chains placed their own shops kept only a count,
        // spread as at the start.
        final regional = reader.version >= _placedVersion
            ? [
                for (var i = 0, n = reader.readInt(); i < n; i++)
                  reader.readInt(),
              ]
            : _apportion(reader.readInt(), chain.spread);
        chain.regional.setAll(0, regional);
        chain
          ..price = Fx.raw(reader.readInt())
          ..cash = Money(reader.readInt())
          ..monthsShort = reader.readInt()
          ..failed = reader.readBool()
          ..boughtBy = reader.version >= _placedVersion
              ? reader.readNullableInt()
              : null;
        chain.months.clear();
        for (var i = 0, n = reader.readInt(); i < n; i++) {
          chain.months.add(
            ChainMonth(
              start: Day(reader.readInt()),
              stores: reader.readInt(),
              sales: Money(reader.readInt()),
              goods: Money(reader.readInt()),
              staff: Money(reader.readInt()),
              premises: Money(reader.readInt()),
              tax: Money(reader.readInt()),
              fitOut: Money(reader.readInt()),
              opened: reader.readInt(),
              closed: reader.readInt(),
            ),
          );
        }
      }
      country.blocks.clear();
      for (var i = 0, n = reader.readInt(); i < n; i++) {
        country.blocks.add(CompanyBlock.read(reader));
      }
    }
    offers.clear();
    if (reader.version >= _placedVersion) {
      nextOffer = reader.readInt();
      for (var i = 0, n = reader.readInt(); i < n; i++) {
        final number = reader.readInt();
        final index = reader.readInt();
        final country = countries[index];
        offers.add(
          NationalOffer(
            number: number,
            country: index,
            block: country.blocks[reader.readInt()],
            chain: country.chains[reader.readInt()],
            price: Money(reader.readInt()),
            expires: Day(reader.readInt()),
          ),
        );
      }
    }
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
