import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/format.dart';
import 'package:market_game/src/l10n.dart';

import 'flutter_test_config.dart';
import 'support.dart';

/// The prototype, the player rich enough to build a factory.
final _rich = loadScenario(
  File('../content/scenarios/prototype.json').readAsStringSync().replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "400000.00"',
  ),
);

FactoryKindId _kind(String key) =>
    _rich.factories!.kinds.firstWhere((kind) => kind.key == key).id;

/// A game whose drinks plant, in the player's company, is making goods.
SimulationController _making([ContentDb? content]) {
  final game = SimulationController.newGame(content ?? _rich, seed: 7);
  game.submit(
    BuildFactory(
      _rich.player,
      kind: _kind('drinks'),
      country: const CountryId(0),
      name: 'Boissons du Coin',
      company: playerCompany,
      capital: Money.parse('150000.00'),
      shifts: 1,
    ),
  );
  for (var day = 0; day <= _rich.factories!.kinds[1].buildDays; day++) {
    game.step();
  }
  return game;
}

void main() {
  testWidgets('a factory is built from the holding', (tester) async {
    final game = SimulationController.newGame(_rich, seed: 7);
    await pumpGame(tester, game);
    await openIndex(tester, 'Build a factory');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Drinks plant'));
    await tester.pumpAndSettle();
    expect(find.text('Drinks plant, France'), findsOneWidget);
    // Its shops sell nothing yet, so there's nothing to estimate.
    expect(find.text('None of your shops sells these goods yet.'), findsOne);
    final capital = find.widgetWithText(
      TextField,
      'Capital from the holding’s cash',
    );
    await scrollTo(tester, capital);
    await tester.enterText(capital, '150000');
    await tester.pumpAndSettle();
    final build = find.widgetWithText(FilledButton, 'Build for 120,000');
    await scrollTo(tester, build);
    await tester.tap(build);
    await tester.pumpAndSettle();
    final command = game.pending.single as BuildFactory;
    expect(command.kind, _kind('drinks'));
    expect(command.name, 'Drinks plant, France');
    expect(find.text('Building starts tomorrow.'), findsOneWidget);
    game.step();
    expect(game.myFactories.single.$2.building, isTrue);
  });

  testWidgets('a factory has a page: the month against buying, its shifts '
      'and whom it sells to', (tester) async {
    final game = _making();
    for (var day = 0; day < 20; day++) {
      game.step();
    }
    await pumpGame(tester, game);
    await openIndex(tester, 'Boissons du Coin');
    expect(find.textContaining('against buying'), findsWidgets);
    expect(
      find.text('Your shops would have paid the wholesalers'),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('Shifts'));
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('3'),
      ),
    );
    await tester.pumpAndSettle();
    expect((game.pending.single as SetFactoryShifts).shifts, 3);
    await scrollTo(tester, find.text('Sell to rivals'));
    await tester.tap(find.text('Sell to rivals'));
    await tester.pumpAndSettle();
    final terms = game.pending.whereType<SetFactoryTerms>().single;
    expect(terms.rivalDiscount, Fx.parse('0.05'));
  });

  testWidgets('made goods are marked on the shelves and ordered from the '
      'factory', (tester) async {
    final game = _making();
    final store = game.myStores.first.$2;
    final drinks = [
      for (final product in _rich.products)
        if (_rich.categories[product.category.index].key == 'drinks' &&
            store.prices[product.id.index] != null)
          product,
    ];
    expect(drinks, isNotEmpty);
    await pumpGame(tester, game);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(drinks.first.name));
    expect(find.text('Made by Boissons du Coin'), findsWidgets);
    await tester.tap(find.text('Supplies'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Order').first);
    await tester.pumpAndSettle();
    expect(find.text('Order from Boissons du Coin'), findsOneWidget);
    // Only what the factory makes.
    expect(find.text(drinks.first.name), findsOneWidget);
    await tester.tap(find.textContaining('Suggest'));
    await tester.pump();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    final order = game.pending.single as OrderFromFactory;
    expect(order.factory, game.myFactories.single.$2.id);
    game.step();
    expect(game.view.companies.first.orders.last.factory, order.factory);
  });

  testWidgets('a factory has a lab: a line and a budget on the bench, and '
      'people hired from the market', (tester) async {
    final game = _making();
    await pumpGame(tester, game);
    await openIndex(tester, 'Boissons du Coin');
    await openIndex(tester, 'The lab');
    expect(find.text('On the bench'), findsOneWidget);
    expect(find.textContaining('The lab is idle'), findsOneWidget);
    final premium = _rich.products.firstWhere(
      (product) =>
          _rich.categories[product.category.index].key == 'drinks' &&
          product.tier == ProductTier.premium,
    );
    final chip = find.widgetWithText(ChoiceChip, premium.name);
    await scrollTo(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final lab = game.pending.single as SetLab;
    expect(lab.project, premium.id);
    expect(lab.budget, Money.parse('1000.00'));
    expect(find.text('Next generation'), findsOneWidget);
    final market = find.widgetWithText(OutlinedButton, 'The market for people');
    await scrollTo(tester, market);
    await tester.tap(market);
    await tester.pumpAndSettle();
    final candidate = game.view.candidates.first;
    expect(find.text(candidate.name), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Hire').first);
    await tester.pumpAndSettle();
    expect(game.pending.whereType<HireKeyPerson>().single.person, candidate.id);
    expect(
      find.text(
        'joins tomorrow · ${money(candidate.salary.times(game.myFactories.single.$2.lab!.wageLevel), cents: false)} a month',
      ),
      findsOneWidget,
    );
    game.step();
    await tester.pumpAndSettle();
    final factory = game.myFactories.single.$2;
    expect(factory.lab!.project, premium.id);
    expect(factory.lab!.people.single.id, candidate.id);
    // Developing, it shows how far the work has come.
    for (var day = 0; day < 70; day++) {
      game.step();
    }
    await goBack(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('of work done'), findsOneWidget);
    expect(find.text('Team · 1 of 5'), findsOneWidget);
    expect(find.text(candidate.name), findsOneWidget);
  });

  testWidgets('goods a lab has bettered are marked so on the shelves', (
    tester,
  ) async {
    final game = _making();
    final store = game.myStores.first.$2;
    final drink = _rich.products.firstWhere(
      (product) =>
          _rich.categories[product.category.index].key == 'drinks' &&
          store.prices[product.id.index] != null,
    );
    final factory = game.myFactories.single.$2;
    game.submit(
      SetLab(
        _rich.player,
        factory: factory.id,
        budget: Money.parse('2000.00'),
        project: drink.id,
      ),
    );
    var lead = Fx.zero;
    for (var day = 0; day < 200 && lead == Fx.zero; day++) {
      game.step();
      lead = game.myFactories.single.$2.lab!.lines
          .firstWhere((line) => line.product == drink.id)
          .lead;
    }
    expect(lead > Fx.zero, isTrue);
    game.submit(
      OrderFromFactory(
        _rich.player,
        store: store.id,
        factory: factory.id,
        lines: [(product: drink.id, quantity: 96)],
      ),
    );
    for (var day = 0; day < 5; day++) {
      game.step();
    }
    final quality = game.myStores.first.$2.qualityOf(drink.id);
    expect(quality > Fx.zero, isTrue);
    await pumpGame(tester, game);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(drink.name));
    expect(
      find.text(
        '${(quality.raw + 50) ~/ 100} points better than the standard: '
        'shoppers will pay more for it',
      ),
      findsOneWidget,
    );
  });

  for (final (code, lab) in [
    ('fr', false),
    ('es', false),
    ('fr', true),
    ('es', true),
  ]) {
    testWidgets('in $code, the page of a factory${lab ? "'s lab" : ''} fits '
        'a narrow phone', (tester) async {
      useStrings(stringsFromFiles(code));
      addTearDown(() => useStrings(stringsFromFiles('en')));
      final content = loadScenario(
        localizedScenario(
          File(
            '../content/scenarios/prototype.json',
          ).readAsStringSync().replaceFirst(
            '"name": "You", "cash": "20000.00"',
            '"name": "You", "cash": "400000.00"',
          ),
          currentStrings!.scenario,
        ),
      );
      final game = _making(content);
      for (var day = 0; day < 10; day++) {
        game.step();
      }
      final hired = game.view.candidates.first.id;
      game
        ..submit(
          SetLab(
            content.player,
            factory: game.myFactories.single.$2.id,
            budget: Money.parse('1500.00'),
            project: game.myFactories.single.$2.lab!.lines.first.product,
          ),
        )
        ..submit(
          HireKeyPerson(
            content.player,
            person: hired,
            factory: game.myFactories.single.$2.id,
          ),
        );
      game.step();
      game.submit(
        SetFactoryTerms(
          content.player,
          factory: game.myFactories.single.$2.id,
          serves: [for (final c in content.countries) c.id.index == 0],
          rivalDiscount: Fx.parse('0.10'),
        ),
      );
      game.step();
      usePhone(tester);
      tester.view
        ..physicalSize = const Size(1080, 2280)
        ..devicePixelRatio = 3;
      await pumpGame(tester, game);
      tester.view
        ..physicalSize = const Size(1080, 2280)
        ..devicePixelRatio = 3;
      await tester.pumpAndSettle();
      await openIndex(tester, 'Boissons du Coin');
      if (lab) await openIndex(tester, tr('lab.title'));
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
