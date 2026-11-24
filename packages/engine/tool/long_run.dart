// Plays a game as the app starts one, with the countries, the stock market
// and the cities asleep, a holding with a corner shop under a manager, day
// after day until a date, and says where a day throws if one does.
//
//   dart run tool/long_run.dart [--seed 1] [--until 2053-07-10]
//       [--save path/to/slot1.mgsave] [--out path/to/end.mgsave]
//
// With --save, it carries on that game instead of starting one; with --out,
// it saves there at each new year and where it stopped. Each new year it prints the biggest balance in
// the books, to see how fast sums near the 2^53 the engine keeps them under.
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seed = int.parse(option('--seed', '1'));
  final until = Day.parse(option('--until', '2053-07-10'));
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
  if (args.contains('--save')) {
    final file = SaveFile(File(option('--save', '')).readAsBytesSync());
    final game = Simulation.load(content, file);
    print('loaded ${game.today} (day ${game.today.number})');
    final out = args.contains('--out') ? File(option('--out', '')) : null;
    _play(game, until, out: out);
    out?.writeAsBytesSync(game.save().bytes);
    return;
  }
  final game = Simulation.newGame(
    content,
    seed: seed,
    start: const GameStart.holding('H'),
    citiesAsleep: true,
  );
  final player = game.world.player;
  final view = game.observe(player);
  final grocery = content.formats.firstWhere((f) => f.key == 'grocery');
  final site = [
    for (final id in view.vacantSites) content.sites[id.index],
  ].firstWhere((site) => site.area >= grocery.minArea);
  game.submit(
    OpenStore(
      player,
      site: site.id,
      name: 'Corner',
      format: grocery.id,
      capital: Money.parse('40000.00'),
    ),
  );
  game.step();
  game.submit(
    HireManager(
      player,
      store: game.world.stores.last.id,
      grade: content.managers.grades.last.id,
      strategy: content.strategies.firstWhere((s) => s.key == 'balanced').id,
      duties: List.filled(ManagerDuty.values.length, true),
    ),
  );
  _play(game, until);
}

void _play(Simulation game, Day until, {File? out}) {
  final clock = Stopwatch()..start();
  var year = game.today.date.year;
  while (game.today < until) {
    try {
      game.step();
    } on Object catch (error, stack) {
      print('THREW on ${game.today} after ${clock.elapsed}: $error');
      print(stack);
      exit(1);
    }
    if (game.today.date.year != year) {
      year = game.today.date.year;
      print(
        '$year reached after ${clock.elapsed.inSeconds}s, biggest balance '
        '${_biggest(game)} cents',
      );
      out?.writeAsBytesSync(game.save().bytes);
    }
  }
  print('reached ${game.today} after ${clock.elapsed.inSeconds}s');
}

/// The biggest balance in any company's or person's books.
int _biggest(Simulation game) {
  var most = 0;
  for (final accounts in [
    for (final company in game.world.companies) company.accounts,
    for (final person in game.world.persons) person.accounts,
  ]) {
    for (final kind in AccountKind.values) {
      final cents = accounts[kind].cents.abs();
      if (cents > most) most = cents;
    }
  }
  return most;
}
