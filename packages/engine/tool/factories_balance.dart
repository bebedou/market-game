// How a factory pays: a chain of the player's grocers in France, each run by
// an expert manager, with and without a plant of their own, played for some
// years over several seeds. Prints, per seed and setup, the chain's yearly
// profit, and for the plant what it made, its use of capacity, what it
// earned against buying each year and in recession months, and what its
// shops bought in beyond it.
//
//   dart run tool/factories_balance.dart [--seeds 1-3] [--years 5]
//       [--kind drinks] [--shops 5] [--shifts 2] [--country fr]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '5'));
  final kindKey = option('--kind', 'drinks');
  final shops = int.parse(option('--shops', '5'));
  final shifts = int.parse(option('--shifts', '2'));
  final countryKey = option('--country', 'fr');
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      root.resolve('scenarios/prototype.json').toFilePath(),
    ).readAsStringSync().replaceFirst(
      '"name": "You", "cash": "20000.00"',
      '"name": "You", "cash": "3000000.00"',
    ),
  );
  final kind = content.factories!.kinds.firstWhere((k) => k.key == kindKey);
  final country = content.countries.firstWhere((c) => c.key == countryKey).id;
  final france = content.countries.first.id;
  stdout.writeln(
    '${kind.name} in ${content.countries[country.index].name}, '
    '$shops grocers, $shifts shifts, $years years',
  );
  stdout.writeln(
    'seed  setup     chain profit/yr by year                 '
    '| made/yr  use   earned/yr  recession/mo  other/mo  bought in',
  );
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    for (final withFactory in [false, true]) {
      final game = Simulation.newGame(content, seed: seed);
      final player = content.player;
      const company = CompanyId(0);
      game.submit(
        InjectCapital(
          player,
          company: company,
          amount: Money.parse('2500000.00'),
        ),
      );
      game.step();
      // The cheapest French grocers on sale, until the chain has its size.
      final view = game.observe(player);
      final grocery = content.formats
          .where((f) => content.formats[f.id.index].sells[0])
          .map((f) => f.id)
          .toSet();
      final candidates =
          [
            for (final shelf in view.shelves)
              if (view.companyOwners[shelf.company.index] != player &&
                  shelf.status != StoreStatus.closed &&
                  grocery.contains(shelf.format) &&
                  content.countryOf(shelf.market) == france &&
                  view.valuations[shelf.id.index] != null)
                shelf.id,
          ]..sort((a, b) {
            final byPrice = view.valuations[a.index]!.price.cents.compareTo(
              view.valuations[b.index]!.price.cents,
            );
            return byPrice != 0 ? byPrice : a.index - b.index;
          });
      for (final store in candidates.take(shops - 1)) {
        game.submit(BuyStore(player, store: store, company: company));
      }
      game.step();
      final owned = game.observe(player).companies.first.stores;
      for (final store in owned) {
        game.submit(
          HireManager(
            player,
            store: store.id,
            grade: content.managers.grades.last.id,
            strategy: content.strategies
                .firstWhere((s) => s.key == 'balanced')
                .id,
            duties: const [true, true, true, true, false],
          ),
        );
      }
      if (withFactory) {
        game.submit(
          BuildFactory(
            player,
            kind: kind.id,
            country: country,
            name: 'Plant',
            company: company,
            shifts: shifts,
            serves: [
              for (var c = 0; c < content.countries.length; c++)
                c == country.index || c == france.index,
            ],
          ),
        );
      }
      final rejected = game.step().rejections;
      if (rejected.isNotEmpty) {
        stdout.writeln('  refused: ${rejected.map((r) => r.reason.key)}');
      }
      final profits = <int>[];
      var made = 0;
      var capacity = 0;
      var boughtIn = 0;
      var earned = Money.zero;
      var recession = Money.zero;
      var recessionMonths = 0;
      var other = Money.zero;
      var otherMonths = 0;
      var yearProfit = Money.zero;
      final flows = List.filled(AccountKind.values.length, Money.zero);
      var sold = 0;
      var missed = 0;
      final end = Day(game.today.number + 365 * years);
      String? month;
      while (game.today < end) {
        final regime = content.macro.regimes[game.world.macro.regime.index].key;
        game.step();
        if (!game.today.isFirstOfMonth) continue;
        final report = game.reports(company, ReportPeriod.month).last;
        yearProfit += report.tradingProfit;
        for (final kind in AccountKind.values) {
          flows[kind.index] += report.flow(kind);
        }
        for (final store in report.stores) {
          for (final product in content.products) {
            if (product.category != kind.category) continue;
            sold += store.sold(product.id);
            missed += store.missed(MissReason.outOfStock, product.id);
          }
        }
        if (game.today.date.month == 1) {
          profits.add(yearProfit.cents ~/ 100);
          yearProfit = Money.zero;
        }
        final part = report.factory(const FactoryId(0));
        month = regime;
        if (part == null) continue;
        made += part.made;
        boughtIn += part.totalBoughtIn;
        earned += part.profit;
        final factory = game.observe(player).companies.first.factories.first;
        capacity += factory.making
            ? kind.shiftUnits * factory.shifts * report.days
            : 0;
        if (month == 'recession') {
          recession += part.profit;
          recessionMonths++;
        } else {
          other += part.profit;
          otherMonths++;
        }
      }
      final use = capacity == 0 ? 0 : made * 100 ~/ capacity;
      int perYear(int value) => value ~/ years;
      stdout.writeln(
        '${'$seed'.padLeft(4)}  ${withFactory ? 'factory ' : 'buying  '}  '
        '${profits.map((p) => '$p'.padLeft(7)).join(' ').padRight(40)}| '
        '${'${perYear(made)}'.padLeft(7)}  ${'$use%'.padLeft(4)}  '
        '${'${perYear(earned.cents) ~/ 100}'.padLeft(9)}  '
        '${'${recessionMonths == 0 ? '-' : recession.cents ~/ 100 ~/ recessionMonths}'.padLeft(12)}  '
        '${'${otherMonths == 0 ? '-' : other.cents ~/ 100 ~/ otherMonths}'.padLeft(8)}  '
        '${perYear(boughtIn)}  sold ${perYear(sold)} '
        'out of stock ${perYear(missed)}',
      );
      if (args.contains('--flows')) {
        stdout.writeln(
          '      ${[for (final kind in AccountKind.values)
            if (flows[kind.index] != Money.zero) '${kind.name} ${flows[kind.index].cents ~/ 100 ~/ years}'].join(', ')}',
        );
      }
    }
  }
}
