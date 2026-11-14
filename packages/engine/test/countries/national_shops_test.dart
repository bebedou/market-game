@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/taxation.dart';
import 'package:test/test.dart';

final _table = loadCountryTable(
  File('../../content/countries/euro.json').readAsStringSync(),
  File('../../content/countries/calibration.json').readAsStringSync(),
);

final _json = File('../../content/scenarios/prototype.json').readAsStringSync();

/// The scenario with the national figures by region, its player rich enough
/// to open shops across a country.
final _content = loadScenario(
  _json.replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "3000000.00"',
  ),
  national: _table,
);

final _player = _content.player;
const _company = CompanyId(0);
final _france = _content.countries.firstWhere((c) => c.key == 'fr').id;
final _grocer = _content.strategies.firstWhere((s) => s.key == 'balanced');

/// France's index in the national table.
final _frIndex = _table.countries.indexWhere((c) => c.key == 'fr');

/// Hauts-de-France's index among France's regions.
const _north = 0;

/// Île-de-France's.
final _paris = _table.countries[_frIndex].regions.indexWhere(
  (r) => r.key == 'FR1',
);

Simulation _game({int seed = 1}) {
  final game = Simulation.newGame(_content, seed: seed, citiesAsleep: true);
  game.submit(
    InjectCapital(_player, company: _company, amount: Money.parse('500000.00')),
  );
  expect(game.step().rejections, isEmpty);
  return game;
}

OpenNational _open({int count = 3, int region = _north}) => OpenNational(
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

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

/// Steps [game] through the first of next month, when the countries by
/// formula move on a month.
void _toNextMonth(Simulation game) {
  final month = game.today.date.month;
  while (game.today.date.month == month) {
    game.step();
  }
  game.step();
}

CompanyBlock? _block(Simulation game) => game
    .national!
    .countries[_frIndex]
    .blocks
    .where((block) => block.company == _company.index)
    .firstOrNull;

void main() {
  test('opens shops run by formula, which trade from the next month and '
      'keep books in the company', () {
    final game = _game();
    final twin = _game();
    final cash = game.world.companies[0].accounts[AccountKind.cash];
    expect(_apply(game, [_open()]), isEmpty);
    twin.step();
    // Fitting out at the country's prices and the region's costs.
    final economy = game.national!.countries[_frIndex];
    final grocery = game.national!.table.trades.indexWhere(
      (t) => t.key == 'grocery',
    );
    final cost = _content.formats[_grocer.format.index].national!.fitOut
        .times(economy.priceIndex)
        .times(economy.costLevels[grocery][_north])
        .timesInt(3);
    final company = game.world.companies[0];
    final other = twin.world.companies[0];
    expect(
      company.accounts[AccountKind.openingCosts] -
          other.accounts[AccountKind.openingCosts],
      cost,
    );
    expect(company.accounts[AccountKind.cash] < cash, isTrue);
    expect(_block(game)!.regions[_north].pending, 3);
    expect(_block(game)!.trading, 0);

    _toNextMonth(game);
    _toNextMonth(twin);
    final block = _block(game)!;
    expect(block.regions[_north].trading, 3);
    expect(block.regions[_north].pending, 0);
    // Four months of trading, each worked out and booked in the company
    // once, on its first day.
    for (var i = 0; i < 3; i++) {
      _toNextMonth(game);
      _toNextMonth(twin);
    }
    final months = block.months.where((month) => month.stores > 0).toList();
    expect(months, hasLength(4));
    Money sum(Money Function(BlockMonth) of) =>
        months.fold(Money.zero, (total, month) => total + of(month));
    Money more(AccountKind kind) =>
        company.accounts[kind] - other.accounts[kind];
    // Revenue and costs are credit and debit balances: compare their sizes.
    expect(Money(more(AccountKind.revenue).cents.abs()), sum((m) => m.sales));
    expect(
      Money(more(AccountKind.costOfGoods).cents.abs()),
      sum((m) => m.goods),
    );
    expect(
      Money(more(AccountKind.marketing).cents.abs()),
      sum((m) => m.marketing),
    );
    expect(Money(more(AccountKind.wages).cents.abs()), sum((m) => m.staff));
    expect(Money(more(AccountKind.rent).cents.abs()), sum((m) => m.premises));
    expect(sum((m) => m.profit) > Money.zero, isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test("taxes what they make in their country's year", () {
    final game = _game();
    final twin = _game();
    expect(_apply(game, [_open()]), isEmpty);
    twin.step();
    final year = game.today.date.year;
    while (game.today.date.year == year) {
      game.step();
      twin.step();
    }
    int profitIn(Simulation sim) => sim.world.districtYears
        .where(
          (entry) =>
              entry.company == _company &&
              entry.country == _france &&
              entry.year == year,
        )
        .fold(0, (sum, entry) => sum + entry.profit.cents);
    final made = _block(game)!.months
        .where((month) => month.start.date.year == year)
        .fold(0, (sum, month) => sum + month.profit.cents);
    expect(made, isNot(0));
    expect(profitIn(game) - profitIn(twin), made);
    final dues = companyTaxes(
      game.world,
      game.content,
      game.world.companies[0],
      year,
    );
    expect(dues.map((due) => due.country), contains(_france));
  });

  test('are refused where they cannot be placed or paid for', () {
    final game = _game();
    expect(
      _apply(game, [
        _open(region: 99),
        _open(count: 0),
        _open(count: maxNationalOpenings + 1),
        // Île-de-France costs the most to fit out.
        _open(count: maxNationalOpenings, region: _paris),
        OpenNational(
          game.world.persons.last.id,
          company: _company,
          country: _france,
          region: _north,
          format: _grocer.format,
          strategy: _grocer.id,
          count: 1,
        ),
      ]),
      [
        'unknownRegion',
        'nationalCountRange',
        'nationalCountRange',
        'cannotPayNational',
        'notYourCompany',
      ],
    );
    expect(_block(game), isNull);
    // Without national figures there is nowhere to open them.
    final plain = Simulation.newGame(
      loadScenario(_json),
      seed: 1,
      citiesAsleep: true,
    );
    expect(_apply(plain, [_open()]), ['noNational']);
  });

  test('saves, loads and replays the same', () {
    final game = _game(seed: 2);
    expect(_apply(game, [_open(count: 4)]), isEmpty);
    _advance(game, 70);
    final loaded = Simulation.load(_content, game.save());
    expect(loaded.stateHash(), game.stateHash());
    expect(_block(loaded)!.stores, 4);
    _advance(game, 40);
    _advance(loaded, 40);
    expect(loaded.stateHash(), game.stateHash());
    expect(loaded.save().bytes, game.save().bytes);
  });

  test('a game saved before the national figures ran rebuilds them alike', () {
    final game = Simulation.newGame(_content, seed: 3, citiesAsleep: true);
    expect(game.world.national, isNull);
    final loaded = Simulation.load(_content, game.save());
    _advance(game, 70);
    _advance(loaded, 70);
    expect(loaded.stateHash(), game.stateHash());
    expect(
      loaded.national!.countries[_frIndex].chains.first.cash,
      game.national!.countries[_frIndex].chains.first.cash,
    );
  });

  test("a director opens them at the brief's rate, where it allows, and "
      'writes of each', () {
    final game = _game();
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _content.directors!.grades.last.id,
        strategy: _grocer.id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        nationalRate: Fx.parse('0.04'),
        nationalRegions: const ['FRJ'],
      ),
    );
    _advance(game, 200);
    final block = _block(game)!;
    final occitanie = _table.countries[_frIndex].regions.indexWhere(
      (r) => r.key == 'FRJ',
    );
    for (final (r, region) in block.regions.indexed) {
      if (r != occitanie) expect(region.stores, 0);
    }
    // One in Occitanie each month: 4% of so few shops is less than one.
    expect(block.regions[occitanie].stores, inInclusiveRange(1, 7));
    final memos = game
        .observe(_player)
        .companies
        .first
        .memos
        .whereType<NationalOpened>()
        .toList();
    expect(memos, isNotEmpty);
    expect(memos.every((memo) => memo.region == 'FRJ'), isTrue);
    expect(memos.length, block.regions[occitanie].stores);
  });

  test('a director may not be asked to grow faster than the most', () {
    final game = _game();
    expect(
      _apply(game, [
        HireDirector(
          _player,
          company: _company,
          grade: _content.directors!.grades.last.id,
          strategy: _grocer.id,
          managerGrade: _content.managers.grades.last.id,
          growth: Growth.open,
          payout: false,
          nationalRate: maxNationalRate + Fx.raw(1),
        ),
        HireDirector(
          _player,
          company: _company,
          grade: _content.directors!.grades.last.id,
          strategy: _grocer.id,
          managerGrade: _content.managers.grades.last.id,
          growth: Growth.open,
          payout: false,
          nationalAuto: true,
          nationalRegions: const ['XX9'],
        ),
      ]),
      ['nationalRateRange', 'unknownRegion'],
    );
  });

  test('shops are fewer and busier where they cost more to run, so a new '
      'one pays back about as soon anywhere', () {
    final game = _game();
    final france = game
        .observe(_player)
        .national
        .firstWhere((n) => n.country == _france);
    final grocery = france.tradeOf(_content, _grocer.format)!;
    final regions = france.def.regions;
    final paris = regions.indexWhere((r) => r.key == 'FR1');
    // Île-de-France earns most and costs most.
    for (final (r, _) in regions.indexed) {
      expect(
        france.costLevels[grocery][paris] >= france.costLevels[grocery][r],
        isTrue,
      );
    }
    int perShop(int r) =>
        france.markets[grocery][r].cents ~/ france.stores[grocery][r];
    expect(perShop(paris) > perShop(_north) * 12 ~/ 10, isTrue);
    final paybacks = [
      for (final (r, _) in regions.indexed)
        () {
          final shop = france.newShop(
            _content,
            company: _company,
            format: _grocer.format,
            strategy: _grocer.id,
            region: r,
          );
          final cost = france.fitOut(_content, _grocer.format, r);
          return cost.cents * 12 ~/ shop.profit.cents;
        }(),
    ];
    // Within a few months of each other: where chains are at home, a little
    // longer.
    final soonest = paybacks.reduce((a, b) => a < b ? a : b);
    final latest = paybacks.reduce((a, b) => a > b ? a : b);
    expect(latest - soonest, lessThanOrEqualTo(4), reason: '$paybacks');
  });

  test('a director opens restaurants that pay back within three years', () {
    final game = _game();
    final steakhouse = _content.strategies.firstWhere(
      (s) => s.key == 'steakhouse',
    );
    expect(steakhouse.expansionPaybackMonths, lessThan(nationalPaybackMonths));
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _content.directors!.grades.last.id,
        strategy: steakhouse.id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        nationalAuto: true,
      ),
    );
    _advance(game, 120);
    final memos = game
        .observe(_player)
        .companies
        .first
        .memos
        .whereType<NationalOpened>()
        .toList();
    expect(memos.length, greaterThan(3));
    for (final memo in memos) {
      expect(memo.format, steakhouse.format);
      expect(
        memo.paybackMonths,
        inInclusiveRange(steakhouse.expansionPaybackMonths + 1, 36),
      );
    }
  });

  test('settled, they sell about what a district shop of their kind does', () {
    final game = _game();
    expect(_apply(game, [_open(count: 5)]), isEmpty);
    // Past their first two years.
    _advance(game, 365 * 2 + 90);
    final block = _block(game)!;
    expect(block.regions[_north].settled, 5);
    final perShop = block.regions[_north].yearSales.cents ~/ 5;
    // The national figure at today's prices, scaled to the region's costs,
    // as shops are busier where they cost more.
    final economy = game.national!.countries[_frIndex];
    final grocery = game.national!.table.trades.indexWhere(
      (t) => t.key == 'grocery',
    );
    final expected = _content.formats[_grocer.format.index].national!
        .salesIn(_france)
        .times(economy.priceIndex)
        .times(economy.costLevels[grocery][_north])
        .cents;
    expect(
      perShop,
      inInclusiveRange(expected * 80 ~/ 100, expected * 120 ~/ 100),
    );
    final margin = block.regions[_north].yearProfit.cents / perShop / 5;
    expect(margin, inInclusiveRange(0.08, 0.22));
  });
}
