import '../content/content_db.dart';
import '../core/money.dart';
import '../observation/observation.dart';
import '../state/director.dart';
import '../state/store.dart';

/// [store]'s share of its company's cash cushion: [days] of its staff's
/// wages and its manager's salary, and a month's rent and overheads, at
/// today's levels. Nothing for a closed store.
Money storeCushion(
  Observation view,
  ContentDb content,
  StoreView store,
  int days,
) {
  if (store.status == StoreStatus.closed) return Money.zero;
  return dailyStaffCost(view, content, store).timesInt(days) +
      monthlyOccupancy(view, content, store);
}

/// What [store]'s staff and manager are paid a day, at today's wages.
Money dailyStaffCost(Observation view, ContentDb content, StoreView store) {
  final level =
      view.macro.wageIndex * content.markets[store.market.index].wageLevel;
  var daily = content.operations.slotWage
      .times(level)
      .times(content.formats[store.format.index].wageFactor)
      .timesInt(store.staff.fold(0, (sum, count) => sum + count));
  if (store.manager case final manager?) {
    daily += content.managers.grades[manager.grade.index].salary.times(level);
  }
  return daily;
}

/// [store]'s rent and overheads for a month, at today's prices.
Money monthlyOccupancy(Observation view, ContentDb content, StoreView store) =>
    (content.sites[store.site.index].rentFor(store.area) +
            content.formats[store.format.index].overheadsFor(store.area))
        .times(view.macro.priceIndex);

/// What [director] is paid a day, at today's wages.
Money directorSalary(Observation view, ContentDb content, Director director) =>
    content.directors!.grades[director.grade.index].salary.times(
      view.macro.wageIndex,
    );

/// [loan]'s next monthly payment: its share of the principal and about a
/// month's interest.
Money nextInstallment(LoanView loan) {
  final principal = loan.installmentsLeft <= 1
      ? loan.outstanding
      : Money(loan.outstanding.cents ~/ loan.installmentsLeft);
  return principal + Money(loan.outstanding.times(loan.rate).cents ~/ 12);
}

/// The cash [company] keeps for what it must pay soon: each store's share of
/// [CompanyView.cushionDays] (see [storeCushion]), as many days of its
/// director's salary, each loan's next payment and the tax on this year's
/// profit so far. Managers and AI owners order
/// in full only from free cash beyond it; within it, only enough to keep
/// selling, from [cashForEssentials].
Money cashCushion(Observation view, ContentDb content, CompanyView company) {
  var cushion = company.taxAccrued;
  if (company.director case final director?) {
    cushion += directorSalary(view, content, director).timesInt(
      company.cushionDays,
    );
  }
  for (final store in company.stores) {
    cushion += storeCushion(view, content, store, company.cushionDays);
  }
  for (final loan in company.loans) {
    cushion += nextInstallment(loan);
  }
  return cushion;
}

/// What [company] may spend on just enough stock to keep selling: its cash
/// less the bills already due and the orders on their way. Bills due later,
/// a tax bill or a supplier's terms, are left to the sales that stock
/// brings in, since a store with empty shelves can't pay them either.
Money cashForEssentials(Observation view, CompanyView company) {
  var spendable = company.cash;
  for (final bill in company.bills) {
    if (bill.due <= view.today) spendable -= bill.amount;
  }
  for (final order in company.orders) {
    for (final line in order.lines) {
      spendable -= line.unitPrice.timesInt(line.quantity);
    }
  }
  return spendable;
}
