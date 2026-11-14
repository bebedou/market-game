import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/labs.dart';
import 'package:engine/src/state/talent.dart';
import 'package:engine/src/systems/labs.dart';
import 'package:test/test.dart';

import 'factories_test.dart'
    show dairy, factoryJson, factorySystems, first, home;
import 'support/fixtures.dart';

/// The dairy's scenario with labs: a generation takes 100 of work and adds
/// ten points exactly, a tenth of every lead goes each month, and people
/// are either ordinary (no power, 30 a month) or strong (they double the
/// lab, 60 a month). Shoppers think a point of quality worth half a point
/// of price.
String labJson() => factoryJson(shiftUnits: 60)
    .replaceFirst(
      '"maxShifts": 3,',
      '"maxShifts": 3, "labs": { "generationWork": "100.00", '
          '"leadHardness": "1", "gain": "0.10", "gainSpread": "0", '
          '"saving": "0.05", "maxSaving": "0.20", "catchUp": "0.10", '
          '"maxBudget": "50.00", "maxPeople": 2, "candidates": 3, '
          '"candidateDays": 60, "revealMonths": 2, "nationalPull": "2", '
          '"levels": [ { "share": "0.50", "power": "0", "salary": "30.00" }, '
          '{ "share": "0.50", "power": "1", "salary": "60.00" } ], '
          '"firstNames": ["Ada", "Max"], "lastNames": ["Roux", "Weber"] },',
    )
    .replaceFirst(
      '"serviceWeight": "1", "sizeWeight": "0"',
      '"serviceWeight": "1", "sizeWeight": "0", "qualityWeight": "0.5"',
    );

/// The factory test pipeline with labs run before settlement.
final labSystems = [
  for (final system in factorySystems) ...[
    system,
    if (system.runtimeType.toString() == 'FactorySystem') const LabSystem(),
  ],
];

void main() {
  (ContentDb, Simulation) start() {
    final content = loadScenario(labJson());
    final game = Simulation.newGame(
      content,
      seed: 3,
      systems: labSystems,
      policies: const {},
    );
    game.submit(
      BuildFactory(
        player,
        kind: dairy,
        country: home,
        name: 'Laiterie',
        company: playerCompany,
      ),
    );
    for (var i = 0; i < 5; i++) {
      expect(game.step().rejections, isEmpty);
    }
    return (content, game);
  }

  List<String> apply(Simulation game, List<Command> commands) {
    commands.forEach(game.submit);
    return [for (final r in game.step().rejections) r.reason.key];
  }

  /// Runs to the first of next month, that day included; returns its events.
  List<TickEvent> toNextMonth(Simulation game) {
    while (true) {
      final first = game.world.today.isFirstOfMonth;
      final result = game.step();
      if (first) return result.events;
    }
  }

  LabView lab(Simulation game) =>
      game.observe(player).companies.first.factories.single.lab!;

  /// Someone of [level], known as [repute], put straight on the market.
  KeyPersonId candidate(
    Simulation game,
    KeyRole role, {
    required int level,
    int? repute,
  }) {
    final id = KeyPersonId(game.world.keyPeople.length);
    game.world.keyPeople.add(
      KeyPerson(
        id: id,
        name: 'Test ${id.index}',
        role: role,
        level: level,
        repute: repute ?? level,
        since: game.world.today,
      ),
    );
    return id;
  }

  group('a lab', () {
    test('loads from the scenario, with a market of candidates', () {
      final (content, game) = start();
      final labs = content.factories!.labs!;
      expect(labs.generationWork, Money(10000));
      expect(labs.levels.length, 2);
      final candidates = game.observe(player).candidates;
      expect(candidates.length, 3);
      for (final person in candidates) {
        expect(person.known, false);
        // The market turns over on the first of the month.
        expect(person.leaves!.isFirstOfMonth, isTrue);
        expect(person.leaves! >= person.since + 60, isTrue);
        expect(person.leaves! < person.since + 92, isTrue);
        expect(person.salary, labs.levels[person.level].salary);
      }
      expect(lab(game).lines.map((line) => line.product), [
        milkBudget,
        milkPremium,
      ]);
      expect(lab(game).project, isNull);
    });

    test(
      'is refused a budget over the limit or a product it does not make',
      () {
        final (_, game) = start();
        expect(
          apply(game, [
            SetLab(player, factory: first, budget: Money(5001)),
            SetLab(player, factory: first, budget: -Money(1)),
            SetLab(
              player,
              factory: first,
              budget: Money(1000),
              project: const ProductId(7),
            ),
            SetLab(rival, factory: first, budget: Money(1000)),
          ]),
          [
            'labBudgetRange',
            'labBudgetRange',
            'unknownProduct',
            'notYourFactory',
          ],
        );
      },
    );

    test('launches a generation once its budget has done the work', () {
      final (_, game) = start();
      expect(
        apply(game, [
          SetLab(
            player,
            factory: first,
            budget: Money(5000),
            project: milkPremium,
          ),
        ]),
        isEmpty,
      );
      expect(lab(game).needed, Money(10000));
      expect(lab(game).monthsLeft, 2);
      expect(lab(game).expectedGain, Fx.parse('0.10'));
      expect(toNextMonth(game).whereType<GenerationLaunched>(), isEmpty);
      expect(lab(game).work, Money(5000));
      final launched = toNextMonth(game).whereType<GenerationLaunched>().single;
      expect(launched.product, milkPremium);
      expect(launched.generation, 1);
      expect(launched.gain, Fx.parse('0.10'));
      expect(launched.saving, Fx.parse('0.05'));
      final line = lab(game).lines[1];
      expect(line.generation, 1);
      expect(line.lead, Fx.parse('0.10'));
      expect(lab(game).lines[0].lead, Fx.zero);
      // Recorded each month since the lab took it up: a step at the launch.
      expect(line.history, [Fx.zero, Fx.parse('0.10')]);
      expect(lab(game).lines[0].history, isEmpty);
      // Ahead by a tenth, the next takes a tenth more work.
      expect(lab(game).needed, Money(11000));
      expect(lab(game).work, Money.zero);
      // The two months' budget is in the factory's books.
      final reports = game.reports(playerCompany, ReportPeriod.month);
      final spent = reports.fold(
        Money.zero,
        (sum, report) => sum + (report.factory(first)?.lab ?? Money.zero),
      );
      expect(spent, Money(10000));
      expect(invariantViolations(game.world), isEmpty);
    });

    test('loses a tenth of its lead to the market each month', () {
      final (_, game) = start();
      game.world.factories.single.lineFor(milkBudget).lead = Fx.parse('0.20');
      toNextMonth(game);
      expect(lab(game).lines[0].lead, Fx.parse('0.18'));
      toNextMonth(game);
      expect(lab(game).lines[0].lead, Fx.parse('0.162'));
      expect(lab(game).lines[0].history, [Fx.parse('0.18'), Fx.parse('0.162')]);
    });

    test('works twice as fast with a strong engineer, who saves more', () {
      final (_, game) = start();
      final engineer = candidate(game, KeyRole.engineer, level: 1);
      expect(
        apply(game, [
          HireKeyPerson(player, person: engineer, factory: first),
          SetLab(
            player,
            factory: first,
            budget: Money(5000),
            project: milkBudget,
          ),
        ]),
        isEmpty,
      );
      expect(lab(game).engineers, Fx.one);
      expect(lab(game).monthlyWork, Money(10000));
      expect(lab(game).monthsLeft, 1);
      final launched = toNextMonth(game).whereType<GenerationLaunched>().single;
      expect(launched.gain, Fx.parse('0.10'));
      expect(launched.saving, Fx.parse('0.10'));
    });

    test('gains twice the quality with a strong designer', () {
      final (_, game) = start();
      final designer = candidate(game, KeyRole.designer, level: 1);
      apply(game, [
        HireKeyPerson(player, person: designer, factory: first),
        SetLab(
          player,
          factory: first,
          budget: Money(5000),
          project: milkBudget,
        ),
      ]);
      expect(lab(game).expectedGain, Fx.parse('0.20'));
      toNextMonth(game);
      final launched = toNextMonth(game).whereType<GenerationLaunched>().single;
      expect(launched.gain, Fx.parse('0.20'));
    });

    test('pays its people every day, at what their repute asks', () {
      final (_, game) = start();
      // Known as strong, in truth ordinary.
      final person = candidate(game, KeyRole.engineer, level: 0, repute: 1);
      apply(game, [HireKeyPerson(player, person: person, factory: first)]);
      final result = game.step();
      final pay = result.entries.where(
        (entry) =>
            entry.reason == EntryReason.salary &&
            entry.debit == AccountKind.salaries &&
            entry.factory == first,
      );
      // 60 a month is 720 a year, 1.97 a day.
      expect(pay.single.amount, Money(197));
      expect(lab(game).people.single.salary, Money(6000));
      expect(lab(game).monthlyPay, Money(6000));
    });

    test('shows a person as reputed until they have worked long enough', () {
      final (_, game) = start();
      final person = candidate(game, KeyRole.engineer, level: 0, repute: 1);
      apply(game, [HireKeyPerson(player, person: person, factory: first)]);
      expect(lab(game).people.single.level, 1);
      expect(lab(game).people.single.known, false);
      // The lab's forecast takes them at their repute.
      expect(lab(game).engineers, Fx.one);
      toNextMonth(game);
      expect(lab(game).people.single.known, false);
      toNextMonth(game);
      expect(lab(game).people.single.known, true);
      expect(lab(game).people.single.level, 0);
      expect(lab(game).engineers, Fx.zero);
    });

    test('hires from the market only, up to its size, and lets people go', () {
      final (_, game) = start();
      final a = candidate(game, KeyRole.engineer, level: 0);
      final b = candidate(game, KeyRole.designer, level: 0);
      final c = candidate(game, KeyRole.designer, level: 1);
      expect(
        apply(game, [
          HireKeyPerson(player, person: a, factory: first),
          HireKeyPerson(player, person: a, factory: first),
          HireKeyPerson(player, person: b, factory: first),
          HireKeyPerson(player, person: c, factory: first),
          HireKeyPerson(player, person: const KeyPersonId(99), factory: first),
          HireKeyPerson(rival, person: c, factory: first),
          DismissKeyPerson(rival, person: a),
          DismissKeyPerson(player, person: c),
        ]),
        [
          'keyPersonTaken',
          'labFull',
          'unknownKeyPerson',
          // The player's own, then the rival's.
          'notYourKeyPerson',
          'notYourFactory',
          'notYourKeyPerson',
        ],
      );
      expect(lab(game).people.map((person) => person.id), [a, b]);
      expect(apply(game, [DismissKeyPerson(player, person: a)]), isEmpty);
      expect(lab(game).people.map((person) => person.id), [b]);
      expect(game.world.keyPeople[a.index].status, KeyStatus.gone);
      expect(
        game.observe(player).candidates.any((person) => person.id == a),
        false,
      );
    });

    test('loses candidates nobody hired to others, and sees new ones', () {
      final (_, game) = start();
      final before = [
        for (final person in game.observe(player).candidates) person.id,
      ];
      for (var day = 0; day < 95; day++) {
        game.step();
      }
      final after = [
        for (final person in game.observe(player).candidates) person.id,
      ];
      expect(after.length, 3);
      expect(after.toSet().intersection(before.toSet()), isEmpty);
      expect(
        apply(game, [
          HireKeyPerson(player, person: before.first, factory: first),
        ]),
        ['keyPersonTaken'],
      );
    });

    test('lets its people go when the factory closes', () {
      final (_, game) = start();
      final person = candidate(game, KeyRole.engineer, level: 0);
      apply(game, [HireKeyPerson(player, person: person, factory: first)]);
      apply(game, [CloseFactory(player, factory: first)]);
      game.step();
      expect(game.world.keyPeople[person.index].status, KeyStatus.gone);
    });

    test('counts in what the factory earns', () {
      final (content, game) = start();
      final factory = game.world.factories.single;
      final person = candidate(game, KeyRole.engineer, level: 0);
      apply(game, [
        HireKeyPerson(player, person: person, factory: first),
        SetLab(
          player,
          factory: first,
          budget: Money(2000),
          project: milkBudget,
        ),
      ]);
      // 30 a month of pay and 20 of budget.
      expect(labYearCost(game.world, content, factory), Money(60000));
      apply(game, [SetLab(player, factory: first, budget: Money(2000))]);
      expect(labYearCost(game.world, content, factory), Money(36000));
    });
  });

  group('quality', () {
    test(
      'reaches the shelf with the factory\'s goods, and saves materials',
      () {
        final (_, game) = start();
        game.world.factories.single.lineFor(milkBudget)
          ..lead = Fx.parse('0.20')
          ..saving = Fx.parse('0.10');
        final stock = game.world.stores[playerStore.index].stock;
        final had = stock[milkBudget.index].units;
        expect(
          apply(game, [
            OrderFromFactory(
              player,
              store: playerStore,
              factory: first,
              lines: [(product: milkBudget, quantity: 96)],
            ),
          ]),
          isEmpty,
        );
        final result = game.step();
        // What was on hand was standard: the delivery blends into it. The
        // day's sales came off both alike.
        final shelf = stock[milkBudget.index];
        expect(
          shelf.quality,
          Fx.raw(Fx.parse('0.20').raw * 96 ~/ (had + 96)),
          reason: 'had $had',
        );
        expect(stock[milkPremium.index].quality, Fx.zero);
        // 0.55 a unit, 40% of it materials, a tenth saved: 0.198, so 0.20.
        final materials = result.entries
            .where(
              (entry) =>
                  entry.reason == EntryReason.materials &&
                  entry.debit == AccountKind.costOfGoods,
            )
            .single;
        expect(materials.amount, Money(96 * 20));
        final view = game.observe(player);
        expect(
          view.companies.first.stores.first.qualityOf(milkBudget),
          shelf.quality,
        );
        expect(
          view.shelves[playerStore.index].qualityOf(milkBudget),
          shelf.quality,
        );
        expect(view.shelves[rivalStore.index].quality, isEmpty);
      },
    );

    test('goes back to standard as wholesalers\' goods come in', () {
      final (_, game) = start();
      final shelf =
          game.world.stores[playerStore.index].stock[milkBudget.index];
      shelf.clear();
      shelf.receive(50, Money(50), null, quality: Fx.parse('0.30'));
      expect(shelf.quality, Fx.parse('0.30'));
      shelf.receive(50, Money(50), null);
      expect(shelf.quality, Fx.parse('0.15'));
      shelf.clear();
      shelf.receive(10, Money(50), null);
      expect(shelf.quality, Fx.zero);
    });

    test('makes a shelf seem cheaper to shoppers, by what they think it '
        'worth', () {
      final content = loadScenario(labJson());
      final segment = content.segments.single;
      final prices = [Money(99), Money(179)];
      final plain = segment.priceIndex(content.products, prices)!;
      final better = segment.priceIndex(
        content.products,
        prices,
        quality: [Fx.parse('0.20'), Fx.parse('0.20')],
      )!;
      expect(plain, Fx.one);
      // A fifth better is worth a tenth more: 1 / 1.10, to the cent.
      expect(better, Fx.parse('0.9084'));
      expect(segment.worthWith(Money(100), Fx.parse('0.20')), Money(110));
      expect(segment.worthWith(Money(100), Fx.zero), Money(100));
    });

    test('draws shoppers to the shop that has it', () {
      int visits(Fx quality) {
        final content = loadScenario(labJson());
        final game = Simulation.newGame(content, seed: 11, policies: const {});
        var total = 0;
        for (var day = 0; day < 60; day++) {
          for (final (store, owner) in [
            (playerStore, player),
            (rivalStore, rival),
          ]) {
            final stock = game.world.stores[store.index].stock;
            if (stock[milkBudget.index].units < 80 &&
                !game.world.orders.any((order) => order.store == store)) {
              game.submit(
                PlaceOrder(
                  owner,
                  store: store,
                  supplier: fresh,
                  lines: [(product: milkBudget, quantity: 120)],
                ),
              );
            }
          }
          for (final stock in game.world.stores[playerStore.index].stock) {
            stock.quality = quality;
          }
          total += game.step().attribution.visits[playerStore.index];
        }
        return total;
      }

      final plain = visits(Fx.zero);
      final better = visits(Fx.parse('0.30'));
      expect(better, greaterThan(plain + plain ~/ 20));
    });
  });

  test('a shop run by policy charges more for better goods, though less '
      'than shoppers think them worth', () {
    Money price(Fx quality) {
      final content = loadScenario(labJson());
      final game = Simulation.newGame(
        content,
        seed: 5,
        systems: labSystems,
        policies: {player: RetailPolicy(content.strategies.single)},
      );
      for (var day = 0; day < 120; day++) {
        game.world.stores[playerStore.index].stock[milkBudget.index].quality =
            quality;
        game.step();
      }
      return game.world.stores[playerStore.index].prices[milkBudget.index]!;
    }

    final plain = price(Fx.zero);
    final better = price(Fx.parse('0.40'));
    // Worth a fifth more to shoppers: half of that in the price.
    expect(better > plain.times(Fx.parse('1.06')), isTrue, reason: '$better');
    expect(better < plain.times(Fx.parse('1.14')), isTrue, reason: '$better');
  });

  test('a game with labs saves, loads and replays to the same world', () {
    final (content, game) = start();
    final hired = game.observe(player).candidates.first.id;
    game
      ..submit(HireKeyPerson(player, person: hired, factory: first))
      ..submit(
        SetLab(
          player,
          factory: first,
          budget: Money(5000),
          project: milkPremium,
        ),
      );
    for (var day = 0; day < 100; day++) {
      if (day % 4 == 0) {
        game.submit(
          OrderFromFactory(
            player,
            store: playerStore,
            factory: first,
            lines: [(product: milkPremium, quantity: 24)],
          ),
        );
      }
      game.step();
    }
    expect(lab(game).lines[1].generation, greaterThan(0));
    expect(
      game.world.stores[playerStore.index].stock[milkPremium.index].quality >
          Fx.zero,
      true,
    );
    final save = game.save();
    final loaded = Simulation.load(content, save, systems: labSystems);
    expect(loaded.stateHash(), game.stateHash());
    final replayed = Simulation.replay(content, save, systems: labSystems);
    expect(replayed.stateHash(), game.stateHash());
    for (var day = 0; day < 40; day++) {
      game.step();
      loaded.step();
    }
    expect(loaded.stateHash(), game.stateHash());
  });
}
