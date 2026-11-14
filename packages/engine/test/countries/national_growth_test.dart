@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _table = loadCountryTable(
  File('../../content/countries/euro.json').readAsStringSync(),
  File('../../content/countries/calibration.json').readAsStringSync(),
);

final _json = File('../../content/scenarios/prototype.json').readAsStringSync();

/// The scenario with the national figures, its player rich, and critical
/// mass at [critical] of a trade.
ContentDb _scenario({String critical = '0.05'}) => loadScenario(
  _json
      .replaceFirst(
        '"name": "You", "cash": "20000.00"',
        '"name": "You", "cash": "5000000.00"',
      )
      .replaceFirst('"criticalShare": "0.05"', '"criticalShare": "$critical"'),
  national: _table,
);

final _content = _scenario();
final _player = _content.player;
const _company = CompanyId(0);
final _france = _content.countries.firstWhere((c) => c.key == 'fr').id;
final _grocer = _content.strategies.firstWhere((s) => s.key == 'balanced');

DirectorGradeDef _grade(String key) =>
    _content.directors!.grades.firstWhere((g) => g.key == key);

Simulation _game(ContentDb content) {
  final game = Simulation.newGame(content, seed: 1, citiesAsleep: true);
  game.submit(
    InjectCapital(
      _player,
      company: _company,
      amount: Money.parse('3000000.00'),
    ),
  );
  expect(game.step().rejections, isEmpty);
  return game;
}

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

/// The number of shops [rate] would open in France this month for [game]'s
/// company, as its director's brief would have it.
int _budget(Simulation game, ContentDb content, Fx rate) {
  final view = game.observe(_player);
  final france = view.national.firstWhere((n) => n.country == _france);
  return nationalBudget(
    view,
    content,
    view.companies.first,
    france,
    france.tradeOf(content, _grocer.format)!,
    rate,
  );
}

/// Opens 100 French grocers for [game]'s company and lets them trade.
void _hundred(Simulation game) {
  for (var r = 0; r < 5; r++) {
    game.submit(
      OpenNational(
        _player,
        company: _company,
        country: _france,
        region: r,
        format: _grocer.format,
        strategy: _grocer.id,
        count: 20,
      ),
    );
  }
  expect(game.step().rejections, isEmpty);
  _advance(game, 40);
}

void main() {
  test('each grade grows a chain as fast as it runs well', () {
    expect(_grade('promoted').growth, Fx.parse('0.015'));
    expect(_grade('seasoned').growth, Fx.parse('0.035'));
    expect(_grade('star').growth, Fx.parse('0.06'));
  });

  test("a month's openings are a share of the chain's shops, at least one", () {
    final game = _game(_content);
    // One shop in Lyon: still one a month; none at no rate.
    expect(_budget(game, _content, Fx.parse('0.06')), 1);
    expect(_budget(game, _content, Fx.zero), 0);
    _hundred(game);
    // A hundred and one shops at 6% a month, far from critical mass.
    expect(_budget(game, _content, Fx.parse('0.06')), 6);
  });

  test('growth slows as the chain nears critical mass in its trade', () {
    final tiny = _scenario(critical: '0.0001');
    final game = _game(tiny);
    _hundred(game);
    // Its hundred shops are already well past so small a share.
    expect(_budget(game, tiny, Fx.parse('0.06')), lessThan(4));
  });

  test('a star compounds faster than a promoted manager', () {
    int grown(String grade) {
      final game = _game(_content);
      // From a hundred shops, where the rates tell.
      _hundred(game);
      game.submit(
        HireDirector(
          _player,
          company: _company,
          grade: _grade(grade).id,
          strategy: _grocer.id,
          managerGrade: _content.managers.grades.last.id,
          growth: Growth.open,
          payout: false,
          nationalAuto: true,
        ),
      );
      _advance(game, 365);
      expect(invariantViolations(game.world), isEmpty);
      var shops = 0;
      for (final country in game.national!.countries) {
        for (final block in country.blocks) {
          if (block.company == 0) shops += block.stores;
        }
      }
      return shops;
    }

    final star = grown('star');
    final promoted = grown('promoted');
    // About a hundred more in a year against a score.
    expect(star - 100, greaterThan((promoted - 100) * 2));
    expect(promoted, greaterThan(100));
  });

  test("pushed past their pace, a director's shops are run worse", () {
    final game = _game(_content);
    _hundred(game);
    HireDirector hire({bool auto = false}) => HireDirector(
      _player,
      company: _company,
      grade: _grade('promoted').id,
      strategy: _grocer.id,
      managerGrade: _content.managers.grades.last.id,
      growth: Growth.open,
      payout: false,
      nationalRate: auto ? Fx.zero : Fx.parse('0.06'),
      nationalAuto: auto,
    );
    game.submit(hire());
    _advance(game, 40);
    final france = _table.countries.indexWhere((c) => c.key == 'fr');
    final block = game.national!.countries[france].blocks.single;
    // Four times their pace: three times over.
    expect(block.strain, Fx.parse('3'));
    expect(strainFactor(block.strain) < Fx.parse('0.40'), isTrue);
    game.submit(hire(auto: true));
    _advance(game, 40);
    expect(block.strain, Fx.zero);
    expect(strainFactor(block.strain), Fx.one);
  });

  test('a brief to grow at a rate is saved and read', () {
    final game = _game(_content);
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _grade('seasoned').id,
        strategy: _grocer.id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        nationalRate: Fx.parse('0.04'),
      ),
    );
    _advance(game, 3);
    final loaded = Simulation.load(_content, game.save());
    final director = loaded.world.companies[0].director!;
    expect(director.nationalRate, Fx.parse('0.04'));
    expect(director.nationalAuto, isFalse);
    expect(loaded.stateHash(), game.stateHash());
  });
}
