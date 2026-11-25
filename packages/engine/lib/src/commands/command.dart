import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';
import '../state/director.dart'
    show
        DirectorPerson,
        Goal,
        Growth,
        goalsVersion,
        personVersion,
        readGoals,
        writeGoals;
import '../state/factory_sales.dart' show factorySalesVersion;
import '../state/software.dart' show softwareBesideVersion;
import '../state/store.dart' show allDuties, shopSizesVersion;

/// The tags of the commands to enlarge a store and to convert it to another
/// format, which went with `shopSizesVersion`: never to be used again.
const _expandStoreTag = 15;
const _convertStoreTag = 19;

/// What a command the game no longer has reads as, once its [fields] are
/// read past.
Command? _retired(List<int> fields) => null;

/// A command as it was applied: the day it took effect, and the command.
typedef LoggedCommand = ({Day day, Command command});

/// A product and quantity on an order.
typedef OrderQuantity = ({ProductId product, int quantity});

/// A brand a command names, in a save that has them.
BrandId? _readBrand(StateReader reader) => reader.version >= 25
    ? switch (reader.readNullableInt()) {
        final index? => BrandId(index),
        null => null,
      }
    : null;

/// The only way an actor changes the world. Commands are queued and applied
/// at the start of the next step, under the same rules for every actor.
///
/// Each command type has a serialization tag. Never renumber one: saved
/// command logs depend on it.
sealed class Command {
  const Command(this.actor);

  /// Reads a command written by [write]; throws for one the game no longer
  /// has.
  factory Command.read(StateReader reader) =>
      readOrRetired(reader) ??
      (throw const FormatException('A command the game no longer has'));

  /// Reads a command written by [write], or, for one the game no longer has
  /// (enlarging or converting a store), skips its fields and gives null.
  static Command? readOrRetired(StateReader reader) {
    final tag = reader.readInt();
    final actor = PersonId(reader.readInt());
    return switch (tag) {
      _expandStoreTag => _retired([reader.readInt()]),
      _convertStoreTag => _retired([reader.readInt(), reader.readInt()]),
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
            ? FormatId(reader.mapFormat(reader.readInt()))
            : const FormatId(0),
        borrow: reader.version >= 21 ? Money(reader.readInt()) : Money.zero,
        termMonths: reader.version >= 21 ? reader.readInt() : 0,
        brand: _readBrand(reader),
        area: reader.version >= shopSizesVersion
            ? reader.readNullableInt()
            : null,
      ),
      CreateBrand.tag => CreateBrand(
        actor,
        name: reader.readString(),
        format: FormatId(reader.mapFormat(reader.readInt())),
      ),
      OpenInDistrict.tag => OpenInDistrict(
        actor,
        row: reader.readInt(),
        site: reader.readInt(),
        company: CompanyId(reader.readInt()),
        format: FormatId(reader.mapFormat(reader.readInt())),
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
        nationalAuto: reader.version >= 31
            ? reader.readBool()
            : reader.version >= 29 && reader.readInt() > 0,
        nationalRate: reader.version >= 31 ? Fx.raw(reader.readInt()) : Fx.zero,
        nationalRegions: [
          if (reader.version >= 29)
            for (var i = 0, n = reader.readInt(); i < n; i++)
              reader.readString(),
        ],
        person: reader.version >= personVersion && reader.readBool()
            ? DirectorPerson.read(reader)
            : null,
        goals: reader.version >= goalsVersion ? readGoals(reader) : const {},
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
        size: reader.version >= factorySalesVersion ? reader.readInt() : 0,
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
      BuyNationalChain.tag => BuyNationalChain(
        actor,
        company: CompanyId(reader.readInt()),
        country: CountryId(reader.readInt()),
        chain: reader.readInt(),
        format: FormatId(reader.mapFormat(reader.readInt())),
        strategy: StrategyId(reader.readInt()),
        borrow: Money(reader.readInt()),
        termMonths: reader.readInt(),
      ),
      SellNational.tag => SellNational(
        actor,
        company: CompanyId(reader.readInt()),
        country: CountryId(reader.readInt()),
        block: reader.readInt(),
      ),
      AcceptNationalOffer.tag => AcceptNationalOffer(
        actor,
        offer: reader.readInt(),
      ),
      DeclineNationalOffer.tag => DeclineNationalOffer(
        actor,
        offer: reader.readInt(),
      ),
      OpenNational.tag => OpenNational(
        actor,
        company: CompanyId(reader.readInt()),
        country: CountryId(reader.readInt()),
        region: reader.readInt(),
        format: FormatId(reader.mapFormat(reader.readInt())),
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
      SetLab.tag => SetLab(
        actor,
        factory: FactoryId(reader.readInt()),
        budget: Money(reader.readInt()),
        project: switch (reader.readNullableInt()) {
          final index? => ProductId(index),
          null => null,
        },
      ),
      HireKeyPerson.tag => HireKeyPerson(
        actor,
        person: KeyPersonId(reader.readInt()),
        factory: FactoryId(reader.readInt()),
      ),
      DismissKeyPerson.tag => DismissKeyPerson(
        actor,
        person: KeyPersonId(reader.readInt()),
      ),
      ClearStock.tag => ClearStock(
        actor,
        store: StoreId(reader.readInt()),
        product: ProductId(reader.readInt()),
        days: reader.readInt(),
      ),
      StartSoftware.tag => StartSoftware(
        actor,
        name: reader.readString(),
        country: CountryId(reader.readInt()),
        capital: Money(reader.readInt()),
        company: reader.version >= softwareBesideVersion
            ? switch (reader.readNullableInt()) {
                final index? => CompanyId(index),
                null => null,
              }
            : null,
      ),
      SetSoftwarePrice.tag => SetSoftwarePrice(
        actor,
        software: SoftwareId(reader.readInt()),
        price: Money(reader.readInt()),
      ),
      SetSoftwareMarketing.tag => SetSoftwareMarketing(
        actor,
        software: SoftwareId(reader.readInt()),
        budget: Money(reader.readInt()),
      ),
      HireSoftwarePerson.tag => HireSoftwarePerson(
        actor,
        software: SoftwareId(reader.readInt()),
        person: KeyPersonId(reader.readInt()),
      ),
      RaiseRound.tag => RaiseRound(
        actor,
        software: SoftwareId(reader.readInt()),
        share: Fx.raw(reader.readInt()),
      ),
      AcceptSoftwareOffer.tag => AcceptSoftwareOffer(
        actor,
        software: SoftwareId(reader.readInt()),
      ),
      DeclineSoftwareOffer.tag => DeclineSoftwareOffer(
        actor,
        software: SoftwareId(reader.readInt()),
      ),
      ShutDownSoftware.tag => ShutDownSoftware(
        actor,
        software: SoftwareId(reader.readInt()),
      ),
      EnlargeFactory.tag => EnlargeFactory(
        actor,
        factory: FactoryId(reader.readInt()),
        capital: Money(reader.readInt()),
        borrow: Money(reader.readInt()),
        termMonths: reader.readInt(),
      ),
      BreakContract.tag => BreakContract(actor, contract: reader.readInt()),
      AnswerContract.tag => AnswerContract(
        actor,
        contract: reader.readInt(),
        accept: reader.readBool(),
      ),
      AskPrice.tag => AskPrice(
        actor,
        contract: reader.readInt(),
        price: Money(reader.readInt()),
      ),
      BidTender.tag => BidTender(
        actor,
        tender: reader.readInt(),
        factory: FactoryId(reader.readInt()),
        price: switch (reader.readNullableInt()) {
          final cents? => Money(cents),
          null => null,
        },
      ),
      BuyShares.tag => BuyShares(
        actor,
        of: reader.readInt(),
        units: reader.readInt(),
        index: reader.readBool(),
      ),
      SellShares.tag => SellShares(
        actor,
        of: reader.readInt(),
        units: reader.readInt(),
        index: reader.readBool(),
      ),
      BidForCompany.tag => BidForCompany(
        actor,
        stock: reader.readInt(),
        premium: Fx.raw(reader.readInt()),
        bidder: reader.readInt(),
        borrow: Money(reader.readInt()),
        termMonths: reader.readInt(),
        format: switch (reader.readInt()) {
          < 0 => -1,
          final format => reader.mapFormat(format),
        },
        strategy: reader.readInt(),
      ),
      AnswerBid.tag => AnswerBid(
        actor,
        bid: reader.readInt(),
        tender: reader.readBool(),
      ),
      RunListed.tag => RunListed(
        actor,
        stock: reader.readInt(),
        payout: switch (reader.readNullableInt()) {
          final raw? => Fx.raw(raw),
          null => null,
        },
        growth: reader.readInt(),
        debt: switch (reader.readNullableInt()) {
          final raw? => Fx.raw(raw),
          null => null,
        },
        director: reader.readNullableInt(),
      ),
      BuyRival.tag => BuyRival(
        actor,
        via: reader.readInt(),
        stock: reader.readInt(),
        premium: Fx.raw(reader.readInt()),
      ),
      SellControlled.tag => SellControlled(actor, stock: reader.readInt()),
      ListCompany.tag => ListCompany(
        actor,
        company: CompanyId(reader.readInt()),
        share: Fx.raw(reader.readInt()),
        newShares: reader.readBool(),
      ),
      FoundCompany.tag => FoundCompany(
        actor,
        name: reader.readString(),
        capital: Money(reader.readInt()),
        parent: reader.readBool() ? CompanyId(reader.readInt()) : null,
      ),
      MoveBusiness.tag => MoveBusiness(
        actor,
        company: CompanyId(reader.readInt()),
        business: reader.readString(),
        to: switch (reader.readNullableInt()) {
          final index? => CompanyId(index),
          null => null,
        },
        name: reader.readString(),
      ),
      MoveCompany.tag => MoveCompany(
        actor,
        company: CompanyId(reader.readInt()),
        under: switch (reader.readNullableInt()) {
          final index? => CompanyId(index),
          null => null,
        },
      ),
      MergeCompany.tag => MergeCompany(
        actor,
        company: CompanyId(reader.readInt()),
        into: CompanyId(reader.readInt()),
      ),
      SellBusiness.tag => SellBusiness(
        actor,
        company: CompanyId(reader.readInt()),
        business: reader.readString(),
      ),
      SellCompany.tag => SellCompany(
        actor,
        company: CompanyId(reader.readInt()),
      ),
      RenameHolding.tag => RenameHolding(actor, name: reader.readString()),
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
    this.area,
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

  /// The floor it opens with, one the site offers its format (see
  /// `SiteDef.openingAreas`); the site's own if null.
  final int? area;

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
      ..writeNullableInt(brand?.index)
      ..writeNullableInt(area);
  }

  @override
  String toString() =>
      'OpenStore(actor: ${actor.index}, site: ${site.index}, name: $name, '
      'company: ${company?.index}, capital: ${capital.toDecimalString()}, '
      'format: ${format.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths, brand: ${brand?.index}, area: $area)';
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

/// Puts a director of [grade], who is [person], in charge of a company (see
/// `Director`); or, for the director already there, changes the brief. A
/// new grade or person replaces the director. Directors are paid daily,
/// like managers.
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
    this.nationalRate = Fx.zero,
    this.nationalAuto = false,
    this.nationalRegions = const [],
    this.person,
    this.goals = const {},
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

  /// How fast they grow the shops run by formula, or whether at the rate
  /// their grade runs well, and where (see `Director.nationalRate`).
  final Fx nationalRate;
  final bool nationalAuto;
  final List<String> nationalRegions;

  /// Who they are, from the month's shortlist; null for a director who
  /// applies the brief as it is.
  final DirectorPerson? person;

  /// The goal for each business (see `Director.goals`); empty for a brief
  /// set by [growth] and the national rate alone.
  final Map<String, Goal> goals;

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
      ..writeBool(nationalAuto)
      ..writeInt(nationalRate.raw)
      ..writeInt(nationalRegions.length);
    nationalRegions.forEach(writer.writeString);
    writer.writeBool(person != null);
    person?.write(writer);
    writeGoals(writer, goals);
  }

  @override
  String toString() =>
      'HireDirector(actor: ${actor.index}, company: ${company.index}, '
      'grade: ${grade.index}, strategy: ${strategy.index}, '
      'managerGrade: ${managerGrade.index}, growth: ${growth.name}, '
      'payout: $payout, borrows: $borrows, nationalRate: ${nationalRate.toDecimalString()}, '
      'nationalAuto: $nationalAuto, '
      'nationalRegions: $nationalRegions, person: ${person?.name}, '
      'goals: ${{for (final e in goals.entries) e.key: e.value.name}})';
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
    this.size = 0,
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

  /// Its size, by index into the scenario's sizes: 0 is a workshop.
  final int size;

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
    writer.writeInt(size);
  }

  @override
  String toString() =>
      'BuildFactory(actor: ${actor.index}, kind: ${kind.index}, '
      'country: ${country.index}, name: $name, company: ${company?.index}, '
      'capital: ${capital.toDecimalString()}, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths, '
      'shifts: $shifts, serves: $serves, size: $size)';
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

/// Has [company] buy [chain], by its place among [country]'s chains in the
/// national table, whole at its price, its shops then run as [strategy] has
/// shops of [format], borrowing [borrow] over [termMonths] if asked, the
/// chain's earnings counted.
final class BuyNationalChain extends Command {
  const BuyNationalChain(
    super.actor, {
    required this.company,
    required this.country,
    required this.chain,
    required this.format,
    required this.strategy,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 36;

  final CompanyId company;
  final CountryId country;
  final int chain;
  final FormatId format;
  final StrategyId strategy;
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeInt(chain)
      ..writeInt(format.index)
      ..writeInt(strategy.index)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'BuyNationalChain(actor: ${actor.index}, company: ${company.index}, '
      'country: ${country.index}, chain: $chain, format: ${format.index}, '
      'strategy: ${strategy.index}, borrow: ${borrow.toDecimalString()}, '
      'termMonths: $termMonths)';
}

/// Sells [company]'s shops run by formula in [country], [block] by its
/// place among the country's blocks in the national table, to the chain of
/// their trade with the most cash that can pay their price.
final class SellNational extends Command {
  const SellNational(
    super.actor, {
    required this.company,
    required this.country,
    required this.block,
  });

  static const int tag = 37;

  final CompanyId company;
  final CountryId country;
  final int block;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeInt(block);
  }

  @override
  String toString() =>
      'SellNational(actor: ${actor.index}, company: ${company.index}, '
      'country: ${country.index}, block: $block)';
}

/// Accepts a chain's [offer], by its number, for the actor's shops run by
/// formula.
final class AcceptNationalOffer extends Command {
  const AcceptNationalOffer(super.actor, {required this.offer});

  static const int tag = 38;

  final int offer;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(offer);
  }

  @override
  String toString() =>
      'AcceptNationalOffer(actor: ${actor.index}, offer: $offer)';
}

/// Turns down a chain's [offer], by its number.
final class DeclineNationalOffer extends Command {
  const DeclineNationalOffer(super.actor, {required this.offer});

  static const int tag = 39;

  final int offer;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(offer);
  }

  @override
  String toString() =>
      'DeclineNationalOffer(actor: ${actor.index}, offer: $offer)';
}

/// Sets what a factory's lab spends a month, and the product whose next
/// generation it develops: one the factory makes, or null for none, when
/// it spends nothing.
final class SetLab extends Command {
  const SetLab(
    super.actor, {
    required this.factory,
    required this.budget,
    this.project,
  });

  static const int tag = 40;

  final FactoryId factory;
  final Money budget;
  final ProductId? project;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(factory.index)
      ..writeInt(budget.cents)
      ..writeNullableInt(project?.index);
  }

  @override
  String toString() =>
      'SetLab(actor: ${actor.index}, factory: ${factory.index}, '
      'budget: ${budget.toDecimalString()}, project: ${project?.index})';
}

/// Hires [person], a candidate on the market, into [factory]'s lab, at
/// what someone of their repute asks.
final class HireKeyPerson extends Command {
  const HireKeyPerson(
    super.actor, {
    required this.person,
    required this.factory,
  });

  static const int tag = 41;

  final KeyPersonId person;
  final FactoryId factory;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(person.index)
      ..writeInt(factory.index);
  }

  @override
  String toString() =>
      'HireKeyPerson(actor: ${actor.index}, person: ${person.index}, '
      'factory: ${factory.index})';
}

/// Lets [person] go from the actor's lab: they leave for good.
final class DismissKeyPerson extends Command {
  const DismissKeyPerson(super.actor, {required this.person});

  static const int tag = 42;

  final KeyPersonId person;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(person.index);
  }

  @override
  String toString() =>
      'DismissKeyPerson(actor: ${actor.index}, person: ${person.index})';
}

/// Sells [store]'s stock of [product] that has been on hand [days] or more
/// to a jobber, for the category's clearance share of what it cost: only
/// goods that go out of fashion.
final class ClearStock extends Command {
  const ClearStock(
    super.actor, {
    required this.store,
    required this.product,
    required this.days,
  });

  static const int tag = 43;

  final StoreId store;
  final ProductId product;
  final int days;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(store.index)
      ..writeInt(product.index)
      ..writeInt(days);
  }

  @override
  String toString() =>
      'ClearStock(actor: ${actor.index}, store: ${store.index}, '
      'product: ${product.index}, days: $days)';
}

/// Starts a software company named [name] in [country], with [capital] of
/// the actor's own cash: a company of its own, which holds nothing else,
/// its product to be built before it sells.
final class StartSoftware extends Command {
  const StartSoftware(
    super.actor, {
    required this.name,
    required this.country,
    this.capital = Money.zero,
    this.company,
  });

  static const int tag = 44;

  final String name;
  final CountryId country;
  final Money capital;

  /// The player's company it starts in, beside what that company holds;
  /// null for a company of its own, under the holding.
  final CompanyId? company;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeString(name)
      ..writeInt(country.index)
      ..writeInt(capital.cents)
      ..writeNullableInt(company?.index);
  }

  @override
  String toString() =>
      'StartSoftware(actor: ${actor.index}, name: $name, '
      'country: ${country.index}, capital: ${capital.toDecimalString()})';
}

/// Sets what [software]'s customers pay a month.
final class SetSoftwarePrice extends Command {
  const SetSoftwarePrice(
    super.actor, {
    required this.software,
    required this.price,
  });

  static const int tag = 45;

  final SoftwareId software;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'SetSoftwarePrice(actor: ${actor.index}, software: ${software.index}, '
      'price: ${price.toDecimalString()})';
}

/// Sets what [software] spends on marketing a month, from its first
/// version on.
final class SetSoftwareMarketing extends Command {
  const SetSoftwareMarketing(
    super.actor, {
    required this.software,
    required this.budget,
  });

  static const int tag = 46;

  final SoftwareId software;
  final Money budget;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index)
      ..writeInt(budget.cents);
  }

  @override
  String toString() =>
      'SetSoftwareMarketing(actor: ${actor.index}, '
      'software: ${software.index}, budget: ${budget.toDecimalString()})';
}

/// Hires [person], a candidate on the market for software people, into
/// [software]'s team, at what someone of their repute asks.
final class HireSoftwarePerson extends Command {
  const HireSoftwarePerson(
    super.actor, {
    required this.software,
    required this.person,
  });

  static const int tag = 47;

  final SoftwareId software;
  final KeyPersonId person;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index)
      ..writeInt(person.index);
  }

  @override
  String toString() =>
      'HireSoftwarePerson(actor: ${actor.index}, '
      'software: ${software.index}, person: ${person.index})';
}

/// Sells [share] of [software]'s company to investors, at what it is worth
/// before the round: their money goes into the company.
final class RaiseRound extends Command {
  const RaiseRound(super.actor, {required this.software, required this.share});

  static const int tag = 48;

  final SoftwareId software;
  final Fx share;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index)
      ..writeInt(share.raw);
  }

  @override
  String toString() =>
      'RaiseRound(actor: ${actor.index}, software: ${software.index}, '
      'share: ${share.toDecimalString()})';
}

/// Sells [software]'s company whole to the rival whose offer stands, for
/// its price: the actor's share of it comes to them.
final class AcceptSoftwareOffer extends Command {
  const AcceptSoftwareOffer(super.actor, {required this.software});

  static const int tag = 49;

  final SoftwareId software;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index);
  }

  @override
  String toString() =>
      'AcceptSoftwareOffer(actor: ${actor.index}, '
      'software: ${software.index})';
}

/// Turns down the offer standing for [software]'s company.
final class DeclineSoftwareOffer extends Command {
  const DeclineSoftwareOffer(super.actor, {required this.software});

  static const int tag = 50;

  final SoftwareId software;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index);
  }

  @override
  String toString() =>
      'DeclineSoftwareOffer(actor: ${actor.index}, '
      'software: ${software.index})';
}

/// Shuts [software] down: its people leave, its customers go elsewhere, and
/// its company keeps its cash.
final class ShutDownSoftware extends Command {
  const ShutDownSoftware(super.actor, {required this.software});

  static const int tag = 51;

  final SoftwareId software;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(software.index);
  }

  @override
  String toString() =>
      'ShutDownSoftware(actor: ${actor.index}, software: ${software.index})';
}

/// Enlarges [factory] to the next of the scenario's sizes, paying the
/// difference from its company's cash, with [capital] of the actor's own
/// and [borrow] over [termMonths] if given; it runs at its size until the
/// works end.
final class EnlargeFactory extends Command {
  const EnlargeFactory(
    super.actor, {
    required this.factory,
    this.capital = Money.zero,
    this.borrow = Money.zero,
    this.termMonths = 0,
  });

  static const int tag = 52;

  final FactoryId factory;
  final Money capital;
  final Money borrow;
  final int termMonths;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(factory.index)
      ..writeInt(capital.cents)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths);
  }

  @override
  String toString() =>
      'EnlargeFactory(actor: ${actor.index}, factory: ${factory.index}, '
      'capital: ${capital.toDecimalString()}, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths)';
}

/// Bids [price] a unit for [tender], numbered, to be supplied by
/// [factory]; with no price, withdraws the actor's bid.
final class BidTender extends Command {
  const BidTender(
    super.actor, {
    required this.tender,
    required this.factory,
    this.price,
  });

  static const int tag = 53;

  final int tender;
  final FactoryId factory;
  final Money? price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(tender)
      ..writeInt(factory.index)
      ..writeNullableInt(price?.cents);
  }

  @override
  String toString() =>
      'BidTender(actor: ${actor.index}, tender: $tender, '
      'factory: ${factory.index}, price: ${price?.toDecimalString()})';
}

/// Breaks [contract], numbered: the factory's company pays its fee and the
/// chain puts the rest out to tender.
final class BreakContract extends Command {
  const BreakContract(super.actor, {required this.contract});

  static const int tag = 54;

  final int contract;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(contract);
  }

  @override
  String toString() =>
      'BreakContract(actor: ${actor.index}, contract: $contract)';
}

/// Answers a chain's request to cut [contract]'s price: [accept] takes the
/// price it asked; turning it down ends the contract and the chain puts
/// the rest out to tender.
final class AnswerContract extends Command {
  const AnswerContract(
    super.actor, {
    required this.contract,
    required this.accept,
  });

  static const int tag = 55;

  final int contract;
  final bool accept;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(contract)
      ..writeBool(accept);
  }

  @override
  String toString() =>
      'AnswerContract(actor: ${actor.index}, contract: $contract, '
      'accept: $accept)';
}

/// Asks [contract]'s chain for a new [price] a unit: it agrees if the
/// price still beats what rivals would bid, as it weighs bids.
final class AskPrice extends Command {
  const AskPrice(super.actor, {required this.contract, required this.price});

  static const int tag = 56;

  final int contract;
  final Money price;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(contract)
      ..writeInt(price.cents);
  }

  @override
  String toString() =>
      'AskPrice(actor: ${actor.index}, contract: $contract, '
      'price: ${price.toDecimalString()})';
}

/// Buys [units] shares of listed company [of] with the player's own money,
/// or if [index], units of exchange [of]'s index.
final class BuyShares extends Command {
  const BuyShares(
    super.actor, {
    required this.of,
    required this.units,
    this.index = false,
  });

  static const int tag = 57;

  final int of;
  final int units;
  final bool index;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(of)
      ..writeInt(units)
      ..writeBool(index);
  }

  @override
  String toString() =>
      'BuyShares(actor: ${actor.index}, of: $of, units: $units, '
      'index: $index)';
}

/// Sells [units] of the player's shares of listed company [of], or if
/// [index], of their units of exchange [of]'s index.
final class SellShares extends Command {
  const SellShares(
    super.actor, {
    required this.of,
    required this.units,
    this.index = false,
  });

  static const int tag = 58;

  final int of;
  final int units;
  final bool index;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(of)
      ..writeInt(units)
      ..writeBool(index);
  }

  @override
  String toString() =>
      'SellShares(actor: ${actor.index}, of: $of, units: $units, '
      'index: $index)';
}

/// Bids for every share of listed company [stock] at [premium] over its
/// price today, by [bidder]: the player's holding ([holdingOwner]) or one
/// of their companies, borrowing [borrow] over [termMonths]. For a chain,
/// [format] and [strategy] are what its shops take in the bidder's company.
final class BidForCompany extends Command {
  const BidForCompany(
    super.actor, {
    required this.stock,
    required this.premium,
    required this.bidder,
    this.borrow = Money.zero,
    this.termMonths = 0,
    this.format = -1,
    this.strategy = -1,
  });

  static const int tag = 59;

  final int stock;
  final Fx premium;
  final int bidder;
  final Money borrow;
  final int termMonths;
  final int format;
  final int strategy;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(stock)
      ..writeInt(premium.raw)
      ..writeInt(bidder)
      ..writeInt(borrow.cents)
      ..writeInt(termMonths)
      ..writeInt(format)
      ..writeInt(strategy);
  }

  @override
  String toString() =>
      'BidForCompany(actor: ${actor.index}, stock: $stock, '
      'premium: ${premium.toDecimalString()}, bidder: $bidder, '
      'borrow: ${borrow.toDecimalString()}, termMonths: $termMonths, '
      'format: $format, strategy: $strategy)';
}

/// Offers the player's shares into someone else's bid [bid], or, if not
/// [tender], keeps them out of it.
final class AnswerBid extends Command {
  const AnswerBid(super.actor, {required this.bid, required this.tender});

  static const int tag = 60;

  final int bid;
  final bool tender;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(bid)
      ..writeBool(tender);
  }

  @override
  String toString() =>
      'AnswerBid(actor: ${actor.index}, bid: $bid, tender: $tender)';
}

/// Sets the levers of company by formula [stock], which the player
/// controls: the share of profit paid out, how fast it invests to grow (-1
/// slow, 0 steady, 1 fast), the debt it aims for in years of profit, and
/// the grade of director running it; null keeps its own.
final class RunListed extends Command {
  const RunListed(
    super.actor, {
    required this.stock,
    this.payout,
    this.growth = 0,
    this.debt,
    this.director,
  });

  static const int tag = 61;

  final int stock;
  final Fx? payout;
  final int growth;
  final Fx? debt;
  final int? director;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(stock)
      ..writeNullableInt(payout?.raw)
      ..writeInt(growth)
      ..writeNullableInt(debt?.raw)
      ..writeNullableInt(director);
  }

  @override
  String toString() =>
      'RunListed(actor: ${actor.index}, stock: $stock, payout: $payout, '
      'growth: $growth, debt: $debt, director: $director)';
}

/// Has company [via], which the player controls, bid at [premium] for
/// smaller listed company [stock] of its sector and country, to merge it
/// in, paying with debt.
final class BuyRival extends Command {
  const BuyRival(
    super.actor, {
    required this.via,
    required this.stock,
    required this.premium,
  });

  static const int tag = 62;

  final int via;
  final int stock;
  final Fx premium;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(via)
      ..writeInt(stock)
      ..writeInt(premium.raw);
  }

  @override
  String toString() =>
      'BuyRival(actor: ${actor.index}, via: $via, stock: $stock, '
      'premium: ${premium.toDecimalString()})';
}

/// Puts company [stock], which the player controls, up for sale: the
/// richest raider that can bids for all of it, the player's shares
/// tendered.
final class SellControlled extends Command {
  const SellControlled(super.actor, {required this.stock});

  static const int tag = 63;

  final int stock;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(stock);
  }

  @override
  String toString() => 'SellControlled(actor: ${actor.index}, stock: $stock)';
}

/// Lists [company], one of the player's, on its country's exchange, selling
/// [share] of it: new shares, whose money goes into the company, if
/// [newShares], else the player's own, whose money goes to the player.
final class ListCompany extends Command {
  const ListCompany(
    super.actor, {
    required this.company,
    required this.share,
    required this.newShares,
  });

  static const int tag = 64;

  final CompanyId company;
  final Fx share;
  final bool newShares;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(share.raw)
      ..writeBool(newShares);
  }

  @override
  String toString() =>
      'ListCompany(actor: ${actor.index}, company: ${company.index}, '
      'share: ${share.toDecimalString()}, newShares: $newShares)';
}

/// Founds an empty company named [name] for the actor, held by [parent], one
/// of their companies, or by their holding if null; [capital] comes out of
/// the holder's cash. Its businesses are started from it afterwards.
final class FoundCompany extends Command {
  const FoundCompany(
    super.actor, {
    required this.name,
    required this.capital,
    this.parent,
  });

  static const int tag = 65;

  final String name;
  final Money capital;
  final CompanyId? parent;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeString(name)
      ..writeInt(capital.cents)
      ..writeBool(parent != null);
    if (parent case final parent?) writer.writeInt(parent.index);
  }

  @override
  String toString() =>
      'FoundCompany(actor: ${actor.index}, name: $name, '
      'capital: ${capital.toDecimalString()}, parent: ${parent?.index})';
}

/// Moves [company]'s business [business] (see `tradeKey`, `plantsKey` and
/// `softwareBusiness`), all its parts, into the owner's company [to], or
/// with none into a new company of its own, [name], under [company]: at its
/// book value, the owner's design of 2026-11-18 (see `MoveBusiness` in the
/// restructuring rules).
final class MoveBusiness extends Command {
  const MoveBusiness(
    super.actor, {
    required this.company,
    required this.business,
    this.to,
    this.name = '',
  });

  static const int tag = 66;

  final CompanyId company;
  final String business;
  final CompanyId? to;
  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeString(business)
      ..writeNullableInt(to?.index)
      ..writeString(name);
  }

  @override
  String toString() =>
      'MoveBusiness(actor: ${actor.index}, company: ${company.index}, '
      'business: $business, to: ${to?.index}, name: $name)';
}

/// Moves [company] under another of the owner's companies, [under], or with
/// none back under their holding, at what its holder put in it.
final class MoveCompany extends Command {
  const MoveCompany(super.actor, {required this.company, this.under});

  static const int tag = 67;

  final CompanyId company;
  final CompanyId? under;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeNullableInt(under?.index);
  }

  @override
  String toString() =>
      'MoveCompany(actor: ${actor.index}, company: ${company.index}, '
      'under: ${under?.index})';
}

/// Merges [company] into [into], its parent or a company beside it, which
/// takes all it has, owes and holds.
final class MergeCompany extends Command {
  const MergeCompany(super.actor, {required this.company, required this.into});

  static const int tag = 68;

  final CompanyId company;
  final CompanyId into;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeInt(into.index);
  }

  @override
  String toString() =>
      'MergeCompany(actor: ${actor.index}, company: ${company.index}, '
      'into: ${into.index})';
}

/// Sells [company]'s business [business] on the spot, each part to the
/// buyer best able to pay (see `businessSale`).
final class SellBusiness extends Command {
  const SellBusiness(
    super.actor, {
    required this.company,
    required this.business,
  });

  static const int tag = 69;

  final CompanyId company;
  final String business;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeInt(company.index)
      ..writeString(business);
  }

  @override
  String toString() =>
      'SellBusiness(actor: ${actor.index}, company: ${company.index}, '
      'business: $business)';
}

/// Sells [company] whole on the spot to the owner best able to pay: one
/// holding shops alone.
final class SellCompany extends Command {
  const SellCompany(super.actor, {required this.company});

  static const int tag = 70;

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
      'SellCompany(actor: ${actor.index}, company: ${company.index})';
}

/// Renames the actor's holding.
final class RenameHolding extends Command {
  const RenameHolding(super.actor, {required this.name});

  static const int tag = 71;

  final String name;

  @override
  void write(StateWriter writer) {
    writer
      ..writeInt(tag)
      ..writeInt(actor.index)
      ..writeString(name);
  }

  @override
  String toString() => 'RenameHolding(actor: ${actor.index}, name: $name)';
}
