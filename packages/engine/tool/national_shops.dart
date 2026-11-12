// What a typical shop of each kind sells and keeps in a year, country by
// country, in the districts run by formula: what a company's shops run by
// formula across a country are sized on (the scenario's formats' `national`
// figures), and what they should come close to. Plays a game with the other
// cities asleep for a year and a month, then averages the districts' shops
// that have traded for two years, by kind and country: their sales, margin,
// and their premises (rent and overheads) and staff as shares of sales,
// staff taken as what's left once goods, marketing, premises and profit are
// counted, so that shops run by formula across the country keep about the
// same margin.
//
//   dart run tool/national_shops.dart [--seeds 1-3]
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/systems/sleepers.dart' show formulaGoodsExtra;

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      root.resolve('scenarios/prototype.json').toFilePath(),
    ).readAsStringSync(),
  );
  final formats = content.formats.length;
  final countries = content.countries.length;
  final sales = List.generate(countries, (_) => List.filled(formats, 0));
  final profit = List.generate(countries, (_) => List.filled(formats, 0));
  final shops = List.generate(countries, (_) => List.filled(formats, 0));
  // Goods, marketing and premises a year, in cents.
  final goods = List.generate(countries, (_) => List.filled(formats, 0));
  final marketing = List.generate(countries, (_) => List.filled(formats, 0));
  final premises = List.generate(countries, (_) => List.filled(formats, 0));
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(content, seed: seed, citiesAsleep: true);
    for (var day = 0; day < 396; day++) {
      game.step();
    }
    final months = game.world.regimeLog.length;
    final rows = game.content.neighbourhoods;
    for (final sleeper in game.world.sleepers) {
      final country = rows[sleeper.row].country.index;
      final level = game.world.macroOf(rows[sleeper.row].country).priceIndex;
      for (final shop in sleeper.shops) {
        if (months - shop.openedMonth < 24 || shop.sales.length < 12) continue;
        final f = shop.format.index;
        final format = content.formats[f];
        final strategy = content.strategies[shop.strategy.index];
        final sold = shop.yearSales;
        sales[country][f] += sold.cents ~/ 100;
        profit[country][f] += shop.yearProfit.cents ~/ 100;
        goods[country][f] += sold
            .times(
              Fx.one.div(Fx.one + strategy.markup) *
                  (Fx.one + formulaGoodsExtra(format)),
            )
            .cents;
        marketing[country][f] += sold.times(strategy.marketingShare).cents;
        final site = sleeper.sites![shop.site];
        premises[country][f] +=
            (site.rentFor(shop.area) + format.overheadsFor(shop.area))
                .times(level)
                .timesInt(12)
                .cents;
        shops[country][f]++;
      }
    }
  }
  stdout.writeln(
    'kind of shop      country  shops  sales a year  margin  staff  premises',
  );
  for (final format in content.formats) {
    for (final country in content.countries) {
      final c = country.id.index;
      final f = format.id.index;
      if (shops[c][f] == 0) continue;
      final average = sales[c][f] ~/ shops[c][f];
      final margin = sales[c][f] == 0 ? 0 : profit[c][f] * 1000 ~/ sales[c][f];
      final cents = sales[c][f] * 100;
      final premisesShare = premises[c][f] / cents;
      final staffShare =
          (cents - goods[c][f] - marketing[c][f] - premises[c][f]) / cents -
          profit[c][f] / sales[c][f];
      stdout.writeln(
        '${format.key.padRight(16)}  ${country.key.padRight(7)}  '
        '${'${shops[c][f]}'.padLeft(5)}  ${'$average'.padLeft(12)}  '
        '${(margin / 10).toStringAsFixed(1).padLeft(5)}%  '
        '${staffShare.toStringAsFixed(3)}  ${premisesShare.toStringAsFixed(3)}',
      );
    }
  }
}
