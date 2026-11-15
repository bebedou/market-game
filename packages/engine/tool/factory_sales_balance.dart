// How a factory sells to other companies: a holding start that builds one
// factory of the size and kind asked for in France, runs it on three
// shifts, sells to independent shops at a discount and bids on every tender
// for its goods at a discount on the producer price, played for some years
// over several seeds. Prints, per seed and year, the tenders it bid on,
// won and lost, what its contracts take a month, how much of its capacity
// it used, its profit, sales to others, penalties, its reliability and its
// share of independents; then the rival producers' discounts at the end.
//
//   dart run tool/factory_sales_balance.dart [--seeds 1-3] [--years 4]
//       [--kind drinks] [--size 1] [--bid 0.05] [--discount 0.10]
//       [--serve fr,de]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final years = int.parse(option('--years', '4'));
  final kindKey = option('--kind', 'drinks');
  final size = int.parse(option('--size', '1'));
  final bid = Fx.parse(option('--bid', '0.05'));
  final discount = Fx.parse(option('--discount', '0.10'));
  final serve = option('--serve', 'fr').split(',');
  final root = Platform.script.resolve('../../../content/');
  String read(String path) =>
      File(root.resolve(path).toFilePath()).readAsStringSync();
  final content = loadScenario(
    read('scenarios/prototype.json').replaceFirst(
      '"name": "You", "cash": "20000.00"',
      '"name": "You", "cash": "50000000.00"',
    ),
    national: loadCountryTable(
      read('countries/euro.json'),
      read('countries/calibration.json'),
    ),
  );
  final factories = content.factories!;
  final kind = factories.kinds.firstWhere((k) => k.key == kindKey);
  final france = content.countries.firstWhere((c) => c.key == 'fr').id;
  final serves = [
    for (final country in content.countries) serve.contains(country.key),
  ];
  stdout.writeln(
    '${kind.name}, ${factories.sizes[size].name}, 3 shifts, serving '
    '${serve.join('+')}; bids ${bid.toDecimalString()} under the producer '
    'price, independents at ${discount.toDecimalString()} off',
  );
  for (var seed = seeds.first; seed <= seeds.last; seed++) {
    final game = Simulation.newGame(
      content,
      seed: seed,
      start: const GameStart.holding('Holding'),
      citiesAsleep: true,
    );
    final player = game.world.player;
    final cost = factories.sized(kind.id, size).buildCost;
    game.submit(
      BuildFactory(
        player,
        kind: kind.id,
        country: france,
        name: 'Usine',
        capital: cost + cost,
        shifts: 3,
        serves: serves,
        size: size,
      ),
    );
    game.step();
    final factory = game.world.factories.single;
    game.submit(
      SetFactoryTerms(
        player,
        factory: factory.id,
        serves: serves,
        rivalDiscount: discount,
      ),
    );
    if (seed == seeds.first) {
      final view = game
          .observe(player)
          .companies
          .expand((c) => c.factories)
          .single;
      for (final line in view.sales!.lines) {
        stdout.writeln(
          '  ${content.products[line.product.index].name}: wholesale '
          '${line.wholesale.toDecimalString()}, producer price '
          '${line.producerPrice.toDecimalString()}, cost at full use '
          '${line.unitCost.toDecimalString()}',
        );
      }
    }
    var bids = 0;
    final bidOn = <int>{};
    final rows = <String>[];
    for (var day = 0; day < years * 365; day++) {
      final capacity =
          factories.sized(kind.id, factory.size).shiftUnits * 3 * 30;
      var committed = game.world.contracts
          .where((c) => !c.ended && game.today < c.ends)
          .fold(0, (sum, c) => sum + c.units);
      for (final tender in game.world.tenders) {
        if (tender.status == TenderStatus.open && tender.bidFactory != null) {
          committed += tender.units;
        }
      }
      for (final tender in game.world.tenders) {
        if (tender.status != TenderStatus.open ||
            !bidOn.add(tender.number) ||
            committed + tender.units > capacity ||
            tender.floor > Fx.zero) {
          continue;
        }
        committed += tender.units;
        bids++;
        game.submit(
          BidTender(
            player,
            tender: tender.number,
            factory: factory.id,
            price: tender.reference.times(Fx.one - bid),
          ),
        );
      }
      // Shifts for what contracts and independents take, at least one.
      if (game.today.isFirstOfMonth) {
        final perShift = factories.sized(kind.id, factory.size).shiftUnits * 30;
        final independents =
            factory.recentRivalUnits(game.today) -
            game.world.contracts
                .where((c) => c.factory == factory.id && c.runsOn(game.today))
                .fold(0, (sum, c) => sum + c.units);
        final wanted = committed + (independents > 0 ? independents : 0);
        var shifts = (wanted + perShift - 1) ~/ perShift;
        if (shifts < 1) shifts = 1;
        if (shifts > 3) shifts = 3;
        if (shifts != factory.shifts) {
          game.submit(
            SetFactoryShifts(player, factory: factory.id, shifts: shifts),
          );
        }
      }
      // Chains' requests for a cut are taken.
      for (final contract in game.world.contracts) {
        if (contract.proposal != null && contract.factory == factory.id) {
          game.submit(
            AnswerContract(player, contract: contract.number, accept: true),
          );
        }
      }
      final result = game.step();
      for (final rejection in result.rejections) {
        if (rejection.command is BidTender) continue;
        stdout.writeln(
          '  refused: ${rejection.command} ${rejection.reason.key}',
        );
      }
      if ((day + 1) % 365 == 0) {
        final year = (day + 1) ~/ 365;
        final months = game
            .reports(factory.company, ReportPeriod.month)
            .where((r) => r.complete)
            .toList();
        final last = months.length > 12
            ? months.sublist(months.length - 12)
            : months;
        var profit = Money.zero;
        var others = Money.zero;
        var penalties = Money.zero;
        var made = 0;
        for (final month in last) {
          final part = month.factory(factory.id);
          if (part == null) continue;
          profit += part.profit;
          others += part.totalRivalSales;
          penalties += part.penalties;
          made += part.made;
        }
        final capacity =
            factories.sized(kind.id, factory.size).shiftUnits * 3 * 365;
        // Use against three shifts all year.
        final won = game.world.tenders
            .where((t) => t.status == TenderStatus.won)
            .length;
        final lost = game.world.tenders
            .where((t) => t.status == TenderStatus.lost && t.bidFactory != null)
            .length;
        final committed = game.world.contracts
            .where((c) => c.runsOn(game.today))
            .fold(0, (sum, c) => sum + c.units);
        rows.add(
          '  y$year: bids $bids won $won lost $lost, contracts '
          '${committed ~/ 1000}k/month, use '
          '${(100 * made / capacity).toStringAsFixed(0)}%, profit '
          '${_k(profit)}, to others ${_k(others)}, penalties '
          '${_k(penalties)}, reliability '
          '${factory.reliability.toDecimalString()}, independents '
          '${(factory.independentShare / 10000).toStringAsFixed(3)}%',
        );
      }
    }
    stdout.writeln('seed $seed, built for ${_k(factory.builtFor)}');
    rows.forEach(stdout.writeln);
    for (final producer in game.world.producers) {
      if (producer.kind != kind.id ||
          !serve.contains(content.countries[producer.country.index].key)) {
        continue;
      }
      stdout.writeln(
        '    ${producer.name.padRight(24)} discount '
        '${producer.discount.toDecimalString()} lead '
        '${producer.lead.toDecimalString()} won ${producer.won} free '
        '${_k(producer.freeOn(game.today))} of ${_k(producer.capacity)}',
      );
    }
  }
}

String _k(Money money) {
  final value = money.cents / 100;
  if (value.abs() >= 1e6) return '${(value / 1e6).toStringAsFixed(2)}m';
  return '${(value / 1e3).toStringAsFixed(0)}k';
}
