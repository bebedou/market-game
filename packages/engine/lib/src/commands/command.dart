import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';
import '../state/director.dart' show Growth;
import '../state/store.dart' show allDuties;

/// A command as it was applied: the day it took effect, and the command.
typedef LoggedCommand = ({Day day, Command command});

/// A product and quantity on an order.
typedef OrderQuantity = ({ProductId product, int quantity});

/// The only way an actor changes the world. Commands are queued and applied
/// at the start of the next step, under the same rules for every actor.
///
/// Each command type has a serialization tag. Never renumber one: saved
/// command logs depend on it.
sealed class Command {
  const Command(this.actor);

  /// Reads a command written by [write].
  factory Command.read(StateReader reader) {
    final tag = reader.readInt();
    final actor = PersonId(reader.readInt());
    return switch (tag) {
      SetPrice.tag => SetPrice(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
        price: Money(reader.readInt()),
      ),
      PlaceOrder.tag => PlaceOrder(
        actor,
        store: StoreId(reader.readInt()),
        supplier: SupplierId(reader.readInt()),
        lines: [
          for (var i = 0, n = reader.readInt(); i < n; i++)
            (product: ProductId(reader.readInt()), quantity: reader.readInt()),
        ],
      ),
      ListProduct.tag => ListProduct(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
        price: Money(reader.readInt()),
      ),
      DelistProduct.tag => DelistProduct(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
      ),
      InjectCapital.tag => InjectCapital(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
      ),
      PayDividend.tag => PayDividend(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
      ),
      TakeLoan.tag => TakeLoan(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
        termMonths: reader.readInt(),
        guarantee: reader.readBool(),
      ),
      RepayLoan.tag => RepayLoan(
        actor,
        loan: reader.readInt(),
        amount: Money(reader.readInt()),
      ),
      OpenStore.tag => OpenStore(
        actor,
        site: SiteId(reader.readInt()),
        name: reader.readString(),
        company: switch (reader.readNullableInt()) {
          final index? => CompanyId(index),
          null => null,
        },
        capital: Money(reader.readInt()),
        format: reader.version >= 10
            ? FormatId(reader.readInt())
            : const FormatId(0),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
      ),
      CloseStore.tag => CloseStore(actor, store: StoreId(reader.readInt())),
      SetStaffing.tag => SetStaffing(
        actor,
        store: StoreId(reader.readInt()),
        staff: [
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
        ],
      ),
      BuyResearch.tag => BuyResearch(
        actor,
        company: CompanyId(reader.readInt()),
        market: MarketId(reader.readInt()),
        tier: ResearchTierId(reader.readInt()),
      ),
      HireManager.tag => HireManager(
        actor,
        store: StoreId(reader.readInt()),
        grade: ManagerGradeId(reader.readInt()),
        strategy: StrategyId(reader.readInt()),
        duties: allDuties([
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readBool(),
        ]),
      ),
      FireManager.tag => FireManager(actor, store: StoreId(reader.readInt())),
      ExpandStore.tag => ExpandStore(actor, store: StoreId(reader.readInt())),
      RenameStore.tag => RenameStore(
        actor,
        store: StoreId(reader.readInt()),
        name: reader.readString(),
      ),
      RenameCompany.tag => RenameCompany(
        actor,
        company: CompanyId(reader.readInt()),
        name: reader.readString(),
      ),
      SetCushion.tag => SetCushion(
        actor,
        company: CompanyId(reader.readInt()),
        days: reader.readInt(),
      ),
      ConvertStore.tag => ConvertStore(
        actor,
        store: StoreId(reader.readInt()),
        format: FormatId(reader.readInt()),
      ),
      SetMarketing.tag => SetMarketing(
        actor,
        store: StoreId(reader.readInt()),
        share: Fx.raw(reader.readInt()),
      ),
      BuyStore.tag => BuyStore(
        actor,
        store: StoreId(reader.readInt()),
        company: CompanyId(reader.readInt()),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
      ),
      SellStore.tag => SellStore(actor, store: StoreId(reader.readInt())),
      BuyCompany.tag => BuyCompany(
        actor,
        company: CompanyId(reader.readInt()),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
      ),
      HireDirector.tag => HireDirector(
        actor,
        company: CompanyId(reader.readInt()),
        grade: DirectorGradeId(reader.readInt()),
        strategy: StrategyId(reader.readInt()),
        managerGrade: ManagerGradeId(reader.readInt()),
        growth: Growth.values[reader.readInt()],
        payout: reader.readBool(),
        borrows: reader.version >= 22 ? reader.readBool() : false,
      ),
      FireDirector.tag => FireDirector(
        actor,
        company: CompanyId(reader.readInt()),
      ),
      _ => throw FormatException('Unknown command tag $tag'),
    };
  }

  final PersonId actor;

  void write(StateWriter writer);
}

/// Sets the shelf price of a product the store already lists.
final class SetPrice extends Command {
  const SetPrice(
    super.actor, {
    required this.store,
    required this.product,
    required this.price,
  });

  static const int tag = 1;

  final StoreId store;
  final ProductId product;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'SetPrice(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index}, price: ${price.toDecimalString()})';
}

/// Orders stock from a supplier. It arrives after the supplier's lead time,
/// at prices fixed now; the invoice is due after the supplier's payment terms.
final class PlaceOrder extends Command {
  const PlaceOrder(
    super.actor, {
    required this.store,
    required this.supplier,
    required this.lines,
  });

  static const int tag = 2;

  final StoreId store;
  final SupplierId supplier;
  final List<OrderQuantity> lines;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(supplier.index)
      ..writeInt(lines.length);
    for (final (:product, :quantity) in lines) {
      writer
        ..writeInt(product.index)
        ..writeInt(quantity);
    }
  }

  @override
  String toString() {
    final items = [
      for (final (:product, :quantity) in lines) '${product.index}×$quantity',
    ];
    return 'PlaceOrder(actor: ${actor.index}, store: ${store.index}, '
        'supplier: ${supplier.index}, lines: ${items.join(', ')})';
  }
}

/// Puts a product on a free shelf slot, at [price].
final class ListProduct extends Command {
  const ListProduct(
    super.actor, {
    required this.store,
    required this.product,
    required this.price,
  });

  static const int tag = 3;

  final StoreId store;
  final ProductId product;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'ListProduct(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index}, price: ${price.toDecimalString()})';
}

/// Frees a product's shelf slot. Remaining stock is written off, and units
/// still on order are refused when they arrive.
final class DelistProduct extends Command {
  const DelistProduct(
    super.actor, {
    required this.store,
    required this.product,
  });

  static const int tag = 4;

  final StoreId store;
  final ProductId product;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index);
  }

  @override
  String toString() =>
      'DelistProduct(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index})';
}

/// Moves money from the actor's personal cash into a company they own.
final class InjectCapital extends Command {
  const InjectCapital(
    super.actor, {
    required this.company,
    required this.amount,
  });

  static const int tag = 5;

  final CompanyId company;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'InjectCapital(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()})';
}

/// Pays the actor out of a company they own, from its retained profits.
final class PayDividend extends Command {
  const PayDividend(super.actor, {required this.company, required this.amount});

  static const int tag = 6;

  final CompanyId company;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'PayDividend(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()})';
}

/// Borrows from the bank, repaid monthly over [termMonths]. Without a
/// [guarantee], the bank lends on the company's earnings (see
/// `earningsCredit`); with one, on the owner's cash (see `guaranteeRoom`).
final class TakeLoan extends Command {
  const TakeLoan(
    super.actor, {
    required this.company,
    required this.amount,
    required this.termMonths,
    required this.guarantee,
  });

  static const int tag = 7;

  final CompanyId company;
  final Money amount;
  final int termMonths;

  /// Whether the owner personally answers for the loan if the company fails.
  final bool guarantee;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents)
      ..writeInt(termMonths)
      ..writeBool(guarantee);
  }

  @override
  String toString() =>
      'TakeLoan(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()}, termMonths: $termMonths, '
      'guarantee: $guarantee)';
}

/// Repays [amount] of a loan's principal early, with the interest accrued on
/// the loan so far.
final class RepayLoan extends Command {
  const RepayLoan(super.actor, {required this.loan, required this.amount});

  static const int tag = 8;

  /// The loan number.
  final int loan;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(loan)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'RepayLoan(actor: ${actor.index}, loan: $loan, '
      'amount: ${amount.toDecimalString()})';
}

/// Opens a store called [name] at a vacant site. The company pays the fit-out
/// now and the store trades once the site's build days have passed. Without
/// a [company], founds one with the same name and [capital] from the actor's
/// personal cash; with one, [capital] is injected into it first. The
/// company may [borrow] towards it, repaid over [termMonths] (see
/// `splitLoan`); if the bank won't lend, nothing happens.
final class OpenStore extends Command {
  const OpenStore(
    super.actor, {
    required this.site,
    required this.name,
    this.company,
    this.capital = Money.zero,
    this.format = const FormatId(0),
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 9;

  final SiteId site;
  final String name;
  final CompanyId? company;
  final Money capital;

  /// What kind of business to open.
  final FormatId format;

  /// What to borrow towards it, if anything, and over how many months.
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(site.index)
      ..writeString(name)
      ..writeNullableInt(company?.index)
      ..writeInt(capital.cents)
      ..writeInt(format.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'OpenStore(actor: ${actor.index}, site: ${site.index}, name: $name, '
      'company: ${company?.index}, capital: ${capital.toDecimalString()}, '
      'format: ${format.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths)';
}

/// Closes a store for good: its stock is written off and its site is freed.
final class CloseStore extends Command {
  const CloseStore(super.actor, {required this.store});

  static const int tag = 10;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'CloseStore(actor: ${actor.index}, store: ${store.index})';
}

/// Sets a store's staff for each slot of the day; a slot without staff is
/// closed. Staff are paid for every day they are rostered.
final class SetStaffing extends Command {
  const SetStaffing(super.actor, {required this.store, required this.staff});

  static const int tag = 11;

  final StoreId store;

  /// Indexed by slot of the day: morning, midday, evening, night.
  final List<int> staff;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(staff.length);
    staff.forEach(writer.writeInt);
  }

  @override
  String toString() =>
      'SetStaffing(actor: ${actor.index}, store: ${store.index}, '
      'staff: [${staff.join(', ')}])';
}

/// Buys a study of a market for one of the actor's companies: estimates of
/// its households and of each store's share of sales, as accurate as the
/// [tier] paid for.
final class BuyResearch extends Command {
  const BuyResearch(
    super.actor, {
    required this.company,
    required this.market,
    required this.tier,
  });

  static const int tag = 12;

  final CompanyId company;
  final MarketId market;
  final ResearchTierId tier;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(market.index)
      ..writeInt(tier.index);
  }

  @override
  String toString() =>
      'BuyResearch(actor: ${actor.index}, company: ${company.index}, '
      'market: ${market.index}, tier: ${tier.index})';
}

/// Puts a manager of [grade] in charge of a store's [duties], following
/// [strategy]; or, for the manager already there, changes the brief. A new
/// grade replaces the manager. Managers are paid daily, like staff.
final class HireManager extends Command {
  const HireManager(
    super.actor, {
    required this.store,
    required this.grade,
    required this.strategy,
    required this.duties,
  });

  static const int tag = 13;

  final StoreId store;
  final ManagerGradeId grade;
  final StrategyId strategy;

  /// Indexed by duty: ordering, pricing, assortment, staffing.
  final List<bool> duties;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(duties.length);
    duties.forEach(writer.writeBool);
  }

  @override
  String toString() =>
      'HireManager(actor: ${actor.index}, store: ${store.index}, '
      'grade: ${grade.index}, strategy: ${strategy.index}, '
      'duties: [${duties.join(', ')}])';
}

/// Lets a store's manager go; the owner runs it again.
final class FireManager extends Command {
  const FireManager(super.actor, {required this.store});

  static const int tag = 14;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'FireManager(actor: ${actor.index}, store: ${store.index})';
}

/// Enlarges a store by one step of floor area, paid now. The works take some
/// days, during which the store keeps trading; then it has more shelf slots
/// and storage, draws more shoppers, and pays more rent.
final class ExpandStore extends Command {
  const ExpandStore(super.actor, {required this.store});

  static const int tag = 15;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'ExpandStore(actor: ${actor.index}, store: ${store.index})';
}

/// Gives a store a new name, which everyone sees.
final class RenameStore extends Command {
  const RenameStore(super.actor, {required this.store, required this.name});

  static const int tag = 16;

  final StoreId store;
  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeString(name);
  }

  @override
  String toString() =>
      'RenameStore(actor: ${actor.index}, store: ${store.index}, name: $name)';
}

/// Gives a company a new name, which everyone sees.
final class RenameCompany extends Command {
  const RenameCompany(super.actor, {required this.company, required this.name});

  static const int tag = 17;

  final CompanyId company;
  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeString(name);
  }

  @override
  String toString() =>
      'RenameCompany(actor: ${actor.index}, company: ${company.index}, '
      'name: $name)';
}

/// Sets how many days of wages a company keeps in its cash cushion.
final class SetCushion extends Command {
  const SetCushion(super.actor, {required this.company, required this.days});

  static const int tag = 23;

  final CompanyId company;
  final int days;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(days);
  }

  @override
  String toString() =>
      'SetCushion(actor: ${actor.index}, company: ${company.index}, '
      'days: $days)';
}

/// Puts a director of [grade] in charge of a company (see `Director`); or,
/// for the director already there, changes the brief. A new grade replaces
/// the director. Directors are paid daily, like managers.
final class HireDirector extends Command {
  const HireDirector(
    super.actor, {
    required this.company,
    required this.grade,
    required this.strategy,
    required this.managerGrade,
    required this.growth,
    required this.payout,
    this.borrows = false,
  });

  static const int tag = 24;

  final CompanyId company;
  final DirectorGradeId grade;
  final StrategyId strategy;
  final ManagerGradeId managerGrade;
  final Growth growth;
  final bool payout;

  /// Whether they may borrow to grow, on the company's earnings.
  final bool borrows;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(managerGrade.index)
      ..writeInt(growth.index)
      ..writeBool(payout)
      ..writeBool(borrows);
  }

  @override
  String toString() =>
      'HireDirector(actor: ${actor.index}, company: ${company.index}, '
      'grade: ${grade.index}, strategy: ${strategy.index}, '
      'managerGrade: ${managerGrade.index}, growth: ${growth.name}, '
      'payout: $payout, borrows: $borrows)';
}

/// Lets a company's director go; the owner runs it again, and its store
/// managers stay.
final class FireDirector extends Command {
  const FireDirector(super.actor, {required this.company});

  static const int tag = 25;

  final CompanyId company;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index);
  }

  @override
  String toString() =>
      'FireDirector(actor: ${actor.index}, company: ${company.index})';
}

/// Sets the share of its recent sales a store spends on marketing each day.
final class SetMarketing extends Command {
  const SetMarketing(super.actor, {required this.store, required this.share});

  static const int tag = 18;

  final StoreId store;
  final Fx share;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(share.raw);
  }

  @override
  String toString() =>
      'SetMarketing(actor: ${actor.index}, store: ${store.index}, '
      'share: ${share.toDecimalString()})';
}

/// Turns a store into another format of its channel, a convenience store
/// into a supermarket: paid at once, and the store keeps trading through the
/// works, enlarged to the format's least area if need be.
final class ConvertStore extends Command {
  const ConvertStore(super.actor, {required this.store, required this.format});

  static const int tag = 19;

  final StoreId store;
  final FormatId format;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(format.index);
  }

  @override
  String toString() =>
      'ConvertStore(actor: ${actor.index}, store: ${store.index}, '
      'format: ${format.index})';
}

/// Buys another owner's store at its asking price, paid by the actor's
/// [company]: the store keeps its stock, staff, prices and shoppers, and
/// orders on their way go with it. The player's stores are sold only when
/// the player says so. The company may [borrow] towards it, repaid over
/// [termMonths], with the store's own earnings counted (see `splitLoan`);
/// if the bank won't lend, nothing happens.
final class BuyStore extends Command {
  const BuyStore(
    super.actor, {
    required this.store,
    required this.company,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 20;

  final StoreId store;

  /// The actor's company that pays for it and runs it from now on.
  final CompanyId company;

  /// What to borrow towards it, if anything, and over how many months.
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(company.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'BuyStore(actor: ${actor.index}, store: ${store.index}, '
      'company: ${company.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths)';
}

/// Sells one of the actor's stores at its asking price to the AI owner of
/// its format best able to pay.
final class SellStore extends Command {
  const SellStore(super.actor, {required this.store});

  static const int tag = 21;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'SellStore(actor: ${actor.index}, store: ${store.index})';
}

/// Buys a whole company from its owner at its asking price, paid from the
/// actor's personal cash: its stores, cash and debts come with it. The
/// company itself may [borrow] part of the price on its own earnings,
/// repaid over [termMonths], so the buyer pays only the rest; if the bank
/// won't lend, nothing happens.
final class BuyCompany extends Command {
  const BuyCompany(
    super.actor, {
    required this.company,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 22;

  final CompanyId company;

  /// What the company borrows towards its price, and over how many months.
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'BuyCompany(actor: ${actor.index}, company: ${company.index}, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths)';
}
