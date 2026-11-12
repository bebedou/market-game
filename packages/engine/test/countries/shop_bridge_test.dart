@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/countries.dart';
import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  final scenario = File(
    '../../content/scenarios/prototype.json',
  ).readAsStringSync();
  final calibration = File(
    '../../content/countries/calibration.json',
  ).readAsStringSync();
  final table = File('../../content/countries/euro.json').readAsStringSync();

  test('the table keeps the shop-level game\'s cycle', () {
    final content = loadScenario(scenario);
    final countries = loadCountryTable(table, calibration);
    final regimes = content.macro.regimes;
    expect(countries.regimes, hasLength(regimes.length));
    for (final (i, regime) in regimes.indexed) {
      final mine = countries.regimes[i];
      expect(mine.key, regime.key);
      expect(mine.meanMonths, regime.meanMonths);
      expect(mine.demand, regime.demand);
      expect(mine.realWageGrowth, regime.realWageGrowth);
    }
  });

  // Fails if the shop-level game and the numbers fitted to it drift apart: if
  // it does after a balance change, run tool/calibrate_countries.dart --write.
  test('the formula predicts what the full simulation sells', () {
    final content = loadScenario(scenario);
    final capture = shopCapture(calibration);
    final balanced = content.strategies.firstWhere((s) => s.key == 'balanced');
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      policies: {
        ...standardPolicies(content),
        content.player: ownerPolicy(balanced),
      },
    );
    final startYear = content.startDay.date.year;
    var priceSum = Fx.zero;
    var demandSum = Fx.zero;
    final sold = <(int, String), Money>{};
    final storeMonths = <(int, String), int>{};
    final gaps = <double>[];
    while (simulation.world.today.date.year < startYear + 3 ||
        simulation.world.today.date.month != 1 ||
        !simulation.world.today.isFirstOfMonth) {
      simulation.step();
      final world = simulation.world;
      if (!world.today.isFirstOfMonth) continue;
      final date = world.today.date;
      final year = date.month == 1
          ? date.year - startYear - 1
          : date.year - startYear;
      priceSum += world.macro.priceIndex;
      demandSum += content.macro.regimes[world.macro.regime.index].demand;
      if (year >= 1) {
        for (final (i, _) in world.companies.indexed) {
          final reports = simulation.reports(CompanyId(i), ReportPeriod.month);
          if (reports.length < 2) continue;
          for (final store in reports[reports.length - 2].stores) {
            final state = world.stores[store.store.index];
            final key = (
              state.market.index,
              content.formats[state.format.index].key,
            );
            sold[key] = (sold[key] ?? Money.zero) + store.totalRevenue;
            if (store.totalRevenue != Money.zero) {
              storeMonths[key] = (storeMonths[key] ?? 0) + 1;
            }
          }
        }
      }
      if (date.month != 1) continue;
      if (year >= 1) {
        // France's cities, which the fit was made on and whose prices and
        // cycle these are.
        for (final market in content.markets) {
          if (market.country != const CountryId(0)) continue;
          var actual = 0;
          var predicted = 0;
          for (final trade in capture.keys) {
            // The formula says what a format sells in a whole year, so one
            // whose only shop closed or opened partway through is left out.
            final here = {
              for (final MapEntry(:key, :value) in storeMonths.entries)
                if (key.$1 == market.id.index &&
                    value >= 12 &&
                    formatTrades[key.$2] == trade)
                  key.$2,
            };
            if (here.isEmpty) continue;
            for (final format in here) {
              actual += sold[(market.id.index, format)]!.cents;
            }
            predicted += shopMarketWants(
              content,
              market,
              formats: here,
              year: year,
              priceIndex: Fx.raw(priceSum.raw ~/ 12),
              demand: Fx.raw(demandSum.raw ~/ 12),
            ).times(capture[trade]!).cents;
          }
          gaps.add((predicted / actual - 1).abs());
        }
      }
      sold.clear();
      storeMonths.clear();
      priceSum = Fx.zero;
      demandSum = Fx.zero;
    }
    gaps.sort();
    final french = content.markets.where(
      (market) => market.country == const CountryId(0),
    );
    expect(gaps, hasLength(french.length * 2));
    expect(gaps[gaps.length ~/ 2], lessThan(0.05));
    expect(gaps.last, lessThan(0.1));
  });
}
