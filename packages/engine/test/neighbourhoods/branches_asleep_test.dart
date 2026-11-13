@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/districts.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _scenario = File(
  '../../content/scenarios/prototype.json',
).readAsStringSync();

/// Today's game with a big district run by formula beside it, and a player
/// rich enough to grow.
final ContentDb _content = () {
  final root =
      jsonDecode(
            _scenario.replaceFirst(
              '"name": "You", "cash": "20000.00"',
              '"name": "You", "cash": "500000.00"',
            ),
          )
          as Map<String, dynamic>;
  root['neighbourhoods'] = [
    {
      'id': 'partdieu',
      'name': 'Lyon, Part-Dieu',
      'households': {
        'families': 900,
        'professionals': 2100,
        'students': 750,
        'retirees': 600,
        'singles': 2700,
        'comfortable': 750,
      },
      'priceLevel': '1.02',
      'wageLevel': '1.02',
      'incomeLevel': '1.05',
      'rent': '8.00',
      'typicalArea': 125,
      'largestArea': 180,
      'room': 90,
    },
  ];
  return loadScenario(jsonEncode(root));
}();

final _player = _content.player;
const _company = CompanyId(0);
final _grocer = _content.strategies.firstWhere((s) => s.key == 'balanced');

List<String> _apply(Simulation game, List<Command> commands) {
  commands.forEach(game.submit);
  return [for (final r in game.step().rejections) r.reason.key];
}

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

HireDirector _hire({Growth growth = Growth.open, bool borrows = false}) =>
    HireDirector(
      _player,
      company: _company,
      grade: _content.directors!.grades.last.id,
      strategy: _grocer.id,
      managerGrade: _content.managers.grades.last.id,
      growth: growth,
      payout: false,
      borrows: borrows,
    );

/// A free site of the district a convenience store fits on.
int _freeSite(Simulation game) {
  final sleeper = game.world.sleepers.single;
  final taken = {for (final shop in sleeper.shops) shop.site};
  return sitesOf(game.world, _content, sleeper)
      .firstWhere(
        (site) =>
            !taken.contains(site.number) &&
            site.area >= _content.formats[_grocer.format.index].minArea,
      )
      .number;
}

OpenInDistrict _openThere(Simulation game) => OpenInDistrict(
  _player,
  row: 0,
  site: _freeSite(game),
  company: _company,
  format: _grocer.format,
);

/// A game whose player's company, run by a director, has a shop in the
/// district run by formula.
Simulation _withBranch() {
  final game = Simulation.newGame(_content, seed: 3);
  expect(
    _apply(game, [
      InjectCapital(_player, company: _company, amount: Money.parse('100000')),
      _hire(),
    ]),
    isEmpty,
  );
  expect(_apply(game, [_openThere(game)]), isEmpty);
  return game;
}

void main() {
  test("the player's shop wakes a district, unless a director opens it for "
      'their company', () {
    final game = Simulation.newGame(_content, seed: 3);
    expect(_apply(game, [_openThere(game)]), ['wakeToOpen']);
    expect(
      _apply(game, [
        InjectCapital(
          _player,
          company: _company,
          amount: Money.parse('100000'),
        ),
        _hire(),
      ]),
      isEmpty,
    );
    final spent = game.world.companies[0].accounts[AccountKind.openingCosts];
    expect(_apply(game, [_openThere(game)]), isEmpty);
    final shop = game.world.sleepers.single.shops.last;
    expect(shop.company, _company);
    // Run as the director's strategy has it, under the company's brand.
    expect(shop.strategy, _grocer.id);
    expect(shop.brand, isNotNull);
    expect(
      game.world.companies[0].accounts[AccountKind.openingCosts] > spent,
      isTrue,
    );
    expect(invariantViolations(game.world), isEmpty);
  });

  test("its shop there trades in the company's books, and waking the "
      "district puts it in the player's hands", () {
    final game = _withBranch();
    _advance(game, 70);
    final shop = game.world.sleepers.single.shops.last;
    expect(shop.sales, isNotEmpty);
    final year = game.world.districtYears.firstWhere(
      (entry) => entry.company == _company,
    );
    expect(
      year.sales,
      shop.sales.fold(Money.zero, (sum, month) => sum + month),
    );
    game.submit(WakeNeighbourhood(_player, row: 0));
    expect(game.world.sleepers, isEmpty);
    final store = game.world.stores.firstWhere((s) => s.name == shop.name);
    expect(store.company, _company);
    _advance(game, 20);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a director buys a shop there for their company, not without one', () {
    final game = Simulation.newGame(_content, seed: 3);
    final target = game.world.sleepers.single.shops.firstWhere(
      (shop) => shop.format == _grocer.format,
    );
    BuyInDistrict buy() =>
        BuyInDistrict(_player, row: 0, site: target.site, company: _company);
    expect(
      _apply(game, [
        InjectCapital(
          _player,
          company: _company,
          amount: Money.parse('200000'),
        ),
        buy(),
      ]),
      ['wakeToOpen'],
    );
    expect(_apply(game, [_hire(growth: Growth.buy), buy()]), isEmpty);
    expect(target.company, _company);
  });

  test('a director weighs districts run by formula with those played in '
      'full, and writes of what they open', () {
    final game = Simulation.newGame(_content, seed: 3);
    expect(
      _apply(game, [
        InjectCapital(
          _player,
          company: _company,
          amount: Money.parse('200000'),
        ),
        _hire(),
      ]),
      isEmpty,
    );
    // The strategy's interval after the company's start.
    _advance(game, _grocer.expansionIntervalDays + 40);
    final memos = game.observe(_player).companies.first.memos;
    final opened = memos.whereType<DistrictOpened>().toList();
    expect(opened, isNotEmpty, reason: '$memos');
    final memo = opened.first;
    expect(memo.row, 0);
    expect(
      memo.paybackMonths,
      lessThanOrEqualTo(_grocer.expansionPaybackMonths),
    );
    final shop = game.world.sleepers.single.shops.firstWhere(
      (shop) => shop.site == memo.site,
    );
    expect(shop.company, _company);
    // Then it waits the strategy's interval again, its shops there counted.
    expect(opened, hasLength(1));
    expect(invariantViolations(game.world), isEmpty);
  });

  test('saves, loads and replays the same', () {
    final game = _withBranch();
    _advance(game, 40);
    final file = game.save();
    final loaded = Simulation.load(_content, file);
    expect(loaded.stateHash(), game.stateHash());
    expect(Simulation.replay(_content, file).stateHash(), game.stateHash());
    _advance(game, 20);
    _advance(loaded, 20);
    expect(loaded.stateHash(), game.stateHash());
  });
}
