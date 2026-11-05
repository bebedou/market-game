import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const convenience = FormatId(0);
const supermarket = FormatId(1);

/// The test scenario where milk sells at convenience stores and at
/// supermarkets, which need 120 m² and add two slots and 300 units of
/// storage, and cost half as much again to fit out.
String withSupermarkets({String demand = ''}) => testScenarioJson
    .replaceFirst(
      '"categories": [{ "id": "milk", "name": "Milk" }],',
      '"categories": [{ "id": "milk", "name": "Milk" }],\n'
          '  "formats": [\n'
          '    { "id": "convenience", "name": "Convenience store", "categories": ["milk"] },\n'
          '    { "id": "supermarket", "name": "Supermarket", "categories": ["milk"], "fitOut": "1.5",\n'
          '      "visitsPerStaff": 45, "minArea": 120, "slotBonus": 2, "storageBonus": 300 }\n'
          '  ],',
    )
    .replaceFirst('"halfSizeArea": 100 }', '"halfSizeArea": 100$demand }');

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

void main() {
  test('Bass diffusion follows its closed form', () {
    final bass = Diffusion(
      innovation: Fx.parse('0.03'),
      imitation: Fx.parse('0.38'),
      launched: Day.parse('2026-01-01'),
    );
    expect(bass.adoption(Day.parse('2026-01-01')), Fx.zero);
    // F(5) = (1 − e^−2.05) / (1 + 12.67·e^−2.05) = 0.331.
    final five = bass.adoption(Day.parse('2031-01-01'));
    expect(five.raw, inInclusiveRange(3260, 3360));
    expect(bass.adoption(Day.parse('2056-01-01')).raw, greaterThan(9900));
    final content = loadScenario(
      testScenarioJson.replaceFirst(
        '{ "id": "milk", "name": "Milk" }',
        '{ "id": "milk", "name": "Milk", "diffusion": { "innovation": "0.03", '
            '"imitation": "0.38", "launched": "2021-01-01" } }',
      ),
    );
    expect(
      content.categories.single.diffusion!.adoption(content.startDay).raw,
      inInclusiveRange(3260, 3360),
    );
  });

  test('loss aversion makes a dear store lose more shoppers', () {
    int playerVisits(String aversion) {
      final simulation =
          Simulation.newGame(
            loadScenario(
              testScenarioJson.replaceFirst(
                '"halfSizeArea": 100 }',
                '"halfSizeArea": 100, "lossAversion": "$aversion" }',
              ),
            ),
            seed: 5,
          )..submit(
            SetPrice(
              player,
              store: playerStore,
              product: milkBudget,
              price: Money(120),
            ),
          );
      var visits = 0;
      for (final day in advance(simulation, 40)) {
        visits += day.attribution.visits[playerStore.index];
      }
      return visits;
    }

    expect(loadScenario(testScenarioJson).demand.lossAversion, Fx.one);
    expect(playerVisits('2.5'), lessThan(playerVisits('1')));
  });

  group('converting a store', () {
    test('turns a convenience store into a supermarket through works', () {
      final content = loadScenario(withSupermarkets());
      expect(content.formatChannels, [0, 0]);
      final simulation = Simulation.newGame(content, seed: 1);
      final world = simulation.world;
      final store = world.stores[playerStore.index];
      expect(store.area, 100);
      final cash =
          world.companies[playerCompany.index].accounts[AccountKind.cash];
      simulation.submit(
        ConvertStore(player, store: playerStore, format: supermarket),
      );
      expect(simulation.step().rejections, isEmpty);
      // Half the 300.00 fit-out again, and 20 m² at 10.00.
      expect(
        cash - world.companies[playerCompany.index].accounts[AccountKind.cash],
        Money.parse('350.00'),
      );
      expect(store.works?.format, supermarket);
      expect(store.format, convenience);
      advance(simulation, 7);
      expect(store.format, supermarket);
      expect(store.area, 120);
      // Two slots to start, one for the extra 20 m², two for the format.
      expect(store.shelfSlots, 5);
      expect(store.storageUnits, 400 + 100 + 300);
    });

    test('is refused across channels, on a small site, or twice', () {
      final content = loadScenario(
        withSupermarkets().replaceFirst('"minArea": 120', '"minArea": 200'),
      );
      final simulation = Simulation.newGame(content, seed: 1)
        ..submit(ConvertStore(player, store: playerStore, format: supermarket))
        ..submit(ConvertStore(player, store: playerStore, format: convenience));
      expect(simulation.step().rejections.map((r) => r.reason.key), [
        'siteTooSmall',
        'alreadyFormat',
      ]);
      expect(
        Simulation.newGame(
          loadScenario(withSupermarkets()),
          seed: 1,
        ).step().rejections,
        isEmpty,
      );
    });

    test('a supermarket competes for the same grocery trips', () {
      final content = loadScenario(withSupermarkets());
      final simulation = Simulation.newGame(content, seed: 1)
        ..submit(ConvertStore(player, store: playerStore, format: supermarket));
      advance(simulation, 8);
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 48)],
        ),
      );
      var visits = 0;
      for (final day in advance(simulation, 10)) {
        visits += day.attribution.visits[playerStore.index];
      }
      expect(simulation.world.stores[playerStore.index].format, supermarket);
      expect(visits, greaterThan(0));
    });
  });
}
