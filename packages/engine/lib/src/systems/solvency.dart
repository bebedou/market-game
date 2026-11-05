import '../accounting/ledger.dart';
import '../commands/transfers.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/entities.dart';
import '../state/world_state.dart';
import 'closure.dart';
import 'events.dart';
import 'settlement.dart';
import 'tick_system.dart';

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

/// Winds up [company]. Its stores are sold at their asking prices to
/// whoever can buy them, or else close, and its loans fall due at once.
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
          : Money(checkedSafe(payable.amount.cents * cash.cents) ~/ owed.cents),
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
      if (payable.creditorAccount == AccountKind.loans) {
        ledger.post(
          creditor,
          debit: AccountKind.writeOffs,
          credit: AccountKind.loans,
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
  final surplus = company.accounts[AccountKind.cash];
  final returned = surplus < company.injected ? surplus : company.injected;
  if (returned > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.equity,
      payee: owner,
      payeeAccount: AccountKind.investments,
      amount: returned,
      reason: EntryReason.liquidation,
    );
  }
  if (surplus > returned) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.dividends,
      payee: owner,
      payeeAccount: AccountKind.dividends,
      amount: surplus - returned,
      reason: EntryReason.liquidation,
    );
  }
  final lost = company.injected - returned;
  if (lost > Money.zero) {
    ledger.post(
      owner,
      debit: AccountKind.writeOffs,
      credit: AccountKind.investments,
      amount: lost,
      reason: EntryReason.liquidation,
    );
  }
  company
    ..injected = Money.zero
    ..status = CompanyStatus.liquidated;
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
