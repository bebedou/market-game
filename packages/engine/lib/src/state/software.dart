import '../content/software_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// The save version from which worlds keep a software market.
const softwareVersion = 35;

/// The months of its record a software product keeps.
const softwareHistoryMonths = 36;

/// Append only.
/// The save version from which software may start inside a company that
/// holds other businesses.
const softwareBesideVersion = 42;

enum SoftwareStatus {
  /// Building its first version: it can't sell yet.
  building,
  selling,

  /// Its owner closed it: its people left and its customers went elsewhere.
  closed,

  /// A rival bought its company.
  sold,
}

/// A month of a software product, for its charts: on the first of the
/// month, as the market turned.
final class SoftwareMonth {
  const SoftwareMonth({
    required this.day,
    required this.customers,
    required this.revenue,
    required this.lead,
    required this.bestRival,
    this.profit = Money.zero,
  });

  SoftwareMonth.read(StateReader reader)
    : day = Day(reader.readInt()),
      customers = reader.readInt(),
      revenue = Money(reader.readInt()),
      lead = Fx.raw(reader.readInt()),
      bestRival = Fx.raw(reader.readInt()),
      profit = reader.version >= softwareBesideVersion
          ? Money(reader.readInt())
          : Money.zero;

  final Day day;
  final int customers;

  /// What its customers pay a month, at its price that day.
  final Money revenue;

  /// How far it stood over the market's standard, and the best rival.
  final Fx lead;
  final Fx bestRival;

  /// What a month left it after its costs that day; zero in a save from
  /// before software could sit beside other businesses.
  final Money profit;

  void write(StateWriter writer) {
    writer
      ..writeInt(day.number)
      ..writeInt(customers)
      ..writeInt(revenue.cents)
      ..writeInt(lead.raw)
      ..writeInt(bestRival.raw)
      ..writeInt(profit.cents);
  }
}

/// A funding round: investors put [money] in for [share] of the company,
/// which was worth [value] before it.
final class FundingRound {
  const FundingRound({
    required this.day,
    required this.money,
    required this.share,
    required this.value,
  });

  FundingRound.read(StateReader reader)
    : day = Day(reader.readInt()),
      money = Money(reader.readInt()),
      share = Fx.raw(reader.readInt()),
      value = Money(reader.readInt());

  final Day day;
  final Money money;
  final Fx share;
  final Money value;

  void write(StateWriter writer) {
    writer
      ..writeInt(day.number)
      ..writeInt(money.cents)
      ..writeInt(share.raw)
      ..writeInt(value.cents);
  }
}

/// A rival's offer to buy a software company whole, for [price], until
/// [expires].
final class SoftwareOffer {
  const SoftwareOffer({
    required this.rival,
    required this.price,
    required this.expires,
  });

  SoftwareOffer.read(StateReader reader)
    : rival = SoftwareRivalId(reader.readInt()),
      price = Money(reader.readInt()),
      expires = Day(reader.readInt());

  final SoftwareRivalId rival;
  final Money price;
  final Day expires;

  void write(StateWriter writer) {
    writer
      ..writeInt(rival.index)
      ..writeInt(price.cents)
      ..writeInt(expires.number);
  }
}

/// A software company's product: a business unit of its own company, which
/// holds nothing else. Its people build it, and its customers pay [price]
/// a month each.
final class Software {
  Software({
    required this.id,
    required this.company,
    required this.country,
    required this.name,
    required this.founded,
    required this.level,
    required this.price,
  }) : status = SoftwareStatus.building,
       customers = 0,
       marketing = Money.zero,
       investors = Fx.zero,
       rounds = [],
       history = [];

  Software.read(this.id, StateReader reader)
    : company = CompanyId(reader.readInt()),
      country = CountryId(reader.readInt()),
      name = reader.readString(),
      founded = Day(reader.readInt()),
      status = SoftwareStatus.values[reader.readInt()],
      level = Fx.raw(reader.readInt()),
      customers = reader.readInt(),
      price = Money(reader.readInt()),
      marketing = Money(reader.readInt()),
      launchedOn = switch (reader.readNullableInt()) {
        final day? => Day(day),
        null => null,
      },
      investors = Fx.raw(reader.readInt()),
      rounds = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          FundingRound.read(reader),
      ],
      offer = reader.readBool() ? SoftwareOffer.read(reader) : null,
      history = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          SoftwareMonth.read(reader),
      ];

  final SoftwareId id;

  /// Its company, which it belongs to for good.
  final CompanyId company;

  /// Where it works from: its people are paid at that country's wages and
  /// it pays tax there.
  final CountryId country;
  String name;
  final Day founded;
  SoftwareStatus status;

  /// How good its product is, on the market's scale: against the standard,
  /// its lead.
  Fx level;
  int customers;

  /// What a customer pays a month.
  Money price;

  /// What it spends on marketing a month.
  Money marketing;

  /// When its first version went on sale.
  Day? launchedOn;

  /// The share of its company outside investors hold; its owner holds the
  /// rest.
  Fx investors;
  final List<FundingRound> rounds;

  /// A rival's standing offer to buy it, if any.
  SoftwareOffer? offer;

  /// Its months, oldest first, at most [softwareHistoryMonths].
  final List<SoftwareMonth> history;

  /// Whether it is still its company's to run: building or selling.
  bool get running =>
      status == SoftwareStatus.building || status == SoftwareStatus.selling;

  /// The share of its company its owner holds.
  Fx get stake => Fx.one - investors;

  void record(SoftwareMonth month) {
    history.add(month);
    if (history.length > softwareHistoryMonths) history.removeAt(0);
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeString(name)
      ..writeInt(founded.number)
      ..writeInt(status.index)
      ..writeInt(level.raw)
      ..writeInt(customers)
      ..writeInt(price.cents)
      ..writeInt(marketing.cents)
      ..writeNullableInt(launchedOn?.number)
      ..writeInt(investors.raw)
      ..writeInt(rounds.length);
    for (final round in rounds) {
      round.write(writer);
    }
    writer.writeBool(offer != null);
    offer?.write(writer);
    writer.writeInt(history.length);
    for (final month in history) {
      month.write(writer);
    }
  }
}

/// Append only.
enum RivalStatus { building, selling, folded }

/// A rival in the software market, run by formula: one of those there at
/// the start, a company that started up since, or everyone else as one.
final class SoftwareRival {
  SoftwareRival({
    required this.id,
    required this.name,
    required this.founded,
    required this.status,
    required this.level,
    required this.customers,
    required this.price,
    required this.marketingShare,
    required this.marketingBudget,
    required this.pace,
    required this.basePace,
    required this.appeal,
    this.rest = false,
    this.launchedOn,
  }) : customersBefore = customers;

  SoftwareRival.read(this.id, StateReader reader)
    : name = reader.readString(),
      founded = Day(reader.readInt()),
      status = RivalStatus.values[reader.readInt()],
      level = Fx.raw(reader.readInt()),
      customers = reader.readInt(),
      customersBefore = reader.readInt(),
      price = Fx.raw(reader.readInt()),
      marketingShare = Fx.raw(reader.readInt()),
      marketingBudget = Money(reader.readInt()),
      pace = Fx.raw(reader.readInt()),
      basePace = Fx.raw(reader.readInt()),
      appeal = Fx.raw(reader.readInt()),
      rest = reader.readBool(),
      launchedOn = switch (reader.readNullableInt()) {
        final day? => Day(day),
        null => null,
      };

  final SoftwareRivalId id;
  final String name;
  final Day founded;
  RivalStatus status;
  Fx level;
  int customers;

  /// Its customers a month before, to tell whether it is losing them.
  int customersBefore;

  /// Its price against the market's.
  final Fx price;

  /// What it spends on marketing a month: a share of its revenue, and a
  /// budget on top.
  final Fx marketingShare;
  final Money marketingBudget;

  /// What its people build a month with no lead, as level, now and as it
  /// tends to.
  Fx pace;
  Fx basePace;

  /// What its design adds, as lead.
  final Fx appeal;

  /// Whether it stands for everyone else in the market.
  final bool rest;
  Day? launchedOn;

  bool get selling => status == RivalStatus.selling;

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(founded.number)
      ..writeInt(status.index)
      ..writeInt(level.raw)
      ..writeInt(customers)
      ..writeInt(customersBefore)
      ..writeInt(price.raw)
      ..writeInt(marketingShare.raw)
      ..writeInt(marketingBudget.cents)
      ..writeInt(pace.raw)
      ..writeInt(basePace.raw)
      ..writeInt(appeal.raw)
      ..writeBool(rest)
      ..writeNullableInt(launchedOn?.number);
  }
}

/// The one world market for software: its standard, its customers and the
/// rivals run by formula. The players' products are in
/// `WorldState.software`.
final class SoftwareMarket {
  SoftwareMarket({
    required this.standard,
    required this.customers,
    required this.rivals,
  }) : customersBefore = customers;

  SoftwareMarket.read(StateReader reader)
    : standard = Fx.raw(reader.readInt()),
      customers = reader.readInt(),
      customersBefore = reader.readInt(),
      rivals = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          SoftwareRival.read(SoftwareRivalId(i), reader),
      ];

  /// Where the market's standard stands: what every product's lead is
  /// measured against.
  Fx standard;

  /// Everyone who pays for software, every product's customers together.
  int customers;

  /// [customers] before the month's turn, to tell a rival's share then.
  int customersBefore;

  /// Every rival there ever was, by [SoftwareRivalId]; those folded stay.
  final List<SoftwareRival> rivals;

  /// Everyone else, as one rival.
  SoftwareRival get rest => rivals.firstWhere((rival) => rival.rest);

  void write(StateWriter writer) {
    writer
      ..writeInt(standard.raw)
      ..writeInt(customers)
      ..writeInt(customersBefore)
      ..writeInt(rivals.length);
    for (final rival in rivals) {
      rival.write(writer);
    }
  }
}

/// The software market as [def] sets it out on [day]: each rival at its
/// share of the customers and its lead, its pace what keeps that lead.
SoftwareMarket initialSoftwareMarket(SoftwareDef def, Day day) {
  final rivals = <SoftwareRival>[];
  var placed = 0;
  for (final (i, rival) in def.rivals.indexed) {
    final customers = rival.rest
        ? def.customers - placed
        : mulDivRound(def.customers, rival.share.raw, Fx.scale);
    placed += customers;
    final pace = steadyPace(def, rival.lead);
    rivals.add(
      SoftwareRival(
        id: SoftwareRivalId(i),
        name: rival.name,
        founded: day,
        status: RivalStatus.selling,
        level: def.standard + rival.lead,
        customers: customers,
        price: rival.price,
        marketingShare: rival.marketing,
        marketingBudget: Money.zero,
        pace: pace,
        basePace: pace,
        appeal: Fx.zero,
        rest: rival.rest,
        launchedOn: day,
      ),
    );
  }
  return SoftwareMarket(
    standard: def.standard,
    customers: def.customers,
    rivals: rivals,
  );
}

/// The pace that holds a product [lead] ahead of a standard rising as
/// [def] has it.
Fx steadyPace(SoftwareDef def, Fx lead) =>
    def.rise * (Fx.one + def.hardness * (lead > Fx.zero ? lead : Fx.zero));
