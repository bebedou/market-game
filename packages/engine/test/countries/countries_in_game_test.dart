@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/taxation.dart';
import 'package:test/test.dart';

final _table = loadCountryTable(
  File('../../content/countries/euro.json').readAsStringSync(),
  File('../../content/countries/calibration.json').readAsStringSync(),
);

final _content = loadScenario(
  File('../../content/scenarios/prototype.json').readAsStringSync(),
  national: _table,
);

CountryDef _country(String key) =>
    _content.countries.firstWhere((country) => country.key == key);

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

/// A new game with the player's first shop on [market]'s first free site.
Simulation _startIn(String market, {int seed = 1}) {
  final site = _content.sites.firstWhere(
    (site) =>
        _content.markets[site.market.index].key == market &&
        startingSites(_content).contains(site.id),
  );
  return Simulation.newGame(
    _content,
    seed: seed,
    start: GameStart(site: site.id, format: const FormatId(0), name: 'Mine'),
    citiesAsleep: true,
  );
}

void main() {
  group('the scenario', () {
    test('has France first, then Germany, Italy and Spain', () {
      expect(
        [for (final c in _content.countries) c.key],
        ['fr', 'de', 'it', 'es'],
      );
      for (final market in _content.markets.take(7)) {
        expect(market.country, _country('fr').id, reason: market.name);
      }
      final berlin = _content.markets.firstWhere((m) => m.key == 'berlin');
      expect(berlin.country, _country('de').id);
      final rows = [
        for (final row in _content.neighbourhoods)
          if (row.country != _country('fr').id) row,
      ];
      expect(rows, hasLength(12));
    });

    test("gives every country its own four suppliers, and pays a shop's "
        'margin at local wages', () {
      for (final country in _content.countries) {
        final own = _content.suppliers.where((s) => s.country == country.id);
        expect(own, hasLength(4), reason: country.key);
        // Goods cost the same across the euro area.
        expect(_content.costLevel(country.id), Fx.one, reason: country.key);
      }
      ProductDef product(String key) =>
          _content.products.firstWhere((p) => p.key == key);
      Money normal(String item, String country) =>
          _content.referenceIn(product(item), _country(country).id);
      // The poorer the country, the less a shop adds over its goods.
      for (final key in ['milk_budget', 'fastfood_budget']) {
        expect(normal(key, 'fr'), product(key).referencePrice);
        expect(normal(key, 'de') < normal(key, 'fr'), isTrue, reason: key);
        expect(normal(key, 'it') < normal(key, 'de'), isTrue, reason: key);
        expect(normal(key, 'es') < normal(key, 'it'), isTrue, reason: key);
      }
      // A meal is mostly work, so it is cheaper still than milk.
      double ratio(String key) =>
          normal(key, 'es').cents / normal(key, 'fr').cents;
      expect(ratio('fastfood_budget'), lessThan(ratio('milk_budget')));
      expect(ratio('fastfood_budget'), closeTo(0.74, 0.06));
    });

    test('names generated shops in each country\'s words', () {
      final names = _content.countries[_country('de').id.index].names!;
      expect(names.shopWords('grocery'), contains('{}-Markt'));
      expect(PlaceNames.fill('{}straße', 'Goethe'), 'Goethestraße');
      expect(PlaceNames.fill('Rue', 'Hugo'), 'Rue Hugo');
      final store = _content.stores.firstWhere(
        (store) =>
            _content.sites[store.site.index].market ==
            _content.markets.firstWhere((m) => m.key == 'madrid').id,
      );
      expect(
        [
          'Ultramarinos',
          'Colmado',
          'Mercado',
          'Despensa',
          'Súper',
        ].any(store.name.startsWith),
        isTrue,
        reason: store.name,
      );
    });
  });

  group('a game across countries', () {
    test('starts in each country, and plays a year', () {
      for (final market in ['berlin', 'milan', 'madrid']) {
        final game = _startIn(market);
        expect(game.content.markets.single.key, market);
        _advance(game, 370);
        expect(invariantViolations(game.world), isEmpty, reason: market);
        final mine = game.world.stores.firstWhere(
          (store) => store.company == game.world.companies.first.id,
          orElse: () => game.world.stores.first,
        );
        expect(mine.isTrading, isTrue, reason: market);
      }
    });

    test('lets a shop buy only from its own country\'s suppliers', () {
      final game = _startIn('madrid');
      final store = game.world.stores.firstWhere(
        (store) =>
            game.world.companies[store.company.index].owner ==
            game.world.player,
      );
      final product = ProductId(
        store.prices.indexWhere((price) => price != null),
      );
      SupplierDef supplier(String key) =>
          game.content.suppliers.firstWhere((s) => s.key == key);
      game.submit(
        PlaceOrder(
          game.world.player,
          store: store.id,
          supplier: supplier('bulkway').id,
          lines: [(product: product, quantity: 48)],
        ),
      );
      final refused = game.step().rejections;
      expect(refused.single.reason.key, 'supplierElsewhere');
      game.submit(
        PlaceOrder(
          game.world.player,
          store: store.id,
          supplier: supplier('es_bulk').id,
          lines: [(product: product, quantity: 48)],
        ),
      );
      expect(game.step().rejections, isEmpty);
      final order = game.world.orders.last;
      // At the Spanish wholesaler's own price, at Spain's prices.
      final spain = game.content.countryOf(store.market);
      expect(
        order.lines.single.unitPrice,
        supplier('es_bulk').unitPrice(
          game.content.products[product.index],
          48,
          game.world.macroOf(spain).priceIndex,
        ),
      );
    });

    test('runs each country\'s cycle, mostly in step, under one rate', () {
      final game = _startIn('berlin', seed: 3);
      final inStep = List.filled(game.content.countries.length, 0);
      var months = 0;
      var deeper = false;
      for (var day = 0; day < 365 * 20; day++) {
        game.step();
        if (!game.today.isFirstOfMonth) continue;
        months++;
        final shared = game.world.cycle!.regime;
        final rates = {
          for (final macro in game.world.economies) macro.policyRate,
        };
        expect(rates, hasLength(1));
        for (final country in game.content.countries) {
          if (game.world.macroOf(country.id).regime == shared) {
            inStep[country.id.index]++;
          }
        }
        final recession = game.content.macro.regimes.firstWhere(
          (r) => r.key == 'recession',
        );
        deeper =
            _country('es').demandIn(recession) <
            _country('fr').demandIn(recession);
      }
      expect(deeper, isTrue);
      // France and Spain follow the shared cycle far more than Germany.
      expect(
        inStep[_country('de').id.index] < inStep[_country('es').id.index],
        isTrue,
      );
      expect(inStep[_country('es').id.index] > months * 6 ~/ 10, isTrue);
      expect(game.world.regimeLog, hasLength(months));
      expect(invariantViolations(game.world), isEmpty);
    });

    test('taxes each country\'s part of a company\'s year at its own rate', () {
      final game = _startIn('madrid');
      _advance(game, 400);
      final company = game.world.companies.firstWhere(
        (company) => company.owner == game.world.player,
      );
      final year = game.today.date.year - 1;
      final dues = companyTaxes(game.world, game.content, company, year);
      expect(dues.map((due) => due.country), [_country('es').id]);
      final due = dues.single;
      final taxable = due.base - due.carried;
      expect(
        due.tax,
        taxable > Money.zero ? taxable.times(Fx.parse('0.25')) : Money.zero,
      );
    });

    test('takes dividend tax where the owner lives', () {
      final game = _startIn('berlin');
      expect(
        game.world.residence(game.content, game.world.player),
        _country('de').id,
      );
      _advance(game, 450);
      // Berlin's shopkeepers pay themselves out of their profits each month.
      final berlin = game.content.markets.single.id;
      final owners = {
        for (final store in game.world.stores)
          if (store.market == berlin &&
              game.world.companies[store.company.index].owner !=
                  game.world.player)
            game.world.companies[store.company.index].owner,
      };
      var checked = 0;
      for (final owner in owners) {
        // A chain from France that opened here pays France's rate.
        if (game.world.residence(game.content, owner) != _country('de').id) {
          continue;
        }
        final person = game.world.persons[owner.index];
        final paid = person.accounts[AccountKind.dividends];
        if (paid >= Money.zero) continue;
        final taxes = person.accounts[AccountKind.taxes];
        final expected = (-paid).times(Fx.parse('0.2638'));
        expect(
          (taxes - expected).cents.abs() <= 200,
          isTrue,
          reason: '${person.name}: $taxes against $expected',
        );
        checked++;
      }
      expect(checked, greaterThan(0));
    });

    test('shows each country by formula, from the game\'s start', () {
      final game = _startIn('milan');
      _advance(game, 400);
      final national = game.national!;
      expect(national.countries, hasLength(4));
      expect(
        national.today.number,
        greaterThan(game.content.startDay.number + 360),
      );
      final germany = national.countries.firstWhere((c) => c.def.key == 'de');
      final grocery = national.table.trades.indexWhere(
        (t) => t.key == 'grocery',
      );
      // About what German households spent on groceries in 2022, a month.
      final month = germany.tradeMonths[grocery].last.market.cents / 100;
      expect(month * 12, inInclusiveRange(240e9, 320e9));
      // The same again after a save.
      final loaded = Simulation.load(_content, game.save());
      expect(
        loaded.national!.countries.first.chains.first.cash,
        national.countries.first.chains.first.cash,
      );
    });

    test('saves, loads and replays the same', () {
      final game = _startIn('barcelona', seed: 2);
      _advance(game, 200);
      final file = game.save();
      final loaded = Simulation.load(_content, file);
      expect(loaded.stateHash(), game.stateHash());
      _advance(game, 60);
      _advance(loaded, 60);
      expect(loaded.stateHash(), game.stateHash());
      expect(loaded.save().bytes, game.save().bytes);
    });
  });
}
