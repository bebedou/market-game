// A tour of every screen on a real device, for reviewing the interface:
// the menu and a new game, then the same screens after two months that the
// "balanced" AI played in the player's seat. Saves stay in memory.
//
//   flutter drive --profile -d <device> --keep-app-running \
//       --driver=test_driver/integration_test.dart \
//       --target=integration_test/tour_test.dart
//
// Without --keep-app-running, flutter drive uninstalls the app when it is
// done, and the phone's saved games with it: back them up first.
import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_game/src/app.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/home.dart';
import 'package:market_game/src/l10n.dart';
import 'package:market_game/src/saves.dart';
import 'package:market_game/src/theme.dart';
import 'package:market_game/src/widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tour', (tester) async {
    var surface = false;
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      if (!surface) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        surface = true;
      }
      await binding.takeScreenshot(name);
    }

    Finder list() => find.byType(Scrollable).first;

    /// Screenshots the screen, then a page further down each time, until
    /// the end or [most] shots.
    Future<void> scrolling(String name, {int most = 6}) async {
      for (var i = 1; i <= most; i++) {
        await shot('${name}_$i');
        final position = tester.state<ScrollableState>(list()).position;
        if (position.pixels >= position.maxScrollExtent - 1) return;
        await tester.drag(list(), Offset(0, -position.viewportDimension * 0.8));
        await tester.pumpAndSettle();
      }
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    // The menu, a new game and the guide.
    // In English, whatever the phone's language: the tour finds things by name.
    await useLanguage('en');
    final content = await loadContent();
    await tester.pumpWidget(
      MarketGameApp(saves: MemorySaveSlots(), language: 'en'),
    );
    for (var i = 0; i < 50 && find.text('New game').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot('01_menu');
    await tap(find.text('How to play'));
    await scrolling('02_guide', most: 4);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(find.text('New game'));
    await scrolling('03_new_game', most: 4);
    await tap(find.text('Start'));
    await scrolling('04_day0_dashboard', most: 3);
    for (final (i, tab) in ['Shop', 'Finance', 'World', 'Books'].indexed) {
      await tap(find.text(tab).last);
      await scrolling('0${5 + i}_day0_${tab.toLowerCase()}', most: 3);
    }

    // Two months later, the "balanced" AI having played for the player.
    final game = SimulationController.newGame(content, seed: 11);
    final ghost = RetailPolicy(
      content.strategies.firstWhere((strategy) => strategy.key == 'balanced'),
    );
    for (var i = 0; i < 60; i++) {
      ghost.decide(game.view, content).forEach(game.submit);
      game.step();
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: gameTheme(Brightness.light),
        darkTheme: gameTheme(Brightness.dark),
        builder: (context, child) => ScreenMargins(child: child!),
        home: HomeScreen(controller: game),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> page(String title, String name, {int most = 1}) async {
      final row = find.widgetWithText(IndexRow, title);
      await tester.scrollUntilVisible(row, 300, scrollable: list());
      await tap(row);
      await scrolling(name, most: most);
      await tap(find.byIcon(Icons.arrow_back));
    }

    await scrolling('10_holding', most: 3);
    await page('Start a new business', '10_new_business');
    await page('News', '10_news');
    await tap(find.text('World').last);
    await scrolling('11_world', most: 2);
    final competitors = find.widgetWithText(IndexRow, 'Competitors');
    await tap(competitors);
    final rival = find.widgetWithText(ExpansionTile, 'QuickStop Market');
    await tester.scrollUntilVisible(rival, 300, scrollable: list());
    await tap(rival);
    await shot('12_world_rival');
    await tap(find.byIcon(Icons.arrow_back));
    await page('Cities', '13_world_cities', most: 2);
    await page('More on the economy', '13_world_economy', most: 2);
    await tap(find.text('Shop').last);
    await scrolling('14_shop_shelves', most: 3);
    await tap(find.text('Supplies'));
    await shot('15_shop_supplies');
    await page('On the way', '15_shop_on_the_way');
    await tap(find.text('Running'));
    await shot('16_shop_running');
    await page('Staff and opening hours', '16_shop_staff');
    await tap(find.text('Finance').last);
    await shot('17_finance');
    await page('Going cheap', '17_finance_cheap');
    await tap(find.text('Books').last);
    await scrolling('18_books', most: 2);
    await page('Profit and loss', '18_books_pnl');
    await tap(find.byTooltip('News'));
    await shot('19_news');
    await tester.tapAt(const Offset(20, 120));
    await tester.pumpAndSettle();
    final store = game.store!;
    final listed = content.products.firstWhere(
      (product) => store.prices[product.id.index] != null,
    );
    game.submit(
      SetPrice(
        game.player,
        store: store.id,
        product: listed.id,
        price: store.prices[listed.id.index]! + const Money(10),
      ),
    );
    await tap(find.text('Holding').last);
    await shot('20_pending_change');

    // The day edition, whatever the phone's setting.
    await tester.pumpWidget(
      MaterialApp(
        theme: gameTheme(Brightness.light),
        themeMode: ThemeMode.light,
        builder: (context, child) => ScreenMargins(child: child!),
        home: HomeScreen(controller: game),
      ),
    );
    await tester.pumpAndSettle();
    await scrolling('21_day_holding', most: 2);
    await tap(find.text('Shop').last);
    await shot('22_day_shelves');
    await tap(find.text('Finance').last);
    await shot('23_day_finance');
  });
}
