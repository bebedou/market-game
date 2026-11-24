import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The save version from which a brief grows by a rate.
const _rateVersion = 31;

/// The save version from which a director is a person with a record.
const personVersion = 40;

/// The save version from which a brief sets a goal for each business.
const goalsVersion = 42;

/// What the owner asks of one of a company's businesses, the boss's brief
/// (the owner's brief B, 2026-11-17). Append only.
enum Goal {
  /// Takes the cash out: no works, nothing new, no research; its shops
  /// that keep losing money closed.
  harvest,

  /// Keeps it as it is: its shops kept up to date, its plants kept full.
  hold,

  /// Grows it at the pace its boss runs well, where it pays back.
  grow,

  /// Grows it twice as fast, buying rivals too, and misjudging more.
  growFast,
}

/// How far a director may grow the company they run, each step allowing
/// what the ones before it do.
enum Growth {
  /// Keeps the stores as they are, closing those that keep losing money.
  none,

  /// Enlarges stores and converts them to a bigger format.
  invest,

  /// Opens new stores.
  open,

  /// Buys struggling rivals' stores.
  buy,
}

/// A director running a company for its owner, above its store managers:
/// they hire a manager for any store without one, close stores that keep
/// losing money, grow the company as far as [growth] allows, borrowing to if
/// [borrows] says so, and send the owner what is left each month if [payout]
/// says so.
final class Director {
  const Director({
    required this.grade,
    required this.strategy,
    required this.managerGrade,
    required this.growth,
    required this.payout,
    required this.hiredOn,
    this.borrows = false,
    this.nationalRate = Fx.zero,
    this.nationalAuto = false,
    this.nationalRegions = const [],
    this.person,
    this.record = const DirectorRecord(),
    this.goals = const {},
  });

  Director.read(StateReader reader)
    : grade = DirectorGradeId(reader.readInt()),
      strategy = StrategyId(reader.readInt()),
      managerGrade = ManagerGradeId(reader.readInt()),
      growth = Growth.values[reader.readInt()],
      payout = reader.readBool(),
      hiredOn = Day(reader.readInt()),
      borrows = reader.version >= 22 ? reader.readBool() : false,
      // Before rates, a brief to open some shops a month left the rate to
      // the director.
      nationalAuto = reader.version >= _rateVersion
          ? reader.readBool()
          : reader.version >= 29 && reader.readInt() > 0,
      nationalRate = reader.version >= _rateVersion
          ? Fx.raw(reader.readInt())
          : Fx.zero,
      nationalRegions = [
        if (reader.version >= 29)
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readString(),
      ],
      person = reader.version >= personVersion && reader.readBool()
          ? DirectorPerson.read(reader)
          : null,
      record = reader.version >= personVersion
          ? DirectorRecord.read(reader)
          : const DirectorRecord(),
      goals = reader.version >= goalsVersion ? readGoals(reader) : const {};

  final DirectorGradeId grade;

  /// What the managers they hire follow, and the kind of store they open.
  final StrategyId strategy;

  /// The grade of the managers they hire.
  final ManagerGradeId managerGrade;
  final Growth growth;

  /// Whether they pay the owner, on the first of each month, the cash left
  /// beyond the company's reserve and the year's tax.
  final bool payout;
  final Day hiredOn;

  /// Whether they may borrow what the company lacks to grow, on its
  /// earnings; never on the owner's guarantee.
  final bool borrows;

  /// How fast they grow the company's shops run by formula across its
  /// countries: new shops a month as a share of its shops of the trade in
  /// each country (see `nationalBudget`); none at zero. Ignored when
  /// [nationalAuto].
  final Fx nationalRate;

  /// Whether they grow at the rate their grade runs well
  /// ([DirectorGradeDef.growth]).
  final bool nationalAuto;

  /// The regions they may open those in, by the national table's keys; any
  /// region of the company's countries if empty.
  final List<String> nationalRegions;

  /// Who they are; null for a director hired before directors were people,
  /// or by a tool, who applies the brief as it is.
  final DirectorPerson? person;

  /// What they have done for the company since they were hired.
  final DirectorRecord record;

  /// The goal for each of the company's businesses, by its key (see
  /// `tradeKey`, `plantsKey` and `softwareBusiness`); empty for a brief
  /// given before goals, which [growth] and the national rate set alone.
  final Map<String, Goal> goals;

  bool allows(Growth step) => growth.index >= step.index;

  /// The goal for [business]: as briefed, or else what [growth] amounts to.
  Goal goalOf(String business) =>
      goals[business] ??
      switch (growth) {
        Growth.none => Goal.harvest,
        Growth.invest => Goal.hold,
        Growth.open => Goal.grow,
        Growth.buy => Goal.growFast,
      };

  /// Whether [business]'s goal allows [step]: works from holding on,
  /// opening from growing, buying when growing fast.
  bool allowsIn(String business, Growth step) {
    if (goals.isEmpty) return allows(step);
    final allowed = switch (goalOf(business)) {
      Goal.harvest => Growth.none,
      Goal.hold => Growth.invest,
      Goal.grow => Growth.open,
      Goal.growFast => Growth.buy,
    };
    return allowed.index >= step.index;
  }

  /// The same director with the goals [goals].
  Director withGoals(Map<String, Goal> goals) => Director(
    grade: grade,
    strategy: strategy,
    managerGrade: managerGrade,
    growth: growth,
    payout: payout,
    hiredOn: hiredOn,
    borrows: borrows,
    nationalRate: nationalRate,
    nationalAuto: nationalAuto,
    nationalRegions: nationalRegions,
    person: person,
    record: record,
    goals: Map.unmodifiable(goals),
  );

  /// The same director, with [memo] counted in their record.
  Director noting(Memo memo) {
    final noted = record.noting(memo);
    if (identical(noted, record)) return this;
    return Director(
      grade: grade,
      strategy: strategy,
      managerGrade: managerGrade,
      growth: growth,
      payout: payout,
      hiredOn: hiredOn,
      borrows: borrows,
      nationalRate: nationalRate,
      nationalAuto: nationalAuto,
      nationalRegions: nationalRegions,
      person: person,
      record: noted,
      goals: goals,
    );
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(managerGrade.index)
      ..writeInt(growth.index)
      ..writeBool(payout)
      ..writeInt(hiredOn.number)
      ..writeBool(borrows)
      ..writeBool(nationalAuto)
      ..writeInt(nationalRate.raw)
      ..writeInt(nationalRegions.length);
    nationalRegions.forEach(writer.writeString);
    writer.writeBool(person != null);
    person?.write(writer);
    record.write(writer);
    writeGoals(writer, goals);
  }
}

/// A brief's goals, as [writeGoals] wrote them.
Map<String, Goal> readGoals(StateReader reader) => Map.unmodifiable({
  for (var i = 0, n = reader.readInt(); i < n; i++)
    reader.readString(): Goal.values[reader.readInt()],
});

void writeGoals(StateWriter writer, Map<String, Goal> goals) {
  writer.writeInt(goals.length);
  for (final MapEntry(:key, :value) in goals.entries) {
    writer
      ..writeString(key)
      ..writeInt(value.index);
  }
}

/// Who a director is: a name, a character and a past, and what their
/// portrait is drawn from.
final class DirectorPerson {
  const DirectorPerson({
    required this.name,
    required this.female,
    required this.character,
    required this.looks,
    this.employer = '',
    this.years = 0,
  });

  DirectorPerson.read(StateReader reader)
    : name = reader.readString(),
      female = reader.readBool(),
      character = reader.readInt(),
      looks = reader.readInt(),
      employer = reader.readString(),
      years = reader.readInt();

  final String name;
  final bool female;

  /// By position in `DirectorsDef.characters`.
  final int character;

  /// A 32-bit number their portrait and sayings are picked from.
  final int looks;

  /// Where they worked before, if anywhere named, and for how many years.
  final String employer;
  final int years;

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeBool(female)
      ..writeInt(character)
      ..writeInt(looks)
      ..writeString(employer)
      ..writeInt(years);
  }
}

/// Whether [a] and [b] are the same person, both none included.
bool samePerson(DirectorPerson? a, DirectorPerson? b) =>
    identical(a, b) ||
    a != null &&
        b != null &&
        a.name == b.name &&
        a.female == b.female &&
        a.character == b.character &&
        a.looks == b.looks &&
        a.employer == b.employer &&
        a.years == b.years;

/// What a director has done for their company since they were hired, kept
/// in full though old memos are dropped.
final class DirectorRecord {
  const DirectorRecord({
    this.shopsAtHire = -1,
    this.opened = 0,
    this.bought = 0,
    this.closed = 0,
    this.paid = Money.zero,
  });

  DirectorRecord.read(StateReader reader)
    : shopsAtHire = reader.readInt(),
      opened = reader.readInt(),
      bought = reader.readInt(),
      closed = reader.readInt(),
      paid = Money(reader.readInt());

  /// The company's shops when they came, of every kind and scale; -1 if
  /// unknown, for a director hired before records were kept.
  final int shopsAtHire;

  /// The shops they opened (across countries too), bought and closed.
  final int opened;
  final int bought;
  final int closed;

  /// What they paid the owner.
  final Money paid;

  /// This record with [memo] counted; itself if [memo] counts for nothing.
  DirectorRecord noting(Memo memo) {
    var (opened, bought, closed, paid) = (
      this.opened,
      this.bought,
      this.closed,
      this.paid,
    );
    switch (memo) {
      case StoreOpened() || DistrictOpened():
        opened++;
      case NationalOpened(:final count):
        opened += count;
      case StoreBought() || DistrictBought():
        bought++;
      case StoreClosed():
        closed++;
      case ProfitPaid(:final amount):
        paid += amount;
      default:
        return this;
    }
    return DirectorRecord(
      shopsAtHire: shopsAtHire,
      opened: opened,
      bought: bought,
      closed: closed,
      paid: paid,
    );
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(shopsAtHire)
      ..writeInt(opened)
      ..writeInt(bought)
      ..writeInt(closed)
      ..writeInt(paid.cents);
  }
}

/// The most memos a company keeps; older ones are dropped.
const maxMemos = 240;

/// A decision a director carried out, kept for the owner: the monthly
/// letter is written from these.
sealed class Memo {
  const Memo(this.day);

  /// Reads a memo written by [write].
  factory Memo.read(StateReader reader) {
    final tag = reader.readInt();
    final day = Day(reader.readInt());
    return switch (tag) {
      ManagerHired.tag => ManagerHired(
        day,
        store: StoreId(reader.readInt()),
        grade: ManagerGradeId(reader.readInt()),
      ),
      StoreClosed.tag => StoreClosed(
        day,
        store: StoreId(reader.readInt()),
        sales: Money(reader.readInt()),
        loss: Money(reader.readInt()),
      ),
      StoreEnlarged.tag => StoreEnlarged(
        day,
        store: StoreId(reader.readInt()),
        cost: Money(reader.readInt()),
        borrowed: reader.version >= 22 ? Money(reader.readInt()) : Money.zero,
      ),
      StoreConverted.tag => StoreConverted(
        day,
        store: StoreId(reader.readInt()),
        format: FormatId(reader.readInt()),
        cost: Money(reader.readInt()),
        borrowed: reader.version >= 22 ? Money(reader.readInt()) : Money.zero,
      ),
      StoreOpened.tag => StoreOpened(
        day,
        site: SiteId(reader.readInt()),
        format: FormatId(reader.readInt()),
        cost: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: reader.version >= 22 ? Money(reader.readInt()) : Money.zero,
      ),
      DistrictOpened.tag => DistrictOpened(
        day,
        row: reader.readInt(),
        site: reader.readInt(),
        format: FormatId(reader.readInt()),
        cost: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: Money(reader.readInt()),
      ),
      DistrictBought.tag => DistrictBought(
        day,
        row: reader.readInt(),
        site: reader.readInt(),
        price: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: Money(reader.readInt()),
      ),
      StoreBought.tag => StoreBought(
        day,
        store: StoreId(reader.readInt()),
        price: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: reader.version >= 22 ? Money(reader.readInt()) : Money.zero,
      ),
      ProfitPaid.tag => ProfitPaid(day, amount: Money(reader.readInt())),
      NationalOpened.tag => NationalOpened(
        day,
        country: CountryId(reader.readInt()),
        region: reader.readString(),
        format: FormatId(reader.readInt()),
        count: reader.readInt(),
        cost: Money(reader.readInt()),
        earns: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: Money(reader.readInt()),
      ),
      ProfitKept.tag => ProfitKept(
        day,
        site: reader.readBool() ? SiteId(reader.readInt()) : null,
        store: reader.readBool() ? StoreId(reader.readInt()) : null,
        needed: Money(reader.readInt()),
      ),
      _ => throw FormatException('Unknown memo tag $tag'),
    };
  }

  final Day day;

  void write(StateWriter writer);
}

/// Hired a manager of [grade] for [store].
final class ManagerHired extends Memo {
  const ManagerHired(super.day, {required this.store, required this.grade});

  static const int tag = 1;

  final StoreId store;
  final ManagerGradeId grade;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(store.index)
      ..writeInt(grade.index);
  }
}

/// Closed [store], which made a [loss] on [sales] over its last twelve
/// months.
final class StoreClosed extends Memo {
  const StoreClosed(
    super.day, {
    required this.store,
    required this.sales,
    required this.loss,
  });

  static const int tag = 2;

  final StoreId store;
  final Money sales;
  final Money loss;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(store.index)
      ..writeInt(sales.cents)
      ..writeInt(loss.cents);
  }
}

/// Started enlarging [store], for [cost], having [borrowed] towards it.
final class StoreEnlarged extends Memo {
  const StoreEnlarged(
    super.day, {
    required this.store,
    required this.cost,
    this.borrowed = Money.zero,
  });

  static const int tag = 3;

  final StoreId store;
  final Money cost;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(store.index)
      ..writeInt(cost.cents)
      ..writeInt(borrowed.cents);
  }
}

/// Started converting [store] to [format], for [cost], having [borrowed]
/// towards it.
final class StoreConverted extends Memo {
  const StoreConverted(
    super.day, {
    required this.store,
    required this.format,
    required this.cost,
    this.borrowed = Money.zero,
  });

  static const int tag = 4;

  final StoreId store;
  final FormatId format;
  final Money cost;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(store.index)
      ..writeInt(format.index)
      ..writeInt(cost.cents)
      ..writeInt(borrowed.cents);
  }
}

/// Started a store of [format] at [site]: [cost] to fit out, expected to
/// pay it back in [paybackMonths], [borrowed] of what it takes from the bank.
final class StoreOpened extends Memo {
  const StoreOpened(
    super.day, {
    required this.site,
    required this.format,
    required this.cost,
    required this.paybackMonths,
    this.borrowed = Money.zero,
  });

  static const int tag = 5;

  final SiteId site;
  final FormatId format;
  final Money cost;
  final int paybackMonths;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(site.index)
      ..writeInt(format.index)
      ..writeInt(cost.cents)
      ..writeInt(paybackMonths)
      ..writeInt(borrowed.cents);
  }
}

/// Bought a rival's [store] for [price], expected to pay it back in
/// [paybackMonths], [borrowed] of it from the bank.
final class StoreBought extends Memo {
  const StoreBought(
    super.day, {
    required this.store,
    required this.price,
    required this.paybackMonths,
    this.borrowed = Money.zero,
  });

  static const int tag = 6;

  final StoreId store;
  final Money price;
  final int paybackMonths;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(store.index)
      ..writeInt(price.cents)
      ..writeInt(paybackMonths)
      ..writeInt(borrowed.cents);
  }
}

/// Paid the owner [amount] as a dividend.
final class ProfitPaid extends Memo {
  const ProfitPaid(super.day, {required this.amount});

  static const int tag = 7;

  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(amount.cents);
  }
}

/// Kept the month's profit, owed to the owner, to save for a new store at
/// [site] or works on [store]: [needed] in all, beyond the company's
/// reserve and the year's tax.
final class ProfitKept extends Memo {
  const ProfitKept(super.day, {this.site, this.store, required this.needed});

  static const int tag = 8;

  final SiteId? site;
  final StoreId? store;
  final Money needed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeNullableInt(site?.index)
      ..writeNullableInt(store?.index)
      ..writeInt(needed.cents);
  }
}

/// Opened [count] shops of [format] run by formula in [region] of [country],
/// for [cost], each to earn about [earns] a year and pay back in
/// [paybackMonths], having [borrowed] towards them.
final class NationalOpened extends Memo {
  const NationalOpened(
    super.day, {
    required this.country,
    required this.region,
    required this.format,
    required this.count,
    required this.cost,
    required this.earns,
    required this.paybackMonths,
    this.borrowed = Money.zero,
  });

  static const int tag = 9;

  final CountryId country;

  /// The region's key in the national table.
  final String region;
  final FormatId format;
  final int count;
  final Money cost;
  final Money earns;
  final int paybackMonths;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(country.index)
      ..writeString(region)
      ..writeInt(format.index)
      ..writeInt(count)
      ..writeInt(cost.cents)
      ..writeInt(earns.cents)
      ..writeInt(paybackMonths)
      ..writeInt(borrowed.cents);
  }
}

/// Opened a shop of [format] on [site] of the district run by formula in
/// [row], for [cost] of fitting out, expected to pay back in
/// [paybackMonths], having [borrowed] towards it.
final class DistrictOpened extends Memo {
  const DistrictOpened(
    super.day, {
    required this.row,
    required this.site,
    required this.format,
    required this.cost,
    required this.paybackMonths,
    this.borrowed = Money.zero,
  });

  static const int tag = 10;

  /// The district's place in the scenario's neighbourhoods.
  final int row;

  /// The site's number in the district.
  final int site;
  final FormatId format;
  final Money cost;
  final int paybackMonths;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(row)
      ..writeInt(site)
      ..writeInt(format.index)
      ..writeInt(cost.cents)
      ..writeInt(paybackMonths)
      ..writeInt(borrowed.cents);
  }
}

/// Bought the struggling shop on [site] of the district run by formula in
/// [row] for [price], expected to pay it back in [paybackMonths], having
/// [borrowed] towards it.
final class DistrictBought extends Memo {
  const DistrictBought(
    super.day, {
    required this.row,
    required this.site,
    required this.price,
    required this.paybackMonths,
    this.borrowed = Money.zero,
  });

  static const int tag = 11;

  final int row;
  final int site;
  final Money price;
  final int paybackMonths;
  final Money borrowed;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(day.number)
      ..writeInt(row)
      ..writeInt(site)
      ..writeInt(price.cents)
      ..writeInt(paybackMonths)
      ..writeInt(borrowed.cents);
  }
}
