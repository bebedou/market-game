import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/home.dart';

/// The prototype with the national table and the stock market.
final _content = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync(),
  national: loadCountryTable(
    File('../content/countries/euro.json').readAsStringSync(),
    File('../content/countries/calibration.json').readAsStringSync(),
  ),
  stocks: File('../content/stocks/companies.json').readAsStringSync(),
);

/// A holding start that has bought index units with its own cash.
SimulationController _investor() {
  final game = SimulationController.newGame(
    _content,
    seed: 7,
    start: const GameStart.holding('Bebedou'),
  );
  game.submit(BuyShares(_content.player, of: 0, units: 5, index: true));
  for (var i = 0; i < 5; i++) {
    game.step();
  }
  return game;
}

void main() {
  test('net worth is the holding\'s books added up', () {
    final game = _investor();
    final view = game.view;
    expect(view.portfolio > Money.zero, isTrue);
    expect(
      game.netWorth,
      view.cash + view.portfolio + game.companiesWorth - game.shareLoans,
    );
  });

  testWidgets('Holding leads with the holding\'s books and its portfolio', (
    tester,
  ) async {
    final game = _investor();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: game)));
    await tester.pumpAndSettle();
    expect(find.text('Bebedou'), findsOneWidget);
    expect(find.text('The holding’s books'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Your portfolio'), findsOneWidget);
    // The index bought, as a line that opens it.
    final index = game.view.stocks!.exchanges.first.indexName;
    await tester.scrollUntilVisible(find.text(index), 200);
    expect(find.text(index), findsOneWidget);
    // Finance shows the companies' money only.
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(find.text('The holding’s cash'), findsNothing);
  });
}
