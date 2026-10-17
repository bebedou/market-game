import '../domain/economy.dart';
import '../domain/ledger.dart';
import 'demand.dart';
import 'seeded_random.dart';

int _min(int a, int b) => a < b ? a : b;

class _DayBook {
  _DayBook(this.id, this.retail, this.openingCash, this.openingInventory);
  final String id;
  final bool retail;
  final int openingCash;
  final int openingInventory;
  int revenue = 0;
  int costOfGoodsSold = 0;
  int inventoryPurchases = 0;
  int operatingExpenses = 0;
  final unitsSold = {for (final p in products) p.id: 0};

  BusinessReport close(int cash, int inventory) => BusinessReport(
        id: id, retail: retail, openingCash: openingCash, closingCash: cash,
        openingInventory: openingInventory, closingInventory: inventory,
        revenue: revenue, costOfGoodsSold: costOfGoodsSold,
        inventoryPurchases: inventoryPurchases,
        operatingExpenses: operatingExpenses, unitsSold: unitsSold,
      );
}

/// Daily economic engine, independent of Flutter, timers, storage, and services.
class Simulation {
  Simulation._(this.day, this.random, this.ledger, this.stores, this.suppliers,
      this.lastReport) {
    validate();
  }

  factory Simulation.neighborhood({int seed = 42}) {
    final stores = <Store>[];
    for (var i = 0; i < 3; i++) {
      final inventory = <String, Stock>{};
      final targets = <String, int>{};
      for (final p in products) {
        final target = ((p.dailyDemandPerThousand + 2) ~/ 3) * 3;
        targets[p.id] = target;
        inventory[p.id] = Stock()..add(target, p.wholesaleCost);
      }
      stores.add(Store(
        id: i == 0 ? 'player' : 'competitor_$i',
        name: ['Corner & Co.', 'Quick Stop', 'Neighborhood Mart'][i],
        playerControlled: i == 0,
        operatingCost: [8000, 9000, 8500][i],
        appeal: [100, 105, 95][i],
        inventory: inventory,
        prices: {for (final p in products)
          p.id: p.referencePrice * [100, 97, 104][i] ~/ 100},
        restockTargets: targets,
      ));
    }
    final suppliers = [
      for (var i = 0; i < 2; i++)
        Supplier('supplier_$i', ['Metro Wholesale', 'Value Supply'][i], {
          for (final p in products)
            p.id: Stock()..add(p.dailyDemandPerThousand * 2, p.productionCost),
        }, {for (final p in products) p.id: p.wholesaleCost}),
    ];
    final ledger = Ledger({
      outsideAccount: 0,
      for (final store in stores) store.id: 2500000,
      for (final supplier in suppliers) supplier.id: 1000000,
      for (final segment in consumerSegments) segment.id: 0,
    });
    return Simulation._(0, SeededRandom(seed), ledger,
        List.unmodifiable(stores), List.unmodifiable(suppliers), null);
  }

  int day;
  final SeededRandom random;
  final Ledger ledger;
  final List<Store> stores;
  final List<Supplier> suppliers;
  DailyReport? lastReport;
  Store get player => stores.singleWhere((s) => s.playerControlled);

  void setPlayerPrice(String productId, int cents) {
    if (!player.prices.containsKey(productId) || cents <= 0 || cents > 1000000) {
      throw ArgumentError('Unknown product or price outside 1..1,000,000 cents.');
    }
    player.prices[productId] = cents;
  }

  void setPlayerRestockTarget(String productId, int units) {
    if (!player.restockTargets.containsKey(productId) || units < 0 || units > 10000) {
      throw ArgumentError('Unknown product or restock target outside 0..10,000.');
    }
    player.restockTargets[productId] = units;
  }

  DailyReport advanceDay() {
    validate();
    day++;
    ledger.beginDay();
    final notifications = <String>[];
    final books = {
      for (final s in stores)
        s.id: _DayBook(s.id, true, ledger.balance(s.id), inventoryValue(s.inventory)),
      for (final s in suppliers)
        s.id: _DayBook(s.id, false, ledger.balance(s.id), inventoryValue(s.inventory)),
    };
    for (final segment in consumerSegments) {
      ledger.transfer(outsideAccount, segment.id, segment.dailyIncome, TransferKind.income);
    }
    _updateSuppliers(books);
    _updateCompetitorPrices();
    final restockOrder = stores.toList();
    random.shuffle(restockOrder);
    for (final store in restockOrder) {
      final book = books[store.id]!;
      if (!store.isOpen) {
        continue;
      }
      if (ledger.balance(store.id) < store.operatingCost) {
        store.isOpen = false;
        notifications.add('${store.name} closed: unable to fund daily operating costs.');
        continue;
      }
      if (store.operatingCost > 0) {
        ledger.transfer(store.id, outsideAccount, store.operatingCost,
            TransferKind.operatingCost);
      }
      book.operatingExpenses += store.operatingCost;
      if (store.autoRestock) {
        _restock(store, books);
      }
    }
    final budgets = {for (final s in consumerSegments) s.id: s.dailyBudget};
    final spending = {for (final s in consumerSegments) s.id: 0};
    var requested = 0;
    var sold = 0;
    final segmentOrder = consumerSegments.toList();
    random.shuffle(segmentOrder);
    for (final segment in segmentOrder) {
      var budget = _min(budgets[segment.id]!, ledger.balance(segment.id));
      final productOrder = products.toList();
      random.shuffle(productOrder);
      for (final p in productOrder) {
        final desired = ConsumerDemand.desiredUnits(segment, p, day, random);
        requested += desired;
        final weights = [for (final store in stores)
          store.isOpen ? ConsumerDemand.storeWeight(segment, p,
              store.prices[p.id]!, store.appeal) : 0];
        final purchases = List<int>.filled(stores.length, 0);
        // Allocate units individually but settle each segment/product/store in
        // one journal entry, keeping the daily journal and memory bounded.
        for (var unit = 0; unit < desired; unit++) {
          var total = ConsumerDemand.outsideWeight;
          final eligible = List<int>.filled(stores.length, 0);
          for (var i = 0; i < stores.length; i++) {
            final store = stores[i];
            if (store.prices[p.id]! <= budget &&
                store.inventory[p.id]!.quantity > purchases[i]) {
              eligible[i] = weights[i];
              total += eligible[i];
            }
          }
          if (total == ConsumerDemand.outsideWeight) {
            break;
          }
          var draw = random.nextInt(total);
          for (var i = 0; i < stores.length; i++) {
            if (draw < eligible[i]) {
              purchases[i]++;
              budget -= stores[i].prices[p.id]!;
              break;
            }
            draw -= eligible[i];
          }
        }
        for (var i = 0; i < stores.length; i++) {
          final quantity = purchases[i];
          if (quantity == 0) {
            continue;
          }
          final store = stores[i];
          final amount = quantity * store.prices[p.id]!;
          final cost = store.inventory[p.id]!.remove(quantity);
          ledger.transfer(segment.id, store.id, amount, TransferKind.retailSale);
          books[store.id]!.revenue += amount;
          books[store.id]!.costOfGoodsSold += cost;
          books[store.id]!.unitsSold[p.id] = books[store.id]!.unitsSold[p.id]! + quantity;
          spending[segment.id] = spending[segment.id]! + amount;
          sold += quantity;
        }
      }
    }
    for (final store in stores) {
      store.lastSales.addAll(books[store.id]!.unitsSold);
      if (store.isOpen && store.inventory.values.any((s) => s.quantity == 0)) {
        notifications.add('${store.name} has empty shelves.');
      }
    }
    final reports = {
      for (final s in stores)
        s.id: books[s.id]!.close(ledger.balance(s.id), inventoryValue(s.inventory)),
      for (final s in suppliers)
        s.id: books[s.id]!.close(ledger.balance(s.id), inventoryValue(s.inventory)),
    };
    final report = DailyReport(day, reports, budgets, spending,
        requested, sold, notifications);
    lastReport = report;
    validate();
    return report;
  }

  void _updateSuppliers(Map<String, _DayBook> books) {
    for (var i = 0; i < suppliers.length; i++) {
      final supplier = suppliers[i];
      for (var j = 0; j < products.length; j++) {
        final p = products[j];
        final stock = supplier.inventory[p.id]!;
        final scarcity = stock.quantity < p.dailyDemandPerThousand ? 5 : 0;
        final bias = (i + j).isEven ? -4 : 4;
        supplier.prices[p.id] = p.wholesaleCost *
            (100 + bias + scarcity + random.nextInt(5) - 2) ~/ 100;
        final required = p.dailyDemandPerThousand * 2 - stock.quantity;
        final quantity = _min(required, ledger.balance(supplier.id) ~/ p.productionCost);
        if (quantity <= 0) {
          continue;
        }
        final cost = quantity * p.productionCost;
        ledger.transfer(supplier.id, outsideAccount, cost, TransferKind.procurement);
        stock.add(quantity, p.productionCost);
        books[supplier.id]!.inventoryPurchases += cost;
      }
    }
  }

  void _updateCompetitorPrices() {
    if (day == 1) {
      return;
    }
    for (final store in stores.where((s) => !s.playerControlled && s.isOpen)) {
      for (final p in products) {
        final current = store.prices[p.id]!;
        final expected = (p.dailyDemandPerThousand + 2) ~/ 3;
        final cheapestRetail = stores.where((s) => s.isOpen)
            .map((s) => s.prices[p.id]!).reduce(_min);
        final cheapestWholesale = suppliers.map((s) => s.prices[p.id]!).reduce(_min);
        final step = current ~/ 50 < 1 ? 1 : current ~/ 50;
        var next = current;
        if (store.inventory[p.id]!.quantity == 0 && store.lastSales[p.id]! > 0) {
          next += step;
        } else if (store.lastSales[p.id]! < expected * 8 ~/ 10 ||
            current * 100 > cheapestRetail * 110) {
          next -= step;
        } else if (current < p.referencePrice) {
          next += 1;
        } else if (current > p.referencePrice) {
          next -= 1;
        }
        final floor = cheapestWholesale * 120 ~/ 100;
        final ceiling = p.referencePrice * 125 ~/ 100;
        store.prices[p.id] = next.clamp(floor, ceiling).toInt();
      }
    }
  }

  void _restock(Store store, Map<String, _DayBook> books) {
    for (final p in products) {
      var needed = store.restockTargets[p.id]! - store.inventory[p.id]!.quantity;
      final offers = suppliers.toList()
        ..sort((a, b) {
          final byPrice = a.prices[p.id]!.compareTo(b.prices[p.id]!);
          return byPrice == 0 ? a.id.compareTo(b.id) : byPrice;
        });
      for (final supplier in offers) {
        if (needed <= 0) {
          break;
        }
        final price = supplier.prices[p.id]!;
        final quantity = _min(needed, _min(supplier.inventory[p.id]!.quantity,
            ledger.balance(store.id) ~/ price));
        if (quantity <= 0) {
          continue;
        }
        final amount = quantity * price;
        final cost = supplier.inventory[p.id]!.remove(quantity);
        ledger.transfer(store.id, supplier.id, amount, TransferKind.wholesaleSale);
        store.inventory[p.id]!.add(quantity, price);
        books[store.id]!.inventoryPurchases += amount;
        books[supplier.id]!.revenue += amount;
        books[supplier.id]!.costOfGoodsSold += cost;
        books[supplier.id]!.unitsSold[p.id] =
            books[supplier.id]!.unitsSold[p.id]! + quantity;
        needed -= quantity;
      }
    }
  }

  void validate() {
    if (day < 0 || stores.length != 3 || suppliers.length != 2 ||
        stores.where((s) => s.playerControlled).length != 1) {
      throw StateError('Invalid neighborhood structure.');
    }
    final accountIds = [outsideAccount, ...stores.map((s) => s.id),
      ...suppliers.map((s) => s.id), ...consumerSegments.map((s) => s.id)];
    if (accountIds.toSet().length != accountIds.length ||
        accountIds.length != ledger.balances.length ||
        accountIds.any((id) => !ledger.balances.containsKey(id))) {
      throw StateError('Invalid neighborhood accounts.');
    }
    ledger.validate();
    for (final store in stores) {
      if (store.operatingCost < 0 || store.appeal <= 0 ||
          store.inventory.length != products.length ||
          store.prices.length != products.length ||
          store.restockTargets.length != products.length ||
          store.lastSales.length != products.length) {
        throw StateError('Invalid store configuration.');
      }
      for (final p in products) {
        if (!store.inventory.containsKey(p.id) ||
            (store.prices[p.id] ?? 0) <= 0 || store.prices[p.id]! > 1000000 ||
            (store.restockTargets[p.id] ?? -1) < 0 ||
            store.restockTargets[p.id]! > 10000 || (store.lastSales[p.id] ?? -1) < 0) {
          throw StateError('Invalid product controls.');
        }
        store.inventory[p.id]!.validate();
      }
    }
    for (final supplier in suppliers) {
      if (supplier.inventory.length != products.length ||
          supplier.prices.length != products.length) {
        throw StateError('Invalid supplier configuration.');
      }
      for (final p in products) {
        if (!supplier.inventory.containsKey(p.id) ||
            (supplier.prices[p.id] ?? 0) <= 0) {
          throw StateError('Invalid supplier offer.');
        }
        supplier.inventory[p.id]!.validate();
      }
    }
    lastReport?.validate();
    if (lastReport != null && lastReport!.day != day) {
      throw StateError('Report is from a different day.');
    }
  }

  /// Snapshot data is versioned; file/browser persistence remains a UI concern.
  Map<String, Object?> toJson() => {
        'schemaVersion': 1, 'day': day, 'randomState': random.state,
        'ledger': ledger.toJson(),
        'stores': [for (final s in stores) s.toJson()],
        'suppliers': [for (final s in suppliers) s.toJson()],
        'lastReport': lastReport?.toJson(),
      };

  static Simulation fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1) {
      throw const FormatException('Unsupported simulation schema.');
    }
    return Simulation._(
      j['day'] as int,
      SeededRandom.fromState(j['randomState'] as int),
      Ledger.fromJson(j['ledger'] as Map<String, dynamic>),
      List.unmodifiable([for (final s in j['stores'] as List)
        Store.fromJson(s as Map<String, dynamic>)]),
      List.unmodifiable([for (final s in j['suppliers'] as List)
        Supplier.fromJson(s as Map<String, dynamic>)]),
      j['lastReport'] == null ? null :
          DailyReport.fromJson(j['lastReport'] as Map<String, dynamic>),
    );
  }
}
