import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';
import 'history.dart';

/// One delivery's worth of a product on hand.
final class Lot {
  Lot({required this.quantity, required this.unitCost, required this.expiry});

  Lot.read(StateReader reader)
    : quantity = reader.readInt(),
      unitCost = Money(reader.readInt()),
      expiry = reader.readBool() ? Day(reader.readInt()) : null;

  int quantity;
  final Money unitCost;

  /// The first day the lot can no longer be sold; null if it never expires.
  final Day? expiry;

  void write(StateWriter writer) {
    writer
      ..writeInt(quantity)
      ..writeInt(unitCost.cents)
      ..writeBool(expiry != null);
    if (expiry case final day?) writer.writeInt(day.number);
  }
}

/// Units taken out of stock, and their cost.
typedef Withdrawal = ({int units, Money cost});

/// A store's stock of one product: lots in arrival order, sold oldest first.
final class Stock {
  Stock() : _lots = [];

  Stock.read(StateReader reader)
    : _lots = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Lot.read(reader),
      ];

  final List<Lot> _lots;

  List<Lot> get lots => List.unmodifiable(_lots);

  int get units => _lots.fold(0, (sum, lot) => sum + lot.quantity);

  /// The stock's value at cost.
  Money get value => _lots.fold(
    Money.zero,
    (sum, lot) => sum + lot.unitCost.timesInt(lot.quantity),
  );

  void receive(int quantity, Money unitCost, Day? expiry) {
    assert(quantity > 0, 'Received $quantity units');
    _lots.add(Lot(quantity: quantity, unitCost: unitCost, expiry: expiry));
  }

  /// Takes up to [wanted] units, oldest lots first.
  Withdrawal take(int wanted) {
    var units = 0;
    var cost = Money.zero;
    while (units < wanted && _lots.isNotEmpty) {
      final lot = _lots.first;
      final remaining = wanted - units;
      final taken = lot.quantity < remaining ? lot.quantity : remaining;
      lot.quantity -= taken;
      units += taken;
      cost += lot.unitCost.timesInt(taken);
      if (lot.quantity == 0) _lots.removeAt(0);
    }
    return (units: units, cost: cost);
  }

  /// Removes every lot that has expired by [today].
  Withdrawal expire(Day today) {
    final expired = [
      for (final lot in _lots)
        if (lot.expiry case final expiry? when expiry <= today) lot,
    ];
    _lots.removeWhere(expired.contains);
    return _total(expired);
  }

  /// Removes everything.
  Withdrawal clear() {
    final all = List.of(_lots);
    _lots.clear();
    return _total(all);
  }

  void write(StateWriter writer) {
    writer.writeInt(_lots.length);
    for (final lot in _lots) {
      lot.write(writer);
    }
  }

  static Withdrawal _total(List<Lot> lots) => (
    units: lots.fold(0, (sum, lot) => sum + lot.quantity),
    cost: lots.fold(
      Money.zero,
      (sum, lot) => sum + lot.unitCost.timesInt(lot.quantity),
    ),
  );
}

/// Append only.
enum StoreStatus {
  /// Being fitted out: it can list products and receive stock, but has no
  /// customers yet.
  building,
  open,

  /// Closed for good; its site is free.
  closed,
}

/// Building works enlarging a store to [area] square metres, in use from
/// [done].
/// Building works on a store: the area it will have, when they finish,
/// and the format it becomes, if it changes.
typedef Works = ({int area, Day done, FormatId? format});

/// What a store manager is asked to look after. Append only.
enum ManagerDuty {
  ordering,

  /// Prices and marketing.
  pricing,
  assortment,
  staffing,

  /// Enlarging the store and converting it to a dearer format of its
  /// channel, from the company's cash beyond a reserve, as an owner would.
  investing,
}

/// [duties] given for the duties there were when they were recorded,
/// those added since off.
List<bool> allDuties(List<bool> duties) => [
  for (var i = 0; i < ManagerDuty.values.length; i++)
    i < duties.length && duties[i],
];

/// A manager running a store for its owner, by a strategy, within [duties].
final class Manager {
  Manager({
    required this.grade,
    required this.strategy,
    required this.duties,
    required this.hiredOn,
  });

  Manager.read(StateReader reader)
    : grade = ManagerGradeId(reader.readInt()),
      strategy = StrategyId(reader.readInt()),
      duties = List.unmodifiable(
        allDuties([
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readBool(),
        ]),
      ),
      hiredOn = Day(reader.readInt());

  final ManagerGradeId grade;
  final StrategyId strategy;

  /// Indexed by [ManagerDuty].
  final List<bool> duties;
  final Day hiredOn;

  bool does(ManagerDuty duty) => duties[duty.index];

  void write(StateWriter writer) {
    writer
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(duties.length);
    duties.forEach(writer.writeBool);
    writer.writeInt(hiredOn.number);
  }
}

/// A business on a site: a grocery store, a restaurant, whatever its format
/// sells.
final class Store {
  Store({
    required this.id,
    required this.name,
    required this.company,
    required this.site,
    required this.status,
    required this.opensOn,
    required this.market,
    required this.location,
    required this.shelfSlots,
    required this.storageUnits,
    required this.prices,
    required this.stock,
    required this.history,
    required this.staff,
    required this.service,
    required this.traffic,
    required this.area,
    this.format = const FormatId(0),
    this.manager,
    this.works,
    this.enlargedOn,
    this.marketingShare = Fx.zero,
    this.goodwill = Money.zero,
    this.boughtFor = Money.zero,
    this.acquiredOn,
    this.reputation = Fx.zero,
  });

  Store.read(this.id, StateReader reader)
    : name = reader.readString(),
      company = CompanyId(reader.readInt()),
      site = SiteId(reader.readInt()),
      status = StoreStatus.values[reader.readInt()],
      opensOn = Day(reader.readInt()),
      market = MarketId(reader.readInt()),
      location = Fx.raw(reader.readInt()),
      shelfSlots = reader.readInt(),
      storageUnits = reader.readInt(),
      prices = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          reader.readBool() ? Money(reader.readInt()) : null,
      ],
      stock = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Stock.read(reader),
      ],
      history = SalesHistory.read(reader),
      staff = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
      ],
      service = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ],
      traffic = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
      ],
      manager = reader.readBool() ? Manager.read(reader) : null,
      area = reader.readInt(),
      works = reader.readBool()
          ? (
              area: reader.readInt(),
              done: Day(reader.readInt()),
              format: reader.version >= 11
                  ? switch (reader.readNullableInt()) {
                      final format? => FormatId(format),
                      null => null,
                    }
                  : null,
            )
          : null,
      enlargedOn = switch (reader.readNullableInt()) {
        final day? => Day(day),
        null => null,
      },
      format = reader.version >= 10
          ? FormatId(reader.readInt())
          : const FormatId(0),
      // Format 10 kept a daily budget in money, which goodwill replaced.
      marketingShare = reader.version >= 11
          ? Fx.raw(reader.readInt())
          : _skipped(reader, reader.version >= 10, Fx.zero),
      goodwill = reader.version >= 11 ? Money(reader.readInt()) : Money.zero,
      boughtFor = reader.version >= 13 ? Money(reader.readInt()) : Money.zero,
      acquiredOn = reader.version >= 13
          ? switch (reader.readNullableInt()) {
              final day? => Day(day),
              null => null,
            }
          : null,
      reputation = reader.version >= 17
          ? Fx.raw(reader.readInt())
          : Fx.zero;

  static T _skipped<T>(StateReader reader, bool present, T value) {
    if (present) reader.readInt();
    return value;
  }

  final StoreId id;
  String name;

  /// The owner, which changes when the store is sold.
  CompanyId company;
  final SiteId site;
  StoreStatus status;

  /// The first trading day.
  final Day opensOn;
  final MarketId market;

  /// How convenient the store's location is, from 0 to 1.
  final Fx location;

  /// How many different products the store can list.
  int shelfSlots;

  /// How many units of stock fit in the store, all products together.
  int storageUnits;

  /// Selling area in square metres. Bigger stores draw more shoppers and
  /// pay more rent.
  int area;

  /// Enlargement under way, if any.
  Works? works;

  /// When the store last grew, if ever.
  Day? enlargedOn;

  /// What kind of business it is, which sets what it may sell. Works can
  /// change it.
  FormatId format;

  /// The share of its recent sales it spends on marketing each day.
  Fx marketingShare;

  /// What its advertising has built up, wearing off day by day.
  Money goodwill;

  /// What its owner paid for it beyond its stock, carried in the owner's
  /// business assets; zero if the owner opened it.
  Money boughtFor;

  /// When its owner bought it, if they did.
  Day? acquiredOn;

  /// What the store sold a day, at today's shelf prices, over the last
  /// [days] days before [today], or as many as it has been open.
  Money recentDailySales(Day today, {int days = 7}) {
    final open = today.number - opensOn.number;
    final counted = open < days ? open : days;
    if (counted <= 0) return Money.zero;
    var total = Money.zero;
    for (var product = 0; product < prices.length; product++) {
      final price = prices[product];
      if (price == null) continue;
      var units = 0;
      for (var ago = 1; ago <= counted; ago++) {
        units += history.at(
          SalesCount.sold,
          ProductId(product),
          Day(today.number - ago),
        );
      }
      total += price.timesInt(units);
    }
    return Money(total.cents ~/ counted);
  }

  /// Shelf price per product, indexed by [ProductId]; null if not listed.
  final List<Money?> prices;

  /// Stock per product, indexed by [ProductId].
  final List<Stock> stock;

  /// Recent daily sales and misses, for the owner's eyes.
  final SalesHistory history;

  /// Staff per slot of the day, indexed by [DaySlot]; a slot without staff
  /// is closed.
  final List<int> staff;

  /// How well each slot's staff kept up with its shoppers yesterday, from 0
  /// to 1, indexed by [DaySlot].
  final List<Fx> service;

  /// Visits per slot so far today, indexed by [DaySlot].
  final List<int> traffic;

  /// Who runs the store for its owner, if anyone.
  Manager? manager;

  /// What shoppers have come to think of it, from 0 to 1: see
  /// `DemandTuning.reputationWeight`.
  Fx reputation;

  /// Whether the store opens its doors in any slot.
  bool get hasHours => staff.any((count) => count > 0);

  int get listedProducts => prices.where((price) => price != null).length;

  /// Whether the store still holds its site: open or being built.
  bool get isTrading => status != StoreStatus.closed;

  int get unitsOnHand => stock.fold(0, (sum, product) => sum + product.units);

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(company.index)
      ..writeInt(site.index)
      ..writeInt(status.index)
      ..writeInt(opensOn.number)
      ..writeInt(market.index)
      ..writeInt(location.raw)
      ..writeInt(shelfSlots)
      ..writeInt(storageUnits)
      ..writeInt(prices.length);
    for (final price in prices) {
      writer.writeBool(price != null);
      if (price != null) writer.writeInt(price.cents);
    }
    writer.writeInt(stock.length);
    for (final product in stock) {
      product.write(writer);
    }
    history.write(writer);
    for (final list in [
      staff,
      [for (final s in service) s.raw],
      traffic,
    ]) {
      writer.writeInt(list.length);
      list.forEach(writer.writeInt);
    }
    writer.writeBool(manager != null);
    manager?.write(writer);
    writer
      ..writeInt(area)
      ..writeBool(works != null);
    if (works case (:final area, :final done, :final format)) {
      writer
        ..writeInt(area)
        ..writeInt(done.number)
        ..writeNullableInt(format?.index);
    }
    writer
      ..writeNullableInt(enlargedOn?.number)
      ..writeInt(format.index)
      ..writeInt(marketingShare.raw)
      ..writeInt(goodwill.cents)
      ..writeInt(boughtFor.cents)
      ..writeNullableInt(acquiredOn?.number)
      ..writeInt(reputation.raw);
  }
}
