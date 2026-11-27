import 'package:engine/engine.dart';
import 'package:engine/src/state/fixed_assets.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'acquisitions_test.dart' show tradingJson;
import 'support/fixtures.dart';

/// [game] after [days] more days.
void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

void main() {
  group('fixed assets', () {
    test('fitting out a shop is an asset, worn by a month on each first of '
        'the month, and charged as depreciation', () {
      final game = Simulation.newGame(loadScenario(testScenarioJson), seed: 1)
        ..submit(
          OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
        );
      game.step();
      final world = game.world;
      final store = world.stores.last;
      final company = world.companies[playerCompany.index];
      // Opened on the first: 250.00 less its first month, a sixtieth.
      final cost = Money.parse('250.00');
      expect(store.fittings, cost - monthsWear(cost, 10));
      expect(company.accounts[AccountKind.fixedAssets], store.fittings);
      expect(company.accounts[AccountKind.openingCosts], Money.zero);
      final before = store.fittings;
      final charged = company.accounts[AccountKind.depreciation];
      // To the first of the next month, and its wear.
      _advance(game, 31);
      expect(store.fittings, before - monthsWear(before, 10));
      expect(
        company.accounts[AccountKind.depreciation] - charged,
        monthsWear(before, 10),
      );
      expect(invariantViolations(world), isEmpty);
    });

    test('closing a shop writes its fittings off', () {
      final game = Simulation.newGame(loadScenario(testScenarioJson), seed: 1)
        ..submit(
          OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
        );
      _advance(game, 40);
      final world = game.world;
      final store = world.stores.last;
      final company = world.companies[playerCompany.index];
      final book = store.fittings;
      expect(book > Money.zero, isTrue);
      final lost = company.accounts[AccountKind.writeOffs];
      game.submit(CloseStore(player, store: store.id));
      game.step();
      expect(store.fittings, Money.zero);
      expect(company.accounts[AccountKind.fixedAssets], Money.zero);
      expect(company.accounts[AccountKind.writeOffs] - lost, book);
      expect(invariantViolations(world), isEmpty);
    });

    test('a shop sold takes its fittings to the buyer, out of the price', () {
      final game = Simulation.newGame(
        loadScenario(
          tradingJson(
            expanding: true,
            rivalCash: '100000.00',
            playerCash: '100000.00',
          ),
        ),
        seed: 1,
        systems: testSystems,
      );
      game.submit(
        InjectCapital(
          player,
          company: playerCompany,
          amount: Money.parse('20000.00'),
        ),
      );
      game.step();
      game.submit(
        OpenStore(player, site: lane, name: 'Lane', company: playerCompany),
      );
      runScripted(game, 60);
      final world = game.world;
      final store = world.stores.last;
      final seller = world.companies[playerCompany.index];
      final book = store.fittings;
      expect(book > Money.zero, isTrue);
      final held = seller.accounts[AccountKind.fixedAssets];
      game.submit(SellStore(player, store: store.id));
      final day = game.step();
      expect(day.rejections, isEmpty);
      expect(store.company, isNot(playerCompany));
      final buyer = world.companies[store.company.index];
      // The seller gives up their book value; the buyer carries it, worn
      // with the rest of its assets on the first of the month.
      expect(seller.accounts[AccountKind.fixedAssets], held - book);
      expect(store.fittings > Money.zero, isTrue);
      expect(store.fittings <= book, isTrue);
      expect(buyer.accounts[AccountKind.fixedAssets] >= store.fittings, isTrue);
      expect(invariantViolations(world), isEmpty);
      _advance(game, 40);
      expect(invariantViolations(world), isEmpty);
    });
  });
}
