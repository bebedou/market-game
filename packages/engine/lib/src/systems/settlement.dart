import '../accounting/ledger.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../state/entities.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'tick_system.dart';

/// The settlement phase. Every day, staff wages are billed; on the first of
/// each month, rent, overheads and loan installments too. Then every bill that is due
/// is paid, oldest first, as far as each company's cash allows. Unpaid bills stay due and
/// are retried daily; the solvency phase deals with those overdue too long.
final class SettlementSystem implements TickSystem {
  const SettlementSystem();

  @override
  void run(WorldState world, TickContext context) {
    _billWages(world, context);
    _billMarketing(world, context);
    if (context.day.isFirstOfMonth) {
      _billRent(world, context);
      for (final loan in world.loans) {
        if (loan.accruedTo < context.day) {
          billInstallment(world, context.ledger, loan);
        }
      }
      world.loans.removeWhere((loan) => loan.outstanding == Money.zero);
    }
    for (final company in world.companies) {
      if (company.isActive) _payDue(world, context, company);
    }
  }

  /// Each store spends its share of its recent daily sales on marketing,
  /// paid to the services, and its goodwill wears off by the decay rate
  /// and grows by what it spent (Nerlove and Arrow's goodwill stock).
  void _billMarketing(WorldState world, TickContext context) {
    final decay = context.content.demand.goodwillDecay;
    for (final store in world.stores) {
      final company = world.companies[store.company.index];
      var spend = Money.zero;
      if (store.isTrading &&
          company.isActive &&
          store.marketingShare > Fx.zero) {
        spend = store.recentDailySales(context.day).times(store.marketingShare);
      }
      if (spend > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.marketing,
          Payable(
            creditor: world.services.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.marketing,
            amount: spend,
            due: context.day,
            store: store.id,
          ),
        );
      }
      store.goodwill = store.goodwill - store.goodwill.times(decay) + spend;
    }
  }

  /// Each trading store's rent, to the landlords, and its format's
  /// overheads for its floor area, to the services.
  void _billRent(WorldState world, TickContext context) {
    final level = world.macro.priceIndex;
    for (final store in world.stores) {
      final company = world.companies[store.company.index];
      if (!store.isTrading || !company.isActive) continue;
      final rent = context.content.sites[store.site.index]
          .rentFor(store.area)
          .times(level);
      if (rent > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.rent,
          Payable(
            creditor: world.landlords.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.rent,
            amount: rent,
            due: context.day,
            store: store.id,
          ),
        );
      }
      final overheads = context.content.formats[store.format.index]
          .overheadsFor(store.area)
          .times(level);
      if (overheads > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.overheads,
          Payable(
            creditor: world.services.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.overheads,
            amount: overheads,
            due: context.day,
            store: store.id,
          ),
        );
      }
    }
  }

  /// Staff and managers are paid daily, at the wage index, to the market's
  /// households; a director at the national wage index, to the households
  /// of the market of the company's first store still trading.
  void _billWages(WorldState world, TickContext context) {
    for (final company in world.companies) {
      final director = company.director;
      if (director == null || !company.isActive) continue;
      final salary = context.content.directors!.grades[director.grade.index]
          .salary
          .times(world.macro.wageIndex);
      final home = world.stores
          .where((store) => store.company == company.id && store.isTrading)
          .firstOrNull;
      if (home == null || salary == Money.zero) continue;
      bill(
        context.ledger,
        company,
        AccountKind.salaries,
        Payable(
          creditor: world.households[home.market.index].partyRef,
          creditorAccount: AccountKind.salaries,
          reason: EntryReason.salary,
          amount: salary,
          due: context.day,
        ),
      );
    }
    for (final store in world.stores) {
      final level =
          world.macro.wageIndex *
          context.content.markets[store.market.index].wageLevel;
      final slotWage = context.content.operations.slotWage
          .times(level)
          .times(context.content.formats[store.format.index].wageFactor);
      final company = world.companies[store.company.index];
      if (!store.isTrading || !company.isActive) continue;
      final households = world.households[store.market.index].partyRef;
      final wages = slotWage.timesInt(
        store.staff.fold(0, (sum, count) => sum + count),
      );
      if (wages > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.wages,
          Payable(
            creditor: households,
            creditorAccount: AccountKind.wages,
            reason: EntryReason.wages,
            amount: wages,
            due: context.day,
            store: store.id,
          ),
        );
      }
      if (store.manager case final manager?) {
        final grade = context.content.managers.grades[manager.grade.index];
        final salary = grade.salary.times(level);
        if (salary == Money.zero) continue;
        bill(
          context.ledger,
          company,
          AccountKind.salaries,
          Payable(
            creditor: households,
            creditorAccount: AccountKind.salaries,
            reason: EntryReason.salary,
            amount: salary,
            due: context.day,
            store: store.id,
          ),
        );
      }
    }
  }

  void _payDue(WorldState world, TickContext context, Company company) {
    final payables = company.payables;
    final order = [for (var i = 0; i < payables.length; i++) i]
      ..sort((a, b) {
        final byDue = payables[a].due.number.compareTo(payables[b].due.number);
        return byDue != 0 ? byDue : a - b;
      });
    final paid = <int>{};
    for (final i in order) {
      final payable = payables[i];
      if (payable.due > context.day) continue;
      if (company.accounts[AccountKind.cash] >= payable.amount) {
        context.ledger.pay(
          payer: company,
          payerAccount: AccountKind.payables,
          payee: world.party(payable.creditor),
          payeeAccount: payable.creditorAccount,
          amount: payable.amount,
          reason: payable.reason,
          store: payable.store,
        );
        paid.add(i);
      } else {
        context.events.add(
          PaymentOverdue(
            company: company.id,
            creditor: payable.creditor,
            reason: payable.reason,
            amount: payable.amount,
            due: payable.due,
          ),
        );
      }
    }
    final unpaid = [
      for (var i = 0; i < payables.length; i++)
        if (!paid.contains(i)) payables[i],
    ];
    payables
      ..clear()
      ..addAll(unpaid);
  }
}

/// Bills [company] for [payable], booking it as [expense] (or, for loan
/// principal, as a reduction of the loan).
void bill(
  Ledger ledger,
  Company company,
  AccountKind expense,
  Payable payable,
) {
  ledger.post(
    company,
    debit: expense,
    credit: AccountKind.payables,
    amount: payable.amount,
    reason: payable.reason,
    store: payable.store,
  );
  company.payables.add(payable);
}

/// Bills the interest [loan] has accrued up to today and one installment of
/// principal, or with [all], every installment left.
void billInstallment(
  WorldState world,
  Ledger ledger,
  Loan loan, {
  bool all = false,
}) {
  final company = world.companies[loan.company.index];
  final interest = loan.interestTo(ledger.day);
  loan.accruedTo = ledger.day;
  if (interest > Money.zero) {
    bill(
      ledger,
      company,
      AccountKind.interest,
      Payable(
        creditor: world.bank.partyRef,
        creditorAccount: AccountKind.revenue,
        reason: EntryReason.interest,
        amount: interest,
        due: ledger.day,
        loan: loan.number,
      ),
    );
  }
  final principal = all || loan.installmentsLeft <= 1
      ? loan.outstanding
      : Money(loan.outstanding.cents ~/ loan.installmentsLeft);
  if (principal > Money.zero) {
    bill(
      ledger,
      company,
      AccountKind.loans,
      Payable(
        creditor: world.bank.partyRef,
        creditorAccount: AccountKind.loans,
        reason: EntryReason.loanRepayment,
        amount: principal,
        due: ledger.day,
        loan: loan.number,
      ),
    );
  }
  loan
    ..outstanding -= principal
    ..installmentsLeft = all || loan.installmentsLeft <= 1
        ? 0
        : loan.installmentsLeft - 1;
}
