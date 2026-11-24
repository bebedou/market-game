import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/financials.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/screens/new_game.dart';
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

  test("a group's books leave out the capital its companies put into each "
      'other, its profit kept the same', () {
    final game = newController();
    game
      ..submit(
        FoundCompany(
          game.player,
          name: 'Filiale',
          capital: Money.parse('1000.00'),
          parent: playerCompany,
        ),
      )
      ..step();
    final companies = game.view.companies;
    final parent = companies.first;
    expect(
      financialsOf(game, [parent]).balance(AccountKind.investments),
      Money.parse('1000.00'),
    );
    final group = financialsOf(game, companies);
    expect(group.balance(AccountKind.investments), Money.zero);
    expect(
      group.retainedEarnings,
      companies.fold(Money.zero, (sum, c) => sum + c.retainedEarnings),
    );
    expect(
      group.balance(AccountKind.equity),
      companies.fold(
            Money.zero,
            (sum, c) => sum + c.balance(AccountKind.equity),
          ) +
          Money.parse('1000.00'),
    );
  });

  testWidgets('Holding has its own books and its portfolio', (tester) async {
    final game = _investor();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: game)));
    await tester.pumpAndSettle();
    expect(find.text('Bebedou'), findsOneWidget);
    // No company yet: the verdict says so, and the figures are the holding's.
    expect(find.textContaining('No company yet'), findsOneWidget);
    expect(find.text('Net worth'), findsWidgets);
    await tester.scrollUntilVisible(find.text('The holding’s books'), 200);
    expect(find.text('Shares'), findsOneWidget);
    // Nothing sold yet, so no result of its own; one unit sold books the
    // gain or loss and the brokerage.
    expect(find.text('Its own result'), findsNothing);
    game
      ..submit(SellShares(_content.player, of: 0, units: 1, index: true))
      ..step();
    await tester.pumpAndSettle();
    expect(game.view.balances[AccountKind.spending.index] > Money.zero, isTrue);
    await tester.scrollUntilVisible(find.text('Its own result'), 200);
    expect(find.text('Fees'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Your portfolio'), 200);
    // The index bought, as a line that opens it.
    final index = game.view.stocks!.exchanges.first.indexName;
    await tester.scrollUntilVisible(find.text(index), 200);
    expect(find.text(index), findsOneWidget);
    // Finance shows the companies' money only.
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(find.text('The holding’s cash'), findsNothing);
  });

  testWidgets('a factory being built is on its business, with news the day '
      'its works start', (tester) async {
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
    await openCompany(tester, game, playerCompany);
    await openRow(tester, rich.factories!.kinds.first.name);
    expect(find.widgetWithText(IndexRow, 'Fournil du Coin'), findsOneWidget);
    expect(find.textContaining('opens'), findsWidgets);
  });

  testWidgets("under a director, a trade's page shows its figures, not its "
      'shops', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    expect(find.text('Worth'), findsOneWidget);
    await openRow(tester, 'Groceries');
    // Run by hand: the store's line, which opens it.
    final shop = find.byWidgetPredicate(
      (widget) =>
          widget is IndexRow &&
          widget.title == 'Corner Shop' &&
          widget.onTap != null,
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
    expect(find.text('Sales a month'), findsOneWidget);
    // Its company's page leads to its money.
    await goBack(tester);
    await scrollTo(tester, find.text('Cash, loans and books'));
    await tester.tap(find.text('Cash, loans and books'));
    await tester.pumpAndSettle();
    expect(find.text('CEO'), findsWidgets);
  });

  testWidgets('a company is renamed from its page, the holding from its '
      'books, each from tomorrow', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    await openRow(tester, 'Rename the company');
    await tester.enterText(find.byType(TextField), 'Rayan & Co');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(game.pending.whereType<RenameCompany>(), hasLength(1));
    game.step();
    await tester.pumpAndSettle();
    expect(game.view.companyNames[playerCompany.index], 'Rayan & Co');

    final investor = _investor();
    await tester.pumpWidget(const SizedBox());
    await pumpGame(tester, investor);
    await tester.scrollUntilVisible(find.text('Rename the holding'), 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename the holding'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Berkshire Bebedou');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    investor.step();
    await tester.pumpAndSettle();
    expect(investor.view.holdingName, 'Berkshire Bebedou');
    expect(find.text('Berkshire Bebedou'), findsWidgets);
  });

  testWidgets('a new game takes the money to start with, within bounds, and '
      'starts with it', (tester) async {
    GameStart? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await Navigator.of(context).push<GameStart>(
                  MaterialPageRoute(
                    builder: (_) => NewGameScreen(content: _content),
                  ),
                ),
            child: const Text('New'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    final name = find.byType(TextField).first;
    final cash = find.byType(TextField).last;
    await tester.enterText(name, 'Bebedou');
    await tester.enterText(cash, '500');
    await tester.pump();
    expect(
      find.text('Start with between 10,000 and 1,000,000,000.'),
      findsOneWidget,
    );
    await tester.enterText(cash, '250000');
    await tester.pump();
    expect(find.textContaining('Start with between'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(chosen?.name, 'Bebedou');
    expect(chosen?.cash, Money.parse('250000.00'));
    final game = SimulationController.newGame(_content, seed: 7, start: chosen);
    expect(game.view.cash, Money.parse('250000.00'));
    expect(game.holdingName, 'Bebedou');
  });

  testWidgets('a company founds a subsidiary from its page, which the '
      'holding counts once, through its parent', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    await openRow(tester, 'Found a subsidiary');
    await tester.enterText(find.byType(TextField).first, 'Filiale');
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.pump();
    await tester.tap(find.text('Found'));
    await tester.pumpAndSettle();
    expect(game.pending.whereType<FoundCompany>().single.parent, playerCompany);
    game.step();
    await tester.pumpAndSettle();
    final subsidiary = game.view.companies.last;
    expect(subsidiary.parent, playerCompany);
    expect(subsidiary.cash, Money.parse('1000.00'));
    // On its parent's page, and only there.
    await scrollTo(tester, find.widgetWithText(IndexRow, 'Filiale'));
    expect(find.text('Subsidiaries'), findsOneWidget);
    // The parent's worth carries it, so the holding adds only the parent.
    final parent = game.view.companies.first;
    expect(game.companiesWorth, SimulationController.worthOf(parent));
    expect(
      SimulationController.worthOf(parent) >= Money.parse('1000.00'),
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.account_balance_outlined));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IndexRow, 'Filiale'), findsNothing);
  });
}
