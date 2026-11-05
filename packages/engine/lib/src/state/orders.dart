import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// One product on a purchase order, at the price fixed when it was placed.
final class OrderLine {
  const OrderLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  OrderLine.read(StateReader reader)
    : product = ProductId(reader.readInt()),
      quantity = reader.readInt(),
      unitPrice = Money(reader.readInt());

  final ProductId product;
  final int quantity;
  final Money unitPrice;

  void write(StateWriter writer) {
    writer
      ..writeInt(product.index)
      ..writeInt(quantity)
      ..writeInt(unitPrice.cents);
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
  });

  PurchaseOrder.read(StateReader reader)
    : number = reader.readInt(),
      store = StoreId(reader.readInt()),
      supplier = SupplierId(reader.readInt()),
      arrival = Day(reader.readInt()),
      lines = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          OrderLine.read(reader),
      ];

  /// Order numbers count up from 1 across the whole world.
  final int number;
  final StoreId store;
  final SupplierId supplier;
  final Day arrival;
  final List<OrderLine> lines;

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
      };

  final PartyRef creditor;

  /// What the creditor credits when paid: revenue, or the loan itself for
  /// loan principal.
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
      ..writeNullableInt(store?.index);
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
