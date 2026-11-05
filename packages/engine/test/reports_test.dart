import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Steps [simulation] through [days] scripted days, returning each result.
List<TickResult> runDays(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++)
    (simulation..submitAll(scriptedCommands(simulation.today))).step(),
];

extension on Simulation {
  void submitAll(List<Command> commands) => commands.forEach(submit);
}

/// Adds [trips] to [key] in [counts].
void count<K>(Map<K, int> counts, K key, int trips) =>
    counts[key] = (counts[key] ?? 0) + trips;

/// A report's numbers as text, to compare whole reports.
String describe(PeriodReport report) => [
  report.start.toIsoString(),
  report.days,
  for (final kind in AccountKind.values) report.flow(kind).cents,
  for (final store in report.stores) ...[
    store.store.index,
    store.visits,
    store.gained,
    store.lost,
    for (final product in [milkBudget, milkPremium]) ...[
      store.sold(product),
      store.revenue(product).cents,
      store.spoiled(product),
      for (final reason in MissReason.values) store.missed(reason, product),
    ],
  ],
].join(' ');

void main() {
  final content = loadScenario(testScenarioJson);
  final start = content.startDay;

  test('periods are calendar weeks from Monday and calendar months', () {
    Day day(String iso) => Day.parse(iso);
    // 2026-01-01 is a Thursday.
    expect(ReportPeriod.week.startOf(day('2026-01-01')), day('2025-12-29'));
    expect(ReportPeriod.week.startOf(day('2026-01-05')), day('2026-01-05'));
    expect(ReportPeriod.week.startOf(day('2026-01-11')), day('2026-01-05'));
    expect(ReportPeriod.week.endOf(day('2026-01-05')), day('2026-01-12'));
    expect(ReportPeriod.month.startOf(day('2026-02-28')), day('2026-02-01'));
    expect(ReportPeriod.month.endOf(day('2026-02-01')), day('2026-03-01'));
    expect(ReportPeriod.month.endOf(day('2026-12-01')), day('2027-01-01'));
  });

  group('company reports', () {
    final simulation = Simulation.newGame(content, seed: 1);
    final results = runDays(simulation, 45); // through 2026-02-14
    final weeks = simulation.reports(playerCompany, ReportPeriod.week);
    final months = simulation.reports(playerCompany, ReportPeriod.month);

    test('run from the first day, by week and by month', () {
      expect(weeks.map((week) => week.start.toIsoString()), [
        '2025-12-29',
        '2026-01-05',
        '2026-01-12',
        '2026-01-19',
        '2026-01-26',
        '2026-02-02',
        '2026-02-09',
      ]);
      expect(weeks.first.firstDay, start);
      expect(weeks.first.days, 4);
      expect(weeks.first.complete, isTrue);
      expect(weeks[1].days, 7);
      expect(weeks.last.days, 6);
      expect(weeks.last.complete, isFalse);
      expect(months.map((month) => (month.start.toIsoString(), month.days)), [
        ('2026-01-01', 31),
        ('2026-02-01', 14),
      ]);
    });

    test('add up to the company books', () {
      final company = simulation.observe(player).companies.single;
      final opening = content.companies[playerCompany.index].cash;
      for (final reports in [weeks, months]) {
        for (final kind in AccountKind.values) {
          final total = reports.fold(
            Money.zero,
            (sum, report) => sum + report.flow(kind),
          );
          final openingBalance = switch (kind) {
            AccountKind.cash => opening,
            AccountKind.equity => -opening,
            _ => Money.zero,
          };
          expect(
            total,
            company.balance(kind) - openingBalance,
            reason: '$kind',
          );
        }
        expect(
          reports.fold(Money.zero, (sum, report) => sum + report.profit),
          company.retainedEarnings + company.balance(AccountKind.dividends),
        );
      }
      expect(
        weeks.fold(Money.zero, (sum, week) => sum + week.profit),
        isNot(Money.zero),
      );
      for (final week in weeks) {
        final store = week.store(playerStore)!;
        expect(
          store.revenue(milkBudget) + store.revenue(milkPremium),
          -week.flow(AccountKind.revenue),
        );
        expect(
          store.costOfGoods(milkBudget) + store.costOfGoods(milkPremium),
          week.flow(AccountKind.costOfGoods),
        );
      }
    });

    test('count sales, shoppers, switches and misses', () {
      var visits = 0;
      var sold = 0;
      final gained = <SwitchKey, int>{};
      final lost = <SwitchKey, int>{};
      final missed = <(MissReason, ProductId), int>{};
      for (final result in results) {
        visits += result.attribution.visits[playerStore.index];
        for (final entry in result.entries) {
          if (entry.reason == EntryReason.sale &&
              entry.party.type == PartyType.company &&
              entry.store == playerStore) {
            sold += entry.units;
          }
        }
        for (final MapEntry(key: (:from, :to, :cause), value: trips)
            in result.attribution.switches.entries) {
          if (to == playerStore) {
            count(gained, (store: from, cause: cause), trips);
          }
          if (from == playerStore) {
            count(lost, (store: to, cause: cause), trips);
          }
        }
        for (final MapEntry(key: miss, value: units)
            in result.attribution.misses.entries) {
          if (miss.store == playerStore) {
            count(missed, (miss.reason, miss.product), units);
          }
        }
      }
      expect(visits, greaterThan(0));
      expect(gained.keys.followedBy(lost.keys), isNotEmpty);
      expect(missed, isNotEmpty);

      final stores = [for (final week in weeks) week.store(playerStore)!];
      expect(stores.fold(0, (sum, store) => sum + store.visits), visits);
      expect(
        stores.fold(
          0,
          (sum, store) =>
              sum + store.sold(milkBudget) + store.sold(milkPremium),
        ),
        sold,
      );
      final reportedGains = <SwitchKey, int>{};
      final reportedLosses = <SwitchKey, int>{};
      final reportedMisses = <(MissReason, ProductId), int>{};
      for (final store in stores) {
        store.gained.forEach((key, trips) => count(reportedGains, key, trips));
        store.lost.forEach((key, trips) => count(reportedLosses, key, trips));
        for (final reason in MissReason.values) {
          for (final product in [milkBudget, milkPremium]) {
            final units = store.missed(reason, product);
            if (units > 0) count(reportedMisses, (reason, product), units);
          }
        }
      }
      expect(reportedGains, gained);
      expect(reportedLosses, lost);
      expect(reportedMisses, missed);
    });

    test('are copies, unaffected by later steps', () {
      final before = describe(weeks.last);
      runDays(simulation, 1);
      expect(describe(weeks.last), before);
    });
  });

  test('trading profit leaves out fitting out, works and tax', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    )..submit(
        OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
      );
    simulation.step();
    final week = simulation.reports(playerCompany, ReportPeriod.week).last;
    expect(week.flow(AccountKind.openingCosts), Money.parse('250.00'));
    // A month's rent is paid on taking the site; the day bears 100.00/31.
    expect(week.rentPaidAhead, Money.parse('96.77'));
    expect(
      week.tradingProfit,
      week.profit + Money.parse('250.00') + Money.parse('96.77'),
      reason: 'the fit-out serves for years',
    );
  });

  test('keep the latest 13 weeks, and survive a save', () {
    final simulation = Simulation.newGame(content, seed: 2);
    runDays(simulation, 120);
    final weeks = simulation.reports(playerCompany, ReportPeriod.week);
    expect(weeks, hasLength(13));
    expect(weeks.first.start, weeks.last.start + -12 * 7);
    expect(simulation.reports(CompanyId(1), ReportPeriod.month), hasLength(4));

    final loaded = Simulation.load(content, simulation.save());
    for (final period in ReportPeriod.values) {
      expect(
        loaded.reports(playerCompany, period).map(describe),
        simulation.reports(playerCompany, period).map(describe),
      );
    }
  });

  test(
    'observations name every store and company and list orders and bills',
    () {
      final simulation = Simulation.newGame(content, seed: 1)
        ..submit(
          PlaceOrder(
            player,
            store: playerStore,
            supplier: fresh,
            lines: [(product: milkBudget, quantity: 24)],
          ),
        )
        ..step();
      final view = simulation.observe(player);
      expect(view.companyNames, ['Player Co', 'Rival Co']);
      expect(view.shelves.map((shelf) => shelf.name), [
        'Player Store',
        'Rival Store',
      ]);
      final order = view.companies.single.orders.single;
      expect(order.supplier, fresh);
      expect(order.arrival, start + 1);
      expect(order.lines.single.quantity, 24);

      simulation.step(); // delivered, on 14 days' credit
      final bill = simulation.observe(player).companies.single.bills.single;
      expect(bill.creditor, (type: PartyType.supplier, index: fresh.index));
      expect(bill.reason, EntryReason.supplierPayment);
      expect(bill.due, start + 1 + 14);
      expect(bill.amount, order.lines.single.unitPrice.timesInt(24));
    },
  );
}
