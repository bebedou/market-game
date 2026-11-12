import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// The first format whose orders may come from factories.
const factoriesVersion = 28;

/// One product on a purchase order, at the price fixed when it was placed.
/// On a factory's order, [made] of the units come from the factory and the
/// rest from [from], the wholesaler whose price it charges.
final class OrderLine {
  const OrderLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.made = 0,
    this.from,
  });

  OrderLine.read(StateReader reader)
    : product = ProductId(reader.readInt()),
      quantity = reader.readInt(),
      unitPrice = Money(reader.readInt()),
      made = reader.version >= factoriesVersion ? reader.readInt() : 0,
      from = reader.version >= factoriesVersion
          ? switch (reader.readNullableInt()) {
              final index? => SupplierId(index),
              null => null,
            }
          : null;

  final ProductId product;
  final int quantity;
  final Money unitPrice;

  /// Units a factory makes; the others are bought from [from].
  final int made;

  /// On a factory's order, the wholesaler whose price is charged and who
  /// delivers what the factory doesn't make.
  final SupplierId? from;

  void write(StateWriter writer) {
    writer
      ..writeInt(product.index)
      ..writeInt(quantity)
      ..writeInt(unitPrice.cents)
      ..writeInt(made)
      ..writeNullableInt(from?.index);
  }
}

/// An order on its way to a store.
final class PurchaseOrder {
  const PurchaseOrder({
    required this.number,
    required this.store,
    required this.supplier,
    required this.arrival,
    required this.lines,
    this.factory,
  });

  PurchaseOrder.read(StateReader reader)
    : number = reader.readInt(),
      store = StoreId(reader.readInt()),
      supplier = SupplierId(reader.readInt()),
      arrival = Day(reader.readInt()),
      lines = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          OrderLine.read(reader),
      ],
      factory = reader.version >= factoriesVersion
          ? switch (reader.readNullableInt()) {
              final index? => FactoryId(index),
              null => null,
            }
          : null;

  /// Order numbers count up from 1 across the whole world.
  final int number;
  final StoreId store;

  /// The wholesaler, or on a factory's order the first line's [OrderLine.from].
  final SupplierId supplier;
  final Day arrival;
  final List<OrderLine> lines;

  /// The factory it was ordered from, if any.
  final FactoryId? factory;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(store.index)
      ..writeInt(supplier.index)
      ..writeInt(arrival.number)
      ..writeInt(lines.length);
    for (final line in lines) {
      line.write(writer);
    }
    writer.writeNullableInt(factory?.index);
  }
}

/// A bill a company owes: a supplier invoice, rent, or part of a loan
/// installment.
final class Payable {
  const Payable({
    required this.creditor,
    required this.creditorAccount,
    required this.reason,
    required this.amount,
    required this.due,
    this.order,
    this.loan,
    this.store,
    this.factory,
  });

  Payable.read(StateReader reader)
    : creditor = (
        type: PartyType.values[reader.readInt()],
        index: reader.readInt(),
      ),
      creditorAccount = AccountKind.values[reader.readInt()],
      reason = EntryReason.values[reader.readInt()],
      amount = Money(reader.readInt()),
      due = Day(reader.readInt()),
      order = reader.readNullableInt(),
      loan = reader.readNullableInt(),
      store = switch (reader.readNullableInt()) {
        final index? => StoreId(index),
        null => null,
      },
      factory = reader.version >= factoriesVersion
          ? switch (reader.readNullableInt()) {
              final index? => FactoryId(index),
              null => null,
            }
          : null;

  final PartyRef creditor;

  /// What the creditor credits when paid: revenue, the loan itself for
  /// loan principal, or for a factory's company what it was owed.
  final AccountKind creditorAccount;
  final EntryReason reason;
  final Money amount;
  final Day due;

  /// The purchase order number, for supplier invoices.
  final int? order;

  /// The loan number, for installments.
  final int? loan;

  /// The store, for rent.
  final StoreId? store;

  /// The factory, for its staff and site.
  final FactoryId? factory;

  void write(StateWriter writer) {
    writer
      ..writeInt(creditor.type.index)
      ..writeInt(creditor.index)
      ..writeInt(creditorAccount.index)
      ..writeInt(reason.index)
      ..writeInt(amount.cents)
      ..writeInt(due.number)
      ..writeNullableInt(order)
      ..writeNullableInt(loan)
      ..writeNullableInt(store?.index)
      ..writeNullableInt(factory?.index);
  }
}

/// A bank loan, repaid in monthly installments of equal principal plus the
/// interest accrued, billed on the first of each month.
final class Loan {
  Loan({
    required this.number,
    required this.company,
    required this.principal,
    required this.outstanding,
    required this.rate,
    required this.installmentsLeft,
    required this.guarantor,
    required this.accruedTo,
  });

  Loan.read(StateReader reader)
    : number = reader.readInt(),
      company = CompanyId(reader.readInt()),
      principal = Money(reader.readInt()),
      outstanding = Money(reader.readInt()),
      rate = Fx.raw(reader.readInt()),
      installmentsLeft = reader.readInt(),
      guarantor = switch (reader.readNullableInt()) {
        final index? => PersonId(index),
        null => null,
      },
      accruedTo = Day(reader.readInt());

  /// Loan numbers count up from 1 across the whole world.
  final int number;
  final CompanyId company;

  /// The amount borrowed.
  final Money principal;

  /// Principal not yet billed.
  Money outstanding;

  /// Annual interest rate.
  final Fx rate;
  int installmentsLeft;

  /// The person who answers for the loan if the company fails, if any.
  /// Who answers for the loan if the company can't, if anyone; whoever
  /// buys the company takes it over.
  PersonId? guarantor;

  /// Interest has been billed up to this day.
  Day accruedTo;

  /// Interest on [outstanding] from [accruedTo] to [day].
  Money interestTo(Day day) => Money(
    mulDivRound(
      outstanding.cents,
      rate.raw * (day.number - accruedTo.number),
      Fx.scale * 365,
    ),
  );

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(company.index)
      ..writeInt(principal.cents)
      ..writeInt(outstanding.cents)
      ..writeInt(rate.raw)
      ..writeInt(installmentsLeft)
      ..writeNullableInt(guarantor?.index)
      ..writeInt(accruedTo.number);
  }
}
