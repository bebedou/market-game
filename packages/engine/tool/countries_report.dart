// Prints what the countries run by formula come to: the markets against what
// sellers really reported, then how the world behaves over the years.
//
//   dart run tool/countries_report.dart [--years 20] [--seeds 8]
import 'dart:io';

import 'package:engine/countries.dart';
import 'package:engine/engine.dart';

String billions(int cents) => (cents / 1e11).toStringAsFixed(1).padLeft(7);

String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

void main(List<String> args) {
  int option(String name, int fallback) =>
      args.contains(name) ? int.parse(args[args.indexOf(name) + 1]) : fallback;
  final years = option('--years', 20);
  final seeds = option('--seeds', 8);
  final root = Platform.script.resolve('../../../content/countries/');
  final table = loadCountryTable(
    File(root.resolve('euro.json').toFilePath()).readAsStringSync(),
    File(root.resolve('calibration.json').toFilePath()).readAsStringSync(),
  );

  stdout
    ..writeln(
      'What households spend against what sellers report, ${table.asOf}, €bn',
    )
    ..writeln('  country   trade         spending  turnover  ratio');
  for (final country in table.countries) {
    for (final (t, trade) in table.trades.indexed) {
      var spending = 0;
      for (final row in country.classes) {
        spending += row.spending[t].cents * row.households;
      }
      final turnover = country.trades[t].turnover.cents;
      stdout.writeln(
        '  ${country.name.padRight(9)} ${trade.key.padRight(13)} '
        '${billions(spending)}   ${billions(turnover)}  '
        '${(spending / turnover).toStringAsFixed(2)}',
      );
    }
  }

  stdout.writeln('\nA year in, seed 1');
  final first = CountryEconomy(table, seed: 1);
  for (var m = 0; m < 12; m++) {
    first.advanceMonth();
  }
  for (final country in first.countries) {
    stdout.writeln('  ${country.def.name}');
    for (final chain in country.chains) {
      final sales = chain.months.fold(0, (sum, m) => sum + m.sales.cents);
      final profit = chain.months.fold(0, (sum, m) => sum + m.profit.cents);
      stdout.writeln(
        '    ${chain.def.name.padRight(26)} ${chain.stores.toString().padLeft(7)} stores '
        '${billions(sales)}bn  ${percent(profit / sales).padLeft(6)} margin',
      );
    }
  }

  stdout.writeln('\nOver $years years and $seeds seeds');
  final clock = Stopwatch();
  var months = 0;
  final realGrowth = <String, List<double>>{};
  final storeGrowth = <String, List<double>>{};
  final margins = <String, List<double>>{};
  var failed = 0;
  var lowest = 1.0;
  var highest = -1.0;
  for (var seed = 1; seed <= seeds; seed++) {
    final economy = CountryEconomy(table, seed: seed);
    final startMarkets = <String, int>{};
    final startStores = <String, int>{};
    for (var month = 0; month < years * 12; month++) {
      clock.start();
      economy.advanceMonth();
      clock.stop();
      months++;
      for (final country in economy.countries) {
        for (final (t, trade) in table.trades.indexed) {
          final key = '${country.def.key} ${trade.key}';
          final stores = [
            for (final chain in country.chains)
              if (chain.def.trade == t) chain.stores,
          ].fold(0, (sum, n) => sum + n);
          final market = country.tradeMonths[t].last;
          if (month == 11) {
            startMarkets[key] = country.tradeMonths[t].fold(
              0,
              (sum, m) => sum + m.market.cents,
            );
            startStores[key] = stores;
          }
          if (month == years * 12 - 1) {
            final last = country.tradeMonths[t]
                .skip(country.tradeMonths[t].length - 12)
                .fold(0, (sum, m) => sum + m.market.cents);
            final prices = market.priceIndex.raw / Fx.scale;
            (realGrowth[key] ??= []).add(
              (last / prices / startMarkets[key]! - 1) * 100 / (years - 1),
            );
            (storeGrowth[key] ??= []).add(
              (stores / startStores[key]! - 1) * 100 / (years - 1),
            );
            final chains = [
              for (final chain in country.chains)
                if (chain.def.trade == t && chain.isTrading) chain,
            ];
            var sales = 0;
            var profit = 0;
            for (final chain in chains) {
              for (final m in chain.months.skip(chain.months.length - 12)) {
                sales += m.sales.cents;
                profit += m.profit.cents;
              }
            }
            (margins[key] ??= []).add(profit / sales);
          }
        }
        for (final chain in country.chains) {
          if (chain.months.isEmpty || !chain.isTrading) continue;
          final m = chain.months.last;
          final margin = m.profit.cents / m.sales.cents;
          if (margin < lowest) lowest = margin;
          if (margin > highest) highest = margin;
        }
      }
    }
    for (final country in economy.countries) {
      failed += country.chains.where((c) => c.failed).length;
    }
  }
  double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  stdout.writeln('  market       real growth/yr  stores/yr  margin  normal');
  for (final country in table.countries) {
    for (final (t, trade) in table.trades.indexed) {
      final key = '${country.key} ${trade.key}';
      stdout.writeln(
        '  ${key.padRight(16)} ${mean(realGrowth[key]!).toStringAsFixed(2).padLeft(6)} '
        '${mean(storeGrowth[key]!).toStringAsFixed(2).padLeft(10)} '
        '${percent(mean(margins[key]!)).padLeft(8)} '
        '${percent(country.trades[t].normalMargin.raw / Fx.scale).padLeft(7)}',
      );
    }
  }
  stdout
    ..writeln(
      '  chains failed per game: ${(failed / seeds).toStringAsFixed(1)}',
    )
    ..writeln(
      '  chain margin in any month: ${percent(lowest)} to ${percent(highest)}',
    )
    ..writeln(
      '  time: ${(clock.elapsedMicroseconds / months).toStringAsFixed(1)} µs a month '
      'for ${table.countries.length} countries',
    );

  final last = CountryEconomy(table, seed: 1);
  for (var m = 0; m < 36; m++) {
    last.advanceMonth();
  }
  final germany = last.countries.first;
  final top = germany.chains.first;
  final why = last.yearOnYear(germany, top)!;
  stdout.writeln(
    '\n${top.def.name}, latest year against the one before, €bn: '
    '${billions(why.before.cents).trim()} to ${billions(why.after.cents).trim()}: '
    'population ${billions(why.population.cents).trim()}, '
    'income ${billions(why.income.cents).trim()}, '
    'prices ${billions(why.prices.cents).trim()}, '
    'economy ${billions(why.economy.cents).trim()}, '
    'share ${billions(why.share.cents).trim()}',
  );
}
