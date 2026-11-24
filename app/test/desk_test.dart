import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/mail.dart';
import 'package:market_game/src/screens/sales_desk.dart';

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

/// A holding with a drinks plant in France, played until a chain opens a
/// tender it could bid for.
SimulationController _withTender() {
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
  bool open() =>
      game.myFactories.isNotEmpty &&
      openTendersFor(game, game.myFactories.single.$2).isNotEmpty;
  while (!open() && days++ < 600) {
    game.step();
  }
  return game;
}

void main() {
  test('a CEO takes a price well over worth, keeps below it, and leans by '
      'character in between; no CEO, no opinion', () {
    final worth = Money.parse('100.00');
    expect(ceoOpinion(null, worth, worth), isNull);
    expect(
      ceoOpinion('steady', Money.parse('130.00'), worth),
      contains('I would take it'),
    );
    expect(
      ceoOpinion('steady', Money.parse('90.00'), worth),
      contains('I would decline'),
    );
    expect(ceoOpinion('bold', worth, worth), contains('keep growing'));
    expect(ceoOpinion('cautious', worth, worth), contains('money in hand'));
    expect(ceoOpinion('steady', worth, worth), contains('Your call'));
  });

  testWidgets('the desk shows the mail waiting, which opens with its numbers '
      'and answers; answered, it says so', (tester) async {
    final game = _withTender();
    final mail = mailOf(game);
    expect(mail, isNotEmpty);
    final tender = mail.firstWhere((each) => each.key.startsWith('tender'));
    expect(tender.until, isNotNull);
    expect(tender.fallback, contains('doesn’t bid'));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: game)));
    await tester.pumpAndSettle();
    expect(find.text('Mail'), findsOneWidget);
    expect(find.textContaining('need'), findsWidgets);
    await tester.scrollUntilVisible(find.text(tender.subject), 200);
    await tester.tap(find.text(tender.subject));
    await tester.pumpAndSettle();
    expect(find.text('Producer price'), findsOneWidget);
    expect(find.textContaining('It stands until'), findsOneWidget);
    expect(find.text('Open the sales desk'), findsOneWidget);
    final bid = tender.answers.where((a) => a.command != null).firstOrNull;
    if (bid != null) {
      await tester.tap(find.text(bid.label));
      await tester.pumpAndSettle();
      expect(game.pending.whereType<BidTender>(), hasLength(1));
      expect(find.textContaining('You answered'), findsOneWidget);
    }
  });

  testWidgets('a holding with no company finds the one to-do on the desk, '
      'then the news', (tester) async {
    final game = SimulationController.newGame(
      _content,
      seed: 4,
      start: const GameStart.holding('Bebedou'),
      citiesAsleep: true,
    );
    await pumpGame(tester, game);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('1 to answer'), findsOneWidget);
    expect(find.text('You have no company trading.'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);
  });
}
