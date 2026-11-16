import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';

/// How a listed company keeps its books: by formula, or as one of the game's
/// own businesses.
enum ListingKind {
  /// A company of a sector the game doesn't play, run by formula.
  formula,

  /// A national chain of the countries by formula.
  chain,

  /// A rival in the software market.
  software,

  /// A rival producer of factory goods.
  producer,

  /// A company of the player's, listed during the game.
  company,
}

/// How well a company is run, from bad to excellent.
const managementGrades = ['bad', 'poor', 'average', 'good', 'excellent'];

/// The middle grade, which neither helps nor hurts.
const averageManagement = 2;

/// The most shares a company may have, so that what each holder is owed
/// stays safe to work out.
const maxListedShares = 4000000000;

/// A sector of the stock market, from the countries' national accounts.
final class SectorDef {
  const SectorDef({
    required this.key,
    required this.name,
    required this.growth,
    required this.risk,
    required this.payout,
    required this.floor,
    this.margin = Fx.zero,
    this.cycle = Fx.zero,
    this.leverage = Fx.zero,
    this.debt = Fx.zero,
    this.output,
    this.trade,
    this.software = false,
  });

  final String key;
  final String name;

  /// Margin on sales before tax in a normal year, for its companies by
  /// formula.
  final Fx margin;

  /// How far its sales move with the economy's output gap.
  final Fx cycle;

  /// How far its margin moves with its sales against normal.
  final Fx leverage;

  /// Yearly real growth beyond its country's.
  final Fx growth;

  /// How much of the market's risk it carries: 1 for the average.
  final Fx risk;

  /// The share of profit its companies pay out, unless one says otherwise.
  final Fx payout;

  /// Net debt, in years of profit, unless one says otherwise.
  final Fx debt;

  /// What a company of it is worth while losing money, in years of sales.
  final Fx floor;

  /// What it makes a year in each of the scenario's countries at the
  /// table's start, by [CountryId]; null for a sector the game plays.
  final List<Money>? output;

  /// The national trade its chains are of, if any.
  final String? trade;

  /// Whether its companies are the software market's rivals.
  final bool software;

  bool get byFormula => output != null;
}

/// How a raider picks what to buy.
enum RaiderStyle {
  /// Companies cheap against their usual, and well run.
  value,

  /// Companies whose profit grows fastest.
  growth,

  /// Companies cheap and badly run, which it builds a stake in and bids for.
  raider,
}

/// A raider: a named investor by formula.
final class RaiderDef {
  const RaiderDef({
    required this.name,
    required this.style,
    required this.funds,
  });

  final String name;
  final RaiderStyle style;

  /// Its money at the start.
  final Money funds;
}

/// A country's stock exchange.
final class ExchangeDef {
  const ExchangeDef({
    required this.country,
    required this.name,
    required this.index,
  });

  final CountryId country;
  final String name;

  /// What its index is called.
  final String index;
}

/// A listed company as the table sets it out at the start.
final class ListingDef {
  const ListingDef({
    required this.ticker,
    required this.name,
    required this.country,
    required this.sector,
    required this.kind,
    required this.link,
    required this.share,
    required this.cap,
    required this.shares,
    required this.margin,
    required this.debt,
    required this.growth,
    required this.payout,
    required this.management,
  });

  final String ticker;
  final String name;
  final CountryId country;

  /// By position in [StocksDef.sectors].
  final int sector;
  final ListingKind kind;

  /// The game's business it is: a chain by its position in its national
  /// country's chains, a software rival or a producer by its position at
  /// the start; -1 for one by formula.
  final int link;

  /// Its share of its sector's output in its country, in millionths.
  final int share;

  /// What it is worth on the exchange at the start; null to start at what
  /// its books say.
  final Money? cap;

  /// Its shares; null to set them from its worth at the start.
  final int? shares;

  /// For one by formula: its margin before tax in a normal year, net debt
  /// in years of profit, and yearly growth beyond its sector's.
  final Fx margin;
  final Fx debt;
  final Fx growth;

  /// The share of profit it pays out.
  final Fx payout;

  /// For one by formula: how well it is run at the start, by
  /// [managementGrades].
  final int management;
}

/// How the market prices companies and moves.
final class StockRulesDef {
  const StockRulesDef({
    required this.termPremium,
    required this.equityPremium,
    required this.inflation,
    required this.minEarningsMultiple,
    required this.maxEarningsMultiple,
    required this.moods,
    required this.euphoria,
    required this.maxEuphoria,
    required this.marketHalfLife,
    required this.marketSpread,
    required this.shared,
    required this.stockHalfLife,
    required this.stockSpread,
    required this.reaction,
    required this.maxSurprise,
    required this.maxMood,
    required this.analystSpread,
    required this.analystHalfLife,
    required this.analystsFollow,
    required this.ratings,
    required this.fee,
    required this.indexFee,
    required this.impact,
    required this.managementChange,
    required this.managementMargin,
    required this.managementGrowth,
    required this.managementPull,
    required this.marginSpread,
    required this.unprovenMonths,
    required this.chainReserveMonths,
    required this.producerUse,
    required this.indexBase,
    required this.offerDays,
    required this.acceptFrom,
    required this.acceptSpan,
    required this.acceptMost,
    required this.squeezeOut,
    required this.raiderStakes,
    required this.raiderBuy,
    required this.raiderMaxStake,
    required this.raiderBidStake,
    required this.raiderPremium,
    required this.raiderLeverage,
    required this.raiderSell,
  });

  /// Long rates over the central bank's.
  final Fx termPremium;

  /// What investors ask over long rates, for the average risk.
  final Fx equityPremium;

  /// The inflation investors expect in the long run.
  final Fx inflation;
  final Fx minEarningsMultiple;
  final Fx maxEarningsMultiple;

  /// Where the market's mood heads in each phase of the cycle, by
  /// [RegimeId]: a log of price over worth.
  final List<Fx> moods;

  /// How much higher it heads for each month an expansion has lasted, and at
  /// most.
  final Fx euphoria;
  final Fx maxEuphoria;

  /// Days for half of a mood to fade, and how far it wanders a day.
  final int marketHalfLife;
  final Fx marketSpread;

  /// How much of each exchange's mood is the whole market's.
  final Fx shared;
  final int stockHalfLife;
  final Fx stockSpread;

  /// How far a stock's mood moves for results that surprise by 100%, and
  /// the largest surprise counted.
  final Fx reaction;
  final Fx maxSurprise;

  /// The furthest any mood goes, either way.
  final Fx maxMood;

  /// How far analysts' own view of a company wanders a month, and the
  /// months for half of it to fade.
  final Fx analystSpread;
  final int analystHalfLife;

  /// How much of the moods analysts are swept along by.
  final Fx analystsFollow;

  /// The upsides that part strong sell, sell, hold, buy and strong buy.
  final List<Fx> ratings;

  /// A broker's fee on an order of shares, and on an index's.
  final Fx fee;
  final Fx indexFee;

  /// How far an order for a whole company would move its price, as a log:
  /// one for 1% of it moves it about [impact] %.
  final Fx impact;

  /// The chance a year that a company by formula changes its management;
  /// what each grade above average adds to its margin and its yearly
  /// growth; and how much of the way its margin moves there a month.
  final Fx managementChange;
  final Fx managementMargin;
  final Fx managementGrowth;
  final Fx managementPull;

  /// How far a company by formula's margin wanders a month, as a share of
  /// it: its own luck, good and bad, which its management pulls back.
  final Fx marginSpread;

  /// Months a new management shows as unproven.
  final int unprovenMonths;

  /// Months of a chain's costs it keeps in cash before paying out.
  final int chainReserveMonths;

  /// How much of a producer's capacity it sells beyond its contracts.
  final Fx producerUse;

  /// What each index stands at the start.
  final Fx indexBase;

  /// How long a bid stays open.
  final int offerDays;

  /// The free float accepts a bid as its premium over the higher of the
  /// price and analysts' view of its worth rises from [acceptFrom], all of
  /// it over [acceptSpan] more, at most [acceptMost] of it.
  final Fx acceptFrom;
  final Fx acceptSpan;
  final Fx acceptMost;

  /// The share past which a winning bid buys out the rest and takes the
  /// company off its exchange.
  final Fx squeezeOut;

  /// How many stakes a raider holds at most; the most of a company it buys
  /// a month and holds; the stake past which a raider bids, and at what
  /// premium; how far it borrows beyond its money to bid; and the gain over
  /// worth at which it sells.
  final int raiderStakes;
  final Fx raiderBuy;
  final Fx raiderMaxStake;
  final Fx raiderBidStake;
  final Fx raiderPremium;
  final Fx raiderLeverage;
  final Fx raiderSell;
}

/// The stock market: its rules, exchanges, sectors and listed companies,
/// from a table of its own beside the scenario.
final class StocksDef {
  StocksDef({
    required this.source,
    required this.rules,
    required this.exchanges,
    required this.sectors,
    required this.listings,
    this.raiders = const [],
  });

  /// The table as read, to load it again beside a changed scenario.
  final String source;
  final StockRulesDef rules;

  /// By [CountryId], one per country listed.
  final List<ExchangeDef> exchanges;
  final List<SectorDef> sectors;
  final List<ListingDef> listings;

  /// By position: what the market keeps of each is in `StockMarket.raiders`.
  final List<RaiderDef> raiders;

  /// Each listed company's exchange, by its position.
  late final List<int> listingExchange = List.unmodifiable([
    for (final listing in listings) exchangeOf(listing.country)!,
  ]);

  /// [country]'s exchange, or null if it has none.
  int? exchangeOf(CountryId country) {
    for (final (i, exchange) in exchanges.indexed) {
      if (exchange.country == country) return i;
    }
    return null;
  }
}
