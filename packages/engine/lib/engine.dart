/// Deterministic economic simulation engine for Market Game.
library;

export 'src/accounting/ledger.dart'
    show AccountKind, EntryReason, JournalEntry, PartyRef, PartyType;
export 'src/commands/apply_command.dart'
    show conversionCost, maxMarketingShare, maxNameLength;
export 'src/commands/command.dart'
    show
        BuyCompany,
        BuyStore,
        CloseStore,
        Command,
        ConvertStore,
        DelistProduct,
        ExpandStore,
        FireDirector,
        FireManager,
        HireDirector,
        HireManager,
        InjectCapital,
        ListProduct,
        LoggedCommand,
        OpenStore,
        OrderQuantity,
        PayDividend,
        PlaceOrder,
        BuyResearch,
        RenameCompany,
        RenameStore,
        RepayLoan,
        SellStore,
        SetCushion,
        SetMarketing,
        SetPrice,
        SetStaffing,
        TakeLoan;
export 'src/commands/refusal.dart' show Refusal;
export 'src/content/content_db.dart';
export 'src/content/scenario_loader.dart' show ContentException, loadScenario;
export 'src/core/calendar.dart' show CivilDate, Day;
export 'src/core/fx.dart' show Fx;
export 'src/core/ids.dart';
export 'src/core/money.dart' show Money;
export 'src/observation/observation.dart'
    show
        CompanyView,
        BillView,
        LoanView,
        MacroView,
        ManagerView,
        Observation,
        OrderView,
        RecentSales,
        StoreMonths,
        ShelfView,
        StoreView;
export 'src/persistence/save_file.dart' show SaveFile;
export 'src/policies/cushion.dart'
    show
        cashCushion,
        cashForEssentials,
        directorSalary,
        nextInstallment,
        storeCushion;
export 'src/policies/director.dart'
    show buyoutPaybackMonths, directorManagerDuties;
export 'src/policies/entrepreneur_policy.dart' show EntrepreneurPolicy;
export 'src/policies/policy.dart'
    show CombinedPolicy, Policy, ownerPolicy, standardPolicies;
export 'src/policies/retail_policy.dart' show RetailPolicy;
export 'src/reports/attribution.dart'
    show Attribution, ItemMiss, MissReason, StoreSwitch, SwitchCause;
export 'src/reports/period_report.dart'
    show PeriodReport, ReportPeriod, StoreReport, SwitchKey;
export 'src/simulation.dart' show CommandRejection, Simulation, TickResult;
export 'src/state/credit.dart' show lendingRate, splitLoan;
export 'src/state/director.dart';
export 'src/state/entities.dart'
    show CompanyStatus, defaultCushionDays, maxCushionDays;
export 'src/state/game_start.dart'
    show GameStart, StartTerms, minStartingCash, startTerms, startingSites;
export 'src/state/history.dart' show SalesCount, salesHistoryDays;
export 'src/state/market.dart' show Census;
export 'src/state/orders.dart' show OrderLine;
export 'src/state/public_record.dart' show EconomicMonth, Filing;
export 'src/state/research.dart' show ResearchReport, SegmentEstimate;
export 'src/state/store.dart' show ManagerDuty, StoreStatus, Works;
export 'src/state/valuation.dart' show Valuation, symbolicPrice;
export 'src/systems/events.dart';
