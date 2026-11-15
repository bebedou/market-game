import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
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

/// A factory's lab launched [product]'s next [generation]: it gained
/// [gain] in quality, which leaves it [lead] over the market's standard,
/// and its materials now cost [saving] less than at the start.
final class GenerationLaunched extends TickEvent {
  const GenerationLaunched({
    required this.factory,
    required this.company,
    required this.product,
    required this.generation,
    required this.gain,
    required this.lead,
    required this.saving,
  });

  final FactoryId factory;
  final CompanyId company;
  final ProductId product;
  final int generation;
  final Fx gain;
  final Fx lead;
  final Fx saving;
}

/// A software company's first version went on sale.
final class SoftwareLaunched extends TickEvent {
  const SoftwareLaunched({required this.software, required this.company});

  final SoftwareId software;
  final CompanyId company;
}

/// A rival offered to buy a software company whole.
final class SoftwareOfferMade extends TickEvent {
  const SoftwareOfferMade({
    required this.software,
    required this.company,
    required this.rival,
    required this.price,
  });

  final SoftwareId software;
  final CompanyId company;
  final SoftwareRivalId rival;
  final Money price;
}

/// A rival that started up put its first version on sale.
final class RivalLaunched extends TickEvent {
  const RivalLaunched({required this.rival});

  final SoftwareRivalId rival;
}

/// A chain opened a tender for a product the player's factories make.
final class TenderOpened extends TickEvent {
  const TenderOpened({required this.number});

  final int number;
}

/// A tender the player bid on closed, won or lost.
final class TenderClosed extends TickEvent {
  const TenderClosed({required this.number, required this.won});

  final int number;
  final bool won;
}

/// A rival that started up gave up, its customers gone elsewhere.
final class RivalFolded extends TickEvent {
  const RivalFolded({required this.rival});

  final SoftwareRivalId rival;
}
