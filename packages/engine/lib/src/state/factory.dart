import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// Append only.
enum FactoryStatus { running, closed }

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
      _lastDay = reader.readInt();

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

  /// What building and fitting it cost.
  final Money builtFor;

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
    writer.writeInt(_lastDay);
  }
}

/// [day]'s month as `year * 12 + month - 1`.
int monthOf(Day day) => day.date.year * 12 + day.date.month - 1;
