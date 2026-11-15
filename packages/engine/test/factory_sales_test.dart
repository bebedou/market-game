@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/factory.dart';
import 'package:engine/src/state/factory_sales.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

/// The prototype with the countries' national figures, its player rich
/// enough to build any size of plant.
final _content = loadScenario(
  File(
    '../../content/scenarios/prototype.json',
  ).readAsStringSync().replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "50000000.00"',
  ),
  national: loadCountryTable(
    File('../../content/countries/euro.json').readAsStringSync(),
    File('../../content/countries/calibration.json').readAsStringSync(),
  ),
);

final _factories = _content.factories!;
final _drinks = _factories.kinds.firstWhere((kind) => kind.key == 'drinks');
final _france = _content.countries.firstWhere((c) => c.key == 'fr').id;

/// A holding start that builds a drinks plant of [size] in France on three
/// shifts, serving France, and plays on to the first of the month after it
/// opens.
(Simulation, Factory) _withPlant(int size, {int seed = 1}) {
  final game = Simulation.newGame(
    _content,
    seed: seed,
    start: const GameStart.holding('Holding'),
    citiesAsleep: true,
  );
  final player = game.world.player;
  final cost = _factories.sized(_drinks.id, size).buildCost;
  game.submit(
    BuildFactory(
      player,
      kind: _drinks.id,
      country: _france,
      name: 'Usine',
      capital: cost + cost,
      shifts: 3,
      size: size,
    ),
  );
  game.step();
  final factory = game.world.factories.single;
  while (!factory.runsOn(game.today) || !game.today.isFirstOfMonth) {
    game.step();
  }
  return (game, factory);
}

/// The first open tender every rival producer may bid on, playing on
/// month by month until there is one.
Tender _openTender(Simulation game) {
  while (true) {
    for (final tender in game.world.tenders) {
      if (tender.status == TenderStatus.open &&
          tender.floor <= Fx.parse('-0.05') &&
          tender.closes > game.today + 1) {
        return tender;
      }
    }
    _throughFirst(game);
  }
}

/// Steps [game] through the next first of the month.
void _throughFirst(Simulation game) {
  do {
    game.step();
  } while (!game.today.isFirstOfMonth);
  game.step();
}

void main() {
  test('a size multiplies what a kind makes, costs and pays', () {
    final workshop = _factories.sized(_drinks.id, 0);
    final plant = _factories.sized(_drinks.id, 1);
    final industrial = _factories.sized(_drinks.id, 2);
    expect(workshop.shiftUnits, _drinks.shiftUnits);
    expect(plant.shiftUnits, _drinks.shiftUnits * 10);
    expect(industrial.shiftUnits, _drinks.shiftUnits * 100);
    expect(plant.buildCost, _drinks.buildCost.timesInt(8));
    expect(plant.shiftWage, _drinks.shiftWage.timesInt(8));
    expect(plant.buildDays, _drinks.buildDays + 120);
    expect(_factories.sizes.first.key, 'workshop');
  });

  test('a plant built at a size makes ten times a workshop', () {
    final (game, factory) = _withPlant(1);
    expect(factory.size, 1);
    final view = game
        .observe(game.world.player)
        .companies
        .expand((c) => c.factories)
        .single;
    expect(view.size, 1);
    final days = 30;
    expect(
      view.monthCapacity ~/ days >= _drinks.shiftUnits * 10 * 3 - 1,
      isTrue,
    );
    expect(view.sales!.enlargeCost, isNotNull);
  });

  test('enlarging pays the difference and takes effect when the works end', () {
    final (game, factory) = _withPlant(0);
    final player = game.world.player;
    final company = game.world.companies[factory.company.index];
    final cash = company.accounts[AccountKind.cash];
    final cost =
        (_factories.sized(_drinks.id, 1).buildCost -
                _factories.sized(_drinks.id, 0).buildCost)
            .times(game.world.macroOf(_france).priceIndex);
    game.submit(EnlargeFactory(player, factory: factory.id, capital: cost));
    expect(game.step().rejections, isEmpty);
    expect(factory.enlargedOn, isNotNull);
    expect(factory.size, 0);
    // The capital came in and the works went out.
    expect(company.accounts[AccountKind.cash] <= cash, isTrue);
    game.submit(EnlargeFactory(player, factory: factory.id));
    expect(game.step().rejections.single.reason.key, 'factoryEnlarging');
    while (factory.enlargedOn != null) {
      game.step();
    }
    expect(factory.size, 1);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('chains open tenders for what the plant makes, where it sells', () {
    final (game, _) = _withPlant(1);
    for (var month = 0; month < 3; month++) {
      _throughFirst(game);
    }
    final tenders = game.world.tenders;
    expect(tenders, isNotEmpty);
    final chains = {
      for (final chain
          in _content.national!.countries
              .firstWhere((c) => c.key == 'fr')
              .chains)
        chain.name,
    };
    for (final tender in tenders) {
      expect(tender.country, _france);
      expect(chains, contains(tender.chain));
      expect(tender.units, greaterThan(0));
      expect(
        _content.products[tender.product.index].category,
        _drinks.category,
      );
      expect(tender.reference > Money.zero, isTrue);
    }
  });

  test('a low bid wins a contract, delivered from the next month', () {
    final (game, factory) = _withPlant(1);
    final player = game.world.player;
    final tender = _openTender(game);
    game.submit(
      BidTender(
        player,
        tender: tender.number,
        factory: factory.id,
        price: tender.reference.times(Fx.parse('0.5')),
      ),
    );
    game.step();
    expect(tender.bidPrice, isNotNull);
    while (tender.status == TenderStatus.open) {
      game.step();
    }
    expect(tender.status, TenderStatus.won);
    expect(tender.winner, factory.name);
    final contract = game.world.contracts.single;
    expect(contract.factory, factory.id);
    expect(contract.units, tender.units);
    expect(contract.price, tender.bidPrice);
    _throughFirst(game);
    expect(contract.delivered + contract.short, contract.units);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a dear bid loses to a rival producer', () {
    final (game, factory) = _withPlant(1);
    final player = game.world.player;
    final tender = _openTender(game);
    game.submit(
      BidTender(
        player,
        tender: tender.number,
        factory: factory.id,
        price: tender.reference.times(Fx.parse('1.5')),
      ),
    );
    while (tender.status == TenderStatus.open) {
      game.step();
    }
    expect(tender.status, TenderStatus.lost);
    expect(game.world.producers.map((p) => p.name), contains(tender.winner));
    expect(tender.winningPrice! < tender.bidPrice!, isTrue);
    expect(game.world.contracts, isEmpty);
  });

  test('a contract the plant can\'t fill costs a penalty and reliability', () {
    final (game, factory) = _withPlant(0);
    final kind = _factories.sized(_drinks.id, 0);
    final product = _content.products.firstWhere(
      (p) => p.category == _drinks.category,
    );
    game.world.contracts.add(
      Contract(
        number: 999,
        factory: factory.id,
        country: _france,
        chain: 'Test chain',
        product: product.id,
        units: kind.shiftUnits * 3 * 31 * 2,
        price: Money.parse('0.50'),
        starts: game.today,
        ends: game.today + 400,
      ),
    );
    _throughFirst(game);
    final contract = game.world.contracts.single;
    expect(contract.short, greaterThan(0));
    expect(factory.reliability < Fx.one, isTrue);
    final penalties = game
        .reports(factory.company, ReportPeriod.month)
        .last
        .factory(factory.id)!
        .penalties;
    expect(penalties > Money.zero, isTrue);
  });

  test('independents buy more of a plant that sells to them at a discount', () {
    final (game, factory) = _withPlant(1);
    final player = game.world.player;
    game.submit(
      SetFactoryTerms(
        player,
        factory: factory.id,
        serves: factory.serves,
        rivalDiscount: Fx.parse('0.10'),
      ),
    );
    _throughFirst(game);
    final first = factory.independentShare;
    _throughFirst(game);
    expect(first, greaterThan(0));
    expect(factory.independentShare, greaterThan(first));
    expect(factory.recentRivalUnits(game.today), greaterThan(0));
  });

  test(
    'bids are refused on closed tenders and where the plant can\'t sell',
    () {
      final (game, factory) = _withPlant(1);
      final player = game.world.player;
      final tender = _openTender(game);
      final germany = _content.countries.firstWhere((c) => c.key == 'de').id;
      final abroad = Tender(
        number: 777,
        country: germany,
        chain: 'Test chain',
        product: tender.product,
        units: 1000,
        months: 12,
        floor: Fx.zero,
        reference: tender.reference,
        opens: game.today,
        closes: game.today + 30,
      );
      final picky = Tender(
        number: 778,
        country: _france,
        chain: 'Test chain',
        product: tender.product,
        units: 1000,
        months: 12,
        floor: Fx.parse('0.10'),
        reference: tender.reference,
        opens: game.today,
        closes: game.today + 30,
      );
      game.world.tenders.addAll([abroad, picky]);
      for (final (number, key) in [
        (777, 'tenderNotServed'),
        (778, 'belowQualityFloor'),
        (12345, 'unknownTender'),
      ]) {
        game.submit(
          BidTender(
            player,
            tender: number,
            factory: factory.id,
            price: tender.reference,
          ),
        );
        expect(game.step().rejections.single.reason.key, key);
      }
    },
  );

  test('tenders, contracts and producers survive a save', () {
    final (game, factory) = _withPlant(1);
    final player = game.world.player;
    final tender = _openTender(game);
    game.submit(
      BidTender(
        player,
        tender: tender.number,
        factory: factory.id,
        price: tender.reference.times(Fx.parse('0.5')),
      ),
    );
    while (tender.status == TenderStatus.open) {
      game.step();
    }
    final loaded = Simulation.load(_content, game.save());
    expect(loaded.stateHash(), game.stateHash());
    expect(loaded.world.contracts, hasLength(game.world.contracts.length));
    expect(loaded.world.producers, hasLength(game.world.producers.length));
    expect(loaded.world.factories.single.size, 1);
  });
}
