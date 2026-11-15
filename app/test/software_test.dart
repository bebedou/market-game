import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/format.dart';
import 'package:market_game/src/screens/software.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

/// A game started as a holding that founds a software company with all
/// its cash and hires the first two people on the market.
SimulationController _founder() {
  final game = SimulationController.newGame(
    prototype,
    seed: 3,
    start: const GameStart.holding('Bebedou'),
  );
  game.submit(
    StartSoftware(
      game.player,
      name: 'Tessel',
      country: prototype.countries.first.id,
      capital: game.view.cash,
    ),
  );
  game.step();
  final software = game.mySoftware.single.$2;
  for (final person in game.view.softwareCandidates.take(2)) {
    game.submit(
      HireSoftwarePerson(game.player, software: software.id, person: person.id),
    );
  }
  game.step();
  return game;
}

/// [widget] in a scroll view, as a page within a tab shows it.
Future<void> _pumpPage(
  WidgetTester tester,
  SimulationController game,
  Widget widget,
) async {
  usePhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameScope(
          controller: game,
          child: SubPages(
            open: (_) {},
            child: ListView(children: [widget]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the holding lists a software company and offers to start one', (
    tester,
  ) async {
    final game = _founder();
    await pumpGame(tester, game);
    await scrollTo(tester, find.text('Your software company'));
    expect(find.text('Tessel'), findsWidgets);
    expect(find.text('Start a software company'), findsOneWidget);
  });

  testWidgets("its page leads with four figures and the pages' index", (
    tester,
  ) async {
    final game = _founder();
    final software = game.mySoftware.single.$2;
    await _pumpPage(tester, game, SoftwarePage(id: software.id));
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Revenue a month'), findsOneWidget);
    expect(find.text('Cash lasts'), findsOneWidget);
    expect(find.textContaining('on paper'), findsOneWidget);
    expect(
      find.textContaining('from a first version that sells'),
      findsOneWidget,
    );
    for (final page in [
      'Product and team',
      'Customers and price',
      'The market',
      'Owners and funding',
    ]) {
      expect(find.widgetWithText(IndexRow, page), findsOneWidget);
    }
  });

  testWidgets('the product page shows the team and how far from selling', (
    tester,
  ) async {
    final game = _founder();
    final software = game.mySoftware.single.$2;
    await _pumpPage(tester, game, SoftwareProductPage(id: software.id));
    expect(find.text('Against the standard'), findsOneWidget);
    expect(find.textContaining('Team · 2 of 12'), findsOneWidget);
    expect(find.text('Let go'), findsNWidgets(2));
  });

  testWidgets('the funding page offers rounds and shows the owners', (
    tester,
  ) async {
    final game = _founder();
    final software = game.mySoftware.single.$2;
    await _pumpPage(tester, game, SoftwareFundingPage(id: software.id));
    expect(find.text('Owners'), findsOneWidget);
    expect(find.text('Worth, on paper'), findsOneWidget);
    expect(find.text('No round yet.'), findsOneWidget);
    expect(find.text('Shut down'), findsWidgets);
  });

  testWidgets('the market page lists the rivals and everyone else', (
    tester,
  ) async {
    final game = _founder();
    final software = game.mySoftware.single.$2;
    await _pumpPage(tester, game, SoftwareMarketPage(id: software.id));
    expect(find.text('Halvren Systems'), findsOneWidget);
    expect(find.text('Everyone else'), findsOneWidget);
  });

  test('net worth counts a software stake at what it is worth, on paper', () {
    final game = _founder();
    final (company, software) = game.mySoftware.single;
    expect(software.yourWorth >= company.netAssets, isTrue);
    expect(game.onPaper, software.yourWorth - company.netAssets);
    expect(
      game.netWorth,
      game.view.cash +
          game.view.companies
              .where((c) => c.id != company.id)
              .fold(Money.zero, (sum, c) => sum + c.netAssets) +
          software.yourWorth,
    );
  });

  test('big figures are shortened to millions and billions', () {
    expect(compactMoney(Money.parse('999999.00')), '999,999');
    expect(compactMoney(Money.parse('2400000.00')), '2.4m');
    expect(compactMoney(Money.parse('31000000000.00')), '31bn');
    expect(compactMoney(Money.parse('-1250000.00')), '−1.3m');
  });
}
