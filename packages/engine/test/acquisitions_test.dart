import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario where businesses change hands, and optionally with
/// [taxes], wages of [slotWage] a slot, a rival who expands and has
/// [rivalCash] and [rivalCompanyCash], a player with [playerCash], and a
/// passive shopkeeper trading on the lane.
String tradingJson({
  bool taxes = false,
  String slotWage = '0.00',
  String rivalCash = '2000.00',
  String rivalCompanyCash = '800.00',
  String playerCash = '1000.00',
  bool expanding = false,
  bool shopkeeper = false,
}) {
  var json = testScenarioJson
      .replaceFirst(
        '"categories": [{ "id": "milk", "name": "Milk" }],',
        '"acquisitions": { "tangibleReturn": "0.08", "capitalization": '
            '"0.33", "distressFloor": "0.5", "fittingsLifeDays": 3650, '
            '"fittingsResidual": "0.25", "buyerReserve": "0.25", '
            '"intervalDays": 180 },\n'
            '${taxes ? '"taxes": { "reducedRate": "0.15", "reducedLimit": "100.00", "corporateRate": "0.25", "dividendRate": "0.30" },\n' : ''}'
            '  "categories": [{ "id": "milk", "name": "Milk" }],',
      )
      .replaceFirst('"slotWage": "0.00"', '"slotWage": "$slotWage"')
      .replaceFirst(
        '"name": "Rival", "cash": "2000.00" }',
        '"name": "Rival", "cash": "$rivalCash"'
            '${expanding ? ', "strategy": "steady"' : ''} }',
      )
      .replaceFirst(
        '"name": "Player", "cash": "1000.00"',
        '"name": "Player", "cash": "$playerCash"',
      )
      .replaceFirst(
        '"owner": "rival", "cash": "800.00"',
        '"owner": "rival", "cash": "$rivalCompanyCash"',
      );
  if (expanding) {
    json = json.replaceFirst(
      '"expansionPaybackMonths": 0,',
      '"expansionPaybackMonths": 24,',
    );
  }
  if (shopkeeper) {
    json = json
        .replaceFirst(
          '{ "id": "player", "name": "Player",',
          '{ "id": "keeper", "name": "Keeper", "cash": "0.00" },\n'
              '    { "id": "player", "name": "Player",',
        )
        .replaceFirst(
          '{ "id": "player_co",',
          '{ "id": "keeper_co", "name": "Keeper Co", "owner": "keeper", '
              '"cash": "5000.00" },\n    { "id": "player_co",',
        )
        .replaceFirst(
          '{ "id": "player_store",',
          '{ "id": "keeper_store", "name": "Keeper Store", "company": '
              '"keeper_co", "site": "lane", "staff": { "morning": 1 }, '
              '"prices": { "milk_budget": "0.99" } },\n    '
              '{ "id": "player_store",',
        );
  }
  return json;
}

void main() {
  group('asking prices', () {
    test('a new store asks what it holds; a trading one adds three years of '
        'what it earns beyond a fair return on that', () {
      final content = loadScenario(tradingJson());
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      final opening = simulation.observe(player).valuations[playerStore.index]!;
      // The corner cost 300.00 to fit out, and nothing is in stock yet.
      expect(opening, (
        stock: Money.zero,
        fittings: Money.parse('300.00'),
        earnings: Money.zero,
        price: Money.parse('300.00'),
      ));
      runScripted(simulation, 60);
      final value = simulation.observe(player).valuations[playerStore.index]!;
      // Sixty days wear off 60/3650 of three quarters of the fittings.
      expect(value.fittings, Money.parse('296.31'));
      expect(value.earnings.cents, greaterThan(100000));
      final held = value.stock + value.fittings;
      final excess = value.earnings - held.times(Fx.parse('0.08'));
      expect(
        ((value.price - held).times(Fx.parse('0.33')) - excess).cents.abs(),
        lessThan(10),
      );
    });

    test('a store losing money asks half what it holds', () {
      final simulation = Simulation.newGame(
        loadScenario(tradingJson(slotWage: '50.00')),
        seed: 1,
        systems: testSystems,
      );
      // Before the unpaid wages wind the company up.
      runScripted(simulation, 29);
      final value = simulation.observe(player).valuations[playerStore.index]!;
      expect(value.earnings.isNegative, isTrue);
      expect(
        value.price,
        (value.stock + value.fittings).times(Fx.parse('0.5')),
      );
    });

    test('a company asks its stores plus its cash less its debts', () {
      final content = loadScenario(tradingJson());
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      runScripted(simulation, 30);
      simulation
        ..submit(
          TakeLoan(
            rival,
            company: CompanyId(1),
            amount: Money.parse('400.00'),
            termMonths: 12,
            guarantee: true,
          ),
        )
        ..step();
      final view = simulation.observe(player);
      final company = simulation.world.companies[1];
      expect(company.accounts[AccountKind.loans].isNegative, isTrue);
      expect(
        view.companyPrices[1],
        company.accounts[AccountKind.cash] +
            company.accounts[AccountKind.payables] +
            company.accounts[AccountKind.loans] +
            view.valuations[rivalStore.index]!.price,
      );
      expect(view.companyOwners, [player, rival]);
    });

    test('a company owing more than it is worth asks a symbolic euro', () {
      final simulation = Simulation.newGame(
        loadScenario(tradingJson(slotWage: '50.00')),
        seed: 1,
        systems: quietSystems,
        policies: const {},
      );
      for (var i = 0; i < 10; i++) {
        simulation.step();
      }
      expect(simulation.world.companies[1].payables, isNotEmpty);
      expect(simulation.observe(player).companyPrices[1], symbolicPrice);
    });

    test('nothing is priced where businesses never change hands', () {
      final simulation = Simulation.newGame(
        loadScenario(testScenarioJson),
        seed: 1,
      )..step();
      final view = simulation.observe(player);
      expect(view.valuations, [null, null]);
      expect(view.companyPrices, [null, null]);
      simulation
        ..submit(SellStore(player, store: playerStore))
        ..submit(BuyCompany(player, company: CompanyId(1)));
      expect(
        simulation.step().rejections.map((r) => r.reason.key),
        everyElement('nothingForSale'),
      );
    });
  });

  group('buying and selling', () {
    test('the player buys a rival store with its stock, staff and orders on '
        'the way, and the rival books its gain', () {
      final content = loadScenario(tradingJson(playerCash: '100000.00'));
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      runScripted(simulation, 31);
      simulation.submit(
        InjectCapital(
          player,
          company: playerCompany,
          amount: Money.parse('50000.00'),
        ),
      );
      simulation.step();
      final world = simulation.world;
      final store = world.stores[rivalStore.index];
      final price = simulation
          .observe(player)
          .valuations[rivalStore.index]!
          .price;
      final stock = store.stock.fold(Money.zero, (sum, s) => sum + s.value);
      final result =
          (simulation..submit(
                BuyStore(player, store: rivalStore, company: playerCompany),
              ))
              .step();
      expect(result.rejections, isEmpty);
      expect(store.company, playerCompany);
      expect(store.acquiredOn, Day(simulation.today.number - 1));
      expect(store.boughtFor, price - stock);
      final buyer = world.companies[0].accounts;
      final seller = world.companies[1].accounts;
      expect(buyer[AccountKind.businessAssets], price - stock);
      expect(seller[AccountKind.disposals], -(price - stock));
      // The day's trading moved cash too, so look at the sale's entries.
      final payment = result.entries.firstWhere(
        (e) => e.reason == EntryReason.storeSale,
      );
      expect(
        (payment.party, payment.debit, payment.amount),
        (world.companies[0].partyRef, AccountKind.businessAssets, price),
      );
      final view = simulation.observe(player).companies.first;
      expect(view.stores.map((s) => s.id), [playerStore, rivalStore]);
      expect(
        view.orders.where((o) => o.store == rivalStore).length,
        world.orders.where((o) => o.store == rivalStore).length,
      );
      expect(simulation.observe(rival).companies.single.stores, isEmpty);
      expect(invariantViolations(world), isEmpty);
      // It is the player's now: the rival can't take it back.
      simulation.submit(
        BuyStore(rival, store: rivalStore, company: CompanyId(1)),
      );
      expect(
        simulation.step().rejections.single.reason.key,
        'ownerNotSelling',
      );
    });

    test("only the player sells the player's stores", () {
      final simulation = Simulation.newGame(
        loadScenario(tradingJson(rivalCash: '100000.00')),
        seed: 1,
        systems: testSystems,
      );
      runScripted(simulation, 30);
      simulation
        ..submit(
          InjectCapital(
            rival,
            company: CompanyId(1),
            amount: Money.parse('90000.00'),
          ),
        )
        ..submit(BuyStore(rival, store: playerStore, company: CompanyId(1)));
      expect(
        simulation.step().rejections.single.reason.key,
        'ownerNotSelling',
      );
    });

    test('selling goes to the AI owner of its format best able to pay, who '
        'puts in what its company lacks', () {
      final content = loadScenario(
        tradingJson(
          rivalCash: '50000.00',
          rivalCompanyCash: '100.00',
          expanding: true,
        ),
      );
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: quietSystems,
        policies: const {},
      );
      for (var i = 0; i < 40; i++) {
        simulation.step();
      }
      final view = simulation.observe(player);
      final store = view.companies.single.stores.single;
      expect(store.buyer, CompanyId(1));
      final price = view.valuations[playerStore.index]!.price;
      final rivalCash =
          simulation.world.persons[rival.index].accounts[AccountKind.cash];
      final result = (simulation..submit(SellStore(player, store: playerStore)))
          .step();
      expect(result.rejections, isEmpty);
      final world = simulation.world;
      expect(world.stores[playerStore.index].company, CompanyId(1));
      // The rival's company had 100.00; the rival topped it up to the price
      // and a quarter more.
      final injected =
          rivalCash - world.persons[rival.index].accounts[AccountKind.cash];
      expect(
        injected,
        price + price.times(Fx.parse('0.25')) - Money.parse('100.00'),
      );
      expect(
        world.companies[0].accounts[AccountKind.cash],
        Money.parse('500.00') + price,
      );
      // No stock, nothing paid before: the whole price is a gain.
      expect(world.companies[0].accounts[AccountKind.disposals], -price);
      expect(
        simulation
            .reports(playerCompany, ReportPeriod.month)
            .last
            .flow(AccountKind.disposals),
        -price,
      );
      expect(invariantViolations(world), isEmpty);
    });

    test('no sale without a buyer who can pay', () {
      final simulation = Simulation.newGame(
        loadScenario(
          tradingJson(
            expanding: true,
            rivalCash: '0.00',
            rivalCompanyCash: '0.00',
          ),
        ),
        seed: 1,
        systems: quietSystems,
        policies: const {},
      );
      for (var i = 0; i < 40; i++) {
        simulation.step();
      }
      expect(
        simulation.observe(player).companies.single.stores.single.buyer,
        isNull,
      );
      simulation.submit(SellStore(player, store: playerStore));
      expect(
        simulation.step().rejections.single.reason.key,
        'noBuyer',
      );
    });

    test('the player buys a whole company with its stores, cash and debts; '
        'the seller pays the flat tax on the gain', () {
      final content = loadScenario(
        tradingJson(taxes: true, playerCash: '100000.00'),
      );
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      runScripted(simulation, 30);
      simulation
        ..submit(
          TakeLoan(
            rival,
            company: CompanyId(1),
            amount: Money.parse('400.00'),
            termMonths: 12,
            guarantee: true,
          ),
        )
        ..step();
      final world = simulation.world;
      final price = simulation.observe(player).companyPrices[1]!;
      final playerCash = world.persons[player.index].accounts[AccountKind.cash];
      final rivalCash = world.persons[rival.index].accounts[AccountKind.cash];
      final result =
          (simulation..submit(BuyCompany(player, company: CompanyId(1))))
              .step();
      expect(result.rejections, isEmpty);
      final company = world.companies[1];
      expect(company.owner, player);
      expect(company.injected, price);
      expect(
        world.persons[player.index].accounts[AccountKind.cash],
        playerCash - price,
      );
      expect(
        world.persons[player.index].accounts[AccountKind.investments],
        price,
      );
      // The rival had put nothing in: all of it is a gain, taxed at 30%.
      final tax = price.times(Fx.parse('0.30'));
      expect(
        world.persons[rival.index].accounts[AccountKind.cash],
        rivalCash + price - tax,
      );
      expect(world.government.accounts[AccountKind.cash], tax);
      expect(world.loans.single.guarantor, player);
      expect(simulation.observe(player).companies.map((c) => c.id), [
        playerCompany,
        CompanyId(1),
      ]);
      expect(simulation.observe(rival).companies, isEmpty);
      expect(invariantViolations(world), isEmpty);
    });

    test('a company wound up sells its stores to whoever can buy them', () {
      final content = loadScenario(
        tradingJson(
          slotWage: '50.00',
          rivalCash: '50000.00',
          rivalCompanyCash: '50000.00',
          expanding: true,
        ),
      );
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: quietSystems,
        policies: const {},
      );
      final sold = <StoreSold>[];
      for (var i = 0; i < 60 && sold.isEmpty; i++) {
        sold.addAll(simulation.step().events.whereType<StoreSold>());
      }
      final world = simulation.world;
      expect(sold.single.store, playerStore);
      expect(sold.single.buyer, CompanyId(1));
      expect(world.companies[0].isActive, isFalse);
      expect(world.stores[playerStore.index].isTrading, isTrue);
      expect(world.stores[playerStore.index].company, CompanyId(1));
      expect(invariantViolations(world), isEmpty);
    });
  });

  test("an expanding owner buys a struggling rival of its format after a "
      "year, but never the player's", () {
    final content = loadScenario(
      tradingJson(rivalCash: '50000.00', expanding: true, shopkeeper: true),
    );
    final keeperStore = StoreId(0);
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: testSystems,
    );
    expect(simulation.world.stores[keeperStore.index].name, 'Keeper Store');
    final rivalCompany = simulation.world.companies
        .firstWhere((c) => c.name == 'Rival Co')
        .id;
    Day? bought;
    for (var i = 0; i < 450 && bought == null; i++) {
      simulation.step();
      if (simulation.world.stores[keeperStore.index].company == rivalCompany) {
        bought = simulation.today;
      }
    }
    expect(bought, isNotNull);
    expect(bought!.number - content.startDay.number, greaterThan(365));
    final players = simulation.world.stores.where(
      (s) =>
          simulation.world.companies[s.company.index].owner == content.player,
    );
    expect(players, isNotEmpty);
    expect(invariantViolations(simulation.world), isEmpty);
  });
}
