@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/policies/director.dart';
import 'package:engine/src/policies/retail_policy.dart' show operatingReserve;
import 'package:engine/src/state/factory_sales.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'director_test.dart' show clerk, growing, opening, star, withDirectors;
import 'software_test.dart' show softwareJson, softwareSystems;
import 'support/fixtures.dart';

/// The town where owners open stores, with a snack bar's trade beside the
/// grocer's, and two more vacant sites.
final _twoTrades = loadScenario(
  withDirectors(testScenarioJson)
      .replaceFirst(
        '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
        '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
      )
      .replaceFirst('"cash": "500.00" }', '"cash": "50000.00" }')
      .replaceFirst(
        '"area": 80, "maxArea": 120 }\n  ],',
        '"area": 80, "maxArea": 120 },\n'
            '    { "id": "alley", "name": "Alley", "market": "town", "location": "0.45", "rent": "0.00",\n'
            '      "shelfSlots": 2, "storageUnits": 300, "openingCost": "250.00", "buildDays": 5,\n'
            '      "area": 80, "maxArea": 120 },\n'
            '    { "id": "yard", "name": "Yard", "market": "town", "location": "0.45", "rent": "0.00",\n'
            '      "shelfSlots": 2, "storageUnits": 300, "openingCost": "250.00", "buildDays": 5,\n'
            '      "area": 80, "maxArea": 120 }\n  ],',
      )
      .replaceFirst(
        '"categories": [{ "id": "milk", "name": "Milk" }],',
        '"categories": [{ "id": "milk", "name": "Milk" }],\n'
            '  "formats": [\n'
            '    { "id": "grocery", "name": "Grocer", "categories": ["milk"] },\n'
            '    { "id": "fastfood", "name": "Snack bar", "categories": ["milk"] }\n'
            '  ],',
      )
      .replaceFirstMapped(
        RegExp(
          r'("strategies": \[\s*\{ "id": "steady", "name": "Steady",)([^}]*\})',
        ),
        (match) =>
            '${match[1]}${match[2]},\n    { "id": "snack", "name": "Snack", '
            '"format": "fastfood",${match[2]}',
      ),
);

/// A brief of [goals] for the player's company, from a star.
HireDirector _brief(
  Map<String, Goal> goals, {
  CompanyId company = playerCompany,
  StrategyId strategy = steady,
  ManagerGradeId managerGrade = clerk,
  DirectorGradeId grade = star,
  bool payout = false,
}) => HireDirector(
  player,
  company: company,
  grade: grade,
  strategy: strategy,
  managerGrade: managerGrade,
  growth: Growth.none,
  payout: payout,
  goals: goals,
);

/// The trade of the player's first store in [content].
String _tradeOf(Simulation game) => tradeKey(
  game.content.formats[game.world.stores[playerStore.index].format.index],
);

void main() {
  test('a goal allows what its growth does, and a brief from before goals '
      'reads as its growth', () {
    const old = Director(
      grade: star,
      strategy: steady,
      managerGrade: clerk,
      growth: Growth.invest,
      payout: false,
      hiredOn: Day(0),
    );
    expect(old.goalOf('grocery'), Goal.hold);
    expect(old.allowsIn('anything', Growth.invest), isTrue);
    expect(old.allowsIn('anything', Growth.open), isFalse);
    const briefed = Director(
      grade: star,
      strategy: steady,
      managerGrade: clerk,
      growth: Growth.none,
      payout: false,
      hiredOn: Day(0),
      goals: {'a': Goal.growFast, 'b': Goal.harvest, 'c': Goal.grow},
    );
    expect(briefed.allowsIn('a', Growth.buy), isTrue);
    expect(briefed.allowsIn('b', Growth.invest), isFalse);
    expect(briefed.allowsIn('c', Growth.open), isTrue);
    expect(briefed.allowsIn('c', Growth.buy), isFalse);
    // A business the brief leaves out: what its growth amounts to.
    expect(briefed.goalOf('d'), Goal.harvest);
  });

  test('growing opens a shop where one pays back; holding opens none', () {
    List<Command> firstOfFebruary(Goal goal) {
      final game = Simulation.newGame(opening, seed: 1);
      game.submit(_brief({_tradeOf(game): goal}));
      for (var i = 0; i < 31; i++) {
        game.step();
      }
      final view = game.observe(player);
      final company = view.companies.first;
      return direct(
        view,
        opening,
        company,
        operatingReserve(
              view,
              company,
              opening.strategies.single.reserveDays,
            )! +
            Money.parse('2000.00'),
        const {},
        [],
      );
    }

    expect(firstOfFebruary(Goal.grow).whereType<OpenStore>(), hasLength(1));
    expect(firstOfFebruary(Goal.growFast).whereType<OpenStore>(), hasLength(1));
    expect(firstOfFebruary(Goal.hold).whereType<OpenStore>(), isEmpty);
  });

  test('each trade grown opens its own shop the same month, never in the '
      'same spot', () {
    final game = Simulation.newGame(_twoTrades, seed: 1);
    final snack = _twoTrades.formats.firstWhere((f) => f.key == 'fastfood');
    game.submit(
      OpenStore(
        player,
        site: lane,
        name: 'Snack',
        company: playerCompany,
        format: snack.id,
      ),
    );
    expect(game.step().rejections, isEmpty);
    game.submit(
      _brief({
        'store': Goal.grow,
        'restaurants': Goal.grow,
        'grocery': Goal.grow,
      }),
    );
    // Two months on: the snack bar has waited its interval.
    for (var month = 0; month < 2; month++) {
      do {
        game.step();
      } while (!game.today.isFirstOfMonth);
    }
    final company = game.world.companies[playerCompany.index];
    Ledger(game.today).pay(
      payer: game.world.elsewhere,
      payerAccount: AccountKind.spending,
      payee: company,
      payeeAccount: AccountKind.revenue,
      amount: Money.parse('20000.00'),
      reason: EntryReason.sale,
    );
    final view = game.observe(player);
    final opened = direct(
      view,
      _twoTrades,
      view.companies.first,
      view.companies.first.cash,
      const {},
      [],
    ).whereType<OpenStore>().toList();
    expect(opened.map((open) => _twoTrades.formats[open.format!.index].key), {
      _twoTrades.formats.first.key,
      'fastfood',
    });
    expect(opened.map((open) => open.site).toSet(), hasLength(2));
  });

  test('goals survive a save, and a game replays the same', () {
    final game = Simulation.newGame(growing, seed: 1);
    final trade = _tradeOf(game);
    game.submit(_brief({trade: Goal.grow, 'plants:drinks': Goal.harvest}));
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    final loaded = Simulation.load(growing, game.save());
    expect(loaded.world.companies.first.director?.goals, {
      trade: Goal.grow,
      'plants:drinks': Goal.harvest,
    });
    expect(loaded.stateHash(), game.stateHash());
    expect(
      Simulation.replay(growing, game.save()).stateHash(),
      game.stateHash(),
    );
    for (var i = 0; i < 40; i++) {
      game.step();
      loaded.step();
    }
    expect(loaded.stateHash(), game.stateHash());
  });

  group('software', () {
    final content = loadScenario(withDirectors(softwareJson));

    /// A game with the player's software company, spending 500 a month on
    /// marketing, and its company.
    (Simulation, CompanyId) started() {
      final game = Simulation.newGame(
        content,
        seed: 1,
        systems: softwareSystems,
      );
      game.submit(
        StartSoftware(
          player,
          name: 'Tessel',
          country: content.countries.first.id,
          capital: Money.parse('50000.00'),
        ),
      );
      game.step();
      final software = game.world.software.single;
      game.submit(
        SetSoftwareMarketing(
          player,
          software: software.id,
          budget: Money.parse('500.00'),
        ),
      );
      game.step();
      return (game, software.company);
    }

    test('a boss runs it only with a brief of goals', () {
      final (game, company) = started();
      game.submit(
        HireDirector(
          player,
          company: company,
          grade: star,
          strategy: steady,
          managerGrade: clerk,
          growth: Growth.none,
          payout: false,
        ),
      );
      expect(game.step().rejections.single.reason.key, 'softwareOnly');
      game.submit(_brief({softwareBusiness: Goal.hold}, company: company));
      expect(game.step().rejections, isEmpty);
      expect(game.world.companies[company.index].director, isNotNull);
    });

    test('growing, the boss hires the best value a year of cash covers; '
        'holding, nobody', () {
      int team(Goal goal) {
        final (game, company) = started();
        game.submit(_brief({softwareBusiness: goal}, company: company));
        game.step();
        while (!game.today.isFirstOfMonth) {
          game.step();
        }
        game.step();
        final software = game.world.software.single;
        return game.world.keyPeople
            .where((person) => person.software == software.id)
            .length;
      }

      expect(team(Goal.grow), 1);
      expect(team(Goal.hold), 0);
    });

    test('harvesting, the boss stops its marketing on the first of the '
        'month; holding, keeps it', () {
      Money marketing(Goal goal) {
        final (game, company) = started();
        game.submit(_brief({softwareBusiness: goal}, company: company));
        game.step();
        while (!game.today.isFirstOfMonth) {
          game.step();
        }
        game.step();
        expect(invariantViolations(game.world), isEmpty);
        return game.world.software.single.marketing;
      }

      expect(marketing(Goal.harvest), Money.zero);
      expect(marketing(Goal.hold), Money.parse('500.00'));
    });
  });

  test("a boss bids a point under the latest winner's share of the "
      'producer price, or 4% under before any, never near cost', () {
    TenderView tender({
      int number = 1,
      Money? reference,
      Money? won,
      int closes = 10,
      TenderStatus status = TenderStatus.open,
    }) => (
      number: number,
      country: const CountryId(0),
      chain: 'Chain',
      product: const ProductId(0),
      units: 100,
      months: 12,
      floor: Fx.zero,
      reference: reference ?? Money.parse('100.00'),
      opens: const Day(0),
      closes: Day(closes),
      status: status,
      bidFactory: null,
      bidPrice: null,
      winner: won == null ? null : 'Rival',
      winningPrice: won,
    );
    final open = tender(number: 3, closes: 40);
    final cheap = Money.parse('50.00');
    expect(tenderBid([open], open, cheap), Money.parse('96.00'));
    // The latest winner took 90% of its producer price: a point under.
    final lost = [
      tender(won: Money.parse('95.00'), closes: 5, status: TenderStatus.lost),
      tender(
        number: 2,
        reference: Money.parse('200.00'),
        won: Money.parse('180.00'),
        closes: 20,
        status: TenderStatus.lost,
      ),
      open,
    ];
    expect(tenderBid(lost, open, cheap), Money.parse('89.00'));
    // Never under its cost and a tenth.
    expect(tenderBid(lost, open, Money.parse('85.00')), isNull);
  });

  group('plants', () {
    final content = loadScenario(
      File(
        '../../content/scenarios/prototype.json',
      ).readAsStringSync().replaceFirst(
        '"name": "You", "cash": "20000.00"',
        '"name": "You", "cash": "50000000.00"',
      ),
      national: loadCountryTable(
        File('../../content/countries/euro.json').readAsStringSync(),
        File('../../content/countries/calibration.json').readAsStringSync(),
      ),
    );
    final drinks = content.factories!.kinds.firstWhere(
      (kind) => kind.key == 'drinks',
    );
    final france = content.countries.firstWhere((c) => c.key == 'fr').id;

    /// A holding start with a drinks plant in France, big enough for a
    /// chain's tender, under a boss with [goal] for it, played through
    /// [months] firsts of the month once it runs.
    Simulation briefed(Goal goal, {int months = 4}) {
      final game = Simulation.newGame(
        content,
        seed: 1,
        start: const GameStart.holding('Holding'),
        citiesAsleep: true,
      );
      final player = game.world.player;
      final cost = content.factories!.sized(drinks.id, 1).buildCost;
      game.submit(
        BuildFactory(
          player,
          kind: drinks.id,
          country: france,
          name: 'Usine',
          capital: cost + cost,
          shifts: 3,
          size: 1,
        ),
      );
      game.step();
      final factory = game.world.factories.single;
      game.submit(
        HireDirector(
          player,
          company: factory.company,
          grade: content.directors!.grades.last.id,
          strategy: content.strategies.first.id,
          managerGrade: content.managers.grades.first.id,
          growth: Growth.none,
          payout: false,
          goals: {plantsKey(drinks): goal},
        ),
      );
      expect(game.step().rejections, isEmpty);
      while (!factory.runsOn(game.today)) {
        game.step();
      }
      for (var month = 0; month < months; month++) {
        do {
          game.step();
        } while (!game.today.isFirstOfMonth);
        game.step();
      }
      return game;
    }

    test('growing, the boss builds another plant beside one full at the '
        'largest size', () {
      final sizes = content.factories!.sizes;
      final game = Simulation.newGame(
        content,
        seed: 1,
        start: const GameStart.holding('Holding'),
        citiesAsleep: true,
      );
      final player = game.world.player;
      final largest = sizes.length - 1;
      final cost = content.factories!.sized(drinks.id, largest).buildCost;
      game.submit(
        BuildFactory(
          player,
          kind: drinks.id,
          country: france,
          name: 'Usine',
          capital: cost + cost,
          shifts: 1,
          size: largest,
        ),
      );
      game.step();
      final plant = game.world.factories.single;
      game.submit(
        HireDirector(
          player,
          company: plant.company,
          grade: content.directors!.grades.last.id,
          strategy: content.strategies.first.id,
          managerGrade: content.managers.grades.first.id,
          growth: Growth.none,
          payout: false,
          goals: {plantsKey(drinks): Goal.grow},
        ),
      );
      game.step();
      while (!plant.runsOn(game.today)) {
        game.step();
      }
      // A chain takes all it can make.
      final view = game.observe(player);
      final capacity = view.companies
          .expand((company) => company.factories)
          .single
          .monthCapacity;
      game.world.contracts.add(
        Contract(
          number: 1,
          factory: plant.id,
          country: france,
          chain: 'Chaîne',
          product: content.products
              .firstWhere((product) => product.category == drinks.category)
              .id,
          units: capacity,
          price: Money.parse('1.00'),
          starts: game.today,
          ends: game.today + 365,
          priceIndex: Fx.one,
        ),
      );
      do {
        game.step();
      } while (!game.today.isFirstOfMonth);
      game.step();
      final plants = game.world.factories
          .where((factory) => factory.kind == drinks.id)
          .toList();
      expect(plants, hasLength(2));
      expect(plants.last.company, plant.company);
      expect(plants.last.country, france);
      expect(plants.last.size, newPlantSize);
      expect(plants.last.name, 'Usine 2');
    });

    test('holding, the boss sells to rivals and bids for tenders; '
        'harvesting, neither', () {
      final held = briefed(Goal.hold);
      final plant = held.world.factories.single;
      expect(plant.rivalDiscount, plantRivalDiscount);
      expect(
        held.world.tenders.where((tender) => tender.bidFactory == plant.id),
        isNotEmpty,
      );
      expect(invariantViolations(held.world), isEmpty);
      final harvested = briefed(Goal.harvest);
      final idle = harvested.world.factories.single;
      expect(idle.rivalDiscount, isNull);
      expect(
        harvested.world.tenders.where((tender) => tender.bidFactory == idle.id),
        isEmpty,
      );
    });
  });
}
