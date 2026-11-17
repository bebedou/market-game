import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import '../systems/stocks.dart'
    show analystPrice, chainOf, earningsMultiple, exchangeOfStock, listingOf;
import '../systems/takeovers.dart' show acceptingUnits;

/// What analysts say of a stock, from strong sell to strong buy.
enum AnalystRating { strongSell, sell, hold, buy, strongBuy }

/// Who holds shares of a company, and how many: see [holdingOwner].
typedef HolderView = ({int owner, int units});

/// A listed company, as anyone sees it.
typedef StockView = ({
  /// Its position on the market.
  int index,
  String ticker,
  String name,
  CountryId country,

  /// By position in the table's sectors.
  int sector,
  ListingKind kind,

  /// False once it has left its exchange.
  bool listed,

  /// Whether it still trades: listed, or held whole by whoever took it over.
  bool running,

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

  /// How far its sales grew: its last four quarters' against the four
  /// before, or, with less than two years of results, its latest quarter's
  /// against the same quarter a year before; null with less than that.
  Fx? salesGrowth,

  /// Its net debt in years of profit; null without debt or profit.
  Fx? debtYears,
  AnalystRating rating,

  /// What analysts think a share worth.
  Money analysts,

  /// How well it is run, by `managementGrades`; null while unproven.
  int? management,

  /// Its price on the first of each month, oldest first.
  List<Money> closes,

  /// Its shops, for a chain; its customers, for software; null otherwise.
  int? stores,
  int? customers,

  /// The player's and their companies' holdings of it, and anyone else's
  /// stake made public (5% or more), biggest first.
  List<HolderView> holders,

  /// Who controls it, if anyone took it over: see [holdingOwner].
  int? controller,

  /// What its controller set, for a company by formula: see
  /// `Listing.payoutLever`.
  Fx? payoutLever,
  int growthLever,
  Fx? debtLever,
  int? director,

  /// For a company of the player's listed during the game, the company.
  CompanyId? company,
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

/// What the player or one of their companies holds: of a company, or of
/// an exchange's index.
typedef HoldingView = ({
  bool index,
  int of,
  int units,

  /// Who: the player's holding ([holdingOwner]) or a company by its index.
  int owner,

  /// What they paid, fees included, and what the units are worth today.
  Money cost,
  Money value,
});

/// A bid for a listed company, as anyone sees it.
typedef BidView = ({
  int number,
  int stock,

  /// Who bids: see [holdingOwner]; and the company it would merge into, by
  /// its position on the market, or -1.
  int bidder,
  int via,

  /// What it offers a share, and what a share was worth to its holders
  /// when it opened.
  Money price,
  Money reference,
  Day opened,
  Day closes,
  BidStatus status,

  /// Whether the player offers their shares into it.
  bool tender,

  /// What share of the company would accept it today, or did when it
  /// closed.
  Fx accepting,
});

/// A raider, as anyone sees it.
typedef RaiderView = ({
  String name,
  RaiderStyle style,

  /// Its money and its shares at today's prices, together.
  Money worth,

  /// The companies it holds stakes in, by position on the market, biggest
  /// first.
  List<int> stakes,
});

/// A loan of the player's holding, secured on shares.
typedef ShareLoanView = ({
  int number,
  int stock,
  Money outstanding,
  Fx rate,
  int installmentsLeft,
});

/// The stock market as the player sees it.
typedef StockMarketView = ({
  List<ExchangeView> exchanges,
  List<StockView> stocks,

  /// The player's and their companies'.
  List<HoldingView> holdings,

  /// What the player's own holdings are worth, and cost.
  Money worth,
  Money cost,

  /// Dividends received this year, before tax, and losses on sales not yet
  /// set against a gain.
  Money dividends,
  Money lossCarried,
  List<BidView> bids,
  List<RaiderView> raiders,
  List<ShareLoanView> loans,
});

/// The stock market of [world], as the player sees it; null without one.
StockMarketView? stockMarketView(WorldState world, ContentDb content) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) return null;
  final rules = def.rules;
  final economy = world.national;
  // Every holder of each company, the biggest first.
  final holders = [for (final _ in market.stocks) <HolderView>[]];
  for (final holding in market.holdings) {
    if (holding.index) continue;
    final stock = market.stocks[holding.of];
    final public = holding.units * 100 >= stakeStep * stock.shares;
    if (isPlayers(holding.owner) || public) {
      holders[holding.of].add((owner: holding.owner, units: holding.units));
    }
  }
  for (final list in holders) {
    list.sort((a, b) => b.units.compareTo(a.units));
  }
  final stocks = <StockView>[];
  for (final (i, stock) in market.stocks.indexed) {
    final listing = listingOf(def, market, i);
    final e = exchangeOfStock(def, market, i);
    final profit = stock.yearProfit;
    final multiple = profit > Money.zero ? stock.multiple : null;
    // Analysts see its worth through their own view and part of the mood.
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
      running: stock.running,
      price: stock.price,
      previous: stock.previous,
      shares: stock.shares,
      cap: stock.cap,
      yearRevenue: stock.yearRevenue,
      yearProfit: profit,
      yearDividends: stock.yearDividends,
      multiple: multiple,
      averageMultiple: _average(stock.multiples),
      salesGrowth: _salesGrowth(stock.results),
      debtYears: debt > Money.zero && profit > Money.zero
          ? moneyRatio(debt, profit)
          : null,
      rating: AnalystRating.values[rating],
      analysts: stock.running ? analystPrice(def, market, i) : stock.price,
      management: _management(world, content, def, listing, stock),
      closes: List.unmodifiable(stock.closes),
      stores: chain?.stores,
      customers: listing.kind == ListingKind.software
          ? world.softwareMarket?.rivals[listing.link].customers
          : null,
      holders: List.unmodifiable(holders[i]),
      controller: stock.controller,
      payoutLever: stock.payoutLever,
      growthLever: stock.growthLever,
      debtLever: stock.debtLever,
      director: stock.director,
      company: listing.kind == ListingKind.company
          ? CompanyId(listing.link)
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
    if (!isPlayers(holding.owner)) continue;
    final value = _priceOf(market, holding).timesInt(holding.units);
    if (holding.owner == holdingOwner) {
      worth += value;
      cost += holding.cost;
    }
    holdings.add((
      index: holding.index,
      of: holding.of,
      units: holding.units,
      owner: holding.owner,
      cost: holding.cost,
      value: value,
    ));
  }
  final bids = [
    for (final bid in market.bids)
      (
        number: bid.number,
        stock: bid.stock,
        bidder: bid.bidder,
        via: bid.via,
        price: bid.price,
        reference: bid.reference,
        opened: bid.opened,
        closes: bid.closes,
        status: bid.status,
        tender: bid.tender,
        accepting: Fx.raw(
          (bid.status == BidStatus.open
                  ? acceptingUnits(def, market, bid)
                  : bid.accepted) *
              Fx.scale ~/
              market.stocks[bid.stock].shares,
        ),
      ),
  ];
  final raiders = [
    for (final (r, raider) in market.raiders.indexed)
      if (r < def.raiders.length) _raiderView(def, market, r, raider),
  ];
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
    bids: List.unmodifiable(bids),
    raiders: List.unmodifiable(raiders),
    loans: List.unmodifiable([
      for (final loan in market.loans)
        (
          number: loan.number,
          stock: loan.stock,
          outstanding: loan.outstanding,
          rate: loan.rate,
          installmentsLeft: loan.installmentsLeft,
        ),
    ]),
  );
}

RaiderView _raiderView(
  StocksDef def,
  StockMarket market,
  int r,
  Raider raider,
) {
  final owner = raiderOwner(r);
  var worth = raider.cash;
  final stakes = <(int, Money)>[];
  for (final holding in market.holdings) {
    if (holding.owner != owner || holding.index) continue;
    final value = _priceOf(market, holding).timesInt(holding.units);
    worth += value;
    stakes.add((holding.of, value));
  }
  stakes.sort((a, b) => b.$2.cents.compareTo(a.$2.cents));
  return (
    name: def.raiders[r].name,
    style: def.raiders[r].style,
    worth: worth,
    stakes: List.unmodifiable([for (final (i, _) in stakes) i]),
  );
}

Money _priceOf(StockMarket market, Holding holding) => holding.index
    ? market.exchanges[holding.of].level
    : market.stocks[holding.of].price;

/// What the player's own holdings in [market] are worth at today's prices;
/// their companies' count in their companies' books.
Money portfolioWorth(StockMarket? market) {
  if (market == null) return Money.zero;
  var worth = Money.zero;
  for (final holding in market.holdings) {
    if (holding.owner != holdingOwner) continue;
    worth += _priceOf(market, holding).timesInt(holding.units);
  }
  return worth;
}

/// How far sales grew over [results], oldest first: see
/// `StockView.salesGrowth`.
Fx? _salesGrowth(List<Results> results) {
  final n = results.length;
  Money sum(int from, int to) {
    var total = Money.zero;
    for (var i = from; i < to; i++) {
      total += results[i].revenue;
    }
    return total;
  }

  final (now, before) = n >= 8
      ? (sum(n - 4, n), sum(n - 8, n - 4))
      : n >= 5
      ? (results[n - 1].revenue, results[n - 5].revenue)
      : (Money.zero, Money.zero);
  if (before <= Money.zero) return null;
  return moneyRatio(now - before, before);
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
    case ListingKind.company:
      // The player's own: as its director runs it, or as the player does.
      final director = world.companies[listing.link].director;
      final grades = content.directors?.grades.length ?? 0;
      if (director == null || grades == 0) return averageManagement;
      return managementGrades.length - grades + director.grade.index;
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
