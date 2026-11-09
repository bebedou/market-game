@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/brands.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _content = loadScenario(
  File('../../content/scenarios/prototype.json').readAsStringSync(),
);

Simulation _game() => Simulation.newGame(_content, seed: 7);

FormatId _format(String key) =>
    _content.formats.firstWhere((format) => format.key == key).id;

SiteId _site(String key) =>
    _content.sites.firstWhere((site) => site.key == key).id;

PersonId _person(String key) =>
    PersonId(_content.persons.indexWhere((person) => person.key == key));

CompanyId _company(String key) =>
    CompanyId(_content.companies.indexWhere((company) => company.key == key));

/// Submits [command] and steps: what was refused, by its key.
List<String> _apply(Simulation game, Command command) {
  game.submit(command);
  return [for (final rejection in game.step().rejections) rejection.reason.key];
}

void main() {
  final player = _content.player;
  const playerCompany = CompanyId(0);

  group('a brand', () {
    test('is for one type of business, under a name nobody else has', () {
      final game = _game();
      // It's there at once, without waiting for the day.
      game.submit(
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      final brand = game.observe(player).brands.single;
      expect(brand.name, 'Coin Malin');
      expect(brand.format, _format('grocery'));
      expect(brand.owner, player);
      expect(brand.shops, 0);
      game
        ..submit(
          CreateBrand(player, name: 'coin malin', format: _format('fastfood')),
        )
        ..submit(CreateBrand(player, name: ' ', format: _format('grocery')));
      expect(game.world.brands, hasLength(1));
      // Only what was made is in the log, for a replay to make again.
      expect(game.commandLog, hasLength(1));
    });

    test('names a shop opened under it after itself and its district', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      final brand = game.observe(player).brands.single.id;
      expect(
        _apply(
          game,
          OpenStore(
            player,
            site: _site('backstreet'),
            name: '',
            company: playerCompany,
            capital: Money.parse('10000.00'),
            brand: brand,
          ),
        ),
        isEmpty,
      );
      final store = game.world.stores.last;
      expect(store.name, 'Coin Malin Croix-Rousse');
      expect(store.brand, brand);
      expect(game.observe(player).brands.single.shops, 1);
      // A second in the same district has its street too.
      expect(
        brandedName(
          game.world,
          _content,
          game.world.brands.single,
          _content.sites[_site('station').index],
        ),
        'Coin Malin Croix-Rousse, Hénon metro',
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('opens a new shop as well known as its shops nearby', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      final brand = game.world.brands.single;
      final corner = game.world.stores.first;
      brandStore(game.world, _content, corner, brand);
      corner.reputation = Fx.parse('0.9');
      expect(corner.name, 'Coin Malin Croix-Rousse');
      _apply(
        game,
        OpenStore(
          player,
          site: _site('backstreet'),
          name: '',
          company: playerCompany,
          capital: Money.parse('10000.00'),
          brand: brand.id,
        ),
      );
      final opened = game.world.stores.last;
      expect(opened.name, 'Coin Malin Croix-Rousse, Rue du Mail');
      // As known as the brand was on the day it opened.
      expect(opened.reputation, Fx.parse('0.9'));
    });

    test('is refused for another type of business, or to anyone else', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Frites et Cie', format: _format('fastfood')),
      );
      final fastFood = game.world.brands.single.id;
      expect(
        _apply(
          game,
          OpenStore(
            player,
            site: _site('backstreet'),
            name: '',
            company: playerCompany,
            capital: Money.parse('10000.00'),
            brand: fastFood,
          ),
        ),
        ['brandWrongFormat'],
      );
      final rival = _person('owner_quickstop');
      expect(
        _apply(
          game,
          OpenStore(
            rival,
            site: _site('backstreet'),
            name: 'Theirs',
            company: _company('quickstop'),
            format: _format('fastfood'),
            brand: fastFood,
          ),
        ),
        ['brandNotYours'],
      );
      expect(
        _apply(
          game,
          OpenStore(
            player,
            site: _site('backstreet'),
            name: '',
            company: playerCompany,
            capital: Money.parse('10000.00'),
          ),
        ),
        ['storeNeedsName'],
      );
    });

    test('names its shops: they can\'t be renamed one by one', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      brandStore(
        game.world,
        _content,
        game.world.stores.first,
        game.world.brands.single,
      );
      expect(
        _apply(
          game,
          RenameStore(player, store: const StoreId(0), name: 'Chez Moi'),
        ),
        ['brandedStoreName'],
      );
    });

    test('leaves a shop that becomes another type of business', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      final corner = game.world.stores.first;
      brandStore(game.world, _content, corner, game.world.brands.single);
      corner.works = (
        area: corner.area,
        done: game.today,
        format: _format('supermarket'),
      );
      game.step();
      expect(corner.format, _format('supermarket'));
      expect(corner.brand, isNull);
      expect(corner.name, 'Coin Malin Croix-Rousse');
    });

    test('is saved, loaded and replayed with the game', () {
      final game = _game();
      _apply(
        game,
        CreateBrand(player, name: 'Coin Malin', format: _format('grocery')),
      );
      _apply(
        game,
        OpenStore(
          player,
          site: _site('backstreet'),
          name: '',
          company: playerCompany,
          capital: Money.parse('10000.00'),
          brand: game.world.brands.single.id,
        ),
      );
      final file = game.save();
      final loaded = Simulation.load(_content, file);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.world.brands.single.name, 'Coin Malin');
      expect(loaded.world.stores.last.brand, game.world.stores.last.brand);
      expect(loaded.save().bytes, file.bytes);
      expect(Simulation.replay(_content, file).stateHash(), game.stateHash());
    });
  });

  group('an AI chain', () {
    test('opens under its brand, named after it, and its shops join it', () {
      final game = _game();
      final owner = _person('owner_quickstop');
      final first = game.world.stores.firstWhere(
        (store) => store.company == _company('quickstop'),
      );
      final known = first.reputation;
      expect(
        _apply(
          game,
          OpenStore(
            owner,
            site: _site('backstreet'),
            name: 'Anything',
            company: _company('quickstop'),
          ),
        ),
        isEmpty,
      );
      final brand = game.world.brands.single;
      expect(brand.name, 'QuickStop Market');
      expect(brand.owner, owner);
      expect(first.name, 'QuickStop Market Croix-Rousse');
      expect(first.brand, brand.id);
      final opened = game.world.stores.last;
      expect(opened.name, 'QuickStop Market Croix-Rousse, Rue du Mail');
      expect(opened.reputation, known);
    });

    test('puts a shop it buys under its brand', () {
      final game = _game();
      final store = game.world.stores.first;
      expect(_apply(game, SellStore(player, store: store.id)), isEmpty);
      final buyer = game.world.companies[store.company.index];
      expect(buyer.owner, isNot(player));
      final brand = game.world.brands[store.brand!.index];
      expect(brand.owner, buyer.owner);
      expect(store.name, startsWith(brand.name));
      expect(store.name, contains('Croix-Rousse'));
    });
  });
}
