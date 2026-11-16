@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/stocks.dart';
import 'package:test/test.dart';

final _scenario = File(
  '../../content/scenarios/prototype.json',
).readAsStringSync();
final _national = loadCountryTable(
  File('../../content/countries/euro.json').readAsStringSync(),
  File('../../content/countries/calibration.json').readAsStringSync(),
);
final _table = File('../../content/stocks/companies.json').readAsStringSync();

/// The prototype with the countries' national figures and the stock market,
/// its player rich enough to buy a good stake.
final _content = loadScenario(
  _scenario.replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "5000000.00"',
  ),
  national: _national,
  stocks: _table,
);

Simulation _game({int seed = 1}) => Simulation.newGame(
  _content,
  seed: seed,
  start: const GameStart.holding('Holding'),
  citiesAsleep: true,
);

/// [table] changed by [change], loaded beside the prototype.
ContentDb _with(void Function(Map<String, Object?> table) change) {
  final table = jsonDecode(_table) as Map<String, Object?>;
  change(table);
  return loadScenario(
    _scenario,
    national: _national,
    stocks: jsonEncode(table),
  );
}

List<Map<String, Object?>> _companies(Map<String, Object?> table) =>
    (table['companies']! as List).cast<Map<String, Object?>>();

Money _cash(Simulation game) =>
    game.world.persons[game.world.player.index].accounts[AccountKind.cash];

/// The first listed company by formula on the Paris exchange.
int _parisFormula(ContentDb content) {
  final def = content.stocks!;
  final paris = content.countries.firstWhere((c) => c.key == 'fr').id;
  return def.listings.indexWhere(
    (l) => l.kind == ListingKind.formula && l.country == paris,
  );
}

void _stepTo(Simulation game, int month, int day) {
  while (game.today.date.month != month || game.today.date.day != day) {
    game.step();
  }
}

void main() {
  group('the table', () {
    test('lists the game\'s own companies and every sector\'s ten', () {
      final def = _content.stocks!;
      expect(def.sectors, hasLength(23));
      expect(def.exchanges, hasLength(4));
      final kinds = {for (final kind in ListingKind.values) kind: 0};
      for (final listing in def.listings) {
        kinds[listing.kind] = kinds[listing.kind]! + 1;
      }
      expect(kinds[ListingKind.chain], 48);
      expect(kinds[ListingKind.software], 6);
      expect(kinds[ListingKind.producer], 48);
      expect(kinds[ListingKind.formula], 18 * 4 * 10);
    });

    test('names its problems', () {
      expect(
        () => _with(
          (t) => _companies(t)[1]['ticker'] = _companies(t)[0]['ticker'],
        ),
        throwsA(isA<ContentException>()),
      );
      expect(
        () => _with((t) {
          final chain = _companies(t).firstWhere((c) => c['chain'] != null);
          chain['chain'] = 'No Such Chain';
        }),
        throwsA(isA<ContentException>()),
      );
      expect(
        () => _with((t) => _companies(t)[0]['management'] = 'superb'),
        throwsA(isA<ContentException>()),
      );
      expect(
        () => _with((t) => _companies(t)[0]['unknown'] = 1),
        throwsA(isA<ContentException>()),
      );
    });

    test('a company added to the table is listed in a saved game', () {
      final game = _game();
      for (var d = 0; d < 40; d++) {
        game.step();
      }
      final grown = _with((t) {
        final copy = Map<String, Object?>.of(_companies(t)[0])
          ..['ticker'] = 'ZZZZ'
          ..['name'] = 'Added Later';
        _companies(t).add(copy);
      });
      final loaded = Simulation.load(grown, game.save());
      loaded.step();
      final market = loaded.world.stocks!;
      expect(market.stocks, hasLength(grown.stocks!.listings.length));
      expect(market.stocks.last.listed, isTrue);
      expect(market.stocks.last.price > Money.zero, isTrue);
    });
  });

  group('opening', () {
    test(
      'a new game opens every exchange at its base, near the table\'s caps',
      () {
        final game = _game();
        final market = game.world.stocks!;
        final def = _content.stocks!;
        expect(market.stocks, hasLength(def.listings.length));
        for (final exchange in market.exchanges) {
          expect(exchange.level, const Money(100000));
        }
        final i = _parisFormula(_content);
        final cap = market.stocks[i].cap.cents;
        final table = def.listings[i].cap!.cents;
        expect((cap - table).abs() * 100, lessThan(table));
        expect(market.stocks.every((s) => s.listed), isTrue);
        expect(market.stocks.every((s) => s.price > Money.zero), isTrue);
        expect(
          game.observe(game.world.player).stocks!.stocks,
          hasLength(def.listings.length),
        );
      },
    );
  });

  group('trading', () {
    test('buying pays the price, a fee, and moves a big order\'s price', () {
      final game = _game();
      final i = _parisFormula(_content);
      final stock = game.world.stocks!.stocks[i];
      final before = _cash(game);
      final price = stock.price;
      final units = 1000;
      final rules = _content.stocks!.rules;
      final value = orderValue(rules, price, stock.shares, units, buy: true);
      final fee = orderFee(rules, value, index: false);
      game.submit(BuyShares(game.world.player, of: i, units: units));
      final result = game.step();
      expect(result.rejections, isEmpty);
      expect(_cash(game), before - value - fee);
      final holding = game.world.stocks!.holding(i)!;
      expect(holding.units, units);
      expect(holding.cost, value + fee);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('refuses what the player can\'t do', () {
      final game = _game();
      final i = _parisFormula(_content);
      final player = game.world.player;
      Refusal? refusal(Command command) {
        game.submit(command);
        final result = game.step();
        return result.rejections.isEmpty
            ? null
            : result.rejections.single.reason;
      }

      expect(
        refusal(BuyShares(player, of: i, units: 0))?.key,
        'unitsNotPositive',
      );
      expect(
        refusal(BuyShares(player, of: 99999, units: 1))?.key,
        'unknownStock',
      );
      final shares = game.world.stocks!.stocks[i].shares;
      expect(
        refusal(BuyShares(player, of: i, units: shares - 1))?.key,
        'notEnoughHoldingCash',
      );
      expect(
        refusal(BuyShares(player, of: i, units: shares + 1))?.key,
        'moreThanItsShares',
      );
      expect(
        refusal(SellShares(player, of: i, units: 1))?.key,
        'notEnoughShares',
      );
      final rival = PersonId((player.index + 1) % game.world.persons.length);
      expect(
        refusal(BuyShares(rival, of: i, units: 1))?.key,
        'onlyThePlayerTrades',
      );
    });

    test('a gain is taxed on selling, once a loss is set against it', () {
      final game = _game();
      final i = _parisFormula(_content);
      final player = game.world.player;
      game.submit(BuyShares(player, of: i, units: 2000));
      game.step();
      final market = game.world.stocks!;
      final holding = market.holding(i)!;
      // A loss of 1,000 carried, then a sale well above cost.
      market.gainsLoss = const Money(100000);
      market.stocks[i].price = market.stocks[i].price.timesInt(2);
      final taxesBefore =
          game.world.persons[player.index].accounts[AccountKind.taxes];
      final cost = holding.cost;
      game.submit(SellShares(player, of: i, units: 2000));
      game.step();
      expect(market.holding(i), isNull);
      expect(market.gainsLoss, Money.zero);
      final taxes =
          game.world.persons[player.index].accounts[AccountKind.taxes] -
          taxesBefore;
      expect(taxes > Money.zero, isTrue);
      // Taxed on less than the whole gain over cost.
      final proceeds = market.stocks[i].previous.timesInt(2000);
      final rate = _content
          .taxesOf(game.world.residence(_content, player))!
          .dividendRate;
      expect(taxes < (proceeds - cost).times(rate), isTrue);
      expect(invariantViolations(game.world), isEmpty);
    });

    test('a stake is made public at each 5%, either way', () {
      final game = _game();
      final def = _content.stocks!;
      final player = game.world.player;
      // A small company, so a stake is within the player's means.
      var i = 0;
      for (final (n, listing) in def.listings.indexed) {
        if (listing.cap! < def.listings[i].cap!) i = n;
      }
      final shares = game.world.stocks!.stocks[i].shares;
      List<StakeCrossed> trade(Command command) {
        game.submit(command);
        final result = game.step();
        expect(
          [for (final r in result.rejections) r.reason.key],
          isEmpty,
          reason: '$command',
        );
        return result.events.whereType<StakeCrossed>().toList();
      }

      final six = shares * 6 ~/ 100;
      final first = trade(BuyShares(player, of: i, units: six));
      expect([for (final e in first) (e.percent, e.up)], [(5, true)]);
      final second = trade(SellShares(player, of: i, units: shares * 2 ~/ 100));
      expect([for (final e in second) (e.percent, e.up)], [(5, false)]);
      final third = trade(BuyShares(player, of: i, units: shares * 8 ~/ 100));
      expect([for (final e in third) (e.percent, e.up)], [(10, true)]);
      expect(trade(BuyShares(player, of: i, units: 1)), isEmpty);
      final held = game.world.stocks!.holding(i)!.units;
      final last = trade(SellShares(player, of: i, units: held));
      expect([for (final e in last) (e.percent, e.up)], [(5, false)]);
    });

    test('an index can be bought as a whole', () {
      final game = _game();
      final before = _cash(game);
      game.submit(BuyShares(game.world.player, of: 0, units: 10, index: true));
      game.step();
      final holding = game.world.stocks!.holding(0, index: true)!;
      expect(holding.units, 10);
      expect(_cash(game) < before - const Money(900000), isTrue);
      final view = game.observe(game.world.player).stocks!;
      expect(view.holdings.single.index, isTrue);
      expect(view.worth > Money.zero, isTrue);
    });
  });

  group('the quarter', () {
    test('holders get dividends, taxed, when results come out', () {
      final game = _game();
      final def = _content.stocks!;
      // A company that pays out well.
      final i = def.listings.indexWhere(
        (l) => l.kind == ListingKind.formula && l.payout > const Fx.raw(5000),
      );
      final price = game.world.stocks!.stocks[i].price;
      final units = const Money(200000000).cents ~/ price.cents;
      game.submit(BuyShares(game.world.player, of: i, units: units));
      expect(game.step().rejections, isEmpty);
      _stepTo(game, 4, 1);
      final before = _cash(game);
      final dividends = game
          .world
          .persons[game.world.player.index]
          .accounts[AccountKind.dividends];
      game.step();
      final received =
          game.world.persons[game.world.player.index].accounts[AccountKind
              .dividends] -
          dividends;
      expect(received < Money.zero, isTrue, reason: 'credited as income');
      expect(_cash(game) > before, isTrue);
      expect(game.world.stocks!.stocks[i].results.last.day, game.today + -1);
      expect(
        game.world.stocks!.stocks[i].results.last.dividends > Money.zero,
        isTrue,
      );
      expect(
        game.observe(game.world.player).stocks!.dividends > Money.zero,
        isTrue,
      );
    });

    test(
      'a chain that is bought whole leaves its exchange, its holders paid',
      () {
        final game = _game();
        final def = _content.stocks!;
        final i = def.listings.indexWhere((l) => l.kind == ListingKind.chain);
        game.submit(BuyShares(game.world.player, of: i, units: 1000));
        game.step();
        final national = game.world.national!;
        final listing = def.listings[i];
        final country = national.countries.firstWhere(
          (c) =>
              c.def.key == _content.countries[listing.country.index].national,
        );
        country.chains[listing.link].boughtBy = 0;
        final before = _cash(game);
        _stepTo(game, 2, 2);
        final stock = game.world.stocks!.stocks[i];
        expect(stock.listed, isFalse);
        expect(game.world.stocks!.holding(i), isNull);
        expect(_cash(game) > before, isTrue);
      },
    );
  });

  group('moods', () {
    test('a recession turns the market gloomy', () {
      final game = _game();
      final recession = _content.macro.regimes.firstWhere(
        (r) => r.key == 'recession',
      );
      final cycle = game.world.cycle!;
      for (var d = 0; d < 200; d++) {
        cycle.regime = recession.id;
        game.world.macro.regime = recession.id;
        game.step();
      }
      expect(game.world.stocks!.mood, lessThan(-100000));
    });

    test('analysts rate and managements show', () {
      final game = _game();
      for (var d = 0; d < 100; d++) {
        game.step();
      }
      final view = game.observe(game.world.player).stocks!;
      final ratings = {for (final s in view.stocks) s.rating};
      expect(ratings.length, greaterThan(2));
      final formula = view.stocks.where((s) => s.kind == ListingKind.formula);
      final proven = formula.where((s) => s.management != null).length;
      expect(proven, greaterThan(formula.length * 9 ~/ 10));
      expect(proven, lessThan(formula.length), reason: 'some changed hands');
      expect(
        view.stocks
            .where((s) => s.kind == ListingKind.chain)
            .any((s) => s.management != null),
        isTrue,
      );
    });
  });

  group('saves', () {
    test('a game with a market saves, loads and replays to the same state', () {
      final game = _game(seed: 7);
      final player = game.world.player;
      final i = _parisFormula(_content);
      game.submit(BuyShares(player, of: i, units: 500));
      for (var d = 0; d < 120; d++) {
        game.step();
      }
      game.submit(SellShares(player, of: i, units: 200));
      for (var d = 0; d < 60; d++) {
        game.step();
      }
      final loaded = Simulation.load(_content, game.save());
      expect(loaded.stateHash(), game.stateHash());
      for (var d = 0; d < 40; d++) {
        game.step();
        loaded.step();
      }
      expect(loaded.stateHash(), game.stateHash());
      final replayed = Simulation.replay(_content, game.save());
      expect(replayed.stateHash(), game.stateHash());
    });

    test('a game saved without a market gains one when loaded with one', () {
      final plain = loadScenario(_scenario, national: _national);
      final game = Simulation.newGame(
        plain,
        seed: 2,
        start: const GameStart.holding('Holding'),
        citiesAsleep: true,
      );
      for (var d = 0; d < 20; d++) {
        game.step();
      }
      expect(game.world.stocks, isNull);
      final loaded = Simulation.load(_with((_) {}), game.save());
      loaded.step();
      expect(loaded.world.stocks, isNotNull);
      expect(loaded.world.stocks!.stocks.every((s) => s.listed), isTrue);
    });

    test('the state version knows the market', () {
      expect(stocksVersion, lessThanOrEqualTo(currentStateVersion));
    });
  });
}
