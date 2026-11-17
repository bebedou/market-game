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
        maxNationalRate,
        maxRivalDiscount,
        maxBidTimes,
        maxSoftwareMarketing,
        maxSoftwarePriceTimes;
export 'src/commands/command.dart'
    show
        AcceptNationalOffer,
        AcceptSoftwareOffer,
        AnswerBid,
        AnswerContract,
        AskPrice,
        BidForCompany,
        BidTender,
        BreakContract,
        BuyRival,
        BuildFactory,
        BuyCompany,
        BuyShares,
        BuyStore,
        CloseFactory,
        CloseStore,
        Command,
        ListCompany,
        RunListed,
        SellControlled,
        SellShares,
        ConvertStore,
        BuyInDistrict,
        CreateBrand,
        BuyNationalChain,
        DeclineNationalOffer,
        DeclineSoftwareOffer,
        DelistProduct,
        ClearStock,
        DismissKeyPerson,
        EnlargeFactory,
        ExpandStore,
        FireDirector,
        FireManager,
        HireDirector,
        HireKeyPerson,
        HireManager,
        HireSoftwarePerson,
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
        RaiseRound,
        RenameCompany,
        RenameStore,
        RepayLoan,
        SellNational,
        SellStore,
        SetCushion,
        SetFactoryShifts,
        SetFactoryTerms,
        SetLab,
        SetMarketing,
        SetPrice,
        SetSoftwareMarketing,
        SetSoftwarePrice,
        SetStaffing,
        ShutDownSoftware,
        StartSoftware,
        WakeNeighbourhood,
        TakeLoan;
export 'src/commands/refusal.dart' show Refusal;
export 'src/commands/stock_trades.dart' show orderFee, orderImpact, orderValue;
export 'src/content/content_db.dart';
export 'src/content/stocks_def.dart';
export 'src/content/scenario_loader.dart' show ContentException, loadScenario;
export 'src/countries/country_economy.dart'
    show
        BlockMonth,
        NationalOffer,
        maxNationalMarketing,
        strainCost,
        strainFactor,
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
        BrandTuning,
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
        KeyPersonView,
        LabView,
        LotAge,
        LineView,
        LoanView,
        MacroView,
        ManagerView,
        Observation,
        OrderView,
        RecentSales,
        StoreMonths,
        ShelfView,
        StoreView;
export 'src/observation/factory_sales_view.dart'
    show ContractView, FactorySalesView, ProducerView, SalesLine, TenderView;
export 'src/observation/software_view.dart'
    show RivalView, SoftwareMarketView, SoftwareOfferView, SoftwareView;
export 'src/observation/factory_outlook.dart'
    show FactoryOutlook, FactoryShiftPlan, factoryOutlook, outlookServes;
export 'src/observation/national_view.dart'
    show
        BlockRegionView,
        CompanyBlockView,
        NationalChainView,
        NationalCountryView,
        NationalOfferView;
export 'src/state/buying_terms.dart'
    show buyingDiscount, buyingDiscountAt, goodsBoughtInYear;
export 'src/state/national_value.dart' show NationalValue;
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
export 'src/policies/candidates.dart'
    show DirectorCandidate, directorShortlist, personOf;
export 'src/policies/director.dart'
    show
        buyoutPaybackMonths,
        directorManagerDuties,
        nationalBudget,
        nationalChainShops,
        nationalGrowthRate,
        nationalPaybackMonths,
        scaledMonths;
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
export 'src/state/labs.dart'
    show generationGain, generationSaving, generationWork, labMonthlyWork;
export 'src/state/factory_sales.dart' show TenderStatus;
export 'src/state/software.dart'
    show FundingRound, RivalStatus, SoftwareMonth, SoftwareStatus;
export 'src/state/software_rules.dart' show SoftwareWorth, roundMoney;
export 'src/state/talent.dart' show KeyRole;
export 'src/state/taxation.dart' show CountryTax;
export 'src/state/valuation.dart' show Valuation, symbolicPrice;
export 'src/observation/stocks_view.dart'
    show
        AnalystRating,
        BidView,
        ExchangeView,
        HolderView,
        HoldingView,
        RaiderView,
        ShareLoanView,
        StockMarketView,
        StockView;
export 'src/state/stocks.dart'
    show BidStatus, holdingOwner, isPlayers, isRaider, raiderOf, raiderOwner;
export 'src/systems/events.dart';
export 'src/systems/takeovers.dart' show freeFloatAccepting;
export 'src/systems/national.dart' show offerDays;
