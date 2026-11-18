import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/screens/shop.dart';
import 'package:market_game/src/visuals.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

/// The prototype with the national table, so a director can run a company
/// by formula.
final _content = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync(),
  national: loadCountryTable(
    File('../content/countries/euro.json').readAsStringSync(),
    File('../content/countries/calibration.json').readAsStringSync(),
  ),
);

void main() {
  testWidgets('the Businesses tab lists the companies, each opening its '
      'page and its store', (tester) async {
    final game = SimulationController.newGame(
      _content,
      seed: 3,
      citiesAsleep: true,
    );
    game.step();
    final company = game.view.companies.first;
    final name = game.companyName(company.id);
    await pumpGame(tester, game);
    await tester.tap(find.text('Businesses'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IndexRow, name), findsOneWidget);
    expect(find.textContaining('1 store · run by hand'), findsOneWidget);
    expect(find.text('Start a new business'), findsOneWidget);
    await openStore(tester, game);
    expect(find.byType(ShopScreen), findsOneWidget);
    expect(find.text('Shelves'), findsOneWidget);
  });

  testWidgets("a director's company shows its figures, and it can be "
      'renamed', (tester) async {
    final game = SimulationController.newGame(
      _content,
      seed: 3,
      citiesAsleep: true,
    );
    game.step();
    final company = game.view.companies.first;
    final store = company.stores.single;
    game.submit(
      HireDirector(
        game.player,
        company: company.id,
        grade: _content.directors!.grades.first.id,
        strategy: _content.strategies.firstWhere((s) => s.key == 'balanced').id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.none,
        payout: false,
      ),
    );
    // The director runs it in full until the first of the month.
    game.step();
    expect(game.view.companies.first.stores.single.status, StoreStatus.open);
    while (!game.today.isFirstOfMonth) {
      game.step();
    }
    game.step();
    expect(
      game.alerts.any((alert) => alert.message.contains('now runs by formula')),
      isTrue,
    );
    await pumpGame(tester, game);
    await tester.tap(find.text('Businesses'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 store · run by'), findsOneWidget);
    await openIndex(tester, game.companyName(company.id));
    // The boss's verdict, the company's figures, its one business.
    expect(find.byType(VerdictBox), findsOneWidget);
    expect(find.text('Worth'), findsOneWidget);
    expect(find.textContaining('1 store · 1 country'), findsOneWidget);
    // The trade's figures, by country, and no shop to run: nothing says
    // how the game works its shops out.
    await openRow(tester, tradeNameOf(game, store.format));
    expect(find.text('Sales a month'), findsOneWidget);
    await scrollTo(tester, find.widgetWithText(IndexRow, 'France'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is IndexRow &&
            widget.title == game.storeName(store.id) &&
            widget.onTap != null,
      ),
      findsNothing,
    );
    expect(find.textContaining('formula'), findsNothing);
    await goBack(tester);

    await openIndex(tester, 'Rename the company');
    await tester.enterText(find.byType(TextField), 'Hénon Holdings');
    await tester.pump();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(game.companyName(company.id), 'Hénon Holdings');
    game.step();
    expect(game.view.companyNames[company.id.index], 'Hénon Holdings');
  });
}
