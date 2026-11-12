// How business goes in each country: games started in each city of the
// scenario, the player's shop left idle, and the rivals' and districts' shops
// measured by country over years 2 to 5. Prints, per country, the margin of
// the city played in full and of the districts by formula, how many shops
// closed and opened, and what a recession does to sales there.
//
//   dart run tool/countries_balance.dart [--seeds 1-3] [--years 5]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '5'));
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      root.resolve('scenarios/prototype.json').toFilePath(),
    ).readAsStringSync(),
    national: loadCountryTable(
      File(root.resolve('countries/euro.json').toFilePath()).readAsStringSync(),
      File(
        root.resolve('countries/calibration.json').toFilePath(),
      ).readAsStringSync(),
    ),
  );
  const starts = [
    'neighborhood',
    'berlin',
    'munich',
    'milan',
    'rome',
    'madrid',
    'barcelona',
  ];
  stdout.writeln(
    'start        seed  city sales  city margin  closed | '
    'districts by country: margin, shops start->end, recession sales',
  );
  for (final key in starts) {
    for (var seed = seeds.first; seed <= seeds.last; seed++) {
      final site = content.sites.firstWhere(
        (site) =>
            content.markets[site.market.index].key == key &&
            startingSites(content).contains(site.id),
      );
      final game = Simulation.newGame(
        content,
        seed: seed,
        start: GameStart(site: site.id, format: const FormatId(0), name: 'Me'),
        citiesAsleep: true,
      );
      final world = game.world;
      final rows = game.content.neighbourhoods;
      final countries = game.content.countries;
      final shopsAtStart = List.filled(countries.length, 0);
      for (final sleeper in world.sleepers) {
        shopsAtStart[rows[sleeper.row].country.index] += sleeper.shops.length;
      }
      // Sales by formula per country in each regime, a month at a time.
      final byRegime = [
        for (final _ in countries)
          {
            for (final regime in game.content.macro.regimes)
              regime.key: <int>[],
          },
      ];
      final firstDay = game.content.startDay.number + 365;
      while (world.today.number < game.content.startDay.number + 365 * years) {
        game.step();
        if (!world.today.isFirstOfMonth || world.today.number < firstDay) {
          continue;
        }
        final sales = List.filled(countries.length, 0);
        final households = List.filled(countries.length, 0);
        for (final sleeper in world.sleepers) {
          final country = rows[sleeper.row].country.index;
          for (final shop in sleeper.shops) {
            if (shop.sales.isNotEmpty) sales[country] += shop.sales.last.cents;
          }
          households[country] += sleeper.households.fold(0, (a, b) => a + b);
        }
        for (final country in countries) {
          final regime = game
              .content
              .macro
              .regimes[world.macroOf(country.id).regime.index];
          if (households[country.id.index] > 0) {
            byRegime[country.id.index][regime.key]!.add(
              sales[country.id.index] * 1000 ~/ households[country.id.index],
            );
          }
        }
      }
      // The city in full: its rivals' stores, years 2 on.
      final city = game.content.markets.single.id;
      var revenue = 0;
      var profit = 0;
      for (final report in world.periodReports) {
        if (report.period != ReportPeriod.month ||
            report.start.number < firstDay ||
            world.companies[report.company.index].owner == world.player) {
          continue;
        }
        for (final store in report.stores) {
          if (world.stores[store.store.index].market != city) continue;
          revenue += store.totalRevenue.cents;
          profit += store.profit.cents;
        }
      }
      final closed = world.stores
          .where(
            (store) =>
                store.market == city &&
                !store.isTrading &&
                world.companies[store.company.index].owner != world.player,
          )
          .length;
      final shopsNow = List.filled(countries.length, 0);
      final districtSales = List.filled(countries.length, 0);
      final districtProfit = List.filled(countries.length, 0);
      for (final sleeper in world.sleepers) {
        final country = rows[sleeper.row].country.index;
        shopsNow[country] += sleeper.shops.length;
        for (final shop in sleeper.shops) {
          districtSales[country] += shop.yearSales.cents;
          districtProfit[country] += shop.yearProfit.cents;
        }
      }
      String pct(int part, int whole) => whole == 0
          ? '   -'
          : (part * 100 / whole).toStringAsFixed(1).padLeft(5);
      double mean(List<int> values) =>
          values.isEmpty ? 0 : values.fold(0, (a, b) => a + b) / values.length;
      final parts = [
        for (final country in countries)
          () {
            final c = country.id.index;
            final regimes = byRegime[c];
            final expansion = mean(regimes['expansion']!);
            final recession = mean(regimes['recession']!);
            final swing = expansion == 0 || regimes['recession']!.isEmpty
                ? '  -'
                : '${((recession / expansion - 1) * 100).toStringAsFixed(0)}%';
            return '${country.key} ${pct(districtProfit[c], districtSales[c])}% '
                '${shopsAtStart[c]}->${shopsNow[c]} $swing';
          }(),
      ];
      stdout.writeln(
        '${key.padRight(12)} ${'$seed'.padLeft(4)}  '
        '${(revenue / 100 / (years - 1)).round().toString().padLeft(10)}  '
        '${pct(profit, revenue)}%       ${'$closed'.padLeft(3)} | '
        '${parts.join('  ')}',
      );
    }
  }
}
