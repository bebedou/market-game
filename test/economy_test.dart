import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/domain/economy.dart';
import 'package:market_game/domain/ledger.dart';
import 'package:market_game/simulation/demand.dart';
import 'package:market_game/simulation/seeded_random.dart';
import 'package:market_game/simulation/simulation.dart';

void emptyStore(Store store) {
  for (final stock in store.inventory.values) {
    if (stock.quantity > 0) {
      stock.remove(stock.quantity);
    }
  }
}

void main() {
  group('Inventory and ledger', () {
    test('FIFO costs reconcile across differently priced purchases', () {
      final stock = Stock()
        ..add(5, 100)
        ..add(5, 140);
      expect(stock.quantity, 10);
      expect(stock.bookValue, 1200);
      expect(stock.remove(7), 780);
      expect(stock.quantity, 3);
      expect(stock.bookValue, 420);
      stock.validate();
      expect(stock.remove(3), 420);
      expect(stock.quantity, 0);
      expect(stock.bookValue, 0);
    });

    test('Invalid stock operations are atomic', () {
      final stock = Stock()..add(2, 150);
      final before = jsonEncode(stock.toJson());
      for (final quantity in [-1, 0, 3]) {
        expect(() => stock.remove(quantity), throwsArgumentError);
      }
      expect(() => stock.add(1, 0), throwsArgumentError);
      expect(jsonEncode(stock.toJson()), before);
    });

    test(
      'Transfers conserve money and reject overdrafts without partial writes',
      () {
        final ledger = Ledger({
          outsideAccount: 0,
          'buyer': 1000,
          'seller': 500,
        });
        ledger.transfer('buyer', 'seller', 400, TransferKind.retailSale);
        expect(ledger.balance('buyer'), 600);
        expect(ledger.balance('seller'), 900);
        expect(ledger.totalCash, 1500);
        final before = jsonEncode(ledger.toJson());
        expect(
          () =>
              ledger.transfer('buyer', 'seller', 601, TransferKind.retailSale),
          throwsStateError,
        );
        expect(
          () => ledger.transfer('buyer', 'missing', 1, TransferKind.retailSale),
          throwsArgumentError,
        );
        expect(
          () => ledger.transfer('buyer', 'seller', -1, TransferKind.retailSale),
          throwsArgumentError,
        );
        expect(jsonEncode(ledger.toJson()), before);
        ledger.transfer(outsideAccount, 'buyer', 200, TransferKind.income);
        expect(ledger.balance(outsideAccount), -200);
        expect(ledger.totalCash, 1500);
        ledger.validate();
      },
    );
  });

  group('Consumer economy', () {
    test(
      'Neighborhood contains 1,000 households, eight products and five businesses',
      () {
        final sim = Simulation.neighborhood();
        expect(consumerSegments.fold<int>(0, (n, s) => n + s.households), 1000);
        expect(products.length, 8);
        expect(sim.stores.length, 3);
        expect(sim.suppliers.length, 2);
        expect(sim.stores.where((s) => s.playerControlled).length, 1);
      },
    );

    test(
      'Lower prices attract more demand, especially from sensitive households',
      () {
        final p = products.first;
        final cheap = p.referencePrice * 80 ~/ 100;
        final budget = consumerSegments.first;
        final affluent = consumerSegments.last;
        expect(
          ConsumerDemand.storeWeight(budget, p, cheap, 100),
          greaterThan(
            ConsumerDemand.storeWeight(budget, p, p.referencePrice, 100),
          ),
        );
        expect(
          ConsumerDemand.storeWeight(budget, p, cheap, 100),
          greaterThan(ConsumerDemand.storeWeight(affluent, p, cheap, 100)),
        );
        expect(
          ConsumerDemand.storeWeight(budget, p, p.referencePrice * 2, 100),
          0,
        );
      },
    );

    test('Realized sales respond to player prices across a month', () {
      final cheap = Simulation.neighborhood(seed: 7);
      final expensive = Simulation.neighborhood(seed: 7);
      for (final p in products) {
        cheap.setPlayerPrice(p.id, p.referencePrice * 70 ~/ 100);
        expensive.setPlayerPrice(p.id, p.referencePrice * 150 ~/ 100);
      }
      var cheapUnits = 0;
      var expensiveUnits = 0;
      for (var day = 0; day < 30; day++) {
        cheapUnits += cheap
            .advanceDay()
            .businesses['player']!
            .unitsSold
            .values
            .fold<int>(0, (a, b) => a + b);
        expensiveUnits += expensive
            .advanceDay()
            .businesses['player']!
            .unitsSold
            .values
            .fold<int>(0, (a, b) => a + b);
      }
      expect(cheapUnits, greaterThan(expensiveUnits * 2));
    });

    test(
      'Every day reconciles consumer budgets, journal, inventory and business profit',
      () {
        final sim = Simulation.neighborhood();
        var purchases = 0;
        for (var day = 0; day < 30; day++) {
          final report = sim.advanceDay();
          report.validate();
          sim.ledger.validate();
          expect(report.retailRevenue, greaterThan(0));
          expect(
            report.marketShares.values.fold<double>(0, (a, b) => a + b),
            closeTo(1, 0.00000001),
          );
          for (final segment in consumerSegments) {
            expect(
              report.spending[segment.id],
              lessThanOrEqualTo(segment.dailyBudget),
            );
            expect(sim.ledger.balance(segment.id), greaterThanOrEqualTo(0));
          }
          final retailTransfers = sim.ledger.entries
              .where((t) => t.kind == TransferKind.retailSale)
              .fold<int>(0, (sum, t) => sum + t.amount);
          final wholesaleTransfers = sim.ledger.entries
              .where((t) => t.kind == TransferKind.wholesaleSale)
              .fold<int>(0, (sum, t) => sum + t.amount);
          expect(retailTransfers, report.retailRevenue);
          expect(
            wholesaleTransfers,
            report.businesses.values
                .where((b) => b.retail)
                .fold<int>(0, (sum, b) => sum + b.inventoryPurchases),
          );
          for (final business in report.businesses.values) {
            expect(
              business.profit,
              business.cashChange +
                  business.closingInventory -
                  business.openingInventory,
            );
            expect(
              business.closingInventory,
              business.openingInventory +
                  business.inventoryPurchases -
                  business.costOfGoodsSold,
            );
            purchases += business.inventoryPurchases;
          }
          for (final s in sim.stores) {
            for (final stock in s.inventory.values) {
              expect(stock.quantity, greaterThanOrEqualTo(0));
            }
          }
        }
        expect(purchases, greaterThan(0));
      },
    );

    test(
      'Empty shelves produce unfulfilled demand without negative inventory',
      () {
        final sim = Simulation.neighborhood();
        for (final store in sim.stores) {
          store.autoRestock = false;
          emptyStore(store);
        }
        final report = sim.advanceDay();
        expect(report.requestedUnits, greaterThan(0));
        expect(report.soldUnits, 0);
        expect(report.retailRevenue, 0);
        expect(report.unfulfilledUnits, report.requestedUnits);
        expect(report.marketShares.values, everyElement(0));
        sim.validate();
      },
    );

    test(
      'Households may leave the market when all offers exceed reservation prices',
      () {
        final sim = Simulation.neighborhood();
        for (final store in sim.stores) {
          for (final p in products) {
            store.prices[p.id] = 1000000;
          }
        }
        final report = sim.advanceDay();
        expect(report.soldUnits, 0);
        expect(report.spending.values, everyElement(0));
      },
    );

    test('Restocking respects available cash', () {
      final sim = Simulation.neighborhood();
      emptyStore(sim.player);
      sim.ledger.transfer(
        'player',
        outsideAccount,
        sim.ledger.balance('player') - sim.player.operatingCost - 100,
        TransferKind.operatingCost,
      );
      final report = sim.advanceDay();
      expect(
        report.businesses['player']!.inventoryPurchases,
        lessThanOrEqualTo(100),
      );
      expect(sim.ledger.balance('player'), greaterThanOrEqualTo(0));
      sim.validate();
    });

    test('An insolvent store closes without a bailout or an overdraft', () {
      final sim = Simulation.neighborhood();
      sim.ledger.transfer(
        'player',
        outsideAccount,
        sim.ledger.balance('player'),
        TransferKind.operatingCost,
      );
      final report = sim.advanceDay();
      expect(sim.player.isOpen, isFalse);
      expect(sim.ledger.balance('player'), 0);
      expect(report.businesses['player']!.revenue, 0);
      expect(report.notifications.any((n) => n.contains('closed')), isTrue);
    });

    test(
      'AI raises a product price after selling out; player pricing stays controlled',
      () {
        final sim = Simulation.neighborhood();
        sim.advanceDay();
        final rival = sim.stores[1];
        final stock = rival.inventory['water']!;
        if (stock.quantity > 0) {
          stock.remove(stock.quantity);
        }
        rival.lastSales['water'] = 100;
        final previous = rival.prices['water']!;
        final playerPrice = sim.player.prices['water'];
        sim.advanceDay();
        expect(rival.prices['water'], greaterThan(previous));
        expect(sim.player.prices['water'], playerPrice);
      },
    );

    test('Invalid controls fail before changing player prices or targets', () {
      final sim = Simulation.neighborhood();
      final before = jsonEncode(sim.toJson());
      expect(() => sim.setPlayerPrice('milk', 0), throwsArgumentError);
      expect(() => sim.setPlayerPrice('missing', 100), throwsArgumentError);
      expect(() => sim.setPlayerRestockTarget('milk', -1), throwsArgumentError);
      expect(jsonEncode(sim.toJson()), before);
    });
  });

  group('Determinism', () {
    test('PRNG agrees with published Park–Miller state sequence', () {
      final random = SeededRandom(0);
      for (final expected in [
        16807,
        282475249,
        1622650073,
        984943658,
        1144108930,
      ]) {
        random.nextInt(100);
        expect(random.state, expected);
      }
      expect(() => SeededRandom.fromState(0), throwsArgumentError);
    });

    test(
      'Identical seeds reproduce the full state and different seeds diverge',
      () {
        final first = Simulation.neighborhood(seed: 42);
        final second = Simulation.neighborhood(seed: 42);
        final third = Simulation.neighborhood(seed: 43);
        for (var i = 0; i < 60; i++) {
          first.advanceDay();
          second.advanceDay();
          third.advanceDay();
          expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
        }
        expect(jsonEncode(first.toJson()), isNot(jsonEncode(third.toJson())));
      },
    );

    test(
      'JSON snapshot resumes the same future, including random and FIFO states',
      () {
        final uninterrupted = Simulation.neighborhood(seed: 17);
        for (var i = 0; i < 17; i++) {
          uninterrupted.advanceDay();
        }
        final snapshot =
            jsonDecode(jsonEncode(uninterrupted.toJson()))
                as Map<String, dynamic>;
        final resumed = Simulation.fromJson(snapshot);
        expect(
          jsonEncode(uninterrupted.toJson()),
          jsonEncode(resumed.toJson()),
        );
        for (var i = 0; i < 60; i++) {
          uninterrupted.advanceDay();
          resumed.advanceDay();
          expect(
            jsonEncode(uninterrupted.toJson()),
            jsonEncode(resumed.toJson()),
          );
        }
        expect(
          () => Simulation.fromJson({'schemaVersion': 999}),
          throwsFormatException,
        );
      },
    );

    test(
      '10,000 days preserve invariants and the baseline neighborhood stays viable',
      () {
        final sim = Simulation.neighborhood(seed: 42);
        final initialCash = sim.ledger.totalCash;
        for (var day = 0; day < 10000; day++) {
          sim.advanceDay(); // Audits cash, inventory, spending and profit each day.
        }
        expect(sim.day, 10000);
        expect(sim.ledger.totalCash, initialCash);
        expect(sim.stores.every((s) => s.isOpen), isTrue);
        expect(
          sim.stores.every((s) => sim.ledger.balance(s.id) > 2500000),
          isTrue,
        );
        expect(sim.ledger.entries.length, lessThan(250));
        expect(
          sim.lastReport!.marketShares.values.every((s) => s > 0.05),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
