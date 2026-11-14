// How a lab pays: a chain of the player's grocers in France with a plant of
// their own, each run by an expert manager, played for some years over
// several seeds, without a lab and with one. Prints, per seed and setup,
// the chain's yearly profit (shops, plant and lab together), what the lab
// cost a year, the generations it launched and each line's lead at the end.
//
//   dart run tool/labs_balance.dart [--seeds 1-3] [--years 5]
//       [--kind drinks] [--shops 7] [--shifts 2] [--budget 5000]
//       [--line premium] [--engineer 2] [--designer 2]
//
// --engineer and --designer hire one person of that level (0 the most
// ordinary), known for what they are; leave them out for a lab of money
// alone.
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/talent.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '5'));
  final kindKey = option('--kind', 'drinks');
  final shops = int.parse(option('--shops', '7'));
  final shifts = int.parse(option('--shifts', '2'));
  final budget = Money.parse('${option('--budget', '5000')}.00');
  final lineKey = option('--line', 'premium');
  final engineer = int.tryParse(option('--engineer', ''));
  final designer = int.tryParse(option('--designer', ''));
  // To measure what quality alone is worth: no lab, both lines held this
  // many points over the standard.
  final force = int.tryParse(option('--force', ''));
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
  final france = content.countries.first.id;
  final line = content.products
      .firstWhere((p) => p.category == kind.category && p.tier.name == lineKey)
      .id;
  stdout.writeln(
    '${kind.name}, $shops grocers, $shifts shifts, $years years; lab at '
    '${budget.toDecimalString()} a month on ${content.products[line.index].name}'
    '${engineer == null ? '' : ', engineer of level $engineer'}'
    '${designer == null ? '' : ', designer of level $designer'}',
  );
  stdout.writeln(
    'seed  setup   chain profit/yr by year                 '
    '| sales/yr  visits/yr  lab/yr  gens  leads at the end',
  );
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    for (final withLab in [false, true]) {
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
      for (final store in game.observe(player).companies.first.stores) {
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
      game.submit(
        BuildFactory(
          player,
          kind: kind.id,
          country: france,
          name: 'Plant',
          company: company,
          shifts: shifts,
        ),
      );
      var rejected = game.step().rejections;
      if (withLab && force == null) {
        const factory = FactoryId(0);
        for (final (role, level) in [
          (KeyRole.engineer, engineer),
          (KeyRole.designer, designer),
        ]) {
          if (level == null) continue;
          final id = KeyPersonId(game.world.keyPeople.length);
          game.world.keyPeople.add(
            KeyPerson(
              id: id,
              name: 'Hired ${role.name}',
              role: role,
              level: level,
              repute: level,
              since: game.today,
            ),
          );
          game.submit(HireKeyPerson(player, person: id, factory: factory));
        }
        game.submit(
          SetLab(player, factory: factory, budget: budget, project: line),
        );
        rejected = game.step().rejections;
      }
      if (rejected.isNotEmpty) {
        stdout.writeln('  refused: ${rejected.map((r) => r.reason.key)}');
      }
      final profits = <int>[];
      var yearProfit = Money.zero;
      var sales = Money.zero;
      var visits = 0;
      var lab = Money.zero;
      var generations = 0;
      final end = Day(game.today.number + 365 * years);
      while (game.today < end) {
        if (withLab && force != null) {
          for (final product in content.products) {
            if (product.category != kind.category) continue;
            game.world.factories.first.lineFor(product.id).lead = Fx.raw(
              force * 100,
            );
          }
        }
        final result = game.step();
        generations += result.events.whereType<GenerationLaunched>().length;
        if (!game.today.isFirstOfMonth) continue;
        final report = game.reports(company, ReportPeriod.month).last;
        yearProfit += report.tradingProfit;
        for (final store in report.stores) {
          sales += store.totalRevenue;
          visits += store.visits;
        }
        lab += report.factory(const FactoryId(0))?.lab ?? Money.zero;
        if (game.today.date.month == 1) {
          profits.add(yearProfit.cents ~/ 100);
          yearProfit = Money.zero;
        }
      }
      final leads = [
        for (final made
            in game.observe(player).companies.first.factories.first.lab!.lines)
          '${content.products[made.product.index].tier.name} '
              '+${made.lead.raw ~/ 100} '
              '(-${made.saving.raw ~/ 100}% materials)',
      ];
      int perYear(int value) => value ~/ years;
      stdout.writeln(
        '${'$seed'.padLeft(4)}  ${withLab ? 'lab   ' : 'no lab'}  '
        '${profits.map((p) => '$p'.padLeft(7)).join(' ').padRight(40)}| '
        '${'${perYear(sales.cents) ~/ 100}'.padLeft(8)}  '
        '${'${perYear(visits)}'.padLeft(9)}  '
        '${'${perYear(lab.cents) ~/ 100}'.padLeft(6)}  '
        '${'$generations'.padLeft(4)}  ${leads.join(', ')}',
      );
    }
  }
}
