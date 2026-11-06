@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/neighbourhoods.dart';
import 'package:engine/src/state/game_start.dart' show playerSetup;
import 'package:test/test.dart';

final _scenario = File(
  '../../content/scenarios/prototype.json',
).readAsStringSync();
final _content = loadScenario(_scenario);

/// A row with [households] of each segment, Lyon's costs and space otherwise.
NeighbourhoodRow _row(
  String key, {
  required int households,
  String income = '1',
  int largestArea = 160,
}) {
  final lyon = rowsFromScenario(_content).first;
  return NeighbourhoodRow(
    key: key,
    name: key,
    households: [for (final _ in _content.segments) households],
    growth: lyon.growth,
    priceLevel: lyon.priceLevel,
    wageLevel: lyon.wageLevel,
    incomeLevel: Fx.parse(income),
    rent: lyon.rent,
    typicalArea: lyon.typicalArea,
    largestArea: largestArea,
    room: lyon.room,
  );
}

Map<String, dynamic> _world(List<NeighbourhoodRow> rows, {int seed = 1}) =>
    jsonDecode(generateScenario(_scenario, rows, seed: seed))
        as Map<String, dynamic>;

/// The formats of the stores generated in [market], in order.
List<String> _formats(Map<String, dynamic> world, String market) {
  final sites = {
    for (final site in world['sites'] as List) site['id']: site['market'],
  };
  return [
    for (final store in world['stores'] as List)
      if (sites[store['site']] == market) store['format'] as String,
  ];
}

/// What each market's grocers sold over two years of [json]'s game, in cents.
Map<String, int> _grocerySales(String json) {
  final content = loadScenario(json);
  final balanced = content.strategies.firstWhere((s) => s.key == 'balanced');
  final simulation = Simulation.newGame(
    content,
    seed: 1,
    policies: {
      ...standardPolicies(content),
      content.player: ownerPolicy(balanced),
    },
  );
  final sold = {for (final market in content.markets) market.key: 0};
  for (var day = 0; day < 2 * 365; day++) {
    simulation.step();
    final world = simulation.world;
    if (!world.today.isFirstOfMonth) continue;
    for (final (i, _) in world.companies.indexed) {
      final reports = simulation.reports(CompanyId(i), ReportPeriod.month);
      if (reports.length < 2) continue;
      for (final store in reports[reports.length - 2].stores) {
        final state = world.stores[store.store.index];
        final format = content.formats[state.format.index].key;
        if (format != 'grocery' && format != 'supermarket') continue;
        final market = content.markets[state.market.index].key;
        sold[market] = sold[market]! + store.totalRevenue.cents;
      }
    }
  }
  return sold;
}

void main() {
  final rows = rowsFromScenario(_content);

  group('a row', () {
    test('holds what households and costs come to in a city, and no site', () {
      final lyon = rows.first;
      expect(lyon.key, 'neighborhood');
      expect(lyon.totalHouseholds, 1600);
      expect(lyon.typicalArea, 121);
      expect(lyon.largestArea, 160);
      expect(lyon.room, 112);
      expect(lyon.rent.cents, inInclusiveRange(530, 560));
      expect(lyon.playerStartsHere, isTrue);
      expect(rows.skip(1).any((row) => row.playerStartsHere), isFalse);
    });
  });

  group('a generated world', () {
    test('is the same from the same seed, and not from another', () {
      expect(
        generateScenario(_scenario, rows, seed: 1),
        generateScenario(_scenario, rows, seed: 1),
      );
      expect(
        generateScenario(_scenario, rows, seed: 1),
        isNot(generateScenario(_scenario, rows, seed: 2)),
      );
    });

    test('loads, with its row\'s households, growth and levels', () {
      final made = loadScenario(generateScenario(_scenario, rows, seed: 1));
      expect(made.markets, hasLength(rows.length));
      for (final (i, market) in made.markets.indexed) {
        final row = rows[i];
        expect(market.key, row.key);
        expect(market.households, row.households);
        expect(market.growth, row.growth);
        expect(market.priceLevel, row.priceLevel);
        expect(market.wageLevel, row.wageLevel);
        expect(market.incomeLevel, row.incomeLevel);
        // As many cohorts as by hand: fewer break the economy.
        expect(market.agents, _content.markets[i].agents);
      }
    });

    test('keeps everything but the cities', () {
      final original = jsonDecode(_scenario) as Map<String, dynamic>;
      final world = _world(rows);
      const replaced = {'markets', 'sites', 'stores', 'companies', 'persons'};
      for (final key in original.keys) {
        if (replaced.contains(key)) continue;
        expect(jsonEncode(world[key]), jsonEncode(original[key]), reason: key);
      }
      final people = {for (final p in world['persons'] as List) p['id']};
      // The owners waiting to open a first store are still there.
      expect(people, containsAll(['player', 'entrepreneur_gastro']));
    });

    test('leaves the player\'s first store as it was, on a usual site', () {
      final made = loadScenario(generateScenario(_scenario, rows, seed: 3));
      final setup = playerSetup(made)!;
      final store = made.stores[setup.store];
      final usual = _content.stores[playerSetup(_content)!.store];
      expect(store.prices, usual.prices);
      expect(store.staff, usual.staff);
      expect(store.format, usual.format);
      expect(
        made.companies[setup.company].cash,
        _content.companies[playerSetup(_content)!.company].cash,
      );
      final site = made.sites[store.site.index];
      expect(site.market, const MarketId(0));
      expect(site.location, Fx.parse('0.5'));
      expect(site.area, rows.first.typicalArea);
      expect(site.storageUnits, 1500);
    });

    test('gives every other store an owner of its own with a strategy', () {
      final made = loadScenario(generateScenario(_scenario, rows, seed: 2));
      final owners = <PersonId>{};
      for (final store in made.stores) {
        final owner = made.companies[store.company.index].owner;
        expect(owners.add(owner), isTrue);
        if (owner == made.player) continue;
        expect(made.persons[owner.index].strategy, isNotNull);
      }
    });

    test('adding a neighbourhood leaves the others as they were', () {
      final first = _world(rows.sublist(0, 2));
      final more = _world(rows.sublist(0, 3));
      List<Object?> sitesIn(Map<String, dynamic> world) => [
        for (final site in world['sites'] as List)
          if (site['market'] != rows[2].key) site,
      ];
      expect(jsonEncode(sitesIn(more)), jsonEncode(sitesIn(first)));
    });

    test('plays a year with every store visited and nobody wound up', () {
      final made = loadScenario(generateScenario(_scenario, rows, seed: 1));
      final simulation = Simulation.newGame(
        made,
        seed: 1,
        policies: standardPolicies(made),
      );
      final visits = List.filled(made.stores.length, 0);
      for (var day = 0; day < 365; day++) {
        final result = simulation.step();
        for (var i = 0; i < visits.length; i++) {
          visits[i] += result.attribution.visits[i];
        }
      }
      // Nobody runs the player's store here, so it has no stock and fails.
      final player = playerSetup(made)!;
      for (final (i, count) in visits.indexed) {
        if (i != player.store) expect(count, greaterThan(1000));
      }
      for (final (i, company) in simulation.world.companies.indexed) {
        if (i != player.company) expect(company.status, CompanyStatus.active);
      }
    });
  });

  // Fails if the generator and the hand-made game drift apart: after a balance
  // change, see "Neighbourhoods from figures" in Engine Architecture.md.
  test('generated cities sell as many groceries as the hand-made ones', () {
    final byHand = _grocerySales(_scenario);
    final generated = _grocerySales(generateScenario(_scenario, rows, seed: 1));
    for (final MapEntry(:key, :value) in byHand.entries) {
      final gap = generated[key]! / value - 1;
      printOnFailure('$key: ${(gap * 100).toStringAsFixed(1)}%');
      expect(gap.abs(), lessThan(0.08), reason: key);
    }
  });

  group('what opens where', () {
    test('more households keep more grocers', () {
      int grocers(int households) => _formats(
        _world([_row('a', households: households)]),
        'a',
      ).where((format) => format == 'grocery').length;
      expect(grocers(100), 2);
      expect(grocers(1000), greaterThan(grocers(100)));
    });

    test('only a neighbourhood with the space starts with a supermarket', () {
      expect(
        _formats(_world([_row('a', households: 300)]), 'a'),
        isNot(contains('supermarket')),
      );
      expect(
        _formats(_world([_row('a', households: 300, largestArea: 220)]), 'a'),
        contains('supermarket'),
      );
    });

    test('a shop opens only where it pays', () {
      final poor = _formats(
        _world([_row('a', households: 60, income: '0.7')]),
        'a',
      );
      expect(poor, everyElement(anyOf('grocery', 'fastfood')));
      final rich = _formats(
        _world([_row('a', households: 800, income: '1.3')]),
        'a',
      );
      expect(rich, containsAll(['finedining', 'steakhouse', 'electronics']));
    });

    test('each neighbourhood keeps a few vacant sites', () {
      final world = _world(rows);
      final taken = {
        for (final store in world['stores'] as List) store['site'],
      };
      for (final row in rows) {
        final vacant = [
          for (final site in world['sites'] as List)
            if (site['market'] == row.key && !taken.contains(site['id'])) site,
        ];
        expect(vacant.length, greaterThanOrEqualTo(3), reason: row.key);
      }
    });
  });
}
