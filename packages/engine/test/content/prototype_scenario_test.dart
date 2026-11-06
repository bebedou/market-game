@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  final content = loadScenario(
    File('../../content/scenarios/prototype.json').readAsStringSync(),
  );

  test('holds neighbourhoods asleep, every one of which can wake', () {
    expect(content.neighbourhoods, isNotEmpty);
    final simulation = Simulation.newGame(content, seed: 1);
    final plan = simulation.plan!;
    expect(
      plan.markets,
      hasLength(content.markets.length + content.neighbourhoods.length),
    );
    // Each has shops and sites to spare, and at least grocers to compete with.
    for (final market in plan.markets.skip(content.markets.length)) {
      final stores = plan.stores.where(
        (store) => plan.sites[store.site.index].market == market.id,
      );
      final sites = plan.sites.where((site) => site.market == market.id);
      expect(stores.length, greaterThanOrEqualTo(2), reason: market.key);
      expect(sites.length, greaterThan(stores.length), reason: market.key);
    }
    for (final (row, _) in content.neighbourhoods.indexed) {
      simulation.submit(WakeNeighbourhood(content.player, row: row));
    }
    expect(simulation.sleeping, isEmpty);
    expect(simulation.content.markets, hasLength(plan.markets.length));
    for (var day = 0; day < 30; day++) {
      simulation.step();
    }
  });

  test('a market study counts each store\'s share within its own trade', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      policies: standardPolicies(content),
    );
    for (var day = 0; day < 60; day++) {
      simulation.step();
    }
    simulation
      ..submit(
        BuyResearch(
          content.player,
          company: const CompanyId(0),
          market: const MarketId(0),
          tier: content.researchTiers.last.id,
        ),
      )
      ..step();
    final view = simulation.observe(content.player);
    final report = view.reports.single;
    String formatOf(StoreId store) =>
        content.formats[view.shelves[store.index].format.index].key;
    // Alone in its trade in Lyon, a burger bar has about all of it, however
    // much the grocers sell.
    final burgers = report.unitShares.singleWhere(
      (row) => formatOf(row.store) == 'fastfood',
    );
    expect(burgers.share.raw, greaterThan(Fx.parse('0.9').raw));
    final grocers = [
      for (final (:store, :share) in report.unitShares)
        if (formatOf(store) == 'grocery') share.raw,
    ];
    expect(grocers, hasLength(4));
    expect(
      grocers.fold(0, (sum, share) => sum + share),
      closeTo(Fx.scale, Fx.parse('0.1').raw),
    );
  });

  test('matches the prototype described in the design doc', () {
    expect(content.markets.map((m) => m.name), [
      'Lyon, Croix-Rousse',
      'Montpellier, Boutonnet',
      'Bordeaux, Chartrons',
      'Nantes, Rezé',
      'Lille, Wazemmes',
      'Marseille, Cours Julien',
      'Paris, Batignolles',
    ]);
    expect(content.stores, hasLength(41));
    expect(content.products, hasLength(24));
    expect(content.categories, hasLength(12));
    expect(content.suppliers, hasLength(4));
    expect(content.formats.map((f) => f.key), [
      'grocery',
      'fastfood',
      'steakhouse',
      'finedining',
      'supermarket',
      'electronics',
    ]);
    // Convenience stores and supermarkets compete for the same trips.
    expect(content.formatChannels, [0, 1, 2, 3, 0, 4]);
    // 21 convenience stores, a supermarket, 15 restaurants and 4
    // electronics shops.
    expect(
      content.stores.where((s) => s.format == const FormatId(0)),
      hasLength(21),
    );
    expect(
      content.stores.where((s) => s.format == const FormatId(5)),
      hasLength(4),
    );
    // Smart home devices are still spreading.
    expect(
      content.categories
          .firstWhere((c) => c.key == 'smarthome')
          .diffusion!
          .adoption(content.startDay)
          .raw,
      inInclusiveRange(2000, 2600),
    );
    expect(content.segments.map((s) => s.key), [
      'families',
      'professionals',
      'students',
      'retirees',
      'singles',
      'comfortable',
    ]);
    // Lyon keeps its original thousand households, now joined by singles
    // and comfortable families.
    expect(
      content.markets.first.households.take(4).fold(0, (a, b) => a + b),
      1000,
    );
    final occupied = {for (final store in content.stores) store.site};
    for (final market in content.markets) {
      final sites = content.sites.where((s) => s.market == market.id);
      // Montpellier is the tightest city; every city has one vacant
      // restaurant site among them.
      expect(
        sites.where((s) => !occupied.contains(s.id)),
        hasLength(market.key == 'montpellier' ? 3 : 4),
        reason: 'vacant sites in ${market.key}',
      );
    }
    expect(content.persons.where((p) => p.strategy != null), hasLength(44));
    expect(content.macro.regimes.map((r) => r.key), [
      'expansion',
      'slowdown',
      'recession',
      'recovery',
    ]);
    expect(content.researchTiers, hasLength(3));
    for (final category in content.categories) {
      final tiers = content.products
          .where((p) => p.category == category.id)
          .map((p) => p.tier);
      expect(tiers, unorderedEquals(ProductTier.values), reason: category.key);
    }
  });

  test('shelf space forces assortment choices', () {
    for (final store in content.stores) {
      final site = content.sites[store.site.index];
      expect(site.shelfSlots, lessThan(content.products.length));
    }
    for (final product in content.products) {
      final listedSomewhere = content.stores.any(
        (store) => store.prices[product.id.index] != null,
      );
      final soldSomewhere = content.suppliers.any(
        (supplier) => supplier.carries[product.id.index],
      );
      expect(listedSomewhere && soldSomewhere, isTrue, reason: product.key);
    }
  });

  test('runs for a year, with households visiting every store', () {
    final simulation = Simulation.newGame(content, seed: 1);
    final visits = List.filled(content.stores.length, 0);
    for (var i = 0; i < 365; i++) {
      final day = simulation.step();
      for (var store = 0; store < visits.length; store++) {
        visits[store] += day.attribution.visits[store];
      }
    }
    expect(simulation.today, Day.parse('2027-01-01'));
    expect(visits, everyElement(greaterThan(0)));
  });
}
