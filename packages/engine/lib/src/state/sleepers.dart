import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The months of a sleeping shop's figures kept.
const sleepingMonthsKept = 12;

/// A site of a sleeping neighbourhood, as the generator lays it out: always the
/// same from the same row and seed, so it isn't saved.
final class PlannedSite {
  const PlannedSite({
    required this.number,
    required this.location,
    required this.rent,
    required this.openingCost,
    required this.area,
    required this.maxArea,
    required this.shelfSlots,
    this.name = '',
  });

  /// Its place among the neighbourhood's sites.
  final int number;

  /// Its street.
  final String name;
  final Fx location;

  /// A month's rent at [area], at a price index of 1.
  final Money rent;
  final Money openingCost;
  final int area;
  final int maxArea;
  final int shelfSlots;

  /// A month's rent at [atArea] m².
  Money rentFor(int atArea) => Money(rent.cents * atArea ~/ area);
}

/// A shop of a neighbourhood run by formula: who it is, how big, what it has
/// made lately and what it and its owner hold.
final class SleepingShop {
  SleepingShop({
    required this.site,
    required this.format,
    required this.strategy,
    required this.name,
    required this.owner,
    required this.area,
    required this.cash,
    required this.ownerCash,
    required this.openedMonth,
    required this.enlargedMonth,
    this.company,
    this.brand,
    this.acquiredMonth,
    List<Money>? sales,
    List<Money>? profits,
  }) : sales = sales ?? [],
       profits = profits ?? [];

  SleepingShop.read(StateReader reader)
    : site = reader.readInt(),
      format = FormatId(reader.readInt()),
      strategy = StrategyId(reader.readInt()),
      name = reader.readString(),
      owner = reader.readString(),
      area = reader.readInt(),
      cash = Money(reader.readInt()),
      ownerCash = Money(reader.readInt()),
      openedMonth = reader.readInt(),
      enlargedMonth = reader.readInt(),
      sales = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Money(reader.readInt()),
      ],
      profits = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Money(reader.readInt()),
      ],
      company = reader.version >= 26
          ? switch (reader.readNullableInt()) {
              final index? => CompanyId(index),
              null => null,
            }
          : null,
      brand = reader.version >= 26
          ? switch (reader.readNullableInt()) {
              final index? => BrandId(index),
              null => null,
            }
          : null,
      acquiredMonth = reader.version >= 26 ? reader.readNullableInt() : null;

  /// Its site's number in the neighbourhood.
  final int site;
  final FormatId format;
  final StrategyId strategy;
  String name;

  /// The chain's company it belongs to, whose books it trades in; null for a
  /// shopkeeper of the district's own.
  CompanyId? company;

  /// The brand it trades under, if a chain's.
  BrandId? brand;

  /// When it last changed hands, in months since the game's start, if ever.
  int? acquiredMonth;

  /// Its owner's name.
  final String owner;
  int area;

  /// What its company holds, and what its owner does.
  Money cash;
  Money ownerCash;

  /// When it opened, in months since the game's start: before it, for those
  /// already there.
  final int openedMonth;

  /// When it last enlarged, likewise.
  int enlargedMonth;

  /// Each of its latest months' sales and profit before tax, oldest first.
  final List<Money> sales;
  final List<Money> profits;

  Money get yearSales => sales.fold(Money.zero, (sum, month) => sum + month);
  Money get yearProfit => profits.fold(Money.zero, (sum, month) => sum + month);

  void remember(Money sold, Money earned) {
    sales.add(sold);
    profits.add(earned);
    if (sales.length > sleepingMonthsKept) {
      sales.removeAt(0);
      profits.removeAt(0);
    }
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(site)
      ..writeInt(format.index)
      ..writeInt(strategy.index)
      ..writeString(name)
      ..writeString(owner)
      ..writeInt(area)
      ..writeInt(cash.cents)
      ..writeInt(ownerCash.cents)
      ..writeInt(openedMonth)
      ..writeInt(enlargedMonth)
      ..writeInt(sales.length);
    for (final month in sales) {
      writer.writeInt(month.cents);
    }
    writer.writeInt(profits.length);
    for (final month in profits) {
      writer.writeInt(month.cents);
    }
    writer
      ..writeNullableInt(company?.index)
      ..writeNullableInt(brand?.index)
      ..writeNullableInt(acquiredMonth);
  }
}

/// A neighbourhood run by formula until the player trades there: no shoppers or
/// stock, just its households and its shops' monthly figures. See
/// [SleeperSystem].
final class SleepingNeighbourhood {
  SleepingNeighbourhood({
    required this.row,
    required this.households,
    required this.shops,
    List<Fx>? pending,
    this.opened = 0,
    this.closed = 0,
  }) : pending = pending ?? List.filled(households.length, Fx.zero);

  SleepingNeighbourhood.read(StateReader reader)
    : row = reader.readInt(),
      households = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
      ],
      pending = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ],
      shops = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          SleepingShop.read(reader),
      ],
      opened = reader.readInt(),
      closed = reader.readInt();

  /// Its place in the scenario's neighbourhoods.
  final int row;

  /// Households by segment, and growth not yet whole households.
  final List<int> households;
  final List<Fx> pending;
  final List<SleepingShop> shops;

  /// The shops opened and closed here since the game began.
  int opened;
  int closed;

  /// Its sites, worked out when first needed: see [PlannedSite].
  List<PlannedSite>? sites;

  void write(StateWriter writer) {
    writer
      ..writeInt(row)
      ..writeInt(households.length);
    households.forEach(writer.writeInt);
    writer.writeInt(pending.length);
    for (final rate in pending) {
      writer.writeInt(rate.raw);
    }
    writer.writeInt(shops.length);
    for (final shop in shops) {
      shop.write(writer);
    }
    writer
      ..writeInt(opened)
      ..writeInt(closed);
  }
}
