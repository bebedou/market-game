import 'dart:io';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/app.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/financials.dart';
import 'package:market_game/src/format.dart';
import 'package:market_game/src/letters.dart';
import 'package:market_game/src/saves.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

void main() {
  testWidgets('the dashboard shows the holding, the date and what to do', (
    tester,
  ) async {
    await pumpGame(tester, newController());
    expect(find.text('Net worth 35,000'), findsWidgets);
    expect(find.text('1 company · 1 store · 1 city'), findsOneWidget);
    expect(find.text('Thu 1 Jan 2026'), findsOneWidget);
    expect(find.text('Your shelves are empty.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Your store'), 300);
    expect(find.text('Corner Shop'), findsWidgets);
  });

  testWidgets('the dashboard leads with the last four weeks and their trend', (
    tester,
  ) async {
    // A manager runs the store, so it trades from the first week.
    final game = newController()
      ..submit(
        HireManager(
          prototype.player,
          store: playerStore,
          grade: grade('expert'),
          strategy: strategy('balanced'),
          duties: [for (final _ in ManagerDuty.values) true],
        ),
      );
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    expect(find.text('Last 4 weeks'), findsOneWidget);
    expect(find.textContaining(RegExp('[▲▼] [0-9]+%')), findsOneWidget);
    expect(find.text('Trading profit, the last 10 weeks'), findsOneWidget);
  });

  testWidgets('the world tab shows competitors, cities and the economy', (
    tester,
  ) async {
    final game = newController();
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    // The country's economy on top.
    expect(find.text('France'), findsOneWidget);
    expect(find.text('Central bank rate'), findsOneWidget);
    expect(find.text('Unemployment'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Competitors'), 300);
    await openIndex(tester, 'Competitors');
    // The player's own company first, then rivals in Lyon.
    expect(find.text('Corner Shop'), findsWidgets);
    await tester.scrollUntilVisible(find.text('QuickStop Market'), 300);
    await goBack(tester);
    await openIndex(tester, 'Cities');
    await tester.scrollUntilVisible(find.text('Vacant sites'), 300);
    expect(find.text('Hénon metro'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Nantes, Rezé'), 300);
    expect(find.text('Montpellier, Boutonnet'), findsOneWidget);
    expect(find.text('Bordeaux, Chartrons'), findsOneWidget);
    await goBack(tester);
    // Back up to the economy, above the player's patch.
    await tester.scrollUntilVisible(
      find.widgetWithText(IndexRow, 'More on the economy'),
      -300,
    );
    await openIndex(tester, 'More on the economy');
    await tester.scrollUntilVisible(find.text('Economic history'), 300);
  });

  testWidgets('a city shows what its shoppers spend on each trade, and yours', (
    tester,
  ) async {
    // A manager runs the store, so it has sales to take a share with.
    final game = newController()
      ..submit(
        HireManager(
          prototype.player,
          store: playerStore,
          grade: grade('expert'),
          strategy: strategy('balanced'),
          duties: [for (final _ in ManagerDuty.values) true],
        ),
      );
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cities'), 300);
    await openIndex(tester, 'Cities');
    // Lyon, where the player trades, is open: its market by trade.
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Fine dining'), findsWidgets);
    expect(find.textContaining(RegExp(r'^yours [0-9]+%$')), findsOneWidget);
    expect(find.textContaining("A year, at today's prices"), findsWidgets);
    // No household counts any more.
    expect(find.textContaining(RegExp('[0-9] households')), findsNothing);
  });

  testWidgets('the world tab says where to open next, trade by trade', (
    tester,
  ) async {
    final game = newController();
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Your patch'), 300);
    expect(find.text('Corner Shop'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Where to open next'), 300);
    // Grocers to begin with, the player's own trade, in every city with room.
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Paris, Batignolles'), 300);
    expect(find.textContaining('3 rivals'), findsWidgets);
    // A burger bar's rivals are burger bars, however many grocers are there.
    await tester.scrollUntilVisible(find.text('Fast food'), -300);
    await tester.ensureVisible(find.text('Fast food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast food'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 rivals'), findsNothing);
    await tester.scrollUntilVisible(find.text('Bordeaux, Chartrons'), 300);
    await openIndex(tester, 'Bordeaux, Chartrons');
    expect(find.text('Fast food: a new shop'), findsOneWidget);
    expect(find.text('Best free site'), findsOneWidget);
    expect(find.textContaining('about 100%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Businesses'), 300);
    await tester.scrollUntilVisible(find.text('Vacant sites'), 300);
  });

  testWidgets('a neighbourhood asleep is in the list, and wakes', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(IndexRow, 'Lyon, Part-Dieu');
    await openIndex(tester, 'Lyon, Part-Dieu');
    expect(row, findsNothing);
    expect(find.text('Convenience store: a new shop'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining("you don't own"), 300);
    final markets = game.content.markets.length;
    final stores = game.view.shelves.length;
    game.wake(
      game.content.neighbourhoods.indexWhere(
        (r) => r.name == 'Lyon, Part-Dieu',
      ),
    );
    await tester.pumpAndSettle();
    expect(game.content.markets, hasLength(markets + 1));
    expect(game.view.shelves.length, greaterThan(stores));
    // The same page, from the game now.
    expect(find.textContaining("you don't own"), findsNothing);
    expect(find.text('Convenience store: a new shop'), findsOneWidget);
    // Nothing more to wake it for, and the game goes on.
    game.step();
    await tester.pump();
  });

  testWidgets('a neighbourhood asleep trades on, and says how it is doing', (
    tester,
  ) async {
    final game = newController();
    for (var day = 0; day < 100; day++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Lyon, Part-Dieu');
    final row = game.content.neighbourhoods.indexWhere(
      (r) => r.name == 'Lyon, Part-Dieu',
    );
    final shop = game.sleeper(row)!.shops.first;
    expect(shop.sales, isNotEmpty);
    await tester.scrollUntilVisible(find.text(shop.name), 300);
    expect(find.textContaining('a year'), findsWidgets);
  });

  testWidgets('opening on a site asleep wakes its neighbourhood', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Lyon, Part-Dieu');
    final markets = game.content.markets.length;
    final open = find.widgetWithText(OutlinedButton, 'Open').first;
    await tester.scrollUntilVisible(open, 300);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    // Still asleep while the player makes up their mind.
    expect(game.content.markets, hasLength(markets));
    await tester.enterText(find.byType(TextField).last, '20000');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(game.content.markets, hasLength(markets + 1));
    final woken = game.content.markets.last;
    expect(woken.name, 'Lyon, Part-Dieu');
    game.step();
    await tester.pump();
    final mine = {for (final company in game.view.companies) company.id};
    expect(
      game.view.shelves.where(
        (shelf) => shelf.market == woken.id && mine.contains(shelf.company),
      ),
      hasLength(1),
    );
  });

  testWidgets('a brand is created in the holding and names a shop opened '
      'under it', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openIndex(tester, 'Create a brand');
    await tester.enterText(find.byType(TextField), 'Coin Malin');
    await tester.pump();
    await tester.tap(find.text('Create brand'));
    await tester.pumpAndSettle();
    // There at once, for a shop to open under it today.
    expect(game.myBrands.single.name, 'Coin Malin');
    await scrollTo(tester, find.widgetWithText(IndexRow, 'Coin Malin'));
    expect(find.text('Convenience store · 0 stores'), findsOneWidget);
    // A second of the same name isn't allowed.
    await openIndex(tester, 'Create a brand');
    await tester.enterText(find.byType(TextField), 'coin malin');
    await tester.pump();
    expect(find.text('That name is taken'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Lyon, Part-Dieu');
    final open = find.widgetWithText(OutlinedButton, 'Open').first;
    await tester.scrollUntilVisible(open, 300);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    // The brand is picked, so the shop is named after it, not by hand.
    expect(find.text('Named Coin Malin Part-Dieu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Store name'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '20000');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    game.step();
    await tester.pump();
    final store = game.myStores.last.$2;
    expect(game.view.shelves[store.id.index].name, 'Coin Malin Part-Dieu');
    expect(game.myBrands.single.shops, 1);
  });

  testWidgets('a chain\'s shops in districts are among its stores', (
    tester,
  ) async {
    final game = newController();
    final chain = PersonId(
      prototype.persons.indexWhere((p) => p.key == 'owner_quickstop'),
    );
    final company = CompanyId(
      prototype.companies.indexWhere((c) => c.key == 'quickstop'),
    );
    final district = game.view.districts.firstWhere(
      (d) => d.name == 'Lyon, Part-Dieu',
    );
    final site = district.free.firstWhere((site) => site.area >= 100);
    game
      ..submit(
        OpenInDistrict(
          chain,
          row: district.row,
          site: site.number,
          company: company,
          format: format('grocery'),
          capital: Money.parse('30000.00'),
        ),
      )
      ..step();
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Competitors'), 300);
    await openIndex(tester, 'Competitors');
    final tile = find.text('QuickStop Market').first;
    await tester.scrollUntilVisible(tile, 300);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('QuickStop Market Part-Dieu'),
      300,
    );
    expect(find.text('Convenience store, Lyon, Part-Dieu'), findsOneWidget);
  });

  testWidgets('with the cities asleep, only the home city is in play, and '
      'another wakes with its own businesses', (tester) async {
    final game = SimulationController.newGame(
      prototype,
      seed: 7,
      citiesAsleep: true,
    );
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Show all'), 300);
    await tester.ensureVisible(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show all'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Paris, Batignolles');
    await tester.scrollUntilVisible(find.text('Maison Lemercier'), 300);
    expect(find.text('Steak & Co'), findsOneWidget);
    expect(game.content.markets.single.name, 'Lyon, Croix-Rousse');
    game.wake(
      game.content.neighbourhoods.indexWhere(
        (row) => row.name == 'Paris, Batignolles',
      ),
    );
    await tester.pumpAndSettle();
    expect(game.content.markets.last.name, 'Paris, Batignolles');
    expect(
      game.view.shelves.map((shelf) => shelf.name),
      contains('Maison Lemercier'),
    );
    game.step();
    await tester.pump();
  });

  testWidgets('the finance tab shows the accounts and the taxes', (
    tester,
  ) async {
    final game = newController();
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(find.text('Free to spend'), findsOneWidget);
    await openIndex(tester, 'Corner Shop');
    expect(find.text('Free cash'), findsOneWidget);
    expect(find.text('Borrow'), findsOneWidget);
    expect(find.text('Cushion'), findsOneWidget);
    await scrollTo(tester, find.text('Change'));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Cash cushion'), findsOneWidget);
    await tester.tap(find.text('4 weeks'));
    await tester.pump();
    await tester.tap(find.text('Keep 4 weeks of wages'));
    await tester.pumpAndSettle();
    final cushion = game.pending.single as SetCushion;
    expect(cushion.days, 28);
    expect(game.cushionDays(game.view.companies.single), 28);
    await goBack(tester);
    await openIndex(tester, 'Taxes');
    expect(find.text('Tax due next January'), findsOneWidget);
    await goBack(tester);
    expect(find.text('Going cheap'), findsOneWidget);
  });

  testWidgets('each store has a card that opens it, and the title switches '
      'stores', (tester) async {
    final game = newController();
    openSecondStore(game);
    game.step();
    await pumpGame(tester, game);
    expect(find.text('2 companies · 2 stores · 1 city'), findsOneWidget);
    // The new company is named after its store: the company is listed first.
    await scrollTo(tester, find.text('Your stores'));
    final row = find.widgetWithText(IndexRow, 'Mail Market').last;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(game.store?.id, game.myStores.last.$2.id);
    expect(find.text('Rename the store'), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('Your stores'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Corner Shop'));
    await tester.pumpAndSettle();
    expect(game.store?.id, playerStore);
  });

  testWidgets('a price set in the store waits for tomorrow', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Value Milk 1 L'), 300);
    await tester.ensureVisible(find.text('Value Milk 1 L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Value Milk 1 L'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0,99');
    await tester.tap(find.text('Set price'));
    await tester.pumpAndSettle();
    expect(find.text('1 change takes effect tomorrow'), findsOneWidget);
    expect(game.priceOf(game.store!, product('milk_budget')), Money(99));

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(
      find.text('Price Value Milk 1 L at 0.99 in Corner Shop'),
      findsOneWidget,
    );
  });

  testWidgets('staffing a slot is a pending change', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    await openIndex(tester, 'Staff and opening hours');
    await tester.scrollUntilVisible(find.text('Night'), 200);
    await tester.ensureVisible(find.text('Night'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More').last); // the night slot
    await tester.pump();
    expect(game.staffOf(game.store!), [1, 1, 2, 1]);
  });

  testWidgets('an order placed from a supplier arrives on the way list', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplies'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Order').first);
    await tester.pumpAndSettle();
    expect(find.text('Order from BulkWay Cash & Carry'), findsOneWidget);
    await tester.tap(find.textContaining('Suggest'));
    await tester.pump();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    final order = game.pending.single as PlaceOrder;
    expect(order.supplier, supplier('bulkway'));
    // A week of what a new store sells, 30 a day, in boxes of 48; bread
    // keeps four days.
    expect(order.lines.map((line) => line.quantity), [
      240, 240, 144, 144, 240, 240, //
    ]);

    game.step();
    await tester.pumpAndSettle();
    await openIndex(tester, 'On the way');
    expect(
      find.textContaining('BulkWay Cash & Carry, arriving'),
      findsOneWidget,
    );
  });

  testWidgets('play runs the clock and pause stops it', (tester) async {
    final game = newController()..pauseOn.clear();
    await pumpGame(tester, game);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(game.today, prototype.startDay + 2);
    expect(find.text('Sat 3 Jan 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 3));
    expect(game.today, prototype.startDay + 2);
  });

  testWidgets('reports explain the week', (tester) async {
    final game = newController();
    game.submit(
      PlaceOrder(
        prototype.player,
        store: playerStore,
        supplier: supplier('freshline'),
        lines: [
          (product: product('milk_budget'), quantity: 60),
          (product: product('bread_budget'), quantity: 36),
        ],
      ),
    );
    for (var i = 0; i < 18; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    expect(find.text('Week of 12 Jan'), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
    expect(find.textContaining('Profit '), findsWidgets);
    await tester.tap(find.byTooltip('Earlier'));
    await tester.pumpAndSettle();
    expect(find.text('Week of 5 Jan'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Profit and loss'), 300);
    await tester.scrollUntilVisible(find.text('Shoppers at Corner Shop'), 300);
    await tester.scrollUntilVisible(find.text('Market research'), 300);

    await tester.dragUntilVisible(
      find.text('Month'),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.ensureVisible(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('January 2026'), findsOneWidget);
  });

  testWidgets('research bought for the city picked shows up as a study', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Market research');
    await tester.scrollUntilVisible(find.text('Quick survey'), 300);
    await tester.tap(find.text('Lyon, Croix-Rousse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bordeaux, Chartrons').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Buy').first);
    await tester.pump();
    expect(game.pending.single, isA<BuyResearch>());
    expect((game.pending.single as BuyResearch).market, MarketId(2));
    game.step();
    await tester.pump();
    await tester.scrollUntilVisible(find.textContaining('Quick survey, '), 300);
    expect(find.text('Bordeaux, Chartrons, ±30%'), findsOneWidget);
  });

  testWidgets('the app loads the bundled scenario', (tester) async {
    final content = (await tester.runAsync(loadContent))!;
    expect(content.fingerprint, prototype.fingerprint);
  });

  testWidgets('a director can be let borrow, when they may open or buy '
      'stores', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Corner Shop');
    await scrollTo(tester, find.text('Hire a director'));
    await tester.tap(find.text('Hire a director'));
    await tester.pumpAndSettle();
    expect(find.text('Borrow when it is short'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('The profit'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Also buy struggling rivals'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Borrow when it is short'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never on your guarantee'), findsOneWidget);
    expect(find.textContaining('buy profitable rivals'), findsOneWidget);
    await tester.tap(find.text('Borrow when it is short'));
    await tester.pump();
    await tester.tap(find.text('Hire for 420 a month'));
    await tester.pumpAndSettle();
    final hire = game.pending.single as HireDirector;
    expect(hire.growth, Growth.buy);
    expect(hire.borrows, isTrue);
    expect(
      find.textContaining('borrowing when it is short, sends you'),
      findsOneWidget,
    );
  });

  test('a director says what they borrowed', () {
    final game = newController();
    final sentence = memoSentence(
      StoreBought(
        game.today,
        store: const StoreId(1),
        price: Money.parse('80000.00'),
        paybackMonths: 40,
        borrowed: Money.parse('60000.00'),
      ),
      prototype,
      game.view,
    );
    expect(
      sentence,
      endsWith('I borrowed 60,000 for it on our earnings, over 7 years.'),
    );
  });

  testWidgets('the saved games say when they were last played, and can be '
      'deleted', (tester) async {
    final saves = MemorySaveSlots();
    saves.stores[0]
      ..file = SaveFile(Uint8List.fromList([1, 2, 3]))
      ..summary = (
        company: 'Corner Shop',
        day: prototype.startDay,
        netWorth: Money.parse('35000.00'),
        saved: DateTime(2026, 11, 4, 18, 30),
      );
    saves.stores[1].file = SaveFile(Uint8List.fromList([4, 5, 6]));
    await pumpMenu(tester, saves);
    expect(find.textContaining('Last played on 4 Nov 2026'), findsOneWidget);
    expect(find.byTooltip('Delete this game'), findsNWidgets(2));
    expect(find.text('Empty'), findsOneWidget);

    // Asked first: cancelling keeps the game.
    await tester.tap(find.byTooltip('Delete this game').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Corner Shop?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves.stores[0].file, isNotNull);

    await tester.tap(find.byTooltip('Delete this game').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(saves.stores[0].file, isNull);
    expect(saves.stores[0].summary, isNull);
    expect(find.text('Empty'), findsNWidgets(2));
    expect(find.text('Corner Shop'), findsNothing);
    expect(find.byTooltip('Delete this game'), findsOneWidget);

    // The last one goes without a summary to name it; then there is nothing
    // to continue.
    await tester.tap(find.byTooltip('Delete this game'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this game?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Empty'), findsNWidgets(3));
    expect(find.textContaining('Continue'), findsNothing);
  });

  testWidgets('the main menu sets up a new game where the player chooses, '
      'saves it in a slot and continues it', (tester) async {
    final saves = MemorySaveSlots();
    await pumpMenu(tester, saves);
    expect(find.text('Empty'), findsNWidgets(3));
    expect(find.textContaining('Continue'), findsNothing);
    await tester.tap(find.text('New game'));
    await tester.pumpAndSettle();
    expect(find.text('Corner Shop'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Burger Lab');
    await tester.tap(find.text('Montpellier, Boutonnet'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Arceaux corner'));
    await tester.tap(find.text('Arceaux corner'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Fast food'));
    await tester.tap(find.text('Fast food'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Start'));
    // 18,000 × 1.6 to fit out leaves the company 16,200.
    expect(find.text('16,200'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Your holding'), findsOneWidget);
    expect(saves.stores[0].summary?.company, 'Burger Lab');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main menu'));
    await tester.pumpAndSettle();
    expect(find.text('Continue · Burger Lab, Thu 1 Jan 2026'), findsOneWidget);
    expect(find.text('Empty'), findsNWidgets(2));
    await tester.tap(find.textContaining('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your holding'), findsOneWidget);
  });

  testWidgets('a game that cannot be loaded is set aside and frees its slot', (
    tester,
  ) async {
    final saves = MemorySaveSlots();
    final old = SaveFile(Uint8List.fromList([1, 2, 3]));
    saves.stores[1].file = old;
    await pumpMenu(tester, saves);
    expect(find.text('From an earlier version'), findsOneWidget);
    await tester.tap(find.text('Saved game'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(saves.stores[1].setAsideFiles, [old]);
    expect(find.text('Empty'), findsNWidgets(3));
  });

  testWidgets('how to play explains buying businesses', (tester) async {
    await pumpMenu(tester, MemorySaveSlots());
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Buying and selling businesses'),
      300,
    );
  });

  testWidgets('a rival store is bought from the market tab', (tester) async {
    final game = newController();
    game
      ..submit(
        InjectCapital(
          prototype.player,
          company: playerCompany,
          amount: game.view.cash,
        ),
      )
      ..step();
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Competitors');
    final tile = find.widgetWithText(ExpansionTile, 'Le Comptoir Étudiant');
    await scrollTo(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Buy the company'), findsOneWidget);
    await scrollTo(tester, find.widgetWithText(TextButton, 'Buy'));
    await tester.tap(find.widgetWithText(TextButton, 'Buy'));
    await tester.pumpAndSettle();
    expect(find.text('Buy Le Comptoir Étudiant?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Buy'));
    await tester.pumpAndSettle();
    expect(game.pending.single, isA<BuyStore>());
    game.step();
    expect(game.myStores, hasLength(2));
  });

  testWidgets('a rival store is bought with a loan that keeps the '
      "company's cushion", (tester) async {
    // A manager runs the shop, so it has earnings the bank lends on.
    final game = newController()
      ..submit(
        HireManager(
          prototype.player,
          store: playerStore,
          grade: grade('expert'),
          strategy: strategy('balanced'),
          duties: [for (final _ in ManagerDuty.values) true],
        ),
      );
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Competitors');
    final tile = find.widgetWithText(ExpansionTile, 'Le Comptoir Étudiant');
    await scrollTo(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // Its store loses money, so the company can't borrow on its earnings.
    expect(find.textContaining('borrowed on its own earnings'), findsNothing);
    expect(find.textContaining('Paid from your own cash: you need'), findsOne);
    await scrollTo(tester, find.widgetWithText(TextButton, 'Buy'));
    await tester.tap(find.widgetWithText(TextButton, 'Buy'));
    await tester.pumpAndSettle();
    // Losing money, it sells cheap: the company could pay, but borrowing
    // keeps its cash cushion.
    expect(find.text('To keep its cash cushion'), findsOneWidget);
    expect(find.text('Borrow the rest'), findsNothing);
    await tester.tap(find.text('Borrow from the bank'));
    await tester.pumpAndSettle();
    expect(find.text('Borrow the rest'), findsOneWidget);
    expect(find.text('Buy with a loan'), findsOneWidget);
    await tester.ensureVisible(find.text('5 years'));
    await tester.tap(find.text('5 years'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Buy with a loan'));
    await tester.pumpAndSettle();
    final buy = game.pending.single as BuyStore;
    expect(buy.borrow.cents, greaterThan(0));
    expect(buy.termMonths, 60);
    game.step();
    expect(game.myStores, hasLength(2));
    expect(game.view.companies.single.loans, isNotEmpty);
  });

  testWidgets('the bank says what it lends, and the borrow sheet keeps to '
      'it', (tester) async {
    final game = newController();
    for (var i = 0; i < 70; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Corner Shop');
    // The shelves are empty, so the store earns nothing to lend on.
    expect(find.text('The bank lends'), findsOneWidget);
    expect(find.text('up to 40,000'), findsOneWidget);
    expect(find.textContaining('Only if you guarantee it'), findsOneWidget);
    await scrollTo(tester, find.text('Borrow'));
    await tester.tap(find.text('Borrow'));
    await tester.pumpAndSettle();
    expect(find.text('Borrow from the bank'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '50000');
    await tester.pump();
    expect(find.textContaining('More than the bank lends'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12000');
    await tester.pump();
    await tester.tap(find.text('3 years'));
    await tester.pump();
    await tester.tap(find.text('Ask the bank'));
    await tester.pumpAndSettle();
    final loan = game.pending.single as TakeLoan;
    expect(
      (loan.amount, loan.termMonths, loan.guarantee),
      (Money.parse('12000.00'), 36, true),
    );
  });

  testWidgets('a store is sold from its screen to the chain that can pay', (
    tester,
  ) async {
    final game = newController();
    for (var i = 0; i < 30; i++) {
      game.step();
    }
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Sell your store');
    await scrollTo(tester, find.text('Sell Corner Shop'));
    await scrollTo(tester, find.textContaining('Sell to '));
    expect(find.text('Asking price'), findsOneWidget);
    await tester.tap(find.textContaining('Sell to '));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sell'));
    await tester.pumpAndSettle();
    expect(game.pending.single, isA<SellStore>());
    game.step();
    expect(game.myStores, isEmpty);
  });

  testWidgets('the game sits 5% in from the top and bottom', (tester) async {
    await pumpGame(tester, newController());
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final scaffold = tester.getRect(find.byType(Scaffold).first);
    expect(scaffold.top, closeTo(height * 0.05, 0.5));
    expect(scaffold.bottom, closeTo(height * 0.95, 0.5));
  });

  testWidgets('a manager is hired from the store and takes over prices', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    await openIndex(tester, 'Manager');
    await tester.scrollUntilVisible(find.text('Hire a manager'), 200);
    await tester.ensureVisible(find.text('Hire a manager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hire a manager'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Experienced ·'), findsOneWidget);
    await tester.tap(find.textContaining('Discount and volume'));
    await tester.pump();
    await tester.tap(find.text('Hire'));
    await tester.pumpAndSettle();
    final hire = game.pending.single as HireManager;
    expect(hire.grade, grade('experienced'));
    expect(hire.strategy, strategy('discount'));
    expect(hire.duties, [true, true, false, false, false]);

    game.step();
    await tester.pump();
    expect(find.text('Experienced manager'), findsOneWidget);
    expect(
      find.text('Looks after: reorder stock, set prices and marketing.'),
      findsOneWidget,
    );
    await goBack(tester);
    await tester.tap(find.text('Shelves'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Value Milk 1 L'), 300);
    expect(find.text('Priced by your manager'), findsWidgets);
    await tester.ensureVisible(find.text('Value Milk 1 L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Value Milk 1 L'));
    await tester.pumpAndSettle();
    expect(find.text('Set price'), findsNothing);
  });

  testWidgets('a director is hired from the company and writes each month', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Corner Shop');
    await scrollTo(tester, find.text('Hire a director'));
    await tester.tap(find.text('Hire a director'));
    await tester.pumpAndSettle();
    expect(find.text('Seasoned director · 420 a month'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('The profit'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Also open new stores'));
    await tester.pump();
    await tester.tap(find.text('Hire for 420 a month'));
    await tester.pumpAndSettle();
    final hire = game.pending.single as HireDirector;
    expect(hire.growth, Growth.open);
    expect(hire.payout, isTrue);
    expect(hire.managerGrade, grade('experienced'));
    expect(hire.strategy, strategy('balanced'));
    expect(
      find.text(
        'Grows it by opening new stores, sends you the profit each month, '
        'and hires experienced managers, balanced.',
      ),
      findsOneWidget,
    );

    // The next day they hire a manager for the store, and say so.
    game
      ..step()
      ..step();
    expect(
      game.alerts.first.message,
      'Director of Corner Shop: I hired an experienced manager for Corner '
      'Shop.',
    );
    expect(game.alerts.first.kind, AlertKind.director);
    await tester.pump();
    await scrollTo(tester, find.text('Your director'));
    expect(find.text('January 2026'), findsOneWidget);
    expect(
      find.text('I hired an experienced manager for Corner Shop.'),
      findsOneWidget,
    );
  });

  testWidgets('the holding shows the company and who runs it, and hires a '
      'director', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await scrollTo(tester, find.text('Your company'));
    expect(find.text('1 store · no director'), findsOneWidget);
    await openIndex(tester, 'Hire a director');
    expect(find.text('Seasoned director · 420 a month'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('The profit'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Hire for 420 a month'));
    await tester.pumpAndSettle();
    expect(game.pending.single, isA<HireDirector>());
    expect(find.text('1 store · run by a seasoned director'), findsOneWidget);
    expect(find.widgetWithText(IndexRow, 'Hire a director'), findsNothing);
  });

  testWidgets("a director's sheet says when discounting pays", (tester) async {
    await pumpGame(tester, newController());
    await openIndex(tester, 'Hire a director');
    final chip = find.widgetWithText(ChoiceChip, 'Discount and volume');
    await tester.scrollUntilVisible(
      chip,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.textContaining("a supermarket's volume"), findsOneWidget);
  });

  testWidgets('the holding opens each company at who runs it', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await scrollTo(tester, find.text('Your company'));
    await tester.tap(find.text('1 store · no director'));
    await tester.pumpAndSettle();
    expect(find.text('Director'), findsOneWidget);
    expect(find.text('Hire a director'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('a subsidiary is started from the holding as a company of its '
      'own', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openIndex(tester, 'Start a subsidiary');
    expect(find.textContaining('if it fails, the rest is safe'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Rue du Mail'), 300);
    await tester.ensureVisible(find.text('Rue du Mail'));
    await tester.pumpAndSettle();
    final site = find.ancestor(
      of: find.text('Rue du Mail'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: site,
        matching: find.widgetWithText(OutlinedButton, 'Open'),
      ),
    );
    await tester.pumpAndSettle();
    final choice = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'As a new company'),
    );
    expect(choice.value, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField, 'Capital from your cash'),
      '20000',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Open').last);
    await tester.pumpAndSettle();
    expect((game.pending.single as OpenStore).company, isNull);

    game.step();
    await tester.pump();
    await goBack(tester);
    await scrollTo(tester, find.text('Your companies'));
    expect(find.text('Rue du Mail Store'), findsWidgets);
    expect(find.textContaining('Hire a director for'), findsNWidgets(2));
  });

  testWidgets('a supermarket takes a manager of any grocery stance, and its '
      'first order is forecast', (tester) async {
    final rich = loadScenario(
      File(
        '../content/scenarios/prototype.json',
      ).readAsStringSync().replaceFirst(
        '"owner": "player", "cash": "15000.00"',
        '"owner": "player", "cash": "90000.00"',
      ),
    );
    final game = SimulationController.newGame(rich, seed: 7)
      ..submit(
        ConvertStore(
          rich.player,
          store: playerStore,
          format: rich.formats.firstWhere((f) => f.key == 'supermarket').id,
        ),
      );
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    expect(rich.formats[game.store!.format.index].key, 'supermarket');
    await pumpGame(tester, game);
    await openRunning(tester);
    await openIndex(tester, 'Manager');
    await tester.scrollUntilVisible(find.text('Hire a manager'), 200);
    await tester.ensureVisible(find.text('Hire a manager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hire a manager'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining("a supermarket's volume"), findsOneWidget);
    await tester.tap(find.textContaining('Discount and volume'));
    await tester.pump();
    await tester.tap(find.text('Hire'));
    await tester.pumpAndSettle();
    final hire = game.pending.single as HireManager;
    expect(rich.strategies[hire.strategy.index].key, 'discount');
  });

  testWidgets('a new business is started from the holding: a restaurant on '
      'any site, its format picked', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openIndex(tester, 'Start a new business');
    expect(
      find.widgetWithText(ChoiceChip, 'Lyon, Croix-Rousse'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Montée de la Grande-Côte'), 300);
    await tester.ensureVisible(find.text('Montée de la Grande-Côte'));
    await tester.pumpAndSettle();
    final site = find.ancestor(
      of: find.text('Montée de la Grande-Côte'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: site,
        matching: find.widgetWithText(OutlinedButton, 'Open'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Fitting out costs 20,000 and takes 28 days. Budget '
        'for stock, staff and rent too.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Fast food'));
    await tester.pumpAndSettle();
    // A fast food costs 1.6 times the site's fitting out.
    expect(find.textContaining('Fitting out costs 32,000'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Capital from your cash'),
      '17000',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Open').last);
    await tester.pumpAndSettle();
    final opening = game.pending.single as OpenStore;
    expect(prototype.formats[opening.format.index].key, 'fastfood');
  });

  testWidgets('marketing is set with a slider and waits for tomorrow', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    await openIndex(tester, 'Marketing');
    await tester.scrollUntilVisible(find.text('No marketing'), 300);
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    final marketing = game.pending.single as SetMarketing;
    expect(marketing.store, playerStore);
    expect(marketing.share.raw, greaterThan(0));
    expect(game.marketingOf(game.store!), marketing.share);
    // What each share costs and builds up to.
    await scrollTo(tester, find.text('12% of sales'));
    expect(find.text('5% of sales'), findsOneWidget);
    await goBack(tester);
    await openIndex(tester, 'Reputation');
    expect(find.textContaining('A new store starts at 75%'), findsOneWidget);
  });

  testWidgets('a restaurant lists dishes, not groceries', (tester) async {
    final game = newController()
      ..submit(
        OpenStore(
          prototype.player,
          site: prototype.sites
              .firstWhere((s) => s.key == 'lyon_grandecote')
              .id,
          name: 'Chez Rayan',
          company: playerCompany,
          capital: Money.parse('17000.00'),
          format: prototype.formats.firstWhere((f) => f.key == 'fastfood').id,
        ),
      );
    game.step();
    game.selectStore(game.myStores.last.$2.id);
    await pumpGame(tester, game);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Burger menu'), 300);
    expect(find.text('Value Milk 1 L'), findsNothing);
  });

  testWidgets('the store offers to become a supermarket once affordable', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    await openIndex(tester, 'Become a supermarket');
    // A supermarket costs 1.8 times the 30,000 fit-out, so 24,000 more, and
    // 100 m² of works at 150.00 to reach its 220 m².
    expect(find.text('39,000'), findsOneWidget);
    expect(
      find.text('You need 24,000 more free cash in the company'),
      findsOneWidget,
    );
    final convert = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Convert to a supermarket'),
    );
    expect(convert.onPressed, isNull);
  });

  testWidgets('the store is enlarged from its header', (tester) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    expect(find.text('120 m²'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Enlarge'));
    await tester.pumpAndSettle();
    expect(find.text('Enlarge to 160 m²?'), findsOneWidget);
    expect(find.text('6,000'), findsOneWidget); // 40 m² at 150.00
    // Rent of 880 and overheads of 6.00 a m² for 160 m²; 1,380 for 120 m².
    expect(find.text('1,840 a month'), findsOneWidget);
    expect(find.text('Now 1,380'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Enlarge'));
    await tester.pumpAndSettle();
    expect(game.pending.single, isA<ExpandStore>());
    expect(find.text('Works start tomorrow'), findsOneWidget);

    game.step();
    await tester.pump();
    expect(find.text('Growing to 160 m², ready 15 Jan'), findsOneWidget);
  });

  testWidgets('the store and its company are renamed from the store', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await openRunning(tester);
    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename the store'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chez Rayan');
    await tester.pump();
    expect(find.text('Rename the company too'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(game.pending.map((c) => c.runtimeType), [
      RenameStore,
      RenameCompany,
    ]);
    // In the title, and in the store's header from tomorrow.
    expect(find.text('Chez Rayan'), findsOneWidget);
    expect(find.text('Chez Rayan (from tomorrow)'), findsOneWidget);

    game.step();
    await tester.pump();
    expect(game.view.companyNames[playerCompany.index], 'Chez Rayan');
    expect(find.text('Chez Rayan'), findsWidgets);
  });

  testWidgets('a company with years behind it shows its real figures', (
    tester,
  ) async {
    final game = managedGame(days: 800);
    final company = game.view.companies.single;
    final months = game.reports(ReportPeriod.month, company: company.id);
    final complete = months.where((month) => month.complete).toList();
    final year = complete.sublist(complete.length - 12);
    final financials = financialsOf(game, [company]);
    final recent = financials.recent!;
    Money total(Money Function(PeriodReport) line) =>
        year.fold(Money.zero, (sum, month) => sum + line(month));

    // The statement adds up to what the books say.
    expect(financials.young, isFalse);
    expect(recent.months, 12);
    expect(recent.sales, -total((m) => m.flow(AccountKind.revenue)));
    expect(recent.net, total((m) => m.profit));
    expect(financials.before!.months, complete.length - 12);
    expect(recent.sales.cents, greaterThan(0));
    // The fit-out, works, stock and bills tied up, not the books' capital.
    expect(financials.fitOut >= Money.parse('30000.00'), isTrue);
    expect(
      recent.roic!.raw,
      ((recent.operating - recent.tax).cents *
              365 /
              recent.days *
              Fx.scale /
              recent.capital.cents)
          .round(),
    );

    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, game.companyName(company.id));
    expect(
      find.text('Last 12 months, against the year before'),
      findsOneWidget,
    );
    expect(find.text(money(recent.sales, cents: false)), findsOneWidget);
    expect(find.text(percent(recent.operatingMargin!)), findsOneWidget);
    expect(find.text(percent(recent.netMargin!)), findsOneWidget);
    expect(find.text(percent(recent.roic!, decimals: 0)), findsOneWidget);
    expect(find.textContaining('No wear is taken off'), findsOneWidget);
    expect(find.text('Net profit each year'), findsOneWidget);

    await openIndex(tester, 'Profit and loss');
    for (final line in ['Gross profit', 'Operating profit', 'Net profit']) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text(money(recent.gross, cents: false)), findsOneWidget);
    expect(find.text(money(recent.operating, cents: false)), findsOneWidget);
    expect(find.text(money(recent.net, cents: false)), findsOneWidget);
    expect(find.textContaining('scaled to twelve'), findsOneWidget);
    await goBack(tester);

    await openIndex(tester, 'Balance sheet');
    expect(find.text(money(company.netAssets)), findsOneWidget);
    expect(find.text(money(financials.capital)), findsOneWidget);
    await goBack(tester);

    await openIndex(tester, 'Year by year');
    final filed = game.view.filings.singleWhere(
      (filing) => filing.company == company.id && filing.year == 2026,
    );
    expect(find.text(money(filed.revenue, cents: false)), findsOneWidget);
    expect(find.text(signedMoney(filed.profit, cents: false)), findsOneWidget);
    expect(find.text('2028*'), findsNWidgets(2));
    expect(find.text('* The year so far.'), findsOneWidget);
    expect(find.text('Margins and ROIC'), findsOneWidget);
  });

  testWidgets('a brand-new company has no figures, then no ROIC yet', (
    tester,
  ) async {
    final game = newController();
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, game.companyName(playerCompany));
    expect(find.text('Financials'), findsOneWidget);
    expect(find.textContaining('Nothing yet'), findsOneWidget);
    expect(find.text('Profit and loss'), findsNothing);

    game.step();
    await tester.pumpAndSettle();
    final recent = financialsOf(game, game.view.companies).recent!;
    expect(recent.sales, Money.zero);
    expect(recent.netMargin, isNull);
    expect(recent.roic, isNull);
    expect(find.text('Since founding: 1 day'), findsOneWidget);
    expect(find.text('–'), findsNWidgets(3));
    expect(
      find.text('ROIC shows after three months of trading.'),
      findsOneWidget,
    );
    await openIndex(tester, 'Profit and loss');
    expect(find.text('Net profit'), findsOneWidget);
    await goBack(tester);
    await openIndex(tester, 'Year by year');
    expect(find.text('2026*'), findsNWidgets(2));
  });

  testWidgets('a young company shows its months at a year\'s rate', (
    tester,
  ) async {
    final game = managedGame(days: 200);
    final financials = financialsOf(game, game.view.companies);
    final recent = financials.recent!;
    expect(financials.young, isTrue);
    expect(financials.before, isNull);
    expect(recent.days, 200);
    expect(recent.roic, isNotNull);
    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, game.companyName(playerCompany));
    expect(find.text('Since founding: 7 months'), findsOneWidget);
    expect(find.text("ROIC, a year's rate"), findsOneWidget);
  });

  testWidgets('a liquidated company keeps its figures, without a ROIC', (
    tester,
  ) async {
    // Nobody runs the store, so the company soon can't pay.
    final game = newController();
    for (var i = 0; i < 2000; i++) {
      if (game.view.companies.single.status != CompanyStatus.active) break;
      game.step();
    }
    final company = game.view.companies.single;
    expect(company.status, CompanyStatus.liquidated);
    final financials = financialsOf(game, [company]);
    final recent = financials.recent!;
    expect(financials.before, isNull);
    expect(recent.roic, isNull);
    expect(
      recent.net,
      game
          .reports(ReportPeriod.month, company: company.id)
          .fold(Money.zero, (sum, month) => sum + month.profit),
    );

    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, game.companyName(company.id));
    expect(find.textContaining('nothing tied up, so no ROIC'), findsOneWidget);
    await openIndex(tester, 'Balance sheet');
    expect(find.text('Net assets'), findsOneWidget);
    expect(find.text('Money tied up'), findsNothing);
  });

  testWidgets('the holding adds its companies up', (tester) async {
    final game = newController();
    openSecondStore(game);
    game.step();
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    final companies = game.view.companies;
    expect(companies, hasLength(2));
    final together = financialsOf(game, companies);
    final apart = [
      for (final company in companies) financialsOf(game, [company]),
    ];
    expect(together.fitOut, apart[0].fitOut + apart[1].fitOut);
    expect(together.capital, apart[0].capital + apart[1].capital);
    expect(together.netAssets, apart[0].netAssets + apart[1].netAssets);
    expect(together.recent!.net, apart[0].recent!.net + apart[1].recent!.net);

    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'All your companies');
    expect(find.textContaining('every company added up'), findsOneWidget);
    expect(find.text('Operating margin'), findsOneWidget);
    await openIndex(tester, 'Balance sheet');
    expect(find.text(money(together.netAssets)), findsWidgets);
  });

  test('the first fit-out is counted as it began, whatever came of it', () {
    final spot = prototype.sites[mill.index].openingCost;
    final diner = format('fastfood');
    final started = SimulationController.newGame(
      prototype,
      seed: 7,
      start: GameStart(site: mill, format: diner, name: 'Chez Rayan'),
    );
    expect(
      financialsOf(started, started.view.companies).fitOut,
      spot.times(prototype.formats[diner.index].fitOut),
    );

    final game = managedGame(days: 400);
    final first = Money.parse('30000.00');
    var company = game.view.companies.single;
    expect(
      financialsOf(game, [company]).fitOut,
      first + company.balance(AccountKind.openingCosts),
    );
    game
      ..submit(
        InjectCapital(
          prototype.player,
          company: company.id,
          amount: game.view.cash,
        ),
      )
      ..submit(
        ConvertStore(
          prototype.player,
          store: playerStore,
          format: format('supermarket'),
        ),
      );
    // The store changes once the works are done.
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    company = game.view.companies.single;
    expect(company.stores.single.format, format('supermarket'));
    expect(
      financialsOf(game, [company]).fitOut,
      first + company.balance(AccountKind.openingCosts),
    );
  });

  test('ROIC needs time and money tied up, and may be negative', () {
    Results results({
      int days = 365,
      String sales = '100000.00',
      String capital = '50000.00',
    }) => Results(
      months: 12,
      days: days,
      sales: Money.parse(sales),
      goods: Money.parse('90000.00'),
      spoiled: Money.zero,
      staff: Money.zero,
      premises: Money.zero,
      marketing: Money.zero,
      research: Money.zero,
      interest: Money.zero,
      works: Money.zero,
      tax: Money.zero,
      oneOffs: Money.zero,
      capital: Money.parse(capital),
    );
    expect(results().roic, Fx.parse('0.2'));
    expect(results(capital: '0.00').roic, isNull);
    expect(results(capital: '-5.00').roic, isNull);
    expect(results(days: 89).roic, isNull);
    expect(results(sales: '80000.00').roic, Fx.parse('-0.2'));
    expect(results(sales: '0.00').netMargin, isNull);
  });
}

/// A game with an expert manager running the store for [days] days.
SimulationController managedGame({required int days}) {
  final game = newController()
    ..submit(
      HireManager(
        prototype.player,
        store: playerStore,
        grade: grade('expert'),
        strategy: strategy('balanced'),
        duties: [for (final _ in ManagerDuty.values) true],
      ),
    );
  for (var i = 0; i < days; i++) {
    game.step();
  }
  return game;
}

/// Opens the shop tab at its running: site, staff, manager, marketing.
Future<void> openRunning(WidgetTester tester) async {
  await tester.tap(find.text('Shop'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Running'));
  await tester.pumpAndSettle();
}
