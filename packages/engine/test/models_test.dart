import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const convenience = FormatId(0);

/// The test scenario where milk sells at convenience stores, whose large
/// size, a supermarket, starts at [large] m², adds two slots and 300 units
/// of storage, serves 45 shoppers a member of staff and costs half as much
/// again to fit out.
String withSupermarkets({
  String demand = '',
  int large = 120,
}) => testScenarioJson
    .replaceFirst(
      '"categories": [{ "id": "milk", "name": "Milk" }],',
      '"categories": [{ "id": "milk", "name": "Milk" }],\n'
          '  "formats": [\n'
          '    { "id": "convenience", "name": "Convenience store", "categories": ["milk"],\n'
          '      "large": { "id": "supermarket", "name": "Supermarket", "area": $large,\n'
          '        "fitOut": "1.5", "visitsPerStaff": 45, "shelfSlots": 2, "storageUnits": 300 } }\n'
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

  group("a grocer's sizes", () {
    test('a site with room opens a supermarket at once, built out as it is '
        'fitted, paying for both', () {
      final content = loadScenario(withSupermarkets());
      final format = content.formats[convenience.index];
      final lane = content.sites[2];
      expect((lane.area, lane.maxArea), (80, 120));
      expect(lane.openingAreas(format), [80, 120]);
      expect(format.isLargeAt(120), isTrue);
      expect(format.isLargeAt(80), isFalse);
      expect(
        (format.visitsPerStaffAt(80), format.visitsPerStaffAt(120)),
        (30, 45),
      );
      final simulation = Simulation.newGame(content, seed: 1);
      final world = simulation.world;
      final cash =
          world.companies[playerCompany.index].accounts[AccountKind.cash];
      simulation.submit(
        OpenStore(
          player,
          site: lane.id,
          name: 'Lane Market',
          company: playerCompany,
          format: convenience,
          capital: Money.parse('1000.00'),
          area: 120,
        ),
      );
      expect(simulation.step().rejections.map((r) => r.reason.key), isEmpty);
      // The fit-out, 250.00 times 1.5, 40 m² of works at 10.00, and the
      // first month's rent, for 120 m² of a site let at 100.00 for 80.
      expect(
        cash +
            Money.parse('1000.00') -
            world.companies[playerCompany.index].accounts[AccountKind.cash],
        Money.parse('375.00') + Money.parse('400.00') + Money.parse('150.00'),
      );
      final store = world.stores.last;
      expect(store.format, convenience);
      expect(store.area, 120);
      // Two slots, two for the 40 m² and two for its size; storage the
      // same way.
      expect(store.shelfSlots, 6);
      expect(store.storageUnits, 300 + 200 + 300);
    });

    test('a floor the site does not offer is refused, and a shop keeps the '
        "site's own without one", () {
      final content = loadScenario(withSupermarkets(large: 200));
      final lane = content.sites[2];
      expect(lane.openingAreas(content.formats[convenience.index]), [80]);
      final simulation = Simulation.newGame(content, seed: 1)
        ..submit(
          OpenStore(
            player,
            site: lane.id,
            name: 'Lane Market',
            company: playerCompany,
            format: convenience,
            capital: Money.parse('1000.00'),
            area: 120,
          ),
        );
      expect(simulation.step().rejections.single.reason.key, 'floorNotOffered');
      simulation.submit(
        OpenStore(
          player,
          site: lane.id,
          name: 'Lane Shop',
          company: playerCompany,
          format: convenience,
          capital: Money.parse('1000.00'),
        ),
      );
      expect(simulation.step().rejections, isEmpty);
      final store = simulation.world.stores.last;
      expect((store.area, store.shelfSlots), (80, 2));
    });
  });
}
