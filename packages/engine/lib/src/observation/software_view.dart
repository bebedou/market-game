import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/factory.dart' show monthOf;
import '../state/software.dart';
import '../state/software_rules.dart';
import '../state/talent.dart';
import '../state/world_state.dart';
import 'observation.dart' show KeyPersonView;

/// A rival in the software market, as anyone sees it.
typedef RivalView = ({
  SoftwareRivalId id,
  String name,
  RivalStatus status,
  int customers,

  /// Its share of every customer in the market.
  Fx share,

  /// How far it stands over the standard.
  Fx lead,

  /// What its customers pay a month.
  Money price,
  Day founded,
  Day? launchedOn,

  /// Whether it started up during the game.
  bool startup,

  /// Whether it stands for everyone else in the market.
  bool rest,
});

/// The software market as anyone sees it.
final class SoftwareMarketView {
  const SoftwareMarketView({
    required this.standard,
    required this.rise,
    required this.customers,
    required this.referencePrice,
    required this.rivals,
  });

  /// Where the standard stands, and how far it rises a month.
  final Fx standard;
  final Fx rise;

  /// Everyone who pays for software.
  final int customers;

  /// What a customer pays a month on average.
  final Money referencePrice;

  /// Every rival there ever was, by [SoftwareRivalId].
  final List<RivalView> rivals;

  RivalView rival(SoftwareRivalId id) => rivals[id.index];
}

/// A rival's standing offer for a software company.
typedef SoftwareOfferView = ({
  SoftwareRivalId rival,
  String rivalName,
  Money price,

  /// What its owner would get: their share of the price.
  Money yours,
  Day expires,
});

/// A software company's product as its owner sees it.
final class SoftwareView {
  const SoftwareView({
    required this.id,
    required this.company,
    required this.name,
    required this.country,
    required this.status,
    required this.founded,
    required this.launchedOn,
    required this.lead,
    required this.appeal,
    required this.pace,
    required this.rise,
    required this.toLaunch,
    required this.monthsToLaunch,
    required this.customers,
    required this.price,
    required this.marketing,
    required this.referencePrice,
    required this.churn,
    required this.growth,
    required this.history,
    required this.team,
    required this.maxPeople,
    required this.wageLevel,
    required this.payroll,
    required this.office,
    required this.serving,
    required this.revenue,
    required this.monthProfit,
    required this.breakEven,
    required this.worth,
    required this.stake,
    required this.investors,
    required this.rounds,
    required this.nextRound,
    required this.maxRoundShare,
    required this.offer,
  });

  final SoftwareId id;
  final CompanyId company;
  final String name;
  final CountryId country;
  final SoftwareStatus status;
  final Day founded;
  final Day? launchedOn;

  /// How far it stands over the market's standard, and what its designers
  /// add, as its owner takes them to be.
  final Fx lead;
  final Fx appeal;

  /// What its team builds a month at its lead, as its owner takes them to
  /// be, against the standard's rise.
  final Fx pace;
  final Fx rise;

  /// While building: how far its level still is from what sells, and the
  /// months that takes at this pace, or null if the team builds no faster
  /// than the market moves.
  final Fx toLaunch;
  final int? monthsToLaunch;

  final int customers;
  final Money price;
  final Money marketing;
  final Money referencePrice;

  /// The share of its customers it loses a month, as it stands.
  final Fx churn;

  /// Its yearly growth in customers.
  final Fx growth;

  /// Its months, oldest first.
  final List<SoftwareMonth> history;

  /// Its people, in the order hired.
  final List<KeyPersonView> team;
  final int maxPeople;

  /// Wages where it works against the first country's at the start: what a
  /// candidate's asking pay is multiplied by here.
  final Fx wageLevel;

  /// What its team and their offices cost a month, and the share of its
  /// revenue serving its customers costs.
  final Money payroll;
  final Money office;
  final Fx serving;

  /// What its customers pay a month, and what a month leaves it after its
  /// costs, as things stand.
  final Money revenue;
  final Money monthProfit;

  /// The customers at which a month pays its costs at this price, team and
  /// marketing.
  final int breakEven;

  /// What its company is worth, and what that rests on.
  final SoftwareWorth worth;

  /// The share of its company its owner holds, and investors.
  final Fx stake;
  final Fx investors;
  final List<FundingRound> rounds;

  /// The first day a round may be raised: today, or months after the last.
  final Day nextRound;
  final Fx maxRoundShare;

  /// A rival's standing offer, if any.
  final SoftwareOfferView? offer;

  /// The owner's share of what the company is worth, on paper.
  Money get yourWorth => worth.worth.times(stake);

  bool get running =>
      status == SoftwareStatus.building || status == SoftwareStatus.selling;
}

/// The software market as anyone sees it, or null if there is none.
SoftwareMarketView? softwareMarketViewOf(WorldState world, ContentDb content) {
  final def = content.software;
  final market = world.softwareMarket;
  if (def == null || market == null) return null;
  final reference = softwareReferencePrice(world, def);
  return SoftwareMarketView(
    standard: market.standard,
    rise: def.rise,
    customers: market.customers,
    referencePrice: reference,
    rivals: List.unmodifiable([
      for (final rival in market.rivals)
        (
          id: rival.id,
          name: rival.name,
          status: rival.status,
          customers: rival.customers,
          share: market.customers <= 0
              ? Fx.zero
              : Fx.raw(
                  mulDivRound(rival.customers, Fx.scale, market.customers),
                ),
          lead: rival.level - market.standard,
          price: reference.times(rival.price),
          founded: rival.founded,
          launchedOn: rival.launchedOn,
          startup: rival.id.index >= def.rivals.length,
          rest: rival.rest,
        ),
    ]),
  );
}

/// The candidates on the market for software people, at software pay in
/// the first country.
List<KeyPersonView> softwareCandidatesOf(WorldState world, ContentDb content) {
  final def = content.software;
  if (def == null) return const [];
  return List.unmodifiable([
    for (final person in world.keyPeople)
      if (person.status == KeyStatus.candidate && person.forSoftware)
        KeyPersonView(
          id: person.id,
          name: person.name,
          role: person.role,
          level: person.repute,
          known: false,
          salary: def.levels[person.repute].salary,
          since: person.since,
          monthsWorked: 0,
          leaves: _firstOnOrAfter(person.since + def.candidateDays),
        ),
  ]);
}

/// [software] as its owner sees it.
SoftwareView softwareViewOf(
  WorldState world,
  ContentDb content,
  Software software,
) {
  final def = content.software!;
  final market = world.softwareMarket!;
  final reference = softwareReferencePrice(world, def);
  final lead = software.level - market.standard;
  final engineers = softwareBuildPower(world, def, software.id, shown: true);
  final appeal = softwareAppeal(
    def,
    softwarePower(world, def, software.id, KeyRole.designer, shown: true),
  );
  final pace = softwareProgress(def, engineers, lead);
  final toLaunch = software.status == SoftwareStatus.building
      ? market.standard - def.launchGap - software.level
      : Fx.zero;
  final gaining = pace - def.rise;
  final monthsToLaunch = software.status != SoftwareStatus.building
      ? 0
      : toLaunch <= Fx.zero
      ? 1
      : gaining <= Fx.zero
      ? null
      : (toLaunch.raw + gaining.raw - 1) ~/ gaining.raw;
  final level = softwareWageLevel(world, content, software.country);
  final people = softwarePeople(world, software.id);
  final payroll = softwarePayroll(world, content, def, software);
  final office = softwareOffice(world, def, software);
  final revenue = software.price.timesInt(software.customers);
  final selling = software.status == SoftwareStatus.selling;
  final marketing = selling ? software.marketing : Money.zero;
  final monthProfit =
      revenue - revenue.times(def.serving) - marketing - office - payroll;
  final perCustomer = software.price - software.price.times(def.serving);
  final costs = payroll + office + software.marketing;
  final breakEven = perCustomer <= Money.zero
      ? 0
      : (costs.cents + perCustomer.cents - 1) ~/ perCustomer.cents;
  final last = software.rounds.lastOrNull;
  final company = world.companies[software.company.index];
  final offer = software.offer;
  return SoftwareView(
    id: software.id,
    company: software.company,
    name: software.name,
    country: software.country,
    status: software.status,
    founded: software.founded,
    launchedOn: software.launchedOn,
    lead: lead,
    appeal: appeal,
    pace: pace,
    rise: def.rise,
    toLaunch: toLaunch,
    monthsToLaunch: monthsToLaunch,
    customers: software.customers,
    price: software.price,
    marketing: software.marketing,
    referencePrice: reference,
    churn: softwareChurn(def, lead + appeal, software.price, reference),
    growth: softwareGrowth(software),
    history: List.unmodifiable(software.history),
    team: List.unmodifiable([
      for (final person in people)
        KeyPersonView(
          id: person.id,
          name: person.name,
          role: person.role,
          level: person.shownLevel(def.revealMonths),
          known: person.knownAfter(def.revealMonths),
          salary: softwareSalary(def, person, level),
          since: person.since,
          monthsWorked: person.monthsWorked,
        ),
    ]),
    maxPeople: def.maxPeople,
    wageLevel: level,
    payroll: payroll,
    office: office,
    serving: def.serving,
    revenue: revenue,
    monthProfit: monthProfit,
    breakEven: breakEven,
    worth: softwareWorth(world, content, def, software),
    stake: software.stake,
    investors: software.investors,
    rounds: List.unmodifiable(software.rounds),
    nextRound: last == null
        ? world.today
        : _monthsAfter(last.day, def.roundMonths, world.today),
    maxRoundShare: def.maxRoundShare,
    offer: offer == null || !company.isActive
        ? null
        : (
            rival: offer.rival,
            rivalName: market.rivals[offer.rival.index].name,
            price: offer.price,
            yours: offer.price.times(software.stake),
            expires: offer.expires,
          ),
  );
}

/// The first day [months] calendar months after [day]'s month, or [today]
/// if that is already past.
Day _monthsAfter(Day day, int months, Day today) {
  final target = monthOf(day) + months;
  if (monthOf(today) >= target) return today;
  return Day.fromDate(target ~/ 12, target % 12 + 1, 1);
}

/// [day] if it is the first of a month, else the first of the next.
Day _firstOnOrAfter(Day day) {
  if (day.isFirstOfMonth) return day;
  final date = day.date;
  return date.month == 12
      ? Day.fromDate(date.year + 1, 1, 1)
      : Day.fromDate(date.year, date.month + 1, 1);
}
