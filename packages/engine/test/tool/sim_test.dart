@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import '../../tool/sim.dart';

void main() {
  final json = File(
    '../../content/scenarios/prototype.json',
  ).readAsStringSync();

  test('a run summarizes every company and store', () {
    final result = runJob(
      Job(scenarioJson: json, bot: 'discount', seed: 1, days: 120, out: ''),
    );
    expect(result.companies.take(3).map((c) => c.name), [
      'Corner Shop',
      'QuickStop Market',
      'Daily Basket',
    ]);
    expect(result.companies.first.isPlayer, isTrue);
    for (final company in result.companies.take(3)) {
      expect(company.revenue.cents, greaterThan(0), reason: company.name);
      expect(company.grossProfit.cents, greaterThan(0), reason: company.name);
    }
    expect(result.stores, hasLength(greaterThanOrEqualTo(3)));
    expect(result.flags, isEmpty);
    final companies = companiesCsv([result]).trim().split('\n');
    expect(companies.first, startsWith('player,seed,company,'));
    expect(companies, hasLength(result.companies.length + 1));
    final stores = storesCsv([result]).trim().split('\n');
    expect(stores, hasLength(result.stores.length + 1));
    final text = summaryText(loadScenario(json), [result]);
    expect(text, contains('player: discount (1 seeds)'));
    expect(text, contains('Criterion 2'));
  });

  test('an idle player goes bankrupt on rent and a chain buys its store', () {
    final result = runJob(
      Job(scenarioJson: json, bot: 'idle', seed: 1, days: 300, out: ''),
    );
    final player = result.companies.first;
    expect(player.liquidated, isNotNull);
    expect(result.rescues, 1);
    expect(result.purchases, greaterThanOrEqualTo(1));
    // The chain stocks and runs it.
    expect(result.stores.first.closed, isNull);
    expect(result.stores.first.sold, greaterThan(0));
  });
}
