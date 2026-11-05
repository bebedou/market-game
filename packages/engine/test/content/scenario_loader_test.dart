import 'package:engine/engine.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  test('loads definitions and the initial world with dense IDs', () {
    final content = loadScenario(testScenarioJson);
    expect(content.scenarioId, 'test');
    expect(content.startDay, Day.parse('2026-01-01'));
    expect(content.products.map((p) => p.key), ['milk_budget', 'milk_premium']);
    expect(content.products[1].id, milkPremium);
    expect(content.products[1].tier, ProductTier.premium);
    expect(content.products[1].baseCost, Money.parse('1.05'));
    expect(content.companies[1].owner, rival);
    expect(content.stores[0].prices, [Money(95), Money(169)]);
    expect(content.stores[1].prices, [Money(99), null]);
    expect(content.persons.map((p) => p.isPlayer), [true, false]);
  });

  test('loads households, segments and demand tuning', () {
    final content = loadScenario(testScenarioJson);
    expect(content.markets.single.households, [60]);
    expect(content.products[0].referencePrice, Money(99));
    expect(content.stores[1].site, square);
    expect(content.sites[square.index].location, Fx.parse('0.60'));
    final segment = content.segments.single;
    expect(segment.id, regulars);
    expect(segment.tripIntervalDays, 2);
    expect(segment.priceSensitivity, Fx.fromInt(8));
    expect(segment.missResponses, [
      Fx.parse('0.40'),
      Fx.parse('0.30'),
      Fx.parse('0.20'),
      Fx.parse('0.10'),
    ]);
    expect(segment.dailyUnits, [Fx.parse('0.50')]);
    expect(segment.premiumShare, [Fx.parse('0.30')]);
    expect(content.demand.maxNeedDays, 7);
  });

  test('loads sites, bank terms, and stores on their sites', () {
    final content = loadScenario(testScenarioJson);
    expect(content.sites.map((site) => site.key), ['corner', 'square', 'lane']);
    final laneSite = content.sites[lane.index];
    expect(laneSite.rent, Money.parse('100.00'));
    expect(laneSite.openingCost, Money.parse('250.00'));
    expect(laneSite.buildDays, 5);
    expect((laneSite.area, laneSite.maxArea), (80, 120));
    expect(laneSite.rentFor(100), Money.parse('125.00'));
    expect(content.expansion.stepArea, 20);
    expect(content.expansion.cost(Fx.one), Money.parse('200.00'));
    expect(content.demand.halfSizeArea, 100);
    expect(content.segments.single.sizeWeight, Fx.zero);
    expect(content.stores.map((store) => store.site), [corner, square]);
    expect(content.finance.bankMargin, Fx.parse('0.02'));
    expect(content.finance.graceDays, 30);
  });

  test('loads the economy, operations and research', () {
    final content = loadScenario(testScenarioJson);
    expect(content.macro.regimes.single.key, 'steady');
    expect(content.macro.neutralRate, Fx.parse('0.03'));
    expect(content.operations.visitsPerStaff, 30);
    expect(content.researchTiers.single.error, Fx.parse('0.10'));
    expect(content.segments.single.slotShares, [
      Fx.parse('0.25'),
      Fx.parse('0.25'),
      Fx.parse('0.40'),
      Fx.parse('0.10'),
    ]);
    expect(content.strategies.single.hours, [true, true, true, false]);
    expect(content.stores.first.staff, [1, 1, 1, 1]);
  });

  test('loads strategies and which persons follow one', () {
    final content = loadScenario(testScenarioJson);
    final strategy = content.strategies.single;
    expect(strategy.id, steady);
    expect(strategy.markup, Fx.parse('0.40'));
    expect(strategy.marketPosition, Fx.zero);
    expect(strategy.forecastDays, 14);
    expect(strategy.openingForecast, Fx.fromInt(10));
    expect(content.persons.map((p) => p.strategy), [null, null]);
    final withAi = loadScenario(
      testScenarioJson.replaceFirst(
        '"cash": "2000.00" }',
        '"cash": "2000.00", "strategy": "steady" }',
      ),
    );
    expect(withAi.persons[1].strategy, steady);
  });

  test('fingerprint ignores formatting and key order, not content', () {
    final original = loadScenario(testScenarioJson).fingerprint;
    final reordered = testScenarioJson
        .replaceAll('\n', ' ')
        .replaceFirst(
          '{ "id": "town", "name": "Town", "households": { "regulars": 60 } }',
          '{"households":{"regulars":60},"name":"Town","id":"town"}',
        );
    expect(loadScenario(reordered).fingerprint, original);
    expect(reordered, isNot(testScenarioJson.replaceAll('\n', ' ')));
    final changed = testScenarioJson.replaceFirst('"Town"', '"City"');
    expect(loadScenario(changed).fingerprint, isNot(original));
  });

  group('rejects invalid content with the JSON path', () {
    final cases = <String, (String, String)>{
      'decimal written as a JSON number': (
        '"baseCost": "0.55"',
        '"baseCost": 0.55',
      ),
      'unknown reference': ('"owner": "rival"', '"owner": "nobody"'),
      'duplicate id': ('"id": "milk_premium"', '"id": "milk_budget"'),
      'unknown field': ('"name": "Town"', '"name": "Town", "colour": "red"'),
      'missing field': ('"name": "Value Milk", ', ''),
      'second player': (
        '"cash": "2000.00"',
        '"cash": "2000.00", "player": true',
      ),
      'impossible date': ('2026-01-01', '2026-02-30'),
      'unknown tier': ('"tier": "budget"', '"tier": "luxury"'),
      'non-positive price': ('"milk_budget": "0.99"', '"milk_budget": "0.00"'),
      'invalid JSON': ('"id": "test",', '"id": "test"'),
      'supplier sells an unknown product': (
        '"products": ["milk_budget"] }',
        '"products": ["milk_budget", "cheese"] }',
      ),
      'discount of 100%': ('"discount": "0.05"', '"discount": "1.00"'),
      'zero lead time': ('"leadTimeDays": 1', '"leadTimeDays": 0'),
      'more products than shelf slots': ('"shelfSlots": 2', '"shelfSlots": 1'),
      'two products with the same category and tier': (
        '"tier": "premium"',
        '"tier": "budget"',
      ),
      'response odds that do not add up to 1': (
        '"skip": "0.10"',
        '"skip": "0.20"',
      ),
      'segment without a category': (
        '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" } }',
        '"categories": {}',
      ),
      'share above 1': ('"premiumShare": "0.30"', '"premiumShare": "1.30"'),
      'households of an unknown segment': (
        '"households": { "regulars": 60 }',
        '"households": { "tourists": 60 }',
      ),
      'location above 1': ('"location": "0.60"', '"location": "1.20"'),
      'player with an AI strategy': (
        '"player": true }',
        '"player": true, "strategy": "steady" }',
      ),
      'unknown strategy': (
        '"cash": "2000.00" }',
        '"cash": "2000.00", "strategy": "greedy" }',
      ),
      'forecast longer than the sales history': (
        '"forecastDays": 14',
        '"forecastDays": 29',
      ),
      'markup below the minimum': ('"markup": "0.40"', '"markup": "0.05"'),
      'two stores on one site': ('"site": "square"', '"site": "corner"'),
      'store on an unknown site': ('"site": "square"', '"site": "pier"'),
      'slot shares that do not add up to 1': (
        '"night": "0.10" }',
        '"night": "0.20" }',
      ),
      'unknown slot of the day': ('"evening": "0.40"', '"dusk": "0.40"'),
      'too many staff in a slot': (
        '"staff": { "morning": 1',
        '"staff": { "morning": 9',
      ),
      'unknown start regime': (
        '"startRegime": "steady"',
        '"startRegime": "boom"',
      ),
      'strategy opens an unknown slot': (
        '"hours": ["morning"',
        '"hours": ["dawn"',
      ),
      'missing bank terms': (
        '"earningsMultiple": "2", "graceDays": 30 }',
        '"earningsMultiple": "2" }',
      ),
      'site that can only shrink': (
        '"area": 80, "maxArea": 120',
        '"area": 80, "maxArea": 60',
      ),
    };
    final expectedPaths = {
      'decimal written as a JSON number': 'products[0].baseCost',
      'unknown reference': 'companies[1].owner',
      'duplicate id': 'products[1].id',
      'unknown field': 'markets[0].colour',
      'missing field': 'products[0].name',
      'second player': 'persons',
      'impossible date': 'startDate',
      'unknown tier': 'products[0].tier',
      'non-positive price': 'stores[1].prices.milk_budget',
      'invalid JSON': '',
      'supplier sells an unknown product': 'suppliers[1].products[1]',
      'discount of 100%': 'suppliers[0].volumeDiscounts[0].discount',
      'zero lead time': 'suppliers[1].leadTimeDays',
      'more products than shelf slots': 'stores[0].prices',
      'two products with the same category and tier': 'products[1].tier',
      'response odds that do not add up to 1': 'segments[0].missResponses',
      'segment without a category': 'segments[0].categories',
      'share above 1': 'segments[0].categories.milk.premiumShare',
      'households of an unknown segment': 'markets[0].households.tourists',
      'location above 1': 'sites[1].location',
      'player with an AI strategy': 'persons[0].strategy',
      'unknown strategy': 'persons[1].strategy',
      'forecast longer than the sales history': 'strategies[0].forecastDays',
      'markup below the minimum': 'strategies[0].markup',
      'two stores on one site': 'stores[1].site',
      'store on an unknown site': 'stores[1].site',
      'missing bank terms': 'finance.graceDays',
      'site that can only shrink': 'sites[2].maxArea',
      'slot shares that do not add up to 1': 'segments[0].slots',
      'unknown slot of the day': 'segments[0].slots.dusk',
      'too many staff in a slot': 'stores[0].staff.morning',
      'unknown start regime': 'macro.startRegime',
      'strategy opens an unknown slot': 'strategies[0].hours[0]',
    };
    for (final MapEntry(key: name, value: (find, replace)) in cases.entries) {
      test(name, () {
        final json = testScenarioJson.replaceFirst(find, replace);
        expect(json, isNot(testScenarioJson), reason: 'fixture edit failed');
        expect(
          () => loadScenario(json),
          throwsA(
            isA<ContentException>().having(
              (e) => e.path,
              'path',
              expectedPaths[name],
            ),
          ),
        );
      });
    }
  });
}
