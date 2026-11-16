import '../core/fx.dart';
import '../core/money.dart';
import 'content_db.dart' show TalentDef, TalentLevelDef;

/// The one world market for software, and how its products compete for it:
/// see `SoftwareSystem`. A software company sells one product to customers
/// who pay a month each. Its people build the product: the market's
/// standard rises every month, and a product ahead of it draws far more of
/// the customers who change products, and loses fewer.
final class SoftwareDef implements TalentDef {
  const SoftwareDef({
    required this.customers,
    required this.price,
    required this.growth,
    required this.cycle,
    required this.standard,
    required this.rise,
    required this.startGap,
    required this.launchGap,
    required this.progress,
    required this.designerBuild,
    required this.decay,
    required this.hardness,
    required this.appeal,
    required this.draw,
    required this.drawFloor,
    required this.drawCap,
    required this.priceElasticity,
    required this.churn,
    required this.churnSteepness,
    required this.minChurn,
    required this.maxChurn,
    required this.wordOfMouth,
    required this.marketingScale,
    required this.serving,
    required this.office,
    required this.maxPeople,
    required this.candidates,
    required this.candidateDays,
    required this.revealMonths,
    required this.levels,
    required this.firstNames,
    required this.lastNames,
    required this.baseMultiple,
    required this.growthMultiple,
    required this.minMultiple,
    required this.maxMultiple,
    required this.valuationCycle,
    required this.teamMonths,
    required this.teamPaceCap,
    required this.maxRoundShare,
    required this.roundMonths,
    required this.offerChance,
    required this.offerRevenue,
    required this.minPremium,
    required this.maxPremium,
    required this.offerDays,
    required this.foundingChance,
    required this.startupTeam,
    required this.startupMarketing,
    required this.startupPrice,
    required this.foldMonths,
    required this.foldCustomers,
    required this.startupNames,
    required this.paceSpread,
    required this.response,
    required this.rivals,
  });

  /// Customers in the world at the start: everyone who pays for software.
  final int customers;

  /// What a customer pays a month on average at the start, at a price index
  /// of one.
  final Money price;

  /// The market's yearly growth in customers in a normal year, and how far
  /// the economy's demand moves it: one point of demand under normal takes
  /// [cycle] points off a year's growth.
  final Fx growth;
  final Fx cycle;

  /// Where the market's standard stands at the start, and how far it rises
  /// each month: 0.01 is a point. Products are levels against it.
  final Fx standard;
  final Fx rise;

  /// How far under the standard a new product starts, and how close to it
  /// its first version must be to sell.
  final Fx startGap;
  final Fx launchGap;

  /// The level a month's work of one unit of an engineer's power adds, the
  /// share of their power designers build with, the share each next person
  /// counts for, the best first, and how much harder progress gets the
  /// further ahead: one plus this times the lead.
  final Fx progress;
  final Fx designerBuild;
  final Fx decay;
  final Fx hardness;

  /// The appeal one unit of a designer's power adds to a product: points
  /// shoppers count as if it were that much further ahead.
  final Fx appeal;

  /// How steeply customers who change products go to the better ones: a
  /// product's pull is e to the power of this times its lead and appeal,
  /// kept between [drawFloor] and [drawCap].
  final Fx draw;
  final Fx drawFloor;
  final Fx drawCap;

  /// How a price over the market's draws fewer: the ratio of the market's
  /// price to a product's, to this power.
  final int priceElasticity;

  /// The share of its customers a product loses a month at the standard
  /// and the market's price, how fast that falls with lead and appeal, and
  /// the least and most it ever is.
  final Fx churn;
  final Fx churnSteepness;
  final Fx minChurn;
  final Fx maxChurn;

  /// What one customer's word is worth a month, as marketing.
  final Money wordOfMouth;

  /// The spend at which marketing reaches as many as it costs: reach grows
  /// as the square root of spend times this.
  final Money marketingScale;

  /// The share of its revenue serving its customers costs a product.
  final Fx serving;

  /// An office for one person a month, at a price index of one.
  final Money office;

  /// The most people a company's team holds.
  final int maxPeople;

  /// How many people the market for software people offers at a time, how
  /// many days one stays, and the months of work after which a person's
  /// true level shows.
  final int candidates;
  @override
  final int candidateDays;
  final int revealMonths;

  /// Software people's levels, the most ordinary first: their powers count
  /// for what they build, their salaries are software pay.
  @override
  final List<TalentLevelDef> levels;
  @override
  final List<String> firstNames;
  @override
  final List<String> lastNames;

  /// What a company is worth: a year's revenue times [baseMultiple] plus
  /// [growthMultiple] times its yearly growth, kept between [minMultiple]
  /// and [maxMultiple], and moved by the economy: one point of demand under
  /// normal takes [valuationCycle] points off the multiple's share. Before
  /// it sells much, it is worth [teamMonths] of its team's pay times how
  /// much faster than the standard its team builds, as a share of the
  /// standard's rise, at most [teamPaceCap]: nothing for a team that can't
  /// outpace it.
  final Fx baseMultiple;
  final Fx growthMultiple;
  final Fx minMultiple;
  final Fx maxMultiple;
  final Fx valuationCycle;
  final int teamMonths;
  final Fx teamPaceCap;

  /// The most of a company one funding round sells, and the months between
  /// rounds.
  final Fx maxRoundShare;
  final int roundMonths;

  /// The chance each month that a rival offers to buy a company selling at
  /// least [offerRevenue] a month, at what it is worth times a premium
  /// between [minPremium] and [maxPremium]; the offer stands [offerDays].
  final Fx offerChance;
  final Money offerRevenue;
  final Fx minPremium;
  final Fx maxPremium;
  final int offerDays;

  /// The chance each month that a new rival starts up, the people its team
  /// is drawn from, what it spends on marketing a month and its price
  /// against the market's; it folds if it hasn't [foldCustomers] customers
  /// after [foldMonths].
  final Fx foundingChance;
  final int startupTeam;
  final Money startupMarketing;
  final Fx startupPrice;
  final int foldMonths;
  final int foldCustomers;
  final List<String> startupNames;

  /// How far a rival's pace wanders each month, as a share of its own, and
  /// how much it raises the lead it aims for in a month it lost customers.
  final Fx paceSpread;
  final Fx response;

  /// The rivals at the start, the rest of the market last.
  final List<SoftwareRivalDef> rivals;
}

/// A rival at the start: its share of the market's customers, how far it is
/// over the standard, its price against the market's, and the share of its
/// revenue it spends on marketing. [rest] is everyone else, as one.
final class SoftwareRivalDef {
  const SoftwareRivalDef({
    required this.name,
    required this.share,
    required this.lead,
    required this.price,
    required this.marketing,
    this.rest = false,
  });

  final String name;
  final Fx share;
  final Fx lead;
  final Fx price;
  final Fx marketing;
  final bool rest;
}
