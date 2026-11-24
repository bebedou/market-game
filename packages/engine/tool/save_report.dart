// What a save holds: how many bytes each part takes, how many of each thing
// there are, and the biggest sums in it against the 2^53 the engine keeps
// every number under.
//
//   dart run tool/save_report.dart path/to/slot1.mgsave
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/persistence/save_file.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/state/world_state.dart';
import 'package:engine/src/systems/stocks.dart' show listingOf;

void main(List<String> args) {
  final root = Platform.script.resolve('../../../content/');
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
  final file = SaveFile(File(args.single).readAsBytesSync());
  final save = SaveData.decode(content, file);
  final world = save.world;
  String kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} KB';
  int size(void Function(StateWriter writer) write) {
    final writer = StateWriter();
    write(writer);
    return writer.toBytes().length;
  }

  print('${world.today.toIsoString()}, ${kb(file.bytes.length)} in all');
  final parts = <String, int>{
    'world': size(world.write),
    'command log (${save.log.length} commands)': size((w) {
      for (final (:day, :command) in save.log) {
        w.writeInt(day.number);
        command.write(w);
      }
    }),
    'districts asleep (${world.sleepers.length})': size((w) {
      for (final sleeper in world.sleepers) {
        sleeper.write(w);
      }
    }),
    'economies': size(world.writeEconomies),
    'countries by formula': size((w) => writeNational(w, world)),
    'stock market': size((w) => writeStocks(w, world)),
  };
  for (final MapEntry(:key, :value) in parts.entries) {
    print('  ${key.padRight(40)} ${kb(value).padLeft(9)}');
  }
  void count(String what, Iterable<Object?> all, bool Function(Object?) live) {
    final list = all.toList();
    print(
      '  ${what.padRight(20)} ${list.length} '
      '(${list.where(live).length} still going)',
    );
  }

  print('Things:');
  count('companies', world.companies, (c) => (c! as dynamic).isActive as bool);
  count('stores', world.stores, (s) => (s! as dynamic).isTrading as bool);
  count('persons', world.persons, (_) => true);
  count('factories', world.factories, (_) => true);
  count('loans', world.loans, (_) => true);
  count('orders', world.orders, (_) => true);
  count('research reports', world.reports, (_) => true);
  count('period reports', world.periodReports, (_) => true);
  count('brands', world.brands, (_) => true);
  count('economic months', world.economicHistory, (_) => true);
  _biggest(world);
  _stocks(content, world);
}

/// The biggest companies on the exchanges, and each exchange's listed
/// companies together, against 2^53 cents.
void _stocks(ContentDb content, WorldState world) {
  const limit = 9007199254740991;
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) return;
  final order = [for (var i = 0; i < market.stocks.length; i++) i]
    ..sort(
      (a, b) =>
          market.stocks[b].worth.cents.compareTo(market.stocks[a].worth.cents),
    );
  print('Biggest companies on the exchanges (worth in cents):');
  for (final i in order.take(6)) {
    final stock = market.stocks[i];
    final listing = listingOf(def, market, i);
    print(
      '  ${listing.name.padRight(28)} ${listing.kind.name.padRight(9)} '
      'worth ${stock.worth.cents.toString().padLeft(17)} '
      '×${limit ~/ stock.worth.cents.abs().clamp(1, limit)}  '
      '${stock.shares} shares',
    );
  }
  for (var e = 0; e < def.exchanges.length; e++) {
    var together = 0;
    for (final (i, stock) in market.stocks.indexed) {
      if (!stock.listed ||
          listingOf(def, market, i).country != def.exchanges[e].country) {
        continue;
      }
      together += stock.price.cents * stock.shares;
    }
    print(
      '  exchange ${def.exchanges[e].name.padRight(20)} listed together '
      '$together cents ×${(limit / together).toStringAsFixed(2)}',
    );
  }
}

/// The largest balances in the books, and how far each is from 2^53 cents.
void _biggest(WorldState world) {
  const limit = 9007199254740991;
  final all = <(String, AccountKind, int)>[];
  for (final company in world.companies) {
    for (final kind in AccountKind.values) {
      all.add((company.name, kind, company.accounts[kind].cents.abs()));
    }
  }
  for (final (i, person) in world.persons.indexed) {
    for (final kind in AccountKind.values) {
      all.add(('person $i', kind, person.accounts[kind].cents.abs()));
    }
  }
  all.sort((a, b) => b.$3.compareTo(a.$3));
  print('Biggest balances (cents), and how many times over they fit in 2^53:');
  for (final (who, kind, cents) in all.take(8)) {
    print(
      '  ${who.padRight(28)} ${kind.name.padRight(16)} '
      '${cents.toString().padLeft(16)}  ×${limit ~/ (cents == 0 ? 1 : cents)}',
    );
  }
  print(
    '  money supply ${world.moneySupply.cents}  '
    '×${limit ~/ world.moneySupply.cents.abs().clamp(1, limit)}',
  );
}
