import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with reputations: shoppers weigh them, a known store
/// starts at 0.80 and a new one at 0.20, moving a tenth of the way each day.
String withReputation(String json, {String weight = '1.0'}) =>
    json.replaceFirst(
      '"offHoursPenalty": "1.5", "halfSizeArea": 100 }',
      '"offHoursPenalty": "1.5", "halfSizeArea": 100, '
          '"reputationWeight": "$weight", "reputationDays": 10, '
          '"establishedReputation": "0.80", "openingReputation": "0.20" }',
    );

void main() {
  final content = loadScenario(withReputation(testScenarioJson));

  test('load, and are off unless the scenario sets them', () {
    final demand = content.demand;
    expect(demand.reputationWeight, Fx.one);
    expect(demand.reputationDays, 10);
    expect(demand.establishedReputation, Fx.parse('0.80'));
    expect(demand.openingReputation, Fx.parse('0.20'));
    final plain = loadScenario(testScenarioJson).demand;
    expect(plain.reputationWeight, Fx.zero);
    expect(plain.openingReputation, Fx.zero);
  });

  test("start known for the rivals' stores, new for the player's and any "
      'opened later', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    Fx reputation(StoreId store) =>
        simulation.world.stores[store.index].reputation;
    expect(reputation(rivalStore), Fx.parse('0.80'));
    expect(reputation(playerStore), Fx.parse('0.20'));
    simulation
      ..submit(OpenStore(player, site: lane, name: 'Lane', company: playerCompany))
      ..step();
    expect(reputation(const StoreId(2)), Fx.parse('0.20'));
    expect(
      simulation.observe(player).companies.first.stores.first.reputation,
      Fx.parse('0.20'),
      reason: 'its owner sees it',
    );
  });

  test('build up with stocked shelves and wear away with empty ones', () {
    // An ace manager keeps the player's shelves stocked; nobody restocks
    // the rival's, which start empty.
    final simulation = Simulation.newGame(content, seed: 1)
      ..submit(
        HireManager(
          player,
          store: playerStore,
          grade: const ManagerGradeId(1),
          strategy: steady,
          duties: const [true, true, true, true, true],
        ),
      );
    for (var i = 0; i < 60; i++) {
      simulation.step();
    }
    final stores = simulation.world.stores;
    expect(stores[playerStore.index].reputation.raw, greaterThan(Fx.parse('0.60').raw));
    expect(stores[rivalStore.index].reputation.raw, lessThan(Fx.parse('0.20').raw));
    expect(
      simulation.observe(player).companies.first.stores.first.reputation,
      stores[playerStore.index].reputation,
    );
  });

  test('draw shoppers to the store with the better name', () {
    int rivalVisits(String weight) {
      final simulation = Simulation.newGame(
        loadScenario(withReputation(testScenarioJson, weight: weight)),
        seed: 1,
      );
      var visits = 0;
      for (var i = 0; i < 10; i++) {
        visits += simulation.step().attribution.visits[rivalStore.index];
      }
      return visits;
    }

    expect(rivalVisits('2.0'), greaterThan(rivalVisits('0')));
  });
}
