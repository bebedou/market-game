import '../accounting/ledger.dart';
import '../core/money.dart';
import '../reports/period_report.dart';
import '../state/orders.dart';
import '../state/public_record.dart';
import '../state/world_state.dart';
import 'settlement.dart';
import 'tick_system.dart';

/// The year's end, on the first of January: every company's accounts for
/// the year just ended become public, and each active company is billed its
/// corporate tax on the year's profit, less losses carried from earlier
/// years, due within the month.
final class TaxSystem implements TickSystem {
  const TaxSystem();

  @override
  void run(WorldState world, TickContext context) {
    final day = context.day;
    if (day.date.month != 1 || !day.isFirstOfMonth) return;
    if (day <= context.content.startDay) return;
    final year = day.date.year - 1;
    final taxes = context.content.taxes;
    for (final company in world.companies) {
      var revenue = Money.zero;
      var profit = Money.zero;
      var taxed = Money.zero;
      var months = 0;
      for (final report in world.periodReports) {
        if (report.company != company.id ||
            report.period != ReportPeriod.month ||
            report.start.date.year != year) {
          continue;
        }
        revenue -= report.flow(AccountKind.revenue);
        profit += report.profit;
        taxed += report.flow(AccountKind.taxes);
        months++;
      }
      if (months == 0) continue;
      world.filings.add((
        company: company.id,
        year: year,
        revenue: revenue,
        profit: profit,
        stores: world.stores
            .where((store) => store.company == company.id && store.isTrading)
            .length,
      ));
      if (taxes == null || !company.isActive) continue;
      // The year's profit before the tax it paid on the year before.
      var base = profit + taxed;
      if (base <= Money.zero) {
        company.lossCarried -= base;
        continue;
      }
      final offset = company.lossCarried < base ? company.lossCarried : base;
      company.lossCarried -= offset;
      base -= offset;
      final tax = taxes.corporateTax(base, world.macro.priceIndex);
      if (tax == Money.zero) continue;
      bill(
        context.ledger,
        company,
        AccountKind.taxes,
        Payable(
          creditor: world.government.partyRef,
          creditorAccount: AccountKind.revenue,
          reason: EntryReason.corporateTax,
          amount: tax,
          due: day + 30,
        ),
      );
    }
    world.filings.removeWhere(
      (filing) => filing.year <= year - filingYearsKept,
    );
  }
}
