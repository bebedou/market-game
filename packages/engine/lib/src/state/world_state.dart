import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../countries/country_economy.dart';
import '../persistence/state_io.dart';
import '../reports/period_report.dart';
import 'cohort.dart';
import 'entities.dart';
import 'factory.dart';
import 'game_start.dart';
import 'history.dart';
import 'macro.dart';
import 'market.dart';
import 'public_record.dart';
import 'orders.dart';
import 'research.dart';
import 'brands.dart';
import 'sleepers.dart';
import 'store.dart';
import 'taxation.dart';

/// All mutable truth about the world. Only commands and tick systems change
/// it, and nothing outside the engine reads it.
final class WorldState {
  WorldState._({
    required this.seed,
    required this.today,
    required this.player,
    required this.moneySupply,
    required this.nextOrderNumber,
    required this.nextLoanNumber,
    required this.nextReportNumber,
    required this.macro,
    required this.persons,
    required this.companies,
    required this.stores,
    required this.suppliers,
    required this.households,
    required this.bank,
    required this.landlords,
    required this.services,
    required this.cohorts,
    required this.orders,
    required this.loans,
    required this.reports,
    required this.periodReports,
    required this.markets,
    required this.government,
    required this.filings,
    required this.economicHistory,
    this.start,
  });

  /// The neighbourhoods run by formula, not yet woken. Saved beside the world
  /// and not in it, as nothing in the world depends on them.
  final sleepers = <SleepingNeighbourhood>[];

  /// The brands shops trade under, by [BrandId].
  final brands = <Brand>[];

  /// Every factory ever built, by [FactoryId]; closed ones stay.
  final factories = <Factory>[];

  /// The countries by formula, region by region, with companies' shops run
  /// there; null until first run, and for a world of one country or without
  /// a national table. Saved beside the world.
  CountryEconomy? national;

  /// The start of the latest month of shops run by formula across countries
  /// already in their companies' books.
  Day? nationalPosted;

  /// The economies of the countries after the first, in order: the first's
  /// is [macro]. Saved beside the world, as a world of one country has none.
  final otherEconomies = <Economy>[];

  /// The cycle its countries share; null with one country.
  SharedCycle? cycle;

  /// Chains' shops in districts by company, country and year, this year's
  /// and last, for each country's tax; kept only with several countries.
  final districtYears = <DistrictYear>[];

  /// Losses companies carry in countries after the first.
  final countryLosses = <CountryLoss>[];

  /// Each month since the start, the regime each country was in, by
  /// [CountryId], then the shared cycle's: what the national view replays.
  final regimeLog = <List<int>>[];

  /// [country]'s economy.
  MacroState macroOf(CountryId country) =>
      country.index == 0 ? macro : otherEconomies[country.index - 1].macro;

  /// The economy of the country [market] is in.
  MacroState macroAt(ContentDb content, MarketId market) =>
      macroOf(content.countryOf(market));

  /// [country]'s economy month by month, oldest first.
  List<EconomicMonth> historyOf(CountryId country) => country.index == 0
      ? economicHistory
      : otherEconomies[country.index - 1].history;

  /// Every country's economy, by [CountryId].
  List<MacroState> get economies => [
    macro,
    for (final economy in otherEconomies) economy.macro,
  ];

  /// Where [person] lives: as the scenario has it, but the player lives
  /// where the game's start put their first store.
  CountryId residence(ContentDb content, PersonId person) => switch (start) {
    GameStart(:final site?) when person == player => content.countryOf(
      content.sites[site.index].market,
    ),
    // A holding lives where its first business opened.
    GameStart(holding: true) when person == player => switch (stores
        .where((store) => companies[store.company.index].owner == person)
        .firstOrNull) {
      final first? => content.countryOf(content.sites[first.site.index].market),
      null => content.residenceOf(person),
    },
    _ => content.residenceOf(person),
  };

  /// Adds an economy for each of [content]'s countries the world lacks, as
  /// the first country's stands, and the shared cycle once there are two.
  void growEconomies(ContentDb content) {
    while (otherEconomies.length < content.countries.length - 1) {
      otherEconomies.add(Economy(macro: MacroState.copyOf(macro), history: []));
    }
    if (content.countries.length > 1) {
      cycle ??= SharedCycle(
        regime: macro.regime,
        monthsInRegime: macro.monthsInRegime,
      );
    }
  }

  /// What the world keeps beside itself of its countries' economies: in saves
  /// and in the state hash, but nothing at all for a world of one country.
  void writeEconomies(StateWriter writer) {
    writer.writeInt(otherEconomies.length);
    for (final economy in otherEconomies) {
      economy.write(writer);
    }
    writer.writeBool(cycle != null);
    cycle?.write(writer);
    writer.writeInt(districtYears.length);
    for (final entry in districtYears) {
      entry.write(writer);
    }
    writer.writeInt(countryLosses.length);
    for (final loss in countryLosses) {
      loss.write(writer);
    }
    writer.writeInt(regimeLog.length);
    for (final month in regimeLog) {
      writer.writeInt(month.length);
      month.forEach(writer.writeInt);
    }
  }

  void readEconomies(StateReader reader) {
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      otherEconomies.add(Economy.read(reader));
    }
    if (reader.readBool()) cycle = SharedCycle.read(reader);
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      districtYears.add(DistrictYear.read(reader));
    }
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      countryLosses.add(CountryLoss.read(reader));
    }
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      regimeLog.add([
        for (var c = 0, m = reader.readInt(); c < m; c++) reader.readInt(),
      ]);
    }
  }

  /// Everyone beyond the districts played in full.
  Elsewhere elsewhere = Elsewhere(accounts: Accounts());

  /// The world at the scenario's start date, the player's first store where
  /// and as [start] chose if given, or none for a holding start, the
  /// scenario's company for them left [CompanyStatus.dormant]. Opening cash
  /// is the only money ever created; from then on it only changes hands.
  factory WorldState.initial(
    ContentDb content, {
    required int seed,
    GameStart? start,
  }) {
    StartTerms? terms;
    final setup = start == null ? null : playerSetup(content);
    if (start != null) {
      final (chosen, problem) = startTerms(content, start);
      if (chosen == null) throw ArgumentError.value(start, 'start', problem);
      terms = chosen;
    }
    final personCash = [
      for (final (i, person) in content.persons.indexed)
        terms != null && i == content.player.index
            ? terms.personalCash
            : person.cash,
    ];
    final companyCash = [
      for (final (i, company) in content.companies.indexed)
        terms != null && i == setup!.company ? terms.companyCash : company.cash,
    ];
    final openingCash = [
      ...personCash,
      ...companyCash,
      content.finance.bankReserves,
    ];
    final cohorts = <HouseholdCohort>[];
    for (final market in content.markets) {
      cohorts.addAll(
        newCohorts(content, seed, market, cohorts.length, content.startDay),
      );
    }
    final world = WorldState._(
      seed: seed,
      today: content.startDay,
      player: content.player,
      moneySupply: openingCash.fold(Money.zero, (sum, cash) => sum + cash),
      nextOrderNumber: 1,
      nextLoanNumber: 1,
      nextReportNumber: 1,
      macro: MacroState.initial(content.macro),
      persons: [
        for (final (i, person) in content.persons.indexed)
          Person(
            id: PersonId(i),
            name: person.name,
            accounts: Accounts.opening(
              personCash[i],
              investments: terms != null && i == content.player.index
                  ? terms.capital
                  : Money.zero,
            ),
          ),
      ],
      companies: [
        for (final (i, company) in content.companies.indexed)
          Company(
            id: CompanyId(i),
            name: start != null && i == setup!.company
                ? start.name
                : company.name,
            owner: company.owner,
            accounts: Accounts.opening(companyCash[i]),
            founded: content.startDay,
            injected: terms != null && i == setup!.company
                ? terms.capital
                : Money.zero,
            status: start != null && start.holding && i == setup!.company
                ? CompanyStatus.dormant
                : CompanyStatus.active,
          ),
      ],
      stores: [],
      suppliers: [
        for (final supplier in content.suppliers)
          Supplier(id: supplier.id, accounts: Accounts()),
      ],
      households: [
        for (final market in content.markets)
          Households(market: market.id, accounts: Accounts()),
      ],
      bank: Bank(accounts: Accounts.opening(content.finance.bankReserves)),
      landlords: Landlords(accounts: Accounts()),
      services: Services(accounts: Accounts()),
      government: Government(accounts: Accounts()),
      filings: [],
      economicHistory: [],
      cohorts: cohorts,
      orders: [],
      loans: [],
      reports: [],
      periodReports: [],
      markets: [
        for (final market in content.markets)
          MarketState.initial(
            market.id,
            content.startDay,
            market.households.fold(0, (sum, count) => sum + count),
          ),
      ],
      start: start,
    )..growEconomies(content);
    for (final (i, store) in content.stores.indexed) {
      if (start != null && i == setup!.store) {
        final (chosen, format) = (start.site, start.format);
        // A holding start opens no store.
        if (chosen == null || format == null) continue;
        final site = content.sites[chosen.index];
        final shop = startingShop(
          content,
          format,
          site.market,
          shelfSlots: site.shelfSlots + content.formats[format.index].slotBonus,
        );
        world.addStore(
          content,
          name: start.name,
          company: store.company,
          site: site,
          prices: shop.prices,
          staff: shop.staff,
          opensOn: content.startDay,
          format: format,
        );
        continue;
      }
      final added = world.addStore(
        content,
        name: store.name,
        company: store.company,
        site: content.sites[store.site.index],
        prices: store.prices,
        staff: store.staff,
        opensOn: content.startDay,
        format: store.format,
        area: store.area,
      );
      // The player's business is new; the others have traded for years.
      if (content.companies[store.company.index].owner != content.player) {
        added.reputation = content.demand.establishedReputation;
      }
    }
    return world;
  }

  factory WorldState.read(StateReader reader) {
    final seed = reader.readInt();
    final world = WorldState._(
      seed: seed,
      today: Day(reader.readInt()),
      player: PersonId(reader.readInt()),
      moneySupply: Money(reader.readInt()),
      nextOrderNumber: reader.readInt(),
      nextLoanNumber: reader.readInt(),
      nextReportNumber: reader.readInt(),
      macro: MacroState.read(reader),
      persons: _readList(reader, (i) => Person.read(PersonId(i), reader)),
      companies: _readList(reader, (i) => Company.read(CompanyId(i), reader)),
      stores: _readList(reader, (i) => Store.read(StoreId(i), reader)),
      suppliers: _readList(reader, (i) => Supplier.read(SupplierId(i), reader)),
      households: _readList(
        reader,
        (i) => Households.read(MarketId(i), reader),
      ),
      bank: Bank.read(reader),
      landlords: Landlords.read(reader),
      services: Services.read(reader),
      cohorts: _readList(
        reader,
        (i) => HouseholdCohort.read(
          CohortId(i),
          reader,
          incomeRank: HouseholdCohort.rankFor(seed, CohortId(i)),
        ),
      ),
      orders: _readList(reader, (_) => PurchaseOrder.read(reader)),
      loans: _readList(reader, (_) => Loan.read(reader)),
      reports: _readList(reader, (_) => ResearchReport.read(reader)),
      periodReports: _readList(reader, (_) => PeriodReport.read(reader)),
      markets: reader.version >= 7
          ? _readList(reader, (i) => MarketState.read(MarketId(i), reader))
          : [],
      government: reader.version >= 12
          ? Government.read(reader)
          : Government(accounts: Accounts()),
      filings: reader.version >= 12
          ? _readList(reader, (_) => readFiling(reader))
          : [],
      economicHistory: reader.version >= 12
          ? _readList(reader, (_) => readEconomicMonth(reader))
          : [],
      start: reader.version >= 13 && reader.readBool()
          ? GameStart.read(reader)
          : null,
    );
    // A save from before population change: each market is counted on the
    // save's day.
    if (world.markets.isEmpty) {
      for (final party in world.households) {
        world.markets.add(
          MarketState.initial(
            party.market,
            world.today,
            world.cohorts
                .where((cohort) => cohort.market == party.market)
                .fold(0, (sum, cohort) => sum + cohort.weight),
          ),
        );
      }
    }
    if (reader.version >= 25) {
      world.brands.addAll(
        _readList(reader, (i) => Brand.read(BrandId(i), reader)),
      );
    }
    if (reader.version >= 26) world.elsewhere = Elsewhere.read(reader);
    if (reader.version >= factoriesVersion) {
      world.factories.addAll(
        _readList(reader, (i) => Factory.read(FactoryId(i), reader)),
      );
    }
    return world;
  }

  /// Every random draw is keyed from this seed.
  final int seed;

  /// How the player chose to start, if they did: replays start the same way.
  final GameStart? start;

  /// The day the next step will simulate.
  Day today;

  final PersonId player;

  /// The total cash held by all parties. Only opening cash, at the start or
  /// when the scenario grows, ever changes it.
  Money moneySupply;

  int nextOrderNumber;
  int nextLoanNumber;
  int nextReportNumber;
  final MacroState macro;

  final List<Person> persons;

  /// Every company ever founded, liquidated ones included.
  final List<Company> companies;

  /// Every store ever opened, closed ones included.
  final List<Store> stores;

  /// Indexed by [SupplierId].
  final List<Supplier> suppliers;

  /// Indexed by [MarketId].
  final List<Households> households;
  final Bank bank;
  final Landlords landlords;
  final Services services;

  /// Every household cohort, grouped by market, then segment.
  final List<HouseholdCohort> cohorts;

  /// Purchase orders not yet delivered, in the order they were placed.
  final List<PurchaseOrder> orders;

  /// Loans with principal not yet billed, in the order they were taken.
  final List<Loan> loans;

  /// Every market study bought, in order.
  final List<ResearchReport> reports;

  /// Each company's recent week and month reports, in the order they were
  /// opened.
  final List<PeriodReport> periodReports;

  /// Population change and censuses, indexed by [MarketId].
  final List<MarketState> markets;

  /// The state's books.
  final Government government;

  /// Every company's yearly accounts, oldest first, for the last
  /// [filingYearsKept] years.
  final List<Filing> filings;

  /// The economy month by month, oldest first.
  final List<EconomicMonth> economicHistory;

  /// Every party with books.
  Iterable<LedgerParty> get parties => [
    ...persons,
    ...companies,
    ...suppliers,
    ...households,
    bank,
    landlords,
    services,
    government,
    elsewhere,
  ];

  LedgerParty party(PartyRef ref) => switch (ref.type) {
    PartyType.person => persons[ref.index],
    PartyType.company => companies[ref.index],
    PartyType.supplier => suppliers[ref.index],
    PartyType.households => households[ref.index],
    PartyType.bank => bank,
    PartyType.landlords => landlords,
    PartyType.services => services,
    PartyType.government => government,
    PartyType.elsewhere => elsewhere,
  };

  /// The store trading at [site], if any.
  Store? storeAt(SiteId site) {
    for (final store in stores) {
      if (store.site == site && store.isTrading) return store;
    }
    return null;
  }

  /// A new company of [owner]'s, with [cash] it starts with out of nowhere:
  /// only a scenario's opening companies do.
  Company addCompany(String name, PersonId owner, {Money cash = Money.zero}) {
    final company = Company(
      id: CompanyId(companies.length),
      name: name,
      owner: owner,
      accounts: Accounts.opening(cash),
      founded: today,
    );
    moneySupply += cash;
    companies.add(company);
    return company;
  }

  /// Puts a store on [site], trading from [opensOn]. Households start with
  /// neutral loyalty toward it and know its prices.
  Store addStore(
    ContentDb content, {
    required String name,
    required CompanyId company,
    required SiteDef site,
    required List<Money?> prices,
    required List<int> staff,
    required Day opensOn,
    FormatId format = const FormatId(0),
    int? area,
  }) {
    // Each round of works already done adds what it would have.
    final expansion = content.expansion;
    final rounds = area == null ? 0 : (area - site.area) ~/ expansion.stepArea;
    final store = Store(
      id: StoreId(stores.length),
      name: name,
      company: company,
      format: format,
      site: site.id,
      status: opensOn > today ? StoreStatus.building : StoreStatus.open,
      opensOn: opensOn,
      market: site.market,
      location: site.location,
      shelfSlots:
          site.shelfSlots +
          content.formats[format.index].slotBonus +
          rounds * expansion.shelfSlots,
      storageUnits:
          site.storageUnits +
          content.formats[format.index].storageBonus +
          rounds * expansion.storageUnits,
      area: area ?? site.area,
      prices: List.of(prices),
      stock: [for (final _ in content.products) Stock()],
      history: SalesHistory(content.products.length),
      staff: List.of(staff),
      service: List.filled(DaySlot.values.length, Fx.one),
      traffic: List.filled(DaySlot.values.length, 0),
      reputation: content.demand.openingReputation,
    );
    stores.add(store);
    final priceIndex = [
      for (final segment in content.segments)
        segment.priceIndex(
              content.products,
              prices,
              priceLevel:
                  macroAt(content, site.market).priceIndex *
                  content.markets[site.market.index].priceLevel,
              references:
                  content.references[content.countryOf(site.market).index],
            ) ??
            Fx.one,
    ];
    for (final cohort in cohorts) {
      cohort.loyalty.add(content.demand.neutralLoyalty);
      cohort.perceivedPrices.add(priceIndex[cohort.segment.index]);
    }
    return store;
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(seed)
      ..writeInt(today.number)
      ..writeInt(player.index)
      ..writeInt(moneySupply.cents)
      ..writeInt(nextOrderNumber)
      ..writeInt(nextLoanNumber)
      ..writeInt(nextReportNumber);
    macro.write(writer);
    _writeList(writer, persons, (person) => person.write(writer));
    _writeList(writer, companies, (company) => company.write(writer));
    _writeList(writer, stores, (store) => store.write(writer));
    _writeList(writer, suppliers, (supplier) => supplier.write(writer));
    _writeList(writer, households, (party) => party.write(writer));
    bank.write(writer);
    landlords.write(writer);
    services.write(writer);
    _writeList(writer, cohorts, (cohort) => cohort.write(writer));
    _writeList(writer, orders, (order) => order.write(writer));
    _writeList(writer, loans, (loan) => loan.write(writer));
    _writeList(writer, reports, (report) => report.write(writer));
    _writeList(writer, periodReports, (report) => report.write(writer));
    _writeList(writer, markets, (market) => market.write(writer));
    government.write(writer);
    _writeList(writer, filings, (filing) => writeFiling(writer, filing));
    _writeList(
      writer,
      economicHistory,
      (month) => writeEconomicMonth(writer, month),
    );
    writer.writeBool(start != null);
    start?.write(writer);
    _writeList(writer, brands, (brand) => brand.write(writer));
    elsewhere.write(writer);
    _writeList(writer, factories, (factory) => factory.write(writer));
  }
}

List<T> _readList<T>(StateReader reader, T Function(int index) read) => [
  for (var i = 0, n = reader.readInt(); i < n; i++) read(i),
];

void _writeList<T>(
  StateWriter writer,
  List<T> items,
  void Function(T item) write,
) {
  writer.writeInt(items.length);
  items.forEach(write);
}

/// The cohorts of [market], numbered from [firstId], drawn for [day]: each
/// segment, or each of [only], gets its share of the market's cohorts, at
/// least one, and its households spread over them as evenly as can be. Each
/// cohort's home, preferred slot and starting needs come from the `homes`
/// stream for the day and its ID: what the segment buys rarely starts part
/// of the way to a unit, so households don't all run out together. Its
/// loyalty and believed prices are for the stores to add.
List<HouseholdCohort> newCohorts(
  ContentDb content,
  int seed,
  MarketDef market,
  int firstId,
  Day day, {
  Iterable<SegmentDef>? only,
}) {
  final cohorts = <HouseholdCohort>[];
  final total = market.households.fold(0, (sum, count) => sum + count);
  for (final segment in only ?? content.segments) {
    final households = market.households[segment.id.index];
    var agents = households;
    if (market.agents case final limit? when households > 0) {
      agents = households * limit ~/ total;
      if (agents < 1) agents = 1;
      if (agents > households) agents = households;
    }
    for (var i = 0; i < agents; i++) {
      final id = firstId + cohorts.length;
      final homes = Rng.keyed(seed, RngStream.homes, day.number, id);
      final proximity = [for (final _ in content.sites) homes.nextFx()];
      var draw = homes.nextFx();
      var slot = 0;
      while (slot < DaySlot.values.length - 1 &&
          draw >= segment.slotShares[slot]) {
        draw -= segment.slotShares[slot++];
      }
      cohorts.add(
        HouseholdCohort(
          id: CohortId(id),
          market: market.id,
          segment: segment.id,
          preferredSlot: slot,
          needs: [
            for (final category in content.categories)
              if (segment.buysRarely(category.id, content.demand))
                homes.nextFx()
              else
                Fx.zero,
          ],
          loyalty: [],
          perceivedPrices: [],
          proximity: proximity,
          incomeRank: HouseholdCohort.rankFor(seed, CohortId(id)),
          weight: households ~/ agents + (i < households % agents ? 1 : 0),
        ),
      );
    }
  }
  return cohorts;
}
