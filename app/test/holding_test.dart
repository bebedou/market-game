import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

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

  testWidgets('a factory being built is on Holding, with news the day its '
      'works start', (tester) async {
    final rich = loadScenario(
      File(
        '../content/scenarios/prototype.json',
      ).readAsStringSync().replaceFirst(
        '"name": "You", "cash": "20000.00"',
        '"name": "You", "cash": "400000.00"',
      ),
    );
    final game = SimulationController.newGame(rich, seed: 7);
    game.submit(
      BuildFactory(
        rich.player,
        kind: rich.factories!.kinds.first.id,
        country: const CountryId(0),
        name: 'Fournil du Coin',
        company: playerCompany,
        capital: Money.parse('150000.00'),
        shifts: 1,
      ),
    );
    game.step();
    expect(
      game.alerts.map((alert) => alert.message),
      contains(startsWith('Works have started on Fournil du Coin')),
    );
    await pumpGame(tester, game);
    expect(find.text('Being built'), findsOneWidget);
    expect(find.widgetWithText(IndexRow, 'Fournil du Coin'), findsWidgets);
  });

  testWidgets('each company has a dashboard, and a director takes its stores '
      'off Holding', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    // The store's line, marked with its trade; its company is named alike.
    final shop = find.byWidgetPredicate(
      (widget) =>
          widget is IndexRow &&
          widget.title == 'Corner Shop' &&
          widget.mark != null,
    );
    await scrollTo(tester, shop);
    expect(shop, findsOneWidget);
    game
      ..submit(
        HireDirector(
          prototype.player,
          company: playerCompany,
          grade: prototype.directors!.grades.first.id,
          strategy: strategy('balanced'),
          managerGrade: grade('trainee'),
          growth: Growth.open,
          payout: false,
        ),
      )
      ..step();
    await tester.pumpAndSettle();
    expect(shop, findsNothing);
    expect(
      find.text('Stores run by a director are on their company’s page.'),
      findsOneWidget,
    );
    // Its dashboard has its worth, its store and the way to its money.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await openIndex(tester, game.companyName(playerCompany));
    expect(find.text('Worth'), findsOneWidget);
    await scrollTo(tester, shop);
    expect(shop, findsOneWidget);
    await scrollTo(tester, find.text('Cash, loans and books'));
    await tester.tap(find.text('Cash, loans and books'));
    await tester.pumpAndSettle();
    expect(find.text('Director'), findsWidgets);
  });
}
