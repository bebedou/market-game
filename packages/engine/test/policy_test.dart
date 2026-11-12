import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with the rival run by the steady AI strategy.
final aiScenarioJson = testScenarioJson.replaceFirst(
  '"name": "Rival", "cash": "2000.00" }',
  '"name": "Rival", "cash": "2000.00", "strategy": "steady" }',
);

void main() {
  final content = loadScenario(testScenarioJson);
  final policy = RetailPolicy(content.strategies[steady.index]);
  final start = content.startDay;
  // Day numbers decide review days: (day + store index) modulo the period.
  final quietDay = start + 1;
  final playerPriceDay = start;
  final rivalAssortmentDay = start + 13;

  /// Sales counts for [days] days, the same every day.
  RecentSales history(int days, Map<(SalesCount, ProductId), int> daily) =>
      RecentSales(days, [
        for (final count in SalesCount.values)
          [
            for (final product in content.products)
              List.filled(days, daily[(count, product.id)] ?? 0),
          ],
      ]);

  /// What the owner of [store] sees; the other store is the competitor.
  Observation view({
    required Day today,
    StoreId store = playerStore,
    List<Money?> prices = const [Money(95), Money(169)],
    List<Money?> competitorPrices = const [Money(99), null],
    List<int> stock = const [0, 0],
    List<int> onOrder = const [0, 0],
    int storage = 400,
    Money cash = const Money(50000),
    Money committed = Money.zero,
    Day? committedDue,
    RecentSales? sales,
    Money personalCash = Money.zero,
    Map<AccountKind, Money> balances = const {},
    Day? founded,
    StoreMonths recentMonths = (
      revenue: Money.zero,
      profit: Money.zero,
      days: 0,
    ),
  }) {
    final setup = content.stores[store.index];
    final site = content.sites[setup.site.index];
    return Observation(
      today: today,
      actor: content.companies[setup.company.index].owner,
      cash: personalCash,
      lastBankruptcy: null,
      macro: (
        regime: RegimeId(0),
        priceIndex: Fx.one,
        wageIndex: Fx.one,
        inflation: Fx.zero,
        policyRate: Fx.parse('0.03'),
        unemployment: Fx.zero,
      ),
      households: const [60],
      censuses: [
        [(day: start, households: 60)],
      ],
      companyNames: [for (final company in content.companies) company.name],
      companies: [
        CompanyView(
          id: setup.company,
          status: CompanyStatus.active,
          founded: founded ?? start,
          balances: [
            for (final kind in AccountKind.values)
              kind == AccountKind.cash ? cash : (balances[kind] ?? Money.zero),
          ],
          committed: committed,
          loans: const [],
          orders: const [],
          // What is spoken for, as a supplier's bill due today unless said.
          bills: [
            if (committed > Money.zero)
              (
                creditor: (type: PartyType.supplier, index: 0),
                reason: EntryReason.supplierPayment,
                amount: committed,
                due: committedDue ?? today,
              ),
          ],
          stores: [
            StoreView(
              id: store,
              site: site.id,
              status: StoreStatus.open,
              opensOn: start,
              market: site.market,
              shelfSlots: site.shelfSlots,
              storageUnits: storage,
              prices: prices,
              stock: stock,
              onOrder: onOrder,
              staff: const [1, 1, 1, 0],
              service: const [Fx.one, Fx.one, Fx.one, Fx.one],
              sales: sales ?? history(0, const {}),
              area: site.area,
              recentMonths: recentMonths,
            ),
          ],
        ),
      ],
      shelves: [
        for (final id in [playerStore, rivalStore])
          ShelfView(
            id: id,
            name: content.stores[id.index].name,
            company: content.stores[id.index].company,
            site: content.stores[id.index].site,
            status: StoreStatus.open,
            market: site.market,
            location:
                content.sites[content.stores[id.index].site.index].location,
            prices: id == store ? prices : competitorPrices,
            openSlots: const [true, true, true, true],
            area: content.sites[content.stores[id.index].site.index].area,
          ),
      ],
      vacantSites: const [lane],
      reports: const [],
    );
  }

  List<String> decide(Observation observation) => [
    for (final command in policy.decide(observation, content))
      command.toString(),
  ];

  group('ordering', () {
    test('orders up to lead time, safety and cycle stock', () {
      // No history: 10 units a day. Bulk is cheapest for both milks and
      // takes 3 days: 30 in transit + 20 safety + 30 cycle stock.
      expect(decide(view(today: quietDay)), [
        'PlaceOrder(actor: 0, store: 0, supplier: 0, lines: 0×80, 1×80)',
      ]);
    });

    test('waits until stock and orders fall to the reorder point', () {
      final observation = view(
        today: quietDay,
        stock: [40, 0],
        onOrder: [20, 0],
      );
      expect(decide(observation), [
        'PlaceOrder(actor: 0, store: 0, supplier: 0, lines: 1×80)',
      ]);
    });

    test('orders smaller batches when storage is short', () {
      // 40 units of safety stock fit in 60; cycle stock gets the other 20.
      expect(decide(view(today: quietDay, storage: 60)), [
        'PlaceOrder(actor: 0, store: 0, supplier: 0, lines: 0×60, 1×60)',
      ]);
    });

    test('spends only uncommitted cash, most profitable lines first', () {
      // Organic milk (84.00) earns more but doesn't fit in 50.00; value milk
      // (44.00) does.
      final observation = view(
        today: quietDay,
        cash: Money.parse('150.00'),
        committed: Money.parse('100.00'),
      );
      expect(decide(observation), [
        'PlaceOrder(actor: 0, store: 0, supplier: 0, lines: 0×80)',
      ]);
    });

    test('keeps buying a few days of each line with cash owed only later', () {
      // The 100.00 is due in a month, so the 150.00 in hand buys organic
      // and value milk up to their reorder points, 50 of each, rather than
      // nothing of organic milk.
      final observation = view(
        today: quietDay,
        cash: Money.parse('150.00'),
        committed: Money.parse('100.00'),
        committedDue: quietDay + 30,
      );
      expect(decide(observation), [
        'PlaceOrder(actor: 0, store: 0, supplier: 0, lines: 0×50, 1×50)',
      ]);
    });
  });

  group('pricing', () {
    test('moves prices toward cost plus markup and the market', () {
      // Value milk: 0.55 × 1.4 = 0.77, halfway to the rival's 0.99 is 0.88,
      // but one step down from 0.95 is 0.90. Organic milk has no competitor:
      // its target is 1.47, and one step down from 1.69 is 1.61.
      expect(decide(view(today: playerPriceDay)).take(2), [
        'SetPrice(actor: 0, store: 0, product: 0, price: 0.90)',
        'SetPrice(actor: 0, store: 0, product: 1, price: 1.61)',
      ]);
    });

    test('cuts a price when too many buyers refuse it', () {
      List<String> organicPrice(RecentSales sales) => [
        for (final command in decide(
          view(
            today: playerPriceDay,
            prices: const [Money(95), Money(140)],
            sales: sales,
          ),
        ))
          if (command.startsWith('SetPrice') && command.contains('product: 1'))
            command,
      ];
      final selling = history(14, {(SalesCount.sold, milkPremium): 10});
      expect(organicPrice(selling), [
        'SetPrice(actor: 0, store: 0, product: 1, price: 1.47)',
      ]);
      final refused = history(14, {
        (SalesCount.sold, milkPremium): 10,
        (SalesCount.overpriced, milkPremium): 5,
      });
      expect(organicPrice(refused), [
        'SetPrice(actor: 0, store: 0, product: 1, price: 1.33)',
      ]);
    });
  });

  test('staffs its hours to cover recent traffic with headroom', () {
    // 70 evening visits a day, 1.2 headroom, 30 visits per staff: 3 staff;
    // a quiet morning and midday get one each; it never opens at night.
    final busyEvenings = RecentSales(
      14,
      [
        for (final _ in SalesCount.values)
          [for (final _ in content.products) List.filled(14, 0)],
      ],
      [
        List.filled(14, 10),
        List.filled(14, 10),
        List.filled(14, 70),
        List.filled(14, 0),
      ],
    );
    final commands = decide(
      view(today: playerPriceDay, sales: busyEvenings),
    ).where((command) => command.startsWith('SetStaffing'));
    expect(commands, ['SetStaffing(actor: 0, store: 0, staff: [1, 1, 3, 0])']);
  });

  test('the owner tops up a profitable company that runs short of cash', () {
    // 3000.00 spent over 30 days: a 30-day reserve is 3000.00. With 1000.00
    // free, below half of that, the owner puts in the 2000.00 missing.
    List<String> injections(Money personal) => [
      for (final command in decide(
        view(
          today: quietDay,
          cash: Money.parse('1000.00'),
          personalCash: personal,
          balances: {AccountKind.costOfGoods: Money.parse('3000.00')},
          founded: quietDay + -30,
          stock: const [80, 80],
        ),
      ))
        if (command.startsWith('InjectCapital')) command,
    ];
    expect(injections(Money.parse('5000.00')), [
      'InjectCapital(actor: 0, company: 0, amount: 2000.00)',
    ]);
    expect(injections(Money.parse('500.00')), [
      'InjectCapital(actor: 0, company: 0, amount: 500.00)',
    ]);
  });

  test('the owner backs a new company that loses money for two years', () {
    // Capital of 1000.00 all in cash and nothing earned yet; a 30-day
    // reserve of 3000.00 is spent either way, so 1000.00 free is short.
    List<String> injections(int age) => [
      for (final command in decide(
        view(
          today: quietDay,
          cash: Money.parse('1000.00'),
          personalCash: Money.parse('5000.00'),
          balances: {
            AccountKind.equity: Money.parse('-1000.00'),
            AccountKind.costOfGoods: Money.parse('100.00').timesInt(age),
          },
          founded: quietDay + -age,
          stock: const [80, 80],
        ),
      ))
        if (command.startsWith('InjectCapital')) command,
    ];
    expect(injections(30), [
      'InjectCapital(actor: 0, company: 0, amount: 2000.00)',
    ]);
    expect(injections(729), hasLength(1));
    expect(injections(730), isEmpty, reason: 'it is left to fail');
  });

  group('closing', () {
    // Two years after the store opened on the start day.
    final twoYears = Day.fromDate(2028, 1, 1);
    List<String> closures(Day today, Money profit) => [
      for (final command in decide(
        view(
          today: today,
          stock: const [80, 80],
          recentMonths: (
            revenue: Money.parse('1000.00'),
            profit: profit,
            days: 365,
          ),
        ),
      ))
        if (command.startsWith('CloseStore') ||
            command.startsWith('PlaceOrder') ||
            command.startsWith('SetPrice'))
          command,
    ];

    test('closes a store that lost over 3% of its sales in twelve months', () {
      expect(start + 730, twoYears);
      // 1000.00 of sales.
      expect(closures(twoYears, Money.parse('-30.01')), [
        'CloseStore(actor: 0, store: 0)',
      ]);
    });

    test('keeps a store that about broke even, is under two years old, or '
        'until the first of the month', () {
      expect(
        closures(twoYears, Money.parse('-30.00')),
        isNot(contains(startsWith('Close'))),
      );
      expect(
        closures(Day.fromDate(2027, 12, 1), Money.parse('-500.00')),
        isNot(contains(startsWith('Close'))),
      );
      expect(
        closures(twoYears + 1, Money.parse('-500.00')),
        isNot(contains(startsWith('Close'))),
      );
    });
  });

  group('assortment', () {
    Observation rivalView(int askedForOrganic) => view(
      today: rivalAssortmentDay,
      store: rivalStore,
      prices: const [Money(99), null],
      competitorPrices: const [Money(95), Money(169)],
      storage: 200,
      sales: history(14, {
        (SalesCount.sold, milkBudget): 2,
        (SalesCount.notListed, milkPremium): askedForOrganic,
      }),
    );

    test('swaps the weakest product for one shoppers keep asking for', () {
      // Value milk earns (0.99 - 0.61) × 2 a day; organic milk would earn
      // (1.58 - 1.05) × 20, priced halfway between 1.47 and the player's 1.69.
      expect(decide(rivalView(20)), [
        'DelistProduct(actor: 1, store: 1, product: 0)',
        'ListProduct(actor: 1, store: 1, product: 1, price: 1.58)',
        'PlaceOrder(actor: 1, store: 1, supplier: 0, lines: 1×160)',
      ]);
    });

    test('keeps the assortment unless the challenger is clearly better', () {
      expect(decide(rivalView(1)), isNot(contains(startsWith('ListProduct'))));
    });
  });

  group('in a simulation', () {
    final aiContent = loadScenario(aiScenarioJson);

    test('AI owners act each day without filling the command log', () {
      final simulation = Simulation.newGame(aiContent, seed: 1);
      expect(simulation.policies.keys, [rival]);
      final result = simulation.step();
      expect(result.rejections, isEmpty);
      expect(simulation.commandLog, isEmpty);
      final order = simulation.world.orders.single;
      expect((order.store, order.supplier), (rivalStore, bulk));
      expect(order.lines.single.quantity, 80);
    });

    test('an observation shows its own stores in full', () {
      final simulation = Simulation.newGame(aiContent, seed: 1)..step();
      final seen = simulation.observe(rival);
      expect(seen.today, start + 1);
      final company = seen.companies.single;
      expect(company.id, CompanyId(1));
      expect(company.committed, Money.parse('44.00')); // 80 × 0.55 on order
      final store = company.stores.single;
      expect(store.id, rivalStore);
      expect(store.onOrder, [80, 0]);
      expect(seen.shelves.map((shelf) => shelf.prices), [
        [Money(95), Money(169)],
        [Money(99), null],
      ]);
    });

    test('recent sales cover the last 28 days', () {
      final simulation = Simulation.newGame(aiContent, seed: 1);
      final sold = <int>[];
      for (var i = 0; i < 40; i++) {
        final day = simulation.step();
        sold.add(
          day.entries
              .where(
                (e) =>
                    e.reason == EntryReason.sale &&
                    e.party.type == PartyType.company &&
                    e.store == rivalStore,
              )
              .fold(0, (sum, e) => sum + e.units),
        );
        if (i == 9) {
          final sales = simulation
              .observe(rival)
              .companies
              .single
              .stores
              .single
              .sales;
          expect(sales.days, 10);
          expect(
            sales.total(SalesCount.sold, milkBudget, 28),
            sold.fold(0, (a, b) => a + b),
          );
        }
      }
      final sales = simulation
          .observe(rival)
          .companies
          .single
          .stores
          .single
          .sales;
      expect(sales.days, salesHistoryDays);
      final lastWeek = sold.skip(33).fold(0, (a, b) => a + b);
      expect(sales.total(SalesCount.sold, milkBudget, 7), lastWeek);
      expect(lastWeek, greaterThan(0));
    });

    void runPlayer(Simulation simulation, int days) {
      for (var i = 0; i < days; i++) {
        scriptedCommands(simulation.today)
            .where((command) => command.actor == player)
            .forEach(simulation.submit);
        simulation.step();
      }
    }

    test('saves and replays continue identically with AI owners', () {
      final straight = Simulation.newGame(aiContent, seed: 5);
      runPlayer(straight, 200);

      final interrupted = Simulation.newGame(aiContent, seed: 5);
      runPlayer(interrupted, 90);
      final resumed = Simulation.load(aiContent, interrupted.save());
      runPlayer(resumed, 110);
      expect(resumed.stateHash(), straight.stateHash());

      final file = straight.save();
      final replayed = Simulation.replay(aiContent, file);
      expect(replayed.stateHash(), straight.stateHash());
      expect(replayed.save().bytes, file.bytes);
    });

    test('a year against the AI produces the committed state hash', () {
      final simulation = Simulation.newGame(aiContent, seed: 20261026);
      runPlayer(simulation, 365);
      expect(simulation.stateHash(), 0xde6255b2);
    });
  });
}
