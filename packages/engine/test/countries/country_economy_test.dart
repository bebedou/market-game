@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:engine/countries.dart';
import 'package:engine/engine.dart';
import 'package:test/test.dart';

final _tableJson = File('../../content/countries/euro.json').readAsStringSync();
final _calibration = File(
  '../../content/countries/calibration.json',
).readAsStringSync();

CountryTable _table() => loadCountryTable(_tableJson, _calibration);

CountryEconomy _run(int months, {int seed = 1}) {
  final economy = CountryEconomy(_table(), seed: seed);
  for (var i = 0; i < months; i++) {
    economy.advanceMonth();
  }
  return economy;
}

Chain _chain(CountryEconomy economy, String name) => economy.countries
    .expand((country) => country.chains)
    .firstWhere((chain) => chain.def.name == name);

CountryState _home(CountryEconomy economy, String name) => economy.countries
    .firstWhere((country) => country.chains.any((c) => c.def.name == name));

void main() {
  group('the table', () {
    test('loads four euro countries of real size', () {
      final table = _table();
      expect(table.countries.map((c) => c.key), ['de', 'fr', 'it', 'es']);
      final germany = table.countries.first;
      final households = germany.classes.fold(
        0,
        (sum, row) => sum + row.households,
      );
      expect(households, closeTo(41000000, 500000));
      expect(germany.population, closeTo(83000000, 1000000));
      // The richest fifth earns more and spends more, on everything.
      expect(
        germany.classes.last.income > germany.classes.first.income,
        isTrue,
      );
      for (final (t, _) in table.trades.indexed) {
        expect(
          germany.classes.last.spending[t] > germany.classes.first.spending[t],
          isTrue,
        );
      }
    });

    test('what households spend is near what sellers report', () {
      final table = _table();
      for (final country in table.countries) {
        for (final (t, trade) in table.trades.indexed) {
          if (trade.key == 'electronics') continue; // Much of it sells online.
          var spent = 0;
          for (final row in country.classes) {
            spent += row.spending[t].cents * row.households;
          }
          final ratio = spent / country.trades[t].turnover.cents;
          expect(
            ratio,
            inInclusiveRange(0.75, 1.55),
            reason: '${country.name} ${trade.key}',
          );
        }
      }
    });

    test('a typical business keeps a margin the statistics report', () {
      for (final country in _table().countries) {
        for (final row in country.trades) {
          expect(row.normalMargin > Fx.zero, isTrue);
          expect(row.normalMargin < Fx.parse('0.25'), isTrue);
        }
      }
    });

    test('rejects unknown fields, and shares that don\'t add up', () {
      final extra = jsonDecode(_tableJson) as Map<String, dynamic>;
      extra['countires'] = <Object>[];
      expect(
        () => loadCountryTable(jsonEncode(extra), _calibration),
        throwsA(isA<ContentException>()),
      );
      final shares = jsonDecode(_tableJson) as Map<String, dynamic>;
      final chains = (shares['countries'] as List).first['chains'] as List;
      chains.first['share'] = '0.99';
      expect(
        () => loadCountryTable(jsonEncode(shares), _calibration),
        throwsA(
          isA<ContentException>().having(
            (e) => e.toString(),
            'message',
            contains('add up'),
          ),
        ),
      );
    });
  });

  group('a month', () {
    test('starts with the table\'s shares and normal margins', () {
      final economy = _run(1);
      for (final country in economy.countries) {
        for (final chain in country.chains) {
          final market = country.tradeMonths[chain.def.trade].last.market;
          final month = chain.months.last;
          expect(
            month.sales.cents / market.cents,
            closeTo(chain.def.share.raw / Fx.scale, 0.005),
            reason: chain.def.name,
          );
          expect(
            month.profit.cents / month.sales.cents,
            closeTo(
              country.def.trades[chain.def.trade].normalMargin.raw / Fx.scale,
              0.01,
            ),
            reason: chain.def.name,
          );
        }
      }
    });

    test('shares out exactly what households spend', () {
      final economy = CountryEconomy(_table(), seed: 3);
      for (var i = 0; i < 60; i++) {
        economy.advanceMonth();
        for (final country in economy.countries) {
          for (final (t, _) in economy.table.trades.indexed) {
            final sold = country.chains
                .where((chain) => chain.def.trade == t && chain.isTrading)
                .fold(Money.zero, (sum, c) => sum + c.months.last.sales);
            expect(sold, country.tradeMonths[t].last.market);
          }
        }
      }
    });

    test('moves a chain\'s cash by exactly what its books say', () {
      final economy = CountryEconomy(_table(), seed: 2);
      final chain = _chain(economy, 'Mercado Levante');
      final start = chain.cash;
      var expected = start;
      for (var i = 0; i < 36; i++) {
        economy.advanceMonth();
        final m = chain.months.last;
        expected += m.profit - m.tax - m.fitOut;
        expect(chain.cash, expected);
      }
      expect(chain.cash > start, isTrue);
    });

    test('is the same from the same seed, and not from another', () {
      List<int> figures(CountryEconomy economy) => [
        economy.regime,
        for (final country in economy.countries)
          for (final chain in country.chains) ...[
            chain.stores,
            chain.cash.cents,
          ],
      ];
      expect(figures(_run(120)), figures(_run(120)));
      expect(figures(_run(120)), isNot(figures(_run(120, seed: 2))));
    });
  });

  group('prices', () {
    test('a rise costs far more sales than the same cut brings', () {
      // In the first month, before any store opens or closes in response.
      Money firstMonth(Fx? price) {
        final economy = CountryEconomy(_table(), seed: 1);
        final chain = _chain(economy, 'Rheinkauf');
        if (price != null) chain.price = price;
        economy.advanceMonth();
        return chain.months.last.sales;
      }

      final normal = firstMonth(null).cents;
      final rise = firstMonth(Fx.parse('1.10')).cents / normal - 1;
      final cut = firstMonth(Fx.parse('0.90')).cents / normal - 1;
      expect(rise, lessThan(-0.15));
      expect(cut, greaterThan(0.02));
      expect(rise.abs(), greaterThan(cut * 2));
    });

    test('a price cut with no cheaper goods eats the margin', () {
      final normal = _run(1);
      final economy = CountryEconomy(_table(), seed: 1);
      final chain = _chain(economy, 'Rheinkauf')..price = Fx.parse('0.97');
      economy.advanceMonth();
      final was = _chain(normal, 'Rheinkauf').months.last;
      final now = chain.months.last;
      expect(
        now.profit.cents / now.sales.cents,
        lessThan(was.profit.cents / was.sales.cents - 0.01),
      );
    });
  });

  group('stores', () {
    test('close when a chain earns below normal, and open above', () {
      final normal = _run(36);
      final economy = CountryEconomy(_table(), seed: 1);
      final cheap = _chain(economy, 'Rheinkauf')..price = Fx.parse('0.97');
      final dear = _chain(economy, 'Bellevue');
      final doing = _chain(normal, 'Bellevue');
      for (var i = 0; i < 36; i++) {
        economy.advanceMonth();
      }
      expect(cheap.stores, lessThan(_chain(normal, 'Rheinkauf').stores));
      // Rivals elsewhere are untouched: the countries don't share customers.
      expect(dear.stores, doing.stores);
    });

    test('a chain out of cash fails and its stores pass on', () {
      final economy = CountryEconomy(_table(), seed: 1);
      final chain = _chain(economy, 'Knauser')..price = Fx.parse('0.70');
      final heirs = _chain(economy, 'Independent groceries');
      var month = 0;
      while (!chain.failed && month < 240) {
        final before = chain.stores;
        final inherited = heirs.stores;
        economy.advanceMonth();
        if (chain.failed) {
          expect(chain.stores, 0);
          expect(heirs.stores, greaterThan(inherited + before ~/ 2));
        }
        month++;
      }
      expect(chain.failed, isTrue);
      economy.advanceMonth();
      expect(chain.isTrading, isFalse);
      expect(chain.months.last.start.number, lessThan(economy.today.number));
    });
  });

  group('the cycle', () {
    test('hits discretionary trades and exposed countries hardest', () {
      final economy = _run(0);
      economy.regime = economy.table.regimes.indexWhere(
        (r) => r.key == 'recession',
      );
      final table = economy.table;
      final grocery = table.trades.indexWhere((t) => t.key == 'grocery');
      final electronics = table.trades.indexWhere(
        (t) => t.key == 'electronics',
      );
      final germany = table.countries.first;
      final spain = table.countries.last;
      expect(spain.name, 'Spain');
      expect(economy.demandIn(germany, grocery) < Fx.one, isTrue);
      expect(
        economy.demandIn(germany, grocery) >
            economy.demandIn(germany, electronics),
        isTrue,
      );
      expect(
        economy.demandIn(germany, electronics) >
            economy.demandIn(spain, electronics),
        isTrue,
      );
      // A real recession's size, not the shop-level game's 12%.
      expect(economy.demandIn(spain, grocery) > Fx.parse('0.9'), isTrue);
    });
  });

  group('over the years', () {
    test('why sales moved adds up exactly', () {
      final economy = _run(48);
      for (final country in economy.countries) {
        for (final chain in country.chains) {
          final why = economy.yearOnYear(country, chain)!;
          expect(
            why.before +
                why.population +
                why.income +
                why.prices +
                why.economy +
                why.share,
            why.after,
            reason: chain.def.name,
          );
        }
      }
      final name = 'Hansemarkt';
      final why = economy.yearOnYear(
        _home(economy, name),
        _chain(economy, name),
      )!;
      expect(why.prices > Money.zero, isTrue);
    });

    test('there is no comparison without two years', () {
      final economy = _run(23);
      final country = economy.countries.first;
      expect(economy.yearOnYear(country, country.chains.first), isNull);
    });

    test('forty years stay sound', () {
      for (final seed in [1, 2, 3]) {
        final economy = _run(480, seed: seed);
        for (final country in economy.countries) {
          // Prices compound, and households and real spending grow.
          expect(country.priceIndex > Fx.parse('1.3'), isTrue);
          expect(country.spendIndex.first.first >= Fx.one, isTrue);
          for (final (t, _) in economy.table.trades.indexed) {
            final mine = country.chains.where((c) => c.def.trade == t);
            var sales = 0;
            var profit = 0;
            var stores = 0;
            for (final chain in mine) {
              stores += chain.stores;
              if (!chain.isTrading) continue;
              for (final m in chain.months) {
                sales += m.sales.cents;
                profit += m.profit.cents;
              }
            }
            expect(stores, greaterThan(0));
            // Openings and closings hold margins near normal.
            expect(
              profit / sales,
              closeTo(country.def.trades[t].normalMargin.raw / Fx.scale, 0.025),
              reason: '${country.def.name} trade $t seed $seed',
            );
          }
        }
      }
    });
  });
}
