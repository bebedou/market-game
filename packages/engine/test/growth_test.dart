import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const newcomer = PersonId(2);
const village = MarketId(1);

/// The test scenario grown by a second market, the village, dearer and
/// better paid, with a newcomer's store on the green and a vacant mill.
final grownScenarioJson = testScenarioJson
    .replaceFirst(
      '"households": { "regulars": 60 } }]',
      '"households": { "regulars": 60 } },\n'
          '    { "id": "village", "name": "Village", "households": { "regulars": 30 },\n'
          '      "priceLevel": "1.2", "wageLevel": "1.5", "incomeLevel": "1.1" }]',
    )
    .replaceFirst(
      '"area": 80, "maxArea": 120 }',
      '"area": 80, "maxArea": 120 },\n'
          '    { "id": "green", "name": "Green", "market": "village", "location": "0.50", "rent": "0.00",\n'
          '      "shelfSlots": 2, "storageUnits": 300, "openingCost": "250.00", "buildDays": 5,\n'
          '      "area": 90, "maxArea": 130 },\n'
          '    { "id": "mill", "name": "Mill", "market": "village", "location": "0.40", "rent": "50.00",\n'
          '      "shelfSlots": 2, "storageUnits": 300, "openingCost": "250.00", "buildDays": 5,\n'
          '      "area": 80, "maxArea": 120 }',
    )
    .replaceFirst(
      '{ "id": "rival", "name": "Rival", "cash": "2000.00" }',
      '{ "id": "rival", "name": "Rival", "cash": "2000.00" },\n'
          '    { "id": "newcomer", "name": "Newcomer", "cash": "1500.00", "strategy": "steady" }',
    )
    .replaceFirst(
      '{ "id": "rival_co", "name": "Rival Co", "owner": "rival", "cash": "800.00" }',
      '{ "id": "rival_co", "name": "Rival Co", "owner": "rival", "cash": "800.00" },\n'
          '    { "id": "newcomer_co", "name": "Newcomer Co", "owner": "newcomer", "cash": "600.00" }',
    )
    .replaceFirst(
      '"prices": { "milk_budget": "0.99" } }',
      '"prices": { "milk_budget": "0.99" } },\n'
          '    { "id": "newcomer_store", "name": "Village Store", "company": "newcomer_co", "site": "green",\n'
          '      "staff": { "morning": 1, "midday": 1, "evening": 1, "night": 0 },\n'
          '      "prices": { "milk_budget": "1.15", "milk_premium": "2.05" } }',
    );

/// The test scenario with bread added: a category, its two products, which
/// the bulk supplier carries, and families, a segment who buy it.
final breadScenarioJson = testScenarioJson
    .replaceFirst(
      '"categories": [{ "id": "milk", "name": "Milk" }]',
      '"categories": [{ "id": "milk", "name": "Milk" }, { "id": "bread", "name": "Bread" }]',
    )
    .replaceFirst(
      '"referencePrice": "1.79" }',
      '"referencePrice": "1.79" },\n'
          '    { "id": "bread_budget", "name": "Loaf", "category": "bread", "tier": "budget", "shelfLifeDays": 4,\n'
          '      "baseCost": "0.70", "referencePrice": "1.15" },\n'
          '    { "id": "bread_premium", "name": "Sourdough", "category": "bread", "tier": "premium", "shelfLifeDays": 4,\n'
          '      "baseCost": "1.60", "referencePrice": "2.69" }',
    )
    .replaceFirst(
      '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" } },',
      '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" },\n'
          '        "bread": { "dailyUnits": "0.30", "premiumShare": "0.20" } },',
    )
    .replaceFirst(
      '"serviceWeight": "1", "sizeWeight": "0" }\n  ],',
      '"serviceWeight": "1", "sizeWeight": "0" },\n'
          '    { "id": "families", "name": "Families", "tripIntervalDays": 3,\n'
          '      "priceSensitivity": "6", "convenienceWeight": "1", "loyaltyWeight": "1",\n'
          '      "priceTolerance": "0.05", "wordOfMouth": "0.05",\n'
          '      "missResponses": { "substitute": "0.50", "elsewhere": "0.20", "delay": "0.20", "skip": "0.10" },\n'
          '      "categories": { "milk": { "dailyUnits": "0.60", "premiumShare": "0.10" },\n'
          '        "bread": { "dailyUnits": "0.50", "premiumShare": "0.10" } },\n'
          '      "slots": { "morning": "0.20", "midday": "0.20", "evening": "0.50", "night": "0.10" },\n'
          '      "serviceWeight": "1", "sizeWeight": "0" }\n  ],',
    )
    .replaceFirst(
      '"households": { "regulars": 60 } }',
      '"households": { "regulars": 60, "families": 24 } }',
    )
    .replaceFirst(
      '"products": ["milk_budget", "milk_premium"] },',
      '"products": ["milk_budget", "milk_premium", "bread_budget", "bread_premium"] },',
    );

void main() {
  final content = loadScenario(testScenarioJson);
  final grown = loadScenario(grownScenarioJson);

  test('a saved game grows into appended markets, sites, people and '
      'stores', () {
    final simulation = Simulation.newGame(content, seed: 3);
    runScripted(simulation, 40);
    final before = simulation.world.moneySupply;

    final resumed = Simulation.load(grown, simulation.save());
    final world = resumed.world;
    expect(resumed.today, simulation.today);
    expect(world.persons, hasLength(3));
    expect(world.markets, hasLength(2));
    expect(world.moneySupply, before + Money.parse('2100.00'));
    expect(invariantViolations(world), isEmpty);
    final store = world.stores.singleWhere((s) => s.site == SiteId(3));
    expect(store.opensOn, resumed.today);
    expect(world.companies[store.company.index].name, 'Newcomer Co');
    expect(world.storeAt(SiteId(4)), isNull);
    final villagers = world.cohorts.where((c) => c.market == village);
    expect(villagers.fold(0, (sum, c) => sum + c.weight), 30);
    for (final cohort in world.cohorts) {
      expect(cohort.proximity, hasLength(5));
      expect(cohort.loyalty, hasLength(3));
      expect(cohort.perceivedPrices, hasLength(3));
    }
    expect(resumed.observe(newcomer).censuses[village.index], [
      (day: resumed.today, households: 30),
    ]);

    // The newcomer's AI stocks and runs its store, and villagers shop there
    // and nowhere else.
    final days = [
      for (var i = 0; i < 60; i++)
        (() {
          scriptedCommands(resumed.today).forEach(resumed.submit);
          return resumed.step();
        })(),
    ];
    expect(invariantViolations(world), isEmpty);
    final soldBy = {
      for (final day in days)
        for (final entry in day.entries)
          if (entry.reason == EntryReason.sale &&
              entry.party.type == PartyType.company)
            entry.store,
    };
    expect(soldBy, contains(store.id));

    // Growth happens once: the grown save loads back unchanged.
    final file = resumed.save();
    expect(Simulation.load(grown, file).save().bytes, file.bytes);
  });

  test('saves refuse content whose lists changed other than by growing', () {
    final simulation = Simulation.newGame(content, seed: 3);
    runScripted(simulation, 10);
    final file = simulation.save();
    final grownFile = Simulation.load(grown, file).save();
    for (final (json, saved) in [
      // A site renamed: the world's stores and households sit on sites by
      // position.
      (testScenarioJson.replaceAll('"lane"', '"alley"'), file),
      // A product renamed: stores price products by position.
      (testScenarioJson.replaceAll('"milk_premium"', '"milk_organic"'), file),
      // The village gone again.
      (testScenarioJson, grownFile),
      // A segment renamed: cohorts belong to segments by position.
      (testScenarioJson.replaceAll('"regulars"', '"locals"'), file),
    ]) {
      expect(
        () => Simulation.load(loadScenario(json), saved),
        throwsFormatException,
      );
    }
  });

  // Reads the fixture from disk, which only the VM can.
  test(
    'a save from format 6 grows too, and refuses lost sites',
    testOn: 'vm',
    () {
      final old = SaveFile(File('test/fixtures/save_v6.bin').readAsBytesSync());
      final resumed = Simulation.load(grown, old);
      expect(resumed.world.stores, hasLength(3));
      expect(invariantViolations(resumed.world), isEmpty);
      runScripted(resumed, 20);
      expect(invariantViolations(resumed.world), isEmpty);
      expect(
        () => Simulation.load(
          // Without the lane, which its households know of.
          loadScenario(
            testScenarioJson.replaceFirst(
              RegExp(r',\s*\{ "id": "lane"[^}]*\}'),
              '',
            ),
          ),
          old,
        ),
        throwsFormatException,
      );
    },
  );

  test('a saved game grows into new categories, products and segments', () {
    final bread = loadScenario(breadScenarioJson);
    expect(bread.products, hasLength(4));
    final simulation = Simulation.newGame(content, seed: 4);
    runScripted(simulation, 40);
    final before = simulation.world.cohorts.length;

    final resumed = Simulation.load(bread, simulation.save());
    final world = resumed.world;
    for (final store in world.stores) {
      expect(store.prices, hasLength(4));
      expect(store.prices.skip(2), everyElement(isNull));
      expect(store.stock, hasLength(4));
      expect(store.history.productCount, 4);
    }
    for (final cohort in world.cohorts) {
      expect(cohort.needs, hasLength(2));
    }
    final families = world.cohorts.skip(before);
    expect(families.map((c) => c.segment), everyElement(const SegmentId(1)));
    expect(families.fold(0, (sum, c) => sum + c.weight), 24);
    expect(resumed.observe(player).censuses.first.last, (
      day: resumed.today,
      households: 84,
    ));
    expect(invariantViolations(world), isEmpty);

    // The player swaps organic milk for bread, and households buy it.
    const loaf = ProductId(2);
    resumed
      ..submit(DelistProduct(player, store: playerStore, product: milkPremium))
      ..submit(
        ListProduct(
          player,
          store: playerStore,
          product: loaf,
          price: Money(115),
        ),
      )
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: loaf, quantity: 96)],
        ),
      );
    final days = [for (var i = 0; i < 20; i++) resumed.step()];
    expect(invariantViolations(world), isEmpty);
    expect(
      days
          .expand((day) => day.entries)
          .any(
            (entry) =>
                entry.reason == EntryReason.sale && entry.product == loaf,
          ),
      isTrue,
    );
    expect(
      resumed
          .reports(playerCompany, ReportPeriod.week)
          .fold(
            0,
            (sum, week) => sum + (week.store(playerStore)?.sold(loaf) ?? 0),
          ),
      greaterThan(0),
    );
    final file = resumed.save();
    expect(Simulation.load(bread, file).save().bytes, file.bytes);
  });

  group('market levels', () {
    /// The test scenario with the town's [levels] set, staff paid, and only
    /// the player selling milk.
    ContentDb town(String levels) => loadScenario(
      testScenarioJson
          .replaceFirst(
            '"households": { "regulars": 60 } }',
            '"households": { "regulars": 60 }$levels }',
          )
          .replaceFirst('"slotWage": "0.00"', '"slotWage": "1.00"')
          .replaceFirst('"premiumShare": "0.30"', '"premiumShare": "0"')
          .replaceFirst(
            '"substitute": "0.40", "elsewhere": "0.30", "delay": "0.20", "skip": "0.10"',
            '"substitute": "0", "elsewhere": "0", "delay": "0", "skip": "1"',
          ),
    );

    test('load from 0.3 to 3, 1 by default', () {
      final market = town(
        ', "priceLevel": "1.2", "wageLevel": "0.8"',
      ).markets.single;
      expect(market.priceLevel, Fx.parse('1.2'));
      expect(market.wageLevel, Fx.parse('0.8'));
      expect(market.incomeLevel, Fx.one);
      expect(
        () => town(', "incomeLevel": "3.5"'),
        throwsA(
          isA<ContentException>().having(
            (e) => e.path,
            'path',
            'markets[0].incomeLevel',
          ),
        ),
      );
    });

    test('scale what shoppers think a fair price', () {
      bool sells(String levels) {
        final simulation = Simulation.newGame(town(levels), seed: 1)
          ..submit(DelistProduct(rival, store: rivalStore, product: milkBudget))
          ..submit(
            SetPrice(
              player,
              store: playerStore,
              product: milkBudget,
              price: Money(250),
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
        return [
          for (var i = 0; i < 6; i++) simulation.step(),
        ].expand((day) => day.entries).any((e) => e.reason == EntryReason.sale);
      }

      // 2.50 is far beyond the 0.99 reference, but within 10% of 2.38.
      expect(sells(''), isFalse);
      expect(sells(', "priceLevel": "2.4"'), isTrue);
    });

    test('scale wages', () {
      Money wages(String levels) {
        final simulation = Simulation.newGame(town(levels), seed: 1)..step();
        return simulation
            .world
            .companies[playerCompany.index]
            .accounts[AccountKind.wages];
      }

      expect(wages(', "wageLevel": "1.5"'), wages('').times(Fx.parse('1.5')));
      expect(wages('').cents, isPositive);
    });

    test('make households better off', () {
      ResearchReport study(String levels) =>
          (Simulation.newGame(town(levels), seed: 1)
                ..submit(
                  BuyResearch(
                    player,
                    company: playerCompany,
                    market: MarketId(0),
                    tier: ResearchTierId(0),
                  ),
                )
                ..step())
              .observe(player)
              .reports
              .single;

      final plain = study('').segments.single.priceSensitivity;
      final rich = study(', "incomeLevel": "1.5"').segments.single;
      expect(rich.priceSensitivity.raw, lessThan(plain.raw * 8 ~/ 10));
    });
  });
}
