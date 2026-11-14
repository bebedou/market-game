import 'dart:async';

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';

import 'commands.dart';
import 'format.dart';
import 'l10n.dart';
import 'letters.dart';
import 'saves.dart';

/// How fast the clock runs: one day per [interval].
enum Speed {
  paused(Duration.zero),
  slow(Duration(seconds: 2)),
  normal(Duration(seconds: 1)),
  fast(Duration(milliseconds: 250));

  const Speed(this.interval);

  final Duration interval;
}

/// The kinds of news the player is told about, each of which may pause the
/// clock.
enum AlertKind {
  refused,
  overdue,
  bankruptcy,
  stockout,
  deliveryRefused,
  stores,
  economy,
  monthEnd,
  manager,
  director,
  milestone,
  offer;

  String get label => tr('alerts.kinds.$name');
}

final class GameAlert {
  const GameAlert(this.day, this.kind, this.message);

  /// The day it happened.
  final Day day;
  final AlertKind kind;
  final String message;
}

/// A week or month of all the player's companies together: when it began,
/// its profit, what trading earned (see [PeriodReport.tradingProfit]), and
/// the days recorded so far.
typedef HoldingPeriod = ({Day start, Money profit, Money trading, int days});

/// Owns the [Simulation] for the app: the clock that steps it, the player's
/// changes waiting for the next day, the news, and saving. Widgets read the
/// player's [view] and reports from here, never the engine's world.
class SimulationController extends ChangeNotifier {
  SimulationController(ContentDb content, Simulation simulation, {this.saves})
    : _simulation = simulation,
      _view = simulation.observe(content.player) {
    // What a loaded game had already reached isn't news.
    _worthReached = _worthTiers.lastWhere(
      (tier) => netWorth >= tier,
      orElse: () => Money.zero,
    );
    for (final company in _view.companies) {
      for (final store in company.stores) {
        _nameReached[store.id] = _reputationTiers.lastWhere(
          (tier) => store.reputation >= tier,
          orElse: () => Fx.zero,
        );
      }
    }
  }

  /// Net worths worth telling the player they have passed.
  static final _worthTiers = [
    for (final amount in [
      '50000', '100000', '250000', '500000', '1000000', '2500000', //
      '5000000', '10000000', '25000000', '50000000', '100000000',
    ])
      Money.parse(amount),
  ];

  /// Reputations worth telling the player a store has reached.
  static final _reputationTiers = [Fx.parse('0.80'), Fx.parse('0.90')];

  /// The highest net worth tier announced, and each store's highest
  /// reputation tier.
  Money _worthReached = Money.zero;
  final _nameReached = <StoreId, Fx>{};

  /// A new game, the player's first store as [start] chose if given.
  /// A new game; with [citiesAsleep], only the player's city is played in
  /// full, the others by formula until the player trades there.
  SimulationController.newGame(
    ContentDb content, {
    required int seed,
    GameStart? start,
    SaveStore? saves,
    bool citiesAsleep = false,
  }) : this(
         content,
         Simulation.newGame(
           content,
           seed: seed,
           start: start,
           citiesAsleep: citiesAsleep,
         ),
         saves: saves,
       );

  /// The most alerts kept.
  static const alertsKept = 100;

  /// The scenario, and any neighbourhoods woken since the start.
  ContentDb get content => _simulation.content;

  /// The neighbourhoods still asleep, as they would wake today, with the
  /// scenario's content; null if none sleep. To look at, not to play.
  ContentDb? get plan => _simulation.plan;

  /// Every country by formula, as its national statistics have it: null
  /// without them, or with one country. To look at, not to play.
  CountryEconomy? get national => _simulation.national;

  /// The country the player is mostly about: where their first store still
  /// trading is, or else the first.
  CountryId get homeCountry {
    for (final (_, store) in myStores) {
      if (store.status != StoreStatus.closed) {
        return content.countryOf(store.market);
      }
    }
    return const CountryId(0);
  }

  /// Where the player lives, and pays tax on their dividends: where their
  /// game started.
  CountryId get residence =>
      _simulation.world.residence(content, _simulation.world.player);

  /// The country [company] is from: where its first store still trading is,
  /// or else the player's home.
  CountryId countryOfCompany(CompanyView? company) {
    for (final store in company?.stores ?? const <StoreView>[]) {
      if (store.status != StoreStatus.closed) {
        return content.countryOf(store.market);
      }
    }
    return homeCountry;
  }

  /// The economy where [market] is: one played in full, or one of [plan]'s
  /// still asleep.
  MacroView economyAt(MarketId market) {
    final markets = market.index < content.markets.length
        ? content.markets
        : plan?.markets ?? content.markets;
    return _view.economy(markets[market.index].country);
  }

  /// The neighbourhood of [row] as the formula runs it, while it sleeps.
  SleepingNeighbourhood? sleeper(int row) => _simulation.world.sleepers
      .where((sleeper) => sleeper.row == row)
      .firstOrNull;

  /// Starts simulating a neighbourhood asleep, for the player to open there:
  /// [row] is its place in the scenario's list. The clock needn't have stepped
  /// for its sites to exist.
  void wake(int row) {
    _simulation.submit(WakeNeighbourhood(player, row: row));
    _view = _simulation.observe(player);
    notifyListeners();
  }

  /// Where the game is saved, if anywhere.
  final SaveStore? saves;

  Simulation _simulation;
  Observation _view;
  final _pending = <Command>[];
  final _alerts = <GameAlert>[];
  final _overdueSeen = <String>{};
  Speed _speed = Speed.paused;
  Timer? _timer;
  Day? _runUntil;
  CompanyId? _selectedCompany;
  StoreId? _selectedStore;

  /// The kinds of alert that pause the clock: by default, only what needs
  /// the player, a change refused, a bill unpaid, a bankruptcy.
  final Set<AlertKind> pauseOn = {
    AlertKind.refused,
    AlertKind.overdue,
    AlertKind.bankruptcy,
  };

  PersonId get player => content.player;

  /// What the player can see, as of the start of [today].
  Observation get view => _view;

  /// The day the next step will simulate.
  Day get today => _view.today;

  Speed get speed => _speed;

  /// Changes the player made since the last step, applied at the start of
  /// the next one.
  List<Command> get pending => List.unmodifiable(_pending);

  /// News, newest first.
  List<GameAlert> get alerts => List.unmodifiable(_alerts);

  /// The player's company being looked at: the one picked, else the newest
  /// active one, else the newest. Null before the player owns any.
  CompanyView? get company {
    final companies = _view.companies;
    if (companies.isEmpty) return null;
    for (final company in companies) {
      if (company.id == _selectedCompany) return company;
    }
    return companies.lastWhere(
      (company) => company.status == CompanyStatus.active,
      orElse: () => companies.last,
    );
  }

  /// The player's store being looked at: the one picked, else the company's
  /// first store that isn't closed, else its first.
  StoreView? get store {
    final stores = company?.stores ?? const <StoreView>[];
    if (stores.isEmpty) return null;
    for (final store in stores) {
      if (store.id == _selectedStore) return store;
    }
    return stores.firstWhere(
      (store) => store.status != StoreStatus.closed,
      orElse: () => stores.first,
    );
  }

  void selectStore(StoreId store) {
    _selectedStore = store;
    for (final company in _view.companies) {
      if (company.stores.any((s) => s.id == store)) {
        _selectedCompany = company.id;
      }
    }
    notifyListeners();
  }

  /// The week or month reports of [company], or of the company being looked
  /// at, oldest first; the latest is still running.
  List<PeriodReport> reports(ReportPeriod period, {CompanyId? company}) {
    final id = company ?? this.company?.id;
    return id == null ? const [] : _simulation.reports(id, period);
  }

  /// How the player chose to start, if they did.
  GameStart? get start => _simulation.world.start;

  /// The holding's name, if the player started with a holding alone.
  String? get holdingName => switch (start) {
    GameStart(holding: true, :final name) => name,
    _ => null,
  };

  String describe(Command command) => describeCommand(command, content, _view);

  /// Queues [command] for the next step. It replaces a pending change to the
  /// same thing; one that would change nothing just cancels that.
  void submit(Command command) {
    final key = _changeKey(command);
    if (key != null) _pending.removeWhere((other) => _changeKey(other) == key);
    if (!_changesNothing(command)) _pending.add(command);
    notifyListeners();
  }

  void cancel(Command command) {
    _pending.remove(command);
    notifyListeners();
  }

  /// The player's brands.
  List<BrandView> get myBrands => [
    for (final brand in _view.brands)
      if (brand.owner == player) brand,
  ];

  /// Starts a brand at once, for a shop to open under it the same day.
  void createBrand(String name, FormatId format) {
    _simulation.submit(CreateBrand(player, name: name, format: format));
    _view = _simulation.observe(player);
    notifyListeners();
  }

  /// Every store of every one of the player's companies, with its company,
  /// in the order they were opened.
  List<(CompanyView, StoreView)> get myStores => [
    for (final company in _view.companies)
      for (final store in company.stores) (company, store),
  ]..sort((a, b) => a.$2.id.index.compareTo(b.$2.id.index));

  /// The player's cash plus what their companies own less what they owe.
  Money get netWorth => _view.companies.fold(
    _view.cash,
    (sum, company) => sum + company.netAssets,
  );

  /// All the player's companies' profit together, week by week or month by
  /// month, oldest first, as far back as reports are kept; the latest period
  /// is still running.
  List<HoldingPeriod> holdingProfits(ReportPeriod period) {
    final profits = <int, Money>{};
    final trading = <int, Money>{};
    final days = <int, int>{};
    for (final company in _view.companies) {
      for (final report in _simulation.reports(company.id, period)) {
        final start = report.start.number;
        profits[start] = (profits[start] ?? Money.zero) + report.profit;
        trading[start] = (trading[start] ?? Money.zero) + report.tradingProfit;
        if (report.days > (days[start] ?? 0)) days[start] = report.days;
      }
    }
    final starts = profits.keys.toList()..sort();
    return [
      for (final start in starts.skip(
        starts.length > period.kept ? starts.length - period.kept : 0,
      ))
        (
          start: Day(start),
          profit: profits[start]!,
          trading: trading[start]!,
          days: days[start]!,
        ),
    ];
  }

  /// What staff and managers are paid in [market], against the scenario's
  /// figures: its country's wage index times the city's wage level.
  Fx wageLevel(MarketId market) =>
      economyAt(market).wageIndex * content.markets[market.index].wageLevel;

  /// [product]'s shelf price at [store] once pending changes apply; null if
  /// it won't be listed.
  Money? priceOf(StoreView store, ProductId product) {
    Money? price = store.prices[product.index];
    for (final command in _pending) {
      switch (command) {
        case SetPrice(store: final s, product: final p, price: final next)
            when s == store.id && p == product:
          price = next;
        case ListProduct(store: final s, product: final p, price: final next)
            when s == store.id && p == product:
          price = next;
        case DelistProduct(store: final s, product: final p)
            when s == store.id && p == product:
          price = null;
        default:
      }
    }
    return price;
  }

  /// The share of its sales [store] spends on marketing once pending
  /// changes apply.
  Fx marketingOf(StoreView store) {
    var share = store.marketingShare;
    for (final command in _pending) {
      if (command case SetMarketing(
        store: final s,
        share: final next,
      ) when s == store.id) {
        share = next;
      }
    }
    return share;
  }

  /// What [store] sold a day over its last week, at today's prices, as the
  /// engine counts it for marketing.
  Money recentDailySales(StoreView store) {
    final sales = store.sales;
    final days = sales.days < 7 ? sales.days : 7;
    if (days == 0) return Money.zero;
    var total = Money.zero;
    for (final product in content.products) {
      final price = store.prices[product.id.index];
      if (price == null) continue;
      total += price.timesInt(sales.total(SalesCount.sold, product.id, days));
    }
    return Money(total.cents ~/ days);
  }

  /// [store]'s staff per slot once pending changes apply.
  List<int> staffOf(StoreView store) {
    var staff = store.staff;
    for (final command in _pending) {
      if (command case SetStaffing(
        store: final s,
        staff: final next,
      ) when s == store.id) {
        staff = next;
      }
    }
    return staff;
  }

  /// [store]'s name once pending changes apply.
  String storeName(StoreId store) {
    var name = _view.shelves[store.index].name;
    for (final command in _pending) {
      if (command case RenameStore(
        store: final s,
        name: final next,
      ) when s == store) {
        name = next;
      }
    }
    return name;
  }

  /// [company]'s name once pending changes apply.
  String companyName(CompanyId company) {
    var name = _view.companyNames[company.index];
    for (final command in _pending) {
      if (command case RenameCompany(
        company: final c,
        name: final next,
      ) when c == company) {
        name = next;
      }
    }
    return name;
  }

  /// [store]'s manager once pending changes apply; null if it will have
  /// none.
  ManagerView? managerOf(StoreView store) {
    var manager = store.manager;
    for (final command in _pending) {
      switch (command) {
        case HireManager(
              store: final s,
              :final grade,
              :final strategy,
              :final duties,
            )
            when s == store.id:
          manager = (
            grade: grade,
            strategy: strategy,
            duties: duties,
            hiredOn: manager != null && manager.grade == grade
                ? manager.hiredOn
                : today,
          );
        case FireManager(store: final s) when s == store.id:
          manager = null;
        default:
      }
    }
    return manager;
  }

  /// [company]'s director once pending changes apply; null if it will have
  /// none.
  Director? directorOf(CompanyView company) {
    var director = company.director;
    for (final command in _pending) {
      switch (command) {
        case HireDirector(
              company: final c,
              :final grade,
              :final strategy,
              :final managerGrade,
              :final growth,
              :final payout,
              :final borrows,
              :final nationalRate,
              :final nationalAuto,
              :final nationalRegions,
            )
            when c == company.id:
          director = Director(
            grade: grade,
            strategy: strategy,
            managerGrade: managerGrade,
            growth: growth,
            payout: payout,
            borrows: borrows,
            nationalRate: nationalRate,
            nationalAuto: nationalAuto,
            nationalRegions: nationalRegions,
            hiredOn: director != null && director.grade == grade
                ? director.hiredOn
                : today,
          );
        case FireDirector(company: final c) when c == company.id:
          director = null;
        default:
      }
    }
    return director;
  }

  /// Whether [store]'s manager will look after [duty].
  bool delegates(StoreView store, ManagerDuty duty) =>
      managerOf(store)?.duties[duty.index] ?? false;

  /// How many days of wages [company]'s cash cushion holds once pending
  /// changes apply.
  int cushionDays(CompanyView company) {
    var days = company.cushionDays;
    for (final command in _pending) {
      if (command case SetCushion(
        company: final c,
        days: final next,
      ) when c == company.id) {
        days = next;
      }
    }
    return days;
  }

  /// [company]'s cash cushion once pending changes apply: see
  /// [cashCushion].
  Money cushion(CompanyView company) {
    final days = cushionDays(company);
    var total = company.taxAccrued;
    if (directorOf(company) case final director?) {
      total += directorSalary(_view, content, company, director).timesInt(days);
    }
    for (final store in company.stores) {
      total += storeCushion(_view, content, store, days);
    }
    for (final factory in company.factories) {
      if (!factory.making) continue;
      total += factory.dailyWages.timesInt(days) + factory.monthlySite;
    }
    for (final loan in company.loans) {
      total += nextInstallment(loan);
    }
    return total;
  }

  /// Every factory of the player's companies, with its company, in the
  /// order built.
  List<(CompanyView, FactoryView)> get myFactories => [
    for (final company in _view.companies)
      for (final factory in company.factories) (company, factory),
  ]..sort((a, b) => a.$2.id.index.compareTo(b.$2.id.index));

  /// The player's factory [id] as of today, if it is theirs.
  FactoryView? factory(FactoryId id) {
    for (final (_, factory) in myFactories) {
      if (factory.id == id) return factory;
    }
    return null;
  }

  /// How many shifts [factory] runs once pending changes apply.
  int shiftsOf(FactoryView factory) {
    var shifts = factory.shifts;
    for (final command in _pending) {
      if (command case SetFactoryShifts(
        factory: final f,
        shifts: final next,
      ) when f == factory.id) {
        shifts = next;
      }
    }
    return shifts;
  }

  /// Where [factory] delivers and what it charges rivals once pending
  /// changes apply.
  ({List<bool> serves, Fx? rivalDiscount}) termsOf(FactoryView factory) {
    var terms = (serves: factory.serves, rivalDiscount: factory.rivalDiscount);
    for (final command in _pending) {
      if (command case SetFactoryTerms(
        factory: final f,
        :final serves,
        :final rivalDiscount,
      ) when f == factory.id) {
        terms = (serves: serves, rivalDiscount: rivalDiscount);
      }
    }
    return terms;
  }

  /// Whether [factory] is to close tomorrow.
  bool closing(FactoryView factory) => _pending.any(
    (command) => command is CloseFactory && command.factory == factory.id,
  );

  /// Whether a change to [product] at [store] is waiting for the next step.
  bool isPending(StoreId store, ProductId product) => _pending.any(
    (command) => switch (command) {
      SetPrice(store: final s, product: final p) ||
      ListProduct(store: final s, product: final p) ||
      DelistProduct(
        store: final s,
        product: final p,
      ) => s == store && p == product,
      _ => false,
    },
  );

  void setSpeed(Speed speed) {
    _runUntil = null;
    _run(speed);
  }

  void pause() => setSpeed(Speed.paused);

  /// Runs the next seven days quickly, then pauses.
  void advanceWeek() {
    _runUntil = today + 7;
    _run(Speed.fast);
  }

  void _run(Speed speed) {
    _timer?.cancel();
    _timer = null;
    _speed = speed;
    if (speed != Speed.paused) {
      _timer = Timer.periodic(speed.interval, (_) => step());
    }
    notifyListeners();
  }

  /// Simulates one day with the pending changes, and gathers the news.
  /// Pauses if any of it is in [pauseOn], or a week run is over.
  TickResult step() {
    final before = _view;
    final submitted = List.of(_pending);
    submitted.forEach(_simulation.submit);
    _pending.clear();
    final result = _simulation.step();
    _view = _simulation.observe(player);
    final news = _news(result, before, _view, submitted);
    _alerts.insertAll(0, news.reversed);
    if (_alerts.length > alertsKept) _alerts.length = alertsKept;
    final runOver = _runUntil != null && today >= _runUntil!;
    if (runOver || news.any((alert) => pauseOn.contains(alert.kind))) {
      _runUntil = null;
      _run(Speed.paused);
    }
    if (today.isFirstOfMonth) unawaited(save());
    notifyListeners();
    return result;
  }

  /// Saves the game, without the pending changes, with what the main menu
  /// shows of it.
  Future<void> save() async {
    final company = this.company;
    await saves?.write(
      _simulation.save(),
      summary: (
        company:
            holdingName ??
            (company == null
                ? tr('common.noCompany')
                : companyName(company.id)),
        day: today,
        netWorth: netWorth,
        saved: DateTime.now(),
      ),
    );
  }

  /// The player's companies still trading.
  List<CompanyView> get activeCompanies => [
    for (final company in _view.companies)
      if (company.status == CompanyStatus.active) company,
  ];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// What [command] changes, if a later command may replace it.
  static String? _changeKey(Command command) => switch (command) {
    SetPrice(:final store, :final product) =>
      'price ${store.index} ${product.index}',
    ListProduct(:final store, :final product) ||
    DelistProduct(
      :final store,
      :final product,
    ) => 'listing ${store.index} ${product.index}',
    SetStaffing(:final store) => 'staff ${store.index}',
    HireManager(:final store) ||
    FireManager(:final store) => 'manager ${store.index}',
    ExpandStore(:final store) => 'enlarge ${store.index}',
    RenameStore(:final store) => 'store name ${store.index}',
    RenameCompany(:final company) => 'company name ${company.index}',
    SetCushion(:final company) => 'cushion ${company.index}',
    HireDirector(:final company) ||
    FireDirector(:final company) => 'director ${company.index}',
    SetMarketing(:final store) => 'marketing ${store.index}',
    ConvertStore(:final store) => 'enlarge ${store.index}',
    BuyStore(:final store) || SellStore(:final store) => 'deal ${store.index}',
    BuyCompany(:final company) => 'company deal ${company.index}',
    SetFactoryShifts(:final factory) => 'factory shifts ${factory.index}',
    SetFactoryTerms(:final factory) => 'factory terms ${factory.index}',
    CloseFactory(:final factory) => 'factory close ${factory.index}',
    _ => null,
  };

  /// Whether [command] would leave things as they are now.
  bool _changesNothing(Command command) {
    StoreView? find(StoreId id) {
      for (final company in _view.companies) {
        for (final store in company.stores) {
          if (store.id == id) return store;
        }
      }
      return null;
    }

    return switch (command) {
      SetPrice(:final store, :final product, :final price) =>
        find(store)?.prices[product.index] == price,
      ListProduct(:final store, :final product) =>
        find(store)?.prices[product.index] != null,
      DelistProduct(:final store, :final product) =>
        find(store)?.prices[product.index] == null,
      SetStaffing(:final store, :final staff) => listEquals(
        find(store)?.staff,
        staff,
      ),
      HireManager(:final store, :final grade, :final strategy, :final duties) =>
        switch (find(store)?.manager) {
          final manager? =>
            manager.grade == grade &&
                manager.strategy == strategy &&
                listEquals(manager.duties, duties),
          null => false,
        },
      FireManager(:final store) => find(store)?.manager == null,
      RenameStore(:final store, :final name) =>
        _view.shelves[store.index].name == name,
      RenameCompany(:final company, :final name) =>
        _view.companyNames[company.index] == name,
      SetCushion(:final company, :final days) => _view.companies.any(
        (c) => c.id == company && c.cushionDays == days,
      ),
      HireDirector(
        :final company,
        :final grade,
        :final strategy,
        :final managerGrade,
        :final growth,
        :final payout,
        :final borrows,
      ) =>
        _view.companies.any(
          (c) =>
              c.id == company &&
              c.director?.grade == grade &&
              c.director?.strategy == strategy &&
              c.director?.managerGrade == managerGrade &&
              c.director?.growth == growth &&
              c.director?.payout == payout &&
              c.director?.borrows == borrows,
        ),
      FireDirector(:final company) => _view.companies.any(
        (c) => c.id == company && c.director == null,
      ),
      SetMarketing(:final store, :final share) =>
        find(store)?.marketingShare == share,
      SetFactoryShifts(:final factory, :final shifts) =>
        this.factory(factory)?.shifts == shifts,
      SetFactoryTerms(:final factory, :final serves, :final rivalDiscount) =>
        switch (this.factory(factory)) {
          final now? =>
            listEquals(now.serves, serves) &&
                now.rivalDiscount == rivalDiscount,
          null => false,
        },
      _ => false,
    };
  }

  List<GameAlert> _news(
    TickResult result,
    Observation before,
    Observation after,
    List<Command> submitted,
  ) {
    final day = result.day;
    final news = <GameAlert>[];
    void add(AlertKind kind, String message) =>
        news.add(GameAlert(day, kind, message));
    String productName(ProductId id) => content.products[id.index].name;
    String storeName(StoreId id) => after.shelves[id.index].name;
    final mine = {for (final company in after.companies) company.id};
    final myStores = {
      for (final company in after.companies)
        for (final store in company.stores) store.id,
    };
    // Stores whose stock a manager orders: what they restock, and what a
    // delivery that didn't fit leaves out, is theirs to see to.
    final restocked = {
      for (final company in after.companies)
        for (final store in company.stores)
          if (delegates(store, ManagerDuty.ordering)) store.id,
    };

    final refused = <(StoreId, RefusalReason), List<String>>{};
    for (final rejection in result.rejections) {
      final command = rejection.command;
      if (command.actor != player) continue;
      final described = describeCommand(command, content, after);
      if (submitted.any((mine) => identical(mine, command))) {
        add(
          AlertKind.refused,
          tr('alerts.refused', {
            'what': described,
            'reason': refusalText(rejection.reason, content),
          }),
        );
      } else {
        // Managers act for the player too.
        add(
          AlertKind.manager,
          tr('alerts.managerCouldNot', {
            'what': uncapitalized(described),
            'reason': refusalText(rejection.reason, content),
          }),
        );
      }
    }
    for (final event in result.events) {
      switch (event) {
        case PaymentOverdue(
              :final company,
              :final reason,
              :final amount,
              :final due,
            )
            when mine.contains(company):
          final key = '${company.index} ${reason.index} ${due.number}';
          if (_overdueSeen.add(key)) {
            add(
              AlertKind.overdue,
              tr('alerts.overdue', {
                'company': after.companyNames[company.index],
                'bill': _billName(reason),
                'amount': money(amount),
                'due': shortDate(due),
              }),
            );
          }
        case CompanyLiquidated(:final company, :final owner, :final guaranteed)
            when owner == player:
          add(
            AlertKind.bankruptcy,
            tr('alerts.liquidated', {
              'company': after.companyNames[company.index],
              'guarantees': guaranteed > Money.zero
                  ? tr('alerts.guaranteesPaid', {'amount': money(guaranteed)})
                  : '',
            }),
          );
        case CompanyLiquidated(:final company):
          add(
            AlertKind.bankruptcy,
            tr('alerts.bankrupt', {
              'company': after.companyNames[company.index],
            }),
          );
        case DeliveryRefused(
              :final store,
              :final product,
              :final units,
              :final reason,
            )
            when myStores.contains(store) && !restocked.contains(store):
          (refused[(store, reason)] ??= []).add(
            '$units ${productName(product)}',
          );
        default:
      }
    }

    refused.forEach((key, lines) {
      final (store, reason) = key;
      add(
        AlertKind.deliveryRefused,
        tr(
          reason == RefusalReason.storageFull
              ? 'alerts.turnedAwayFull'
              : 'alerts.turnedAwayNotStocked',
          {'store': storeName(store), 'lines': lines.join(', ')},
        ),
      );
    });

    // A product that sold out with nothing on order, where the player does
    // the ordering: what a manager restocks is theirs to see to.
    for (final company in after.companies) {
      for (final store in company.stores) {
        if (store.status != StoreStatus.open ||
            delegates(store, ManagerDuty.ordering)) {
          continue;
        }
        final soldOut = <String>[];
        StoreView? previous;
        for (final earlier in before.companies) {
          for (final s in earlier.stores) {
            if (s.id == store.id) previous = s;
          }
        }
        for (final product in content.products) {
          final i = product.id.index;
          if (store.prices[i] != null &&
              store.stock[i] == 0 &&
              store.onOrder[i] == 0 &&
              (previous?.stock[i] ?? 0) > 0) {
            soldOut.add(product.name);
          }
        }
        if (soldOut.isNotEmpty) {
          add(
            AlertKind.stockout,
            tr('alerts.soldOut', {
              'store': storeName(store.id),
              'products': soldOut.join(', '),
            }),
          );
        }
      }
    }

    final liquidated = {
      for (final sold in result.events.whereType<StoreSold>()) sold.store,
    };
    for (final shelf in after.shelves) {
      final previous = shelf.id.index < before.shelves.length
          ? before.shelves[shelf.id.index]
          : null;
      final owner = after.companyNames[shelf.company.index];
      final place = content.sites[shelf.site.index];
      final site = content.markets.length == 1
          ? place.name
          : tr('common.siteIn', {
              'site': place.name,
              'market': content.markets[place.market.index].name,
            });
      if (previous == null) {
        add(
          AlertKind.stores,
          tr('alerts.fittingOut', {'owner': owner, 'site': site}),
        );
      } else if (previous.company != shelf.company) {
        final seller = after.companyNames[previous.company.index];
        final wasMine = before.companies.any((c) => c.id == previous.company);
        // By the name it was known by: a chain puts it under its brand.
        final known = previous.name;
        add(
          AlertKind.stores,
          liquidated.contains(shelf.id)
              ? tr('alerts.woundUp', {
                  'store': known,
                  'owner': owner,
                  'seller': seller,
                })
              : myStores.contains(shelf.id)
              ? tr('alerts.youBought', {
                  'store': known,
                  'site': site,
                  'seller': seller,
                })
              : wasMine
              ? tr('alerts.youSold', {'store': known, 'owner': owner})
              : tr('alerts.rivalBought', {
                  'owner': owner,
                  'store': known,
                  'site': site,
                  'seller': seller,
                }),
        );
      } else if (previous.area < shelf.area) {
        add(
          AlertKind.stores,
          myStores.contains(shelf.id)
              ? tr('alerts.grown', {'store': shelf.name, 'area': shelf.area})
              : tr('alerts.rivalEnlarged', {
                  'owner': owner,
                  'store': shelf.name,
                  'area': shelf.area,
                }),
        );
      } else if (previous.status != shelf.status) {
        add(AlertKind.stores, switch (shelf.status) {
          StoreStatus.open => tr('alerts.opened', {
            'store': shelf.name,
            'site': site,
          }),
          StoreStatus.closed => tr('alerts.closed', {
            'store': shelf.name,
            'site': site,
          }),
          StoreStatus.building => tr('alerts.beingFitted', {
            'store': shelf.name,
          }),
        });
      }
    }

    for (final company in after.companies) {
      for (final factory in company.factories) {
        final was = before.companies
            .expand((c) => c.factories)
            .where((f) => f.id == factory.id)
            .firstOrNull;
        if (factory.making && was != null && !was.making) {
          add(
            AlertKind.stores,
            tr('alerts.factoryOpened', {
              'factory': factory.name,
              'country': content.countries[factory.country.index].name,
            }),
          );
        }
      }
    }
    if (after.today.isFirstOfMonth) {
      for (final company in after.companies) {
        final month = _simulation
            .reports(company.id, ReportPeriod.month)
            .lastOrNull;
        if (month == null) continue;
        for (final part in month.factories) {
          final factory = company.factories
              .where((f) => f.id == part.factory)
              .firstOrNull;
          if (factory == null || part.profit >= Money.zero) continue;
          final kind = content.factories!.kinds[factory.kind.index];
          final capacity = kind.shiftUnits * factory.shifts * month.days;
          add(
            AlertKind.monthEnd,
            tr('alerts.factoryBelowBreakEven', {
              'factory': factory.name,
              'month': monthName(month.start),
              'loss': money(-part.profit, cents: false),
              'use': percent(
                capacity == 0
                    ? Fx.zero
                    : Fx.raw(part.made * Fx.scale ~/ capacity),
                decimals: 0,
              ),
            }),
          );
        }
      }
    }

    for (final company in after.companies) {
      if (company.founded >= day ||
          before.companies.any((c) => c.id == company.id)) {
        continue;
      }
      final stores = company.stores.where(
        (s) => s.status != StoreStatus.closed,
      );
      add(
        AlertKind.stores,
        tr('alerts.boughtCompany', {
          'company': after.companyNames[company.id.index],
          'count': stores.length,
        }),
      );
    }

    for (final company in after.companies) {
      // Directors write memos on the day they act.
      for (final memo
          in company.memos.reversed
              .takeWhile((memo) => memo.day == day)
              .toList()
              .reversed) {
        add(
          AlertKind.director,
          tr('alerts.directorSays', {
            'company': after.companyNames[company.id.index],
            'memo': memoSentence(memo, content, after),
          }),
        );
      }
    }

    // Chains offer for the player's shops run by formula on the first of
    // the month.
    if (day.isFirstOfMonth) {
      final known = {
        for (final country in before.national)
          for (final offer in country.offers) offer.number,
      };
      for (final country in after.national) {
        for (final offer in country.offers) {
          if (known.contains(offer.number)) continue;
          add(
            AlertKind.offer,
            tr('alerts.chainOffers', {
              'chain': offer.chain,
              'price': money(offer.price, cents: false),
              'country': country.country == null
                  ? country.def.name
                  : content.countries[country.country!.index].name,
            }),
          );
        }
      }
    }

    // The market grows or shrinks with the households who shop there.
    for (final census in result.events.whereType<CensusTaken>()) {
      if (census.previous == 0) continue;
      final change = Fx.raw(
        ((census.households - census.previous) * Fx.scale / census.previous)
            .round(),
      );
      add(
        AlertKind.economy,
        tr('alerts.census', {
          'year': day.date.year,
          'market': content.markets[census.market.index].name,
          'change': '${change.isNegative ? '' : '+'}${percent(change)}',
        }),
      );
    }

    if (content.countries.length == 1) {
      if (before.macro.regime != after.macro.regime) {
        final regime = content.macro.regimes[after.macro.regime.index];
        add(
          AlertKind.economy,
          tr('alerts.regime', {'regime': aRegime(regime)}),
        );
      }
    } else {
      for (final country in content.countries) {
        final now = after.economy(country.id).regime;
        if (before.economy(country.id).regime == now) continue;
        add(
          AlertKind.economy,
          tr('alerts.countryRegime', {
            'country': country.name,
            'regime': aRegime(content.macro.regimes[now.index]),
          }),
        );
      }
    }

    if (after.today.isFirstOfMonth) {
      final months = reports(ReportPeriod.month);
      if (months.isNotEmpty) {
        final month = months.last;
        add(
          AlertKind.monthEnd,
          tr('alerts.monthEnd', {
            'month': monthName(month.start),
            'profit': money(month.tradingProfit),
            'sales': money(-month.flow(AccountKind.revenue)),
          }),
        );
      }
      // A record month across the holding, once there is a past to beat.
      final holding = holdingProfits(ReportPeriod.month);
      if (holding.length >= 3) {
        final latest = holding.last;
        if (latest.trading > Money.zero &&
            holding
                .take(holding.length - 1)
                .every((month) => month.trading < latest.trading)) {
          add(
            AlertKind.milestone,
            tr('alerts.bestMonth', {
              'amount': money(latest.trading, cents: false),
              'month': monthOnly(latest.start),
            }),
          );
        }
      }
    }

    final worth = netWorth;
    for (final tier in _worthTiers) {
      if (tier > _worthReached && worth >= tier) {
        _worthReached = tier;
        add(
          AlertKind.milestone,
          tr('alerts.netWorth', {'amount': money(tier, cents: false)}),
        );
      }
    }
    for (final company in after.companies) {
      for (final store in company.stores) {
        if (store.status == StoreStatus.closed) continue;
        for (final tier in _reputationTiers) {
          if (tier > (_nameReached[store.id] ?? Fx.zero) &&
              store.reputation >= tier) {
            _nameReached[store.id] = tier;
            add(
              AlertKind.milestone,
              tr('alerts.madeAName', {
                'store': storeName(store.id),
                'rating': percent(tier, decimals: 0),
              }),
            );
          }
        }
      }
    }
    return news;
  }

  static String _billName(EntryReason reason) => switch (reason) {
    EntryReason.supplierPayment => tr('terms.bills.supplierInvoice'),
    EntryReason.rent => tr('terms.bills.rent'),
    EntryReason.overheads => tr('terms.bills.overheads'),
    EntryReason.wages => tr('terms.bills.wages'),
    EntryReason.interest => tr('terms.bills.interest'),
    EntryReason.loanRepayment => tr('terms.bills.loan'),
    EntryReason.marketing => tr('terms.bills.marketing'),
    EntryReason.corporateTax => tr('terms.bills.tax'),
    EntryReason.materials => tr('terms.bills.materials'),
    EntryReason.freight => tr('terms.bills.freight'),
    _ => tr('terms.bills.other'),
  };
}
