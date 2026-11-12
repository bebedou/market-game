import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';
import '../state/director.dart' show Growth;
import '../state/store.dart' show allDuties;

/// A command as it was applied: the day it took effect, and the command.
typedef LoggedCommand = ({Day day, Command command});

/// A product and quantity on an order.
typedef OrderQuantity = ({ProductId product, int quantity});

/// The only way an actor changes the world. Commands are queued and applied
/// at the start of the next step, under the same rules for every actor.
///
/// Each command type has a serialization tag. Never renumber one: saved
/// command logs depend on it.
/// A brand a command names, in a save that has them.
BrandId? _readBrand(StateReader reader) => reader.version >= 25
    ? switch (reader.readNullableInt()) {
        final index? => BrandId(index),
        null => null,
      }
    : null;

sealed class Command {
  const Command(this.actor);

  /// Reads a command written by [write].
  factory Command.read(StateReader reader) {
    final tag = reader.readInt();
    final actor = PersonId(reader.readInt());
    return switch (tag) {
      WakeNeighbourhood.tag => WakeNeighbourhood(actor, row: reader.readInt()),
      SetPrice.tag => SetPrice(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
        price: Money(reader.readInt()),
      ),
      PlaceOrder.tag => PlaceOrder(
        actor,
        store: StoreId(reader.readInt()),
        supplier: SupplierId(reader.readInt()),
        lines: [
          for (var i = 0, n = reader.readInt(); i < n; i++)
            (product: ProductId(reader.readInt()), quantity: reader.readInt()),
        ],
      ),
      ListProduct.tag => ListProduct(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
        price: Money(reader.readInt()),
      ),
      DelistProduct.tag => DelistProduct(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
      ),
      InjectCapital.tag => InjectCapital(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
      ),
      PayDividend.tag => PayDividend(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
      ),
      TakeLoan.tag => TakeLoan(
        actor,
        company: CompanyId(reader.readInt()),
        amount: Money(reader.readInt()),
        termMonths: reader.readInt(),
        guarantee: reader.readBool(),
      ),
      RepayLoan.tag => RepayLoan(
        actor,
        loan: reader.readInt(),
        amount: Money(reader.readInt()),
      ),
      OpenStore.tag => OpenStore(
        actor,
        site: SiteId(reader.readInt()),
        name: reader.readString(),
        company: switch (reader.readNullableInt()) {
          final index? => CompanyId(index),
          null => null,
        },
        capital: Money(reader.readInt()),
        format: reader.version >= 10
            ? FormatId(reader.readInt())
            : const FormatId(0),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
        brand: _readBrand(reader),
      ),
      CreateBrand.tag => CreateBrand(
        actor,
        name: reader.readString(),
        format: FormatId(reader.readInt()),
      ),
      OpenInDistrict.tag => OpenInDistrict(
        actor,
        row: reader.readInt(),
        site: reader.readInt(),
        company: CompanyId(reader.readInt()),
        format: FormatId(reader.readInt()),
        capital: Money(reader.readInt()),
      ),
      BuyInDistrict.tag => BuyInDistrict(
        actor,
        row: reader.readInt(),
        site: reader.readInt(),
        company: CompanyId(reader.readInt()),
      ),
      CloseStore.tag => CloseStore(actor, store: StoreId(reader.readInt())),
      SetStaffing.tag => SetStaffing(
        actor,
        store: StoreId(reader.readInt()),
        staff: [
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
        ],
      ),
      BuyResearch.tag => BuyResearch(
        actor,
        company: CompanyId(reader.readInt()),
        market: MarketId(reader.readInt()),
        tier: ResearchTierId(reader.readInt()),
      ),
      HireManager.tag => HireManager(
        actor,
        store: StoreId(reader.readInt()),
        grade: ManagerGradeId(reader.readInt()),
        strategy: StrategyId(reader.readInt()),
        duties: allDuties([
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readBool(),
        ]),
      ),
      FireManager.tag => FireManager(actor, store: StoreId(reader.readInt())),
      ExpandStore.tag => ExpandStore(actor, store: StoreId(reader.readInt())),
      RenameStore.tag => RenameStore(
        actor,
        store: StoreId(reader.readInt()),
        name: reader.readString(),
      ),
      RenameCompany.tag => RenameCompany(
        actor,
        company: CompanyId(reader.readInt()),
        name: reader.readString(),
      ),
      SetCushion.tag => SetCushion(
        actor,
        company: CompanyId(reader.readInt()),
        days: reader.readInt(),
      ),
      ConvertStore.tag => ConvertStore(
        actor,
        store: StoreId(reader.readInt()),
        format: FormatId(reader.readInt()),
      ),
      SetMarketing.tag => SetMarketing(
        actor,
        store: StoreId(reader.readInt()),
        share: Fx.raw(reader.readInt()),
      ),
      BuyStore.tag => BuyStore(
        actor,
        store: StoreId(reader.readInt()),
        company: CompanyId(reader.readInt()),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
        brand: _readBrand(reader),
      ),
      SellStore.tag => SellStore(actor, store: StoreId(reader.readInt())),
      BuyCompany.tag => BuyCompany(
        actor,
        company: CompanyId(reader.readInt()),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
      ),
      HireDirector.tag => HireDirector(
        actor,
        company: CompanyId(reader.readInt()),
        grade: DirectorGradeId(reader.readInt()),
        strategy: StrategyId(reader.readInt()),
        managerGrade: ManagerGradeId(reader.readInt()),
        growth: Growth.values[reader.readInt()],
        payout: reader.readBool(),
        borrows: reader.version >= 22 ? reader.readBool() : false,
        nationalPace: reader.version >= 29 ? reader.readInt() : 0,
        nationalRegions: [
          if (reader.version >= 29)
            for (var i = 0, n = reader.readInt(); i < n; i++)
              reader.readString(),
        ],
      ),
      FireDirector.tag => FireDirector(
        actor,
        company: CompanyId(reader.readInt()),
      ),
      BuildFactory.tag => BuildFactory(
        actor,
        kind: FactoryKindId(reader.readInt()),
        country: CountryId(reader.readInt()),
        name: reader.readString(),
        company: switch (reader.readNullableInt()) {
          final index? => CompanyId(index),
          null => null,
        },
        capital: Money(reader.readInt()),
        borrow: Money(reader.readInt()),
        termMonths: reader.readInt(),
        shifts: reader.readInt(),
        serves: reader.readBool()
            ? [
                for (var c = 0, n = reader.readInt(); c < n; c++)
                  reader.readBool(),
              ]
            : null,
      ),
      SetFactoryShifts.tag => SetFactoryShifts(
        actor,
        factory: FactoryId(reader.readInt()),
        shifts: reader.readInt(),
      ),
      SetFactoryTerms.tag => SetFactoryTerms(
        actor,
        factory: FactoryId(reader.readInt()),
        serves: [
          for (var i = 0, n = reader.readInt(); i < n; i++) reader.readBool(),
        ],
        rivalDiscount: switch (reader.readNullableInt()) {
          final raw? => Fx.raw(raw),
          null => null,
        },
      ),
      CloseFactory.tag => CloseFactory(
        actor,
        factory: FactoryId(reader.readInt()),
      ),
      OpenNational.tag => OpenNational(
        actor,
        company: CompanyId(reader.readInt()),
        country: CountryId(reader.readInt()),
        region: reader.readInt(),
        format: FormatId(reader.readInt()),
        strategy: StrategyId(reader.readInt()),
        count: reader.readInt(),
        borrow: Money(reader.readInt()),
        termMonths: reader.readInt(),
      ),
      OrderFromFactory.tag => OrderFromFactory(
        actor,
        store: StoreId(reader.readInt()),
        factory: FactoryId(reader.readInt()),
        lines: [
          for (var i = 0, n = reader.readInt(); i < n; i++)
            (product: ProductId(reader.readInt()), quantity: reader.readInt()),
        ],
      ),
      _ => throw FormatException('Unknown command tag $tag'),
    };
  }

  final PersonId actor;

  void write(StateWriter writer);
}

/// Sets the shelf price of a product the store already lists.
final class SetPrice extends Command {
  const SetPrice(
    super.actor, {
    required this.store,
    required this.product,
    required this.price,
  });

  static const int tag = 1;

  final StoreId store;
  final ProductId product;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'SetPrice(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index}, price: ${price.toDecimalString()})';
}

/// Orders stock from a supplier. It arrives after the supplier's lead time,
/// at prices fixed now; the invoice is due after the supplier's payment terms.
final class PlaceOrder extends Command {
  const PlaceOrder(
    super.actor, {
    required this.store,
    required this.supplier,
    required this.lines,
  });

  static const int tag = 2;

  final StoreId store;
  final SupplierId supplier;
  final List<OrderQuantity> lines;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(supplier.index)
      ..writeInt(lines.length);
    for (final (:product, :quantity) in lines) {
      writer
        ..writeInt(product.index)
        ..writeInt(quantity);
    }
  }

  @override
  String toString() {
    final items = [
      for (final (:product, :quantity) in lines) '${product.index}×$quantity',
    ];
    return 'PlaceOrder(actor: ${actor.index}, store: ${store.index}, '
        'supplier: ${supplier.index}, lines: ${items.join(', ')})';
  }
}

/// Puts a product on a free shelf slot, at [price].
final class ListProduct extends Command {
  const ListProduct(
    super.actor, {
    required this.store,
    required this.product,
    required this.price,
  });

  static const int tag = 3;

  final StoreId store;
  final ProductId product;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'ListProduct(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index}, price: ${price.toDecimalString()})';
}

/// Frees a product's shelf slot. Remaining stock is written off, and units
/// still on order are refused when they arrive.
final class DelistProduct extends Command {
  const DelistProduct(
    super.actor, {
    required this.store,
    required this.product,
  });

  static const int tag = 4;

  final StoreId store;
  final ProductId product;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index);
  }

  @override
  String toString() =>
      'DelistProduct(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index})';
}

/// Moves money from the actor's personal cash into a company they own.
final class InjectCapital extends Command {
  const InjectCapital(
    super.actor, {
    required this.company,
    required this.amount,
  });

  static const int tag = 5;

  final CompanyId company;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'InjectCapital(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()})';
}

/// Pays the actor out of a company they own, from its retained profits.
final class PayDividend extends Command {
  const PayDividend(super.actor, {required this.company, required this.amount});

  static const int tag = 6;

  final CompanyId company;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'PayDividend(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()})';
}

/// Borrows from the bank, repaid monthly over [termMonths]. Without a
/// [guarantee], the bank lends on the company's earnings (see
/// `earningsCredit`); with one, on the owner's cash (see `guaranteeRoom`).
final class TakeLoan extends Command {
  const TakeLoan(
    super.actor, {
    required this.company,
    required this.amount,
    required this.termMonths,
    required this.guarantee,
  });

  static const int tag = 7;

  final CompanyId company;
  final Money amount;
  final int termMonths;

  /// Whether the owner personally answers for the loan if the company fails.
  final bool guarantee;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(amount.cents)
      ..writeInt(termMonths)
      ..writeBool(guarantee);
  }

  @override
  String toString() =>
      'TakeLoan(actor: ${actor.index}, company: ${company.index}, '
      'amount: ${amount.toDecimalString()}, termMonths: $termMonths, '
      'guarantee: $guarantee)';
}

/// Repays [amount] of a loan's principal early, with the interest accrued on
/// the loan so far.
final class RepayLoan extends Command {
  const RepayLoan(super.actor, {required this.loan, required this.amount});

  static const int tag = 8;

  /// The loan number.
  final int loan;
  final Money amount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(loan)
      ..writeInt(amount.cents);
  }

  @override
  String toString() =>
      'RepayLoan(actor: ${actor.index}, loan: $loan, '
      'amount: ${amount.toDecimalString()})';
}

/// Opens a store called [name] at a vacant site. The company pays the fit-out
/// now and the store trades once the site's build days have passed. Without
/// a [company], founds one with the same name and [capital] from the actor's
/// personal cash; with one, [capital] is injected into it first. The
/// company may [borrow] towards it, repaid over [termMonths] (see
/// `splitLoan`); if the bank won't lend, nothing happens.
final class OpenStore extends Command {
  const OpenStore(
    super.actor, {
    required this.site,
    required this.name,
    this.company,
    this.capital = Money.zero,
    this.format = const FormatId(0),
    this.borrow = Money.zero,
    this.termMonths = 0,
    this.brand,
  });

  static const int tag = 9;

  final SiteId site;
  final String name;
  final CompanyId? company;
  final Money capital;

  /// What kind of business to open.
  final FormatId format;

  /// What to borrow towards it, if anything, and over how many months.
  final Money borrow;
  final int termMonths;

  /// The actor's brand to open it under, which names it, if any. An AI
  /// owner's shops always trade under its brand.
  final BrandId? brand;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(site.index)
      ..writeString(name)
      ..writeNullableInt(company?.index)
      ..writeInt(capital.cents)
      ..writeInt(format.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths)
      ..writeNullableInt(brand?.index);
  }

  @override
  String toString() =>
      'OpenStore(actor: ${actor.index}, site: ${site.index}, name: $name, '
      'company: ${company?.index}, capital: ${capital.toDecimalString()}, '
      'format: ${format.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths, brand: ${brand?.index})';
}

/// Opens a shop of [company]'s in a district run by formula, under the
/// actor's brand: it trades by formula, in the company's books, until the
/// district wakes. Only an AI owner's chain does this: a shop of the
/// player's wakes the district instead.
final class OpenInDistrict extends Command {
  const OpenInDistrict(
    super.actor, {
    required this.row,
    required this.site,
    required this.company,
    required this.format,
    this.capital = Money.zero,
  });

  static const int tag = 28;

  /// The district's place in the scenario's neighbourhoods.
  final int row;

  /// The site's number in the district.
  final int site;
  final CompanyId company;
  final FormatId format;

  /// What the actor puts into the company towards it first.
  final Money capital;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(row)
      ..writeInt(site)
      ..writeInt(company.index)
      ..writeInt(format.index)
      ..writeInt(capital.cents);
  }

  @override
  String toString() =>
      'OpenInDistrict(actor: ${actor.index}, row: $row, site: $site, '
      'company: ${company.index}, format: ${format.index}, '
      'capital: ${capital.toDecimalString()})';
}

/// Buys the shop on [site] of a district run by formula, at its asking
/// price, for [company], which puts it under the actor's brand. Only an AI
/// owner's chain does this.
final class BuyInDistrict extends Command {
  const BuyInDistrict(
    super.actor, {
    required this.row,
    required this.site,
    required this.company,
  });

  static const int tag = 29;

  final int row;
  final int site;
  final CompanyId company;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(row)
      ..writeInt(site)
      ..writeInt(company.index);
  }

  @override
  String toString() =>
      'BuyInDistrict(actor: ${actor.index}, row: $row, site: $site, '
      'company: ${company.index})';
}

/// Starts a brand for one type of business, which the actor's shops can then
/// be opened or bought under.
final class CreateBrand extends Command {
  const CreateBrand(super.actor, {required this.name, required this.format});

  static const int tag = 27;

  final String name;
  final FormatId format;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeString(name)
      ..writeInt(format.index);
  }

  @override
  String toString() =>
      'CreateBrand(actor: ${actor.index}, name: $name, '
      'format: ${format.index})';
}

/// Closes a store for good: its stock is written off and its site is freed.
final class CloseStore extends Command {
  const CloseStore(super.actor, {required this.store});

  static const int tag = 10;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'CloseStore(actor: ${actor.index}, store: ${store.index})';
}

/// Sets a store's staff for each slot of the day; a slot without staff is
/// closed. Staff are paid for every day they are rostered.
final class SetStaffing extends Command {
  const SetStaffing(super.actor, {required this.store, required this.staff});

  static const int tag = 11;

  final StoreId store;

  /// Indexed by slot of the day: morning, midday, evening, night.
  final List<int> staff;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(staff.length);
    staff.forEach(writer.writeInt);
  }

  @override
  String toString() =>
      'SetStaffing(actor: ${actor.index}, store: ${store.index}, '
      'staff: [${staff.join(', ')}])';
}

/// Buys a study of a market for one of the actor's companies: estimates of
/// its households and of each store's share of sales, as accurate as the
/// [tier] paid for.
final class BuyResearch extends Command {
  const BuyResearch(
    super.actor, {
    required this.company,
    required this.market,
    required this.tier,
  });

  static const int tag = 12;

  final CompanyId company;
  final MarketId market;
  final ResearchTierId tier;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(market.index)
      ..writeInt(tier.index);
  }

  @override
  String toString() =>
      'BuyResearch(actor: ${actor.index}, company: ${company.index}, '
      'market: ${market.index}, tier: ${tier.index})';
}

/// Puts a manager of [grade] in charge of a store's [duties], following
/// [strategy]; or, for the manager already there, changes the brief. A new
/// grade replaces the manager. Managers are paid daily, like staff.
final class HireManager extends Command {
  const HireManager(
    super.actor, {
    required this.store,
    required this.grade,
    required this.strategy,
    required this.duties,
  });

  static const int tag = 13;

  final StoreId store;
  final ManagerGradeId grade;
  final StrategyId strategy;

  /// Indexed by duty: ordering, pricing, assortment, staffing.
  final List<bool> duties;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(duties.length);
    duties.forEach(writer.writeBool);
  }

  @override
  String toString() =>
      'HireManager(actor: ${actor.index}, store: ${store.index}, '
      'grade: ${grade.index}, strategy: ${strategy.index}, '
      'duties: [${duties.join(', ')}])';
}

/// Lets a store's manager go; the owner runs it again.
final class FireManager extends Command {
  const FireManager(super.actor, {required this.store});

  static const int tag = 14;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'FireManager(actor: ${actor.index}, store: ${store.index})';
}

/// Enlarges a store by one step of floor area, paid now. The works take some
/// days, during which the store keeps trading; then it has more shelf slots
/// and storage, draws more shoppers, and pays more rent.
final class ExpandStore extends Command {
  const ExpandStore(super.actor, {required this.store});

  static const int tag = 15;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'ExpandStore(actor: ${actor.index}, store: ${store.index})';
}

/// Gives a store a new name, which everyone sees.
final class RenameStore extends Command {
  const RenameStore(super.actor, {required this.store, required this.name});

  static const int tag = 16;

  final StoreId store;
  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeString(name);
  }

  @override
  String toString() =>
      'RenameStore(actor: ${actor.index}, store: ${store.index}, name: $name)';
}

/// Gives a company a new name, which everyone sees.
final class RenameCompany extends Command {
  const RenameCompany(super.actor, {required this.company, required this.name});

  static const int tag = 17;

  final CompanyId company;
  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeString(name);
  }

  @override
  String toString() =>
      'RenameCompany(actor: ${actor.index}, company: ${company.index}, '
      'name: $name)';
}

/// Sets how many days of wages a company keeps in its cash cushion.
final class SetCushion extends Command {
  const SetCushion(super.actor, {required this.company, required this.days});

  static const int tag = 23;

  final CompanyId company;
  final int days;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(days);
  }

  @override
  String toString() =>
      'SetCushion(actor: ${actor.index}, company: ${company.index}, '
      'days: $days)';
}

/// Puts a director of [grade] in charge of a company (see `Director`); or,
/// for the director already there, changes the brief. A new grade replaces
/// the director. Directors are paid daily, like managers.
final class HireDirector extends Command {
  const HireDirector(
    super.actor, {
    required this.company,
    required this.grade,
    required this.strategy,
    required this.managerGrade,
    required this.growth,
    required this.payout,
    this.borrows = false,
    this.nationalPace = 0,
    this.nationalRegions = const [],
  });

  static const int tag = 24;

  final CompanyId company;
  final DirectorGradeId grade;
  final StrategyId strategy;
  final ManagerGradeId managerGrade;
  final Growth growth;
  final bool payout;

  /// Whether they may borrow to grow, on the company's earnings.
  final bool borrows;

  /// Shops run by formula they may open a month, and where (see
  /// `Director.nationalPace`).
  final int nationalPace;
  final List<String> nationalRegions;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(grade.index)
      ..writeInt(strategy.index)
      ..writeInt(managerGrade.index)
      ..writeInt(growth.index)
      ..writeBool(payout)
      ..writeBool(borrows)
      ..writeInt(nationalPace)
      ..writeInt(nationalRegions.length);
    nationalRegions.forEach(writer.writeString);
  }

  @override
  String toString() =>
      'HireDirector(actor: ${actor.index}, company: ${company.index}, '
      'grade: ${grade.index}, strategy: ${strategy.index}, '
      'managerGrade: ${managerGrade.index}, growth: ${growth.name}, '
      'payout: $payout, borrows: $borrows, nationalPace: $nationalPace, '
      'nationalRegions: $nationalRegions)';
}

/// Lets a company's director go; the owner runs it again, and its store
/// managers stay.
final class FireDirector extends Command {
  const FireDirector(super.actor, {required this.company});

  static const int tag = 25;

  final CompanyId company;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index);
  }

  @override
  String toString() =>
      'FireDirector(actor: ${actor.index}, company: ${company.index})';
}

/// Sets the share of its recent sales a store spends on marketing each day.
final class SetMarketing extends Command {
  const SetMarketing(super.actor, {required this.store, required this.share});

  static const int tag = 18;

  final StoreId store;
  final Fx share;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(share.raw);
  }

  @override
  String toString() =>
      'SetMarketing(actor: ${actor.index}, store: ${store.index}, '
      'share: ${share.toDecimalString()})';
}

/// Turns a store into another format of its channel, a convenience store
/// into a supermarket: paid at once, and the store keeps trading through the
/// works, enlarged to the format's least area if need be.
final class ConvertStore extends Command {
  const ConvertStore(super.actor, {required this.store, required this.format});

  static const int tag = 19;

  final StoreId store;
  final FormatId format;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(format.index);
  }

  @override
  String toString() =>
      'ConvertStore(actor: ${actor.index}, store: ${store.index}, '
      'format: ${format.index})';
}

/// Buys another owner's store at its asking price, paid by the actor's
/// [company]: the store keeps its stock, staff, prices and shoppers, and
/// orders on their way go with it. The player's stores are sold only when
/// the player says so. The company may [borrow] towards it, repaid over
/// [termMonths], with the store's own earnings counted (see `splitLoan`);
/// if the bank won't lend, nothing happens.
final class BuyStore extends Command {
  const BuyStore(
    super.actor, {
    required this.store,
    required this.company,
    this.borrow = Money.zero,
    this.termMonths = 0,
    this.brand,
  });

  static const int tag = 20;

  final StoreId store;

  /// The actor's company that pays for it and runs it from now on.
  final CompanyId company;

  /// What to borrow towards it, if anything, and over how many months.
  final Money borrow;
  final int termMonths;

  /// The actor's brand to put it under, if any; without one, it keeps its
  /// name. An AI owner puts it under its own brand.
  final BrandId? brand;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(company.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths)
      ..writeNullableInt(brand?.index);
  }

  @override
  String toString() =>
      'BuyStore(actor: ${actor.index}, store: ${store.index}, '
      'company: ${company.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths, brand: ${brand?.index})';
}

/// Sells one of the actor's stores at its asking price to the AI owner of
/// its format best able to pay.
final class SellStore extends Command {
  const SellStore(super.actor, {required this.store});

  static const int tag = 21;

  final StoreId store;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index);
  }

  @override
  String toString() =>
      'SellStore(actor: ${actor.index}, store: ${store.index})';
}

/// Buys a whole company from its owner at its asking price, paid from the
/// actor's personal cash: its stores, cash and debts come with it. The
/// company itself may [borrow] part of the price on its own earnings,
/// repaid over [termMonths], so the buyer pays only the rest; if the bank
/// won't lend, nothing happens.
final class BuyCompany extends Command {
  const BuyCompany(
    super.actor, {
    required this.company,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 22;

  final CompanyId company;

  /// What the company borrows towards its price, and over how many months.
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'BuyCompany(actor: ${actor.index}, company: ${company.index}, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths)';
}

/// Starts simulating a neighbourhood the game only held figures for, so its
/// sites can be opened on and its shops compete. It takes effect at once, not
/// with the day's other commands, as they may refer to its sites.
final class WakeNeighbourhood extends Command {
  const WakeNeighbourhood(super.actor, {required this.row});

  static const int tag = 26;

  /// Its place in [ContentDb.neighbourhoods].
  final int row;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(row);
  }

  @override
  String toString() => 'WakeNeighbourhood(actor: ${actor.index}, row: $row)';
}

/// Builds a factory of [kind] in [country] for [company], or for a new one
/// named [name] founded with [capital] of the actor's cash: it pays the
/// kind's build cost at the country's prices, borrowing [borrow] of it over
/// [termMonths] if asked, and makes goods after the kind's build days, at
/// [shifts]. It serves its own country's shops.
final class BuildFactory extends Command {
  const BuildFactory(
    super.actor, {
    required this.kind,
    required this.country,
    required this.name,
    this.company,
    this.capital = Money.zero,
    this.borrow = Money.zero,
    this.termMonths = 0,
    this.shifts = 1,
    this.serves,
  });

  static const int tag = 30;

  final FactoryKindId kind;
  final CountryId country;

  /// The factory's name, and a new company's if [company] is null.
  final String name;
  final CompanyId? company;
  final Money capital;
  final Money borrow;
  final int termMonths;
  final int shifts;

  /// The countries whose shops it delivers to, by [CountryId], its own
  /// among them; null for its own alone.
  final List<bool>? serves;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(kind.index)
      ..writeInt(country.index)
      ..writeString(name)
      ..writeNullableInt(company?.index)
      ..writeInt(capital.cents)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths)
      ..writeInt(shifts)
      ..writeBool(serves != null);
    if (serves case final serves?) {
      writer.writeInt(serves.length);
      serves.forEach(writer.writeBool);
    }
  }

  @override
  String toString() =>
      'BuildFactory(actor: ${actor.index}, kind: ${kind.index}, '
      'country: ${country.index}, name: $name, company: ${company?.index}, '
      'capital: ${capital.toDecimalString()}, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths, '
      'shifts: $shifts, serves: $serves)';
}

/// Sets how many shifts a factory runs, from 0, stopped, to the scenario's
/// most: each one's staff are paid whether or not it has work.
final class SetFactoryShifts extends Command {
  const SetFactoryShifts(
    super.actor, {
    required this.factory,
    required this.shifts,
  });

  static const int tag = 31;

  final FactoryId factory;
  final int shifts;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(factory.index)
      ..writeInt(shifts);
  }

  @override
  String toString() =>
      'SetFactoryShifts(actor: ${actor.index}, factory: ${factory.index}, '
      'shifts: $shifts)';
}

/// Sets which countries' shops a factory delivers to, by [CountryId], its
/// own always among them, and whether it sells to rivals: [rivalDiscount]
/// under their wholesalers' prices, or null to keep it for the owner's
/// shops.
final class SetFactoryTerms extends Command {
  const SetFactoryTerms(
    super.actor, {
    required this.factory,
    required this.serves,
    this.rivalDiscount,
  });

  static const int tag = 32;

  final FactoryId factory;
  final List<bool> serves;
  final Fx? rivalDiscount;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(factory.index)
      ..writeInt(serves.length);
    serves.forEach(writer.writeBool);
    writer.writeNullableInt(rivalDiscount?.raw);
  }

  @override
  String toString() =>
      'SetFactoryTerms(actor: ${actor.index}, factory: ${factory.index}, '
      'serves: $serves, rivalDiscount: ${rivalDiscount?.raw})';
}

/// Closes a factory for good: the owner's shops buy its goods from their
/// wholesalers again, and orders on their way arrive from them.
final class CloseFactory extends Command {
  const CloseFactory(super.actor, {required this.factory});

  static const int tag = 33;

  final FactoryId factory;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(factory.index);
  }

  @override
  String toString() =>
      'CloseFactory(actor: ${actor.index}, factory: ${factory.index})';
}

/// Orders goods for [store] from [factory]: the actor's own, which charges
/// what the store's wholesalers would and makes what it can, or a rival's
/// that sells to others, from what it can spare.
final class OrderFromFactory extends Command {
  const OrderFromFactory(
    super.actor, {
    required this.store,
    required this.factory,
    required this.lines,
  });

  static const int tag = 34;

  final StoreId store;
  final FactoryId factory;
  final List<OrderQuantity> lines;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(factory.index)
      ..writeInt(lines.length);
    for (final (:product, :quantity) in lines) {
      writer
        ..writeInt(product.index)
        ..writeInt(quantity);
    }
  }

  @override
  String toString() {
    final items = [
      for (final (:product, :quantity) in lines) '${product.index}×$quantity',
    ];
    return 'OrderFromFactory(actor: ${actor.index}, store: ${store.index}, '
        'factory: ${factory.index}, lines: ${items.join(', ')})';
  }
}

/// Opens [count] of [company]'s shops of [format] run by formula in
/// [region] of [country], by the national table's regions, priced and
/// stocked as [strategy] has it: each costs the format's national fitting out
/// at the country's prices, borrowing [borrow] over [termMonths] if asked,
/// and trades from the next month.
final class OpenNational extends Command {
  const OpenNational(
    super.actor, {
    required this.company,
    required this.country,
    required this.region,
    required this.format,
    required this.strategy,
    required this.count,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 35;

  final CompanyId company;
  final CountryId country;

  /// By index into the national table's regions of [country].
  final int region;
  final FormatId format;
  final StrategyId strategy;
  final int count;
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeInt(region)
      ..writeInt(format.index)
      ..writeInt(strategy.index)
      ..writeInt(count)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'OpenNational(actor: ${actor.index}, company: ${company.index}, '
      'country: ${country.index}, region: $region, format: ${format.index}, '
      'strategy: ${strategy.index}, count: $count, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths)';
}
