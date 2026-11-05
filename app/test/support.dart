import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/app.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/saves.dart';
import 'package:market_game/src/screens/menu.dart';
import 'package:market_game/src/widgets.dart';

/// The prototype scenario, read from the content package.
final prototype = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync(),
);

const playerStore = StoreId(0);
const playerCompany = CompanyId(0);

ManagerGradeId grade(String key) =>
    prototype.managers.grades.firstWhere((grade) => grade.key == key).id;

StrategyId strategy(String key) =>
    prototype.strategies.firstWhere((strategy) => strategy.key == key).id;

ProductId product(String key) =>
    prototype.products.firstWhere((product) => product.key == key).id;

SupplierId supplier(String key) =>
    prototype.suppliers.firstWhere((supplier) => supplier.key == key).id;

FormatId format(String key) =>
    prototype.formats.firstWhere((format) => format.key == key).id;

SimulationController newController({SaveStore? saves}) =>
    SimulationController.newGame(prototype, seed: 7, saves: saves);

/// Rue du Mail, vacant at the start.
final mill = prototype.sites.firstWhere((site) => site.key == 'backstreet').id;

/// Opens a second store at Rue du Mail tomorrow, as a company of its own,
/// with all the player's cash.
void openSecondStore(SimulationController game) => game.submit(
  OpenStore(
    prototype.player,
    site: mill,
    name: 'Mail Market',
    capital: game.view.cash,
  ),
);

/// Sizes the test screen like a phone.
void usePhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

/// Scrolls the screen's outermost list until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Shows the main menu on a phone-sized screen, games kept in [saves].
Future<void> pumpMenu(WidgetTester tester, SaveSlots saves) async {
  usePhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ScreenMargins(child: child!),
      home: MainMenu(content: prototype, saves: saves),
    ),
  );
  await tester.pumpAndSettle();
}

/// Shows [controller]'s game on a phone-sized screen.
Future<void> pumpGame(
  WidgetTester tester,
  SimulationController controller,
) async {
  usePhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ScreenMargins(child: child!),
      home: HomeScreen(controller: controller),
    ),
  );
  await tester.pump();
}

/// Opens the index line titled [title] on the screen shown.
Future<void> openIndex(WidgetTester tester, String title) async {
  final row = find.widgetWithText(IndexRow, title);
  await scrollTo(tester, row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Goes back from a page opened within a tab.
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}
