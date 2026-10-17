import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/application/game_controller.dart';
import 'package:market_game/ui/app.dart';
import 'package:market_game/ui/format.dart';

void setScreen(WidgetTester tester, double width, {double scale = 1}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets(
      'All dashboard sections render without overflow at width $width',
      (tester) async {
        setScreen(tester, width);
        final game = GameController();
        addTearDown(game.dispose);
        await tester.pumpWidget(MarketGameApp(controller: game));
        expect(find.text('Day 0'), findsOneWidget);
        expect(find.text('\$25,000.00'), findsOneWidget);
        expect(find.text('No completed days yet'), findsOneWidget);
        expect(find.text('After your first close'), findsNWidgets(2));
        for (final tab in ['Stock', 'Market', 'Activity', 'Home']) {
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
    for (final tab in ['Stock', 'Market', 'Activity', 'Home']) {
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
    expect(
      find.text(money(game.simulation.ledger.balance('player'))),
      findsOneWidget,
    );
    expect(
      find.text(money(game.playerReport!.profit, signed: true)),
      findsOneWidget,
    );
    expect(find.text('After your first close'), findsNothing);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Bottled water'), findsOneWidget);
    expect(
      find.text(
        '${count(game.simulation.player.inventory['water']!.quantity)} on hand',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Trading day completed'), findsOneWidget);
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
