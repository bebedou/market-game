import 'dart:io';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with [growth] for its one segment, and [migration] in
/// its one regime.
ContentDb withPopulation({String growth = '0', String migration = '0'}) =>
    loadScenario(
      testScenarioJson
          .replaceFirst(
            '"households": { "regulars": 60 } }',
            '"households": { "regulars": 60 }, '
                '"growth": { "regulars": "$growth" } }',
          )
          .replaceFirst(
            '"demand": "1", "premiumShift": "0" }',
            '"demand": "1", "premiumShift": "0", "migration": "$migration" }',
          ),
    );

int households(Simulation simulation) =>
    simulation.world.cohorts.fold(0, (sum, cohort) => sum + cohort.weight);

void main() {
  final start = loadScenario(testScenarioJson).startDay;

  test('loads growth, migration and cohort counts, zero by default', () {
    final plain = loadScenario(testScenarioJson);
    expect(plain.markets.single.growth, [Fx.zero]);
    expect(plain.markets.single.agents, isNull);
    expect(plain.macro.regimes.single.migration, Fx.zero);
    final growing = withPopulation(growth: '0.02', migration: '-0.01');
    expect(growing.markets.single.growth, [Fx.parse('0.02')]);
    expect(growing.macro.regimes.single.migration, Fx.parse('-0.01'));
    expect(
      () => withPopulation(growth: '0.9'),
      throwsA(
        isA<ContentException>().having(
          (e) => e.path,
          'path',
          'markets[0].growth.regulars',
        ),
      ),
    );
    expect(
      () => loadScenario(
        testScenarioJson.replaceFirst(
          '"households": { "regulars": 60 } }',
          '"households": { "regulars": 60 }, "agents": 61 }',
        ),
      ),
      throwsA(
        isA<ContentException>().having(
          (e) => e.path,
          'path',
          'markets[0].agents',
        ),
      ),
    );
  });

  test('fewer cohorts can stand for the same households', () {
    ContentDb withAgents(int agents) => loadScenario(
      testScenarioJson.replaceFirst(
        '"households": { "regulars": 60 } }',
        '"households": { "regulars": 60 }, "agents": $agents }',
      ),
    );
    final twenty = Simulation.newGame(withAgents(20), seed: 1).world.cohorts;
    expect(twenty.map((cohort) => cohort.weight), everyElement(3));
    final quarter = Simulation.newGame(withAgents(25), seed: 1).world.cohorts;
    expect(quarter, hasLength(25));
    expect(quarter.map((c) => c.weight).toSet(), {2, 3});
    expect(quarter.fold(0, (sum, c) => sum + c.weight), 60);
  });

  test(
    'a cohort shops for all its households, and an empty one not at all',
    () {
      final content = loadScenario(testScenarioJson);
      final grouped = Simulation.newGame(content, seed: 2);
      for (final cohort in grouped.world.cohorts) {
        cohort.weight = 3;
      }
      final empty = Simulation.newGame(content, seed: 2);
      for (final cohort in empty.world.cohorts) {
        cohort.weight = 0;
      }
      for (var day = 0; day < 30; day++) {
        for (final simulation in [grouped, empty]) {
          scriptedCommands(simulation.today).forEach(simulation.submit);
        }
        final trips = grouped.step().attribution;
        expect(trips.visits.every((visits) => visits % 3 == 0), isTrue);
        expect(trips.switches.values.every((count) => count % 3 == 0), isTrue);
        expect(empty.step().attribution.visits, everyElement(0));
      }
      expect(
        grouped.world.cohorts.expand((cohort) => cohort.needs),
        everyElement(predicate<Fx>((need) => !need.isNegative)),
      );
      expect(
        grouped
            .observe(player)
            .companies
            .single
            .stores
            .single
            .sales
            .dailyVisits
            .fold(0, (a, b) => a + b),
        greaterThan(0),
      );
    },
  );

  test('markets grow by their trend, a census every January', () {
    final simulation = Simulation.newGame(
      withPopulation(growth: '0.12'),
      seed: 1,
      systems: quietSystems,
    );
    final censuses = <CensusTaken>[];
    for (var day = 0; day < 366; day++) {
      censuses.addAll(simulation.step().events.whereType<CensusTaken>());
    }
    // 12% a year on 60 households, a month at a time, fractions carried.
    expect(households(simulation), 67);
    expect(censuses.single.households, 67);
    expect(censuses.single.previous, 60);
    final view = simulation.observe(player);
    expect(view.households, [67]);
    expect(view.censuses.single, [
      (day: start, households: 60),
      (day: Day.parse('2027-01-01'), households: 67),
    ]);
  });

  test('people leave in hard times, and the census lags behind', () {
    final simulation = Simulation.newGame(
      withPopulation(migration: '-0.24'),
      seed: 1,
      systems: quietSystems,
    );
    final counts = <int>[];
    while (simulation.today < Day.parse('2026-07-02')) {
      if (simulation.step().day.isFirstOfMonth) {
        counts.add(households(simulation));
      }
    }
    // Nothing on the first day; then 2% a month: 1.2 households, then a
    // little less each month, fractions carried.
    expect(counts, [60, 59, 58, 57, 56, 55, 54]);
    expect(simulation.world.cohorts.every((c) => c.weight >= 0), isTrue);
    expect(simulation.observe(player).households, [60]);
  });

  test('studies count the households cohorts stand for', () {
    final simulation = Simulation.newGame(
      withPopulation(growth: '0.30'),
      seed: 1,
    );
    runScripted(simulation, 200);
    simulation
      ..submit(
        BuyResearch(
          player,
          company: playerCompany,
          market: MarketId(0),
          tier: ResearchTierId(0),
        ),
      )
      ..step();
    final counted = households(simulation);
    expect(counted, greaterThan(60));
    final estimate = simulation
        .observe(player)
        .reports
        .single
        .segments
        .single
        .households;
    expect(estimate, inInclusiveRange(counted * 9 ~/ 10, counted * 11 ~/ 10));
  });

  // Reads the fixture from disk, which only the VM can.
  test('a save from format 6 loads and plays on', testOn: 'vm', () {
    final content = loadScenario(testScenarioJson);
    final old = SaveFile(File('test/fixtures/save_v6.bin').readAsBytesSync());
    final simulation = Simulation.load(content, old);
    expect(simulation.today, Day.parse('2026-02-10'));
    final view = simulation.observe(player);
    final company = view.companies.single;
    expect(company.cash, Money.parse('303.31'));
    expect(company.stores.single.area, 120);
    expect(company.stores.single.manager?.grade, ManagerGradeId(0));
    expect(simulation.world.cohorts.map((c) => c.weight), everyElement(1));
    expect(view.censuses.single, [
      (day: Day.parse('2026-02-10'), households: 60),
    ]);
    runScripted(simulation, 30);
    final resaved = simulation.save();
    expect(
      Simulation.load(content, resaved).stateHash(),
      simulation.stateHash(),
    );
  });
}
