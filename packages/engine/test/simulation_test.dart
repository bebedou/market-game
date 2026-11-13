import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final content = loadScenario(testScenarioJson);

  Simulation newGame({int seed = 1}) => Simulation.newGame(content, seed: seed);

  Simulation loadGame(SaveFile file) => Simulation.load(content, file);

  test('a new game starts on the scenario start date', () {
    final simulation = newGame();
    expect(simulation.today, Day.parse('2026-01-01'));
    simulation.step();
    expect(simulation.today, Day.parse('2026-01-02'));
  });

  test(
    'the same seed and commands give the same state; another seed differs',
    () {
      final a = newGame(), b = newGame(), c = newGame(seed: 2);
      for (final simulation in [a, b, c]) {
        runScripted(simulation, 100);
      }
      expect(a.stateHash(), b.stateHash());
      expect(a.stateHash(), isNot(c.stateHash()));
    },
  );

  group('commands', () {
    test('apply at the next step, not when submitted', () {
      final simulation = newGame();
      final price = simulation.world.stores[playerStore.index].prices;
      simulation.submit(
        SetPrice(
          player,
          store: playerStore,
          product: milkBudget,
          price: Money(123),
        ),
      );
      expect(price[milkBudget.index], Money(95));
      final result = simulation.step();
      expect(result.rejections, isEmpty);
      expect(price[milkBudget.index], Money(123));
    });

    test('are rejected with a reason when invalid', () {
      final simulation = newGame();
      final invalid = {
        SetPrice(
          player,
          store: rivalStore,
          product: milkBudget,
          price: Money(1),
        ): 'notYourStore',
        SetPrice(
          rival,
          store: rivalStore,
          product: milkPremium,
          price: Money(1),
        ): 'notListed',
        SetPrice(
          player,
          store: playerStore,
          product: milkBudget,
          price: Money(0),
        ): 'priceNotPositive',
        SetPrice(
          player,
          store: StoreId(9),
          product: milkBudget,
          price: Money(1),
        ): 'unknownStore',
        SetPrice(
          PersonId(9),
          store: playerStore,
          product: milkBudget,
          price: Money(1),
        ): 'unknownActor',
      };
      invalid.keys.forEach(simulation.submit);
      final reasons = {
        for (final rejection in simulation.step().rejections)
          rejection.command: rejection.reason.key,
      };
      expect(reasons, invalid);
    });

    test('apply in actor order, then submission order', () {
      final simulation = newGame();
      final rivalCommand = SetPrice(
        rival,
        store: rivalStore,
        product: milkBudget,
        price: Money(90),
      );
      final first = SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(91),
      );
      final second = SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(92),
      );
      simulation
        ..submit(rivalCommand)
        ..submit(first)
        ..submit(second)
        ..step();
      expect(simulation.commandLog.map((entry) => entry.command), [
        first,
        second,
        rivalCommand,
      ]);
      expect(
        simulation.world.stores[playerStore.index].prices[milkBudget.index],
        Money(92),
      );
    });
  });

  group('saves', () {
    test('continue identically after save and load mid-run', () {
      final straight = newGame();
      runScripted(straight, 365);

      final interrupted = newGame();
      runScripted(interrupted, 180);
      final resumed = loadGame(interrupted.save());
      runScripted(resumed, 185);

      expect(resumed.today, straight.today);
      expect(resumed.stateHash(), straight.stateHash());
    });

    test('keep commands queued for the next step', () {
      final straight = newGame();
      final interrupted = newGame();
      for (final simulation in [straight, interrupted]) {
        runScripted(simulation, 10);
        simulation.submit(
          SetPrice(
            player,
            store: playerStore,
            product: milkBudget,
            price: Money(77),
          ),
        );
      }
      straight.step();
      final resumed = loadGame(interrupted.save())..step();
      expect(resumed.stateHash(), straight.stateHash());
    });

    test('replay from seed and command log to the same state', () {
      final original = newGame(seed: 42);
      runScripted(original, 365);
      final file = original.save();

      final replayed = Simulation.replay(content, file);

      expect(replayed.today, original.today);
      expect(replayed.stateHash(), original.stateHash());
      expect(replayed.save().bytes, file.bytes);
    });

    test('round-trip to identical bytes', () {
      final simulation = newGame();
      runScripted(simulation, 50);
      final file = simulation.save();
      expect(loadGame(file).save().bytes, file.bytes);
    });

    test('load with retuned content but refuse other structures, damaged '
        'files and non-saves', () {
      final simulation = newGame();
      runScripted(simulation, 20);
      final bytes = simulation.save().bytes;
      final retuned = loadScenario(
        testScenarioJson
            .replaceFirst('"Town"', '"City"')
            .replaceFirst('"baseCost": "0.55"', '"baseCost": "0.60"'),
      );
      expect(Simulation.load(retuned, SaveFile(bytes)).today, simulation.today);
      final restructured = loadScenario(
        testScenarioJson.replaceAll('"town"', '"city"'),
      );
      expect(
        () => Simulation.load(restructured, SaveFile(bytes)),
        throwsFormatException,
      );
      expect(
        () => Simulation.load(
          content,
          SaveFile(Uint8List.sublistView(bytes, 0, bytes.length - 3)),
        ),
        throwsFormatException,
      );
      expect(
        () => Simulation.load(content, SaveFile(Uint8List.fromList([1, 2, 3]))),
        throwsFormatException,
      );
    });
  });

  test('a scripted year produces the committed state hash', () {
    final simulation = newGame(seed: 20261026);
    runScripted(simulation, 365);
    expect(simulation.stateHash(), 0xcba8f4a0);
  });
}
