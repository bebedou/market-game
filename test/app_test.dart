import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/application/game_controller.dart';
import 'package:market_game/ui/app.dart';
import 'package:market_game/ui/format.dart';
import 'package:market_game/ui/competition_chart.dart';

void setScreen(WidgetTester tester, double width, {double scale = 1}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('Shop selection inspects each shop and survives a daily tick', (
    tester,
  ) async {
    setScreen(tester, 430);
    final game = GameController()..nextDay();
    addTearDown(game.dispose);
    await tester.pumpWidget(MarketGameApp(controller: game));
    await tester.tap(find.text('Shops'));
    await tester.pumpAndSettle();
    for (final store in game.simulation.stores) {
      await tester.tap(find.byKey(const Key('shop-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.name).last);
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('shop-selector')),
      );
      expect(dropdown.value, store.id);
      expect(
        find.text(money(game.simulation.ledger.balance(store.id))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('next-day')));
      await tester.pump();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('shop-selector')),
            )
            .value,
        store.id,
      );
      expect(
        find.text(money(game.simulation.ledger.balance(store.id))),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Comparison chart supports losses, shares, and zero-sales days', (
    tester,
  ) async {
    setScreen(tester, 430);
    final game = GameController();
    addTearDown(game.dispose);
    for (final store in game.simulation.stores) {
      store.autoRestock = false;
      for (final stock in store.inventory.values) {
        stock.remove(stock.quantity);
      }
    }
    game.nextDay();
    expect(game.retailProfit, lessThan(0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitionChart(
            reports: game.reports,
            stores: game.simulation.stores,
          ),
        ),
      ),
    );
    for (final metric in TrendMetric.values) {
      await tester.tap(find.byType(DropdownButton<TrendMetric>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(metric.label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1. Corner & Co.'), findsOneWidget);
    }
  });

  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets(
      'All dashboard sections render without overflow at width $width',
      (tester) async {
        setScreen(tester, width);
        final game = GameController();
        addTearDown(game.dispose);
        await tester.pumpWidget(MarketGameApp(controller: game));
        expect(find.text('Day 0'), findsOneWidget);
        expect(find.text('\$75,000.00'), findsOneWidget);
        expect(find.textContaining('No completed days yet'), findsOneWidget);
        expect(find.text('1. Corner & Co.'), findsOneWidget);
        expect(find.text('2. Quick Stop'), findsOneWidget);
        expect(find.text('3. Neighborhood Mart'), findsOneWidget);
        for (final tab in ['Shops', 'Supply', 'Activity', 'Economy']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('Narrow phone supports large text in every section', (
    tester,
  ) async {
    setScreen(tester, 320, scale: 1.8);
    final game = GameController()..nextDay();
    addTearDown(game.dispose);
    await tester.pumpWidget(MarketGameApp(controller: game));
    for (final tab in ['Shops', 'Supply', 'Activity', 'Economy']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Next day updates real cash, profit, inventory and activity', (
    tester,
  ) async {
    setScreen(tester, 430);
    final game = GameController();
    addTearDown(game.dispose);
    await tester.pumpWidget(MarketGameApp(controller: game));
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pump();
    expect(game.simulation.day, 1);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text(money(game.retailCash)), findsOneWidget);
    expect(find.text(money(game.retailProfit, signed: true)), findsOneWidget);
    expect(find.textContaining('No completed days yet'), findsNothing);
    await tester.tap(find.text('Shops'));
    await tester.pumpAndSettle();
    expect(find.text('Bottled water'), findsOneWidget);
    expect(
      find.text(count(game.simulation.player.inventory['water']!.quantity)),
      findsOneWidget,
    );
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Neighborhood day completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Play, 10×, pause, and lifecycle controls actually govern ticks',
    (tester) async {
      setScreen(tester, 430);
      final game = GameController();
      addTearDown(game.dispose);
      await tester.pumpWidget(MarketGameApp(controller: game));
      await tester.tap(find.text('10×'));
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pump();
      expect(game.isPlaying, isTrue);
      final next = tester.widget<IconButton>(find.byKey(const Key('next-day')));
      expect(next.onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(game.simulation.day, 1);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pump(const Duration(seconds: 10));
      expect(game.simulation.day, 1);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 10));
      expect(game.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(game.isPlaying, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Playback and navigation have labeled Android-sized tap targets',
    (tester) async {
      setScreen(tester, 390);
      final semantics = tester.ensureSemantics();
      try {
        final game = GameController();
        addTearDown(game.dispose);
        await tester.pumpWidget(MarketGameApp(controller: game));
        expect(tester, meetsGuideline(androidTapTargetGuideline));
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    },
  );

  test('Currency formatting keeps cents exact and readable', () {
    expect(money(123456789), '\$1,234,567.89');
    expect(money(-101), '−\$1.01');
    expect(money(0, signed: true), '\$0.00');
    expect(money(150, signed: true), '+\$1.50');
  });
}
