// How a software company fares: a holding start that founds one, hires a
// team of the kind asked for, raises a round whenever its cash runs short
// and markets from its first version, played for some years over several
// seeds. Prints, per seed, the months to launch, and each year's
// customers, revenue, profit, lead, worth and the owner's stake; then the
// rivals at the end.
//
//   dart run tool/software_balance.dart [--seeds 1-3] [--years 6]
//       [--team star|strong|middle|ordinary|big] [--rivals] [--price 1.0]
//
// With --price, its price is kept at that multiple of the market's usual
// price, set on the first of each month.
//
// The team is picked by people's true levels, as a player with a perfect
// eye would: star is one level-4 engineer and two level-2s, strong a
// level-3 engineer, a level-3 designer and a level-2, middle three
// level-2s, ordinary four level-1s, big ten of level 1 or 2.
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/talent.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '6'));
  final team = option('--team', 'star');
  final priced = args.contains('--price')
      ? Fx.parse(option('--price', '1.0'))
      : null;
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      root.resolve('scenarios/prototype.json').toFilePath(),
    ).readAsStringSync(),
  );
  // Who to hire: levels wanted, engineers first.
  final wanted = switch (team) {
    'star' => [(4, KeyRole.engineer), (2, null), (2, null)],
    'strong' => [(3, KeyRole.engineer), (3, KeyRole.designer), (2, null)],
    'middle' => [(2, null), (2, null), (2, null)],
    'ordinary' => [(1, null), (1, null), (1, null), (1, null)],
    'big' => [for (var i = 0; i < 10; i++) (i.isEven ? 1 : 2, null)],
    _ => throw ArgumentError('unknown team $team'),
  };
  stdout.writeln('Team: $team, $years years');
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(
      content,
      seed: seed,
      start: const GameStart.holding('Holding'),
      citiesAsleep: true,
    );
    final player = game.world.player;
    final cash = game.observe(player).cash;
    game.submit(
      StartSoftware(
        player,
        name: 'Tessel',
        country: content.countries.first.id,
        capital: cash,
      ),
    );
    game.step();
    final software = game.world.software.single;
    final left = [...wanted];
    var marketing = false;
    int? launchMonth;
    final rows = <String>[];
    for (var day = 0; day < years * 365; day++) {
      final world = game.world;
      // Hire whoever fits the next opening, at their true level.
      if (left.isNotEmpty) {
        for (final person in world.keyPeople) {
          if (left.isEmpty) break;
          if (!person.forSoftware || person.status != KeyStatus.candidate) {
            continue;
          }
          final slot = left.indexWhere(
            (want) =>
                want.$1 == person.level &&
                (want.$2 == null || want.$2 == person.role),
          );
          if (slot < 0) continue;
          left.removeAt(slot);
          game.submit(
            HireSoftwarePerson(
              player,
              software: software.id,
              person: person.id,
            ),
          );
        }
      }
      final view = game
          .observe(player)
          .companies
          .firstWhere((c) => c.id == software.company)
          .software!;
      final companyCash = game
          .observe(player)
          .companies
          .firstWhere((c) => c.id == software.company)
          .cash;
      // A round when less than half a year of cash is left.
      final burn = -view.monthProfit.cents;
      if (view.running &&
          burn > 0 &&
          companyCash.cents < burn * 6 &&
          !view.nextRound.number.isNegative &&
          view.nextRound.number <= game.today.number) {
        game.submit(
          RaiseRound(player, software: software.id, share: Fx.parse('0.25')),
        );
      }
      // From the first version, marketing at a third of revenue, at least
      // 6,000 a month.
      if (view.status == SoftwareStatus.selling &&
          (!marketing || game.today.isFirstOfMonth)) {
        marketing = true;
        launchMonth ??= (game.today.number - software.founded.number) ~/ 30;
        final third = view.revenue.times(Fx.parse('0.33'));
        final floor = Money.parse('6000.00');
        game.submit(
          SetSoftwareMarketing(
            player,
            software: software.id,
            budget: third > floor ? third : floor,
          ),
        );
      }
      if (priced != null && view.running && game.today.isFirstOfMonth) {
        game.submit(
          SetSoftwarePrice(
            player,
            software: software.id,
            price: view.referencePrice.times(priced),
          ),
        );
      }
      final result = game.step();
      for (final rejection in result.rejections) {
        if (rejection.command is PayDividend) continue;
        stdout.writeln(
          '  refused: ${rejection.command} ${rejection.reason.key}',
        );
      }
      if ((day + 1) % 365 == 0) {
        final company = game
            .observe(player)
            .companies
            .firstWhere((c) => c.id == software.company);
        final s = company.software!;
        final reports = game.reports(company.id, ReportPeriod.month);
        final year = reports.length > 12
            ? reports.sublist(reports.length - 13, reports.length - 1)
            : reports;
        final revenue = year.fold(
          Money.zero,
          (sum, r) => sum - r.flow(AccountKind.revenue),
        );
        final profit = year.fold(Money.zero, (sum, r) => sum + r.profit);
        rows.add(
          '  y${(day + 1) ~/ 365}: ${s.status.name.padRight(8)} '
          'customers ${s.customers.toString().padLeft(10)} '
          'revenue ${_k(revenue).padLeft(9)} '
          'profit ${_k(profit).padLeft(9)} '
          'lead ${(s.lead.raw / 100).toStringAsFixed(1).padLeft(5)} '
          'growth ${(s.growth.raw / 100).toStringAsFixed(0).padLeft(5)}% '
          'worth ${_k(s.worth.worth).padLeft(9)} '
          'stake ${(s.stake.raw / 100).toStringAsFixed(0)}% '
          'cash ${_k(company.cash)} '
          'offer ${s.offer == null ? '-' : _k(s.offer!.price)}',
        );
        if (!s.running) break;
      }
    }
    stdout.writeln(
      'seed $seed: launched after ${launchMonth ?? '-'} months, '
      '${software.rounds.length} rounds',
    );
    rows.forEach(stdout.writeln);
    if (args.contains('--rivals')) {
      final market = game.observe(player).softwareMarket!;
      for (final rival in market.rivals) {
        if (rival.customers == 0 && rival.startup) continue;
        stdout.writeln(
          '    ${rival.name.padRight(16)} ${rival.status.name.padRight(8)} '
          '${(rival.share.raw / 100).toStringAsFixed(2).padLeft(6)}% '
          'lead ${(rival.lead.raw / 100).toStringAsFixed(1)}',
        );
      }
    }
  }
}

String _k(Money money) {
  final value = money.cents / 100;
  if (value.abs() >= 1e9) return '${(value / 1e9).toStringAsFixed(2)}bn';
  if (value.abs() >= 1e6) return '${(value / 1e6).toStringAsFixed(2)}m';
  return '${(value / 1e3).toStringAsFixed(0)}k';
}
