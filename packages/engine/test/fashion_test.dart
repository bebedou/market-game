import 'package:engine/engine.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/state/store.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test town with milk that keeps but goes out of fashion: new for 20
/// days, then 30% of its worth lost a month (10% for the premium), down to
/// 40%; a jobber pays a quarter of what it cost.
final fashionable = loadScenario(
  testScenarioJson
      .replaceFirst(
        '{ "id": "milk", "name": "Milk" }',
        '{ "id": "milk", "name": "Milk", "fashion": { "freshDays": 20, '
            '"fade": "0.30", "premiumFade": "0.10", "floor": "0.40", '
            '"clearance": "0.25" } }',
      )
      .replaceAll('"shelfLifeDays": 10,', ''),
);

void main() {
  final fashion = fashionable.categories.single.fashion!;

  Simulation quietGame() =>
      Simulation.newGame(fashionable, seed: 1, systems: quietSystems);

  Store shop(Simulation game) => game.world.stores[playerStore.index];

  /// Orders [units] of budget milk from the bulk wholesaler and waits for it.
  void stockUp(Simulation game, int units) {
    game.submit(
      PlaceOrder(
        player,
        store: playerStore,
        supplier: bulk,
        lines: [(product: milkBudget, quantity: units)],
      ),
    );
    for (var day = 0; day < 4; day++) {
      game.step();
    }
  }

  test('goods keep their worth while new, then fade to a floor', () {
    expect(fashion.worthAt(0, ProductTier.budget), Fx.one);
    expect(fashion.worthAt(20, ProductTier.budget), Fx.one);
    expect(fashion.worthAt(50, ProductTier.budget), Fx.parse('0.70'));
    expect(fashion.worthAt(50, ProductTier.premium), Fx.parse('0.90'));
    expect(fashion.worthAt(400, ProductTier.budget), Fx.parse('0.40'));
    expect(fashion.ageAt(Fx.parse('0.40'), ProductTier.budget), 80);
    expect(fashion.ageAt(Fx.one, ProductTier.budget), 20);
  });

  test('a delivery is dated, and its worth falls as it sits', () {
    final game = quietGame();
    stockUp(game, 48);
    final lot = shop(game).stock[milkBudget.index].lots.single;
    expect(lot.arrived, isNotNull);
    expect(lot.expiry, isNull);
    final arrived = lot.arrived!;
    Fx view() => game
        .observe(player)
        .companies
        .single
        .stores
        .single
        .fashionOf(milkBudget);
    expect(view(), Fx.one);
    while (game.today.number - arrived.number < 50) {
      game.step();
    }
    expect(view(), Fx.parse('0.70'));
    final lots = game.observe(player).companies.single.stores.single.lots;
    expect(lots[milkBudget.index].single.days, 50);
  });

  test("shoppers think faded goods worth less, as they mind it", () {
    final segment = fashionable.segments.single;
    final reference = Money.parse('1.00');
    expect(
      segment.worthWith(reference, Fx.zero, Fx.parse('0.70')),
      Money.parse('0.70'),
    );
    final half = SegmentDef(
      id: segment.id,
      key: segment.key,
      name: segment.name,
      tripIntervalDays: segment.tripIntervalDays,
      priceSensitivity: segment.priceSensitivity,
      convenienceWeight: segment.convenienceWeight,
      loyaltyWeight: segment.loyaltyWeight,
      priceTolerance: segment.priceTolerance,
      wordOfMouth: segment.wordOfMouth,
      missResponses: segment.missResponses,
      dailyUnits: segment.dailyUnits,
      premiumShare: segment.premiumShare,
      slotShares: segment.slotShares,
      serviceWeight: segment.serviceWeight,
      sizeWeight: segment.sizeWeight,
      incomeSpread: segment.incomeSpread,
      fashionWeight: Fx.parse('0.5'),
    );
    expect(
      half.worthWith(reference, Fx.zero, Fx.parse('0.70')),
      Money.parse('0.85'),
    );
    // The same shelf price is dearer against goods that have faded.
    final prices = <Money?>[Money.parse('0.99'), null];
    final fresh = segment.priceIndex(fashionable.products, prices)!;
    final faded = segment.priceIndex(
      fashionable.products,
      prices,
      fashion: [Fx.parse('0.70'), Fx.one],
    )!;
    expect(faded > fresh, isTrue);
  });

  test('old stock is cleared to a jobber for part of its cost', () {
    final game = quietGame();
    stockUp(game, 48);
    final cost = shop(game).stock[milkBudget.index].value;
    final cash =
        game.world.companies[playerCompany.index].accounts[AccountKind.cash];
    // Too young to go yet.
    game.submit(
      ClearStock(player, store: playerStore, product: milkBudget, days: 30),
    );
    expect(game.step().rejections, isEmpty);
    expect(shop(game).stock[milkBudget.index].units, 48);
    while (shop(game).stock[milkBudget.index].lots.single.ageOn(game.today) <
        30) {
      game.step();
    }
    game.submit(
      ClearStock(player, store: playerStore, product: milkBudget, days: 30),
    );
    expect(game.step().rejections, isEmpty);
    expect(shop(game).stock[milkBudget.index].units, 0);
    final company = game.world.companies[playerCompany.index];
    expect(
      company.accounts[AccountKind.cash] - cash,
      cost.times(fashion.clearance),
    );
    expect(company.accounts[AccountKind.inventory], Money.zero);
    expect(
      company.accounts[AccountKind.writeOffs],
      cost - cost.times(fashion.clearance),
    );
  });

  test('clearing is refused for goods that keep, and for no age', () {
    final plain = Simulation.newGame(
      loadScenario(testScenarioJson),
      seed: 1,
      systems: quietSystems,
    );
    plain.submit(
      ClearStock(player, store: playerStore, product: milkBudget, days: 10),
    );
    expect(plain.step().rejections.single.reason.key, 'notFashion');
    final game = quietGame();
    game
      ..submit(
        ClearStock(player, store: playerStore, product: milkBudget, days: -1),
      )
      ..submit(
        ClearStock(rival, store: playerStore, product: milkBudget, days: 10),
      );
    expect(
      [for (final r in game.step().rejections) r.reason.key],
      ['clearanceAge', 'notYourStore'],
    );
  });

  test('a lot keeps its age through a save, and older lots load as new', () {
    final game = quietGame();
    stockUp(game, 48);
    for (var day = 0; day < 30; day++) {
      game.step();
    }
    final again = Simulation.load(fashionable, game.save());
    expect(again.stateHash(), game.stateHash());
    expect(
      shop(again).stock[milkBudget.index].lots.single.ageOn(again.today),
      shop(game).stock[milkBudget.index].lots.single.ageOn(game.today),
    );
    final writer = StateWriter();
    Lot(quantity: 5, unitCost: Money.parse('0.55'), expiry: null).write(writer);
    // Format 33 wrote no arrival: the reader stops before it.
    final bytes = writer.toBytes();
    final old = Lot.read(
      StateReader(bytes.sublist(0, bytes.length - 1), version: 33),
    );
    expect(old.arrived, isNull);
    expect(old.ageOn(game.today), 0);
  });

  group('a manager', () {
    /// A game whose shop has a manager doing everything, stocked with milk
    /// that has sat [days] since it came.
    Simulation managed(int days) {
      final game = quietGame();
      stockUp(game, 96);
      game.submit(
        HireManager(
          player,
          store: playerStore,
          grade: const ManagerGradeId(0),
          strategy: steady,
          duties: [for (final _ in ManagerDuty.values) true],
        ),
      );
      expect(game.step().rejections, isEmpty);
      final arrived = shop(game).stock[milkBudget.index].lots.first.arrived!;
      while (game.today.number - arrived.number < days) {
        game.step();
      }
      return game;
    }

    test('marks down goods as they fade', () {
      final fresh = managed(10);
      final faded = managed(70);
      Money price(Simulation game) => shop(game).prices[milkBudget.index]!;
      expect(price(faded) < price(fresh), isTrue);
    });

    test('clears what has lost all it will of its worth', () {
      final game = managed(85);
      final lots = shop(game).stock[milkBudget.index].lots;
      expect(
        lots.every(
          (lot) =>
              lot.ageOn(game.today) <
              fashion.ageAt(fashion.floor, ProductTier.budget),
        ),
        isTrue,
      );
    });
  });
}
