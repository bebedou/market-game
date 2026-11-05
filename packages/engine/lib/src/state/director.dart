import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

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
  });

  Director.read(StateReader reader)
    : grade = DirectorGradeId(reader.readInt()),
      strategy = StrategyId(reader.readInt()),
      managerGrade = ManagerGradeId(reader.readInt()),
      growth = Growth.values[reader.readInt()],
      payout = reader.readBool(),
      hiredOn = Day(reader.readInt()),
      borrows = reader.version >= 22 ? reader.readBool() : false;

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

  bool allows(Growth step) => growth.index >= step.index;

  void write(StateWriter writer) {
    writer
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(managerGrade.index)
      ..writeInt(growth.index)
      ..writeBool(payout)
      ..writeInt(hiredOn.number)
      ..writeBool(borrows);
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
      StoreBought.tag => StoreBought(
        day,
        store: StoreId(reader.readInt()),
        price: Money(reader.readInt()),
        paybackMonths: reader.readInt(),
        borrowed: reader.version >= 22 ? Money(reader.readInt()) : Money.zero,
      ),
      ProfitPaid.tag => ProfitPaid(day, amount: Money(reader.readInt())),
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
