import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import '../systems/stocks.dart' show chainOf, earningsMultiple;

/// What analysts say of a stock, from strong sell to strong buy.
enum AnalystRating { strongSell, sell, hold, buy, strongBuy }

/// A listed company, as anyone sees it.
typedef StockView = ({
  /// Its position in the table.
  int index,
  String ticker,
  String name,
  CountryId country,

  /// By position in the table's sectors.
  int sector,
  ListingKind kind,

  /// False once it has left its exchange.
  bool listed,

  /// A share's price today and at yesterday's close, its shares, and what
  /// they are worth together.
  Money price,
  Money previous,
  int shares,
  Money cap,

  /// Its last four quarters' sales, profit after interest and tax, and
  /// dividends.
  Money yearRevenue,
  Money yearProfit,
  Money yearDividends,

  /// Its price over a share's profit, and the same on average over the
  /// months it has been listed; null while it loses money.
  Fx? multiple,
  Fx? averageMultiple,

  /// Its net debt in years of profit; null without debt or profit.
  Fx? debtYears,
  AnalystRating rating,

  /// How well it is run, by `managementGrades`; null while unproven.
  int? management,

  /// Its price on the first of each month, oldest first.
  List<Money> closes,

  /// Its shops, for a chain; its customers, for software; null otherwise.
  int? stores,
  int? customers,
});

/// A country's exchange and its index, as anyone sees them.
typedef ExchangeView = ({
  int index,
  CountryId country,
  String name,
  String indexName,

  /// The price of one unit of its index, today and at yesterday's close.
  Money level,
  Money previous,
  List<Money> closes,
});

/// What the player holds: of a company, or of an exchange's index.
typedef HoldingView = ({
  bool index,
  int of,
  int units,

  /// What they paid, fees included, and what the units are worth today.
  Money cost,
  Money value,
});

/// The stock market as the player sees it.
typedef StockMarketView = ({
  List<ExchangeView> exchanges,
  List<StockView> stocks,
  List<HoldingView> holdings,

  /// What the player's holdings are worth, and cost.
  Money worth,
  Money cost,

  /// Dividends received this year, before tax, and losses on sales not yet
  /// set against a gain.
  Money dividends,
  Money lossCarried,
});

/// The stock market of [world], as the player sees it; null without one.
StockMarketView? stockMarketView(WorldState world, ContentDb content) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) return null;
  final rules = def.rules;
  final economy = world.national;
  final stocks = <StockView>[];
  for (final (i, stock) in market.stocks.indexed) {
    final listing = def.listings[i];
    final e = def.listingExchange[i];
    final profit = stock.yearProfit;
    final multiple = profit > Money.zero ? stock.multiple : null;
    // Analysts see its worth through their own view and half the mood.
    final exchange = market.exchanges[e];
    final shared = rules.shared.raw;
    final marketMood =
        (market.mood * shared + exchange.mood * (Fx.scale - shared)) ~/
        Fx.scale;
    final mood = marketMood + stock.mood;
    final follow = rules.analystsFollow.raw;
    final upside = stock.bias - mood * (Fx.scale - follow) ~/ Fx.scale;
    var rating = 0;
    for (final step in rules.ratings) {
      if (upside >= step.raw * 100) rating++;
    }
    final chain = chainOf(content, economy, listing);
    final debt = switch (listing.kind) {
      ListingKind.formula => stock.debt,
      ListingKind.chain => -(chain?.cash ?? Money.zero),
      _ => Money.zero,
    };
    stocks.add((
      index: i,
      ticker: listing.ticker,
      name: listing.name,
      country: listing.country,
      sector: listing.sector,
      kind: listing.kind,
      listed: stock.listed,
      price: stock.price,
      previous: stock.previous,
      shares: stock.shares,
      cap: stock.cap,
      yearRevenue: stock.yearRevenue,
      yearProfit: profit,
      yearDividends: stock.yearDividends,
      multiple: multiple,
      averageMultiple: _average(stock.multiples),
      debtYears: debt > Money.zero && profit > Money.zero
          ? moneyRatio(debt, profit)
          : null,
      rating: AnalystRating.values[rating],
      management: _management(world, content, def, listing, stock),
      closes: List.unmodifiable(stock.closes),
      stores: chain?.stores,
      customers: listing.kind == ListingKind.software
          ? world.softwareMarket?.rivals[listing.link].customers
          : null,
    ));
  }
  final exchanges = [
    for (final (e, exchange) in market.exchanges.indexed)
      (
        index: e,
        country: def.exchanges[e].country,
        name: def.exchanges[e].name,
        indexName: def.exchanges[e].index,
        level: exchange.level,
        previous: exchange.previous,
        closes: List<Money>.unmodifiable(exchange.closes),
      ),
  ];
  var worth = Money.zero;
  var cost = Money.zero;
  final holdings = <HoldingView>[];
  for (final holding in market.holdings) {
    final price = holding.index
        ? market.exchanges[holding.of].level
        : market.stocks[holding.of].price;
    final value = price.timesInt(holding.units);
    worth += value;
    cost += holding.cost;
    holdings.add((
      index: holding.index,
      of: holding.of,
      units: holding.units,
      cost: holding.cost,
      value: value,
    ));
  }
  return (
    exchanges: List.unmodifiable(exchanges),
    stocks: List.unmodifiable(stocks),
    holdings: List.unmodifiable(holdings),
    worth: worth,
    cost: cost,
    dividends: market.dividendsYear == world.today.date.year
        ? market.dividends
        : Money.zero,
    lossCarried: market.gainsLoss,
  );
}

/// What the player's holdings in [market] are worth at today's prices.
Money portfolioWorth(StockMarket? market) {
  if (market == null) return Money.zero;
  var worth = Money.zero;
  for (final holding in market.holdings) {
    final price = holding.index
        ? market.exchanges[holding.of].level
        : market.stocks[holding.of].price;
    worth += price.timesInt(holding.units);
  }
  return worth;
}

/// The average of [multiples] that were positive, or null if none.
Fx? _average(List<Fx> multiples) {
  var sum = 0;
  var n = 0;
  for (final multiple in multiples) {
    if (multiple <= Fx.zero) continue;
    sum += multiple.raw;
    n++;
  }
  return n == 0 ? null : Fx.raw(sum ~/ n);
}

/// How well [listing] is run, as its record shows: a company by formula's
/// management once it has had time to prove itself; a chain's margin
/// against its trade's normal one; a software rival's or a producer's lead.
int? _management(
  WorldState world,
  ContentDb content,
  StocksDef def,
  ListingDef listing,
  Listing stock,
) {
  int byScale(Fx value, List<int> steps) {
    var grade = 0;
    for (final step in steps) {
      if (value.raw >= step) grade++;
    }
    return grade;
  }

  switch (listing.kind) {
    case ListingKind.formula:
      final months = def.rules.unprovenMonths;
      if (world.today.number - stock.managementSince.number < 30 * months) {
        return null;
      }
      return stock.management;
    case ListingKind.chain:
      final chain = chainOf(content, world.national, listing);
      if (chain == null || chain.months.isEmpty) return null;
      var sales = Money.zero;
      var profit = Money.zero;
      for (final month in chain.months) {
        sales += month.sales;
        profit += month.profit;
      }
      if (sales <= Money.zero) return null;
      final country = world.national!.countries.firstWhere(
        (c) => c.def.key == content.countries[listing.country.index].national,
      );
      final normal = country.def.trades[chain.def.trade].normalMargin;
      final margin = moneyRatio(profit, sales);
      return byScale(margin - normal, const [-300, -100, 100, 300]);
    case ListingKind.software:
      final market = world.softwareMarket;
      if (market == null) return null;
      final rival = market.rivals[listing.link];
      return byScale(rival.level - market.standard, const [
        -1000,
        -300,
        300,
        1000,
      ]);
    case ListingKind.producer:
      if (listing.link >= world.producers.length) return null;
      final lead = world.producers[listing.link].lead;
      return byScale(lead, const [-400, -150, 150, 400]);
  }
}

/// What [listing] is worth to the market today against its books: its
/// multiple of a year's profit, for tools and tests.
Fx stockMultiple(WorldState world, ContentDb content, int i) =>
    earningsMultiple(
      world,
      content,
      content.stocks!,
      content.stocks!.listings[i],
    );
