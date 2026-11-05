import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/money.dart';

/// Something notable that happened during a step without a journal entry of
/// its own.
sealed class TickEvent {
  const TickEvent();
}

enum RefusalReason { storageFull, notListed }

/// Delivered units the store couldn't take. They go back to the supplier and
/// aren't invoiced.
final class DeliveryRefused extends TickEvent {
  const DeliveryRefused({
    required this.order,
    required this.store,
    required this.product,
    required this.units,
    required this.reason,
  });

  final int order;
  final StoreId store;
  final ProductId product;
  final int units;
  final RefusalReason reason;
}

/// A bill that is due but couldn't be paid for lack of cash. Payment is
/// retried every day until the company pays or is liquidated.
final class PaymentOverdue extends TickEvent {
  const PaymentOverdue({
    required this.company,
    required this.creditor,
    required this.reason,
    required this.amount,
    required this.due,
  });

  final CompanyId company;
  final PartyRef creditor;
  final EntryReason reason;
  final Money amount;
  final Day due;
}

/// A market's yearly census: [households] counted, against [previous] at
/// the last one.
final class CensusTaken extends TickEvent {
  const CensusTaken({
    required this.market,
    required this.households,
    required this.previous,
  });

  final MarketId market;
  final int households;
  final int previous;
}

/// A company wound up for unpaid bills. Of the [owed] total, creditors were
/// [paid] from its cash, guarantors paid [guaranteed], and [writtenOff] was
/// lost.
final class CompanyLiquidated extends TickEvent {
  const CompanyLiquidated({
    required this.company,
    required this.owner,
    required this.owed,
    required this.paid,
    required this.guaranteed,
    required this.writtenOff,
  });

  final CompanyId company;
  final PersonId owner;
  final Money owed;
  final Money paid;
  final Money guaranteed;
  final Money writtenOff;
}

/// A store sold by a company being wound up, to [buyer].
final class StoreSold extends TickEvent {
  const StoreSold({
    required this.store,
    required this.seller,
    required this.buyer,
  });

  final StoreId store;
  final CompanyId seller;
  final CompanyId buyer;
}
