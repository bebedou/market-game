import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import 'entities.dart';
import 'valuation.dart';
import 'world_state.dart';

/// A year's earnings of [company]'s stores, each counted as a buyer would
/// (see [storeEarnings]): [values] if given, indexed by [StoreId], else
/// worked out. Stores too new to tell count nothing; losing ones count
/// their losses.
Money companyEarnings(
  WorldState world,
  ContentDb content,
  CompanyId company, {
  List<Valuation?>? values,
}) {
  var total = Money.zero;
  for (final store in world.stores) {
    if (store.company != company || !store.isTrading) continue;
    final earnings =
        values?[store.id.index]?.earnings ??
        storeEarnings(world, content, store);
    if (earnings != null) total += earnings;
  }
  return total;
}

/// What [company]'s earnings carry beyond its loans: up to
/// [FinanceDef.earningsMultiple] times a year of its stores' earnings, less
/// what is left of its unguaranteed loans. Below zero when those loans
/// exceed it.
Money earningsRoom(
  WorldState world,
  ContentDb content,
  Company company, {
  List<Valuation?>? values,
}) {
  var room = companyEarnings(
    world,
    content,
    company.id,
    values: values,
  ).times(content.finance.earningsMultiple);
  for (final loan in world.loans) {
    if (loan.company == company.id && loan.guarantor == null) {
      room -= loan.outstanding;
    }
  }
  return room;
}

/// What the bank still lends [company] without a guarantee: its
/// [earningsRoom] with [extra] earnings of a store it is buying counted
/// too, never below zero.
Money earningsCredit(
  WorldState world,
  ContentDb content,
  Company company, {
  Money extra = Money.zero,
}) {
  final room =
      earningsRoom(world, content, company) +
      extra.times(content.finance.earningsMultiple);
  return room.isNegative ? Money.zero : room;
}

/// What [person] can still guarantee: [FinanceDef.guaranteeMultiple] times
/// their cash, less [spent] of it, less what is left of the loans they
/// already guarantee; never below zero.
Money guaranteeRoom(
  WorldState world,
  ContentDb content,
  Person person, {
  Money spent = Money.zero,
}) {
  var room = (person.accounts[AccountKind.cash] - spent).times(
    content.finance.guaranteeMultiple,
  );
  for (final loan in world.loans) {
    if (loan.guarantor == person.id) room -= loan.outstanding;
  }
  return room.isNegative ? Money.zero : room;
}

/// How the bank lends [amount] for a purchase: on the buyer's earnings,
/// [credit], as far as they go, and the rest on the owner's guarantee,
/// [guarantee]; null if the two together fall short.
({Money unsecured, Money guaranteed})? splitLoan(
  Money amount, {
  required Money credit,
  required Money guarantee,
}) {
  final unsecured = amount < credit ? amount : credit;
  final guaranteed = amount - unsecured;
  if (guaranteed > guarantee) return null;
  return (unsecured: unsecured, guaranteed: guaranteed);
}

/// The yearly rate the bank charges on a new loan [today]: the policy rate,
/// its margin and the spread for a [guaranteed] loan or an unguaranteed
/// one, and more if the owner went bankrupt on [lastBankruptcy], within
/// [FinanceDef.reputationDays].
Fx lendingRate(
  ContentDb content,
  Fx policyRate,
  Day today, {
  required bool guaranteed,
  Day? lastBankruptcy,
}) {
  final finance = content.finance;
  var rate =
      policyRate +
      finance.bankMargin +
      (guaranteed ? finance.guaranteedSpread : finance.unsecuredSpread);
  if (lastBankruptcy != null &&
      today.number - lastBankruptcy.number <= finance.reputationDays) {
    rate += finance.bankruptcySpread;
  }
  return rate;
}
