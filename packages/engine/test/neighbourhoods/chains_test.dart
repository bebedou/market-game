@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/districts.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _scenario = File(
  '../../content/scenarios/prototype.json',
).readAsStringSync();

/// Today's game with a district run by formula beside it.
final ContentDb _content = () {
  final root = jsonDecode(_scenario) as Map<String, dynamic>;
  root['neighbourhoods'] = [
    {
      'id': 'partdieu',
      'name': 'Lyon, Part-Dieu',
      'households': {
        'families': 300,
        'professionals': 700,
        'students': 250,
        'retirees': 200,
        'singles': 900,
        'comfortable': 250,
      },
      'growth': {'professionals': '0.03', 'singles': '0.02'},
      'priceLevel': '1.02',
      'wageLevel': '1.02',
      'incomeLevel': '1.05',
      'rent': '8.00',
      'typicalArea': 125,
      'largestArea': 180,
      'room': 90,
    },
  ];
  return loadScenario(jsonEncode(root));
}();

PersonId _person(String key) =>
    PersonId(_content.persons.indexWhere((person) => person.key == key));

CompanyId _company(String key) =>
    CompanyId(_content.companies.indexWhere((company) => company.key == key));

FormatId _format(String key) =>
    _content.formats.firstWhere((format) => format.key == key).id;

final _chain = _person('owner_quickstop');
final _chainCompany = _company('quickstop');

List<String> _apply(Simulation game, Command command) {
  game.submit(command);
  return [for (final rejection in game.step().rejections) rejection.reason.key];
}

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

/// A free site of the district a convenience store fits on.
int _freeSite(Simulation game) {
  final sleeper = game.world.sleepers.single;
  final taken = {for (final shop in sleeper.shops) shop.site};
  return sitesOf(game.world, _content, sleeper)
      .firstWhere(
        (site) =>
            !taken.contains(site.number) &&
            site.area >= _content.formats[_format('grocery').index].minArea,
      )
      .number;
}

/// The game with QuickStop Market's shop opened in Part-Dieu.
Simulation _withChainShop() {
  final game = Simulation.newGame(_content, seed: 3);
  final refused = _apply(
    game,
    OpenInDistrict(
      _chain,
      row: 0,
      site: _freeSite(game),
      company: _chainCompany,
      format: _format('grocery'),
      capital: Money.parse('30000.00'),
    ),
  );
  expect(refused, isEmpty);
  return game;
}

void main() {
  group('a chain in a district run by formula', () {
    test('opens under its brand, paying from its company', () {
      final before = Simulation.newGame(_content, seed: 3);
      final cash = before
          .world
          .companies[_chainCompany.index]
          .accounts[AccountKind.cash];
      final game = _withChainShop();
      final shop = game.world.sleepers.single.shops.last;
      expect(shop.company, _chainCompany);
      expect(game.world.brands[shop.brand!.index].name, 'QuickStop Market');
      expect(shop.name, 'QuickStop Market Part-Dieu');
      // Its shop in the city joined the brand.
      expect(
        game.world.stores
            .firstWhere((store) => store.company == _chainCompany)
            .name,
        'QuickStop Market Croix-Rousse',
      );
      expect(
        game.world.companies[_chainCompany.index].accounts[AccountKind.cash] <
            cash + Money.parse('30000.00'),
        isTrue,
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('trades in its company\'s books, against everyone elsewhere', () {
      final game = _withChainShop();
      _advance(game, 40);
      final shop = game.world.sleepers.single.shops.last;
      expect(shop.sales, isNotEmpty);
      final month = game
          .reports(_chainCompany, ReportPeriod.month)
          .lastWhere(
            (report) => report.flow(AccountKind.revenue) != Money.zero,
          );
      // The month's revenue holds the district shop's sales.
      expect(
        month.flow(AccountKind.revenue).cents.abs() >= shop.sales.last.cents,
        isTrue,
      );
      expect(
        game.world.elsewhere.accounts[AccountKind.cash] != Money.zero,
        isTrue,
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('is for AI chains: the player\'s shop wakes the district', () {
      final game = Simulation.newGame(_content, seed: 3);
      expect(
        _apply(
          game,
          OpenInDistrict(
            _content.player,
            row: 0,
            site: _freeSite(game),
            company: const CompanyId(0),
            format: _format('grocery'),
          ),
        ),
        ['wakeToOpen'],
      );
    });

    test('buys a shopkeeper\'s shop there and puts it under its brand', () {
      final game = Simulation.newGame(_content, seed: 3);
      final sleeper = game.world.sleepers.single;
      final target = sleeper.shops.firstWhere(
        (shop) => shop.format == _format('grocery'),
      );
      final elsewhere = game.world.elsewhere.accounts[AccountKind.cash];
      expect(
        _apply(
          game,
          InjectCapital(
            _chain,
            company: _chainCompany,
            amount: Money.parse('50000.00'),
          ),
        ),
        isEmpty,
      );
      expect(
        _apply(
          game,
          BuyInDistrict(
            _chain,
            row: 0,
            site: target.site,
            company: _chainCompany,
          ),
        ),
        isEmpty,
      );
      expect(target.company, _chainCompany);
      expect(target.name, startsWith('QuickStop Market Part-Dieu'));
      expect(
        game.world.elsewhere.accounts[AccountKind.cash] > elsewhere,
        isTrue,
      );
      expect(
        _apply(
          game,
          BuyInDistrict(
            _chain,
            row: 0,
            site: target.site,
            company: _chainCompany,
          ),
        ),
        ['alreadyOwnStore'],
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('wakes as a store of its company, under its brand', () {
      final game = _withChainShop();
      _advance(game, 40);
      final shop = game.world.sleepers.single.shops.last;
      // A plan to look at shows it like any other shop.
      expect(game.plan!.stores.map((store) => store.name), contains(shop.name));
      final companies = game.world.companies.length;
      game.submit(WakeNeighbourhood(_content.player, row: 0));
      final store = game.world.stores.firstWhere(
        (store) => store.name == shop.name,
      );
      expect(store.company, _chainCompany);
      expect(store.brand, shop.brand);
      expect(store.area, shop.area);
      expect(game.content.markets[store.market.index].name, 'Lyon, Part-Dieu');
      // No business of its own was made for it.
      expect(game.world.companies.where((c) => c.name == shop.name), isEmpty);
      expect(game.world.companies.length, greaterThan(companies));
      expect(invariantViolations(game.world), isEmpty);
      _advance(game, 30);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('saves, loads and replays the same', () {
      final game = _withChainShop();
      _advance(game, 40);
      game.submit(WakeNeighbourhood(_content.player, row: 0));
      _advance(game, 10);
      final file = game.save();
      final loaded = Simulation.load(_content, file);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.save().bytes, file.bytes);
      expect(Simulation.replay(_content, file).stateHash(), game.stateHash());
      _advance(game, 20);
      _advance(loaded, 20);
      expect(loaded.stateHash(), game.stateHash());
    });
  });
}
