import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with a restaurant format, and a bistro in the lane when
/// [bistro] is true. Meals are a category of their own, so no grocer sells them.
ContentDb _scenario({int households = 60, bool bistro = false}) {
  var json = testScenarioJson;
  void edit(String from, String to) {
    if (!json.contains(from)) throw StateError('The fixture has no $from');
    json = json.replaceFirst(from, to);
  }

  edit('"regulars": 60', '"regulars": $households');
  edit(
    '"categories": [{ "id": "milk", "name": "Milk" }],',
    '"categories": [{ "id": "milk", "name": "Milk" }, { "id": "meals", "name": "Meals" }],\n'
        '  "formats": [\n'
        '    { "id": "grocery", "name": "Grocer", "overheads": "1.00", "categories": ["milk"] },\n'
        '    { "id": "bistro", "name": "Bistro", "overheads": "1.00", "categories": ["meals"] }\n'
        '  ],',
  );
  edit(
    '"baseCost": "1.05", "referencePrice": "1.79" }',
    '"baseCost": "1.05", "referencePrice": "1.79" },\n'
        '    { "id": "meal", "name": "Meal", "category": "meals", "tier": "budget", "shelfLifeDays": 3,\n'
        '      "baseCost": "3.00", "referencePrice": "10.00" }',
  );
  edit(
    '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" } }',
    '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" }, '
        '"meals": { "dailyUnits": "0.10", "premiumShare": "0" } }',
  );
  edit(
    '"products": ["milk_budget", "milk_premium"] }',
    '"products": ["milk_budget", "milk_premium", "meal"] }',
  );
  if (bistro) {
    edit(
      '"persons": [',
      '"persons": [\n'
          '    { "id": "chef", "name": "Chef", "cash": "1000.00" },',
    );
    edit(
      '"companies": [',
      '"companies": [\n'
          '    { "id": "chef_co", "name": "Chef Co", "owner": "chef", "cash": "500.00" },',
    );
    edit(
      '"stores": [',
      '"stores": [\n'
          '    { "id": "bistro_store", "name": "Bistro", "company": "chef_co", "site": "lane", "format": "bistro",\n'
          '      "staff": { "midday": 1, "evening": 1 }, "prices": { "meal": "10.00" } },',
    );
  }
  return loadScenario(json);
}

ShopOutlook _outlook(ContentDb content, SiteId site, String format) {
  final simulation = Simulation.newGame(content, seed: 1, policies: const {});
  return shopOutlook(
    simulation.observe(content.player),
    content,
    content.sites[site.index],
    content.formats.firstWhere((f) => f.key == format),
  );
}

void main() {
  group('a new shop\'s outlook', () {
    test('counts rivals only in its own trade', () {
      final plain = _scenario();
      final grocer = _outlook(plain, lane, 'grocery');
      // The player's grocer and the rival's.
      expect(grocer.rivals, 2);
      final bistro = _outlook(plain, lane, 'bistro');
      expect(bistro.rivals, 0);
      expect(bistro.share, Fx.one);
    });

    test('a restaurant takes nothing from a grocer', () {
      final without = _outlook(_scenario(), lane, 'bistro');
      final beside = _scenario(bistro: true);
      final withOne = _outlook(beside, lane, 'bistro');
      expect(withOne.rivals, 1);
      expect(withOne.share < without.share, isTrue);
      // A grocer's trade is just as it was with no bistro.
      final alone = _outlook(_scenario(), lane, 'grocery');
      final byBistro = _outlook(beside, lane, 'grocery');
      expect(byBistro.rivals, alone.rivals);
      expect(byBistro.share, alone.share);
      expect(byBistro.sales, alone.sales);
    });

    test('what households spend grows with them, and a shop with it', () {
      final few = _outlook(_scenario(households: 60), lane, 'bistro');
      final many = _outlook(_scenario(households: 300), lane, 'bistro');
      expect(many.spending > few.spending, isTrue);
      expect(many.sales > few.sales, isTrue);
      expect(many.profit > few.profit, isTrue);
    });

    test('tells a market\'s whole trade, shop or no shop', () {
      final content = _scenario();
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        policies: const {},
      );
      final view = simulation.observe(content.player);
      final format = content.formats.firstWhere((f) => f.key == 'grocery');
      expect(
        tradeSpending(view, content, content.markets.first, format),
        _outlook(content, lane, 'grocery').spending,
      );
    });

    test('changes nothing in the game', () {
      final content = _scenario();
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        policies: const {},
      );
      final before = simulation.stateHash();
      shopOutlook(
        simulation.observe(content.player),
        content,
        content.sites[lane.index],
        content.formats.first,
      );
      expect(simulation.stateHash(), before);
    });
  });
}
