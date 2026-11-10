import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/saves.dart';

import 'support.dart';

void main() {
  final milk = product('milk_budget');
  final player = prototype.player;

  test('only what needs the player pauses, and good news is told too', () {
    final game = newController()
      ..submit(
        HireManager(
          player,
          store: playerStore,
          grade: grade('expert'),
          strategy: strategy('balanced'),
          duties: [for (final _ in ManagerDuty.values) true],
        ),
      );
    expect(game.pauseOn, {
      AlertKind.refused,
      AlertKind.overdue,
      AlertKind.bankruptcy,
    });
    for (var i = 0; i < 152; i++) {
      game.step();
    }
    expect(
      game.alerts.where(
        (alert) =>
            alert.kind == AlertKind.stockout ||
            alert.kind == AlertKind.deliveryRefused,
      ),
      isEmpty,
      reason: 'the manager restocks the store',
    );
    expect(
      game.alerts
          .where((alert) => alert.kind == AlertKind.milestone)
          .map((alert) => alert.message),
      contains(startsWith('Your best month yet')),
    );
  });

  test('starts on the scenario day, looking at the player\'s store', () {
    final game = newController();
    expect(game.today, prototype.startDay);
    expect(game.company?.id, playerCompany);
    expect(game.store?.id, playerStore);
    expect(game.speed, Speed.paused);
    expect(game.view.companyNames.first, 'Corner Shop');
  });

  test('the holding adds up every company: net worth and profit', () {
    final game = newController();
    // Your 20,000 and the company's 15,000.
    expect(game.netWorth, Money.parse('35000.00'));
    openSecondStore(game);
    // A month, before its unpaid rent winds the new company up.
    for (var i = 0; i < 30; i++) {
      game.step();
    }
    expect(game.view.companies, hasLength(2));
    expect(game.myStores.map((pair) => game.storeName(pair.$2.id)), [
      'Corner Shop',
      'Mail Market',
    ]);
    expect(
      game.netWorth,
      game.view.companies.fold(
        game.view.cash,
        (sum, company) => sum + company.netAssets,
      ),
    );
    final weeks = game.holdingProfits(ReportPeriod.week);
    for (final week in weeks) {
      expect(
        week.profit,
        game.view.companies.fold(
          Money.zero,
          (sum, company) =>
              sum +
              (game
                      .reports(ReportPeriod.week, company: company.id)
                      .where((report) => report.start == week.start)
                      .firstOrNull
                      ?.profit ??
                  Money.zero),
        ),
      );
    }
    // Moving cash into the new company left net worth alone: only profit,
    // the fitting out included, changed it.
    expect(
      game.netWorth - Money.parse('35000.00'),
      weeks.fold(Money.zero, (sum, week) => sum + week.profit),
    );
  });

  test('keeps one pending change per thing, and drops changes to nothing', () {
    final game = newController();
    final store = game.store!;
    final current = store.prices[milk.index]!;
    game
      ..submit(
        SetPrice(player, store: playerStore, product: milk, price: Money(101)),
      )
      ..submit(
        SetPrice(player, store: playerStore, product: milk, price: Money(105)),
      );
    expect(game.pending, hasLength(1));
    expect(game.priceOf(store, milk), Money(105));
    expect(game.isPending(playerStore, milk), isTrue);

    game.submit(
      SetPrice(player, store: playerStore, product: milk, price: current),
    );
    expect(game.pending, isEmpty);
    expect(game.priceOf(store, milk), current);

    game.submit(DelistProduct(player, store: playerStore, product: milk));
    expect(game.priceOf(store, milk), isNull);
    game.submit(
      ListProduct(player, store: playerStore, product: milk, price: current),
    );
    expect(game.pending, isEmpty, reason: 'relisting cancels the delisting');

    game.submit(
      SetStaffing(player, store: playerStore, staff: const [2, 1, 2, 0]),
    );
    expect(game.staffOf(store), [2, 1, 2, 0]);
  });

  test('applies pending changes on the next step', () {
    final game = newController()
      ..submit(
        SetPrice(player, store: playerStore, product: milk, price: Money(105)),
      );
    final result = game.step();
    expect(result.rejections, isEmpty);
    expect(game.pending, isEmpty);
    expect(game.store!.prices[milk.index], Money(105));
    expect(game.today, prototype.startDay + 1);
  });

  test('reports refusals as news', () {
    final game = newController()
      ..submit(
        PayDividend(
          player,
          company: playerCompany,
          amount: Money.parse('100.00'),
        ),
      );
    game.step();
    final alert = game.alerts.first;
    expect(alert.kind, AlertKind.refused);
    expect(alert.day, prototype.startDay);
    expect(
      alert.message,
      contains('dividends can only come out of retained profits'),
    );
  });

  test('sums up each month when it ends', () {
    final game = newController();
    for (var i = 0; i < 31; i++) {
      game.step();
    }
    expect(game.today.isFirstOfMonth, isTrue);
    final summary = game.alerts.firstWhere((a) => a.kind == AlertKind.monthEnd);
    expect(summary.message, startsWith('January 2026: profit'));
    expect(game.reports(ReportPeriod.month).first.days, 31);
  });

  testWidgets('the clock steps at its speed and a week run pauses', (
    tester,
  ) async {
    final game = newController();
    addTearDown(game.dispose);
    game.pauseOn.clear();
    game.setSpeed(Speed.normal);
    await tester.pump(const Duration(milliseconds: 3100));
    expect(game.today, prototype.startDay + 3);

    game.advanceWeek();
    await tester.pump(const Duration(seconds: 5));
    expect(game.today, prototype.startDay + 10);
    expect(game.speed, Speed.paused);
  });

  testWidgets('pausing news stops the clock', (tester) async {
    final game = newController();
    addTearDown(game.dispose);
    game
      ..submit(
        PayDividend(
          player,
          company: playerCompany,
          amount: Money.parse('100.00'),
        ),
      )
      ..setSpeed(Speed.fast);
    await tester.pump(const Duration(seconds: 2));
    expect(game.speed, Speed.paused);
    expect(game.today, prototype.startDay + 1);
  });

  test('saves the game, which loads back identically', () async {
    final saves = MemorySaveStore();
    final game = newController(saves: saves);
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    await game.save();
    expect(saves.summary?.company, 'Corner Shop');
    expect(saves.summary?.day, game.today);
    expect(saves.summary?.netWorth, game.netWorth);
    final loaded = SimulationController(
      prototype,
      Simulation.load(prototype, saves.file!),
    );
    expect(loaded.today, game.today);
    expect(loaded.view.cash, game.view.cash);
    expect(
      loaded.reports(ReportPeriod.week).map((report) => report.profit),
      game.reports(ReportPeriod.week).map((report) => report.profit),
    );
  });

  test('a new game starts where the player chose', () {
    final game = SimulationController.newGame(
      prototype,
      seed: 3,
      start: GameStart(
        site: mill,
        format: format('fastfood'),
        name: 'Mill Burgers',
      ),
    );
    expect(game.company?.id, playerCompany);
    expect(game.companyName(playerCompany), 'Mill Burgers');
    expect(game.store?.site, mill);
    expect(game.store?.format, format('fastfood'));
  });

  test('buying and selling stores make the news', () {
    final game = newController();
    final student = game.view.shelves.firstWhere(
      (shelf) => shelf.name == 'Le Comptoir Étudiant',
    );
    game
      ..submit(
        InjectCapital(player, company: playerCompany, amount: game.view.cash),
      )
      ..step()
      ..submit(BuyStore(player, store: student.id, company: playerCompany))
      ..step();
    expect(game.myStores.map((s) => s.$2.id), [playerStore, student.id]);
    expect(
      game.alerts.map((a) => a.message),
      contains(
        startsWith("You bought Le Comptoir Étudiant at Rue de l'Université"),
      ),
    );
    final buyer = game.myStores.last.$2.buyer!;
    game
      ..submit(SellStore(player, store: student.id))
      ..step();
    expect(game.myStores.map((s) => s.$2.id), [playerStore]);
    expect(
      game.alerts.first.message,
      'You sold Le Comptoir Étudiant to ${game.view.companyNames[buyer.index]}.',
    );
  });

  test('shows a manager as it will be, and replaces or cancels changes', () {
    final game = newController();
    final store = game.store!;
    HireManager hire(String key, List<bool> duties) => HireManager(
      player,
      store: playerStore,
      grade: grade(key),
      strategy: strategy('balanced'),
      duties: duties,
    );
    game.submit(hire('trainee', const [true, false, false, false, false]));
    expect(game.managerOf(store)?.grade, grade('trainee'));
    expect(game.delegates(store, ManagerDuty.ordering), isTrue);
    expect(game.delegates(store, ManagerDuty.pricing), isFalse);
    game.submit(hire('expert', const [true, true, false, false, false]));
    expect(game.pending, hasLength(1));
    expect(game.delegates(store, ManagerDuty.pricing), isTrue);
    game.submit(FireManager(player, store: playerStore));
    expect(game.pending, isEmpty, reason: 'there is no manager to let go');
    expect(game.managerOf(store), isNull);
  });

  test('a hired manager keeps the store stocked and priced', () {
    final game = newController()
      ..submit(
        HireManager(
          player,
          store: playerStore,
          grade: grade('experienced'),
          strategy: strategy('discount'),
          duties: const [true, true, false, false, false],
        ),
      );
    for (var i = 0; i < 45; i++) {
      game.step();
    }
    final store = game.store!;
    expect(store.manager?.grade, grade('experienced'));
    expect(store.sales.total(SalesCount.sold, milk, 28), greaterThan(100));
    expect(store.prices[milk.index], isNot(Money(95)), reason: 'repriced');
    expect(
      game.reports(ReportPeriod.month).first.flow(AccountKind.salaries).cents,
      greaterThan(0),
    );
    expect(
      game.alerts.where((alert) => alert.kind == AlertKind.refused),
      isEmpty,
    );
  });

  test('enlarging the store shows as works, then as news', () {
    final game = newController()
      ..submit(ExpandStore(player, store: playerStore));
    game.step();
    expect(game.store!.works?.area, 160);
    for (var i = 0; i < 14; i++) {
      game.step();
    }
    expect(game.store!.area, 160);
    expect(game.store!.shelfSlots, 10);
    expect(
      game.alerts.map((alert) => alert.message),
      contains('Corner Shop has grown to 160 m².'),
    );
  });

  test('shows names as they will be, and drops renames to the same name', () {
    final game = newController()
      ..submit(RenameStore(player, store: playerStore, name: 'Chez Rayan'))
      ..submit(
        RenameCompany(player, company: playerCompany, name: 'Rayan & Co'),
      );
    expect(game.storeName(playerStore), 'Chez Rayan');
    expect(game.companyName(playerCompany), 'Rayan & Co');
    game.submit(RenameStore(player, store: playerStore, name: 'Corner Shop'));
    expect(game.pending, hasLength(1));
    game.step();
    expect(game.view.companyNames[playerCompany.index], 'Rayan & Co');
    expect(game.view.shelves[playerStore.index].name, 'Corner Shop');
  });

  test('each January census is news', () {
    final game = newController();
    while (game.today < Day.parse('2027-01-02')) {
      game.step();
    }
    final censuses = [
      for (final alert in game.alerts)
        if (alert.message.startsWith('2027 census')) alert,
    ];
    expect(censuses, hasLength(prototype.markets.length));
    expect(
      censuses.map((alert) => alert.kind),
      everyElement(AlertKind.economy),
    );
    // The market moves with the households who shop there, in percent.
    expect(
      censuses.map((alert) => alert.message),
      contains(
        allOf(contains('the market in Lyon, Croix-Rousse is'), contains('%')),
      ),
    );
    expect(game.view.censuses.first, hasLength(2));
    expect(game.view.households.first, greaterThan(1000));
  });
}
