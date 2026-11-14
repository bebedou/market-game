import 'package:engine/engine.dart';

import 'controller.dart';

/// What some months came to, for a company or several together: from sales
/// down to net profit, and the money tied up meanwhile.
final class Results {
  const Results({
    required this.months,
    required this.days,
    required this.sales,
    required this.goods,
    required this.spoiled,
    required this.staff,
    required this.premises,
    required this.marketing,
    required this.research,
    required this.interest,
    required this.works,
    required this.tax,
    required this.oneOffs,
    required this.capital,
    this.ownGoods = Money.zero,
  });

  /// The least time over which a return means anything.
  static const roicDays = 90;

  /// Months counted, the one still running among them if it is.
  final int months;
  final int days;
  final Money sales;

  /// What the companies' own factories made for their owner's shops, at
  /// what the wholesalers would have charged: what those shops' goods cost
  /// them, which the factories' materials, staff and site then cost less.
  final Money ownGoods;
  final Money goods;

  /// Stock thrown away or abandoned.
  final Money spoiled;

  /// Wages and salaries.
  final Money staff;

  /// Rent and overheads.
  final Money premises;
  final Money marketing;
  final Money research;
  final Money interest;

  /// Fitting out and enlarging stores.
  final Money works;

  /// The corporate tax billed in these months: on the year before.
  final Money tax;

  /// Gains on stores sold and debts forgiven, less losses.
  final Money oneOffs;

  /// The money tied up (see [Financials.capital]), averaged over the
  /// month-ends; zero for a company gone.
  final Money capital;

  Money get gross => sales + ownGoods - goods - spoiled;

  /// What trading earned, before interest, works, tax and one-offs.
  Money get operating => gross - staff - premises - marketing - research;
  Money get net => operating - interest - works - tax + oneOffs;

  Fx? get grossMargin => shareOfSales(gross);
  Fx? get operatingMargin => shareOfSales(operating);
  Fx? get netMargin => shareOfSales(net);

  /// [part] as a share of sales, or for a company that only makes goods
  /// for its owner's shops, of those; null without either.
  Fx? shareOfSales(Money part) {
    final base = sales.cents != 0 ? sales : ownGoods;
    return base.cents == 0
        ? null
        : Fx.raw((part.cents * Fx.scale / base.cents).round());
  }

  /// Operating profit after tax over the money tied up, at a year's rate;
  /// null if too soon to tell or nothing is tied up.
  Fx? get roic {
    if (days < roicDays || capital <= Money.zero) return null;
    final yearly = (operating - tax).cents * 365 / days;
    return Fx.raw((yearly * Fx.scale / capital.cents).round());
  }

  /// [amount], from these months, scaled to twelve.
  Money perYear(Money amount) =>
      months >= 12 ? amount : Money((amount.cents * 12 / months).round());
}

/// One calendar year: what was filed for it, and the [detail] that only
/// reports hold, while they are kept.
typedef YearResults = ({
  int year,
  Money sales,
  Money net,
  int stores,
  Results? detail,

  /// The year still running, so nothing filed yet.
  bool soFar,
});

/// A company's figures, or several companies' added up.
final class Financials {
  const Financials({
    required this.balances,
    required this.fitOut,
    required this.recent,
    required this.young,
    required this.before,
    required this.years,
  });

  /// The fewest months worth comparing.
  static const beforeMonths = 6;

  /// Balances, debit-positive, indexed by [AccountKind].
  final List<Money> balances;

  /// Fitting out and works at what they cost, though spent long ago.
  final Money fitOut;

  /// The last twelve complete months, or if [young] every month so far, the
  /// running one with them; for a company gone, its last. Null before its
  /// first day.
  final Results? recent;

  /// Whether there are fewer than twelve complete months to show.
  final bool young;

  /// The months before [recent], fewer than twelve once the oldest report is
  /// dropped; null if too few to compare, or for a company gone, whose last
  /// month is cut short and whose debts forgiven count as income.
  final Results? before;

  /// Newest first.
  final List<YearResults> years;

  Money balance(AccountKind kind) => balances[kind.index];

  /// The money tied up in the business: fit-out and works at cost, what was
  /// paid for stores beyond their stock, and the stock, less unpaid bills.
  /// Equity plus loans less cash wouldn't do: fitting out is an expense here,
  /// so a shop's books would show almost nothing invested.
  Money get capital => _tiedUp(fitOut, balances);

  /// What is owned less what is owed, at book value: fit-out and works are
  /// spent, so they don't count.
  Money get netAssets =>
      balance(AccountKind.cash) +
      balance(AccountKind.inventory) +
      balance(AccountKind.receivables) +
      balance(AccountKind.businessAssets) +
      balance(AccountKind.investments) +
      balance(AccountKind.payables) +
      balance(AccountKind.loans);

  /// Profit kept since the start.
  Money get retainedEarnings => netAssets + balance(AccountKind.equity);
}

Money _tiedUp(Money fitOut, List<Money> balances) =>
    fitOut +
    balances[AccountKind.businessAssets.index] +
    balances[AccountKind.inventory.index] +
    balances[AccountKind.receivables.index] +
    balances[AccountKind.payables.index];

/// A month's report, and the money tied up at its end.
typedef _Month = ({PeriodReport report, Money capital});

/// The figures of [companies], added up.
Financials financialsOf(
  SimulationController game,
  List<CompanyView> companies,
) {
  final balances = List.filled(AccountKind.values.length, Money.zero);
  var fitOut = Money.zero;
  for (final company in companies) {
    for (final kind in AccountKind.values) {
      balances[kind.index] += company.balance(kind);
    }
    fitOut += _fitOut(game, company);
  }
  final histories = [for (final company in companies) _history(game, company)];
  final reports = [
    for (final history in histories)
      for (final month in history) month.report,
  ];
  if (reports.isEmpty) {
    return Financials(
      balances: balances,
      fitOut: fitOut,
      recent: null,
      young: true,
      before: null,
      years: const [],
    );
  }
  var first = reports.first.start;
  var last = reports.first.end;
  for (final report in reports) {
    if (report.start < first) first = report.start;
    if (report.end > last) last = report.end;
  }
  final trading = companies.any((c) => c.status == CompanyStatus.active);
  // The month now running, or for companies gone, the month after their last.
  final now = trading ? ReportPeriod.month.startOf(game.today) : last;
  final yearAgo = _monthsBefore(now, 12);
  final young = first > yearAgo;
  final before = young || !trading
      ? null
      : _over(histories, _monthsBefore(now, 24), yearAgo, trading: trading);
  return Financials(
    balances: balances,
    fitOut: fitOut,
    recent: young
        ? _over(histories, first, last, trading: trading)
        : _over(histories, yearAgo, now, trading: trading),
    young: young,
    before: before != null && before.months >= Financials.beforeMonths
        ? before
        : null,
    years: _years(game, companies, histories, trading: trading),
  );
}

/// [company]'s months, oldest first, the money tied up rolled back from
/// today's through what each month posted.
List<_Month> _history(SimulationController game, CompanyView company) {
  var capital = _tiedUp(_fitOut(game, company), company.balances);
  final months = <_Month>[];
  for (final report
      in game.reports(ReportPeriod.month, company: company.id).reversed) {
    months.add((report: report, capital: capital));
    capital -=
        report.flow(AccountKind.openingCosts) +
        report.flow(AccountKind.businessAssets) +
        report.flow(AccountKind.inventory) +
        report.flow(AccountKind.receivables) +
        report.flow(AccountKind.payables);
  }
  return months.reversed.toList();
}

/// What [company] has spent fitting out and enlarging stores, with the
/// stores the game began with, which no books show.
Money _fitOut(SimulationController game, CompanyView company) {
  final content = game.content;
  final start = game.start;
  final chosen = content.stores.indexWhere(
    (store) => content.companies[store.company.index].owner == content.player,
  );
  var total = company.balance(AccountKind.openingCosts);
  // A holding began with no store: its books show every one.
  if (start != null && start.holding) return total;
  for (final store in company.stores) {
    final index = store.id.index;
    if (index >= content.stores.length || store.acquiredOn != null) continue;
    // As the store began: converting it since is among the works.
    final format = index == chosen && start != null
        ? start.format!
        : content.stores[index].format;
    total += content.sites[store.site.index].openingCost.times(
      content.formats[format.index].fitOut,
    );
  }
  return total;
}

/// What the months from [from] up to [to] came to.
Results _over(
  List<List<_Month>> histories,
  Day from,
  Day to, {
  required bool trading,
}) {
  final days = <int, int>{};
  var sales = Money.zero;
  var ownGoods = Money.zero;
  var goods = Money.zero;
  var spoiled = Money.zero;
  var staff = Money.zero;
  var premises = Money.zero;
  var marketing = Money.zero;
  var research = Money.zero;
  var interest = Money.zero;
  var works = Money.zero;
  var tax = Money.zero;
  var oneOffs = Money.zero;
  var capital = Money.zero;
  for (final history in histories) {
    for (final (:report, capital: tiedUp) in history) {
      if (report.start < from || report.start >= to) continue;
      final start = report.start.number;
      if (report.days > (days[start] ?? 0)) days[start] = report.days;
      sales -= report.flow(AccountKind.revenue);
      ownGoods -= report.flow(AccountKind.ownGoods);
      goods += report.flow(AccountKind.costOfGoods);
      spoiled += report.flow(AccountKind.writeOffs);
      staff +=
          report.flow(AccountKind.wages) + report.flow(AccountKind.salaries);
      premises +=
          report.flow(AccountKind.rent) + report.flow(AccountKind.overheads);
      marketing += report.flow(AccountKind.marketing);
      research += report.flow(AccountKind.research);
      interest += report.flow(AccountKind.interest);
      works += report.flow(AccountKind.openingCosts);
      tax += report.flow(AccountKind.taxes);
      oneOffs -=
          report.flow(AccountKind.disposals) +
          report.flow(AccountKind.debtRelief);
      capital += tiedUp;
    }
  }
  return Results(
    months: days.length,
    days: days.values.fold(0, (sum, count) => sum + count),
    sales: sales,
    ownGoods: ownGoods,
    goods: goods,
    spoiled: spoiled,
    staff: staff,
    premises: premises,
    marketing: marketing,
    research: research,
    interest: interest,
    works: works,
    tax: tax,
    oneOffs: oneOffs,
    capital: trading && days.isNotEmpty
        ? Money(capital.cents ~/ days.length)
        : Money.zero,
  );
}

/// Every year there is anything for, newest first: what was filed, with the
/// detail if the year's months are all still kept.
List<YearResults> _years(
  SimulationController game,
  List<CompanyView> companies,
  List<List<_Month>> histories, {
  required bool trading,
}) {
  final mine = {for (final company in companies) company.id};
  final filed = <int, List<Filing>>{};
  for (final filing in game.view.filings) {
    if (mine.contains(filing.company)) {
      (filed[filing.year] ??= []).add(filing);
    }
  }
  final years = <int>{
    ...filed.keys,
    for (final history in histories)
      for (final month in history) month.report.start.date.year,
  }.toList()..sort((a, b) => b.compareTo(a));
  final open = companies.fold(
    0,
    (sum, company) =>
        sum +
        company.stores.where((s) => s.status != StoreStatus.closed).length,
  );
  YearResults results(int year) {
    final january = Day.fromDate(year, 1, 1);
    final filings = filed[year];
    // A full set of reports may have dropped months from before its first.
    final kept = histories.every(
      (history) =>
          history.length < ReportPeriod.month.kept ||
          history.first.report.start <= january,
    );
    final detail = _over(
      histories,
      january,
      Day.fromDate(year + 1, 1, 1),
      trading: trading,
    );
    if (filings == null) {
      return (
        year: year,
        sales: detail.sales,
        net: detail.net,
        stores: open,
        detail: detail,
        soFar: year == game.today.date.year,
      );
    }
    return (
      year: year,
      sales: filings.fold(Money.zero, (sum, f) => sum + f.revenue),
      net: filings.fold(Money.zero, (sum, f) => sum + f.profit),
      stores: filings.fold(0, (sum, f) => sum + f.stores),
      detail: kept ? detail : null,
      soFar: false,
    );
  }

  return [for (final year in years) results(year)];
}

/// The first of the month [months] before [month], itself a first.
Day _monthsBefore(Day month, int months) {
  final count = month.date.year * 12 + month.date.month - 1 - months;
  return Day.fromDate(count ~/ 12, count % 12 + 1, 1);
}
