import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/store.dart';
import 'package:engine/src/systems/sales.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final content = loadScenario(testScenarioJson);

  Simulation quietGame([ContentDb? scenario]) =>
      Simulation.newGame(scenario ?? content, seed: 1, systems: quietSystems);

  Store shop(Simulation simulation) =>
      simulation.world.stores[playerStore.index];

  Money cashOf(Simulation simulation) => simulation
      .world
      .companies[playerCompany.index]
      .accounts[AccountKind.cash];

  /// Steps [days] times and returns the results.
  List<TickResult> advance(Simulation simulation, int days) => [
    for (var i = 0; i < days; i++) simulation.step(),
  ];

  List<JournalEntry> entriesFor(List<TickResult> results, EntryReason reason) =>
      [
        for (final result in results)
          ...result.entries.where((entry) => entry.reason == reason),
      ];

  test('supplier prices apply the factor and volume discount', () {
    final budget = content.products[milkBudget.index];
    final bulkSupplier = content.suppliers[bulk.index];
    expect(bulkSupplier.unitPrice(budget, 48, Fx.one), Money.parse('0.55'));
    expect(
      bulkSupplier.unitPrice(budget, 96, Fx.one),
      Money.parse('0.52'),
    ); // 0.5225
    expect(
      content.suppliers[fresh.index].unitPrice(budget, 12, Fx.one),
      Money.parse('0.61'), // 0.605
    );
  });

  group('orders', () {
    test('are rejected with a reason when invalid', () {
      final simulation = quietGame();
      PlaceOrder order(
        StoreId store,
        SupplierId supplier,
        List<OrderQuantity> lines, {
        PersonId actor = player,
      }) => PlaceOrder(actor, store: store, supplier: supplier, lines: lines);
      final invalid = {
        order(rivalStore, bulk, [(product: milkBudget, quantity: 48)]):
            'notYourStore',
        order(playerStore, SupplierId(9), [
          (product: milkBudget, quantity: 48),
        ]): 'unknownSupplier',
        order(playerStore, bulk, []): 'orderEmpty',
        order(playerStore, fresh, [(product: milkPremium, quantity: 12)]):
            'supplierDoesNotSell',
        order(playerStore, bulk, [(product: milkBudget, quantity: 47)]):
            'belowMinimum',
        order(playerStore, bulk, [
          (product: milkBudget, quantity: 48),
          (product: milkBudget, quantity: 48),
        ]): 'productTwice',
        order(playerStore, bulk, [(product: milkBudget, quantity: 401)]):
            'overCapacity',
        order(rivalStore, bulk, [
          (product: milkPremium, quantity: 48),
        ], actor: rival): 'storeDoesNotList',
      };
      invalid.keys.forEach(simulation.submit);
      final reasons = {
        for (final rejection in simulation.step().rejections)
          rejection.command: rejection.reason.key,
      };
      expect(reasons, invalid);
      expect(simulation.world.orders, isEmpty);
    });

    test('arrive after the lead time and are paid when the invoice is due', () {
      final simulation = quietGame();
      final start = simulation.today;
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 24)],
        ),
      );
      simulation.step();
      expect(shop(simulation).stock[milkBudget.index].units, 0);

      final arrival = simulation.step();
      final lots = shop(simulation).stock[milkBudget.index].lots;
      expect(lots.single.quantity, 24);
      expect(lots.single.unitCost, Money.parse('0.61'));
      expect(lots.single.expiry, start + 11);
      expect(
        arrival.entries.single,
        isA<JournalEntry>()
            .having((e) => e.debit, 'debit', AccountKind.inventory)
            .having((e) => e.credit, 'credit', AccountKind.payables)
            .having((e) => e.amount, 'amount', Money.parse('14.64')),
      );
      final company = simulation.world.companies[playerCompany.index];
      expect(company.payables.single.due, start + 15);

      final opening = cashOf(simulation);
      final beforeDue = advance(simulation, 13);
      expect(entriesFor(beforeDue, EntryReason.supplierPayment), isEmpty);
      final dueDay = simulation.step();
      expect(simulation.today, start + 16);
      expect(dueDay.entries.map((e) => (e.party.type, e.debit, e.credit)), [
        (PartyType.company, AccountKind.payables, AccountKind.cash),
        (PartyType.supplier, AccountKind.cash, AccountKind.revenue),
      ]);
      expect(cashOf(simulation), opening - Money.parse('14.64'));
      expect(company.payables, isEmpty);
    });

    test('with cash-on-delivery terms are paid the day they arrive', () {
      final simulation = quietGame();
      final opening = cashOf(simulation);
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: milkBudget, quantity: 48)],
        ),
      );
      advance(simulation, 3);
      expect(cashOf(simulation), opening);
      final arrival = simulation.step();
      expect(entriesFor([arrival], EntryReason.supplierPayment), hasLength(2));
      expect(cashOf(simulation), opening - Money.parse('26.40'));
    });

    test('refuse units beyond storage and invoice only what was accepted', () {
      final simulation = quietGame();
      final opening = cashOf(simulation);
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [
            (product: milkBudget, quantity: 300),
            (product: milkPremium, quantity: 200),
          ],
        ),
      );
      final arrival = advance(simulation, 4).last;
      expect(shop(simulation).unitsOnHand, 400);
      expect(
        arrival.events.single,
        isA<DeliveryRefused>()
            .having((e) => e.product, 'product', milkPremium)
            .having((e) => e.units, 'units', 100)
            .having((e) => e.reason, 'reason', RefusalReason.storageFull),
      );
      // 300 × 0.52 + 100 × 1.00 (1.05 less 5%, rounded)
      expect(cashOf(simulation), opening - Money.parse('256.00'));
    });

    test('refuse units of products delisted while on order', () {
      final simulation = quietGame();
      final opening = cashOf(simulation);
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: milkPremium, quantity: 48)],
        ),
      );
      simulation
        ..step()
        ..submit(
          DelistProduct(player, store: playerStore, product: milkPremium),
        );
      final results = advance(simulation, 3);
      expect(
        results.last.events.single,
        isA<DeliveryRefused>()
            .having((e) => e.units, 'units', 48)
            .having((e) => e.reason, 'reason', RefusalReason.notListed),
      );
      expect(cashOf(simulation), opening);
    });

    test('that come due without enough cash are retried until paid', () {
      final poorer = loadScenario(
        testScenarioJson.replaceFirst('"cash": "500.00"', '"cash": "10.00"'),
      );
      final simulation = Simulation.newGame(
        poorer,
        seed: 1,
        systems: testSystems,
      );
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: milkBudget, quantity: 96)],
        ),
      );
      final results = advance(simulation, 4);
      expect(results.last.events.single, isA<PaymentOverdue>());
      final company = simulation.world.companies[playerCompany.index];
      expect(company.payables, hasLength(1));

      final later = advance(simulation, 10);
      expect(entriesFor(later, EntryReason.supplierPayment), hasLength(2));
      expect(company.payables, isEmpty);
    });
  });

  test('spoiled lots are written off on their expiry day', () {
    final simulation = quietGame();
    simulation.submit(
      PlaceOrder(
        player,
        store: playerStore,
        supplier: fresh,
        lines: [(product: milkBudget, quantity: 24)],
      ),
    );
    advance(simulation, 11);
    expect(shop(simulation).stock[milkBudget.index].units, 24);
    final expiry = simulation.step();
    expect(shop(simulation).stock[milkBudget.index].units, 0);
    expect(
      expiry.entries.single,
      isA<JournalEntry>()
          .having((e) => e.reason, 'reason', EntryReason.spoilage)
          .having((e) => e.debit, 'debit', AccountKind.writeOffs)
          .having((e) => e.units, 'units', 24)
          .having((e) => e.amount, 'amount', Money.parse('14.64')),
    );
  });

  group('assortment', () {
    test('listing needs a free shelf slot', () {
      final simulation = quietGame();
      final list = ListProduct(
        rival,
        store: rivalStore,
        product: milkPremium,
        price: Money(150),
      );
      simulation.submit(list);
      expect(
        simulation.step().rejections.single.reason.key,
        'shelvesFull',
      );
      simulation
        ..submit(DelistProduct(rival, store: rivalStore, product: milkBudget))
        ..submit(list);
      expect(simulation.step().rejections, isEmpty);
      expect(simulation.world.stores[rivalStore.index].prices, [
        null,
        Money(150),
      ]);
    });

    test('delisting writes off the remaining stock', () {
      final simulation = quietGame();
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 24)],
        ),
      );
      advance(simulation, 2);
      simulation.submit(
        DelistProduct(player, store: playerStore, product: milkBudget),
      );
      final result = simulation.step();
      expect(shop(simulation).prices[milkBudget.index], isNull);
      expect(shop(simulation).stock[milkBudget.index].units, 0);
      expect(
        result.entries.single,
        isA<JournalEntry>()
            .having((e) => e.reason, 'reason', EntryReason.delisting)
            .having((e) => e.amount, 'amount', Money.parse('14.64')),
      );
    });
  });

  test('sales take the oldest lots first and book revenue and cost', () {
    final simulation = quietGame();
    simulation
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 24)],
        ),
      )
      ..submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: bulk,
          lines: [(product: milkBudget, quantity: 96)],
        ),
      );
    advance(simulation, 4);
    final ledger = Ledger(simulation.today);
    final sold = sellUnits(
      simulation.world,
      ledger,
      shop(simulation),
      milkBudget,
      30,
    );
    expect(sold, 30);
    expect(shop(simulation).stock[milkBudget.index].units, 90);
    expect(ledger.entries.map((e) => (e.party.type, e.reason, e.amount)), [
      (PartyType.households, EntryReason.sale, Money.parse('28.50')),
      (PartyType.company, EntryReason.sale, Money.parse('28.50')),
      // 24 × 0.61 + 6 × 0.52
      (PartyType.company, EntryReason.costOfSale, Money.parse('17.76')),
    ]);
    expect(invariantViolations(simulation.world), isEmpty);
  });

  group('invariants', () {
    test('hold through a scripted year that exercises every flow', () {
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      final results = <TickResult>[];
      for (var i = 0; i < 365; i++) {
        scriptedCommands(simulation.today).forEach(simulation.submit);
        results.add(simulation.step());
      }
      final reasons = {
        for (final result in results) ...result.entries.map((e) => e.reason),
      };
      expect(reasons, {
        EntryReason.delivery,
        EntryReason.supplierPayment,
        EntryReason.sale,
        EntryReason.costOfSale,
        EntryReason.spoilage,
        EntryReason.delisting,
      });
      expect(
        results.expand((result) => result.events),
        contains(isA<DeliveryRefused>()),
      );
      expect(invariantViolations(simulation.world), isEmpty);
      final totalCash = simulation.world.parties.fold(
        Money.zero,
        (sum, party) => sum + party.accounts[AccountKind.cash],
      );
      expect(totalCash, Money.parse('104300.00')); // with the bank's
    });

    test('catch stock that changes without a journal entry', () {
      final simulation = quietGame();
      simulation.submit(
        PlaceOrder(
          player,
          store: playerStore,
          supplier: fresh,
          lines: [(product: milkBudget, quantity: 24)],
        ),
      );
      advance(simulation, 2);
      shop(simulation).stock[milkBudget.index].take(5);
      expect(
        invariantViolations(simulation.world),
        contains(contains('inventory account')),
      );
      expect(simulation.step, throwsStateError);
    });
  });
}
