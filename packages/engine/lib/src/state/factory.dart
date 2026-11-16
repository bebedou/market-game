import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';
import 'factory_sales.dart' show factorySalesVersion;
import 'store.dart' show labsVersion;

/// Append only.
enum FactoryStatus { running, closed }

/// The months of its lead a line remembers.
const lineHistoryMonths = 36;

/// One of a factory's products as its lab has developed it.
final class FactoryLine {
  FactoryLine(this.product) : history = [];

  FactoryLine.read(StateReader reader)
    : product = ProductId(reader.readInt()),
      generation = reader.readInt(),
      lead = Fx.raw(reader.readInt()),
      saving = Fx.raw(reader.readInt()),
      launchedOn = switch (reader.readNullableInt()) {
        final day? => Day(day),
        null => null,
      },
      history = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ];

  final ProductId product;

  /// Generations launched: none while it makes the product as bought.
  int generation = 0;

  /// How far it is over the market's standard, which catches up month by
  /// month: 0.10 is ten points better.
  Fx lead = Fx.zero;

  /// The share of its materials its generations have saved.
  Fx saving = Fx.zero;

  /// When its latest generation launched.
  Day? launchedOn;

  /// Its lead on the first of each month since its lab took it up, oldest
  /// first, at most [lineHistoryMonths].
  final List<Fx> history;

  /// Records [lead] as this month's.
  void record(Fx lead) {
    history.add(lead);
    if (history.length > lineHistoryMonths) history.removeAt(0);
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(product.index)
      ..writeInt(generation)
      ..writeInt(lead.raw)
      ..writeInt(saving.raw)
      ..writeNullableInt(launchedOn?.number)
      ..writeInt(history.length);
    for (final lead in history) {
      writer.writeInt(lead.raw);
    }
  }
}

/// The days a factory remembers of what it made.
const factoryHistoryDays = 28;

/// A company's factory: a business unit that makes one category, both its
/// lines, for its owner's shops, which then buy those goods only from it,
/// and for rivals if it sells to them. It makes what is ordered, up to its
/// shifts' capacity each month; what its owner's shops order beyond that is
/// bought from their wholesalers instead.
final class Factory {
  Factory({
    required this.id,
    required this.kind,
    required this.company,
    required this.country,
    required this.name,
    required this.opensOn,
    required this.builtFor,
    required this.shifts,
    required this.serves,
    this.rivalDiscount,
    this.status = FactoryStatus.running,
  }) : month = 0,
       madeThisMonth = 0,
       _own = List.filled(factoryHistoryDays, 0),
       _rival = List.filled(factoryHistoryDays, 0),
       _margin = List.filled(factoryHistoryDays, Money.zero),
       _lastDay = opensOn.number - 1;

  Factory.read(this.id, StateReader reader)
    : kind = FactoryKindId(reader.readInt()),
      company = CompanyId(reader.readInt()),
      country = CountryId(reader.readInt()),
      name = reader.readString(),
      opensOn = Day(reader.readInt()),
      builtFor = Money(reader.readInt()),
      shifts = reader.readInt(),
      serves = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readBool(),
      ],
      rivalDiscount = switch (reader.readNullableInt()) {
        final raw? => Fx.raw(raw),
        null => null,
      },
      status = FactoryStatus.values[reader.readInt()],
      month = reader.readInt(),
      madeThisMonth = reader.readInt(),
      _own = [for (var i = 0; i < factoryHistoryDays; i++) reader.readInt()],
      _rival = [for (var i = 0; i < factoryHistoryDays; i++) reader.readInt()],
      _margin = [
        for (var i = 0; i < factoryHistoryDays; i++) Money(reader.readInt()),
      ],
      _lastDay = reader.readInt() {
    if (reader.version < labsVersion) return;
    labBudget = Money(reader.readInt());
    project = switch (reader.readNullableInt()) {
      final index? => ProductId(index),
      null => null,
    };
    labWork = Money(reader.readInt());
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      lines.add(FactoryLine.read(reader));
    }
    if (reader.version < factorySalesVersion) return;
    size = reader.readInt();
    enlargedOn = switch (reader.readNullableInt()) {
      final day? => Day(day),
      null => null,
    };
    reliability = Fx.raw(reader.readInt());
    independentShare = reader.readInt();
  }

  final FactoryId id;
  final FactoryKindId kind;

  /// Whose it is: it belongs to its company for good.
  final CompanyId company;

  /// Where it stands: its staff are paid at that country's wages, and it
  /// pays tax there.
  final CountryId country;
  String name;

  /// The day it starts making: building takes the kind's build days.
  final Day opensOn;

  /// What building and fitting it cost, and enlarging it since.
  Money builtFor;

  /// Its size, by index into the scenario's sizes: 0 is a workshop.
  int size = 0;

  /// The day the works enlarging it to the next size end, if under way; it
  /// runs at its size until then.
  Day? enlargedOn;

  /// How reliably it has delivered its contracts, from 0 to 1: chains weigh
  /// it when choosing between bids.
  Fx reliability = Fx.one;

  /// The share of independent shops' goods it supplies, in millionths,
  /// which moves month by month toward what its list price and quality
  /// earn.
  int independentShare = 0;

  /// Shifts it runs, from 0, stopped, to the scenario's most.
  int shifts;

  /// The countries whose shops it delivers to, by [CountryId]: always its
  /// own.
  final List<bool> serves;

  /// What it sells to rivals for under their wholesalers' prices, or null if
  /// it sells only to its owner's shops.
  Fx? rivalDiscount;
  FactoryStatus status;

  /// The month [madeThisMonth] counts, as `year * 12 + month - 1`.
  int month;

  /// Units made this month so far.
  int madeThisMonth;

  /// What its lab spends a month while it has a [project].
  Money labBudget = Money.zero;

  /// The product whose next generation its lab is developing, if any.
  ProductId? project;

  /// The work done towards that generation, in money's worth.
  Money labWork = Money.zero;

  /// The products its lab has worked on, in the order it took them up.
  final List<FactoryLine> lines = [];

  /// [product]'s line, if its lab ever took it up.
  FactoryLine? lineOf(ProductId product) {
    for (final line in lines) {
      if (line.product == product) return line;
    }
    return null;
  }

  /// [product]'s line, opened if its lab hadn't taken it up.
  FactoryLine lineFor(ProductId product) {
    final existing = lineOf(product);
    if (existing != null) return existing;
    final line = FactoryLine(product);
    lines.add(line);
    return line;
  }

  /// How far [product] as it makes it is over the market's standard.
  Fx leadOf(ProductId product) => lineOf(product)?.lead ?? Fx.zero;

  /// The share of [product]'s materials its generations have saved.
  Fx savingOf(ProductId product) => lineOf(product)?.saving ?? Fx.zero;

  final List<int> _own;
  final List<int> _rival;
  final List<Money> _margin;
  int _lastDay;

  /// Whether it is making goods on [day]: built and not closed.
  bool runsOn(Day day) =>
      status == FactoryStatus.running && day.number >= opensOn.number;

  bool servesCountry(CountryId country) =>
      country.index < serves.length && serves[country.index];

  /// Serves countries the scenario gained since it was built: none of them.
  void growCountries(int countries) {
    while (serves.length < countries) {
      serves.add(false);
    }
  }

  /// What it makes in a day at its shifts.
  int dailyCapacity(FactoryKindDef kind) => kind.shiftUnits * shifts;

  /// What it can make in the month of [day] at its shifts.
  int monthCapacity(FactoryKindDef kind, Day day) =>
      dailyCapacity(kind) * daysInMonth(day.date.year, day.date.month);

  /// What it can still make this month, as of [day].
  int capacityLeft(FactoryKindDef kind, Day day) {
    final made = month == monthOf(day) ? madeThisMonth : 0;
    final left = monthCapacity(kind, day) - made;
    return left > 0 ? left : 0;
  }

  /// What it can sell to rivals this month, as of [day]: what it can still
  /// make, less what its owner's shops will want for the rest of the month
  /// at their pace of the last weeks.
  int spareFor(FactoryKindDef kind, Day day) {
    final date = day.date;
    final daysLeft = daysInMonth(date.year, date.month) - date.day + 1;
    final reserve = mulDivRound(
      recentOwnUnits(day),
      daysLeft,
      factoryHistoryDays,
    );
    final spare = capacityLeft(kind, day) - reserve;
    return spare > 0 ? spare : 0;
  }

  /// Counts [units] made on [day] for its owner's shops ([own]) or a
  /// rival's, earning [margin] over their materials and freight.
  void recordMade(Day day, int units, {required bool own, Money? margin}) {
    final key = monthOf(day);
    if (month != key) {
      month = key;
      madeThisMonth = 0;
    }
    madeThisMonth += units;
    _roll(day);
    final slot = day.number % factoryHistoryDays;
    if (own) {
      _own[slot] += units;
    } else {
      _rival[slot] += units;
    }
    if (margin != null) _margin[slot] += margin;
  }

  void _roll(Day day) {
    if (day.number <= _lastDay) return;
    final from = day.number - _lastDay >= factoryHistoryDays
        ? day.number - factoryHistoryDays + 1
        : _lastDay + 1;
    for (var d = from; d <= day.number; d++) {
      final slot = d % factoryHistoryDays;
      _own[slot] = 0;
      _rival[slot] = 0;
      _margin[slot] = Money.zero;
    }
    _lastDay = day.number;
  }

  int _sum(List<int> days, Day today) {
    var total = 0;
    final oldest = today.number - factoryHistoryDays + 1;
    for (var d = oldest; d <= today.number && d <= _lastDay; d++) {
      total += days[d % factoryHistoryDays];
    }
    return total;
  }

  /// Units made for its owner's shops over the last [factoryHistoryDays]
  /// days up to [today].
  int recentOwnUnits(Day today) => _sum(_own, today);

  /// Units made for rivals over the same days.
  int recentRivalUnits(Day today) => _sum(_rival, today);

  /// What those units sold for beyond their materials and freight.
  Money recentMargin(Day today) {
    var total = Money.zero;
    final oldest = today.number - factoryHistoryDays + 1;
    for (var d = oldest; d <= today.number && d <= _lastDay; d++) {
      total += _margin[d % factoryHistoryDays];
    }
    return total;
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(kind.index)
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeString(name)
      ..writeInt(opensOn.number)
      ..writeInt(builtFor.cents)
      ..writeInt(shifts)
      ..writeInt(serves.length);
    serves.forEach(writer.writeBool);
    writer
      ..writeNullableInt(rivalDiscount?.raw)
      ..writeInt(status.index)
      ..writeInt(month)
      ..writeInt(madeThisMonth);
    _own.forEach(writer.writeInt);
    _rival.forEach(writer.writeInt);
    for (final margin in _margin) {
      writer.writeInt(margin.cents);
    }
    writer
      ..writeInt(_lastDay)
      ..writeInt(labBudget.cents)
      ..writeNullableInt(project?.index)
      ..writeInt(labWork.cents)
      ..writeInt(lines.length);
    for (final line in lines) {
      line.write(writer);
    }
    writer
      ..writeInt(size)
      ..writeNullableInt(enlargedOn?.number)
      ..writeInt(reliability.raw)
      ..writeInt(independentShare);
  }
}

/// [day]'s month as `year * 12 + month - 1`.
int monthOf(Day day) => day.date.year * 12 + day.date.month - 1;

/// The first day of [month], counted as [monthOf] counts it.
Day firstOfMonth(int month) => Day.fromDate(month ~/ 12, month % 12 + 1, 1);
