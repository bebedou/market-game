import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/l10n.dart';
import 'package:market_game/src/screens/exchange.dart';
import 'package:market_game/src/screens/screener.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

/// The prototype with the stock market.
final _content = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync(),
  national: loadCountryTable(
    File('../content/countries/euro.json').readAsStringSync(),
    File('../content/countries/calibration.json').readAsStringSync(),
  ),
  stocks: File('../content/stocks/companies.json').readAsStringSync(),
);

SimulationController _game() => SimulationController.newGame(
  _content,
  seed: 7,
  start: const GameStart.holding('Bebedou'),
);

ScreenCriteria _criteria(
  Map<Criterion, int> limits, {
  Set<int> sectors = const {},
  Set<CountryId> countries = const {},
}) => (sectors: sectors, countries: countries, limits: limits);

void main() {
  final game = _game();
  // Two quarters of results, so prices and sales have moved.
  for (var i = 0; i < 200; i++) {
    game.step();
  }
  final stocks = game.view.stocks!.stocks;

  group('a screen', () {
    test('keeps only listed companies that meet every limit', () {
      final found = screen(
        stocks,
        _criteria({Criterion.pe: 12, Criterion.dividendYield: 3}),
        ScreenSort.pe,
      );
      expect(found, isNotEmpty);
      expect(found.length, lessThan(stocks.length));
      for (final f in found) {
        expect(f.stock.listed, isTrue);
        expect(f.pe! < Fx.fromInt(12), isTrue);
        expect(f.dividendYield >= Fx.parse('0.03'), isTrue);
      }
      // Every one left out fails a limit.
      final kept = {for (final f in found) f.stock.index};
      for (final stock in stocks) {
        if (!stock.listed || kept.contains(stock.index)) continue;
        final f = figuresOf(stock);
        expect(
          f.pe == null ||
              f.pe! >= Fx.fromInt(12) ||
              f.dividendYield < Fx.parse('0.03'),
          isTrue,
          reason: stock.name,
        );
      }
    });

    test('sorts by its figure, each the natural way first, and reverses', () {
      final cheapest = screen(stocks, _criteria({}), ScreenSort.pe);
      final pes = [
        for (final f in cheapest)
          if (f.pe case final pe?) pe.raw,
      ];
      expect(pes, [...pes]..sort());
      // Those losing money, with no price to earnings, come last.
      expect(cheapest.last.pe, isNull);
      final dearest = screen(
        stocks,
        _criteria({}),
        ScreenSort.pe,
        reversed: true,
      );
      expect(dearest.first.pe!.raw, pes.last);
      final biggest = screen(stocks, _criteria({}), ScreenSort.size);
      expect(biggest.first.stock.cap >= biggest.last.stock.cap, isTrue);
      final yields = [
        for (final f in screen(stocks, _criteria({}), ScreenSort.dividendYield))
          f.dividendYield.raw,
      ];
      expect(yields, [...yields]..sort((a, b) => b.compareTo(a)));
    });

    test('limits sectors and exchanges', () {
      final paris = _content.countries.firstWhere((c) => c.key == 'fr').id;
      final found = screen(
        stocks,
        _criteria({}, sectors: {0, 1}, countries: {paris}),
        ScreenSort.size,
      );
      expect(found, isNotEmpty);
      for (final f in found) {
        expect({0, 1}.contains(f.stock.sector), isTrue);
        expect(f.stock.country, paris);
      }
    });

    test('ready-made screens find what they say', () {
      final cheap = screen(
        stocks,
        _criteria(ReadyScreen.cheap.limits),
        ReadyScreen.cheap.sort,
      );
      for (final f in cheap) {
        expect(f.againstUsual! <= Fx.parse('-0.2'), isTrue);
        expect(f.pe! < Fx.fromInt(20), isTrue);
        expect(f.stock.management! >= 2, isTrue);
      }
      final debtFree = screen(
        stocks,
        _criteria(ReadyScreen.smallDebtFree.limits),
        ReadyScreen.smallDebtFree.sort,
      );
      for (final f in debtFree) {
        expect(f.debt, Fx.zero);
        expect(f.stock.cap < const Money(100000000000), isTrue);
      }
      expect(
        screen(
          stocks,
          _criteria(ReadyScreen.everything.limits),
          ScreenSort.size,
        ).length,
        stocks.where((s) => s.listed).length,
      );
    });

    test('every limit has its words', () {
      for (final MapEntry(key: criterion, value: limits)
          in criterionLimits.entries) {
        expect(
          trMaybe('stocks.screener.criteria.${criterion.name}'),
          isNotNull,
        );
        expect(trMaybe('stocks.screener.short.${criterion.name}'), isNotNull);
        for (final limit in limits) {
          expect(limitText(criterion, limit), isNot(contains('stocks.')));
        }
      }
      for (final sort in ScreenSort.values) {
        expect(trMaybe('stocks.screener.sorts.${sort.name}'), isNotNull);
      }
      for (final ready in ReadyScreen.values) {
        for (final part in ['title', 'hint', 'chip']) {
          expect(
            trMaybe('stocks.screener.ready.${ready.name}.$part'),
            isNotNull,
          );
        }
      }
      for (final view in ScreenerView.values) {
        expect(trMaybe('stocks.screener.views.${view.name}'), isNotNull);
      }
    });
  });

  testWidgets('the screener opens from the Market tab, in three views, and '
      'a result opens its stock', (tester) async {
    await pumpGame(tester, game);
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Screener');
    // Ready-made screens, each with its count, the cheap one shown.
    expect(find.text('Cheap against their past'), findsWidgets);
    final income = screen(
      stocks,
      _criteria(ReadyScreen.income.limits),
      ReadyScreen.income.sort,
    );
    expect(find.widgetWithText(IndexRow, '${income.length}'), findsWidgets);
    await openIndex(tester, 'Paying over 5%');
    expect(find.text('Paying over 5%'), findsNWidgets(2));

    // The criteria view: the screen's limits as lines, and one added.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Criteria'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Criteria'));
    await tester.pumpAndSettle();
    expect(find.text('Dividend yield'), findsOneWidget);
    expect(find.text('over 5%'), findsOneWidget);
    await openIndex(tester, 'Add a criterion');
    await tester.tap(find.text('Price to earnings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('under 12'));
    await tester.pumpAndSettle();
    expect(find.text('Price to earnings'), findsOneWidget);
    final both = screen(
      stocks,
      _criteria({...ReadyScreen.income.limits, Criterion.pe: 12}),
      ScreenSort.dividendYield,
    );
    expect(
      find.text(both.length == 1 ? '1 company' : '${both.length} companies'),
      findsOneWidget,
    );

    // The table view: the limits as chips, sorted by a tapped column.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Table'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'P/E under 12'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(InputChip, 'P/E under 12').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'P/E under 12'), findsNothing);
    await tester.ensureVisible(find.text('P/E'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P/E'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    await tester.tap(find.text('P/E'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

    final top = screen(
      stocks,
      _criteria(ReadyScreen.income.limits),
      ScreenSort.pe,
      reversed: true,
    ).first.stock;
    await tester.ensureVisible(find.text(top.name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(top.name).first);
    await tester.pumpAndSettle();
    expect(find.byType(StockPage), findsOneWidget);
    expect(find.text('${top.name} · ${top.ticker}'), findsOneWidget);
  });
}
