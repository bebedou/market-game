// How the clothing shops trade: plays the prototype with every city in full
// for a few years and prints, for each clothing shop, its last twelve
// months' sales and profit, what its stock has kept of its appeal, what it
// wrote off clearing old stock, and its prices against normal; then the
// average of each strategy against the other trades' shops.
//
//   dart run tool/clothing_balance.dart [--seeds 1-3] [--days 730] [--shops]
//       [--scenario path]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final days = int.parse(option('--days', '730'));
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      option(
        '--scenario',
        root.resolve('scenarios/prototype.json').toFilePath(),
      ),
    ).readAsStringSync(),
  );
  final clothing = content.formats.firstWhere((f) => f.key == 'clothing');
  final byStrategy = <String, List<(int, int, int)>>{};
  final byFormat = <String, List<(int, int)>>{};
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(content, seed: seed);
    for (var day = 0; day < days; day++) {
      game.step();
    }
    for (final company in game.world.companies) {
      if (company.status != CompanyStatus.active) continue;
      final owner = company.owner.index;
      final setup = owner < content.persons.length
          ? content.persons[owner].strategy
          : null;
      final strategy = setup == null ? null : content.strategies[setup.index];
      final view = game.observe(company.owner);
      for (final store in game.world.stores) {
        if (store.company != company.id || store.status != StoreStatus.open) {
          continue;
        }
        final format = content.formats[store.format.index];
        final months = view.companies
            .expand((c) => c.stores)
            .firstWhere((s) => s.id == store.id)
            .recentMonths;
        if (format != clothing) {
          byFormat.putIfAbsent(format.key, () => []).add((
            months.revenue.cents,
            months.profit.cents,
          ));
          continue;
        }
        var units = 0;
        var worth = 0;
        var priced = 0;
        var normal = 0;
        for (final product in content.products) {
          final fashion = content.categories[product.category.index].fashion;
          if (fashion == null) continue;
          final stock = store.stock[product.id.index];
          units += stock.units;
          worth +=
              stock.fashionOn(game.today, fashion, product.tier).raw *
              stock.units;
          if (store.prices[product.id.index] case final price?) {
            priced += price.cents;
            normal += content
                .references[content
                    .countryOf(store.market)
                    .index][product.id.index]
                .cents;
          }
        }
        final writeOffs = company.accounts[AccountKind.writeOffs];
        final key = strategy?.key ?? 'newcomer';
        byStrategy.putIfAbsent(key, () => []).add((
          months.revenue.cents,
          months.profit.cents,
          writeOffs.cents,
        ));
        if (args.contains('--shops')) {
          print(
            '$seed ${store.name.padRight(24)} ${key.padRight(11)} '
            'sales ${(months.revenue.cents ~/ 100).toString().padLeft(7)} '
            'profit ${(months.profit.cents ~/ 100).toString().padLeft(7)} '
            'stock ${units.toString().padLeft(5)} '
            'worth ${units == 0 ? '-' : (worth / units / Fx.scale).toStringAsFixed(2)} '
            'prices ${normal == 0 ? '-' : (priced / normal).toStringAsFixed(2)} '
            'written off ${writeOffs.cents ~/ 100}',
          );
        }
      }
    }
  }
  String k(num cents) => '${(cents / 100000).toStringAsFixed(1)}k';
  print('Clothing, last twelve months, by strategy:');
  for (final MapEntry(:key, :value) in byStrategy.entries) {
    final n = value.length;
    final sales = value.fold(0, (s, v) => s + v.$1) / n;
    final profit = value.fold(0, (s, v) => s + v.$2) / n;
    final off = value.fold(0, (s, v) => s + v.$3) / n;
    print(
      '  ${key.padRight(12)} $n shops: sales ${k(sales)}, profit ${k(profit)} '
      '(${(100 * profit / sales).toStringAsFixed(1)}%), written off ${k(off)} '
      'since the start',
    );
  }
  print('Other trades:');
  for (final MapEntry(:key, :value) in byFormat.entries) {
    final n = value.length;
    final sales = value.fold(0, (s, v) => s + v.$1) / n;
    final profit = value.fold(0, (s, v) => s + v.$2) / n;
    print(
      '  ${key.padRight(12)} $n shops: sales ${k(sales)}, profit ${k(profit)} '
      '(${(100 * profit / sales).toStringAsFixed(1)}%)',
    );
  }
}
