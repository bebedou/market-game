import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

void main() {
  testWidgets("a business's page moves it to another company, saying how and "
      'at what', (tester) async {
    final game = newController();
    game
      ..submit(
        FoundCompany(
          game.player,
          name: 'Autre',
          capital: Money.parse('5000.00'),
        ),
      )
      ..step();
    final other = game.view.companies.last;
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    await openRow(tester, 'Groceries');
    await openRow(tester, 'Move to another company');
    await tester.tap(find.text('Autre'));
    await tester.pumpAndSettle();
    // Beside it: the other pays its book value in cash, untaxed.
    expect(find.textContaining('Autre pays Corner Shop'), findsOneWidget);
    expect(find.text('none inside the group'), findsOneWidget);
    await tester.tap(find.text('Move it'));
    await tester.pumpAndSettle();
    final move = game.pending.whereType<MoveBusiness>().single;
    expect(move.company, playerCompany);
    expect(move.business, 'grocery');
    expect(move.to, other.id);
    game.step();
    expect(game.view.companies.last.stores, isNotEmpty);
  });

  testWidgets("a company's page merges a subsidiary up, its kept profit "
      'paying the dividend rate', (tester) async {
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
    final subsidiary = game.view.companies.last;
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    await openRow(tester, 'Filiale');
    await openRow(tester, 'Merge into another company');
    await tester.tap(find.text('Corner Shop').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('pays the dividend rate'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await tester.pumpAndSettle();
    final merge = game.pending.whereType<MergeCompany>().single;
    expect(merge.company, subsidiary.id);
    expect(merge.into, playerCompany);
    game.step();
    expect(
      game.view.companies.firstWhere((c) => c.id == subsidiary.id).status,
      CompanyStatus.merged,
    );
  });

  testWidgets("a company's page offers to sell it whole, or says why not", (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await openCompany(tester, game, playerCompany);
    await openRow(tester, 'Sell the company');
    expect(find.text('Sell Corner Shop'), findsOneWidget);
    final sale = game.view.companies.first.sale!;
    if (sale.refusal == null) {
      expect(find.textContaining('Sell for'), findsOneWidget);
    } else {
      expect(find.widgetWithText(IndexRow, 'Sell for'), findsNothing);
    }
  });
}
