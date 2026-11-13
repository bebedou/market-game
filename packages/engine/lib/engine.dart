/// Deterministic economic simulation engine for Market Game.
library;

export 'src/accounting/ledger.dart'
    show AccountKind, EntryReason, JournalEntry, PartyRef, PartyType;
export 'src/commands/apply_command.dart'
    show
        conversionCost,
        maxMarketingShare,
        maxNameLength,
        maxNationalOpenings,
        maxNationalPace,
        maxRivalDiscount;
export 'src/commands/command.dart'
    show
        BuildFactory,
        BuyCompany,
        BuyStore,
        CloseFactory,
        CloseStore,
        Command,
        ConvertStore,
        BuyInDistrict,
        CreateBrand,
        DelistProduct,
        ExpandStore,
        FireDirector,
        FireManager,
        HireDirector,
        HireManager,
        InjectCapital,
        ListProduct,
        LoggedCommand,
        OpenInDistrict,
        OpenNational,
        OpenStore,
        OrderFromFactory,
        OrderQuantity,
        PayDividend,
        PlaceOrder,
        BuyResearch,
        RenameCompany,
        RenameStore,
        RepayLoan,
        SellStore,
        SetCushion,
        SetFactoryShifts,
        SetFactoryTerms,
        SetMarketing,
        SetPrice,
        SetStaffing,
        WakeNeighbourhood,
        TakeLoan;
export 'src/commands/refusal.dart' show Refusal;
export 'src/content/content_db.dart';
export 'src/content/scenario_loader.dart' show ContentException, loadScenario;
export 'src/countries/country_economy.dart'
    show
        BlockMonth,
        Chain,
        ChainMonth,
        CompanyBlock,
        CountryEconomy,
        CountryState,
        ShopCosts,
        TradeMonth,
        youngMonths;
export 'src/countries/country_table.dart'
    show
        ChainDef,
        CountryTable,
        NationalCountry,
        NationalRegion,
        RegionalTuning,
        loadCountryTable;
export 'src/countries/shop_bridge.dart' show formatTrades;
export 'src/core/calendar.dart' show CivilDate, Day;
export 'src/core/fx.dart' show Fx;
export 'src/core/ids.dart';
export 'src/core/money.dart' show Money;
export 'src/observation/observation.dart'
    show
        CompanyView,
        BillView,
        FactoryOffer,
        FactoryView,
        LoanView,
        MacroView,
        ManagerView,
        Observation,
        OrderView,
        RecentSales,
        StoreMonths,
        ShelfView,
        StoreView;
export 'src/observation/factory_outlook.dart'
    show FactoryOutlook, FactoryShiftPlan, factoryOutlook, outlookServes;
export 'src/observation/national_view.dart'
    show
        BlockRegionView,
        CompanyBlockView,
        NationalChainView,
        NationalCountryView;
export 'src/observation/outlook.dart'
    show
        ShopOutlook,
        channelSpending,
        marketSpending,
        shopOutlook,
        tradeSpending;
export 'src/persistence/save_file.dart' show SaveFile;
export 'src/policies/cushion.dart'
    show
        cashCushion,
        cashForEssentials,
        directorSalary,
        nextInstallment,
        storeCushion;
export 'src/policies/director.dart'
    show buyoutPaybackMonths, directorManagerDuties, nationalPaybackMonths;
export 'src/policies/entrepreneur_policy.dart' show EntrepreneurPolicy;
export 'src/policies/policy.dart'
    show CombinedPolicy, Policy, ownerPolicy, standardPolicies;
export 'src/policies/retail_policy.dart' show RetailPolicy;
export 'src/reports/attribution.dart'
    show Attribution, ItemMiss, MissReason, StoreSwitch, SwitchCause;
export 'src/reports/period_report.dart'
    show FactoryReport, PeriodReport, ReportPeriod, StoreReport, SwitchKey;
export 'src/simulation.dart' show CommandRejection, Simulation, TickResult;
export 'src/state/credit.dart' show lendingRate, splitLoan;
export 'src/state/director.dart';
export 'src/state/entities.dart'
    show CompanyStatus, defaultCushionDays, maxCushionDays;
export 'src/state/factories.dart'
    show factoryLeadTime, factoryPrice, marketQuote, materialsCost;
export 'src/state/factory.dart' show FactoryStatus, factoryHistoryDays;
export 'src/state/game_start.dart'
    show GameStart, StartTerms, minStartingCash, startTerms, startingSites;
export 'src/state/history.dart' show SalesCount, salesHistoryDays;
export 'src/state/market.dart' show Census;
export 'src/state/orders.dart' show OrderLine;
export 'src/state/public_record.dart' show EconomicMonth, Filing;
export 'src/state/brands.dart' show BrandView;
export 'src/state/districts.dart' show DistrictShop, DistrictSite, DistrictView;
export 'src/state/research.dart' show ResearchReport, SegmentEstimate;
export 'src/state/sleepers.dart' show SleepingNeighbourhood, SleepingShop;
export 'src/state/store.dart' show ManagerDuty, StoreStatus, Works;
export 'src/state/taxation.dart' show CountryTax;
export 'src/state/valuation.dart' show Valuation, symbolicPrice;
export 'src/systems/events.dart';
