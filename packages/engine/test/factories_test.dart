import 'package:engine/engine.dart';
import 'package:engine/src/state/credit.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/valuation.dart';
import 'package:engine/src/systems/close.dart';
import 'package:engine/src/systems/factories.dart';
import 'package:engine/src/systems/logistics.dart';
import 'package:engine/src/systems/macro.dart';
import 'package:engine/src/systems/operations.dart';
import 'package:engine/src/systems/population.dart';
import 'package:engine/src/systems/report.dart';
import 'package:engine/src/systems/settlement.dart';
import 'package:engine/src/systems/solvency.dart';
import 'package:engine/src/systems/spoilage.dart';
import 'package:engine/src/systems/tick_system.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test scenario with a dairy: it makes both milks, [shiftUnits] a day
/// a shift, for 200 to build over 5 days.
String factoryJson({int shiftUnits = 10, bool acquisitions = false}) {
  var json = testScenarioJson.replaceFirst(
    '"suppliers": [',
    '"factories": { "abroadDays": 2, "freight": "0.04", '
        '"paymentTermsDays": 30, "maxShifts": 3, "kinds": [ '
        '{ "id": "dairy", "name": "Dairy", "category": "milk", '
        '"buildCost": "200.00", "buildDays": 5, "shiftUnits": $shiftUnits, '
        '"shiftWage": "1.00", "site": "15.00", "materials": "0.40", '
        '"leadTimeDays": 1, "minOrderUnits": 12 } ] },\n'
        '  "suppliers": [',
  );
  if (acquisitions) {
    json = json.replaceFirst(
      '"categories": [{ "id": "milk", "name": "Milk" }],',
      '"acquisitions": { "tangibleReturn": "0.08", "capitalization": '
          '"0.33", "distressFloor": "0.5", "fittingsLifeDays": 3650, '
          '"fittingsResidual": "0.25", "buyerReserve": "0.25", '
          '"intervalDays": 180 },\n'
          '  "categories": [{ "id": "milk", "name": "Milk" }],',
    );
  }
  return json;
}

/// The test pipeline, with factories billed before settlement.
const factorySystems = <TickSystem>[
  MacroSystem(),
  PopulationSystem(),
  LogisticsSystem(),
  SpoilageSystem(),
  OperationsSystem(),
  ScriptedDemandSystem(),
  FactorySystem(),
  SettlementSystem(),
  SolvencySystem(),
  CloseSystem(),
  ReportSystem(),
];

const dairy = FactoryKindId(0);
const home = CountryId(0);
const first = FactoryId(0);

void main() {
  (ContentDb, Simulation) start({
    int shiftUnits = 10,
    bool acquisitions = false,
    Map<PersonId, Policy> policies = const {},
  }) {
    final content = loadScenario(
      factoryJson(shiftUnits: shiftUnits, acquisitions: acquisitions),
    );
    return (
      content,
      Simulation.newGame(
        content,
        seed: 3,
        systems: factorySystems,
        policies: policies,
      ),
    );
  }

  List<String> apply(Simulation game, List<Command> commands) {
    commands.forEach(game.submit);
    return [for (final r in game.step().rejections) r.reason.key];
  }

  void run(Simulation game, int days) {
    for (var i = 0; i < days; i++) {
      expect(game.step().rejections, isEmpty);
    }
  }

  BuildFactory build({
    CompanyId? company = playerCompany,
    Money capital = Money.zero,
    int shifts = 1,
  }) => BuildFactory(
    player,
    kind: dairy,
    country: home,
    name: 'Laiterie',
    company: company,
    capital: capital,
    shifts: shifts,
  );

  /// A game whose dairy is making goods.
  (ContentDb, Simulation) making({
    int shiftUnits = 10,
    bool acquisitions = false,
    Map<PersonId, Policy> policies = const {},
  }) {
    final (content, game) = start(
      shiftUnits: shiftUnits,
      acquisitions: acquisitions,
      policies: policies,
    );
    expect(apply(game, [build()]), isEmpty);
    run(game, 4);
    expect(game.observe(player).companies.first.factories.single.making, true);
    return (content, game);
  }

  Money cents(int value) => Money(value);

  group('a factory', () {
    test('loads from the scenario', () {
      final content = loadScenario(factoryJson());
      final kind = content.factories!.kinds.single;
      expect(kind.key, 'dairy');
      expect(kind.shiftUnits, 10);
      expect(kind.exports, isTrue);
      // A kind that names no freight of its own pays the scenario's.
      expect(kind.freight, Fx.parse('0.04'));
      expect(
        content.structure.firstWhere((list) => list.name == 'factories').keys,
        ['dairy'],
      );
      expect(loadScenario(testScenarioJson).factories, isNull);
    });

    test('is built for its cost and makes goods after its build days', () {
      final (_, game) = start();
      final company = game.world.companies[playerCompany.index];
      final before = company.accounts[AccountKind.cash];
      expect(apply(game, [build()]), isEmpty);
      expect(
        company.accounts[AccountKind.cash],
        before - Money.parse('200.00'),
      );
      final view = game.observe(player).companies.first.factories.single;
      expect(view.building, isTrue);
      expect(view.builtFor, Money.parse('200.00'));
      // Bought from the wholesalers while it's being built.
      expect(
        apply(game, [
          PlaceOrder(
            player,
            store: playerStore,
            supplier: bulk,
            lines: [(product: milkBudget, quantity: 48)],
          ),
        ]),
        isEmpty,
      );
      run(game, 3);
      expect(
        game.observe(player).companies.first.factories.single.making,
        true,
      );
      // Made or bought, never both.
      expect(
        apply(game, [
          PlaceOrder(
            player,
            store: playerStore,
            supplier: bulk,
            lines: [(product: milkBudget, quantity: 48)],
          ),
        ]),
        ['madeInHouse'],
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('is refused without the cash, a name or a sensible shift', () {
      final (_, game) = start();
      expect(
        apply(game, [
          BuildFactory(
            player,
            kind: dairy,
            country: home,
            name: 'Laiterie',
            company: playerCompany,
            shifts: 4,
          ),
          BuildFactory(player, kind: dairy, country: home, name: ''),
          // A new company with too little capital.
          BuildFactory(
            player,
            kind: dairy,
            country: home,
            name: 'Laiterie',
            capital: Money.parse('100.00'),
          ),
          BuildFactory(
            rival,
            kind: dairy,
            country: home,
            name: 'Laiterie',
            company: playerCompany,
          ),
        ]),
        ['shiftsRange', 'nameRule', 'cannotPayFactory', 'notYourCompany'],
      );
      expect(game.world.factories, isEmpty);
    });

    test('charges the shops what their wholesalers would', () {
      final (content, game) = making();
      final company = game.world.companies[playerCompany.index];
      expect(
        apply(game, [
          OrderFromFactory(
            player,
            store: playerStore,
            factory: first,
            lines: [
              (product: milkBudget, quantity: 96),
              (product: milkPremium, quantity: 24),
            ],
          ),
        ]),
        isEmpty,
      );
      final order = game.world.orders.single;
      expect(order.factory, first);
      // 96 budget milks are bulk's, 5% off; 24 premium ones are below
      // bulk's minimum, the only one to carry them.
      expect(order.lines[0].unitPrice, cents(52));
      expect(order.lines[1].unitPrice, cents(105));
      expect(order.lines[0].made, 96);
      expect(order.lines[0].from, bulk);
      final stock = game.world.stores[playerStore.index].unitsOnHand;
      game.step();
      expect(game.world.orders, isEmpty);
      expect(
        game.world.stores[playerStore.index].unitsOnHand,
        greaterThan(stock),
      );
      final value = cents(96 * 52 + 24 * 105);
      // The shop owes the factory's company, here its own, in 30 days.
      expect(
        company.payables
            .where((p) => p.creditorAccount == AccountKind.receivables)
            .single
            .amount,
        value,
      );
      expect(company.accounts[AccountKind.receivables], value);
      final report = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!;
      expect(report.madeForOwn(milkBudget), 96);
      expect(report.ownGoods(milkBudget), cents(96 * 52));
      expect(report.materials(milkBudget), cents(96 * 22));
      expect(report.materials(milkPremium), cents(24 * 42));
      // Its sales to its owner's shops aren't sales.
      expect(
        report.profit,
        value -
            cents(96 * 22 + 24 * 42) -
            report.wages -
            report.occupancy -
            report.freight,
      );
      expect(content.factories, isNotNull);
      expect(invariantViolations(game.world), isEmpty);
      // Paid on its terms.
      run(game, 31);
      expect(company.accounts[AccountKind.receivables], Money.zero);
    });

    test('makes up to its capacity; the rest is bought in', () {
      final (_, game) = making();
      final view = game.observe(player).companies.first.factories.single;
      // January: ten a day for 31 days.
      expect(view.monthCapacity, 310);
      expect(
        apply(game, [
          OrderFromFactory(
            player,
            store: playerStore,
            factory: first,
            lines: [(product: milkBudget, quantity: 350)],
          ),
        ]),
        isEmpty,
      );
      expect(game.world.orders.single.lines.single.made, 310);
      Money paidToBulk() =>
          -game.world.suppliers[bulk.index].accounts[AccountKind.revenue];
      final before = paidToBulk();
      game.step();
      // The wholesaler bills what it delivered, cash on delivery.
      expect(paidToBulk() - before, cents(40 * 52));
      final report = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!;
      expect(report.boughtIn(milkBudget), 40);
      expect(report.madeForOwn(milkBudget), 310);
      expect(
        game.observe(player).companies.first.factories.single.capacityLeft,
        0,
      );
    });

    test('pays its shifts every day and its site every month', () {
      final (_, game) = making();
      game.step();
      var report = game
          .reports(playerCompany, ReportPeriod.week)
          .last
          .factory(first)!;
      expect(report.wages.cents, greaterThan(0));
      expect(
        apply(game, [SetFactoryShifts(player, factory: first, shifts: 3)]),
        isEmpty,
      );
      final wages = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!
          .wages;
      game.step();
      final after = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!
          .wages;
      expect(after - wages, Money.parse('3.00'));
      expect(
        apply(game, [SetFactoryShifts(player, factory: first, shifts: 9)]),
        ['shiftsRange'],
      );
      // The site is billed on the first of February.
      while (!game.today.isFirstOfMonth) {
        game.step();
      }
      game.step();
      report = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!;
      expect(report.site, Money.parse('15.00'));
    });

    test('sells to rivals only if its owner says, from what it can spare', () {
      final (_, game) = making();
      OrderFromFactory rivalOrder(int units) => OrderFromFactory(
        rival,
        store: rivalStore,
        factory: first,
        lines: [(product: milkBudget, quantity: units)],
      );
      expect(apply(game, [rivalOrder(24)]), ['factoryExclusive']);
      expect(
        apply(game, [
          SetFactoryTerms(
            player,
            factory: first,
            serves: const [true],
            rivalDiscount: Fx.parse('0.10'),
          ),
        ]),
        isEmpty,
      );
      expect(game.observe(rival).offers.single.discount, Fx.parse('0.10'));
      // Stopped, it has nothing to spare.
      expect(
        apply(game, [SetFactoryShifts(player, factory: first, shifts: 0)]),
        isEmpty,
      );
      expect(apply(game, [rivalOrder(24)]), ['factoryFull']);
      expect(
        apply(game, [SetFactoryShifts(player, factory: first, shifts: 1)]),
        isEmpty,
      );
      expect(apply(game, [rivalOrder(24)]), isEmpty);
      // Fresh charges 61 cents for 24; the factory 10% less.
      expect(game.world.orders.single.lines.single.unitPrice, cents(55));
      game.step();
      final report = game
          .reports(playerCompany, ReportPeriod.month)
          .last
          .factory(first)!;
      expect(report.madeForRivals(milkBudget), 24);
      expect(report.rivalSales(milkBudget), cents(24 * 55));
      expect(
        game.world.companies[1].payables
            .where((p) => p.creditor == game.world.companies[0].partyRef)
            .single
            .amount,
        cents(24 * 55),
      );
      expect(invariantViolations(game.world), isEmpty);
      expect(
        apply(game, [
          SetFactoryTerms(
            player,
            factory: first,
            serves: const [true],
            rivalDiscount: Fx.parse('0.90'),
          ),
          SetFactoryTerms(player, factory: first, serves: const [false]),
        ]),
        ['rivalDiscountRange', 'servesItsCountry'],
      );
    });

    test('is what a rival run by the retail policy buys from when cheaper', () {
      final content = loadScenario(factoryJson(shiftUnits: 30));
      final (_, game) = making(
        shiftUnits: 30,
        policies: {rival: RetailPolicy(content.strategies.single)},
      );
      expect(
        apply(game, [
          SetFactoryTerms(
            player,
            factory: first,
            serves: const [true],
            rivalDiscount: Fx.parse('0.20'),
          ),
        ]),
        isEmpty,
      );
      for (var i = 0; i < 30; i++) {
        game.step();
      }
      final made = game
          .reports(playerCompany, ReportPeriod.month)
          .fold(
            0,
            (sum, report) =>
                sum + (report.factory(first)?.madeForRivals(milkBudget) ?? 0),
          );
      expect(made, greaterThan(0));
      expect(invariantViolations(game.world), isEmpty);
    });

    test('closes for good, and its orders come from the wholesaler', () {
      final (_, game) = making();
      expect(
        apply(game, [
          OrderFromFactory(
            player,
            store: playerStore,
            factory: first,
            lines: [(product: milkBudget, quantity: 48)],
          ),
        ]),
        isEmpty,
      );
      Money paidToBulk() =>
          -game.world.suppliers[bulk.index].accounts[AccountKind.revenue];
      final before = paidToBulk();
      expect(apply(game, [CloseFactory(player, factory: first)]), isEmpty);
      final company = game.world.companies[playerCompany.index];
      expect(paidToBulk() - before, cents(48 * 55));
      expect(company.accounts[AccountKind.receivables], Money.zero);
      expect(
        apply(game, [
          PlaceOrder(
            player,
            store: playerStore,
            supplier: bulk,
            lines: [(product: milkBudget, quantity: 48)],
          ),
          SetFactoryShifts(player, factory: first, shifts: 2),
        ]),
        ['factoryClosed'],
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('closes with its company, which collects what it is owed', () {
      final (_, game) = start();
      // A company of its own, left with nothing once it is built.
      expect(
        apply(game, [build(company: null, capital: Money.parse('200.00'))]),
        isEmpty,
      );
      run(game, 4);
      final factoryCompany = game.world.factories.single.company;
      expect(
        apply(game, [
          OrderFromFactory(
            player,
            store: playerStore,
            factory: first,
            lines: [(product: milkBudget, quantity: 48)],
          ),
        ]),
        isEmpty,
      );
      var wound = false;
      for (var i = 0; i < 120 && !wound; i++) {
        game.step();
        wound = !game.world.companies[factoryCompany.index].isActive;
      }
      expect(wound, isTrue);
      expect(game.world.factories.single.status, FactoryStatus.closed);
      final shop = game.world.companies[playerCompany.index];
      expect(
        shop.payables.where(
          (p) =>
              p.creditor == game.world.companies[factoryCompany.index].partyRef,
        ),
        isEmpty,
      );
      expect(invariantViolations(game.world), isEmpty);
    });

    test('earns against buying, which the bank and buyers count', () {
      final (content, game) = making(acquisitions: true);
      for (var day = 0; day < 40; day++) {
        if (day % 3 == 0) {
          game.submit(
            OrderFromFactory(
              player,
              store: playerStore,
              factory: first,
              lines: [(product: milkBudget, quantity: 48)],
            ),
          );
        }
        game.step();
      }
      final factory = game.world.factories.single;
      final earnings = factoryEarnings(game.world, content, factory)!;
      final stores =
          companyEarnings(game.world, content, playerCompany) - earnings;
      expect(earnings, isNot(Money.zero));
      expect(
        companyEarnings(game.world, content, playerCompany),
        stores + earnings,
      );
      final value = valueFactory(game.world, content, factory)!;
      expect(value.earnings, earnings);
      final view = game.observe(player).companies.first.factories.single;
      expect(view.earnings, earnings);
      expect(view.recentOwnUnits, greaterThan(0));
    });

    test('estimates what it would make and earn for the shops', () {
      final (content, game) = start();
      runScripted(game, 30);
      final outlook = factoryOutlook(
        game.observe(player),
        content,
        dairy,
        home,
      );
      expect(outlook.shops, 1);
      expect(outlook.units, greaterThan(0));
      expect(outlook.plans.map((plan) => plan.shifts), [1, 2, 3]);
      expect(outlook.buildCost, Money.parse('200.00'));
      for (final plan in outlook.plans) {
        expect(plan.made + plan.boughtIn, outlook.units);
      }
      expect(outlook.recession.made, lessThanOrEqualTo(outlook.best.made));
    });

    test('saves, loads and replays to the same world', () {
      final (content, game) = making(shiftUnits: 30);
      game.submit(
        SetFactoryTerms(
          player,
          factory: first,
          serves: const [true],
          rivalDiscount: Fx.parse('0.05'),
        ),
      );
      for (var day = 0; day < 45; day++) {
        if (day % 4 == 0) {
          game.submit(
            OrderFromFactory(
              player,
              store: playerStore,
              factory: first,
              lines: [(product: milkPremium, quantity: 24)],
            ),
          );
        }
        game.step();
      }
      final save = game.save();
      final loaded = Simulation.load(content, save, systems: factorySystems);
      expect(loaded.stateHash(), game.stateHash());
      final replayed = Simulation.replay(
        content,
        save,
        systems: factorySystems,
      );
      expect(replayed.stateHash(), game.stateHash());
      for (var day = 0; day < 10; day++) {
        game.step();
        loaded.step();
      }
      expect(loaded.stateHash(), game.stateHash());
    });
  });
}
