@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/taxation.dart';
import 'package:test/test.dart';

/// The game's scenario, the player rich enough to build.
final _content = loadScenario(
  File(
    '../../content/scenarios/prototype.json',
  ).readAsStringSync().replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "400000.00"',
  ),
);

CountryId _country(String key) =>
    _content.countries.firstWhere((country) => country.key == key).id;

FactoryKindId _kind(String key) =>
    _content.factories!.kinds.firstWhere((kind) => kind.key == key).id;

void main() {
  final player = _content.player;
  const company = CompanyId(0);
  final france = _country('fr');
  final spain = _country('es');

  test('the scenario has four kinds of factory, bread kept at home', () {
    final kinds = _content.factories!.kinds;
    expect(kinds.map((kind) => kind.key), [
      'bakery',
      'drinks',
      'snacks',
      'household',
    ]);
    expect(kinds.first.exports, isFalse);
    expect(kinds.skip(1).every((kind) => kind.exports), isTrue);
  });

  test('a plant in Spain serves French shops, and pays tax in Spain', () {
    final game = Simulation.newGame(_content, seed: 5, citiesAsleep: true);
    final serves = [
      for (var c = 0; c < _content.countries.length; c++)
        c == france.index || c == spain.index,
    ];
    game.submit(
      InjectCapital(player, company: company, amount: Money.parse('300000.00')),
    );
    game.step();
    game.submit(
      BuildFactory(
        player,
        kind: _kind('drinks'),
        country: spain,
        name: 'Bebidas',
        company: company,
        shifts: 1,
        serves: serves,
      ),
    );
    expect(game.step().rejections, isEmpty);
    // A bakery's bread doesn't travel.
    game.submit(
      BuildFactory(
        player,
        kind: _kind('bakery'),
        country: spain,
        name: 'Horno',
        company: company,
        serves: serves,
      ),
    );
    expect(game.step().rejections.map((r) => r.reason.key), ['factoryLocal']);
    // The player's shop needs a manager to order on its own.
    final view = game.observe(player);
    final store = view.companies.first.stores.first;
    game.submit(
      HireManager(
        player,
        store: store.id,
        grade: _content.managers.grades.last.id,
        strategy: _content.strategies.first.id,
        duties: const [true, true, true, true, false],
      ),
    );
    for (var day = 0; day < 200; day++) {
      game.step();
    }
    final reports = game.reports(company, ReportPeriod.month);
    var made = 0;
    var freight = Money.zero;
    for (final report in reports) {
      final part = report.factory(const FactoryId(0));
      if (part == null) continue;
      made += part.made;
      freight += part.freight;
    }
    // The French shop's drinks came from Spain, carried at a cost.
    expect(made, greaterThan(0));
    expect(freight.cents, greaterThan(0));
    final year = game.today.date.year;
    final taxes = companyTaxes(
      game.world,
      _content,
      game.world.companies[company.index],
      year,
    );
    expect(taxes.map((tax) => tax.country), contains(spain));
    expect(invariantViolations(game.world), isEmpty);
  });
}
