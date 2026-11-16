import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../reports/period_report.dart' show ReportPeriod;
import '../state/districts.dart';
import 'national_view.dart';
import 'stocks_view.dart';
import '../state/stocks.dart' show Listing;
import '../state/brands.dart';
import '../state/buying_terms.dart';
import '../state/credit.dart';
import '../state/director.dart';
import '../state/entities.dart';
import '../state/factories.dart' show factoryLead, factorySaving, kindMakes;
import '../state/factory.dart';
import '../state/labs.dart';
import '../state/talent.dart';
import '../state/history.dart';
import '../state/macro.dart';
import '../state/market.dart';
import '../state/public_record.dart';
import '../state/orders.dart';
import '../state/research.dart';
import '../state/store.dart';
import '../state/taxation.dart';
import '../state/valuation.dart';
import '../state/world_state.dart';
import 'software_view.dart';
import '../state/software_rules.dart' show softwareOf;
import 'factory_sales_view.dart';

/// What one actor can see at the start of a day: the economy, its own
/// companies and stores in full, every store's shelf and hours, each
/// market's size, and the research it bought. Policies, and later the app,
/// read the world only through this. It is a copy, unaffected by later
/// steps.
final class Observation {
  const Observation({
    required this.today,
    required this.actor,
    required this.cash,
    required this.lastBankruptcy,
    required this.macro,
    this.economies = const [],
    this.histories = const [],
    required this.households,
    required this.censuses,
    required this.companyNames,
    required this.companies,
    required this.shelves,
    required this.vacantSites,
    required this.reports,
    this.filings = const [],
    this.history = const [],
    this.companyOwners = const [],
    this.valuations = const [],
    this.companyPrices = const [],
    this.companyCredits = const [],
    this.guaranteeRoom = Money.zero,
    this.portfolio = Money.zero,
    this.listedCompanies = const [],
    this.brands = const [],
    this.offers = const [],
    this.candidates = const [],
    this.softwareMarket,
    this.softwareCandidates = const [],
    this.tenders = const [],
    this.producers = const [],
    List<DistrictView> Function() districts = _noDistricts,
    List<NationalCountryView> Function() national = _noNational,
    StockMarketView? Function() stocks = _noStocks,
  }) : _districts = districts,
       _national = national,
       _stocks = stocks;

  static StockMarketView? _noStocks() => null;

  final StockMarketView? Function() _stocks;

  /// The stock market as the actor sees it; null without one. Worked out
  /// the first time anyone looks.
  StockMarketView? get stocks => _stocks();

  static List<NationalCountryView> _noNational() => const [];

  final List<NationalCountryView> Function() _national;

  /// Every country by formula, region by region, with the actor's shops run
  /// there: empty without a national table or with one country. Worked out
  /// when asked for.

  List<NationalCountryView> get national => _national();

  static List<DistrictView> _noDistricts() => const [];

  final List<DistrictView> Function() _districts;

  /// The districts run by formula, as anyone can see them, where chains may
  /// open and buy. Worked out when first asked for, as few look.
  List<DistrictView> get districts => _districts();

  /// Every brand, whose names are on the shop fronts, by [BrandId].
  final List<BrandView> brands;

  /// The day about to be simulated.
  final Day today;
  final PersonId actor;

  /// The actor's personal cash.
  final Money cash;

  /// When a company of the actor's was last liquidated, if ever.
  final Day? lastBankruptcy;

  /// The state of the first country's economy, which everyone can read in
  /// the news.
  final MacroView macro;

  /// Every country's economy, by [CountryId]: empty for one country, whose
  /// economy is [macro].
  final List<MacroView> economies;

  /// Every country's economy month by month, oldest first, by [CountryId]:
  /// empty for one country, whose history is [history].
  final List<List<EconomicMonth>> histories;

  /// [country]'s economy.
  MacroView economy(CountryId country) =>
      country.index < economies.length ? economies[country.index] : macro;

  /// The economy of the country [market] is in.
  MacroView economyAt(ContentDb content, MarketId market) =>
      economy(content.countryOf(market));

  /// [country]'s economy month by month, oldest first.
  List<EconomicMonth> historyOf(CountryId country) =>
      country.index < histories.length ? histories[country.index] : history;

  /// Households per market at the latest census, indexed by [MarketId].
  /// Censuses are public, taken every first of January.
  final List<int> households;

  /// Every market's censuses, oldest first, indexed by [MarketId].
  final List<List<Census>> censuses;

  /// Every company's name, indexed by [CompanyId].
  final List<String> companyNames;

  /// The companies the actor owns, active or liquidated.
  final List<CompanyView> companies;

  /// Every store's public face, indexed by [StoreId].
  final List<ShelfView> shelves;

  /// Sites where anyone may open a store.
  final List<SiteId> vacantSites;

  /// The market studies the actor bought, oldest first.
  final List<ResearchReport> reports;

  /// Every company's yearly accounts, public: oldest first.
  final List<Filing> filings;

  /// The economy month by month, oldest first.
  final List<EconomicMonth> history;

  /// Every company's owner, as the register shows: indexed by [CompanyId].
  final List<PersonId> companyOwners;

  /// Every store's asking price and what it rests on, indexed by [StoreId]:
  /// null for a closed store, or all of them if the scenario sells nothing.
  final List<Valuation?> valuations;

  /// What each company sells for whole, indexed by [CompanyId]: null if it
  /// has been liquidated or the scenario sells nothing.
  final List<Money?> companyPrices;

  /// What the bank still lends each company on its earnings, without a
  /// guarantee (see `earningsRoom`), indexed by [CompanyId]: below zero if
  /// its loans exceed what its earnings carry, null if it has been
  /// liquidated. Buying a store adds the multiple of its earnings.
  final List<Money?> companyCredits;

  /// How much more the actor can guarantee (see `guaranteeRoom`).
  final Money guaranteeRoom;

  /// What the actor's shares and index units are worth at today's prices.
  final Money portfolio;

  /// The player's companies listed on an exchange: their worth to the player
  /// is their shares, in [portfolio].
  final List<CompanyId> listedCompanies;

  /// The key people on the market, for anyone to hire, as their track
  /// records show them.
  final List<KeyPersonView> candidates;

  /// The world market for software, if there is one, and the people on
  /// its market for software work.
  final SoftwareMarketView? softwareMarket;
  final List<KeyPersonView> softwareCandidates;

  /// Chains' tenders, open and lately closed, in the order they opened.
  final List<TenderView> tenders;

  /// The rival producers factories bid against.
  final List<ProducerView> producers;

  /// The factories that sell to anyone's shops, with what each can spare
  /// this month: public, as a supplier's terms are.
  final List<FactoryOffer> offers;

  /// The actor's factory that makes [product] for [store], one of the
  /// actor's: running, making its category and serving its country, the
  /// one with the most left to make this month first, then the first
  /// built. The store then buys the product only from it.
  FactoryView? factoryFor(
    ContentDb content,
    StoreView store,
    ProductDef product,
  ) {
    final factories = content.factories;
    if (factories == null) return null;
    final country = content.countryOf(store.market);
    FactoryView? best;
    for (final company in companies) {
      if (company.status != CompanyStatus.active) continue;
      for (final factory in company.factories) {
        if (!factory.making ||
            !factory.servesCountry(country) ||
            factories.kinds[factory.kind.index].category != product.category) {
          continue;
        }
        if (best == null || factory.capacityLeft > best.capacityLeft) {
          best = factory;
        }
      }
    }
    return best;
  }

  /// Rivals' factories that would sell [store] goods, the actor's own
  /// left out.
  List<FactoryOffer> offersFor(ContentDb content, StoreView store) {
    final country = content.countryOf(store.market);
    return [
      for (final offer in offers)
        if (companyOwners[offer.company.index] != actor &&
            offer.serves.length > country.index &&
            offer.serves[country.index])
          offer,
    ];
  }
}

/// A factory selling to rivals, as anyone can see it: what it makes, where
/// it delivers, its discount on their wholesalers' prices and what it can
/// still make for them this month.
typedef FactoryOffer = ({
  FactoryId id,
  FactoryKindId kind,
  CompanyId company,
  CountryId country,
  List<bool> serves,
  Fx discount,
  int spare,
});

/// A key person as a candidate, or as their employer sees them.
final class KeyPersonView {
  const KeyPersonView({
    required this.id,
    required this.name,
    required this.role,
    required this.level,
    required this.known,
    required this.salary,
    required this.since,
    required this.monthsWorked,
    this.leaves,
  });

  final KeyPersonId id;
  final String name;
  final KeyRole role;

  /// Their place in the scenario's levels: what their track record
  /// suggests, or once [known], what they have shown at work.
  final int level;

  /// Whether their employer has seen enough of their work to know it.
  final bool known;

  /// A month's pay: for a candidate, at a wage index of one in the first
  /// country; for someone employed, at their factory's country's wages.
  final Money salary;

  /// The day they came onto the market, or were hired.
  final Day since;
  final int monthsWorked;

  /// The day a candidate is taken by another company: the first of the
  /// month after their time on the market runs out.
  final Day? leaves;
}

/// One of a factory's products as its lab has developed it.
typedef LineView = ({
  ProductId product,
  int generation,
  Fx lead,
  Fx saving,
  Day? launchedOn,

  /// Its lead on the first of each month since its lab took it up, oldest
  /// first.
  List<Fx> history,
});

/// A factory's lab as its owner sees it, its people taken at what is known
/// of them.
final class LabView {
  const LabView({
    required this.budget,
    required this.budgetLimit,
    required this.project,
    required this.work,
    required this.needed,
    required this.monthlyWork,
    required this.expectedGain,
    required this.gainSpread,
    required this.expectedSaving,
    required this.engineers,
    required this.designers,
    required this.wageLevel,
    required this.maxPeople,
    required this.lines,
    required this.people,
  });

  /// What it spends a month while it has a [project], and the most it may.
  final Money budget;
  final Money budgetLimit;

  /// The product whose next generation it is developing, if any.
  final ProductId? project;

  /// The work done towards that generation, the work it takes, and what a
  /// month adds at this budget with these engineers.
  final Money work;
  final Money? needed;
  final Money monthlyWork;

  /// The lead that generation should add, give or take [gainSpread] of it,
  /// and the share of its materials it should save.
  final Fx expectedGain;
  final Fx gainSpread;
  final Fx? expectedSaving;

  /// What its engineers and designers add to its multipliers.
  final Fx engineers;
  final Fx designers;

  /// Wages where it stands against the first country's at the start: what
  /// a candidate's pay is multiplied by here.
  final Fx wageLevel;
  final int maxPeople;

  /// Each product the factory makes, as developed so far.
  final List<LineView> lines;

  /// Its key people, in the order hired.
  final List<KeyPersonView> people;

  /// The months until the generation launches at this pace; null with no
  /// project or nothing spent.
  int? get monthsLeft {
    final needed = this.needed;
    if (needed == null || monthlyWork <= Money.zero) return null;
    final left = needed - work;
    if (left <= Money.zero) return 1;
    return (left.cents + monthlyWork.cents - 1) ~/ monthlyWork.cents;
  }

  /// A month of its people's pay.
  Money get monthlyPay =>
      people.fold(Money.zero, (sum, person) => sum + person.salary);
}

/// A factory as its owner sees it.
final class FactoryView {
  const FactoryView({
    required this.id,
    required this.kind,
    required this.company,
    required this.country,
    required this.name,
    required this.opensOn,
    required this.builtFor,
    required this.shifts,
    required this.serves,
    required this.rivalDiscount,
    required this.status,
    required this.making,
    required this.monthCapacity,
    required this.madeThisMonth,
    required this.capacityLeft,
    required this.spare,
    required this.recentOwnUnits,
    required this.recentRivalUnits,
    required this.recentMargin,
    required this.earnings,
    required this.dailyWages,
    required this.monthlySite,
    required this.value,
    this.lab,
    this.size = 0,
    this.sales,
  });

  /// Its lab, if the scenario has labs.
  final LabView? lab;

  /// Its size, by index into the scenario's sizes: 0 is a workshop.
  final int size;

  /// How it sells to other companies, if the scenario has such sales.
  final FactorySalesView? sales;

  final FactoryId id;
  final FactoryKindId kind;
  final CompanyId company;
  final CountryId country;
  final String name;
  final Day opensOn;
  final Money builtFor;
  final int shifts;

  /// The countries whose shops it delivers to, by [CountryId].
  final List<bool> serves;

  /// Its discount for rivals, or null if it sells only to its owner's
  /// shops.
  final Fx? rivalDiscount;
  final FactoryStatus status;

  /// Whether it makes goods today: built and not closed.
  final bool making;

  /// What it can make this month at its shifts, what it has made so far,
  /// and what is left.
  final int monthCapacity;
  final int madeThisMonth;
  final int capacityLeft;

  /// What it can still sell rivals this month.
  final int spare;

  /// Units made for its owner's shops and for rivals over the last four
  /// weeks, and what they sold for beyond their materials and freight.
  final int recentOwnUnits;
  final int recentRivalUnits;
  final Money recentMargin;

  /// A year's earnings against buying, at its last four weeks (see
  /// `factoryEarnings`); null too soon to tell.
  final Money? earnings;

  /// What its shifts cost a day, and its site a month, at today's levels.
  final Money dailyWages;
  final Money monthlySite;

  /// Its asking price and what it rests on; null if it isn't making goods.
  final Valuation? value;

  bool servesCountry(CountryId country) =>
      country.index < serves.length && serves[country.index];

  bool get building => status == FactoryStatus.running && !making;
}

/// The economy as published.
typedef MacroView = ({
  RegimeId regime,
  Fx priceIndex,
  Fx wageIndex,

  /// The latest annual inflation rate.
  Fx inflation,
  Fx policyRate,

  /// The share of the labour force out of work.
  Fx unemployment,
});

/// A loan as its borrower sees it.
typedef LoanView = ({
  int number,
  Money outstanding,
  Fx rate,
  int installmentsLeft,
  bool guaranteed,
});

/// A store's results over its owner's last complete months, up to twelve:
/// its sales, what it earned before interest and tax (see
/// [StoreReport.profit]), and the days covered.
typedef StoreMonths = ({Money revenue, Money profit, int days});

/// A store's manager, as the owner sees it.

typedef ManagerView = ({
  ManagerGradeId grade,
  StrategyId strategy,

  /// Indexed by [ManagerDuty].
  List<bool> duties,
  Day hiredOn,
});

/// A purchase order on its way, as the buyer sees it.
typedef OrderView = ({
  int number,
  StoreId store,
  SupplierId supplier,
  Day arrival,
  List<OrderLine> lines,

  /// The factory it comes from, if any.
  FactoryId? factory,
});

/// A bill not yet paid, as the debtor sees it.
typedef BillView = ({
  PartyRef creditor,
  EntryReason reason,
  Money amount,
  Day due,
});

/// A company as its owner sees it.
final class CompanyView {
  const CompanyView({
    required this.id,
    required this.status,
    required this.founded,
    required this.balances,
    required this.committed,
    required this.loans,
    required this.orders,
    required this.bills,
    required this.stores,
    this.lossCarried = Money.zero,
    this.cushionDays = defaultCushionDays,
    this.taxAccrued = Money.zero,
    this.countryTaxes = const [],
    this.director,
    this.memos = const [],
    this.factories = const [],
    this.goodsBought = Money.zero,
    this.buyingDiscount = Fx.zero,
    this.software,
  });

  final CompanyId id;

  /// Its software product, if it is a software company.
  final SoftwareView? software;

  /// What it bought of goods over its latest twelve months, and what its
  /// suppliers take off them for it (see `buyingDiscount`).
  final Money goodsBought;
  final Fx buyingDiscount;
  final CompanyStatus status;
  final Day founded;

  /// Its factories, built, being built or closed, in the order built.
  final List<FactoryView> factories;

  /// Account balances, debit-positive, indexed by [AccountKind].
  final List<Money> balances;

  /// Unpaid bills plus orders not yet delivered: money already spoken for.
  final Money committed;
  final List<LoanView> loans;

  /// Orders not yet delivered, in the order they were placed.
  final List<OrderView> orders;

  /// Unpaid bills, oldest first.
  final List<BillView> bills;
  final List<StoreView> stores;

  Money balance(AccountKind kind) => balances[kind.index];

  Money get cash => balance(AccountKind.cash);

  /// What the company owns less what it owes, at book value: cash, stock at
  /// cost, what it paid for stores it bought and stakes in other companies,
  /// less unpaid bills and loans. Fitting out and works are spent, so they
  /// don't count.
  Money get netAssets =>
      balance(AccountKind.cash) +
      balance(AccountKind.inventory) +
      balance(AccountKind.receivables) +
      balance(AccountKind.businessAssets) +
      balance(AccountKind.investments) +
      balance(AccountKind.payables) +
      balance(AccountKind.loans);

  /// Past losses not yet set against profit for tax.
  final Money lossCarried;

  /// How many days of wages its cash cushion holds.
  final int cushionDays;

  /// The corporate tax on this year's profit so far, less losses carried:
  /// what January's bill would be if the year ended today. On the first of
  /// January, before that bill, the tax on the year just ended.
  final Money taxAccrued;

  /// [taxAccrued] country by country, where it trades in several: what each
  /// country takes of the year so far. Empty in a world of one country.
  final List<CountryTax> countryTaxes;

  /// Who runs it for its owner, if anyone.
  final Director? director;

  /// What its directors did, oldest first.
  final List<Memo> memos;

  /// Profit kept since the start: what dividends may be paid from.
  Money get retainedEarnings => netAssets + balance(AccountKind.equity);
}

/// A store as its owner sees it.
final class StoreView {
  const StoreView({
    required this.id,
    required this.site,
    required this.status,
    required this.opensOn,
    required this.market,
    required this.shelfSlots,
    required this.storageUnits,
    required this.prices,
    required this.stock,
    required this.onOrder,
    required this.staff,
    required this.service,
    required this.sales,
    required this.area,
    this.format = const FormatId(0),
    this.marketingShare = Fx.zero,
    this.goodwill = Money.zero,
    this.reputation = Fx.zero,
    this.manager,
    this.works,
    this.enlargedOn,
    this.boughtFor = Money.zero,
    this.acquiredOn,
    this.buyer,
    this.recentMonths = (revenue: Money.zero, profit: Money.zero, days: 0),
    this.quality = const [],
    this.fashion = const [],
    this.lots = const [],
  });

  /// How far what is on hand of each product is over the market's
  /// standard, indexed by [ProductId]: empty if all are at it.
  final List<Fx> quality;

  /// What each product on hand has kept of its appeal against new, indexed
  /// by [ProductId]: empty if nothing it holds goes out of fashion.
  final List<Fx> fashion;

  /// What [product] on its shelves has kept of its appeal: 1 for new.
  Fx fashionOf(ProductId product) =>
      product.index < fashion.length ? fashion[product.index] : Fx.one;

  /// Each product's lots on hand, oldest first, indexed by [ProductId]:
  /// empty if nothing it holds goes out of fashion, and for goods that
  /// don't.
  final List<List<LotAge>> lots;

  /// How far [product] on its shelves is over the market's standard.
  Fx qualityOf(ProductId product) =>
      product.index < quality.length ? quality[product.index] : Fx.zero;

  final StoreId id;
  final SiteId site;

  /// What kind of business it is, which sets what it may sell.
  final FormatId format;

  /// The share of its recent sales it spends on marketing each day.
  final Fx marketingShare;

  /// What its advertising has built up.
  final Money goodwill;

  /// What shoppers think of it, from 0 to 1.
  final Fx reputation;
  final StoreStatus status;

  /// The first trading day.
  final Day opensOn;
  final MarketId market;
  final int shelfSlots;
  final int storageUnits;

  /// Shelf price per product, indexed by [ProductId]; null if not listed.
  final List<Money?> prices;

  /// Units on hand, indexed by [ProductId].
  final List<int> stock;

  /// Units ordered but not delivered, indexed by [ProductId].
  final List<int> onOrder;

  /// Staff per slot of the day, indexed by [DaySlot]; zero means closed.
  final List<int> staff;

  /// How well each slot's staff kept up with shoppers, from 0 to 1, indexed
  /// by [DaySlot].
  final List<Fx> service;
  final RecentSales sales;

  /// Who runs the store for its owner, if anyone.
  final ManagerView? manager;

  /// Selling area in square metres.
  final int area;

  /// Enlargement under way, if any.
  final Works? works;

  /// When the store last grew, if ever.
  final Day? enlargedOn;

  /// What its owner paid for it beyond its stock; zero if they opened it.
  final Money boughtFor;

  /// When its owner bought it, if they did.
  final Day? acquiredOn;

  /// The company that would buy it at its asking price today, if any.
  final CompanyId? buyer;

  /// How it did over its owner's last complete months.
  final StoreMonths recentMonths;

  int get listedProducts => prices.where((price) => price != null).length;
}

/// A store as everyone sees it.
final class ShelfView {
  const ShelfView({
    required this.id,
    required this.name,
    required this.company,
    required this.site,
    required this.status,
    required this.market,
    required this.location,
    required this.prices,
    required this.openSlots,
    required this.area,
    this.format = const FormatId(0),
    this.opensOn = const Day(0),
    this.acquiredOn,
    this.quality = const [],
  });

  /// How far each product on its shelves is over the market's standard,
  /// which anyone can see, indexed by [ProductId]: empty if all are at it.
  final List<Fx> quality;

  /// How far [product] on its shelves is over the market's standard.
  Fx qualityOf(ProductId product) =>
      product.index < quality.length ? quality[product.index] : Fx.zero;

  final StoreId id;
  final String name;
  final CompanyId company;
  final SiteId site;
  final StoreStatus status;
  final MarketId market;
  final Fx location;

  /// What kind of business it is.
  final FormatId format;

  /// Whether the store opens in each slot of the day, indexed by [DaySlot].
  final List<bool> openSlots;

  /// Selling area in square metres.
  final int area;

  /// Shelf price per product, indexed by [ProductId]; null if not listed.
  final List<Money?> prices;

  /// The first trading day.
  final Day opensOn;

  /// When its owner bought it, if they did.
  final Day? acquiredOn;
}

/// A store's daily sales counts for the days recorded so far, up to
/// [salesHistoryDays].
final class RecentSales {
  RecentSales(this.days, this._counts, [List<List<int>>? traffic])
    : _traffic =
          traffic ?? [for (final _ in DaySlot.values) List.filled(days, 0)];

  /// Days recorded since the store opened, the latest being yesterday.
  final int days;

  /// Indexed by [SalesCount], then product, then day, oldest first.
  final List<List<List<int>>> _counts;

  /// Visits indexed by [DaySlot], then day, oldest first.
  final List<List<int>> _traffic;

  /// Visits per recorded day, all slots together, oldest first.
  List<int> get dailyVisits => [
    for (var day = 0; day < days; day++)
      _traffic.fold(0, (sum, slot) => sum + slot[day]),
  ];

  /// Units sold per recorded day, all products together, oldest first.
  List<int> get dailySold => [
    for (var day = 0; day < days; day++)
      _counts[SalesCount.sold.index].fold(
        0,
        (sum, product) => sum + product[day],
      ),
  ];

  /// Visits in [slot] over the last [lastDays] recorded days, or all of them
  /// if fewer.
  int visits(DaySlot slot, int lastDays) {
    final daily = _traffic[slot.index];
    var sum = 0;
    for (var i = lastDays < days ? days - lastDays : 0; i < days; i++) {
      sum += daily[i];
    }
    return sum;
  }

  /// The total [count] of [product] over the last [lastDays] recorded days,
  /// or all of them if fewer.
  int total(SalesCount count, ProductId product, int lastDays) {
    final daily = _counts[count.index][product.index];
    var sum = 0;
    for (var i = lastDays < days ? days - lastDays : 0; i < days; i++) {
      sum += daily[i];
    }
    return sum;
  }
}

/// Builds [actor]'s observation of [world].
/// What everyone can see of [world] at once: the economy, the censuses,
/// company names, every store's shelf and the vacant sites. Built once and
/// shared by every observation of the same moment.
final class PublicView {
  PublicView(WorldState world, ContentDb content)
    : macro = _macroView(world.macro),
      economies = world.cycle == null
          ? const []
          : List.unmodifiable([
              for (final economy in world.economies) _macroView(economy),
            ]),
      histories = world.cycle == null
          ? const []
          : List.unmodifiable([
              for (final country in content.countries)
                List<EconomicMonth>.unmodifiable(world.historyOf(country.id)),
            ]),
      filings = List.unmodifiable(world.filings),
      history = List.unmodifiable(world.economicHistory),
      households = List.unmodifiable([
        for (final market in world.markets) market.censuses.last.households,
      ]),
      censuses = List.unmodifiable([
        for (final market in world.markets)
          List<Census>.unmodifiable(market.censuses),
      ]),
      companyNames = List.unmodifiable([
        for (final company in world.companies) company.name,
      ]),
      shelves = List.unmodifiable([
        for (final store in world.stores)
          ShelfView(
            id: store.id,
            name: store.name,
            company: store.company,
            site: store.site,
            status: store.status,
            market: store.market,
            location: store.location,
            prices: List.unmodifiable(store.prices),
            openSlots: List.unmodifiable([
              for (final count in store.staff) count > 0,
            ]),
            area: store.area,
            format: store.format,
            opensOn: store.opensOn,
            acquiredOn: store.acquiredOn,
            quality: _shelfQuality(store),
          ),
      ]),
      candidates = _candidates(world, content),
      softwareMarket = softwareMarketViewOf(world, content),
      softwareCandidates = softwareCandidatesOf(world, content),
      vacantSites = _vacantSites(world, content),
      companyOwners = List.unmodifiable([
        for (final company in world.companies) company.owner,
      ]),
      valuations = List.unmodifiable([
        for (final store in world.stores) valueStore(world, content, store),
      ]),
      offers = List.unmodifiable([
        for (final factory in world.factories)
          if (factory.rivalDiscount case final discount?
              when factory.runsOn(world.today) &&
                  world.companies[factory.company.index].isActive)
            (
              id: factory.id,
              kind: factory.kind,
              company: factory.company,
              country: factory.country,
              serves: List<bool>.unmodifiable(factory.serves),
              discount: discount,
              spare: factory.spareFor(
                content.factories!.sized(factory.kind, factory.size),
                world.today,
              ),
            ),
      ]),
      _world = world,
      _content = content {
    companyPrices = List.unmodifiable([
      for (final company in world.companies)
        companyPrice(world, content, company, values: valuations),
    ]);
    companyCredits = List.unmodifiable([
      for (final company in world.companies)
        company.isActive
            ? earningsRoom(world, content, company, values: valuations)
            : null,
    ]);
  }

  final MacroView macro;
  final List<MacroView> economies;
  final List<List<EconomicMonth>> histories;
  final List<int> households;
  final List<List<Census>> censuses;
  final List<String> companyNames;
  final List<ShelfView> shelves;
  final List<SiteId> vacantSites;
  final List<Filing> filings;
  final List<EconomicMonth> history;
  final List<PersonId> companyOwners;
  final List<Valuation?> valuations;
  final List<FactoryOffer> offers;
  final List<KeyPersonView> candidates;
  final SoftwareMarketView? softwareMarket;
  final List<KeyPersonView> softwareCandidates;
  final WorldState _world;
  final ContentDb _content;

  /// The districts run by formula, worked out the first time anyone looks.
  late final List<DistrictView> districts = districtViews(_world, _content);
  late final List<Money?> companyPrices;
  late final List<Money?> companyCredits;

  static MacroView _macroView(MacroState macro) => (
    regime: macro.regime,
    priceIndex: macro.priceIndex,
    wageIndex: macro.wageIndex,
    inflation: macro.inflation,
    policyRate: macro.policyRate,
    unemployment: macro.unemployment,
  );

  static List<SiteId> _vacantSites(WorldState world, ContentDb content) {
    final held = {
      for (final store in world.stores)
        if (store.isTrading) store.site.index,
    };
    return List.unmodifiable([
      for (final site in content.sites)
        if (!held.contains(site.id.index)) site.id,
    ]);
  }
}

/// What [actor] can see of [world], sharing [public] if given: it must be of
/// the same moment.
Observation observe(
  WorldState world,
  ContentDb content,
  PersonId actor, {
  PublicView? public,
}) {
  final person = world.persons[actor.index];
  final shared = public ?? PublicView(world, content);
  // Each of the actor's companies' profit before tax in the year yesterday
  // belonged to, by company index, as the January tax counts it; and each
  // of their stores' last twelve complete months, by store index.
  final taxBase = <int, Money>{};
  final months = <int, StoreMonths>{};
  final year = Day(world.today.number - 1).date.year;
  final yearAgo = world.today.number - 366;
  for (final report in world.periodReports) {
    if (report.period != ReportPeriod.month ||
        world.companies[report.company.index].owner != actor) {
      continue;
    }
    if (content.taxes != null && report.start.date.year == year) {
      taxBase[report.company.index] =
          (taxBase[report.company.index] ?? Money.zero) +
          report.profit +
          report.flow(AccountKind.taxes);
    }
    if (report.start.number < yearAgo ||
        ReportPeriod.month.endOf(report.start) > world.today) {
      continue;
    }
    for (final store in report.stores) {
      final (:revenue, :profit, :days) =
          months[store.store.index] ??
          (revenue: Money.zero, profit: Money.zero, days: 0);
      months[store.store.index] = (
        revenue: revenue + store.totalRevenue,
        profit: profit + store.profit,
        days: days + report.days,
      );
    }
  }
  return Observation(
    brands: [
      for (final brand in world.brands)
        (
          id: brand.id,
          name: brand.name,
          format: brand.format,
          owner: brand.owner,
          shops: world.stores
              .where((store) => store.brand == brand.id && store.isTrading)
              .length,
        ),
    ],
    today: world.today,
    actor: actor,
    cash: person.accounts[AccountKind.cash],
    lastBankruptcy: person.lastBankruptcy,
    macro: shared.macro,
    economies: shared.economies,
    histories: shared.histories,
    households: shared.households,
    censuses: shared.censuses,
    companyNames: shared.companyNames,
    companies: [
      for (final company in world.companies)
        // A holding start's sleeping company was never the player's.
        if (company.owner == actor && company.status != CompanyStatus.dormant)
          CompanyView(
            id: company.id,
            status: company.status,
            founded: company.founded,
            goodsBought: goodsBoughtInYear(company),
            buyingDiscount: buyingDiscount(content, company),
            balances: List.unmodifiable([
              for (final kind in AccountKind.values) company.accounts[kind],
            ]),
            committed: _committed(world, company.id),
            loans: List.unmodifiable([
              for (final loan in world.loans)
                if (loan.company == company.id)
                  (
                    number: loan.number,
                    outstanding: loan.outstanding,
                    rate: loan.rate,
                    installmentsLeft: loan.installmentsLeft,
                    guaranteed: loan.guarantor != null,
                  ),
            ]),
            orders: List.unmodifiable([
              for (final order in world.orders)
                if (world.stores[order.store.index].company == company.id)
                  (
                    number: order.number,
                    store: order.store,
                    supplier: order.supplier,
                    arrival: order.arrival,
                    lines: List<OrderLine>.unmodifiable(order.lines),
                    factory: order.factory,
                  ),
            ]),
            bills: List.unmodifiable([
              for (final payable in company.payables)
                (
                  creditor: payable.creditor,
                  reason: payable.reason,
                  amount: payable.amount,
                  due: payable.due,
                ),
            ]),
            stores: [
              for (final store in world.stores)
                if (store.company == company.id)
                  _storeView(world, content, shared, store, months),
            ],
            factories: [
              for (final factory in world.factories)
                if (factory.company == company.id)
                  _factoryView(world, content, factory),
            ],
            software: switch (softwareOf(world, company.id)) {
              final software? => softwareViewOf(world, content, software),
              null => null,
            },
            lossCarried: company.lossCarried,
            cushionDays: company.cushionDays,
            director: company.director,
            memos: List.unmodifiable(company.memos),
            countryTaxes: world.cycle != null
                ? List.unmodifiable(companyTaxes(world, content, company, year))
                : const [],
            taxAccrued: world.cycle != null
                ? companyTaxes(
                    world,
                    content,
                    company,
                    year,
                  ).fold(Money.zero, (sum, due) => sum + due.tax)
                : switch (content.taxes) {
                    final taxes? => taxes.corporateTax(
                      (taxBase[company.id.index] ?? Money.zero) -
                          company.lossCarried,
                      world.macro.priceIndex,
                    ),
                    null => Money.zero,
                  },
          ),
    ],
    shelves: shared.shelves,
    vacantSites: shared.vacantSites,
    filings: shared.filings,
    history: shared.history,
    companyOwners: shared.companyOwners,
    valuations: shared.valuations,
    companyPrices: shared.companyPrices,
    companyCredits: shared.companyCredits,
    districts: () => shared.districts,
    national: () => nationalViews(world, content, actor),
    stocks: _once(() => stockMarketView(world, content)),
    offers: shared.offers,
    candidates: shared.candidates,
    softwareMarket: shared.softwareMarket,
    softwareCandidates: shared.softwareCandidates,
    tenders: tenderViews(world),
    producers: producerViews(world),
    guaranteeRoom: guaranteeRoom(world, content, person),
    portfolio: actor == world.player
        ? portfolioWorth(world.stocks)
        : Money.zero,
    listedCompanies: [
      for (final stock in world.stocks?.stocks ?? const <Listing>[])
        if (stock.own case final own? when stock.running)
          CompanyId(own.company),
    ],
    reports: List.unmodifiable([
      for (final report in world.reports)
        if (report.buyer == actor) report,
    ]),
  );
}

/// [work], done the first time it is asked for and remembered.
T Function() _once<T>(T Function() work) {
  late final T result = work();
  return () => result;
}

Money _committed(WorldState world, CompanyId company) {
  var total = Money.zero;
  for (final payable in world.companies[company.index].payables) {
    total += payable.amount;
  }
  for (final order in world.orders) {
    if (world.stores[order.store.index].company != company) continue;
    for (final line in order.lines) {
      total += line.unitPrice.timesInt(line.quantity);
    }
  }
  return total;
}

/// A lot on hand: how many days it has been there, its units and what each
/// cost.
typedef LotAge = ({int days, int units, Money unitCost});

/// What each product on [store]'s shelves has kept of its appeal by
/// [today], by [ProductId]; empty if none goes out of fashion.
List<Fx> _shelfFashion(Store store, ContentDb content, Day today) {
  List<Fx>? worth;
  for (final product in content.products) {
    final fashion = content.categories[product.category.index].fashion;
    if (fashion == null) continue;
    final stock = store.stock[product.id.index];
    if (stock.units == 0) continue;
    (worth ??= List.filled(content.products.length, Fx.one))[product.id.index] =
        stock.fashionOn(today, fashion, product.tier);
  }
  return worth == null ? const [] : List.unmodifiable(worth);
}

/// Each product's lots on [store]'s shelves by [today], oldest first, by
/// [ProductId]; empty if none goes out of fashion.
List<List<LotAge>> _shelfLots(Store store, ContentDb content, Day today) {
  List<List<LotAge>>? lots;
  for (final product in content.products) {
    if (content.categories[product.category.index].fashion == null) continue;
    final stock = store.stock[product.id.index];
    if (stock.units == 0) continue;
    (lots ??= List.filled(
      content.products.length,
      const [],
    ))[product.id.index] = List.unmodifiable([
      for (final lot in stock.lots)
        (days: lot.ageOn(today), units: lot.quantity, unitCost: lot.unitCost),
    ]);
  }
  return lots == null ? const [] : List.unmodifiable(lots);
}

/// How far each product on [store]'s shelves is over the market's
/// standard, by [ProductId]; empty if all are at it.
List<Fx> _shelfQuality(Store store) =>
    store.stock.every((stock) => stock.quality == Fx.zero)
    ? const []
    : List.unmodifiable([for (final stock in store.stock) stock.quality]);

List<KeyPersonView> _candidates(WorldState world, ContentDb content) =>
    switch (content.factories?.labs) {
      final labs? => candidateViews(world, labs, forSoftware: false),
      null => const [],
    };

/// The candidates on [def]'s market for key people, for software work or
/// for labs as [forSoftware] says, at its pay in the first country, as
/// everyone sees them: by their repute.
List<KeyPersonView> candidateViews(
  WorldState world,
  TalentDef def, {
  required bool forSoftware,
}) => List.unmodifiable([
  for (final person in world.keyPeople)
    if (person.status == KeyStatus.candidate &&
        person.forSoftware == forSoftware)
      KeyPersonView(
        id: person.id,
        name: person.name,
        role: person.role,
        level: person.repute,
        known: false,
        salary: def.levels[person.repute].salary,
        since: person.since,
        monthsWorked: 0,
        // The market for people turns over on the first.
        leaves: (person.since + def.candidateDays).firstOfMonthOnOrAfter,
      ),
]);

LabView? _labView(WorldState world, ContentDb content, Factory factory) {
  final labs = content.factories?.labs;
  if (labs == null) return null;
  final kind = content.factories!.sized(factory.kind, factory.size);
  final level = labWageLevel(world, content, factory);
  final engineers = labPower(
    world,
    labs,
    factory.id,
    KeyRole.engineer,
    shown: true,
  );
  final designers = labPower(
    world,
    labs,
    factory.id,
    KeyRole.designer,
    shown: true,
  );
  final project = factory.project;
  return LabView(
    budget: factory.labBudget,
    budgetLimit: labBudgetLimit(world, labs, factory),
    project: project,
    work: factory.labWork,
    needed: project == null
        ? null
        : generationWork(
            labs,
            factoryLead(world, factory, project),
            world.macroOf(factory.country).priceIndex,
          ),
    monthlyWork: labMonthlyWork(factory.labBudget, engineers),
    expectedGain: generationGain(labs, designers),
    gainSpread: labs.gainSpread,
    expectedSaving: project == null
        ? null
        : generationSaving(
            labs,
            factorySaving(world, factory, project),
            engineers,
          ),
    engineers: engineers,
    designers: designers,
    wageLevel: level,
    maxPeople: labs.maxPeople,
    lines: List.unmodifiable([
      for (final product in content.products)
        if (kindMakes(kind, product))
          (
            product: product.id,
            generation: factory.lineOf(product.id)?.generation ?? 0,
            lead: factoryLead(world, factory, product.id),
            saving: factorySaving(world, factory, product.id),
            launchedOn: factory.lineOf(product.id)?.launchedOn,
            history: List<Fx>.unmodifiable(
              factory.lineOf(product.id)?.history ?? const <Fx>[],
            ),
          ),
    ]),
    people: List.unmodifiable([
      for (final person in labPeople(world, factory.id))
        KeyPersonView(
          id: person.id,
          name: person.name,
          role: person.role,
          level: person.shownLevel(labs.revealMonths),
          known: person.knownAfter(labs.revealMonths),
          salary: keySalary(labs, person, level),
          since: person.since,
          monthsWorked: person.monthsWorked,
        ),
    ]),
  );
}

FactoryView _factoryView(WorldState world, ContentDb content, Factory factory) {
  final kind = content.factories!.sized(factory.kind, factory.size);
  final economy = world.macroOf(factory.country);
  final today = world.today;
  final yesterday = Day(today.number - 1);
  final made = factory.month == monthOf(today) ? factory.madeThisMonth : 0;
  return FactoryView(
    id: factory.id,
    kind: factory.kind,
    company: factory.company,
    country: factory.country,
    name: factory.name,
    opensOn: factory.opensOn,
    builtFor: factory.builtFor,
    shifts: factory.shifts,
    serves: List.unmodifiable(factory.serves),
    rivalDiscount: factory.rivalDiscount,
    status: factory.status,
    making:
        factory.runsOn(today) &&
        world.companies[factory.company.index].isActive,
    monthCapacity: factory.monthCapacity(kind, today),
    madeThisMonth: made,
    capacityLeft: factory.capacityLeft(kind, today),
    spare: factory.spareFor(kind, today),
    recentOwnUnits: factory.recentOwnUnits(yesterday),
    recentRivalUnits: factory.recentRivalUnits(yesterday),
    recentMargin: factory.recentMargin(yesterday),
    earnings: factoryEarnings(world, content, factory),
    dailyWages: kind.shiftWage
        .times(economy.wageIndex)
        .times(content.countries[factory.country.index].service)
        .timesInt(factory.shifts),
    monthlySite: kind.site.times(economy.priceIndex),
    value: valueFactory(world, content, factory),
    lab: _labView(world, content, factory),
    size: factory.size,
    sales: factorySalesView(world, content, factory),
  );
}

StoreView _storeView(
  WorldState world,
  ContentDb content,
  PublicView public,
  Store store,
  Map<int, StoreMonths> months,
) {
  final days = world.today.number - store.opensOn.number;
  final recorded = days < 0
      ? 0
      : (days < salesHistoryDays ? days : salesHistoryDays);
  final products = store.prices.length;
  final onOrder = List.filled(products, 0);
  for (final order in world.orders.where((order) => order.store == store.id)) {
    for (final line in order.lines) {
      onOrder[line.product.index] += line.quantity;
    }
  }
  final yesterday = world.today.number - 1;
  return StoreView(
    id: store.id,
    site: store.site,
    status: store.status,
    opensOn: store.opensOn,
    market: store.market,
    shelfSlots: store.shelfSlots,
    storageUnits: store.storageUnits,
    prices: List.unmodifiable(store.prices),
    stock: List.unmodifiable([for (final stock in store.stock) stock.units]),
    onOrder: List.unmodifiable(onOrder),
    staff: List.unmodifiable(store.staff),
    service: List.unmodifiable(store.service),
    area: store.area,
    format: store.format,
    marketingShare: store.marketingShare,
    goodwill: store.goodwill,
    reputation: store.reputation,
    works: store.works,
    enlargedOn: store.enlargedOn,
    boughtFor: store.boughtFor,
    acquiredOn: store.acquiredOn,
    quality: _shelfQuality(store),
    fashion: _shelfFashion(store, content, world.today),
    lots: _shelfLots(store, content, world.today),
    recentMonths:
        months[store.id.index] ??
        (revenue: Money.zero, profit: Money.zero, days: 0),
    buyer: switch (public.valuations[store.id.index]) {
      final value? => bestBuyer(world, content, store, value.price)?.id,
      null => null,
    },
    manager: switch (store.manager) {
      final manager? => (
        grade: manager.grade,
        strategy: manager.strategy,
        duties: manager.duties,
        hiredOn: manager.hiredOn,
      ),
      null => null,
    },
    sales: RecentSales(
      recorded,
      [
        for (final count in SalesCount.values)
          [
            for (var product = 0; product < products; product++)
              [
                for (var ago = recorded - 1; ago >= 0; ago--)
                  store.history.at(
                    count,
                    ProductId(product),
                    Day(yesterday - ago),
                  ),
              ],
          ],
      ],
      [
        for (final slot in DaySlot.values)
          [
            for (var ago = recorded - 1; ago >= 0; ago--)
              store.history.visitsAt(slot.index, Day(yesterday - ago)),
          ],
      ],
    ),
  );
}
