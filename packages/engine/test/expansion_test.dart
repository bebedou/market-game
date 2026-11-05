import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

void main() {
  final content = loadScenario(testScenarioJson);
  final start = content.startDay;

  group('enlarging a store', () {
    test('is paid at once and adds space when the works finish', () {
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: quietSystems,
      )..submit(ExpandStore(player, store: playerStore));
      final paid = simulation.step().entries.where(
        (entry) => entry.reason == EntryReason.expansion,
      );
      // 20 m² at 10.00, to the landlords, as a fit-out cost.
      expect(paid.map((e) => (e.party.type, e.debit, e.amount)), [
        (PartyType.company, AccountKind.openingCosts, Money.parse('200.00')),
        (PartyType.landlords, AccountKind.cash, Money.parse('200.00')),
      ]);
      StoreView store() =>
          simulation.observe(player).companies.single.stores.single;
      expect(store().works, (area: 120, done: start + 3, format: null));
      expect((store().area, store().shelfSlots), (100, 2));

      advance(simulation, 3); // the works finish on day 3
      expect(store().works, isNull);
      expect(store().area, 120);
      expect(store().shelfSlots, 3);
      expect(store().storageUnits, 500);
      expect(store().enlargedOn, start + 3);
      expect(simulation.observe(rival).shelves[playerStore.index].area, 120);
    });

    test('is refused beyond the site, during works, or without the cash', () {
      final poor = loadScenario(
        testScenarioJson.replaceFirst(
          '"cash": "500.00" }',
          '"cash": "150.00" }',
        ),
      );
      final broke = Simulation.newGame(poor, seed: 1, systems: quietSystems)
        ..submit(ExpandStore(player, store: playerStore));
      expect(
        broke.step().rejections.single.reason.key,
        'cannotPayWorks',
      );

      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: quietSystems,
      );
      simulation
        ..submit(ExpandStore(player, store: playerStore))
        ..submit(ExpandStore(player, store: playerStore))
        ..submit(ExpandStore(player, store: rivalStore));
      expect(simulation.step().rejections.map((r) => r.reason.key), [
        'alreadyEnlarging',
        'notYourStore',
      ]);
      advance(simulation, 3);
      simulation.submit(ExpandStore(player, store: playerStore));
      expect(simulation.step().rejections, isEmpty); // 140 m², the most
      advance(simulation, 3);
      simulation.submit(ExpandStore(player, store: playerStore));
      expect(
        simulation.step().rejections.single.reason.key,
        'noRoomToGrow',
      );
    });

    test('raises the rent in proportion to the area', () {
      final rich = loadScenario(
        testScenarioJson.replaceFirst(
          '"cash": "500.00" }',
          '"cash": "2000.00" }',
        ),
      );
      final simulation =
          Simulation.newGame(rich, seed: 1, systems: quietSystems)..submit(
            OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
          );
      advance(simulation, 6);
      simulation.submit(ExpandStore(player, store: StoreId(2)));
      final rents = [
        for (final day in advance(simulation, 40))
          for (final entry in day.entries)
            if (entry.reason == EntryReason.rent &&
                entry.debit == AccountKind.rent)
              entry.amount,
      ];
      // February's rent, for 100 m² of a site that charges 100.00 for 80.
      expect(rents, [Money.parse('125.00')]);
    });

    test('ends with the store', () {
      final simulation =
          Simulation.newGame(content, seed: 1, systems: quietSystems)
            ..submit(ExpandStore(player, store: playerStore))
            ..step()
            ..submit(CloseStore(player, store: playerStore))
            ..step();
      expect(simulation.world.stores[playerStore.index].works, isNull);
    });
  });

  test('bigger stores draw more shoppers, and say so', () {
    // The same two stores and prices, with shoppers who like size.
    final likesSize = testScenarioJson
        .replaceFirst('"sizeWeight": "0"', '"sizeWeight": "3"')
        .replaceAll('"location": "0.60"', '"location": "0.50"');
    final equal = loadScenario(likesSize);
    final bigger = loadScenario(
      likesSize.replaceFirst(
        '"area": 100, "maxArea": 140 },\n    { "id": "lane"',
        '"area": 400, "maxArea": 400 },\n    { "id": "lane"',
      ),
    );
    expect(bigger.sites[square.index].area, 400);
    (int, int) trips(ContentDb content) {
      final simulation = Simulation.newGame(content, seed: 4);
      var player = 0;
      var rival = 0;
      for (final day in advance(simulation, 20)) {
        player += day.attribution.visits[playerStore.index];
        rival += day.attribution.visits[rivalStore.index];
      }
      return (player, rival);
    }

    final (playerEqual, rivalEqual) = trips(equal);
    final (playerSmaller, rivalBigger) = trips(bigger);
    expect(rivalBigger * playerEqual, greaterThan(rivalEqual * playerSmaller));

    // With stocked shelves, households form habits, and leave them.
    final simulation = Simulation.newGame(bigger, seed: 4);
    final days = [
      for (var i = 0; i < 40; i++)
        (simulation..submitAll(scriptedCommands(simulation.today))).step(),
    ];
    final causes = {
      for (final day in days)
        for (final MapEntry(:key) in day.attribution.switches.entries)
          if (key.to == rivalStore) key.cause,
    };
    expect(causes, contains(SwitchCause.size));
  });

  test('AI owners enlarge full stores that pay back, by the same rules', () {
    final growing = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"cash": "2000.00" }',
            '"cash": "2000.00", "strategy": "steady" }',
          )
          .replaceFirst(
            '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
            '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
          )
          .replaceFirst('"cash": "800.00" }', '"cash": "5000.00" }'),
    );
    expect(growing.strategies.single.expansionPaybackMonths, 60);
    final simulation = Simulation.newGame(growing, seed: 1);
    final enlargements = <Day>[];
    for (final day in advance(simulation, 120)) {
      for (final entry in day.entries) {
        if (entry.reason == EntryReason.expansion &&
            entry.party.type == PartyType.company) {
          enlargements.add(day.day);
        }
      }
    }
    // The rival's one slot is full and organic milk waits: it grows on the
    // first of a month, one step at a time, up to the site's 140 m².
    expect(enlargements, isNotEmpty);
    expect(enlargements.every((day) => day.isFirstOfMonth), isTrue);
    final store = simulation.world.stores[rivalStore.index];
    expect(store.area, greaterThan(100));
    expect(store.shelfSlots, greaterThan(1));
    expect(simulation.world.stores[playerStore.index].area, 100);
  });
}

extension on Simulation {
  void submitAll(List<Command> commands) => commands.forEach(submit);
}
