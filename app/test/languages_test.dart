import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/app.dart';
import 'package:market_game/src/commands.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/format.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/l10n.dart';
import 'package:market_game/src/letters.dart';
import 'package:market_game/src/saves.dart';
import 'package:market_game/src/screens/guide.dart';
import 'package:market_game/src/screens/menu.dart';
import 'package:market_game/src/screens/new_game.dart';
import 'package:market_game/src/widgets.dart';

import 'flutter_test_config.dart';

/// The scenario in the words of the language in use.
ContentDb _content() => loadScenario(
  localizedScenario(
    File('../content/scenarios/prototype.json').readAsStringSync(),
    currentStrings!.scenario,
  ),
);

/// Like [_content], with the countries' national figures by region.
ContentDb _nationalContent() => loadScenario(
  localizedScenario(
    File('../content/scenarios/prototype.json').readAsStringSync(),
    currentStrings!.scenario,
  ),
  national: loadCountryTable(
    File('../content/countries/euro.json').readAsStringSync(),
    File('../content/countries/calibration.json').readAsStringSync(),
  ),
);

/// The name of the first region of [content]'s first country.
String _firstRegion(ContentDb content) => content.national!.countries
    .firstWhere((c) => c.key == content.countries.first.national)
    .regions
    .first
    .name;

/// A narrow phone: what is too long for it overflows, and that fails the test.
void _useNarrowPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2280)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final _rawKey = RegExp(r'^[a-zA-Z]+(\.[a-zA-Z0-9]+)+$');

/// Fails on anything shown as a bare key or with a blank left unfilled.
void _checkWords(WidgetTester tester, String where) {
  final problem = tester.takeException();
  if (problem is FlutterError) {
    fail('$where: ${problem.toStringDeep()}');
  }
  expect(problem, isNull, reason: where);
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final shown = text.data ?? text.textSpan?.toPlainText() ?? '';
    expect(_rawKey.hasMatch(shown), isFalse, reason: '$where: "$shown"');
    expect(shown.contains('{'), isFalse, reason: '$where: "$shown"');
  }
}

/// Closes the sheet or dialog on top.
void _closeSheet(WidgetTester tester) {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  if (navigator.canPop()) navigator.pop();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Opens each line of the contents on the screen shown, reads it and comes
/// back, scrolling on until the end.
Future<void> _visitRows(WidgetTester tester, String where) async {
  final seen = <String>{};
  for (var sweep = 0; sweep < 8; sweep++) {
    final titles = [
      for (final row in tester.widgetList<IndexRow>(find.byType(IndexRow)))
        row.title,
    ];
    for (final title in titles) {
      if (!seen.add(title)) continue;
      final row = find.widgetWithText(IndexRow, title).first;
      if (row.evaluate().isEmpty) continue;
      await tester.ensureVisible(row);
      await _settle(tester);
      await tester.tap(row, warnIfMissed: false);
      await _settle(tester);
      _checkWords(tester, '$where > $title');
      if (find.byIcon(Icons.arrow_back).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back));
      } else {
        // A sheet rather than a page.
        _closeSheet(tester);
      }
      await _settle(tester);
    }
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    await tester.drag(
      scrollable.first,
      const Offset(0, -500),
      warnIfMissed: false,
    );
    await _settle(tester);
  }
}

/// A game some way in: a manager, a director who has written, a loan and news.
SimulationController _playedGame(ContentDb content, {required int days}) {
  ManagerGradeId grade(String key) =>
      content.managers.grades.firstWhere((grade) => grade.key == key).id;
  StrategyId strategy(String key) =>
      content.strategies.firstWhere((strategy) => strategy.key == key).id;
  final game = SimulationController.newGame(content, seed: 7);
  game
    ..submit(
      HireManager(
        content.player,
        store: const StoreId(0),
        grade: grade('expert'),
        strategy: strategy('balanced'),
        duties: [for (final _ in ManagerDuty.values) true],
      ),
    )
    ..submit(
      HireDirector(
        content.player,
        company: const CompanyId(0),
        grade: content.directors!.grades.last.id,
        strategy: strategy('balanced'),
        managerGrade: grade('experienced'),
        growth: Growth.buy,
        payout: false,
        borrows: true,
      ),
    );
  for (var i = 0; i < days; i++) {
    game.step();
  }
  return game;
}

void main() {
  for (final code in ['en', 'fr', 'es']) {
    group(code, () {
      setUp(() {
        // No fallback: what this language lacks shows up as a bare key.
        useStrings(stringsFromFiles(code));
      });
      tearDown(() => useStrings(stringsFromFiles('en')));

      testWidgets('the main menu, the guide and a new game fit', (
        tester,
      ) async {
        _useNarrowPhone(tester);
        final content = _content();
        final saves = MemorySaveSlots();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ScreenMargins(child: child!),
            home: MainMenu(
              content: content,
              saves: saves,
              languages: const [
                (code: 'en', name: 'English'),
                (code: 'fr', name: 'Français'),
                (code: 'es', name: 'Español'),
              ],
              language: code,
              onLanguage: (_) {},
            ),
          ),
        );
        await _settle(tester);
        _checkWords(tester, 'menu');
        expect(find.text(tr('common.newGame')), findsOneWidget);

        await tester.tap(find.byIcon(Icons.language));
        await _settle(tester);
        expect(find.text('Français'), findsWidgets);
        _checkWords(tester, 'language picker');
        _closeSheet(tester);
        await _settle(tester);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ScreenMargins(child: child!),
            home: const HowToPlayScreen(),
          ),
        );
        await _settle(tester);
        _checkWords(tester, 'guide');

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ScreenMargins(child: child!),
            home: NewGameScreen(content: content),
          ),
        );
        await _settle(tester);
        _checkWords(tester, 'new game');
      });

      testWidgets('every tab and page of a game played a while fits', (
        tester,
      ) async {
        _useNarrowPhone(tester);
        final content = _content();
        final game = _playedGame(content, days: 200);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ScreenMargins(child: child!),
            home: HomeScreen(controller: game),
          ),
        );
        await _settle(tester);
        _checkWords(tester, 'holding');
        await _visitRows(tester, 'holding');

        Future<void> tab(IconData icon, String name) async {
          await tester.tap(find.byIcon(icon));
          await _settle(tester);
          _checkWords(tester, name);
          await _visitRows(tester, name);
        }

        await tab(Icons.payments_outlined, 'finance');
        await tab(Icons.public_outlined, 'world');
        await tab(Icons.menu_book_outlined, 'books');

        await tester.tap(find.byIcon(Icons.storefront_outlined));
        await _settle(tester);
        _checkWords(tester, 'shelves');
        await tester.tap(find.text(tr('store.parts.supplies')));
        await _settle(tester);
        _checkWords(tester, 'supplies');
        await _visitRows(tester, 'supplies');
        await tester.tap(find.text(tr('orders.order')).first);
        await _settle(tester);
        _checkWords(tester, 'order sheet');
        _closeSheet(tester);
        await _settle(tester);
        await tester.tap(find.text(tr('store.parts.running')));
        await _settle(tester);
        _checkWords(tester, 'running');
        await _visitRows(tester, 'running');

        // The news, whatever has come by now.
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await _settle(tester);
        _checkWords(tester, 'news');
        expect(game.alerts, isNotEmpty);
      });

      testWidgets('the sheets and dialogs of a company fit', (tester) async {
        _useNarrowPhone(tester);
        final content = _content();
        final game = _playedGame(content, days: 40);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ScreenMargins(child: child!),
            home: HomeScreen(controller: game),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.payments_outlined));
        await _settle(tester);
        await tester.tap(
          find.widgetWithText(IndexRow, game.companyName(game.company!.id)),
        );
        await _settle(tester);
        Future<void> openAndClose(String label) async {
          final button = find.text(label).first;
          await tester.scrollUntilVisible(
            button,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(button);
          await _settle(tester);
          await tester.tap(button);
          await _settle(tester);
          _checkWords(tester, label);
          _closeSheet(tester);
          await _settle(tester);
        }

        await openAndClose(tr('common.changeBrief'));
        await openAndClose(tr('finance.change'));
        await openAndClose(tr('finance.borrow'));
        await openAndClose(tr('finance.addCapital'));
        await openAndClose(tr('finance.payDividend'));
      });

      test('everything said of a command leaves no blank', () {
        final content = _content();
        final game = SimulationController.newGame(content, seed: 7);
        final view = game.view;
        const store = StoreId(0);
        const company = CompanyId(0);
        final player = content.player;
        final product = content.products.first.id;
        final amount = Money.parse('1234.50');
        final commands = <Command>[
          SetPrice(player, store: store, product: product, price: amount),
          PlaceOrder(
            player,
            store: store,
            supplier: content.suppliers.first.id,
            lines: [(product: product, quantity: 12)],
          ),
          ListProduct(player, store: store, product: product, price: amount),
          DelistProduct(player, store: store, product: product),
          InjectCapital(player, company: company, amount: amount),
          PayDividend(player, company: company, amount: amount),
          TakeLoan(
            player,
            company: company,
            amount: amount,
            termMonths: 36,
            guarantee: false,
          ),
          TakeLoan(
            player,
            company: company,
            amount: amount,
            termMonths: 18,
            guarantee: true,
          ),
          RepayLoan(player, loan: 1, amount: amount),
          OpenStore(
            player,
            site: content.sites.first.id,
            name: 'Mail',
            format: content.formats.first.id,
            borrow: amount,
            termMonths: 60,
          ),
          SetMarketing(player, store: store, share: Fx.zero),
          SetMarketing(player, store: store, share: Fx.parse('0.05')),
          ConvertStore(player, store: store, format: content.formats.last.id),
          CloseStore(player, store: store),
          SetStaffing(player, store: store, staff: const [1, 2, 3, 0]),
          HireManager(
            player,
            store: store,
            grade: content.managers.grades.first.id,
            strategy: content.strategies.first.id,
            duties: [for (final _ in ManagerDuty.values) true],
          ),
          FireManager(player, store: store),
          for (final growth in Growth.values)
            HireDirector(
              player,
              company: company,
              grade: content.directors!.grades.first.id,
              strategy: content.strategies.first.id,
              managerGrade: content.managers.grades.first.id,
              growth: growth,
              payout: true,
              borrows: true,
            ),
          FireDirector(player, company: company),
          RenameStore(player, store: store, name: 'Mail'),
          RenameCompany(player, company: company, name: 'Mail'),
          SetCushion(player, company: company, days: 14),
          ExpandStore(player, store: store),
          BuyStore(
            player,
            store: const StoreId(1),
            company: company,
            borrow: amount,
            termMonths: 84,
          ),
          SellStore(player, store: store),
          BuyCompany(
            player,
            company: const CompanyId(1),
            borrow: amount,
            termMonths: 84,
          ),
          BuyResearch(
            player,
            company: company,
            market: content.markets.first.id,
            tier: content.researchTiers.first.id,
          ),
          if (view.districts.firstOrNull case final district?) ...[
            OpenInDistrict(
              player,
              row: district.row,
              site: district.free.first.number,
              company: company,
              format: content.formats.first.id,
            ),
            BuyInDistrict(
              player,
              row: district.row,
              site: district.shops.first.site,
              company: company,
            ),
          ],
        ];
        for (final command in commands) {
          final text = describeCommand(command, content, view);
          expect(text, isNot(contains('{')), reason: '$command');
          expect(_rawKey.hasMatch(text), isFalse, reason: '$command');
        }
        final national = _nationalContent();
        final nationalView = SimulationController.newGame(
          national,
          seed: 7,
        ).view;
        for (final count in [1, 3]) {
          final command = OpenNational(
            player,
            company: company,
            country: national.countries.first.id,
            region: 0,
            format: national.formats.first.id,
            strategy: national.strategies.first.id,
            count: count,
            borrow: amount,
            termMonths: 60,
          );
          final text = describeCommand(command, national, nationalView);
          expect(text, isNot(contains('{')), reason: '$command');
          expect(text, contains(_firstRegion(national)), reason: '$command');
        }
      });

      test('everything a director writes leaves no blank', () {
        final content = _content();
        final game = SimulationController.newGame(content, seed: 7);
        final day = game.today;
        final site = content.sites.first.id;
        const store = StoreId(0);
        final format = content.formats.first.id;
        final amount = Money.parse('1234.50');
        final memos = <Memo>[
          ManagerHired(
            day,
            store: store,
            grade: content.managers.grades.first.id,
          ),
          StoreClosed(day, store: store, sales: amount, loss: amount),
          StoreClosed(day, store: store, sales: Money.zero, loss: amount),
          StoreEnlarged(day, store: store, cost: amount, borrowed: amount),
          StoreConverted(day, store: store, format: format, cost: amount),
          StoreOpened(
            day,
            site: site,
            format: format,
            cost: amount,
            paybackMonths: 18,
            borrowed: amount,
          ),
          StoreBought(day, store: store, price: amount, paybackMonths: 18),
          ProfitPaid(day, amount: amount),
          ProfitKept(day, site: site, needed: amount),
          ProfitKept(day, store: store, needed: amount),
          ProfitKept(day, needed: amount),
          for (final district in game.view.districts.take(1)) ...[
            DistrictOpened(
              day,
              row: district.row,
              site: district.shops.first.site,
              format: format,
              cost: amount,
              paybackMonths: 14,
              borrowed: amount,
            ),
            DistrictBought(
              day,
              row: district.row,
              site: district.shops.first.site,
              price: amount,
              paybackMonths: 14,
            ),
          ],
          // A district since woken.
          DistrictOpened(
            day,
            row: 0,
            site: 99,
            format: format,
            cost: amount,
            paybackMonths: 14,
          ),
        ];
        for (final memo in memos) {
          final text = memoSentence(memo, content, game.view);
          expect(text, isNot(contains('{')), reason: text);
          expect(_rawKey.hasMatch(text), isFalse, reason: text);
        }
        final national = _nationalContent();
        final nationalGame = SimulationController.newGame(national, seed: 7);
        final region = national.national!.countries
            .firstWhere((c) => c.key == national.countries.first.national)
            .regions
            .first;
        for (final count in [1, 2]) {
          final text = memoSentence(
            NationalOpened(
              day,
              country: national.countries.first.id,
              region: region.key,
              format: format,
              count: count,
              cost: amount,
              earns: amount,
              paybackMonths: 14,
              borrowed: amount,
            ),
            national,
            nationalGame.view,
          );
          expect(text, isNot(contains('{')), reason: text);
          expect(text, contains(region.name), reason: text);
        }
      });

      test('news in full leaves no blank', () {
        final content = _content();
        final game = _playedGame(content, days: 400);
        expect(game.alerts, isNotEmpty);
        for (final alert in game.alerts) {
          expect(alert.message, isNot(contains('{')), reason: alert.message);
          expect(alert.kind.label, isNot(contains('.')), reason: alert.message);
        }
      });
    });
  }

  test('a language lacking a file falls back on English', () {
    final partial = Strings(
      'xx',
      interface: const {},
      fallback: stringsFromFiles('en'),
    );
    useStrings(partial);
    addTearDown(() => useStrings(stringsFromFiles('en')));
    expect(tr('common.cancel'), 'Cancel');
    expect(money(Money.parse('1234.5')), '1,235');
  });

  test('the first language is the player\'s last choice', () async {
    final saves = MemorySaveSlots();
    expect(await saves.language(), isNull);
    await saves.setLanguage('fr');
    expect(await saves.language(), 'fr');
  });

  testWidgets('choosing a language on the menu changes the game\'s words', (
    tester,
  ) async {
    _useNarrowPhone(tester);
    final saves = MemorySaveSlots();
    await tester.pumpWidget(MarketGameApp(saves: saves, language: 'en'));
    for (var i = 0; i < 50 && find.text('New game').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('New game'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    for (
      var i = 0;
      i < 50 && find.text('Nouvelle partie').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Nouvelle partie'), findsOneWidget);
    expect(await tester.runAsync(saves.language), 'fr');

    await tester.tap(find.text('Nouvelle partie'));
    await tester.pumpAndSettle();
    // The scenario's words came with it.
    expect(find.text('Épicerie du Coin'), findsOneWidget);
    // Flutter's own words come over too: the way back is "Retour".
    expect(find.byTooltip('Retour'), findsOneWidget);
    useStrings(stringsFromFiles('en'));
  });
}
