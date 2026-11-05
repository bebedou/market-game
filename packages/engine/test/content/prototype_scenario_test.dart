@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  final content = loadScenario(
    File('../../content/scenarios/prototype.json').readAsStringSync(),
  );

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
