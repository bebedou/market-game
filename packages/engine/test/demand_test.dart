import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _odds =
    '{ "substitute": "0.40", "elsewhere": "0.30", "delay": "0.20", '
    '"skip": "0.10" }';

/// The test scenario with demand settings changed. [always] makes every
/// shopper respond the same way to a missing or overpriced item.
ContentDb scenario({
  int households = 60,
  String premiumShare = '0.30',
  String rivalLocation = '0.60',
  MissResponse? always,
}) {
  var json = testScenarioJson;
  void edit(String from, String to) {
    if (!json.contains(from)) throw StateError('The fixture has no $from');
    json = json.replaceFirst(from, to);
  }

  edit('"regulars": 60', '"regulars": $households');
  edit('"premiumShare": "0.30"', '"premiumShare": "$premiumShare"');
  edit('"location": "0.60"', '"location": "$rivalLocation"');
  if (always != null) {
    final odds = [
      for (final response in MissResponse.values)
        '"${response.name}": "${response == always ? 1 : 0}"',
    ];
    edit(_odds, '{ ${odds.join(', ')} }');
  }
  return loadScenario(json);
}

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

/// Units sold during a day, by store and product.
List<(StoreId?, ProductId?, int)> sales(TickResult day) => [
  for (final entry in day.entries)
    if (entry.reason == EntryReason.sale &&
        entry.party.type == PartyType.company)
      (entry.store, entry.product, entry.units),
];

/// Orders budget milk from the fresh supplier for any store running low.
void restock(Simulation simulation) {
  for (final (store, owner) in [(playerStore, player), (rivalStore, rival)]) {
    final onShelf =
        simulation.world.stores[store.index].stock[milkBudget.index].units;
    final onOrder = simulation.world.orders
        .where((order) => order.store == store)
        .expand((order) => order.lines)
        .fold(0, (sum, line) => sum + line.quantity);
    if (onShelf + onOrder < 60) {
      simulation.submit(
        PlaceOrder(
          owner,
          store: store,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 60)],
        ),
      );
    }
  }
}

void main() {
  group('households', () {
    test('are created per segment, knowing the starting prices', () {
      final cohorts = Simulation.newGame(scenario(), seed: 1).world.cohorts;
      expect(cohorts, hasLength(60));
      expect(cohorts.map((cohort) => cohort.segment).toSet(), {regulars});
      final first = cohorts.first;
      expect(first.needs, [Fx.zero]);
      expect(first.loyalty, [Fx.parse('0.5'), Fx.parse('0.5')]);
      expect(
        first.proximity.map((p) => p.raw),
        everyElement(inInclusiveRange(0, Fx.scale)),
      );
      // (0.95 × 0.35 + 1.69 × 0.15) / (0.99 × 0.35 + 1.79 × 0.15), weighting
      // each tier by daily units × tier share; the rival charges reference.
      expect(first.perceivedPrices, [Fx.parse('0.9528'), Fx.one]);
    });

    test('shop every few days once a need reaches a whole unit', () {
      final simulation = Simulation.newGame(
        scenario(households: 2, always: MissResponse.skip),
        seed: 1,
      );
      final visits = [
        for (final day in advance(simulation, 8))
          day.attribution.visits.fold(0, (sum, count) => sum + count),
      ];
      // Each needs half a unit a day and shops every other day, a day apart.
      expect(visits, [0, 1, 1, 1, 1, 1, 1, 1]);
    });

    test('carry unmet needs up to a cap', () {
      final simulation = Simulation.newGame(
        scenario(households: 1, always: MissResponse.delay),
        seed: 1,
      );
      advance(simulation, 20);
      expect(simulation.world.cohorts.single.needs, [Fx.parse('3.5')]);
    });
  });

  test('believed prices drift toward actual prices by word of mouth', () {
    final simulation = Simulation.newGame(scenario(households: 1), seed: 1)
      ..submit(
        SetPrice(
          player,
          store: playerStore,
          product: milkBudget,
          price: Money(119),
        ),
      )
      ..step();
    // The actual index is now 0.67 / 0.615 = 1.0894; 5% of the gap closes.
    expect(
      simulation.world.cohorts.single.perceivedPrices[playerStore.index],
      Fx.parse('0.9596'),
    );
  });

  test('a household learns prices and loyalty from each trip', () {
    final simulation = Simulation.newGame(
      scenario(
        households: 1,
        premiumShare: '1',
        always: MissResponse.substitute,
      ),
      seed: 1,
    );
    final household = simulation.world.cohorts.single;
    Fx loyalty(StoreId store) => household.loyalty[store.index];
    simulation
      ..submit(DelistProduct(rival, store: rivalStore, product: milkBudget))
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 12)],
        ),
      )
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: milkPremium, quantity: 48)],
        ),
      );

    // Day 2: organic milk hasn't arrived, so the household takes value milk.
    final day2 = advance(simulation, 3).last;
    expect(day2.attribution.visits, [1, 0]);
    expect(day2.attribution.misses, {
      (
        store: playerStore,
        product: milkPremium,
        reason: MissReason.outOfStock,
        response: MissResponse.substitute,
        elsewhere: null,
      ): 1,
    });
    expect(sales(day2), [(playerStore, milkBudget, 1)]);
    // A substitute counts half: a fill score of 0.5, no better than neutral.
    expect(loyalty(playerStore), Fx.parse('0.5'));

    final day4 = advance(simulation, 2).last;
    expect(day4.attribution.misses, isEmpty);
    expect(sales(day4), [(playerStore, milkPremium, 1)]);
    // 20% of the way to a full basket.
    expect(loyalty(playerStore), Fx.parse('0.6'));

    // The player empties the shelves; the rival relists value milk.
    simulation
      ..submit(DelistProduct(player, store: playerStore, product: milkBudget))
      ..submit(DelistProduct(player, store: playerStore, product: milkPremium))
      ..submit(
        ListProduct(
          rival,
          store: rivalStore,
          product: milkBudget,
          price: Money(99),
        ),
      )
      ..submit(
        PlaceOrder(
          rival,
          store: rivalStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 12)],
        ),
      );
    final day6 = advance(simulation, 2).last;
    expect(day6.attribution.switches, {
      (from: playerStore, to: rivalStore, cause: SwitchCause.closed): 1,
    });
    expect(day6.attribution.misses.keys.single.reason, MissReason.notListed);
    expect(sales(day6), [(rivalStore, milkBudget, 1)]);
    expect(loyalty(rivalStore), Fx.parse('0.5'));
    // 5% of the way back to neutral.
    expect(loyalty(playerStore), Fx.parse('0.595'));
    expect(household.perceivedPrices[rivalStore.index], Fx.one);
  });

  test('items priced beyond the tolerance lose buyers', () {
    final simulation = Simulation.newGame(
      scenario(households: 20, premiumShare: '0', always: MissResponse.skip),
      seed: 1,
    );
    simulation
      ..submit(DelistProduct(rival, store: rivalStore, product: milkBudget))
      ..submit(
        SetPrice(
          player,
          store: playerStore,
          product: milkBudget,
          price: Money(500),
        ),
      )
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 120)],
        ),
      );
    final expensive = advance(simulation, 6);
    expect(expensive.expand(sales), isEmpty);
    expect(expensive.expand((day) => day.attribution.misses.keys).toSet(), {
      (
        store: playerStore,
        product: milkBudget,
        reason: MissReason.overpriced,
        response: MissResponse.skip,
        elsewhere: null,
      ),
    });

    // 1.08 is within 10% of the 0.99 reference price. (The milk spoils on
    // day 11.)
    simulation.submit(
      SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(108),
      ),
    );
    final fair = advance(simulation, 4);
    expect(fair.expand(sales), isNotEmpty);
    expect(fair.expand((day) => day.attribution.misses.keys), isEmpty);
  });

  group('a price too dear', () {
    /// A game where only the player's store lists milk, with both tiers in
    /// stock at these prices. Bulk takes three days to deliver, so it runs
    /// three days first.
    Simulation dear({
      required MissResponse always,
      required Money budget,
      required Money premium,
      String premiumShare = '0',
      int households = 20,
    }) {
      final simulation = Simulation.newGame(
        scenario(
          households: households,
          premiumShare: premiumShare,
          always: always,
        ),
        seed: 1,
      );
      simulation
        ..submit(DelistProduct(rival, store: rivalStore, product: milkBudget))
        ..submit(
          PlaceOrder(
            player,
            store: playerStore,
            supplier: bulk,
            lines: [
              (product: milkBudget, quantity: 120),
              (product: milkPremium, quantity: 120),
            ],
          ),
        );
      advance(simulation, 3);
      simulation
        ..submit(
          SetPrice(
            player,
            store: playerStore,
            product: milkBudget,
            price: budget,
          ),
        )
        ..submit(
          SetPrice(
            player,
            store: playerStore,
            product: milkPremium,
            price: premium,
          ),
        );
      return simulation;
    }

    test('is never answered with something dearer', () {
      // Budget at 1.65 is far beyond its reference of 0.99, and the premium
      // at 1.69 is fair for what it is, but dearer.
      final simulation = dear(
        always: MissResponse.substitute,
        budget: Money(165),
        premium: Money(169),
      );
      final days = advance(simulation, 6);
      expect(
        days.expand(sales).where((sale) => sale.$2 == milkPremium),
        isEmpty,
      );
      final misses = days.expand((day) => day.attribution.misses.keys);
      expect(misses, isNotEmpty);
      expect(misses.map((miss) => miss.response).toSet(), {MissResponse.skip});
    });

    test('is answered with something cheaper', () {
      final simulation = dear(
        always: MissResponse.substitute,
        budget: Money(95),
        premium: Money(500),
        premiumShare: '1',
      );
      final days = advance(simulation, 6);
      final sold = days.expand(sales);
      expect(sold, isNotEmpty);
      expect(sold.map((sale) => sale.$2).toSet(), {milkBudget});
      expect(days.expand((day) => day.attribution.misses.keys).toSet(), {
        (
          store: playerStore,
          product: milkPremium,
          reason: MissReason.overpriced,
          response: MissResponse.substitute,
          elsewhere: null,
        ),
      });
    });

    test('is not waited out', () {
      final simulation = dear(
        always: MissResponse.delay,
        budget: Money(500),
        premium: Money(169),
        households: 1,
      );
      final days = advance(simulation, 6);
      expect(days.expand(sales), isEmpty);
      expect(days.expand((day) => day.attribution.misses.keys).toSet(), {
        (
          store: playerStore,
          product: milkBudget,
          reason: MissReason.overpriced,
          response: MissResponse.skip,
          elsewhere: null,
        ),
      });
      // Half a unit a day: a need that had waited would be at its cap of 3.5.
      expect(
        simulation.world.cohorts.single.needs.single < Fx.parse('1.5'),
        isTrue,
      );
    });

    test('at the next store too, leaves the need behind', () {
      final simulation = Simulation.newGame(
        scenario(
          households: 1,
          premiumShare: '0',
          always: MissResponse.elsewhere,
        ),
        seed: 1,
      );
      restock(simulation);
      advance(simulation, 2);
      for (final (owner, store) in [
        (player, playerStore),
        (rival, rivalStore),
      ]) {
        simulation.submit(
          SetPrice(owner, store: store, product: milkBudget, price: Money(500)),
        );
      }
      final days = advance(simulation, 6);
      expect(days.expand(sales), isEmpty);
      final responses = days
          .expand((day) => day.attribution.misses.keys)
          .map((miss) => miss.response)
          .toSet();
      expect(responses, {MissResponse.elsewhere, MissResponse.skip});
      expect(
        simulation.world.cohorts.single.needs.single < Fx.parse('1.5'),
        isTrue,
      );
    });

    test('here, and sold out at the next store, can still be waited out', () {
      final simulation = dear(
        always: MissResponse.elsewhere,
        budget: Money(500),
        premium: Money(169),
        households: 1,
      );
      // The rival lists milk again, with none in stock.
      simulation.submit(
        ListProduct(
          rival,
          store: rivalStore,
          product: milkBudget,
          price: Money(99),
        ),
      );
      advance(simulation, 6);
      expect(
        simulation.world.cohorts.single.needs.single > Fx.parse('1.5'),
        isTrue,
      );
    });
  });

  test('shoppers who go elsewhere buy at another store listing the item', () {
    final simulation = Simulation.newGame(
      scenario(premiumShare: '0', always: MissResponse.elsewhere),
      seed: 1,
    );
    simulation
      ..submit(DelistProduct(player, store: playerStore, product: milkBudget))
      ..submit(
        PlaceOrder(
          rival,
          store: rivalStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 180)],
        ),
      );
    final days = advance(simulation, 5);
    final walkedOut = (
      store: playerStore,
      product: milkBudget,
      reason: MissReason.notListed,
      response: MissResponse.elsewhere,
      elsewhere: rivalStore,
    );
    final misses = days.expand((day) => day.attribution.misses.entries);
    expect(misses.map((miss) => miss.key).toSet(), {walkedOut});
    final rivalSales = days.expand(sales).fold(0, (sum, sale) => sum + sale.$3);
    final redirected = misses.fold(0, (sum, miss) => sum + miss.value);
    expect(redirected, greaterThan(0));
    expect(rivalSales, greaterThan(redirected));
  });

  test('cheaper stores win visits, and a price rise loses them gradually', () {
    final simulation = Simulation.newGame(
      scenario(premiumShare: '0', rivalLocation: '0.50'),
      seed: 1,
    );
    int playerShare(Iterable<TickResult> days) {
      final visits = days.map((day) => day.attribution.visits);
      final total = visits.fold(0, (sum, v) => sum + v[0] + v[1]);
      return visits.fold(0, (sum, v) => sum + v[0]) * 100 ~/ total;
    }

    List<TickResult> run(int days) {
      final results = <TickResult>[];
      for (var i = 0; i < days; i++) {
        restock(simulation);
        results.add(simulation.step());
      }
      return results;
    }

    simulation.submit(
      SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(85),
      ),
    );
    final cheap = run(40);
    expect(playerShare(cheap.skip(20)), greaterThan(70));

    simulation.submit(
      SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(109),
      ),
    );
    final dear = run(40);
    expect(playerShare(dear.take(4)), greaterThan(playerShare(dear.skip(20))));
    expect(playerShare(dear.skip(20)), lessThan(40));

    final causes = <SwitchCause, int>{};
    for (final day in dear) {
      for (final MapEntry(:key, :value) in day.attribution.switches.entries) {
        if (key.from == playerStore) {
          causes[key.cause] = (causes[key.cause] ?? 0) + value;
        }
      }
    }
    final byCount = causes.keys.toList()
      ..sort((a, b) => causes[b]! - causes[a]!);
    expect(byCount.first, SwitchCause.price);
  });

  test('every sale moves household cash to the store', () {
    final simulation = Simulation.newGame(scenario(), seed: 3);
    final results = <TickResult>[];
    for (var i = 0; i < 120; i++) {
      scriptedCommands(simulation.today).forEach(simulation.submit);
      results.add(simulation.step());
    }
    // Balances are debit-positive, so revenue is stored negative.
    final households = simulation.world.households.single.accounts;
    final revenue = simulation.world.companies.fold(
      Money.zero,
      (sum, company) => sum + company.accounts[AccountKind.revenue],
    );
    expect(households[AccountKind.spending], -revenue);
    expect(households[AccountKind.cash], revenue);
    final storesSelling = results.expand(sales).map((sale) => sale.$1).toSet();
    expect(storesSelling, {playerStore, rivalStore});
  });
}
