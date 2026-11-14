import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The save version from which a brief grows by a rate.
const _rateVersion = 31;

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
      ];

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

  bool allows(Growth step) => growth.index >= step.index;

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
