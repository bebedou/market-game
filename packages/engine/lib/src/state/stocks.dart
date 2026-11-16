import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// The save version from which the world keeps a stock market.
const stocksVersion = 38;

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

/// Quarters of results kept, and months of closing prices.
const resultsKept = 8;
const closesKept = 60;

/// One quarter's results, as published.
final class Results {
  const Results({
    required this.day,
    required this.revenue,
    required this.profit,
    required this.dividends,
  });

  Results.read(StateReader reader)
    : day = Day(reader.readInt()),
      revenue = Money(reader.readInt()),
      profit = Money(reader.readInt()),
      dividends = Money(reader.readInt());

  /// When they were published.
  final Day day;
  final Money revenue;

  /// After interest and tax.
  final Money profit;

  /// Paid out to all its shareholders.
  final Money dividends;

  void write(StateWriter writer) {
    writer
      ..writeInt(day.number)
      ..writeInt(revenue.cents)
      ..writeInt(profit.cents)
      ..writeInt(dividends.cents);
  }
}

/// A listed company on its exchange: its price and what moves it, and, for
/// one run by formula, its books.
final class Listing {
  Listing({
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

  Listing.read(StateReader reader)
    : since = Day(reader.readInt()),
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
      ];

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
  }
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

/// Shares a person holds, of a listed company or of an exchange's index,
/// and what they paid for them.
final class Holding {
  Holding({required this.index, required this.of, this.units = 0})
    : cost = Money.zero;

  Holding.read(StateReader reader)
    : index = reader.readBool(),
      of = reader.readInt(),
      units = reader.readInt(),
      cost = Money(reader.readInt()),
      declared = reader.readInt();

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
      ..writeInt(declared);
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
  }) : holdings = [];

  StockMarket.read(StateReader reader)
    : mood = reader.readInt(),
      longRate = Fx.raw(reader.readInt()),
      exchanges = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Exchange.read(reader),
      ],
      stocks = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Listing.read(reader),
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
      dividends = Money(reader.readInt());

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

  /// The player's.
  final List<Holding> holdings;

  /// Public stakes sold whole today, still to be made public as gone; not
  /// saved, as the day's run empties it.
  final released = <Holding>[];

  /// Losses on shares sold, not yet set against a gain.
  Money gainsLoss = Money.zero;

  /// The dividends the player received in [dividendsYear], before tax.
  int dividendsYear = 0;
  Money dividends = Money.zero;

  /// The player's holding of a company, or of an exchange's index if
  /// [index]; null if none.
  Holding? holding(int of, {bool index = false}) {
    for (final holding in holdings) {
      if (holding.index == index && holding.of == of) return holding;
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
      ..writeInt(dividends.cents);
  }
}
