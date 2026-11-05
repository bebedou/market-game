import 'package:engine/engine.dart';
import 'package:engine/src/core/rng.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/policies/manager.dart';
import 'package:engine/src/policies/retail_policy.dart' show Judgment;
import 'package:test/test.dart';

import 'support/fixtures.dart';

const clerk = ManagerGradeId(0);
const ace = ManagerGradeId(1);
const everything = [true, true, true, true, true];

HireManager hire({
  ManagerGradeId grade = ace,
  List<bool> duties = everything,
  StoreId store = playerStore,
  StrategyId strategy = steady,
}) => HireManager(
  player,
  store: store,
  grade: grade,
  strategy: strategy,
  duties: duties,
);

void main() {
  final content = loadScenario(testScenarioJson);
  final start = content.startDay;

  test('loads the grades on offer', () {
    expect(content.managers.grades.map((grade) => grade.key), ['clerk', 'ace']);
    expect(content.managers.grades.first.skill, Fx.parse('0.50'));
    expect(content.managers.forecastError, Fx.parse('0.50'));
  });

  test('are hired, rebriefed and fired by the owner', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final invalid = {
      hire(grade: const ManagerGradeId(5)): 'unknownManagerGrade',
      hire(strategy: const StrategyId(3)): 'unknownStrategy',
      hire(duties: const [true]): 'eachDuty',
      hire(duties: const [false, false, false, false, false]):
          'managerNeedsDuty',
      hire(store: rivalStore): 'notYourStore',
      FireManager(player, store: playerStore): 'noManager',
    };
    invalid.keys.forEach(simulation.submit);
    simulation.submit(hire(grade: clerk));
    final result = simulation.step();
    expect({
      for (final rejection in result.rejections)
        rejection.command: rejection.reason.key,
    }, invalid);
    ManagerView? manager() =>
        simulation.observe(player).companies.single.stores.single.manager;
    expect(manager()?.grade, clerk);
    expect(manager()?.hiredOn, start);

    simulation
      ..submit(
        hire(grade: clerk, duties: const [false, true, false, false, false]),
      )
      ..step();
    expect(manager()?.duties, [false, true, false, false, false]);
    expect(manager()?.hiredOn, start, reason: 'the same manager, rebriefed');
    simulation
      ..submit(hire())
      ..step();
    expect(manager()?.hiredOn, start + 2, reason: 'a new manager');
    simulation
      ..submit(FireManager(player, store: playerStore))
      ..step();
    expect(manager(), isNull);
  });

  test('are paid daily, at the wage index, to the households', () {
    final simulation =
        Simulation.newGame(content, seed: 1, systems: quietSystems)..submit(
          hire(grade: clerk, duties: const [false, true, false, false, false]),
        );
    List<JournalEntry> salaries(TickResult day) => [
      for (final entry in day.entries)
        if (entry.reason == EntryReason.salary) entry,
    ];
    final paid = salaries(simulation.step());
    expect(paid.map((entry) => (entry.party.type, entry.debit, entry.amount)), [
      (PartyType.company, AccountKind.salaries, Money.parse('5.00')),
      // Billed, then paid the same day.
      (PartyType.company, AccountKind.payables, Money.parse('5.00')),
      (PartyType.households, AccountKind.cash, Money.parse('5.00')),
    ]);
    simulation
      ..submit(FireManager(player, store: playerStore))
      ..step();
    expect(salaries(simulation.step()), isEmpty);
    final report = simulation.reports(playerCompany, ReportPeriod.week).first;
    expect(report.flow(AccountKind.salaries), Money.parse('5.00'));
  });

  test('of full skill decide just as the owner\'s policy would', () {
    final simulation = Simulation.newGame(content, seed: 1)
      ..submit(hire())
      ..step();
    for (var i = 0; i < 20; i++) {
      final view = simulation.observe(player);
      final managed = manage(
        view,
        content,
        (entity) => Rng.keyed(1, RngStream.manager, 0, entity),
      );
      final owned = RetailPolicy(content.strategies.single)
          .decide(view, content)
          .where(
            (command) => command is! PayDividend && command is! InjectCapital,
          );
      expect(
        managed.map((c) => c.toString()).toSet(),
        owned.map((c) => c.toString()).toSet(),
        reason: 'day $i',
      );
      simulation.step();
    }
  });

  test('stick to their duties', () {
    final simulation = Simulation.newGame(content, seed: 1)
      ..submit(hire(duties: const [false, true, false, false, false]))
      ..step();
    final pricing = <Type>{};
    for (var i = 0; i < 30; i++) {
      final view = simulation.observe(player);
      pricing.addAll([
        for (final command in manage(
          view,
          content,
          (entity) => Rng.keyed(1, RngStream.manager, 0, entity),
        ))
          command.runtimeType,
      ]);
      simulation.step();
    }
    expect(pricing, {SetPrice});
  });

  test('enlarge the store as an owner would, only if trusted to', () {
    final growing = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
            '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
          )
          .replaceFirst('"cash": "500.00" }', '"cash": "5000.00" }')
          // One slot, filled, and organic milk waiting.
          .replaceFirst(
            '"shelfSlots": 2, "storageUnits": 400',
            '"shelfSlots": 1, "storageUnits": 400',
          )
          .replaceFirst(
            '"milk_budget": "0.95", "milk_premium": "1.69"',
            '"milk_budget": "0.95"',
          ),
    );
    int area(List<bool> duties) {
      final simulation = Simulation.newGame(growing, seed: 1)
        ..submit(hire(duties: duties));
      for (var i = 0; i < 120; i++) {
        simulation.step();
      }
      return simulation.world.stores[playerStore.index].area;
    }

    expect(area(everything), greaterThan(100));
    expect(area(const [true, true, true, true, false]), 100);
  });

  test('market at the share that pays, the strategy share before any sales',
      () {
    final marketed = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"openingTraffic": 10',
            '"openingTraffic": 10, "marketingShare": "0.02"',
          )
          .replaceFirst(
            '"offHoursPenalty": "1.5", "halfSizeArea": 100 }',
            '"offHoursPenalty": "1.5", "halfSizeArea": 100, '
                '"marketingWeight": "1.2", "halfGoodwill": "20.00" }',
          )
          // An unpaid ace, so the small shop's margin isn't all salary.
          .replaceFirst('"salary": "9.00"', '"salary": "0.00"'),
    );
    final simulation = Simulation.newGame(marketed, seed: 1)
      ..submit(SetMarketing(player, store: playerStore, share: Fx.parse('0.20')))
      ..submit(hire());
    Fx share() => simulation.world.stores[playerStore.index].marketingShare;
    simulation.step();
    expect(share(), Fx.parse('0.20'), reason: 'the owner set it');
    for (var i = 0; i < 30; i++) {
      simulation.step();
    }
    expect(share().raw, greaterThan(Fx.parse('0.02').raw));
    expect(share().raw, lessThanOrEqualTo(Fx.parse('0.08').raw));
    expect(share().raw % 50, 0, reason: 'in half percents');
  });

  test('read briefs from before investing with it off', () {
    final writer = StateWriter();
    hire(duties: const [true, true, true, true]).write(writer);
    final read = Command.read(StateReader(writer.toBytes())) as HireManager;
    expect(read.duties, [true, true, true, true, false]);
  });

  test('misjudge by up to their share of the error, differently by store', () {
    final store = Simulation.newGame(
      content,
      seed: 1,
    ).observe(player).companies.single.stores.single;
    final clerkGrade = content.managers.grades[clerk.index];
    Judgment judge(int week, ManagerGradeDef grade) => misjudgment(
      content,
      store,
      grade,
      (entity) => Rng.keyed(1, RngStream.manager, week, entity),
    );
    final factors = <Fx>[];
    for (var week = 0; week < 50; week++) {
      final judgment = judge(week * 7, clerkGrade);
      // Skill 0.5 halves the scenario's 50% forecast and 20% price errors.
      for (final factor in [...judgment.demand, judgment.traffic]) {
        expect(factor.raw, inInclusiveRange(7500, 12500));
        factors.add(factor);
      }
      for (final factor in judgment.price) {
        expect(factor.raw, inInclusiveRange(9000, 11000));
      }
    }
    expect(factors.toSet().length, greaterThan(100));
    final exact = judge(0, content.managers.grades[ace.index]);
    expect([
      ...exact.demand,
      ...exact.price,
      exact.traffic,
    ], everyElement(Fx.one));
  });

  test('restock the store, unlogged, and replay to the same world', () {
    final simulation = Simulation.newGame(content, seed: 3)
      ..submit(hire(grade: clerk));
    for (var i = 0; i < 60; i++) {
      simulation.step();
    }
    final world = simulation.world;
    expect(simulation.commandLog.map((entry) => entry.command), [
      isA<HireManager>(),
    ]);
    final sold = simulation
        .observe(player)
        .companies
        .single
        .stores
        .single
        .sales
        .total(SalesCount.sold, milkBudget, 28);
    expect(
      sold,
      greaterThan(0),
      reason: 'the manager kept the shelves stocked',
    );
    expect(world.stores[playerStore.index].manager?.grade, clerk);

    final save = simulation.save();
    expect(
      Simulation.replay(content, save).stateHash(),
      simulation.stateHash(),
    );
    expect(Simulation.load(content, save).stateHash(), simulation.stateHash());
  });

  test('leave with the store when it closes', () {
    final simulation =
        Simulation.newGame(content, seed: 1, systems: quietSystems)
          ..submit(hire(grade: clerk))
          ..step()
          ..submit(CloseStore(player, store: playerStore))
          ..step();
    expect(simulation.world.stores[playerStore.index].manager, isNull);
    expect(
      simulation.step().entries.where((e) => e.reason == EntryReason.salary),
      isEmpty,
    );
  });
}
