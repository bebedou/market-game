import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/systems/taxes.dart';
import 'package:engine/src/systems/tick_system.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with a labour market, in a slump with an output gap of
/// [gap], wages slowed by [phillips] for each point of excess unemployment.
String withLabour({
  String gap = '-0.03',
  String phillips = '0.5',
}) => testScenarioJson
    .replaceFirst(
      '"retailFeedback": "0",',
      '"retailFeedback": "0",\n    "labour": { "naturalUnemployment": "0.075", '
          '"okunCoefficient": "2", "adjustment": "0.25", '
          '"phillipsSlope": "$phillips", "confidence": "2" },',
    )
    .replaceFirst('"outputGap": "0"', '"outputGap": "$gap"')
    .replaceFirst('"realWageGrowth": "0"', '"realWageGrowth": "0.02"');

/// The test scenario with French taxes.
final taxedJson = testScenarioJson.replaceFirst(
  '"categories": [{ "id": "milk", "name": "Milk" }],',
  '"taxes": { "reducedRate": "0.15", "reducedLimit": "100.00", '
      '"corporateRate": "0.25", "dividendRate": "0.30" },\n'
      '  "categories": [{ "id": "milk", "name": "Milk" }],',
);

/// Scripted demand with the year-end taxes.
const taxedSystems = <TickSystem>[TaxSystem(), ...testSystems];

void main() {
  group('labour market', () {
    test("unemployment heads for Okun's target in a slump, holding wages "
        'back', () {
      final content = loadScenario(withLabour());
      final labour = content.macro.labour!;
      expect(labour.naturalUnemployment, Fx.parse('0.075'));
      // A 3% gap over Okun's 2 adds a point and a half.
      expect(labour.unemploymentTarget(Fx.parse('-0.03')), Fx.parse('0.09'));
      final slump = Simulation.newGame(content, seed: 1);
      expect(slump.world.macro.unemployment, Fx.parse('0.075'));
      for (var i = 0; i < 400; i++) {
        slump.step();
      }
      final unemployment = slump.world.macro.unemployment;
      expect(unemployment.raw, inInclusiveRange(890, 900));
      // Without the Phillips curve, wages grow faster.
      final loose = Simulation.newGame(
        loadScenario(withLabour(phillips: '0')),
        seed: 1,
      );
      for (var i = 0; i < 400; i++) {
        loose.step();
      }
      expect(
        slump.world.macro.wageIndex.raw,
        lessThan(loose.world.macro.wageIndex.raw),
      );
      // Twice the excess unemployment off spending.
      expect(
        labour.confidenceFactor(unemployment).raw,
        inInclusiveRange(9700, 9720),
      );
    });

    test('a save from before starts at the natural rate', () {
      final old = Simulation.newGame(loadScenario(testScenarioJson), seed: 1);
      old.step();
      final grown = Simulation.load(loadScenario(withLabour()), old.save());
      expect(grown.world.macro.unemployment, Fx.parse('0.075'));
    });

    test('the economy is recorded month by month for everyone', () {
      final simulation = Simulation.newGame(
        loadScenario(withLabour()),
        seed: 1,
      );
      for (var i = 0; i < 100; i++) {
        simulation.step();
      }
      final history = simulation.observe(player).history;
      expect(history.map((m) => m.day.date.month), [2, 3, 4]);
      expect(history.last.unemployment, simulation.world.macro.unemployment);
    });
  });

  group('taxes', () {
    test("the year's profit is taxed in January, losses carried forward, "
        'and every company files its accounts', () {
      final content = loadScenario(taxedJson);
      expect(content.taxes!.corporateRate, Fx.parse('0.25'));
      // 15% of the first 100.00, 25% of the rest.
      expect(
        content.taxes!.corporateTax(Money.parse('300.00'), Fx.one),
        Money.parse('65.00'),
      );
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: taxedSystems,
      );
      runScripted(simulation, 365);
      final view = simulation.observe(player);
      final playerYear = simulation
          .reports(playerCompany, ReportPeriod.month)
          .where((r) => r.start.date.year == 2026)
          .fold(Money.zero, (sum, r) => sum + r.profit);
      simulation.step();
      final filings = simulation.observe(player).filings;
      expect(filings.map((f) => f.year), everyElement(2026));
      expect(filings.map((f) => f.company), [playerCompany, CompanyId(1)]);
      final filed = filings.first;
      expect(filed.profit, playerYear);
      expect(filed.stores, 1);
      expect(filed.revenue.cents, greaterThan(0));
      final company = simulation.world.companies[playerCompany.index];
      final taxed = company.accounts[AccountKind.taxes];
      expect(
        view.companies.single.taxAccrued,
        taxed,
        reason: 'the cushion held the bill before it came',
      );
      if (playerYear > Money.zero) {
        expect(taxed, content.taxes!.corporateTax(playerYear, Fx.one));
        expect(company.lossCarried, Money.zero);
      } else {
        expect(taxed, Money.zero);
        expect(company.lossCarried, -playerYear);
      }
      expect(view.macro.unemployment, Fx.zero);
      expect(invariantViolations(simulation.world), isEmpty);
    });

    test('dividends are taxed at the flat rate', () {
      final content = loadScenario(taxedJson);
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: taxedSystems,
      );
      runScripted(simulation, 120);
      final before =
          simulation.world.persons[player.index].accounts[AccountKind.cash];
      final kept = simulation.observe(player).companies.single.retainedEarnings;
      expect(kept.cents, greaterThan(1000));
      simulation
        ..submit(
          PayDividend(
            player,
            company: playerCompany,
            amount: Money.parse('10.00'),
          ),
        )
        ..step();
      final world = simulation.world;
      expect(
        world.persons[player.index].accounts[AccountKind.cash] - before,
        Money.parse('7.00'),
      );
      expect(world.government.accounts[AccountKind.cash], Money.parse('3.00'));
      expect(invariantViolations(world), isEmpty);
    });
  });
}
