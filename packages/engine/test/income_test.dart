import 'package:engine/engine.dart';
import 'package:engine/src/policies/retail_policy.dart';
import 'package:engine/src/state/cohort.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with households' incomes spread by [spread], and
/// [effect] of real wage changes reaching them.
String withIncomes({
  String spread = '0.8',
  String effect = '1',
}) => testScenarioJson
    .replaceFirst(
      '"serviceWeight": "1", "sizeWeight": "0" }',
      '"serviceWeight": "1", "sizeWeight": "0", "incomeSpread": "$spread" }',
    )
    .replaceFirst(
      '"halfSizeArea": 100 }',
      '"halfSizeArea": 100, "incomeEffect": "$effect" }',
    );

void main() {
  test('loads income spreads and effect, zero by default', () {
    final plain = loadScenario(testScenarioJson);
    expect(plain.segments.single.incomeSpread, Fx.zero);
    expect(plain.demand.incomeEffect, Fx.zero);
    final spread = loadScenario(withIncomes(spread: '0.4', effect: '0.5'));
    expect(spread.segments.single.incomeSpread, Fx.parse('0.4'));
    expect(spread.demand.incomeEffect, Fx.parse('0.5'));
    expect(
      () => loadScenario(withIncomes(spread: '0.95')),
      throwsA(
        isA<ContentException>().having(
          (e) => e.path,
          'path',
          'segments[0].incomeSpread',
        ),
      ),
    );
  });

  test('incomes spread evenly around the average, and purchasing power '
      'follows real wages', () {
    final segment = loadScenario(withIncomes(spread: '0.4')).segments.single;
    expect(segment.relativeIncome(Fx.zero), Fx.parse('0.6'));
    expect(segment.relativeIncome(Fx.parse('0.5')), Fx.one);
    expect(segment.relativeIncome(Fx.one), Fx.parse('1.4'));
    final demand = loadScenario(withIncomes(effect: '0.5')).demand;
    // Wages 10% ahead of prices; half of it reaches households.
    expect(
      demand.purchasingPower(Fx.parse('1.21'), Fx.parse('1.1')),
      Fx.parse('1.05'),
    );
  });

  test(
    'ranks follow from the seed, and survive a save without being in it',
    () {
      final content = loadScenario(withIncomes());
      final simulation = Simulation.newGame(content, seed: 3);
      final ranks = [for (final c in simulation.world.cohorts) c.incomeRank];
      expect(ranks.toSet().length, greaterThan(50));
      expect(
        ranks,
        everyElement(predicate<Fx>((r) => r >= Fx.zero && r < Fx.one)),
      );
      expect(ranks.first, HouseholdCohort.rankFor(3, CohortId(0)));
      final loaded = Simulation.load(content, simulation.save());
      expect([for (final c in loaded.world.cohorts) c.incomeRank], ranks);
    },
  );

  test('richer households stick with a dearer store', () {
    // Both stores sell only budget milk, the player's dearer; both restock
    // as in the script, but nobody reprices.
    final simulation = Simulation.newGame(loadScenario(withIncomes()), seed: 5)
      ..submit(DelistProduct(player, store: playerStore, product: milkPremium))
      ..submit(
        SetPrice(
          player,
          store: playerStore,
          product: milkBudget,
          price: Money(110),
        ),
      );
    for (var day = 0; day < 120; day++) {
      scriptedCommands(
        simulation.today,
      ).whereType<PlaceOrder>().forEach(simulation.submit);
      simulation.step();
    }
    Fx loyalty(bool Function(HouseholdCohort) group) {
      final members = simulation.world.cohorts.where(group).toList();
      return Fx.raw(
        members.fold(0, (sum, c) => sum + c.loyalty[playerStore.index].raw) ~/
            members.length,
      );
    }

    final rich = loyalty((c) => c.incomeRank >= Fx.parse('0.75'));
    final poor = loyalty((c) => c.incomeRank < Fx.parse('0.25'));
    expect(rich.raw, greaterThan(poor.raw));
  });

  test('rising real wages make households trade up and mind price less', () {
    final content = loadScenario(
      withIncomes(
        spread: '0',
      ).replaceFirst('"realWageGrowth": "0"', '"realWageGrowth": "0.5"'),
    );
    final simulation = Simulation.newGame(content, seed: 1);
    BuyResearch study() => BuyResearch(
      player,
      company: playerCompany,
      market: MarketId(0),
      tier: ResearchTierId(0),
    );
    simulation
      ..submit(study())
      ..step();
    runScripted(simulation, 400);
    simulation
      ..submit(study())
      ..step();
    final [before, after] = simulation.observe(player).reports;
    // A year and more of 50% real wage growth: purchasing power about 1.6.
    expect(
      after.segments.single.premiumShare.single.raw,
      greaterThan(before.segments.single.premiumShare.single.raw * 13 ~/ 10),
    );
    expect(
      after.segments.single.priceSensitivity.raw,
      lessThan(before.segments.single.priceSensitivity.raw * 8 ~/ 10),
    );
  });

  test('owners hold dividends while they save for works that pay', () {
    // The rival's one slot is full and organic milk waits, so enlarging
    // pays; but the works cost more than it can spare at once.
    final content = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"cash": "2000.00" }',
            '"cash": "2000.00", "strategy": "steady" }',
          )
          .replaceFirst(
            '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
            '"expansionPaybackMonths": 120,\n      "expansionIntervalDays": 30',
          )
          .replaceFirst('"costPerSqm": "10.00"', '"costPerSqm": "40.00"'),
    );
    final simulation = Simulation.newGame(content, seed: 1);
    final strategy = content.strategies.single;
    Day? wanted;
    Day? enlarged;
    final dividends = <Day>[];
    for (var day = 0; day < 400 && enlarged == null; day++) {
      final view = simulation.observe(rival);
      if (wanted == null && view.today.isFirstOfMonth) {
        final company = view.companies.single;
        final plan = StorePlan(
          strategy,
          content,
          view,
          company,
          company.stores.single,
        );
        if (plan.enlargementCost() != null) wanted = view.today;
      }
      for (final entry in simulation.step().entries) {
        if (entry.party.type != PartyType.company || entry.party.index != 1) {
          continue;
        }
        if (entry.reason == EntryReason.dividend) dividends.add(entry.day);
        if (entry.reason == EntryReason.expansion) enlarged = entry.day;
      }
    }
    expect(wanted, isNotNull);
    expect(enlarged, isNotNull);
    expect(enlarged! > wanted!, isTrue, reason: 'it had to save first');
    expect(
      dividends.where((day) => day >= wanted! && day <= enlarged!),
      isEmpty,
    );
  });
}
