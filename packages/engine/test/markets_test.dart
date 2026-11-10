@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _json = File('../../content/scenarios/prototype.json').readAsStringSync();

/// The prototype with [change] made to its JSON.
ContentDb _with(void Function(Map<String, dynamic> root) change) {
  final root = jsonDecode(_json) as Map<String, dynamic>;
  change(root);
  return loadScenario(jsonEncode(root));
}

Map<String, dynamic> _place(
  Map<String, dynamic> root,
  String list,
  String key,
) => (root[list] as List).cast<Map<String, dynamic>>().firstWhere(
  (place) => place['id'] == key,
);

/// [place]'s market for [trade], times [times].
void _grow(Map<String, dynamic> place, String trade, int times) {
  final market = place['market'] as Map<String, dynamic>;
  market[trade] = Money.parse(
    market[trade] as String,
  ).timesInt(times).toDecimalString();
}

FormatDef _format(ContentDb content, String key) =>
    content.formats.firstWhere((format) => format.key == key);

/// What [market]'s households spend a year on [trade] at the start.
int _spending(ContentDb content, String market, String trade) {
  final game = Simulation.newGame(content, seed: 1);
  return tradeSpending(
    game.observe(content.player),
    content,
    content.markets.firstWhere((m) => m.key == market),
    _format(content, trade),
  ).cents;
}

void _near(num actual, num expected, {double within = 0.002}) =>
    expect((actual - expected).abs() / expected, lessThan(within));

/// Lyon's grocers' sales in months 2 to 4.
int _lyonGrocers(ContentDb content) {
  final game = Simulation.newGame(content, seed: 3);
  final lyon = content.markets.first.id;
  final grocery = content.formatChannels[_format(content, 'grocery').id.index];
  var sales = 0;
  for (var day = 0; day < 120; day++) {
    game.step();
    final world = game.world;
    if (day < 30 || !world.today.isFirstOfMonth) continue;
    for (final store in world.stores) {
      if (store.market != lyon ||
          content.formatChannels[store.format.index] != grocery) {
        continue;
      }
      final reports = game.reports(store.company, ReportPeriod.month);
      if (reports.length < 2) continue;
      sales +=
          reports[reports.length - 2].store(store.id)?.totalRevenue.cents ?? 0;
    }
  }
  expect(invariantViolations(game.world), isEmpty);
  return sales;
}

void main() {
  final base = loadScenario(_json);

  group('a place sized by its market', () {
    test('spends what its market says on each trade', () {
      final bigger = _with(
        (root) => _grow(_place(root, 'markets', 'neighborhood'), 'grocery', 2),
      );
      _near(
        _spending(bigger, 'neighborhood', 'grocery'),
        2 * _spending(base, 'neighborhood', 'grocery'),
      );
      // The other trades keep theirs: only the households' number changed.
      _near(
        _spending(bigger, 'neighborhood', 'fastfood'),
        _spending(base, 'neighborhood', 'fastfood'),
      );
      final lyon = bigger.markets.first;
      final before = base.markets.first;
      int total(MarketDef market) =>
          market.households.fold(0, (sum, count) => sum + count);
      expect(total(lyon), greaterThan(total(before)));
    });

    test('is as big at any income: income changes how they shop', () {
      final richer = _with(
        (root) =>
            _place(root, 'markets', 'neighborhood')['incomeLevel'] = '1.50',
      );
      _near(
        _spending(richer, 'neighborhood', 'grocery'),
        _spending(base, 'neighborhood', 'grocery'),
      );
      int total(MarketDef market) =>
          market.households.fold(0, (sum, count) => sum + count);
      // Better-off households buy dearer goods, so fewer spend as much.
      expect(total(richer.markets.first), lessThan(total(base.markets.first)));
    });

    test('has shops that sell more where it is bigger', () {
      final bigger = _with(
        (root) => _grow(_place(root, 'markets', 'neighborhood'), 'grocery', 2),
      );
      expect(_lyonGrocers(bigger), greaterThan(_lyonGrocers(base) * 1.4));
    });

    test('sizes the shops of a place run by formula', () {
      int sales(ContentDb content) {
        final game = Simulation.newGame(content, seed: 1);
        for (var day = 0; day < 400; day++) {
          game.step();
        }
        final row = content.neighbourhoods.indexWhere(
          (row) => row.key == 'presquile',
        );
        final sleeper = game.world.sleepers.firstWhere((s) => s.row == row);
        return sleeper.shops
            .where(
              (shop) => content.formats[shop.format.index].key == 'grocery',
            )
            .fold(0, (sum, shop) => sum + shop.yearSales.cents);
      }

      final bigger = _with(
        (root) =>
            _grow(_place(root, 'neighbourhoods', 'presquile'), 'grocery', 2),
      );
      expect(sales(bigger), greaterThan(sales(base) * 1.6));
    });

    test('keeps its market once woken', () {
      final bigger = _with(
        (root) =>
            _grow(_place(root, 'neighbourhoods', 'presquile'), 'grocery', 2),
      );
      final row = bigger.neighbourhoods.indexWhere(
        (row) => row.key == 'presquile',
      );
      final channel =
          bigger.formatChannels[_format(bigger, 'grocery').id.index];
      expect(bigger.neighbourhoods[row].scaleOf(channel), isNot(Fx.one));
      final game = Simulation.newGame(bigger, seed: 1);
      game.submit(WakeNeighbourhood(bigger.player, row: row));
      final woken = game.content.markets.last;
      expect(woken.key, 'presquile');
      expect(
        woken.scaleOf(channel),
        bigger.neighbourhoods[row].scaleOf(channel),
      );
      for (var day = 0; day < 20; day++) {
        game.step();
      }
      expect(invariantViolations(game.world), isEmpty);
    });

    test('keeps its market asleep, as a city of the game', () {
      final bigger = _with(
        (root) => _grow(_place(root, 'markets', 'paris'), 'grocery', 2),
      );
      final channel =
          bigger.formatChannels[_format(bigger, 'grocery').id.index];
      final game = Simulation.newGame(bigger, seed: 1, citiesAsleep: true);
      final row = game.content.neighbourhoods.indexWhere(
        (row) => row.key == 'paris',
      );
      final paris = bigger.markets.firstWhere((m) => m.key == 'paris');
      expect(
        game.content.neighbourhoods[row].scaleOf(channel),
        paris.scaleOf(channel),
      );
      game.submit(WakeNeighbourhood(bigger.player, row: row));
      expect(
        game.content.markets.last.scaleOf(channel),
        paris.scaleOf(channel),
      );
    });
  });

  group('a scenario', () {
    void refused(void Function(Map<String, dynamic> lyon) change) => expect(
      () => _with((root) => change(_place(root, 'markets', 'neighborhood'))),
      throwsA(isA<ContentException>()),
    );

    test('gives a place a market or households, not both', () {
      refused((lyon) => lyon['households'] = {'families': 100});
      refused((lyon) => lyon.remove('market'));
    });

    test('names trades it knows, once each', () {
      refused((lyon) => (lyon['market'] as Map)['bakery'] = '1000.00');
      // A supermarket sells groceries: its trade is already given.
      refused((lyon) => (lyon['market'] as Map)['supermarket'] = '1000.00');
      refused((lyon) => (lyon['market'] as Map)['grocery'] = '-1.00');
    });

    test('has someone living in each place', () {
      refused(
        (lyon) => lyon['mix'] = {
          for (final segment in base.segments) segment.key: '0',
        },
      );
    });
  });
}
