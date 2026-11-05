import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  // A shop format with overheads of 1.00 a square metre, and a corner site
  // that rents for 100.00.
  final content = loadScenario(
    testScenarioJson
        .replaceFirst(
          '"categories": [{ "id": "milk", "name": "Milk" }],',
          '"categories": [{ "id": "milk", "name": "Milk" }],\n'
              '  "formats": [{ "id": "shop", "name": "Shop", '
              '"categories": ["milk"], "overheads": "1.00" }],',
        )
        .replaceFirst(
          '"location": "0.50", "rent": "0.00"',
          '"location": "0.50", "rent": "100.00"',
        ),
  );

  test('are billed with the rent each month, for the floor area', () {
    expect(content.formats.single.overheads, Money.parse('1.00'));
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final day = simulation.step();
    expect(content.startDay.isFirstOfMonth, isTrue);
    final billed = [
      for (final entry in day.entries)
        if (entry.store == playerStore &&
            entry.party.type == PartyType.company &&
            entry.credit == AccountKind.payables)
          (entry.reason, entry.debit, entry.amount),
    ];
    expect(billed, [
      (EntryReason.rent, AccountKind.rent, Money.parse('100.00')),
      // 100 m² at 1.00.
      (EntryReason.overheads, AccountKind.overheads, Money.parse('100.00')),
    ]);
    expect(
      simulation.step().entries.where(
        (entry) => entry.reason == EntryReason.overheads,
      ),
      isEmpty,
      reason: 'once a month',
    );
  });

  test("add to a store's running costs and take from its profit", () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    )..step();
    final report = simulation
        .reports(playerCompany, ReportPeriod.month)
        .last
        .store(playerStore)!;
    // Rent and overheads; wages are free in the test scenario and nothing
    // sold.
    expect(report.runningCosts, Money.parse('200.00'));
    expect(report.profit, Money.parse('-200.00'));
    expect(
      simulation
          .reports(playerCompany, ReportPeriod.month)
          .last
          .flow(AccountKind.overheads),
      Money.parse('100.00'),
    );
  });

  test('are counted day by day in the reports, though paid on the first', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    for (var i = 0; i < 31; i++) {
      simulation.step();
    }
    // 200.00 a month of rent and overheads, 6.45 a day in January.
    final weeks = simulation.reports(playerCompany, ReportPeriod.week);
    final first = weeks.first; // Thursday 1 to Sunday 4 January.
    expect(first.days, 4);
    expect(first.store(playerStore)!.occupancy, Money.parse('25.80'));
    expect(first.rentPaidAhead, Money.parse('174.20'));
    expect(first.tradingProfit, first.profit + Money.parse('174.20'));
    final second = weeks[1];
    expect(second.rentPaidAhead, Money.parse('-45.15'));
    expect(second.tradingProfit, Money.parse('-45.15'), reason: 'no sales');
    final january = simulation.reports(playerCompany, ReportPeriod.month).last;
    expect(january.complete, isTrue);
    expect(january.rentPaidAhead, Money.parse('0.05'), reason: 'rounding');
  });
}
