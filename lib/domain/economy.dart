/// Domain objects use integer cents and contain no Flutter dependencies.
class Product {
  const Product(this.id, this.name, this.referencePrice, this.wholesaleCost,
      this.productionCost, this.dailyDemandPerThousand);

  final String id;
  final String name;
  final int referencePrice;
  final int wholesaleCost;
  final int productionCost;
  final int dailyDemandPerThousand;
}

const products = [
  Product('water', 'Bottled water', 150, 80, 55, 400),
  Product('milk', 'Milk', 240, 155, 110, 200),
  Product('bread', 'Bread', 280, 170, 120, 250),
  Product('soda', 'Soft drinks', 220, 110, 75, 300),
  Product('snacks', 'Snacks', 180, 90, 60, 350),
  Product('coffee', 'Coffee', 350, 150, 95, 250),
  Product('soap', 'Household soap', 520, 310, 210, 50),
  Product('fruit', 'Fresh fruit', 190, 115, 80, 300),
];

class ConsumerSegment {
  const ConsumerSegment(this.id, this.households, this.monthlyIncome,
      this.retailBudgetBps, this.priceSensitivity);

  final String id;
  final int households;
  final int monthlyIncome;
  final int retailBudgetBps;
  final int priceSensitivity;

  int get dailyIncome => households * monthlyIncome ~/ 30;
  int get dailyBudget => dailyIncome * retailBudgetBps ~/ 10000;
}

const consumerSegments = [
  ConsumerSegment('budget', 300, 180000, 650, 5),
  ConsumerSegment('working', 350, 340000, 650, 4),
  ConsumerSegment('comfortable', 250, 600000, 650, 3),
  ConsumerSegment('affluent', 100, 1000000, 650, 2),
];

class _Lot {
  _Lot(this.quantity, this.unitCost);
  int quantity;
  final int unitCost;
}

/// Exact FIFO costing: purchases become inventory; only sold units become COGS.
class Stock {
  final List<_Lot> _lots = [];
  int _quantity = 0;
  int _value = 0;

  int get quantity => _quantity;
  int get bookValue => _value;

  void add(int quantity, int unitCost) {
    if (quantity <= 0 || unitCost <= 0) {
      throw ArgumentError('Stock quantity and unit cost must be positive.');
    }
    if (_lots.isNotEmpty && _lots.last.unitCost == unitCost) {
      _lots.last.quantity += quantity;
    } else {
      _lots.add(_Lot(quantity, unitCost));
    }
    _quantity += quantity;
    _value += quantity * unitCost;
  }

  int remove(int quantity) {
    if (quantity <= 0 || quantity > _quantity) {
      throw ArgumentError('Cannot remove $quantity units from $_quantity.');
    }
    var remaining = quantity;
    var cost = 0;
    while (remaining > 0) {
      final lot = _lots.first;
      final taken = remaining < lot.quantity ? remaining : lot.quantity;
      cost += taken * lot.unitCost;
      remaining -= taken;
      lot.quantity -= taken;
      if (lot.quantity == 0) {
        _lots.removeAt(0);
      }
    }
    _quantity -= quantity;
    _value -= cost;
    return cost;
  }

  void validate() {
    if (_lots.any((l) => l.quantity <= 0 || l.unitCost <= 0) ||
        _quantity != _lots.fold<int>(0, (v, l) => v + l.quantity) ||
        _value != _lots.fold<int>(0, (v, l) => v + l.quantity * l.unitCost)) {
      throw StateError('Inventory quantities and carrying value disagree.');
    }
  }

  List<Object> toJson() => [
        for (final lot in _lots)
          {'quantity': lot.quantity, 'unitCost': lot.unitCost},
      ];

  static Stock fromJson(List<dynamic> json) {
    final stock = Stock();
    for (final value in json) {
      final lot = value as Map<String, dynamic>;
      stock.add(lot['quantity'] as int, lot['unitCost'] as int);
    }
    return stock;
  }
}

int inventoryValue(Map<String, Stock> inventory) =>
    inventory.values.fold(0, (sum, stock) => sum + stock.bookValue);

class Store {
  Store({
    required this.id,
    required this.name,
    required this.playerControlled,
    required this.operatingCost,
    required this.appeal,
    required this.inventory,
    required this.prices,
    required this.restockTargets,
    this.autoRestock = true,
    this.isOpen = true,
    Map<String, int>? lastSales,
  }) : lastSales = lastSales ?? {for (final p in products) p.id: 0};

  final String id;
  final String name;
  final bool playerControlled;
  final int operatingCost;
  final int appeal;
  final Map<String, Stock> inventory;
  final Map<String, int> prices;
  final Map<String, int> restockTargets;
  final Map<String, int> lastSales;
  bool autoRestock;
  bool isOpen;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'playerControlled': playerControlled,
        'operatingCost': operatingCost,
        'appeal': appeal,
        'inventory': {for (final e in inventory.entries) e.key: e.value.toJson()},
        'prices': Map<String, int>.of(prices),
        'restockTargets': Map<String, int>.of(restockTargets),
        'lastSales': Map<String, int>.of(lastSales),
        'autoRestock': autoRestock,
        'isOpen': isOpen,
      };

  static Store fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as String,
        name: json['name'] as String,
        playerControlled: json['playerControlled'] as bool,
        operatingCost: json['operatingCost'] as int,
        appeal: json['appeal'] as int,
        inventory: {
          for (final e in (json['inventory'] as Map<String, dynamic>).entries)
            e.key: Stock.fromJson(e.value as List<dynamic>),
        },
        prices: Map<String, int>.from(json['prices'] as Map),
        restockTargets: Map<String, int>.from(json['restockTargets'] as Map),
        lastSales: Map<String, int>.from(json['lastSales'] as Map),
        autoRestock: json['autoRestock'] as bool,
        isOpen: json['isOpen'] as bool,
      );
}

class Supplier {
  Supplier(this.id, this.name, this.inventory, this.prices);
  final String id;
  final String name;
  final Map<String, Stock> inventory;
  final Map<String, int> prices;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'inventory': {for (final e in inventory.entries) e.key: e.value.toJson()},
        'prices': Map<String, int>.of(prices),
      };

  static Supplier fromJson(Map<String, dynamic> json) => Supplier(
        json['id'] as String,
        json['name'] as String,
        {
          for (final e in (json['inventory'] as Map<String, dynamic>).entries)
            e.key: Stock.fromJson(e.value as List<dynamic>),
        },
        Map<String, int>.from(json['prices'] as Map),
      );
}

/// A settled daily report. All monetary values are cents.
class BusinessReport {
  BusinessReport({
    required this.id,
    required this.retail,
    required this.openingCash,
    required this.closingCash,
    required this.openingInventory,
    required this.closingInventory,
    required this.revenue,
    required this.costOfGoodsSold,
    required this.inventoryPurchases,
    required this.operatingExpenses,
    required Map<String, int> unitsSold,
  }) : unitsSold = Map.unmodifiable(unitsSold);

  final String id;
  final bool retail;
  final int openingCash;
  final int closingCash;
  final int openingInventory;
  final int closingInventory;
  final int revenue;
  final int costOfGoodsSold;
  final int inventoryPurchases;
  final int operatingExpenses;
  final Map<String, int> unitsSold;
  int get profit => revenue - costOfGoodsSold - operatingExpenses;
  int get cashChange => closingCash - openingCash;

  void validate() {
    if (cashChange != revenue - inventoryPurchases - operatingExpenses ||
        closingInventory !=
            openingInventory + inventoryPurchases - costOfGoodsSold ||
        profit != cashChange + closingInventory - openingInventory) {
      throw StateError('Daily accounts do not reconcile for $id.');
    }
  }

  Map<String, Object> toJson() => {
        'id': id,
        'retail': retail,
        'openingCash': openingCash,
        'closingCash': closingCash,
        'openingInventory': openingInventory,
        'closingInventory': closingInventory,
        'revenue': revenue,
        'costOfGoodsSold': costOfGoodsSold,
        'inventoryPurchases': inventoryPurchases,
        'operatingExpenses': operatingExpenses,
        'unitsSold': unitsSold,
      };

  static BusinessReport fromJson(Map<String, dynamic> j) => BusinessReport(
        id: j['id'] as String,
        retail: j['retail'] as bool,
        openingCash: j['openingCash'] as int,
        closingCash: j['closingCash'] as int,
        openingInventory: j['openingInventory'] as int,
        closingInventory: j['closingInventory'] as int,
        revenue: j['revenue'] as int,
        costOfGoodsSold: j['costOfGoodsSold'] as int,
        inventoryPurchases: j['inventoryPurchases'] as int,
        operatingExpenses: j['operatingExpenses'] as int,
        unitsSold: Map<String, int>.from(j['unitsSold'] as Map),
      );
}

class DailyReport {
  DailyReport(this.day, Map<String, BusinessReport> businesses,
      Map<String, int> budgets, Map<String, int> spending,
      this.requestedUnits, this.soldUnits, List<String> notifications)
      : businesses = Map.unmodifiable(businesses),
        budgets = Map.unmodifiable(budgets),
        spending = Map.unmodifiable(spending),
        notifications = List.unmodifiable(notifications);

  final int day;
  final Map<String, BusinessReport> businesses;
  final Map<String, int> budgets;
  final Map<String, int> spending;
  final int requestedUnits;
  final int soldUnits;
  final List<String> notifications;
  int get unfulfilledUnits => requestedUnits - soldUnits;
  int get retailRevenue => businesses.values
      .where((b) => b.retail)
      .fold(0, (sum, b) => sum + b.revenue);

  /// Revenue shares; zero for every store when no retail sales take place.
  Map<String, double> get marketShares => {
        for (final b in businesses.values.where((b) => b.retail))
          b.id: retailRevenue == 0 ? 0 : b.revenue / retailRevenue,
      };

  void validate() {
    for (final b in businesses.values) {
      b.validate();
    }
    if (retailRevenue != spending.values.fold<int>(0, (v, s) => v + s) ||
        spending.entries.any((e) => e.value < 0 || e.value > budgets[e.key]!) ||
        soldUnits < 0 || soldUnits > requestedUnits) {
      throw StateError('Consumer spending and retail sales disagree.');
    }
  }

  Map<String, Object> toJson() => {
        'day': day,
        'businesses': {for (final e in businesses.entries) e.key: e.value.toJson()},
        'budgets': budgets,
        'spending': spending,
        'requestedUnits': requestedUnits,
        'soldUnits': soldUnits,
        'notifications': notifications,
      };

  static DailyReport fromJson(Map<String, dynamic> j) => DailyReport(
        j['day'] as int,
        {
          for (final e in (j['businesses'] as Map<String, dynamic>).entries)
            e.key: BusinessReport.fromJson(e.value as Map<String, dynamic>),
        },
        Map<String, int>.from(j['budgets'] as Map),
        Map<String, int>.from(j['spending'] as Map),
        j['requestedUnits'] as int,
        j['soldUnits'] as int,
        List<String>.from(j['notifications'] as List),
      );
}
