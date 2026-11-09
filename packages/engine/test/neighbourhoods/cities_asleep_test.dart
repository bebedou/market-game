@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _content = loadScenario(
  File('../../content/scenarios/prototype.json').readAsStringSync(),
);

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

int _row(Simulation game, String name) =>
    game.content.neighbourhoods.indexWhere((row) => row.name == name);

void main() {
  group('a game with the cities asleep', () {
    test('plays only the player\'s city in full', () {
      final game = Simulation.newGame(_content, seed: 1, citiesAsleep: true);
      expect(game.content.markets.single.name, 'Lyon, Croix-Rousse');
      final rows = game.content.neighbourhoods;
      expect(rows, hasLength(_content.neighbourhoods.length + 6));
      expect(game.world.sleepers, hasLength(rows.length));
      // The other cities' businesses and owners stay, their shops asleep.
      expect(game.world.companies, hasLength(_content.companies.length));
      expect(game.world.persons, hasLength(_content.persons.length));
      final paris = game.world.sleepers.firstWhere(
        (sleeper) => rows[sleeper.row].name == 'Paris, Batignolles',
      );
      final shops = {for (final shop in paris.shops) shop.name};
      expect(shops, containsAll(['Maison Lemercier', 'Steak & Co']));
      expect(paris.shops.every((shop) => shop.company != null), isTrue);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('trades the sleeping cities\' shops in their businesses\' books', () {
      final game = Simulation.newGame(_content, seed: 1, citiesAsleep: true);
      final lemercier = CompanyId(
        _content.companies.indexWhere((c) => c.key == 'lemercier'),
      );
      final cash =
          game.world.companies[lemercier.index].accounts[AccountKind.cash];
      _advance(game, 400);
      expect(
        game.world.companies[lemercier.index].accounts[AccountKind.cash] !=
            cash,
        isTrue,
      );
      final month = game
          .reports(lemercier, ReportPeriod.month)
          .lastWhere(
            (report) => report.flow(AccountKind.revenue) != Money.zero,
          );
      expect(month.flow(AccountKind.revenue) != Money.zero, isTrue);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('starts in another city, as well off as with every city in play', () {
      final site = _content.sites.firstWhere(
        (site) =>
            _content.markets[site.market.index].name ==
                'Montpellier, Boutonnet' &&
            startingSites(_content).contains(site.id),
      );
      final start = GameStart(
        site: site.id,
        format: const FormatId(0),
        name: 'Chez Moi',
      );
      final classic = Simulation.newGame(_content, seed: 1, start: start);
      final game = Simulation.newGame(
        _content,
        seed: 1,
        start: start,
        citiesAsleep: true,
      );
      expect(game.content.markets.single.name, 'Montpellier, Boutonnet');
      expect(
        game.content.neighbourhoods.any(
          (row) => row.name == 'Lyon, Croix-Rousse',
        ),
        isTrue,
      );
      final mine = game.world.stores.firstWhere(
        (store) =>
            game.world.companies[store.company.index].owner ==
            game.content.player,
      );
      expect(mine.name, 'Chez Moi');
      expect(game.content.sites[mine.site.index].key, site.key);
      final player = game.content.player;
      expect(
        game.world.persons[player.index].accounts[AccountKind.cash],
        classic.world.persons[player.index].accounts[AccountKind.cash],
      );
      expect(
        game.world.companies[mine.company.index].accounts[AccountKind.cash],
        classic.world.companies[mine.company.index].accounts[AccountKind.cash],
      );
    });

    test('wakes a city with its own businesses, under their names', () {
      final game = Simulation.newGame(_content, seed: 1, citiesAsleep: true);
      _advance(game, 60);
      final row = _row(game, 'Paris, Batignolles');
      final sleeper = game.world.sleepers.firstWhere((s) => s.row == row);
      final names = {for (final shop in sleeper.shops) shop.name};
      final companies = game.world.companies.length;
      game.submit(WakeNeighbourhood(game.content.player, row: row));
      final paris = game.content.markets.last;
      expect(paris.name, 'Paris, Batignolles');
      final stores = [
        for (final store in game.world.stores)
          if (store.market == paris.id) store,
      ];
      expect({for (final store in stores) store.name}, names);
      final lemercier = stores.firstWhere(
        (store) => store.name == 'Maison Lemercier',
      );
      expect(
        game.world.companies[lemercier.company.index].name,
        'Maison Lemercier',
      );
      // Its businesses were in the game already: none was made for it.
      expect(game.world.companies, hasLength(companies));
      _advance(game, 30);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('saves, loads and replays the same', () {
      final game = Simulation.newGame(_content, seed: 2, citiesAsleep: true);
      _advance(game, 70);
      game.submit(
        WakeNeighbourhood(game.content.player, row: _row(game, 'Nantes, Rezé')),
      );
      _advance(game, 20);
      final file = game.save();
      final loaded = Simulation.load(_content, file);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.content.markets, hasLength(game.content.markets.length));
      expect(loaded.save().bytes, file.bytes);
      expect(Simulation.replay(_content, file).stateHash(), game.stateHash());
      _advance(game, 30);
      _advance(loaded, 30);
      expect(loaded.stateHash(), game.stateHash());
    });
  });
}
