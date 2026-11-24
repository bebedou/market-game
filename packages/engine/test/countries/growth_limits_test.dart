// What keeps chains from growing without end: a head office opens so many
// shops a month, the competition authority lets no owner hold more than a
// tenth of a region's shops of a trade, and households grow ever slower.
@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/systems/national.dart' show ownerShops;
import 'package:test/test.dart';

final _euro = File('../../content/countries/euro.json').readAsStringSync();
final _calibration = File(
  '../../content/countries/calibration.json',
).readAsStringSync();

/// The national table, the competition authority's ceiling at [ceiling].
CountryTable _table({String ceiling = '0.10'}) => loadCountryTable(
  _euro.replaceFirst('"ceiling": "0.10"', '"ceiling": "$ceiling"'),
  _calibration,
);

final _json = File('../../content/scenarios/prototype.json').readAsStringSync();

/// The scenario with the national figures and a rich player.
ContentDb _scenario({String ceiling = '0.10'}) => loadScenario(
  _json.replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "50000000.00"',
  ),
  national: _table(ceiling: ceiling),
);

final _content = _scenario();
final _player = _content.player;
const _company = CompanyId(0);
final _france = _content.countries.firstWhere((c) => c.key == 'fr').id;
final _frIndex = _table().countries.indexWhere((c) => c.key == 'fr');
final _grocery = _table().trades.indexWhere((t) => t.key == 'grocery');
final _grocer = _content.strategies.firstWhere((s) => s.key == 'balanced');

DirectorGradeDef _grade(ContentDb content, String key) =>
    content.directors!.grades.firstWhere((g) => g.key == key);

Simulation _game(ContentDb content) {
  final game = Simulation.newGame(content, seed: 1, citiesAsleep: true);
  game.submit(
    InjectCapital(
      _player,
      company: _company,
      amount: Money.parse('30000000.00'),
    ),
  );
  expect(game.step().rejections, isEmpty);
  return game;
}

OpenNational _open({int count = 20, int region = 0}) => OpenNational(
  _player,
  company: _company,
  country: _france,
  region: region,
  format: _grocer.format,
  strategy: _grocer.id,
  count: count,
);

List<String> _apply(Simulation game, List<Command> commands) {
  commands.forEach(game.submit);
  return [for (final r in game.step().rejections) r.reason.key];
}

/// Plays [days], none of them refusing anything.
void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    expect(game.step().rejections, isEmpty);
  }
}

CountryState _fr(Simulation game) => game.national!.countries[_frIndex];

int _shops(Simulation game) => _fr(game).blocks
    .where((b) => b.company == _company.index)
    .fold(0, (sum, b) => sum + b.stores);

void main() {
  test('a head office opens so many shops a month: two under a promoted '
      'manager, five under a seasoned CEO, ten under a star, as their '
      'character paces them', () {
    final directors = _content.directors!;
    int openings(String grade, [String? character]) => directors.openingsOf(
      Director(
        grade: _grade(_content, grade).id,
        strategy: _grocer.id,
        managerGrade: _content.managers.grades.first.id,
        growth: Growth.open,
        payout: false,
        hiredOn: _content.startDay,
        person: character == null
            ? null
            : DirectorPerson(
                name: 'Anne Varenne',
                female: true,
                character: directors.characters.indexWhere(
                  (c) => c.key == character,
                ),
                looks: 0,
              ),
      ),
    )!;
    expect(openings('promoted'), 2);
    expect(openings('seasoned'), 5);
    expect(openings('star'), 10);
    expect(openings('star', 'bold'), 12);
    expect(openings('seasoned', 'cautious'), 4);
    expect(openings('promoted', 'cautious'), 2);
  });

  test('a promoted manager opens two shops a month however big the chain', () {
    final game = _game(_content);
    for (var r = 0; r < 15; r++) {
      expect(_apply(game, [_open(region: r % 5)]), isEmpty);
    }
    _advance(game, 40);
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _grade(_content, 'promoted').id,
        strategy: _grocer.id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        // At their pace, 1.5% a month: four or five a month from 300.
        nationalAuto: true,
      ),
    );
    final before = _shops(game);
    _advance(game, 365);
    // Twelve or thirteen firsts of the month: at most two each.
    final opened = _shops(game) - before;
    expect(opened, greaterThan(12));
    expect(opened, lessThanOrEqualTo(26));
    // Their letters say what held them.
    final held = game.world.companies[_company.index].memos
        .whereType<GrowthHeld>();
    expect(held, isNotEmpty);
    expect(held.every((memo) => memo.paced == 2), isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test("no owner opens past a tenth of a region's shops of a trade", () {
    // A ceiling so low that Corsica's groceries leave room for a few.
    final low = _scenario(ceiling: '0.01');
    final game = _game(low);
    final country = _fr(game);
    final corse = country.def.regions.indexWhere((r) => r.key == 'FRM');
    final room = game.national!.roomIn(country, _grocery, corse, 0);
    expect(room, greaterThan(0));
    expect(room, lessThan(20));
    expect(_apply(game, [_open(count: room + 1, region: corse)]), [
      'regionCeiling',
    ]);
    expect(_apply(game, [_open(count: room, region: corse)]), isEmpty);
    expect(_apply(game, [_open(count: 1, region: corse)]), ['regionCeiling']);
    // Elsewhere there is room still.
    expect(_apply(game, [_open(count: 1, region: 0)]), isEmpty);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a director grows a chain up to the ceiling in each region and no '
      'further, refused nothing', () {
    final low = _scenario(ceiling: '0.001');
    final game = _game(low);
    expect(_apply(game, [_open(count: 10)]), isEmpty);
    _advance(game, 40);
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _grade(low, 'star').id,
        strategy: _grocer.id,
        managerGrade: low.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        nationalAuto: true,
      ),
    );
    _advance(game, 365);
    final country = _fr(game);
    final ceiling = Fx.parse('0.001');
    var full = 0;
    for (var r = 0; r < country.regionCount; r++) {
      var held = 0;
      for (final block in country.blocks) {
        if (block.company == _company.index && block.trade == _grocery) {
          held += block.regions[r].stores;
        }
      }
      final all = CountryEconomy.shopsIn(country, _grocery, r);
      // Within the ceiling, as far as a whole shop goes.
      expect(
        held * Fx.scale <= all * ceiling.raw + Fx.scale,
        isTrue,
        reason: country.def.regions[r].key,
      );
      if (game.national!.roomIn(country, _grocery, r, held) == 0) full++;
    }
    expect(full, greaterThan(0));
    expect(
      game.world.companies[_company.index].memos.whereType<GrowthHeld>().any(
        (memo) => memo.full > 0,
      ),
      isTrue,
    );
    expect(invariantViolations(game.world), isEmpty);
  });

  test('shops in districts count toward the ceiling, and none opens there '
      'past it', () {
    final low = _scenario(ceiling: '0.002');
    final game = _game(low);
    final economy = game.national!;
    final country = _fr(game);
    final frk = country.def.regions.indexWhere((r) => r.key == 'FRK');
    // The shop in Lyon.
    final held = ownerShops(
      game.world,
      game.content,
      economy,
      _frIndex,
      _player,
      _grocery,
      region: frk,
    );
    expect(held, 1);
    var room = economy.roomIn(country, _grocery, frk, held);
    expect(room, greaterThan(0));
    expect(room, lessThan(60));
    while (room > 0) {
      final count = room < 20 ? room : 20;
      expect(_apply(game, [_open(count: count, region: frk)]), isEmpty);
      room -= count;
    }
    expect(_apply(game, [_open(count: 1, region: frk)]), ['regionCeiling']);
    final content = game.content;
    final format = content.formats[_grocer.format.index];
    final site = content.sites.firstWhere(
      (site) =>
          content.markets[site.market.index].region == 'FRK' &&
          game.world.storeAt(site.id) == null &&
          site.openingArea(format) != null,
    );
    expect(
      _apply(game, [
        OpenStore(
          _player,
          site: site.id,
          name: 'One Too Many',
          company: _company,
          format: _grocer.format,
        ),
      ]),
      ['regionCeiling'],
    );
  });

  test('no chain buys shops that would take it past the ceiling', () {
    final low = _scenario(ceiling: '0.001');
    final game = _game(low);
    expect(_apply(game, [_open(count: 12)]), isEmpty);
    _advance(game, 120);
    final country = _fr(game);
    final block = country.blocks.firstWhere((b) => b.company == 0);
    expect(
      _apply(game, [
        SellNational(
          _player,
          company: _company,
          country: _france,
          block: country.blocks.indexOf(block),
        ),
      ]),
      ['noChainBuyer'],
    );
  });

  test("what a chain's own plants save it opens it no shops", () {
    CountryEconomy run({required bool plants}) {
      final economy = CountryEconomy(_table(), seed: 7);
      for (var month = 0; month < 36; month++) {
        if (plants) {
          for (final country in economy.countries) {
            for (final chain in country.chains) {
              if (!chain.def.independent) chain.ownSaving = Fx.parse('0.05');
            }
          }
        }
        economy.advanceMonth();
      }
      return economy;
    }

    final without = run(plants: false);
    final with_ = run(plants: true);
    for (final (n, country) in with_.countries.indexed) {
      for (final (c, chain) in country.chains.indexed) {
        expect(
          chain.stores,
          without.countries[n].chains[c].stores,
          reason: chain.def.name,
        );
        // It keeps what they save.
        if (!chain.def.independent && chain.isTrading) {
          expect(chain.cash > without.countries[n].chains[c].cash, isTrue);
        }
      }
    }
  });

  test('a chain is not sold to an owner it would take past the ceiling', () {
    final low = _scenario(ceiling: '0.001');
    final game = _game(low);
    _advance(game, 40);
    final country = _fr(game);
    final chain = country.chains.firstWhere(
      (c) => c.def.trade == _grocery && !c.def.independent,
    );
    expect(
      _apply(game, [
        BuyNationalChain(
          _player,
          company: _company,
          country: _france,
          chain: country.chains.indexOf(chain),
          format: _grocer.format,
          strategy: _grocer.id,
        ),
      ]),
      ['nationalCeiling'],
    );
    expect(chain.boughtBy, isNull);
  });

  test("a chain opens at most the table's few shops a month, and none in a "
      'region past the ceiling', () {
    final table = _table();
    final economy = CountryEconomy(table, seed: 3);
    final low = CountryEconomy(_table(ceiling: '0.01'), seed: 3);
    final before = [
      for (final chain in low.countries[_frIndex].chains) [...chain.regional],
    ];
    for (var month = 0; month < 36; month++) {
      economy.advanceMonth();
      low.advanceMonth();
    }
    var opened = 0;
    for (final country in economy.countries) {
      for (final chain in country.chains) {
        if (chain.def.independent) continue;
        for (final month in chain.months) {
          expect(month.opened, lessThanOrEqualTo(table.chainOpenings));
          opened += month.opened;
        }
      }
    }
    expect(opened, greaterThan(0));
    // At a hundredth, every chain starts past it in every region it is in,
    // and opens in none of them.
    final france = low.countries[_frIndex];
    for (final (i, chain) in france.chains.indexed) {
      if (chain.def.independent) continue;
      for (var r = 0; r < france.regionCount; r++) {
        if (low.roomIn(france, chain.def.trade, r, before[i][r]) > 0) {
          continue;
        }
        expect(
          chain.regional[r],
          lessThanOrEqualTo(before[i][r]),
          reason: '${chain.def.name} ${france.def.regions[r].key}',
        );
      }
    }
  });

  test("households grow half as fast after twenty years", () {
    final economy = CountryEconomy(_table(), seed: 5);
    final years = <int>[economy.countries[_frIndex].totalHouseholds];
    for (var month = 0; month < 12 * 21; month++) {
      economy.advanceMonth();
      if (month % 12 == 11) {
        years.add(economy.countries[_frIndex].totalHouseholds);
      }
    }
    final first = years[1] - years[0];
    final later = years[21] - years[20];
    // France's 1.09% at the start, by 2046 about half that.
    expect(first, closeTo(years[0] * 0.0109, years[0] * 0.0002));
    expect(later / years[20], closeTo(0.0109 / 2, 0.0004));
  });
}
