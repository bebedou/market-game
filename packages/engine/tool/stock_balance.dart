// How the stock market behaves over a game, and whether spotting value
// pays: each exchange's index year by year, its worst fall, and a year's
// return, dividends included, of a few ways to pick shares each January,
// against all of them bought equally.
//
//   dart run tool/stock_balance.dart [--seeds 1-4] [--years 10]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  var seeds = [1, 4];
  var years = 10;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--seeds') {
      final parts = args[i + 1].split('-').map(int.parse).toList();
      seeds = [parts.first, parts.last];
    }
    if (args[i] == '--years') years = int.parse(args[i + 1]);
  }
  final root = Directory.current.uri.resolve('../../content/');
  String read(String path) =>
      File(root.resolve(path).toFilePath()).readAsStringSync();
  final content = loadScenario(
    read('scenarios/prototype.json'),
    national: loadCountryTable(
      read('countries/euro.json'),
      read('countries/calibration.json'),
    ),
    stocks: read('stocks/companies.json'),
  );
  final def = content.stocks!;
  final picks = <String, List<double>>{};
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(
      content,
      seed: seed,
      start: const GameStart.holding('Holding'),
      citiesAsleep: true,
    );
    final market = game.world.stocks!;
    final peaks = [for (final e in market.exchanges) e.level.cents];
    final falls = List.filled(market.exchanges.length, 0.0);
    final levels = <List<String>>[];
    final regimes = <String>[];
    // What each way of picking held from last January, at what price.
    var held = <String, List<(int, Money)>>{};
    for (var year = 0; year <= years; year++) {
      if (year > 0) {
        for (final MapEntry(key: way, value: stocks) in held.entries) {
          var total = 0.0;
          for (final (i, bought) in stocks) {
            final stock = market.stocks[i];
            var paid = 0;
            for (final result in stock.results) {
              if (result.day.number > game.today.number - 366) {
                paid += result.dividends.cents ~/ stock.shares;
              }
            }
            final now = stock.listed ? stock.price.cents : 0;
            total += (now + paid) / bought.cents - 1;
          }
          if (stocks.isNotEmpty) {
            (picks[way] ??= []).add(total / stocks.length);
          }
        }
      }
      levels.add([
        for (final e in market.exchanges)
          (e.level.cents / 100).round().toString(),
      ]);
      final regime = content.macro.regimes[game.world.cycle!.regime.index].key;
      regimes.add(regime);
      final view = game.observe(game.world.player).stocks!;
      final listed = [
        for (final stock in view.stocks)
          if (stock.listed) stock,
      ];
      final cheap =
          [
            for (final stock in listed)
              if (stock.kind == ListingKind.formula &&
                  stock.multiple != null &&
                  (stock.management ?? 0) >= averageManagement)
                stock,
          ]..sort((a, b) {
            final x =
                a.multiple!.raw *
                1000 ~/
                (a.averageMultiple?.raw ?? a.multiple!.raw);
            final y =
                b.multiple!.raw *
                1000 ~/
                (b.averageMultiple?.raw ?? b.multiple!.raw);
            return x.compareTo(y);
          });
      final dear = [...cheap.reversed];
      held = {
        'every stock': [for (final s in listed) (s.index, s.price)],
        'cheapest 20 against their usual, run well': [
          for (final s in cheap.take(20)) (s.index, s.price),
        ],
        'dearest 20 against their usual': [
          for (final s in dear.take(20)) (s.index, s.price),
        ],
        'strong buys': [
          for (final s in listed)
            if (s.rating == AnalystRating.strongBuy) (s.index, s.price),
        ],
        'strong sells': [
          for (final s in listed)
            if (s.rating == AnalystRating.strongSell) (s.index, s.price),
        ],
        'excellent management': [
          for (final s in listed)
            if (s.kind == ListingKind.formula && s.management == 4)
              (s.index, s.price),
        ],
        'bad management': [
          for (final s in listed)
            if (s.kind == ListingKind.formula && s.management == 0)
              (s.index, s.price),
        ],
      };
      if (year == years) break;
      final end = Day.fromDate(game.today.date.year + 1, 1, 1);
      while (game.today < end) {
        game.step();
        for (final (e, exchange) in market.exchanges.indexed) {
          final level = exchange.level.cents;
          if (level > peaks[e]) peaks[e] = level;
          final fall = 1 - level / peaks[e];
          if (fall > falls[e]) falls[e] = fall;
        }
      }
    }
    stdout.writeln('Seed $seed');
    stdout.writeln(
      '  year   ${[for (final e in def.exchanges) e.name.padLeft(9)].join()}  cycle',
    );
    for (final (y, row) in levels.indexed) {
      stdout.writeln(
        '  ${y.toString().padLeft(4)}   ${[for (final v in row) v.padLeft(9)].join()}  ${regimes[y]}',
      );
    }
    stdout.writeln(
      '  worst fall ${[for (final f in falls) '${(f * 100).round()}%'.padLeft(9)].join()}',
    );
  }
  stdout.writeln(
    '\nA year held from each January, dividends included (mean, worst, best):',
  );
  for (final MapEntry(key: way, value: returns) in picks.entries) {
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    returns.sort();
    stdout.writeln(
      '  ${way.padRight(44)} ${(mean * 100).toStringAsFixed(1).padLeft(6)}%'
      '  ${(returns.first * 100).toStringAsFixed(0).padLeft(5)}%'
      '  ${(returns.last * 100).toStringAsFixed(0).padLeft(5)}%',
    );
  }
}
