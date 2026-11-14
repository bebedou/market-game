// How a chain grows across countries by formula: the player, made rich,
// hands their company to a star director who may open shops run by formula
// in its countries at a rate, a share of its shops a month, and plays some
// years. Prints each year
// the shops run by formula in every country, opened and closed, their sales
// a shop against what a district shop of the same kind sells, their margin,
// the company's trading profit, and in France its buying terms, marketing
// and the pull its brand adds; then France's regions, its chains' prices
// and offers at the end.
//
//   dart run tool/national_balance.dart [--seeds 1-2] [--years 5]
//       [--rate auto|0.04] [--grade star] [--strategy balanced]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-2').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '5'));
  final rate = option('--rate', 'auto');
  final gradeKey = option('--grade', 'star');
  final strategyKey = option('--strategy', 'balanced');
  final root = Platform.script.resolve('../../../content/');
  String read(String path) =>
      File(root.resolve(path).toFilePath()).readAsStringSync();
  final content = loadScenario(
    read('scenarios/prototype.json').replaceFirst(
      '"name": "You", "cash": "20000.00"',
      '"name": "You", "cash": "3000000.00"',
    ),
    national: loadCountryTable(
      read('countries/euro.json'),
      read('countries/calibration.json'),
    ),
  );
  final player = content.player;
  const company = CompanyId(0);
  final strategy = content.strategies.firstWhere((s) => s.key == strategyKey);
  final format = content.formats[strategy.format.index];
  stdout.writeln(
    '${format.name}, growing ${rate == 'auto' ? 'as they judge' : '$rate a month'}, '
    '$gradeKey director, $years years',
  );
  stdout.writeln(
    'seed year  shops  opened closed  a shop sells  (district)  margin  '
    'company trading profit  terms  marketing  brand',
  );
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(content, seed: seed, citiesAsleep: true);
    game
      ..submit(
        InjectCapital(
          player,
          company: company,
          amount: Money.parse('2000000.00'),
        ),
      )
      ..submit(
        HireDirector(
          player,
          company: company,
          grade: content.directors!.grades
              .firstWhere((g) => g.key == gradeKey)
              .id,
          strategy: strategy.id,
          managerGrade: content.managers.grades.last.id,
          growth: Growth.open,
          payout: false,
          nationalAuto: rate == 'auto',
          nationalRate: rate == 'auto' ? Fx.zero : Fx.parse(rate),
        ),
      );
    for (var year = 1; year <= years; year++) {
      var trading = Money.zero;
      final calendar = game.today.date.year;
      while (game.today.date.year == calendar) {
        game.step();
      }
      for (final report in game.reports(company, ReportPeriod.month)) {
        if (report.start.date.year == calendar) {
          trading += report.tradingProfit;
        }
      }
      final france = game.observe(player).national.first.def.key == 'fr'
          ? game.observe(player).national.first
          : game
                .observe(player)
                .national
                .firstWhere((country) => country.def.key == 'fr');
      final block = france.blocks
          .where((b) => b.company == company)
          .firstOrNull;
      // Every country's: a director may grow wherever pays back soonest.
      final blocks = [
        for (final country in game.observe(player).national)
          for (final b in country.blocks)
            if (b.company == company) b,
      ];
      var opened = 0;
      var closed = 0;
      var sales = Money.zero;
      var profit = Money.zero;
      var shopMonths = 0;
      var stores = 0;
      for (final b in blocks) {
        stores += b.stores;
        for (final month in b.months) {
          if (month.start.date.year != calendar) continue;
          opened += month.opened;
          closed += month.closed;
          sales += month.sales;
          profit += month.profit;
          shopMonths += month.stores;
        }
      }
      final perShop = shopMonths == 0
          ? 0
          : sales.cents ~/ 100 * 12 ~/ shopMonths;
      final margin = sales.cents == 0 ? 0 : profit.cents * 1000 ~/ sales.cents;
      stdout.writeln(
        '${'$seed'.padLeft(4)} ${'$year'.padLeft(4)}  '
        '${'$stores'.padLeft(5)}  ${'$opened'.padLeft(6)} '
        '${'$closed'.padLeft(6)}  ${'$perShop'.padLeft(12)}  '
        '(${format.national!.salesIn(content.countries.first.id).cents ~/ 100})'
        '  ${(margin / 10).toStringAsFixed(1).padLeft(5)}%  '
        '${'${trading.cents ~/ 100}'.padLeft(12)}  '
        '${(-(block?.discount.raw ?? 0) / 100).toStringAsFixed(1).padLeft(5)}%  '
        '${((block?.marketing.raw ?? 0) / 100).toStringAsFixed(1).padLeft(8)}%  '
        '${((block?.brandPull.raw ?? 0) / 100).toStringAsFixed(1).padLeft(5)}%',
      );
    }
    final view = game.observe(player).national;
    final france = view.firstWhere((country) => country.def.key == 'fr');
    final block = france.blocks.where((b) => b.company == company).firstOrNull;
    if (block == null) continue;
    final trade = france.tradeOf(content, format.id)!;
    for (final chain in france.chains) {
      final value = chain.value;
      if (chain.trade != trade || value == null) continue;
      stdout.writeln(
        '      chain ${chain.name.padRight(24)} ${'${chain.stores}'.padLeft(5)} '
        'shops  earns ${value.earnings.cents ~/ 100}  price '
        '${value.price.cents ~/ 100}',
      );
    }
    stdout.writeln(
      '      your shops: worth ${(block.value?.price.cents ?? 0) ~/ 100} '
      'to ${block.buyer}; offers ${france.offers.length}',
    );
    for (final (r, region) in france.def.regions.indexed) {
      final mine = block.regions[r];
      if (mine.trading + mine.pending == 0) continue;
      final market = france.markets[trade][r];
      final share = market.cents == 0
          ? 0
          : mine.yearSales.cents * 10000 ~/ market.cents;
      final next = france.newShop(
        content,
        company: company,
        format: format.id,
        strategy: strategy.id,
        region: r,
      );
      stdout.writeln(
        '      ${region.name.padRight(28)} ${'${mine.trading + mine.pending}'.padLeft(4)} shops '
        '${(share / 100).toStringAsFixed(2).padLeft(6)}%  '
        'a year ${mine.yearSales.cents ~/ 100}  profit ${mine.yearProfit.cents ~/ 100}  '
        'next shop ${next.profit.cents ~/ 100}',
      );
    }
  }
}
