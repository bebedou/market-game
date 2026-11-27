import '../accounting/ledger.dart';
import '../commands/apply_command.dart' show holderOf;
import '../commands/transfers.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/districts.dart'
    show monthsSinceStart, sitesOf, valueSleepingShop;
import '../state/entities.dart';
import '../state/factory.dart';
import '../state/fixed_assets.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'closure.dart';
import 'events.dart';
import 'settlement.dart';
import 'tick_system.dart';
import '../state/software_rules.dart' show payInvestors;

/// The solvency phase: a company with a bill overdue for more than the grace
/// period is liquidated.
final class SolvencySystem implements TickSystem {
  const SolvencySystem();

  @override
  void run(WorldState world, TickContext context) {
    final grace = context.content.finance.graceDays;
    for (final company in world.companies) {
      if (!company.isActive) continue;
      final overdue = company.payables.any(
        (payable) => payable.due.number + grace < context.day.number,
      );
      if (overdue) liquidate(world, context, company);
    }
  }
}

/// Hands [company]'s shops in districts run by formula to their
/// shopkeepers, for what each is worth, paid by everyone beyond the
/// districts played in full, as a business sold does; otherwise they would
/// go on booking their months to a company wound up.
void _sellSleepingShops(
  WorldState world,
  TickContext context,
  Company company,
) {
  final content = context.content;
  final month = monthsSinceStart(content, world.today);
  for (final sleeper in world.sleepers) {
    for (final shop in sleeper.shops) {
      if (shop.company != company.id) continue;
      final price =
          valueSleepingShop(
            world,
            content,
            sitesOf(world, content, sleeper)[shop.site],
            shop,
            month,
            country: content.neighbourhoods[sleeper.row].country,
          )?.price ??
          Money.zero;
      if (price > Money.zero) {
        context.ledger.pay(
          payer: world.elsewhere,
          payerAccount: AccountKind.spending,
          payee: company,
          payeeAccount: AccountKind.disposals,
          amount: price,
          reason: EntryReason.storeSale,
        );
      }
      sellFixed(context.ledger, company, shop.fittings);
      shop
        ..company = null
        ..brand = null
        ..acquiredMonth = month
        ..fittings = Money.zero;
    }
  }
}

/// Winds up [company]. Its stores are sold at their asking prices to
/// whoever can buy them, or else close, its shops in districts run by
/// formula pass to their shopkeepers for what they are worth, and its loans
/// fall due at once.
/// Creditors share its cash in proportion to what they are owed; guarantors
/// answer for what is left of guaranteed loans, as far as their cash goes;
/// the rest is written off. The owner loses the capital put in and the bank
/// remembers the bankruptcy.
void liquidate(WorldState world, TickContext context, Company company) {
  final ledger = context.ledger;
  for (final store in world.stores) {
    if (store.company != company.id || !store.isTrading) continue;
    final buyer = sellToBestBuyer(world, context.content, ledger, store);
    if (buyer == null) {
      closeStore(world, ledger, store);
    } else {
      context.events.add(
        StoreSold(store: store.id, seller: company.id, buyer: buyer.id),
      );
    }
  }
  for (final factory in world.factories) {
    if (factory.company != company.id) continue;
    writeOffFixed(ledger, company, factory.book, factory: factory.id);
    factory
      ..status = FactoryStatus.closed
      ..book = Money.zero;
  }
  // Its shops run by formula close with it.
  if (world.national case final national?) {
    for (final country in national.countries) {
      for (final block in country.blocks) {
        if (block.company != company.id.index) continue;
        writeOffFixed(ledger, company, block.fittings);
        block.fittings = Money.zero;
      }
    }
    national.closeCompany(company.id.index);
  }
  _sellSleepingShops(world, context, company);
  _collectReceivables(world, ledger, company);
  final guarantors = <int, Person>{};
  for (final loan in world.loans) {
    if (loan.company != company.id) continue;
    if (loan.guarantor case final guarantor?) {
      guarantors[loan.number] = world.persons[guarantor.index];
    }
    billInstallment(world, ledger, loan, all: true);
  }
  world.loans.removeWhere((loan) => loan.company == company.id);

  final payables = company.payables;
  final owed = payables.fold(Money.zero, (sum, p) => sum + p.amount);
  final cash = company.accounts[AccountKind.cash];
  final shares = [
    for (final payable in payables)
      owed <= cash
          ? payable.amount
          : Money(
              mulDivTruncated(payable.amount.cents, cash.cents, owed.cents),
            ),
  ];
  // Rounding leaves a few cents; they go to the first creditors.
  var leftover = owed <= cash
      ? 0
      : (cash - shares.fold(Money.zero, (sum, s) => sum + s)).cents;
  var paid = Money.zero;
  var guaranteed = Money.zero;
  var writtenOff = Money.zero;
  for (final (i, payable) in payables.indexed) {
    var share = shares[i];
    if (leftover > 0 && share < payable.amount) {
      share += const Money(1);
      leftover--;
    }
    final creditor = world.party(payable.creditor);
    if (share > Money.zero) {
      ledger.pay(
        payer: company,
        payerAccount: AccountKind.payables,
        payee: creditor,
        payeeAccount: payable.creditorAccount,
        amount: share,
        reason: EntryReason.liquidation,
        store: payable.store,
      );
      paid += share;
    }
    var unpaid = payable.amount - share;
    final guarantor = guarantors[payable.loan];
    if (guarantor != null && unpaid > Money.zero) {
      final wealth = guarantor.accounts[AccountKind.cash];
      final call = unpaid < wealth ? unpaid : wealth;
      if (call > Money.zero) {
        ledger
          ..pay(
            payer: guarantor,
            payerAccount: AccountKind.writeOffs,
            payee: creditor,
            payeeAccount: payable.creditorAccount,
            amount: call,
            reason: EntryReason.guaranteeCall,
          )
          ..post(
            company,
            debit: AccountKind.payables,
            credit: AccountKind.debtRelief,
            amount: call,
            reason: EntryReason.guaranteeCall,
          );
        guaranteed += call;
        unpaid -= call;
      }
    }
    if (unpaid > Money.zero) {
      ledger.post(
        company,
        debit: AccountKind.payables,
        credit: AccountKind.debtRelief,
        amount: unpaid,
        reason: EntryReason.liquidation,
      );
      if (payable.creditorAccount == AccountKind.loans ||
          payable.creditorAccount == AccountKind.receivables) {
        ledger.post(
          creditor,
          debit: AccountKind.writeOffs,
          credit: payable.creditorAccount,
          amount: unpaid,
          reason: EntryReason.liquidation,
        );
      }
      writtenOff += unpaid;
    }
  }
  payables.clear();

  // What is left after the creditors goes back to the owner, as a return of
  // capital first; whatever capital isn't returned is lost.
  final owner = world.persons[company.owner.index];
  // A subsidiary's surplus goes to its parent, which bears what it lost.
  final holder = holderOf(world, company);
  // Outside investors in a software company take their share first.
  payInvestors(
    world,
    ledger,
    company.id,
    company.accounts[AccountKind.cash],
    AccountKind.dividends,
    EntryReason.liquidation,
  );
  final surplus = company.accounts[AccountKind.cash];
  final returned = surplus < company.injected ? surplus : company.injected;
  if (returned > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.equity,
      payee: holder,
      payeeAccount: AccountKind.investments,
      amount: returned,
      reason: EntryReason.liquidation,
    );
  }
  if (surplus > returned) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.dividends,
      payee: holder,
      payeeAccount: company.parent == null
          ? AccountKind.dividends
          : AccountKind.disposals,
      amount: surplus - returned,
      reason: EntryReason.liquidation,
    );
  }
  final lost = company.injected - returned;
  if (lost > Money.zero) {
    ledger.post(
      holder,
      debit: AccountKind.writeOffs,
      credit: AccountKind.investments,
      amount: lost,
      reason: EntryReason.liquidation,
    );
  }
  company
    ..injected = Money.zero
    ..status = CompanyStatus.liquidated;
  // Its own subsidiaries go up to whoever held it.
  for (final other in world.companies) {
    if (other.parent == company.id) other.parent = company.parent;
  }
  owner
    ..bankruptcies += 1
    ..lastBankruptcy = context.day;
  context.events.add(
    CompanyLiquidated(
      company: company.id,
      owner: owner.id,
      owed: owed,
      paid: paid,
      guaranteed: guaranteed,
      writtenOff: writtenOff,
    ),
  );
}

/// Collects what other companies owe [company]'s factories before it is
/// wound up: each pays now what its cash allows, and the rest is forgiven.
void _collectReceivables(WorldState world, Ledger ledger, Company company) {
  final ref = company.partyRef;
  for (final debtor in world.companies) {
    if (debtor.id == company.id || !debtor.isActive) continue;
    final kept = <Payable>[];
    for (final payable in debtor.payables) {
      if (payable.creditor != ref) {
        kept.add(payable);
        continue;
      }
      final cash = debtor.accounts[AccountKind.cash];
      final paid = payable.amount < cash ? payable.amount : cash;
      if (paid > Money.zero) {
        ledger.pay(
          payer: debtor,
          payerAccount: AccountKind.payables,
          payee: company,
          payeeAccount: payable.creditorAccount,
          amount: paid,
          reason: EntryReason.liquidation,
        );
      }
      final forgiven = payable.amount - paid;
      if (forgiven > Money.zero) {
        ledger
          ..post(
            debtor,
            debit: AccountKind.payables,
            credit: AccountKind.debtRelief,
            amount: forgiven,
            reason: EntryReason.liquidation,
          )
          ..post(
            company,
            debit: AccountKind.writeOffs,
            credit: payable.creditorAccount,
            amount: forgiven,
            reason: EntryReason.liquidation,
          );
      }
    }
    debtor.payables
      ..clear()
      ..addAll(kept);
  }
}
