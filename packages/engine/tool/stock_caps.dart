// Fills in the market caps and share counts content/stocks/companies.json
// leaves to the game: those of its own companies (chains, software rivals,
// rival producers), at what their books are worth when a game starts. The
// rest of the file is left as it is.
//
//   dart run tool/stock_caps.dart [--all]
//
// With --all, the game's own companies are set again even where the file
// already gives a cap.
import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  final all = args.contains('--all');
  final root = Directory.current.uri.resolve('../../content/');
  String read(String path) =>
      File(root.resolve(path).toFilePath()).readAsStringSync();
  final path = root.resolve('stocks/companies.json').toFilePath();
  final text = File(path).readAsStringSync();
  final table = jsonDecode(text) as Map<String, Object?>;
  final companies = (table['companies']! as List).cast<Map<String, Object?>>();
  if (all) {
    for (final company in companies) {
      if (_ownBooks(company)) {
        company
          ..['cap'] = null
          ..['shares'] = null;
      }
    }
  }
  final content = loadScenario(
    read('scenarios/prototype.json'),
    national: loadCountryTable(
      read('countries/euro.json'),
      read('countries/calibration.json'),
    ),
    stocks: jsonEncode(table),
  );
  final game = Simulation.newGame(
    content,
    seed: 1,
    start: const GameStart.holding('Holding'),
    citiesAsleep: true,
  );
  final view = game.observe(game.world.player).stocks!;
  var filled = 0;
  for (final (i, company) in companies.indexed) {
    if (company['cap'] != null) continue;
    final stock = view.stocks[i];
    // To the nearest 100,000 euros.
    final euros = (stock.cap.cents + 5000000) ~/ 10000000 * 100000;
    company
      ..['cap'] = '$euros'
      ..['shares'] = stock.shares;
    filled++;
  }
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(table)}\n');
  stdout.writeln('Filled in $filled caps.');
}

bool _ownBooks(Map<String, Object?> company) =>
    company['chain'] != null ||
    company['software'] != null ||
    company['producer'] != null;
