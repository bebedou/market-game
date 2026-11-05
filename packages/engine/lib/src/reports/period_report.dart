import 'dart:collection';

import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';
import '../state/entities.dart';
import '../state/world_state.dart';
import '../systems/tick_system.dart';
import 'attribution.dart';

/// How long a report runs: a calendar week from Monday, or a calendar month.
/// Append only.
enum ReportPeriod {
  week,
  month;

  /// The first day of the period that contains [day].
  Day startOf(Day day) => switch (this) {
    // Day 0, 1970-01-01, was a Thursday.
    week => Day(day.number - (day.number + 3) % 7),
    month => Day.fromDate(day.date.year, day.date.month, 1),
  };

  /// The first day after the period that starts on [start].
  Day endOf(Day start) => switch (this) {
    week => start + 7,
    month =>
      start.date.month == 12
          ? Day.fromDate(start.date.year + 1, 1, 1)
          : Day.fromDate(start.date.year, start.date.month + 1, 1),
  };

  /// How many reports of this period each company keeps.
  int get kept => switch (this) {
    week => 13,
    month => 24,
  };
}

/// A store a household usually shops at, or went to instead, and why.
typedef SwitchKey = ({StoreId store, SwitchCause cause});

/// What one company did over one week or month: the money posted to each of
/// its accounts, and per store, shoppers, sales, spoilage and misses, and
/// where shoppers came from and went. Recorded at the end of each day; a
/// company's latest report of each period is still running.
final class PeriodReport {
  PeriodReport._({
    required this.company,
    required this.period,
    required this.start,
    required this.firstDay,
    required int days,
    required List<Money> flows,
    required List<StoreReport> stores,
  }) : _days = days,
       _flows = flows,
       _stores = stores;

  PeriodReport._open(this.company, this.period, Day day)
    : start = period.startOf(day),
      firstDay = day,
      _days = 0,
      _flows = List.filled(AccountKind.values.length, Money.zero),
      _stores = [];

  PeriodReport.read(StateReader reader)
    : company = CompanyId(reader.readInt()),
      period = ReportPeriod.values[reader.readInt()],
      start = Day(reader.readInt()),
      firstDay = Day(reader.readInt()),
      _days = reader.readInt(),
      _flows = Accounts.readBalances(reader),
      _stores = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          StoreReport._read(reader),
      ];

  final CompanyId company;
  final ReportPeriod period;

  /// The first day of the week or month.
  final Day start;

  /// The first day recorded: later than [start] if the company was founded,
  /// or the game started, during the period.
  final Day firstDay;
  int _days;
  final List<Money> _flows;
  final List<StoreReport> _stores;

  /// The first day after the period.
  Day get end => period.endOf(start);

  /// Days recorded so far.
  int get days => _days;

  /// Whether every day up to [end] is recorded.
  bool get complete => firstDay + _days == end;

  /// The net amount posted to [kind] in the company's books during the
  /// period, debit-positive like balances: revenue is negative.
  Money flow(AccountKind kind) => _flows[kind.index];

  /// Income less expenses: what the period added to retained earnings
  /// before dividends.
  Money get profit {
    var total = Money.zero;
    for (final kind in _incomeStatement) {
      total -= _flows[kind.index];
    }
    return total;
  }

  /// What trading earned: [profit] before what was spent fitting out and
  /// enlarging stores, which serves for years, the corporate tax, gains on
  /// stores sold and debts forgiven, and with each store's rent and
  /// overheads, paid on the first of the month, counted day by day (see
  /// [StoreReport.occupancy]), so a week with the first in it bears only
  /// its share.
  Money get tradingProfit =>
      profit +
      flow(AccountKind.openingCosts) +
      flow(AccountKind.taxes) +
      flow(AccountKind.disposals) +
      flow(AccountKind.debtRelief) +
      rentPaidAhead;

  /// Rent and overheads paid during the period beyond its days' share:
  /// ahead, in a week with the first of the month in it, or drawn on, below
  /// zero, in one without.
  Money get rentPaidAhead =>
      flow(AccountKind.rent) +
      flow(AccountKind.overheads) -
      _stores.fold(Money.zero, (sum, store) => sum + store._occupancy);

  /// The company's stores that traded or were reported on, in order of
  /// first activity.
  List<StoreReport> get stores => UnmodifiableListView(_stores);

  StoreReport? store(StoreId store) {
    for (final report in _stores) {
      if (report.store == store) return report;
    }
    return null;
  }

  /// Reports [products] from now on: the scenario gained some since the
  /// game was saved.
  void growProducts(int products) {
    for (final store in _stores) {
      store._grow(products);
    }
  }

  StoreReport _storeFor(StoreId store, int products) {
    final existing = this.store(store);
    if (existing != null) return existing;
    final report = StoreReport._(store, products);
    _stores.add(report);
    return report;
  }

  PeriodReport _copy() => PeriodReport._(
    company: company,
    period: period,
    start: start,
    firstDay: firstDay,
    days: _days,
    flows: List.of(_flows),
    stores: [for (final store in _stores) store._copy()],
  );

  void write(StateWriter writer) {
    writer
      ..writeInt(company.index)
      ..writeInt(period.index)
      ..writeInt(start.number)
      ..writeInt(firstDay.number)
      ..writeInt(_days);
    Accounts.writeBalances(writer, _flows);
    writer.writeInt(_stores.length);
    for (final store in _stores) {
      store._write(writer);
    }
  }
}

/// The accounts whose flows make up profit.
const _incomeStatement = [
  AccountKind.revenue,
  AccountKind.costOfGoods,
  AccountKind.writeOffs,
  AccountKind.spending,
  AccountKind.rent,
  AccountKind.interest,
  AccountKind.openingCosts,
  AccountKind.debtRelief,
  AccountKind.wages,
  AccountKind.research,
  AccountKind.salaries,
  AccountKind.marketing,
  AccountKind.taxes,
  AccountKind.disposals,
  AccountKind.overheads,
];

/// One store's part of a [PeriodReport].
final class StoreReport {
  StoreReport._(this.store, int products)
    : _visits = 0,
      _sold = List.filled(products, 0),
      _revenue = List.filled(products, Money.zero),
      _costOfGoods = List.filled(products, Money.zero),
      _spoiled = List.filled(products, 0),
      _spoilage = List.filled(products, Money.zero),
      _missed = [for (final _ in MissReason.values) List.filled(products, 0)],
      _gained = {},
      _lost = {},
      _runningCosts = Money.zero,
      _occupancy = Money.zero;

  StoreReport._copyOf(StoreReport other)
    : store = other.store,
      _visits = other._visits,
      _sold = List.of(other._sold),
      _revenue = List.of(other._revenue),
      _costOfGoods = List.of(other._costOfGoods),
      _spoiled = List.of(other._spoiled),
      _spoilage = List.of(other._spoilage),
      _missed = [for (final units in other._missed) List.of(units)],
      _gained = Map.of(other._gained),
      _lost = Map.of(other._lost),
      _runningCosts = other._runningCosts,
      _occupancy = other._occupancy;

  StoreReport._read(StateReader reader)
    : store = StoreId(reader.readInt()),
      _visits = reader.readInt(),
      _sold = _readInts(reader),
      _revenue = [for (final cents in _readInts(reader)) Money(cents)],
      _costOfGoods = [for (final cents in _readInts(reader)) Money(cents)],
      _spoiled = _readInts(reader),
      _spoilage = [for (final cents in _readInts(reader)) Money(cents)],
      _missed = [for (final _ in MissReason.values) _readInts(reader)],
      _gained = _readSwitches(reader),
      _lost = _readSwitches(reader),
      _runningCosts = reader.version >= 15
          ? Money(reader.readInt())
          : Money.zero,
      _occupancy = reader.version >= 20
          ? Money(reader.readInt())
          : Money.zero;

  final StoreId store;
  int _visits;
  final List<int> _sold;
  final List<Money> _revenue;
  final List<Money> _costOfGoods;
  final List<int> _spoiled;
  final List<Money> _spoilage;
  final List<List<int>> _missed;
  final Map<SwitchKey, int> _gained;
  final Map<SwitchKey, int> _lost;
  Money _runningCosts;
  Money _occupancy;

  void _grow(int products) {
    while (_sold.length < products) {
      _sold.add(0);
      _revenue.add(Money.zero);
      _costOfGoods.add(Money.zero);
      _spoiled.add(0);
      _spoilage.add(Money.zero);
      for (final missed in _missed) {
        missed.add(0);
      }
    }
  }

  /// Shopping trips to the store.
  int get visits => _visits;

  /// Units of [product] sold.
  int sold(ProductId product) => _sold[product.index];

  /// What sales of [product] took in.
  Money revenue(ProductId product) => _revenue[product.index];

  /// What the units of [product] sold had cost.
  Money costOfGoods(ProductId product) => _costOfGoods[product.index];

  /// Units of [product] thrown away past their shelf life.
  int spoiled(ProductId product) => _spoiled[product.index];

  /// What the spoiled units of [product] had cost.
  Money spoilage(ProductId product) => _spoilage[product.index];

  /// What its staff, manager, rent, overheads and marketing cost.
  Money get runningCosts => _runningCosts;

  /// Its rent and overheads for the days recorded: each day's share of the
  /// month's, which is paid on the first.
  Money get occupancy => _occupancy;

  /// Sales of every product.
  Money get totalRevenue => _revenue.fold(Money.zero, (sum, m) => sum + m);

  /// Sales less the goods sold and spoiled and the running costs: what the
  /// store earned before interest and tax.
  Money get profit {
    var profit = -_runningCosts;
    for (var i = 0; i < _revenue.length; i++) {
      profit += _revenue[i] - _costOfGoods[i] - _spoilage[i];
    }
    return profit;
  }

  /// Units of [product] shoppers wanted but didn't buy here, for [reason].
  int missed(MissReason reason, ProductId product) =>
      _missed[reason.index][product.index];

  /// Trips here by households who usually shop elsewhere, by that store and
  /// what drew them here, in order of first occurrence.
  Map<SwitchKey, int> get gained => UnmodifiableMapView(_gained);

  /// Trips elsewhere by households who usually shop here, by the store they
  /// chose and why, in order of first occurrence.
  Map<SwitchKey, int> get lost => UnmodifiableMapView(_lost);

  StoreReport _copy() => StoreReport._copyOf(this);

  void _write(StateWriter writer) {
    writer
      ..writeInt(store.index)
      ..writeInt(_visits);
    _writeInts(writer, _sold);
    _writeInts(writer, [for (final money in _revenue) money.cents]);
    _writeInts(writer, [for (final money in _costOfGoods) money.cents]);
    _writeInts(writer, _spoiled);
    _writeInts(writer, [for (final money in _spoilage) money.cents]);
    for (final units in _missed) {
      _writeInts(writer, units);
    }
    _writeSwitches(writer, _gained);
    _writeSwitches(writer, _lost);
    writer
      ..writeInt(_runningCosts.cents)
      ..writeInt(_occupancy.cents);
  }
}

/// The accounts that make up a store's running costs.
const _runningCostAccounts = {
  AccountKind.wages,
  AccountKind.salaries,
  AccountKind.rent,
  AccountKind.overheads,
  AccountKind.marketing,
};

List<int> _readInts(StateReader reader) => [
  for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
];

void _writeInts(StateWriter writer, List<int> values) {
  writer.writeInt(values.length);
  values.forEach(writer.writeInt);
}

Map<SwitchKey, int> _readSwitches(StateReader reader) => {
  for (var i = 0, n = reader.readInt(); i < n; i++)
    (
      store: StoreId(reader.readInt()),
      cause: SwitchCause.values[reader.readInt()],
    ): reader
        .readInt(),
};

void _writeSwitches(StateWriter writer, Map<SwitchKey, int> switches) {
  writer.writeInt(switches.length);
  for (final MapEntry(key: (:store, :cause), value: trips)
      in switches.entries) {
    writer
      ..writeInt(store.index)
      ..writeInt(cause.index)
      ..writeInt(trips);
  }
}

/// [company]'s reports for [period], oldest first, as copies unaffected by
/// later steps.
List<PeriodReport> companyReports(
  WorldState world,
  CompanyId company,
  ReportPeriod period,
) => [
  for (final report in world.periodReports)
    if (report.company == company && report.period == period) report._copy(),
];

/// Folds the day's journal entries and attribution into each company's
/// running week and month reports. Active companies are recorded every day;
/// a company liquidated today is recorded one last time.
void recordPeriodReports(WorldState world, TickContext context) {
  final day = context.day;
  final products = context.content.products.length;
  final running = List<List<PeriodReport>?>.filled(
    world.companies.length,
    null,
  );
  List<PeriodReport> reportsOf(CompanyId company) =>
      running[company.index] ??= [
        for (final period in ReportPeriod.values)
          _runningReport(world, company, period, day),
      ];
  void add(CompanyId company, void Function(PeriodReport report) change) =>
      reportsOf(company).forEach(change);

  for (final company in world.companies) {
    if (company.status == CompanyStatus.active) reportsOf(company.id);
  }
  // Each trading store's day of the month's rent and overheads, as billed.
  final days = daysInMonth(day.date.year, day.date.month);
  for (final store in world.stores) {
    if (!store.isTrading ||
        world.companies[store.company.index].status !=
            CompanyStatus.active) {
      continue;
    }
    final monthly =
        (context.content.sites[store.site.index].rentFor(store.area) +
                context.content.formats[store.format.index].overheadsFor(
                  store.area,
                ))
            .times(world.macro.priceIndex);
    final share = Money(mulDivRound(monthly.cents, 1, days));
    add(store.company, (report) {
      report._storeFor(store.id, products)._occupancy += share;
    });
  }
  for (final entry in context.ledger.entries) {
    if (entry.party.type != PartyType.company) continue;
    final company = CompanyId(entry.party.index);
    add(company, (report) {
      report._flows[entry.debit.index] += entry.amount;
      report._flows[entry.credit.index] -= entry.amount;
      final store = entry.store;
      final product = entry.product;
      if (store != null && _runningCostAccounts.contains(entry.debit)) {
        report._storeFor(store, products)._runningCosts += entry.amount;
      }
      if (store == null || product == null) return;
      final sales = report._storeFor(store, products);
      switch (entry.reason) {
        case EntryReason.sale:
          sales._sold[product.index] += entry.units;
          sales._revenue[product.index] += entry.amount;
        case EntryReason.costOfSale:
          sales._costOfGoods[product.index] += entry.amount;
        case EntryReason.spoilage:
          sales._spoiled[product.index] += entry.units;
          sales._spoilage[product.index] += entry.amount;
        default:
      }
    });
  }
  final attribution = context.attribution;
  for (var i = 0; i < attribution.visits.length; i++) {
    final visits = attribution.visits[i];
    if (visits == 0) continue;
    final store = world.stores[i];
    add(store.company, (report) {
      report._storeFor(store.id, products)._visits += visits;
    });
  }
  for (final MapEntry(key: (:from, :to, :cause), value: trips)
      in attribution.switches.entries) {
    add(world.stores[from.index].company, (report) {
      final lost = report._storeFor(from, products)._lost;
      final key = (store: to, cause: cause);
      lost[key] = (lost[key] ?? 0) + trips;
    });
    add(world.stores[to.index].company, (report) {
      final gained = report._storeFor(to, products)._gained;
      final key = (store: from, cause: cause);
      gained[key] = (gained[key] ?? 0) + trips;
    });
  }
  for (final MapEntry(key: miss, value: units) in attribution.misses.entries) {
    add(world.stores[miss.store.index].company, (report) {
      final missed = report._storeFor(miss.store, products)._missed;
      missed[miss.reason.index][miss.product.index] += units;
    });
  }
  for (final reports in running) {
    for (final report in reports ?? const <PeriodReport>[]) {
      report._days++;
    }
  }
}

/// [company]'s report for the [period] that contains [day], opened if it
/// doesn't exist yet. Opening one drops the company's oldest beyond what the
/// period keeps.
PeriodReport _runningReport(
  WorldState world,
  CompanyId company,
  ReportPeriod period,
  Day day,
) {
  final reports = world.periodReports;
  final start = period.startOf(day);
  var count = 0;
  int? oldest;
  for (var i = reports.length - 1; i >= 0; i--) {
    final report = reports[i];
    if (report.company != company || report.period != period) continue;
    if (report.start == start) return report;
    count++;
    oldest = i;
  }
  if (count >= period.kept) reports.removeAt(oldest!);
  final report = PeriodReport._open(company, period, day);
  reports.add(report);
  return report;
}
