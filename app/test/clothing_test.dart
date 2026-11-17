import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/screens/rails.dart';
import 'package:market_game/src/widgets.dart';

import 'support.dart';

/// A game started, rich, as a clothing shop on the first clothing site in Lyon,
/// played [days] in.
SimulationController _clothier(int days) {
  // Rich enough to fit one out.
  final content = nationalPrototype;
  final clothing = content.formats.firstWhere((f) => f.key == 'clothing');
  final site = content.sites.firstWhere(
    (site) =>
        content.markets[site.market.index].key == 'neighborhood' &&
        !content.stores.any((store) => store.site == site.id),
  );
  final game = SimulationController.newGame(
    content,
    seed: 3,
    start: GameStart(site: site.id, format: clothing.id, name: 'Maille'),
  );
  for (var day = 0; day < days; day++) {
    game.step();
  }
  return game;
}

void main() {
  /// Orders [units] of women's basics from the quick supplier for [game]'s
  /// shop.
  ProductDef order(SimulationController game, int units) {
    final content = game.content;
    final basics = content.products.firstWhere(
      (p) => p.key == 'womenswear_budget',
    );
    game.submit(
      PlaceOrder(
        game.player,
        store: game.store!.id,
        supplier: content.suppliers
            .firstWhere((s) => s.key == 'pretexpress')
            .id,
        lines: [(product: basics.id, quantity: units)],
      ),
    );
    return basics;
  }

  testWidgets('a clothing shop shows its rails by age and what is on order', (
    tester,
  ) async {
    final game = _clothier(0);
    order(game, 300);
    game.step();
    await pumpGame(tester, game);
    await tester.tap(find.text('Businesses'));
    await tester.pumpAndSettle();
    expect(find.text('Rails'), findsOneWidget);
    expect(find.text('New, under 2 months'), findsOneWidget);
    expect(find.text('Nothing on the rails yet.'), findsOneWidget);
    expect(find.text('300 pieces from Prêt Express'), findsOneWidget);
    for (var day = 0; day < 12; day++) {
      game.step();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('of new, on average'), findsOneWidget);
    expect(find.text('Nothing on order for this shop.'), findsOneWidget);
  });

  testWidgets('each line shows its age, worth and markdown', (tester) async {
    final game = _clothier(0);
    game.submit(
      InjectCapital(
        game.player,
        company: game.view.companies.single.id,
        amount: Money.parse('200000.00'),
      ),
    );
    // Priced far too dear, it sits, and fades.
    final basics = order(game, 600);
    game.submit(
      SetPrice(
        game.player,
        store: game.store!.id,
        product: basics.id,
        price: Money.parse('45.00'),
      ),
    );
    for (var day = 0; day < 110; day++) {
      game.step();
    }
    game.submit(
      SetPrice(
        game.player,
        store: game.store!.id,
        product: basics.id,
        price: Money.parse('14.00'),
      ),
    );
    game.step();
    expect(game.store!.fashionOf(basics.id) < Fx.one, isTrue);
    usePhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameScope(
            controller: game,
            child: ListView(children: [LinesPage(store: game.store!.id)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Women's basics"), findsOneWidget);
    expect(find.textContaining('months old'), findsOneWidget);
    expect(find.textContaining('marked down'), findsOneWidget);
  });

  test('only goods that go out of fashion get rails', () {
    final content = prototype;
    expect(
      sellsFashion(
        content,
        content.formats.firstWhere((f) => f.key == 'clothing'),
      ),
      isTrue,
    );
    expect(
      sellsFashion(
        content,
        content.formats.firstWhere((f) => f.key == 'grocery'),
      ),
      isFalse,
    );
  });
}
