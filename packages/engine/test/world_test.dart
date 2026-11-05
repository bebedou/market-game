import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _steadyMacro =
    '"regimes": [\n'
    '      { "id": "steady", "name": "Steady", "meanMonths": 12, '
    '"inflation": "0", "realWageGrowth": "0",\n'
    '        "outputGap": "0", "demand": "1", "premiumShift": "0" }\n'
    '    ] },';

/// The test scenario with [regimes] (JSON objects) in place of its steady
/// economy, a 2% inflation target and a 2% neutral rate.
String withRegimes(String regimes) {
  if (!testScenarioJson.contains(_steadyMacro)) {
    throw StateError('The fixture has no steady economy');
  }
  return testScenarioJson
      .replaceFirst(_steadyMacro, '"regimes": [$regimes] },')
      .replaceFirst('"neutralRate": "0.03"', '"neutralRate": "0.02"')
      .replaceFirst('"inflationTarget": "0"', '"inflationTarget": "0.02"');
}

String regime(
  String id, {
  int months = 12,
  String inflation = '0',
  String wages = '0',
  String gap = '0',
  String demand = '1',
  String shift = '0',
}) =>
    '{ "id": "$id", "name": "$id", "meanMonths": $months, '
    '"inflation": "$inflation", "realWageGrowth": "$wages", '
    '"outputGap": "$gap", "demand": "$demand", "premiumShift": "$shift" }';

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

void main() {
  final start = loadScenario(testScenarioJson).startDay;

  group('macro', () {
    test('inflation compounds into prices, rents and the policy rate', () {
      final content = loadScenario(
        withRegimes(
          regime('hot', inflation: '0.12', wages: '0.06', gap: '0.01'),
        ).replaceFirst('"startRegime": "steady"', '"startRegime": "hot"'),
      );
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: quietSystems,
      );
      final macro = simulation.world.macro;
      // 2% neutral + 2% target + 1.5 × 10% above target + 0.5 × 1% gap.
      expect(macro.policyRate, Fx.parse('0.195'));
      expect(macro.priceIndex, Fx.one);

      simulation.submit(
        OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
      );
      final february = advance(simulation, 32).last; // through February 1
      expect(macro.priceIndex, Fx.parse('1.01')); // 12% a year, monthly
      expect(
        february.entries
            .where((e) => e.reason == EntryReason.rent)
            .map((e) => e.amount)
            .toSet(),
        {Money.parse('101.00')}, // the lane's 100.00 rent
      );
      expect(macro.wageIndex, Fx.parse('1.015')); // plus 6% real
      simulation
        ..submit(
          PlaceOrder(
            player,
            store: playerStore,
            supplier: bulk,
            lines: [(product: milkBudget, quantity: 48)],
          ),
        )
        ..submit(
          TakeLoan(
            player,
            company: playerCompany,
            amount: Money(10000),
            termMonths: 12,
            guarantee: true,
          ),
        )
        ..step();
      // 0.55 × 1.01, rounded.
      expect(simulation.world.orders.single.lines.single.unitPrice, Money(56));
      // The policy rate, the 2% margin and the 2% for a guaranteed loan.
      expect(simulation.world.loans.single.rate, Fx.parse('0.235'));
      expect(simulation.observe(rival).macro.priceIndex, Fx.parse('1.01'));

      advance(simulation, 27); // through March 1
      expect(macro.priceIndex, Fx.parse('1.0201'));
    });

    test('the cycle moves on, and a slump cuts what households need', () {
      final content = loadScenario(
        withRegimes(
          '${regime('boom', months: 1)}, '
          '${regime('slump', months: 1, demand: '0.5')}',
        ).replaceFirst('"startRegime": "steady"', '"startRegime": "boom"'),
      );
      final closed = loadScenario(
        withRegimes(
              '${regime('boom', months: 1)}, '
              '${regime('slump', months: 1, demand: '0.5')}',
            )
            .replaceFirst('"startRegime": "steady"', '"startRegime": "boom"')
            .replaceAll(
              '"staff": { "morning": 1, "midday": 1, "evening": 1, "night": 1 }',
              '"staff": {}',
            ),
      );
      expect(content.macro.regimes.map((r) => r.key), ['boom', 'slump']);
      // With no store open, nobody shops and needs just build up.
      final simulation = Simulation.newGame(closed, seed: 1);
      final world = simulation.world;
      advance(simulation, 31);
      expect(world.macro.regime, RegimeId(0));
      expect(world.cohorts.first.needs, [Fx.parse('3.5')]); // 7 days' cap
      simulation.step();
      expect(world.macro.regime, RegimeId(1));
      // Half the consumption: the cap is now 7 × 0.25.
      expect(world.cohorts.first.needs, [Fx.parse('1.75')]);
      advance(simulation, 28);
      expect(world.macro.regime, RegimeId(0));
    });
  });

  group('staffing', () {
    final paid = loadScenario(
      testScenarioJson
          .replaceFirst('"slotWage": "0.00"', '"slotWage": "20.00"')
          .replaceFirst('"visitsPerStaff": 30', '"visitsPerStaff": 2'),
    );

    test('is set per slot, within limits, by the owner', () {
      final simulation = Simulation.newGame(
        paid,
        seed: 1,
        systems: quietSystems,
      );
      SetStaffing staffing(List<int> staff, {StoreId store = playerStore}) =>
          SetStaffing(player, store: store, staff: staff);
      final invalid = {
        staffing([1, 1, 1]): 'staffEachSlot',
        staffing([5, 0, 0, 0]): 'staffRange',
        staffing([1, 1, 1, 1], store: rivalStore):
            'notYourStore',
      };
      invalid.keys.forEach(simulation.submit);
      simulation.submit(staffing([2, 0, 1, 0]));
      final result = simulation.step();
      expect({
        for (final rejection in result.rejections)
          rejection.command: rejection.reason.key,
      }, invalid);
      expect(simulation.world.stores[playerStore.index].staff, [2, 0, 1, 0]);
      expect(simulation.observe(rival).shelves[playerStore.index].openSlots, [
        true,
        false,
        true,
        false,
      ]);
    });

    test('costs wages every day, paid to the households', () {
      final simulation = Simulation.newGame(
        paid,
        seed: 1,
        systems: quietSystems,
      );
      List<(PartyType, Money)> wages(TickResult day) => [
        for (final entry in day.entries)
          if (entry.reason == EntryReason.wages &&
              entry.debit == AccountKind.cash)
            (entry.party.type, entry.amount),
      ];
      // Four slots of one staff at 20.00, at each store.
      expect(wages(simulation.step()), [
        (PartyType.households, Money.parse('80.00')),
        (PartyType.households, Money.parse('80.00')),
      ]);
      simulation.submit(
        SetStaffing(player, store: playerStore, staff: const [2, 0, 0, 0]),
      );
      expect(wages(simulation.step()).first.$2, Money.parse('40.00'));
    });

    test('a store with no staff gets no shoppers', () {
      final simulation = Simulation.newGame(paid, seed: 1)
        ..submit(
          SetStaffing(player, store: playerStore, staff: const [0, 0, 0, 0]),
        );
      final visits = advance(simulation, 10).map((d) => d.attribution.visits);
      expect(visits.map((v) => v[playerStore.index]), everyElement(0));
      expect(
        visits.map((v) => v[rivalStore.index]).reduce((a, b) => a + b),
        greaterThan(0),
      );
    });

    test('service falls when shoppers outnumber what staff can serve', () {
      final simulation = Simulation.newGame(paid, seed: 1);
      final rivalShop = simulation.world.stores[rivalStore.index];
      advance(simulation, 5);
      final traffic = List.of(rivalShop.traffic);
      expect(traffic.reduce((a, b) => a + b), greaterThan(0));
      simulation.step();
      // One staff serves two shoppers a slot.
      expect(rivalShop.service, [
        for (final visits in traffic)
          visits <= 2 ? Fx.one : Fx.raw(2 * Fx.scale ~/ visits),
      ]);
      expect(rivalShop.service.any((s) => s < Fx.one), isTrue);
      final sales = simulation
          .observe(rival)
          .companies
          .single
          .stores
          .single
          .sales;
      expect(sales.visits(DaySlot.values[0], 28), greaterThan(0));
    });
  });

  group('research', () {
    test('buys estimates within the paid-for error, seen by the buyer', () {
      final simulation = Simulation.newGame(testScenarioContent(), seed: 1);
      runScripted(simulation, 30);
      simulation
        ..submit(
          BuyResearch(
            player,
            company: playerCompany,
            market: MarketId(0),
            tier: ResearchTierId(0),
          ),
        )
        ..submit(
          BuyResearch(
            player,
            company: playerCompany,
            market: MarketId(0),
            tier: ResearchTierId(5),
          ),
        );
      final result = simulation.step();
      expect(result.rejections.single.reason.key, 'unknownResearch');
      final services = simulation.world.services.accounts[AccountKind.cash];
      expect(services, Money.parse('50.00'));
      final report = simulation.observe(player).reports.single;
      expect(simulation.observe(rival).reports, isEmpty);
      expect(report.asOf, start + 30);
      final regulars = report.segments.single;
      // 60 households and 0.5 units a day, each off by up to 10%.
      expect(regulars.households, inInclusiveRange(54, 66));
      expect(
        regulars.dailyUnits.single.raw,
        inInclusiveRange(Fx.parse('0.45').raw, Fx.parse('0.55').raw),
      );
      expect(report.unitShares.map((s) => s.store), [playerStore, rivalStore]);
      final total = report.unitShares.fold(0, (sum, s) => sum + s.share.raw);
      expect(total, inInclusiveRange(Fx.parse('0.9').raw, Fx.parse('1.1').raw));
    });
  });
}

ContentDb testScenarioContent() => loadScenario(testScenarioJson);
