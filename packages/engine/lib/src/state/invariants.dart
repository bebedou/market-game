import '../accounting/ledger.dart';
import '../core/fx.dart';
import '../core/money.dart';
import 'store.dart';
import 'world_state.dart';

/// Accounting, stock and household rules that must hold after every step.
/// Returns one description per violation; empty when the world is consistent.
List<String> invariantViolations(WorldState world) {
  final violations = <String>[];
  var totalCash = Money.zero;
  for (final party in world.parties) {
    final (:type, :index) = party.partyRef;
    if (party.accounts.total != Money.zero) {
      violations.add(
        '${type.name} $index: books are off by '
        '${party.accounts.total.toDecimalString()}',
      );
    }
    totalCash += party.accounts[AccountKind.cash];
  }
  if (totalCash != world.moneySupply) {
    violations.add(
      'total cash ${totalCash.toDecimalString()} differs from the money '
      'supply ${world.moneySupply.toDecimalString()}',
    );
  }

  for (final company in world.companies) {
    var stockValue = Money.zero;
    for (final store in world.stores.where((s) => s.company == company.id)) {
      final where = 'store ${store.id.index}';
      if (store.listedProducts > store.shelfSlots) {
        violations.add('$where lists more products than it has slots');
      }
      if (store.unitsOnHand > store.storageUnits) {
        violations.add('$where holds more units than its storage');
      }
      for (final (product, stock) in store.stock.indexed) {
        if (stock.units > 0 && store.prices[product] == null) {
          violations.add('$where has stock of unlisted product $product');
        }
        if (stock.lots.any((lot) => lot.quantity <= 0)) {
          violations.add('$where has an empty lot of product $product');
        }
        stockValue += stock.value;
      }
    }
    final where = 'company ${company.id.index}';
    if (company.accounts[AccountKind.inventory] != stockValue) {
      violations.add(
        '$where: inventory account '
        '${company.accounts[AccountKind.inventory].toDecimalString()} '
        'differs from stock at cost ${stockValue.toDecimalString()}',
      );
    }
    final owed = company.payables.fold(
      Money.zero,
      (sum, payable) => sum + payable.amount,
    );
    if (-company.accounts[AccountKind.payables] != owed) {
      violations.add(
        '$where: payables account differs from unpaid bills '
        '${owed.toDecimalString()}',
      );
    }
    final borrowed = world.loans
        .where((loan) => loan.company == company.id)
        .fold(Money.zero, (sum, loan) => sum + loan.outstanding);
    if (-company.accounts[AccountKind.loans] != borrowed) {
      violations.add(
        '$where: loans account differs from loans outstanding '
        '${borrowed.toDecimalString()}',
      );
    }
    if (!company.isActive &&
        (company.accounts[AccountKind.cash] != Money.zero ||
            company.payables.isNotEmpty)) {
      violations.add('$where is liquidated but holds cash or owes bills');
    }
  }

  var lent = Money.zero;
  for (final loan in world.loans) {
    lent += loan.outstanding;
  }
  for (final company in world.companies) {
    for (final payable in company.payables) {
      if (payable.creditorAccount == AccountKind.loans) lent += payable.amount;
    }
  }
  if (world.bank.accounts[AccountKind.loans] != lent) {
    violations.add(
      'the bank\'s loans account differs from principal still owed '
      '${lent.toDecimalString()}',
    );
  }
  for (final person in world.persons) {
    if (person.accounts[AccountKind.cash].isNegative) {
      violations.add('person ${person.id.index} has negative cash');
    }
  }
  for (final store in world.stores) {
    if (store.status == StoreStatus.closed &&
        (store.unitsOnHand > 0 || store.listedProducts > 0)) {
      violations.add('closed store ${store.id.index} still has stock');
    }
  }

  for (final cohort in world.cohorts) {
    final where = 'cohort ${cohort.id.index}';
    if (cohort.needs.any((need) => need.isNegative)) {
      violations.add('$where has a negative need');
    }
    if (cohort.loyalty.any((value) => value.isNegative || value > Fx.one)) {
      violations.add('$where has loyalty outside 0 to 1');
    }
  }
  return violations;
}
