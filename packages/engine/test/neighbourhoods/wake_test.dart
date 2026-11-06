@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:test/test.dart';

final _scenario = File(
  '../../content/scenarios/prototype.json',
).readAsStringSync();

/// A row of figures for a neighbourhood called [key].
Map<String, Object?> _row(String key, {String price = '1.02'}) => {
  'id': key,
  'name': 'Lyon, $key',
  'households': {
    'families': 300,
    'professionals': 700,
    'students': 250,
    'retirees': 200,
    'singles': 900,
    'comfortable': 250,
  },
  'growth': {'families': '0.02', 'professionals': '0.03', 'singles': '0.02'},
  'priceLevel': price,
  'wageLevel': '1.02',
  'incomeLevel': '1.05',
  'rent': '8.00',
  'typicalArea': 125,
  'largestArea': 180,
  'room': 90,
};

/// Today's game with the [rows] asleep beside it.
ContentDb _content(List<Map<String, Object?>> rows) {
  final root = jsonDecode(_scenario) as Map<String, dynamic>;
  root['neighbourhoods'] = rows;
  return loadScenario(jsonEncode(root));
}

Simulation _game(ContentDb content, {int seed = 1}) =>
    Simulation.newGame(content, seed: seed);

void _advance(Simulation simulation, int days) {
  for (var i = 0; i < days; i++) {
    simulation.step();
  }
}

MarketDef _market(ContentDb content, String key) =>
    content.markets.firstWhere((market) => market.key == key);

/// The world's encoding, without the neighbourhoods run by formula beside it.
List<int> _worldBytes(Simulation simulation) {
  final writer = StateWriter();
  simulation.world.write(writer);
  return writer.toBytes();
}

void main() {
  group('a neighbourhood asleep', () {
    test('changes nothing in the game', () {
      final without = _game(loadScenario(_scenario));
      final beside = _game(_content([_row('partdieu'), _row('vaise')]));
      _advance(without, 90);
      _advance(beside, 90);
      expect(_worldBytes(beside), _worldBytes(without));
      expect(beside.content.markets, hasLength(without.content.markets.length));
      expect(beside.content.sites, hasLength(without.content.sites.length));
    });

    test('is planned without being woken, which changes nothing either', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 5);
      final hash = game.stateHash();
      final plan = game.plan!;
      expect(game.stateHash(), hash);
      expect(game.woken, isEmpty);
      expect(_market(plan, 'partdieu').name, 'Lyon, partdieu');
      expect(
        game.content.markets.any((market) => market.key == 'partdieu'),
        isFalse,
      );
    });

    test('has an outlook, against only the rivals of each trade', () {
      final game = _game(_content([_row('partdieu')]));
      final plan = game.plan!;
      final market = _market(plan, 'partdieu');
      final view = game.observe(plan.player);
      final taken = {for (final store in plan.stores) store.site.index};
      final site = plan.sites.firstWhere(
        (site) => site.market == market.id && !taken.contains(site.id.index),
      );
      for (final format in plan.formats) {
        final planned = plan.stores.where(
          (store) =>
              plan.sites[store.site.index].market == market.id &&
              plan.formatChannels[store.format.index] ==
                  plan.formatChannels[format.id.index],
        );
        final outlook = shopOutlook(view, plan, site, format);
        expect(outlook.rivals, planned.length, reason: format.key);
        expect(outlook.spending > Money.zero, isTrue, reason: format.key);
      }
    });

    test('a scenario can\'t call one what it calls a market', () {
      expect(
        () => _content([_row('neighborhood')]),
        throwsA(isA<ContentException>()),
      );
      expect(
        () => _content([_row('a'), _row('a')]),
        throwsA(isA<ContentException>()),
      );
    });
  });

  group('a neighbourhood run by formula', () {
    SleepingNeighbourhood sleeper(Simulation game) =>
        game.world.sleepers.single;

    test('does nothing before its first month is out', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 1);
      for (final shop in sleeper(game).shops) {
        expect(shop.sales, isEmpty);
      }
    });

    test('books sales and profit for each shop, every month', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 400);
      final shops = sleeper(game).shops;
      expect(shops, isNotEmpty);
      for (final shop in shops) {
        expect(shop.sales, hasLength(12));
        expect(shop.yearSales > Money.zero, isTrue, reason: shop.name);
      }
      expect(shops.any((shop) => shop.yearProfit > Money.zero), isTrue);
    });

    test('grows its households', () {
      final content = _content([_row('partdieu')]);
      final game = _game(content);
      _advance(game, 800);
      final total = sleeper(game).households.fold(0, (sum, n) => sum + n);
      expect(total, greaterThan(content.neighbourhoods.single.totalHouseholds));
    });

    test('sells more where there are more households', () {
      Money sales(int households) {
        final row = _row('partdieu');
        row['households'] = {
          'professionals': households,
          'singles': households,
        };
        final game = _game(_content([row]));
        _advance(game, 400);
        return sleeper(game).shops
            .where((shop) => shop.openedMonth < 0)
            .fold(Money.zero, (sum, shop) => sum + shop.yearSales);
      }

      expect(sales(2400) > sales(1200), isTrue);
    });

    test('shares each trade only among its own shops', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 400);
      final content = game.content;
      final shops = sleeper(game).shops;
      final byChannel = <int, Money>{};
      for (final shop in shops) {
        final channel = content.formatChannels[shop.format.index];
        byChannel[channel] =
            (byChannel[channel] ?? Money.zero) + shop.yearSales;
      }
      // A restaurant's trade and a grocer's are of different sizes: neither
      // is what's left of the other's.
      expect(byChannel.length, greaterThan(1));
    });

    test('closes a shop that keeps losing money', () {
      final row = _row('partdieu');
      // Nobody lives here any more.
      row['households'] = {'singles': 20};
      final game = _game(_content([row]));
      final start = sleeper(game).shops.length;
      expect(start, greaterThan(0));
      _advance(game, 365 * 4);
      expect(sleeper(game).closed, greaterThan(0));
      expect(sleeper(game).shops.length, lessThan(start));
    });

    test(
      'pays for a round of works from the shop first, not only its owner',
      () {
        final content = _content([_row('partdieu')]);
        final game = _game(content);
        _advance(game, 400);
        // Nothing put by: all a shop has from now on is what it makes.
        final shops = sleeper(game).shops;
        final areas = [for (final shop in shops) shop.area];
        for (final shop in shops) {
          shop
            ..cash = Money.zero
            ..ownerCash = Money.zero;
        }
        _advance(game, 500);
        expect(sleeper(game).closed, 0);
        expect(
          [for (final shop in shops) shop.area],
          isNot(areas),
          reason: 'a grocer should have enlarged by now',
        );
        for (final shop in sleeper(game).shops) {
          expect(shop.ownerCash.isNegative, isFalse, reason: shop.name);
        }
      },
    );

    test('is the same from the same seed, and saves and replays so', () {
      final content = _content([_row('partdieu'), _row('vaise')]);
      final game = _game(content);
      _advance(game, 500);
      final twin = _game(content);
      _advance(twin, 500);
      expect(twin.stateHash(), game.stateHash());
      final file = game.save();
      final loaded = Simulation.load(content, file);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.save().bytes, file.bytes);
      expect(
        loaded.world.sleepers.first.shops.first.yearSales,
        game.world.sleepers.first.shops.first.yearSales,
      );
      expect(Simulation.replay(content, file).stateHash(), game.stateHash());
      _advance(game, 100);
      _advance(loaded, 100);
      expect(loaded.stateHash(), game.stateHash());
    });
  });

  group('waking a neighbourhood', () {
    test('finds the shops its history left, as big as they became', () {
      final content = _content([_row('partdieu')]);
      final game = _game(content);
      _advance(game, 365 * 5);
      final left = game.world.sleepers.single.shops.toList();
      expect(left, isNotEmpty);
      // One has been through two more rounds of works.
      final enlarged = left.first;
      enlarged.area += 2 * content.expansion.stepArea;
      final first = game.world.stores.length;
      final cash = enlarged.cash;
      game.submit(WakeNeighbourhood(content.player, row: 0));
      final stores = game.world.stores.skip(first).toList();
      expect(stores.map((store) => store.name), left.map((shop) => shop.name));
      expect(stores.first.area, enlarged.area);
      final site = game.content.sites[stores.first.site.index];
      final steps = (enlarged.area - site.area) ~/ content.expansion.stepArea;
      expect(steps, greaterThanOrEqualTo(2));
      expect(
        stores.first.shelfSlots,
        site.shelfSlots +
            content.formats[stores.first.format.index].slotBonus +
            steps * content.expansion.shelfSlots,
      );
      expect(
        game.world.companies[stores.first.company.index].accounts[AccountKind
            .cash],
        cash,
      );
    });

    test('takes up where the formula left off, in shops and households', () {
      final content = _content([_row('partdieu')]);
      final game = _game(content);
      _advance(game, 365 * 3);
      final households = game.world.sleepers.single.households.fold(
        0,
        (sum, count) => sum + count,
      );
      game.submit(WakeNeighbourhood(content.player, row: 0));
      final market = _market(game.content, 'partdieu');
      expect(
        market.households.fold(0, (sum, count) => sum + count),
        households,
      );
      expect(game.world.sleepers, isEmpty);
    });

    test('adds its sites, households, shops and owners', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 10);
      final people = game.world.persons.length;
      final stores = game.world.stores.length;
      final cohorts = game.world.cohorts.length;
      final money = game.world.moneySupply;
      game.submit(WakeNeighbourhood(game.content.player, row: 0));
      final market = _market(game.content, 'partdieu');
      expect(game.world.persons.length, greaterThan(people));
      expect(game.world.stores.length, greaterThan(stores));
      expect(game.world.cohorts.length, greaterThan(cohorts));
      expect(game.world.moneySupply > money, isTrue);
      expect(game.world.markets, hasLength(game.content.markets.length));
      expect(game.woken.single.row, 0);
      expect(game.sleeping, isEmpty);
      expect(game.plan, isNull);
      final there = game.world.cohorts.where((c) => c.market == market.id);
      expect(
        there.fold(0, (sum, cohort) => sum + cohort.weight),
        market.households.fold(0, (sum, count) => sum + count),
      );
    });

    test('brings shops that have traded for years, and now trade here', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 10);
      final first = game.world.stores.length;
      game.submit(WakeNeighbourhood(game.content.player, row: 0));
      final rivals = game.world.stores.skip(first).toList();
      for (final store in rivals) {
        expect(store.reputation, game.content.demand.establishedReputation);
      }
      final visits = List.filled(game.world.stores.length, 0);
      for (var day = 0; day < 60; day++) {
        final result = game.step();
        for (var i = 0; i < visits.length; i++) {
          visits[i] += result.attribution.visits[i];
        }
      }
      for (final store in rivals) {
        expect(visits[store.id.index], greaterThan(0), reason: store.name);
      }
    });

    test('lets the player open there the same day', () {
      final game = _game(_content([_row('partdieu')]));
      _advance(game, 10);
      final player = game.content.player;
      game.submit(WakeNeighbourhood(player, row: 0));
      final market = _market(game.content, 'partdieu');
      final view = game.observe(player);
      final site = view.vacantSites
          .map((id) => game.content.sites[id.index])
          .firstWhere((site) => site.market == market.id);
      game.submit(
        OpenStore(
          player,
          site: site.id,
          name: 'New Shop',
          company: const CompanyId(0),
          capital: Money.parse('20000.00'),
        ),
      );
      final result = game.step();
      expect(
        result.rejections,
        isEmpty,
        reason: result.rejections.map((r) => r.reason.key).join(),
      );
      expect(game.world.stores.last.name, 'New Shop');
      expect(game.world.stores.last.market, market.id);
    });

    test('saves, loads and replays the same', () {
      final content = _content([_row('partdieu'), _row('vaise')]);
      final game = _game(content);
      _advance(game, 20);
      game.submit(WakeNeighbourhood(content.player, row: 1));
      _advance(game, 20);
      game.submit(WakeNeighbourhood(content.player, row: 0));
      _advance(game, 20);
      final file = game.save();
      final loaded = Simulation.load(content, file);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.content.markets, hasLength(game.content.markets.length));
      expect(loaded.woken.map((wake) => wake.row), [1, 0]);
      expect(loaded.save().bytes, file.bytes);
      final replayed = Simulation.replay(content, file);
      expect(replayed.stateHash(), game.stateHash());
      _advance(game, 30);
      _advance(loaded, 30);
      _advance(replayed, 30);
      expect(loaded.stateHash(), game.stateHash());
      expect(replayed.stateHash(), game.stateHash());
    });

    test('is the same neighbourhood from the same seed, not from another', () {
      List<int> rents(Simulation game) {
        final market = _market(game.plan!, 'partdieu');
        return [
          for (final site in game.plan!.sites)
            if (site.market == market.id) site.rent.cents,
        ];
      }

      final content = _content([_row('partdieu')]);
      expect(rents(_game(content)), rents(_game(content)));
      expect(rents(_game(content)), isNot(rents(_game(content, seed: 2))));
      // What the plan shows is what wakes.
      final game = _game(content);
      final planned = rents(game);
      game.submit(WakeNeighbourhood(content.player, row: 0));
      final market = _market(game.content, 'partdieu');
      expect([
        for (final site in game.content.sites)
          if (site.market == market.id) site.rent.cents,
      ], planned);
    });

    test('does nothing twice, or for a row that isn\'t there', () {
      final game = _game(_content([_row('partdieu')]));
      game.submit(WakeNeighbourhood(game.content.player, row: 0));
      final markets = game.content.markets.length;
      game
        ..submit(WakeNeighbourhood(game.content.player, row: 0))
        ..submit(WakeNeighbourhood(game.content.player, row: 5));
      expect(game.content.markets, hasLength(markets));
      expect(game.woken, hasLength(1));
    });

    test('finds it grown, and at today\'s prices', () {
      final content = _content([_row('partdieu')]);
      final game = _game(content);
      final row = content.neighbourhoods.single;
      _advance(game, 800);
      final index = game.world.macro.priceIndex;
      expect(index > Fx.one, isTrue);
      final first = game.world.stores.length;
      game.submit(WakeNeighbourhood(content.player, row: 0));
      final market = _market(game.content, 'partdieu');
      expect(
        market.households.fold(0, (sum, count) => sum + count),
        greaterThan(row.totalHouseholds),
      );
      final store = game.world.stores[first];
      final (p, price) = store.prices.indexed.firstWhere((e) => e.$2 != null);
      final normal = game.content.products[p].referencePrice
          .times(market.priceLevel)
          .times(index);
      // Within what any strategy's position moves it.
      expect(price!.cents / normal.cents, closeTo(1, 0.1));
    });
  });
}
