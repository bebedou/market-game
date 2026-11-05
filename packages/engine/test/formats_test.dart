import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const groceries = FormatId(0);
const diner = FormatId(1);
const burger = ProductId(2);
const steak = ProductId(3);
const kitchen = SupplierId(2);

/// The test scenario with meals: a diner format sells them, groceries sell
/// milk, households eat out now and then, and a kitchen supplier sells the
/// dishes' ingredients. The lane stays vacant for a diner.
String withMeals({String demand = ''}) => testScenarioJson
    .replaceFirst(
      '"categories": [{ "id": "milk", "name": "Milk" }],',
      '"categories": [{ "id": "milk", "name": "Milk" }, { "id": "meals", "name": "Meals" }],\n'
          '  "formats": [\n'
          '    { "id": "grocery", "name": "Grocery store", "categories": ["milk"] },\n'
          '    { "id": "diner", "name": "Diner", "categories": ["meals"], "fitOut": "1.5", "visitsPerStaff": 10 }\n'
          '  ],',
    )
    .replaceFirst(
      '"referencePrice": "1.79" }',
      '"referencePrice": "1.79" },\n'
          '    { "id": "burger", "name": "Burger", "category": "meals", "tier": "budget", "shelfLifeDays": 3,\n'
          '      "baseCost": "3.00", "referencePrice": "9.00" },\n'
          '    { "id": "steak", "name": "Steak", "category": "meals", "tier": "premium", "shelfLifeDays": 3,\n'
          '      "baseCost": "7.00", "referencePrice": "19.00" }',
    )
    .replaceFirst(
      '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" } },',
      '"categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" },\n'
          '        "meals": { "dailyUnits": "0.20", "premiumShare": "0.20" } },',
    )
    .replaceFirst(
      '"products": ["milk_budget"] }\n  ],',
      '"products": ["milk_budget"] },\n'
          '    { "id": "kitchen", "name": "Kitchen", "leadTimeDays": 1, "paymentTermsDays": 0, "priceFactor": "1.00",\n'
          '      "minOrderUnits": 10, "products": ["burger", "steak"] }\n  ],',
    )
    .replaceFirst('"halfSizeArea": 100 }', '"halfSizeArea": 100$demand }');

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

/// Units sold during [days], by store and product.
Map<(StoreId?, ProductId?), int> soldDuring(List<TickResult> days) {
  final sold = <(StoreId?, ProductId?), int>{};
  for (final day in days) {
    for (final entry in day.entries) {
      if (entry.reason == EntryReason.sale &&
          entry.party.type == PartyType.company) {
        final key = (entry.store, entry.product);
        sold[key] = (sold[key] ?? 0) + entry.units;
      }
    }
  }
  return sold;
}

/// Opens a diner on the lane for the player, lists both dishes and orders
/// their ingredients.
Simulation withDiner(ContentDb content) {
  final simulation = Simulation.newGame(content, seed: 2)
    ..submit(
      OpenStore(
        player,
        site: lane,
        name: 'Diner',
        company: playerCompany,
        format: diner,
      ),
    );
  advance(simulation, 1);
  final store = StoreId(simulation.world.stores.length - 1);
  simulation
    ..submit(
      ListProduct(player, store: store, product: burger, price: Money(900)),
    )
    ..submit(
      ListProduct(player, store: store, product: steak, price: Money(1900)),
    )
    ..submit(SetStaffing(player, store: store, staff: const [1, 1, 1, 1]));
  advance(simulation, 5);
  for (var i = 0; i < 12; i++) {
    simulation.submit(
      PlaceOrder(
        player,
        store: store,
        supplier: kitchen,
        lines: [
          (product: burger, quantity: 20),
          (product: steak, quantity: 10),
        ],
      ),
    );
    simulation.submit(
      PlaceOrder(
        player,
        store: playerStore,
        supplier: fresh,
        lines: [(product: milkBudget, quantity: 24)],
      ),
    );
    advance(simulation, 2);
  }
  return simulation;
}

void main() {
  group('formats', () {
    test('load, and group into channels by what they sell', () {
      final content = loadScenario(withMeals());
      expect(content.formats.map((f) => f.key), ['grocery', 'diner']);
      expect(content.formatChannels, [0, 1]);
      expect(content.channelCategories, [
        [const CategoryId(0)],
        [const CategoryId(1)],
      ]);
      expect(content.formats[diner.index].fitOut, Fx.parse('1.5'));
      expect(content.formats[diner.index].visitsPerStaff, 10);
      // Without formats, one sells everything.
      final plain = loadScenario(testScenarioJson);
      expect(plain.formats.single.sells, [true]);
      // Formats selling a category in common share a channel.
      final shared = loadScenario(
        withMeals().replaceFirst(
          '"categories": ["meals"]',
          '"categories": ["meals", "milk"]',
        ),
      );
      expect(shared.formatChannels, [0, 0]);
      expect(shared.channelCategories.single, hasLength(2));
      expect(
        () => loadScenario(
          withMeals().replaceFirst(
            '"prices": { "milk_budget": "0.99" } }',
            '"prices": { "milk_budget": "0.99", "burger": "9.00" } }',
          ),
        ),
        throwsA(
          isA<ContentException>().having(
            (e) => e.message,
            'message',
            contains('does not sell'),
          ),
        ),
      );
    });

    test('set what a store may list, and what fitting it out costs', () {
      final content = loadScenario(withMeals());
      final simulation = Simulation.newGame(content, seed: 1)
        ..submit(
          ListProduct(
            player,
            store: playerStore,
            product: burger,
            price: Money(900),
          ),
        );
      final refused = simulation.step().rejections.single;
      expect(refused.reason.key, 'formatDoesNotSell');

      final cash = simulation.observe(player).companies.single.cash;
      simulation.submit(
        OpenStore(
          player,
          site: lane,
          name: 'Diner',
          company: playerCompany,
          format: diner,
        ),
      );
      expect(simulation.step().rejections, isEmpty);
      final store = simulation.world.stores.last;
      expect(store.format, diner);
      // 250.00 times one and a half.
      final paid = cash - simulation.observe(player).companies.single.cash;
      expect(paid, Money.parse('375.00'));
    });

    test('households eat out at diners and shop at grocery stores', () {
      final simulation = withDiner(loadScenario(withMeals()));
      final diner = StoreId(simulation.world.stores.length - 1);
      final sold = soldDuring(advance(simulation, 20));
      expect(sold[(diner, burger)], greaterThan(0));
      expect(sold[(diner, milkBudget)], isNull);
      expect(sold[(playerStore, burger)], isNull);
      expect(
        (sold[(playerStore, milkBudget)] ?? 0) +
            (sold[(rivalStore, milkBudget)] ?? 0),
        greaterThan(0),
      );
    });

    test('serve as many customers per member of staff as the format says', () {
      final content = loadScenario(withMeals());
      final simulation =
          Simulation.newGame(content, seed: 1, systems: quietSystems)..submit(
            OpenStore(
              player,
              site: lane,
              name: 'Diner',
              company: playerCompany,
              format: diner,
            ),
          );
      simulation.step();
      final store = simulation.world.stores.last;
      store
        ..staff[1] = 1
        ..traffic[1] = 15;
      simulation.step();
      // One member of staff serves 10 diners, not 30 shoppers.
      expect(store.service[1], Fx.raw(10 * Fx.scale ~/ 15));
    });

    test('open diners for an entrepreneur whose strategy runs them', () {
      final content = loadScenario(
        withMeals()
            .replaceFirst(
              '"name": "Rival", "cash": "2000.00" }',
              '"name": "Rival", "cash": "6000.00", "strategy": "steady" }',
            )
            .replaceFirst(
              '"expansionPaybackMonths": 0',
              '"expansionPaybackMonths": 24',
            )
            .replaceFirst(
              '"expansionIntervalDays": 365',
              '"expansionIntervalDays": 0',
            )
            .replaceFirst(
              '"hours": ["morning", "midday", "evening"],',
              '"hours": ["morning", "midday", "evening"], "format": "diner",',
            )
            .replaceFirst(
              '"marginPerHousehold": "0.30"',
              '"marginPerHousehold": "3.00"',
            ),
      );
      expect(content.strategies.single.format, diner);
      final simulation = Simulation.newGame(content, seed: 1);
      advance(simulation, 40);
      final opened = simulation.world.stores.skip(2);
      expect(opened, isNotEmpty);
      expect(opened.map((store) => store.format), everyElement(diner));
    });
  });

  group('marketing', () {
    final marketed = withMeals(
      demand:
          ', "marketingWeight": "2", "halfGoodwill": "20.00", '
          '"goodwillDecay": "0.10"',
    );

    /// A game where the player's store has sold milk for a week.
    Simulation stocked(ContentDb content) {
      final simulation = Simulation.newGame(content, seed: 1);
      for (var i = 0; i < 4; i++) {
        simulation.submit(
          PlaceOrder(
            player,
            store: playerStore,
            supplier: fresh,
            lines: [(product: milkBudget, quantity: 24)],
          ),
        );
        advance(simulation, 2);
      }
      return simulation;
    }

    test('is a share of sales set within limits, paid daily, and builds '
        'goodwill that wears off', () {
      final content = loadScenario(marketed);
      expect(content.demand.halfGoodwill, Money.parse('20.00'));
      expect(content.demand.goodwillDecay, Fx.parse('0.10'));
      final simulation = stocked(content)
        ..submit(
          SetMarketing(player, store: playerStore, share: Fx.parse('-0.1')),
        )
        ..submit(
          SetMarketing(player, store: rivalStore, share: Fx.parse('0.05')),
        )
        ..submit(
          SetMarketing(player, store: playerStore, share: Fx.parse('0.3')),
        );
      expect(simulation.step().rejections.map((r) => r.reason.key), [
        'shareNegative',
        'notYourStore',
        'marketingCap',
      ]);
      final world = simulation.world;
      final store = world.stores[playerStore.index];
      final sales = store.recentDailySales(simulation.today);
      expect(sales.cents, greaterThan(0));
      simulation.submit(
        SetMarketing(player, store: playerStore, share: Fx.parse('0.10')),
      );
      simulation.step();
      // A tenth of the week's daily sales, spent today, is all its goodwill.
      final spent =
          world.companies[playerCompany.index].accounts[AccountKind.marketing];
      expect(spent, sales.times(Fx.parse('0.10')));
      expect(store.goodwill, spent);
      // Stopping, it loses a tenth a day.
      simulation.submit(
        SetMarketing(player, store: playerStore, share: Fx.zero),
      );
      simulation.step();
      expect(store.goodwill, spent - spent.times(Fx.parse('0.10')));
      final resumed = Simulation.load(content, simulation.save());
      expect(resumed.world.stores[playerStore.index].goodwill, store.goodwill);
      expect(resumed.stateHash(), simulation.stateHash());
    });

    test('draws shoppers away from a store that does none', () {
      int playerVisits({Fx? share}) {
        final simulation = stocked(loadScenario(marketed));
        if (share != null) {
          simulation.submit(
            SetMarketing(player, store: playerStore, share: share),
          );
        }
        var visits = 0;
        for (var i = 0; i < 8; i++) {
          simulation.submit(
            PlaceOrder(
              player,
              store: playerStore,
              supplier: fresh,
              lines: [(product: milkBudget, quantity: 24)],
            ),
          );
          for (final day in advance(simulation, 3)) {
            visits += day.attribution.visits[playerStore.index];
          }
        }
        return visits;
      }

      final without = playerVisits();
      final with_ = playerVisits(share: Fx.parse('0.20'));
      expect(with_, greaterThan(without * 11 ~/ 10));
    });

    test('is the strategy share for an AI owner', () {
      final content = loadScenario(
        marketed
            .replaceFirst(
              '"name": "Rival", "cash": "2000.00" }',
              '"name": "Rival", "cash": "2000.00", "strategy": "steady" }',
            )
            .replaceFirst(
              '"openingTraffic": 10',
              '"openingTraffic": 10, "marketingShare": "0.05"',
            ),
      );
      final simulation = Simulation.newGame(content, seed: 1)..step();
      expect(
        simulation.world.stores[rivalStore.index].marketingShare,
        Fx.parse('0.05'),
      );
    });
  });
}
