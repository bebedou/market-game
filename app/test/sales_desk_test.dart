import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/screens/factory.dart';
import 'package:market_game/src/screens/sales_desk.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

/// The prototype with the national figures, its player rich enough to
/// build a plant.
final _content = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync().replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "5000000.00"',
  ),
  national: loadCountryTable(
    File('../content/countries/euro.json').readAsStringSync(),
    File('../content/countries/calibration.json').readAsStringSync(),
  ),
);

/// A holding with a drinks plant in France, played until chains have
/// opened tenders for its goods.
SimulationController _withPlant() {
  final game = SimulationController.newGame(
    _content,
    seed: 4,
    start: const GameStart.holding('Bebedou'),
    citiesAsleep: true,
  );
  final factories = _content.factories!;
  final drinks = factories.kinds.firstWhere((k) => k.key == 'drinks');
  final cost = factories.sized(drinks.id, 1).buildCost;
  game.submit(
    BuildFactory(
      game.player,
      kind: drinks.id,
      country: _content.countries.first.id,
      name: 'Sources Vives',
      capital: cost + cost,
      shifts: 1,
      size: 1,
    ),
  );
  var days = 0;
  while (game.view.tenders.isEmpty && days++ < 500) {
    game.step();
  }
  return game;
}

Future<void> _pumpPage(
  WidgetTester tester,
  SimulationController game,
  Widget page,
) async {
  usePhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameScope(
          controller: game,
          child: SubPages(
            open: (_) {},
            child: ListView(children: [page]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a factory page leads to its sales desk and shows its size', (
    tester,
  ) async {
    final game = _withPlant();
    final factory = game.myFactories.single.$2;
    await _pumpPage(tester, game, FactoryPage(id: factory.id));
    expect(find.textContaining('plant'), findsWidgets);
    expect(find.widgetWithText(IndexRow, 'Sales desk'), findsOneWidget);
    expect(
      find.textContaining('Enlarge to the next size, industrial site'),
      findsOneWidget,
    );
  });

  testWidgets('the sales desk lists the open tenders for its goods', (
    tester,
  ) async {
    final game = _withPlant();
    final factory = game.myFactories.single.$2;
    await _pumpPage(tester, game, SalesDeskPage(id: factory.id));
    expect(find.text('Its market a month'), findsOneWidget);
    expect(find.text('Open tenders'), findsOneWidget);
    expect(find.textContaining(' seeks '), findsWidgets);
    expect(find.text('Independent shops'), findsOneWidget);
  });

  testWidgets('a bid page weighs the bid and places it', (tester) async {
    final game = _withPlant();
    final factory = game.myFactories.single.$2;
    final tender = openTendersFor(game, factory).first;
    await _pumpPage(
      tester,
      game,
      TenderBidPage(factory: factory.id, tender: tender.number),
    );
    expect(find.text('Producer price'), findsOneWidget);
    expect(find.text('Earns a month if won'), findsOneWidget);
    expect(find.text('5% under'), findsOneWidget);
    final place = find.text('Place bid');
    if (tester
            .widget<FilledButton>(
              find.ancestor(of: place, matching: find.byType(FilledButton)),
            )
            .onPressed !=
        null) {
      await tester.tap(place);
      await tester.pumpAndSettle();
      expect(game.bidOn(tender), isNotNull);
    }
  });

  testWidgets('a contract page shows its terms, a new price and its fee', (
    tester,
  ) async {
    final game = _withPlant();
    var factory = game.myFactories.single.$2;
    final tender = openTendersFor(game, factory).first;
    game.submit(
      BidTender(
        game.player,
        tender: tender.number,
        factory: factory.id,
        price: tender.reference.times(Fx.parse('0.5')),
      ),
    );
    var days = 0;
    while ((game.factory(factory.id)!.sales!.contracts.isEmpty) &&
        days++ < 80) {
      game.step();
    }
    factory = game.factory(factory.id)!;
    final contract = factory.sales!.contracts.single;
    await _pumpPage(
      tester,
      game,
      ContractPage(factory: factory.id, contract: contract.number),
    );
    expect(find.text('Ask for a new price'), findsOneWidget);
    expect(find.text('Break it'), findsOneWidget);
    expect(find.textContaining('Fee: 3 months'), findsOneWidget);
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(game.pending.whereType<AskPrice>(), hasLength(1));
  });
}
