import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';
import 'store.dart' show fixedAssetsVersion;

/// The save version from which the world keeps a stock market.
const stocksVersion = 38;

/// The save version from which shares have owners other than the player,
/// and the market keeps bids, raiders, share loans and companies under
/// control.
const controlVersion = 39;

/// Who holds shares, bids or controls a company: the player's holding (the
/// player in person), one of the player's companies by its index, or a
/// raider.
const holdingOwner = -1;

/// The owner that stands for raider [raider].
int raiderOwner(int raider) => -2 - raider;

/// Whether [owner] is a raider, and which.
bool isRaider(int owner) => owner <= -2 && owner > _chains;
int raiderOf(int owner) => -2 - owner;

const _chains = -100000;

/// The bidder that stands for chain [chain] of the national table's country
/// [country], which bids only for the player's listed companies.
int chainBidder(int country, int chain) => _chains - country * 1000 - chain;

/// Whether [owner] is a chain, and which.
bool isChain(int owner) => owner <= _chains;
({int country, int chain}) chainOfBidder(int owner) =>
    (country: (_chains - owner) ~/ 1000, chain: (_chains - owner) % 1000);

/// Whether [owner] is the player or one of the player's companies.
bool isPlayers(int owner) => owner >= holdingOwner;

/// [a] over [b], kept safe for amounts in the trillions: both are taken
/// in coarser units until the division is.
Fx moneyRatio(Money a, Money b) {
  var top = a.cents;
  var bottom = b.cents;
  while (bottom.abs() > 400000000000) {
    top ~/= 10;
    bottom ~/= 10;
  }
  if (bottom == 0) return Fx.zero;
  return Fx.raw(mulDivRound(top, Fx.scale, bottom));
}

/// A stake in a listed company is made public each time it crosses a
/// multiple of this, in percent, either way.
const stakeStep = 5;

/// Quarters of results kept, five years, and months of closing prices.
const resultsKept = 20;
const closesKept = 60;

/// One quarter's results, as published.
final class Results {
  const Results({
    required this.day,
    required this.revenue,
    required this.profit,
    required this.dividends,
    this.equity,
  });

  Results.read(StateReader reader)
    : day = Day(reader.readInt()),
      revenue = Money(reader.readInt()),
      profit = Money(reader.readInt()),
      dividends = Money(reader.readInt()),
      equity = reader.version >= fixedAssetsVersion && reader.readBool()
          ? Money(reader.readInt())
          : null;

  /// When they were published.
  final Day day;
  final Money revenue;

  /// After interest and tax.
  final Money profit;

  /// Paid out to all its shareholders.
  final Money dividends;

  /// Its book value at the quarter's end, what it held less its net debt;
  /// null for quarters published before saves kept it.
  final Money? equity;

  void write(StateWriter writer) {
    writer
      ..writeInt(day.number)
      ..writeInt(revenue.cents)
      ..writeInt(profit.cents)
      ..writeInt(dividends.cents)
      ..writeBool(equity != null);
    if (equity case final equity?) writer.writeInt(equity.cents);
  }
}

/// A listed company on its exchange: its price and what moves it, and, for
/// one run by formula, its books.
final class Listing {
  Listing({
    required this.table,
    required this.since,
    required this.shares,
    required this.price,
    required this.worth,
    required this.mood,
    required this.management,
    required this.managementSince,
    required this.share,
    required this.margin,
    required this.debt,
  }) : previous = price,
       closes = [price],
       multiples = [],
       results = [];

  Listing.read(StateReader reader, {required int position})
    : table = reader.version >= controlVersion ? reader.readInt() : position,
      since = Day(reader.readInt()),
      listed = reader.readBool(),
      shares = reader.readInt(),
      price = Money(reader.readInt()),
      previous = Money(reader.readInt()),
      worth = Money(reader.readInt()),
      mood = reader.readInt(),
      bias = reader.readInt(),
      management = reader.readInt(),
      managementSince = Day(reader.readInt()),
      share = reader.readInt(),
      margin = Fx.raw(reader.readInt()),
      debt = Money(reader.readInt()),
      cycle = Fx.raw(reader.readInt()),
      quarterRevenue = Money(reader.readInt()),
      quarterProfit = Money(reader.readInt()),
      quarterMonths = reader.readInt(),
      results = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Results.read(reader),
      ],
      closes = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Money(reader.readInt()),
      ],
      multiples = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ] {
    if (reader.version < controlVersion) return;
    if (reader.readBool()) own = OwnListing.read(reader);
    controller = reader.readNullableInt();
    if (reader.readBool()) payoutLever = Fx.raw(reader.readInt());
    growthLever = reader.readInt();
    if (reader.readBool()) debtLever = Fx.raw(reader.readInt());
    director = reader.readNullableInt();
    if (reader.version < fixedAssetsVersion) return;
    assets = Money(reader.readInt());
    volume = Money(reader.readInt());
  }

  /// Its position in the table, or -1 for a company of the player's listed
  /// during the game ([own]).
  final int table;

  /// For a company of the player's listed during the game: what the table
  /// would say of it.
  OwnListing? own;

  /// Who controls it, if anyone has taken it over: see [holdingOwner].
  int? controller;

  /// What its controller has set, for a company by formula: the share of
  /// profit paid out, how fast it invests to grow (-1 slow, 0 steady, 1
  /// fast), the debt it aims for in years of profit, and the grade of the
  /// director running it.
  Fx? payoutLever;
  int growthLever = 0;
  Fx? debtLever;
  int? director;

  /// Whether it still trades, listed or held whole by whoever took it over.
  bool get running => listed || controller != null;

  /// When it was listed.
  final Day since;

  /// False once it has left the exchange: bought whole, or failed.
  bool listed = true;
  int shares;

  /// A share's price today and at yesterday's close.
  Money price;
  Money previous;

  /// What the whole company is worth by its books, as last valued.
  Money worth;

  /// How far its price stands from its worth beyond the market's mood, as a
  /// log in millionths: its results' surprises, fading.
  int mood;

  /// How far analysts' own view of its worth is off, as a log in millionths.
  int bias = 0;

  /// How well it is run, by `managementGrades`, and since when.
  int management;
  Day managementSince;

  /// For one by formula: its share of its sector's output in its country, in
  /// millionths; its net margin in a normal year; its net debt (negative
  /// for net cash); and how far its sales stand from normal with the cycle.
  int share;
  Fx margin;
  Money debt;
  Fx cycle = Fx.one;

  /// For one by formula: what it holds to trade, at the table's prices
  /// (its book value at today's is this times its country's price level),
  /// and what it sells a year at those prices, what its last investment
  /// was sized on. Each euro of sales it adds costs its sector's capital
  /// to build (see `SectorDef.capital`).
  Money assets = Money.zero;
  Money volume = Money.zero;

  /// What it has sold and earned so far this quarter, in how many months.
  Money quarterRevenue = Money.zero;
  Money quarterProfit = Money.zero;
  int quarterMonths = 0;

  /// Its latest quarters' results, oldest first, up to [resultsKept].
  final List<Results> results;

  /// Its price on the first of each month, oldest first, up to [closesKept],
  /// and its price over its year's profit then (zero while losing money).
  final List<Money> closes;
  final List<Fx> multiples;

  /// What it is worth on the exchange.
  Money get cap => price.timesInt(shares);

  /// Its price over its last four quarters' profit; zero while it loses
  /// money.
  Fx get multiple {
    final profit = yearProfit;
    if (profit <= Money.zero) return Fx.zero;
    return moneyRatio(cap, profit);
  }

  /// Its last four quarters' profit, and revenue.
  Money get yearProfit => _lastYear((r) => r.profit);
  Money get yearRevenue => _lastYear((r) => r.revenue);
  Money get yearDividends => _lastYear((r) => r.dividends);

  Money _lastYear(Money Function(Results) of) {
    var sum = Money.zero;
    final from = results.length > 4 ? results.length - 4 : 0;
    for (var i = from; i < results.length; i++) {
      sum += of(results[i]);
    }
    return sum;
  }

  void keep(Results quarter) {
    results.add(quarter);
    if (results.length > resultsKept) results.removeAt(0);
  }

  void close(Fx multiple) {
    closes.add(price);
    multiples.add(multiple);
    if (closes.length > closesKept) closes.removeAt(0);
    if (multiples.length > closesKept) multiples.removeAt(0);
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(table)
      ..writeInt(since.number)
      ..writeBool(listed)
      ..writeInt(shares)
      ..writeInt(price.cents)
      ..writeInt(previous.cents)
      ..writeInt(worth.cents)
      ..writeInt(mood)
      ..writeInt(bias)
      ..writeInt(management)
      ..writeInt(managementSince.number)
      ..writeInt(share)
      ..writeInt(margin.raw)
      ..writeInt(debt.cents)
      ..writeInt(cycle.raw)
      ..writeInt(quarterRevenue.cents)
      ..writeInt(quarterProfit.cents)
      ..writeInt(quarterMonths)
      ..writeInt(results.length);
    for (final quarter in results) {
      quarter.write(writer);
    }
    writer.writeInt(closes.length);
    for (final close in closes) {
      writer.writeInt(close.cents);
    }
    writer.writeInt(multiples.length);
    for (final multiple in multiples) {
      writer.writeInt(multiple.raw);
    }
    writer.writeBool(own != null);
    own?.write(writer);
    writer
      ..writeNullableInt(controller)
      ..writeBool(payoutLever != null);
    if (payoutLever case final payout?) writer.writeInt(payout.raw);
    writer
      ..writeInt(growthLever)
      ..writeBool(debtLever != null);
    if (debtLever case final debt?) writer.writeInt(debt.raw);
    writer
      ..writeNullableInt(director)
      ..writeInt(assets.cents)
      ..writeInt(volume.cents);
  }
}

/// A company of the player's listed during the game: what the table says
/// of the companies it starts with.
final class OwnListing {
  OwnListing({
    required this.company,
    required this.ticker,
    required this.name,
    required this.country,
    required this.sector,
  });

  OwnListing.read(StateReader reader)
    : company = reader.readInt(),
      ticker = reader.readString(),
      name = reader.readString(),
      country = reader.readInt(),
      sector = reader.readInt(),
      revenueMark = Money(reader.readInt());

  /// The game's company, by its index.
  final int company;
  final String ticker;
  final String name;

  /// By [CountryId] index and position in the table's sectors.
  final int country;
  final int sector;

  /// Its company's sales account when its last month was booked.
  Money revenueMark = Money.zero;

  void write(StateWriter writer) {
    writer
      ..writeInt(company)
      ..writeString(ticker)
      ..writeString(name)
      ..writeInt(country)
      ..writeInt(sector)
      ..writeInt(revenueMark.cents);
  }
}

/// Append only.
enum BidStatus { open, won, lost, lapsed }

/// An offer for every share of a listed company, open for a month: won if
/// shareholders holding more than half accept, and the bidder can pay.
final class Bid {
  Bid({
    required this.number,
    required this.stock,
    required this.bidder,
    required this.price,
    required this.opened,
    required this.closes,
    required this.reference,
    this.via = -1,
    this.borrow = Money.zero,
    this.termMonths = 0,
    this.format = -1,
    this.strategy = -1,
  });

  Bid.read(StateReader reader)
    : number = reader.readInt(),
      stock = reader.readInt(),
      bidder = reader.readInt(),
      via = reader.readInt(),
      price = Money(reader.readInt()),
      opened = Day(reader.readInt()),
      closes = Day(reader.readInt()),
      reference = Money(reader.readInt()),
      borrow = Money(reader.readInt()),
      termMonths = reader.readInt(),
      format = switch (reader.readInt()) {
        < 0 => -1,
        final format => reader.mapFormat(format),
      },
      strategy = reader.readInt(),
      status = BidStatus.values[reader.readInt()],
      tender = reader.readBool(),
      accepted = reader.readInt();

  final int number;

  /// The company bid for, by its position on the market.
  final int stock;

  /// Who bids: see [holdingOwner].
  final int bidder;

  /// A company the bidder controls that bids to merge [stock] into it, by
  /// its position on the market; -1 if none.
  final int via;

  /// What it offers a share.
  Money price;
  final Day opened;
  Day closes;

  /// What a share was worth to its holders when it opened: the higher of
  /// its price and what analysts thought it worth. Its premium is over this.
  final Money reference;

  /// What the bidder borrows for it, and over how long.
  final Money borrow;
  final int termMonths;

  /// For a chain: the format and strategy its shops take in the bidder's
  /// company.
  final int format;
  final int strategy;
  BidStatus status = BidStatus.open;

  /// Whether the player offers their own shares into someone else's bid.
  bool tender = false;

  /// The shares that accepted, once it closed.
  int accepted = 0;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(stock)
      ..writeInt(bidder)
      ..writeInt(via)
      ..writeInt(price.cents)
      ..writeInt(opened.number)
      ..writeInt(closes.number)
      ..writeInt(reference.cents)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths)
      ..writeInt(format)
      ..writeInt(strategy)
      ..writeInt(status.index)
      ..writeBool(tender)
      ..writeInt(accepted);
  }
}

/// What the player's holding borrowed to take a company over, against the
/// shares it bought, repaid monthly; if an instalment can't be paid, the
/// bank sells the shares.
final class ShareLoan {
  ShareLoan({
    required this.number,
    required this.stock,
    required this.outstanding,
    required this.rate,
    required this.installmentsLeft,
  });

  ShareLoan.read(StateReader reader)
    : number = reader.readInt(),
      stock = reader.readInt(),
      outstanding = Money(reader.readInt()),
      rate = Fx.raw(reader.readInt()),
      installmentsLeft = reader.readInt();

  final int number;

  /// The company whose shares secure it.
  final int stock;
  Money outstanding;

  /// Yearly interest.
  final Fx rate;
  int installmentsLeft;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(stock)
      ..writeInt(outstanding.cents)
      ..writeInt(rate.raw)
      ..writeInt(installmentsLeft);
  }
}

/// A raider: a named investor by formula whose money grows with its returns.
final class Raider {
  Raider({required this.cash});

  Raider.read(StateReader reader) : cash = Money(reader.readInt());

  /// Its money not in shares.
  Money cash;

  void write(StateWriter writer) => writer.writeInt(cash.cents);
}

/// A country's exchange: its mood and its index.
final class Exchange {
  Exchange({required this.divisor, required this.level})
    : previous = level,
      closes = [level];

  Exchange.read(StateReader reader)
    : mood = reader.readInt(),
      divisor = Money(reader.readInt()),
      level = Money(reader.readInt()),
      previous = Money(reader.readInt()),
      closes = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Money(reader.readInt()),
      ];

  /// The exchange's own mood, as a log in millionths.
  int mood = 0;

  /// What its listed companies are worth for each point of its index.
  Money divisor;

  /// Its index today and at yesterday's close, as the price of one unit.
  Money level;
  Money previous;

  /// Its index on the first of each month, oldest first.
  final List<Money> closes;

  void close() {
    closes.add(level);
    if (closes.length > closesKept) closes.removeAt(0);
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(mood)
      ..writeInt(divisor.cents)
      ..writeInt(level.cents)
      ..writeInt(previous.cents)
      ..writeInt(closes.length);
    for (final close in closes) {
      writer.writeInt(close.cents);
    }
  }
}

/// Shares held, of a listed company or of an exchange's index, and what
/// they cost.
final class Holding {
  Holding({
    required this.index,
    required this.of,
    this.units = 0,
    this.owner = holdingOwner,
  }) : cost = Money.zero;

  Holding.read(StateReader reader)
    : index = reader.readBool(),
      of = reader.readInt(),
      units = reader.readInt(),
      cost = Money(reader.readInt()),
      declared = reader.readInt(),
      owner = reader.version >= controlVersion
          ? reader.readInt()
          : holdingOwner;

  /// Who holds it: see [holdingOwner]; a merged company's go to the one it
  /// merged into.
  int owner;

  /// Whether it is of an exchange's index rather than a company.
  final bool index;

  /// The company's or the exchange's position in the table.
  final int of;
  int units;
  Money cost;

  /// The stake last made public, in steps of [stakeStep].
  int declared = 0;

  void write(StateWriter writer) {
    writer
      ..writeBool(index)
      ..writeInt(of)
      ..writeInt(units)
      ..writeInt(cost.cents)
      ..writeInt(declared)
      ..writeInt(owner);
  }
}

/// The stock market: every exchange and listed company by position in the
/// table, each sector's trend in each country, and the player's holdings.
final class StockMarket {
  StockMarket({
    required this.exchanges,
    required this.stocks,
    required this.trends,
    required this.longRate,
  }) : holdings = [],
       bids = [],
       raiders = [],
       loans = [];

  StockMarket.read(StateReader reader)
    : mood = reader.readInt(),
      longRate = Fx.raw(reader.readInt()),
      exchanges = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Exchange.read(reader),
      ],
      stocks = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Listing.read(reader, position: i),
      ],
      trends = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ],
      holdings = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Holding.read(reader),
      ],
      gainsLoss = Money(reader.readInt()),
      dividendsYear = reader.readInt(),
      dividends = Money(reader.readInt()),
      bids = [
        if (reader.version >= controlVersion)
          for (var i = 0, n = reader.readInt(); i < n; i++) Bid.read(reader),
      ],
      raiders = [
        if (reader.version >= controlVersion)
          for (var i = 0, n = reader.readInt(); i < n; i++) Raider.read(reader),
      ],
      loans = [
        if (reader.version >= controlVersion)
          for (var i = 0, n = reader.readInt(); i < n; i++)
            ShareLoan.read(reader),
      ] {
    if (reader.version >= controlVersion) {
      nextBid = reader.readInt();
      nextLoan = reader.readInt();
    }
  }

  /// The whole market's mood, which every exchange shares in part.
  int mood = 0;

  /// The rate investors expect over the years: the central bank's, slowly
  /// followed.
  Fx longRate;
  final List<Exchange> exchanges;
  final List<Listing> stocks;

  /// Each sector's real growth since the start in each country, by country
  /// then sector, as a multiplier.
  final List<Fx> trends;

  /// Everyone's: the player's, their companies' and raiders'.
  final List<Holding> holdings;

  /// Bids open, and lately closed.
  final List<Bid> bids;

  /// By position in the table's raiders.
  final List<Raider> raiders;

  /// The player's holding's loans for takeovers.
  final List<ShareLoan> loans;
  int nextBid = 1;
  int nextLoan = 1;

  /// Public stakes sold whole today, still to be made public as gone; not
  /// saved, as the day's run empties it.
  final released = <Holding>[];

  /// Losses on shares sold, not yet set against a gain.
  Money gainsLoss = Money.zero;

  /// The dividends the player received in [dividendsYear], before tax.
  int dividendsYear = 0;
  Money dividends = Money.zero;

  /// [owner]'s holding of a company, or of an exchange's index if [index];
  /// null if none.
  Holding? holding(int of, {bool index = false, int owner = holdingOwner}) {
    for (final holding in holdings) {
      if (holding.index == index &&
          holding.of == of &&
          holding.owner == owner) {
        return holding;
      }
    }
    return null;
  }

  /// The shares of company [of] that [owner] holds.
  int unitsOf(int of, int owner) => holding(of, owner: owner)?.units ?? 0;

  /// The shares of company [of] the player and their companies hold.
  int playersUnits(int of) {
    var units = 0;
    for (final holding in holdings) {
      if (!holding.index && holding.of == of && isPlayers(holding.owner)) {
        units += holding.units;
      }
    }
    return units;
  }

  /// The open bid for company [of], if any.
  Bid? openBid(int of) {
    for (final bid in bids) {
      if (bid.stock == of && bid.status == BidStatus.open) return bid;
    }
    return null;
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(mood)
      ..writeInt(longRate.raw)
      ..writeInt(exchanges.length);
    for (final exchange in exchanges) {
      exchange.write(writer);
    }
    writer.writeInt(stocks.length);
    for (final stock in stocks) {
      stock.write(writer);
    }
    writer.writeInt(trends.length);
    for (final trend in trends) {
      writer.writeInt(trend.raw);
    }
    writer.writeInt(holdings.length);
    for (final holding in holdings) {
      holding.write(writer);
    }
    writer
      ..writeInt(gainsLoss.cents)
      ..writeInt(dividendsYear)
      ..writeInt(dividends.cents)
      ..writeInt(bids.length);
    for (final bid in bids) {
      bid.write(writer);
    }
    writer.writeInt(raiders.length);
    for (final raider in raiders) {
      raider.write(writer);
    }
    writer.writeInt(loans.length);
    for (final loan in loans) {
      loan.write(writer);
    }
    writer
      ..writeInt(nextBid)
      ..writeInt(nextLoan);
  }
}

/// What [owner]'s holdings in [market] are worth at today's prices: the
/// player's own with [holdingOwner], a company's by its index.
Money sharesWorth(StockMarket? market, int owner) {
  if (market == null) return Money.zero;
  var worth = Money.zero;
  for (final holding in market.holdings) {
    if (holding.owner != owner) continue;
    final price = holding.index
        ? market.exchanges[holding.of].level
        : market.stocks[holding.of].price;
    worth += price.timesInt(holding.units);
  }
  return worth;
}
