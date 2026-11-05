import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final content = loadScenario(testScenarioJson);
  final start = content.startDay;

  /// A game without demand: money only moves through commands, deliveries,
  /// rent and loans.
  Simulation quietGame([ContentDb? scenario]) =>
      Simulation.newGame(scenario ?? content, seed: 1, systems: quietSystems);

  List<TickResult> advance(Simulation simulation, int days) => [
    for (var i = 0; i < days; i++) simulation.step(),
  ];

  /// Applies [commands] in the next step and returns the rejection reasons.
  List<String> apply(Simulation simulation, List<Command> commands) {
    commands.forEach(simulation.submit);
    return [
      for (final rejection in simulation.step().rejections)
        rejection.reason.key,
    ];
  }

  Money cash(LedgerParty party) => party.accounts[AccountKind.cash];

  group('owner money', () {
    test('capital moves from the owner into the company', () {
      final simulation = quietGame();
      final world = simulation.world;
      expect(
        apply(simulation, [
          InjectCapital(
            player,
            company: playerCompany,
            amount: Money.parse('400.00'),
          ),
          InjectCapital(
            player,
            company: playerCompany,
            amount: Money.parse('2000.00'),
          ),
          InjectCapital(player, company: CompanyId(1), amount: Money(100)),
          InjectCapital(player, company: playerCompany, amount: Money.zero),
        ]),
        [
          'notEnoughPersonalCash',
          'notYourCompany',
          'amountNotPositive',
        ],
      );
      final company = world.companies[playerCompany.index];
      expect(cash(world.persons[player.index]), Money.parse('600.00'));
      expect(cash(company), Money.parse('900.00'));
      expect(company.injected, Money.parse('400.00'));
      expect(
        world.persons[player.index].accounts[AccountKind.investments],
        Money.parse('400.00'),
      );
    });

    test('dividends come only out of retained profits', () {
      final simulation = Simulation.newGame(
        content,
        seed: 1,
        systems: testSystems,
      );
      expect(
        apply(simulation, [
          PayDividend(player, company: playerCompany, amount: Money(100)),
        ]),
        ['dividendsFromProfits'],
      );
      runScripted(simulation, 60);
      final company = simulation.world.companies[playerCompany.index];
      final retained = company.accounts.retainedEarnings;
      expect(retained.cents, greaterThan(0));
      expect(cash(company).cents, greaterThanOrEqualTo(retained.cents));
      final before = cash(simulation.world.persons[player.index]);
      expect(
        apply(simulation, [
          PayDividend(player, company: playerCompany, amount: retained),
          PayDividend(player, company: playerCompany, amount: Money(1)),
        ]),
        ['dividendsFromProfits'],
      );
      expect(cash(simulation.world.persons[player.index]), before + retained);
    });
  });

  group('loans', () {
    TakeLoan loan(Money amount, {bool guarantee = true, int months = 12}) =>
        TakeLoan(
          player,
          company: playerCompany,
          amount: amount,
          termMonths: months,
          guarantee: guarantee,
        );

    test('need a guarantee the owner can back while the company is small', () {
      final simulation = quietGame();
      expect(
        apply(simulation, [
          loan(Money.parse('1500.00')),
          loan(Money.parse('600.00')),
          loan(Money.parse('100.00'), guarantee: false),
          loan(Money.parse('100.00'), months: 0),
        ]),
        [
          'cannotBackGuarantee',
          'bankWantsGuarantee',
          'termRange',
        ],
      );
      final world = simulation.world;
      final taken = world.loans.single;
      expect(taken.rate, Fx.parse('0.07')); // 5% base + 2% guaranteed
      expect(taken.guarantor, player);
      expect(cash(world.companies[playerCompany.index]), Money(200000));
      expect(world.bank.accounts[AccountKind.loans], Money(150000));
    });

    test('are billed on the first of each month and paid if cash allows', () {
      final simulation = quietGame();
      apply(simulation, [loan(Money.parse('1200.00'))]);
      final firstOfFebruary = advance(simulation, 31).last;
      expect(firstOfFebruary.day, Day.parse('2026-02-01'));
      final payments = [
        for (final entry in firstOfFebruary.entries)
          if (entry.party.type == PartyType.bank) (entry.reason, entry.amount),
      ];
      // 1200.00 × 7% × 31 / 365 days of interest, and 1200.00 / 12.
      expect(payments, [
        (EntryReason.interest, Money.parse('7.13')),
        (EntryReason.loanRepayment, Money.parse('100.00')),
      ]);
      final taken = simulation.world.loans.single;
      expect(taken.outstanding, Money.parse('1100.00'));
      expect(taken.installmentsLeft, 11);
    });

    test('can be repaid early with the interest accrued', () {
      final simulation = quietGame();
      apply(simulation, [loan(Money.parse('1200.00'))]);
      advance(simulation, 9);
      final company = simulation.world.companies[playerCompany.index];
      final before = cash(company);
      expect(
        apply(simulation, [
          RepayLoan(player, loan: 1, amount: Money.parse('500.00')),
          RepayLoan(player, loan: 1, amount: Money.parse('5000.00')),
          RepayLoan(player, loan: 9, amount: Money(1)),
        ]),
        ['moreThanLoan', 'unknownLoan'],
      );
      // Ten days at 7% on 1200.00 is 2.30.
      expect(cash(company), before - Money.parse('502.30'));
      expect(simulation.world.loans.single.outstanding, Money(70000));
    });
  });

  group('stores', () {
    test('open on a vacant site after the fit-out and pay rent monthly', () {
      final simulation = quietGame();
      final world = simulation.world;
      expect(
        apply(simulation, [
          OpenStore(
            player,
            site: corner,
            name: 'Second',
            company: playerCompany,
          ),
          OpenStore(
            player,
            site: lane,
            name: 'Lane Shop',
            company: playerCompany,
          ),
          OpenStore(rival, site: lane, name: 'Rival Lane'),
        ]),
        ['siteTaken', 'siteTaken'],
      );
      final store = world.stores.last;
      expect(store.id, StoreId(2));
      expect(store.status, StoreStatus.building);
      expect(store.opensOn, start + 5);
      expect(world.cohorts.first.loyalty, hasLength(3));
      // The fit-out, and January's rent: it starts the day the site is taken.
      expect(cash(world.companies[playerCompany.index]), Money.parse('150.00'));
      expect(cash(world.landlords), Money.parse('350.00'));

      advance(simulation, 4);
      expect(store.status, StoreStatus.building);
      advance(simulation, 1);
      expect(store.status, StoreStatus.open);

      final february = advance(simulation, 26).last;
      expect(february.day, Day.parse('2026-02-01'));
      final rent = february.entries.where(
        (e) =>
            e.reason == EntryReason.rent && e.party.type == PartyType.company,
      );
      expect(rent.map((e) => (e.store, e.amount)), [
        (store.id, Money.parse('100.00')), // billed
        (store.id, Money.parse('100.00')), // paid
      ]);
    });

    test('founding a company puts the owner\'s capital in it', () {
      final simulation = quietGame();
      expect(
        apply(simulation, [
          OpenStore(player, site: lane, name: 'Too Poor'),
          OpenStore(
            rival,
            site: lane,
            name: 'Rival Two',
            capital: Money(30000),
          ),
        ]),
        ['cannotPayOpening'],
      );
      final world = simulation.world;
      final founded = world.companies.last;
      expect(founded.name, 'Rival Two');
      expect(founded.owner, rival);
      expect(founded.injected, Money(30000));
      // 300.00 less the 250.00 fit-out; January's 100.00 rent is overdue.
      expect(cash(founded), Money(5000));
      expect(founded.payables.single.reason, EntryReason.rent);
    });

    test('close for good, freeing the site', () {
      final simulation = quietGame();
      apply(simulation, [
        OpenStore(
          player,
          site: lane,
          name: 'Lane Shop',
          company: playerCompany,
        ),
      ]);
      final store = simulation.world.stores.last;
      expect(simulation.observe(rival).vacantSites, isEmpty);
      expect(
        apply(simulation, [
          CloseStore(player, store: store.id),
          CloseStore(player, store: store.id),
          SetPrice(
            player,
            store: store.id,
            product: milkBudget,
            price: Money(1),
          ),
        ]),
        ['storeClosed', 'storeClosed'],
      );
      expect(store.status, StoreStatus.closed);
      expect(simulation.observe(rival).vacantSites, [lane]);
    });
  });

  group('insolvency', () {
    // The player borrows 1000.00 on a guarantee and spends it fitting out a
    // dear site, then can't pay the rent.
    final dearLane = loadScenario(
      testScenarioJson
          .replaceFirst('"cash": "1000.00"', '"cash": "3000.00"')
          .replaceFirst('"rent": "100.00"', '"rent": "600.00"')
          .replaceFirst('"openingCost": "250.00"', '"openingCost": "1400.00"'),
    );

    Simulation failingGame() {
      final simulation = quietGame(dearLane)..step();
      apply(simulation, [
        TakeLoan(
          player,
          company: playerCompany,
          amount: Money.parse('1000.00'),
          termMonths: 12,
          guarantee: true,
        ),
        OpenStore(
          player,
          site: lane,
          name: 'Lane Shop',
          company: playerCompany,
        ),
      ]);
      return simulation;
    }

    test('a company with a bill overdue past the grace period is wound up', () {
      final simulation = failingGame();
      final world = simulation.world;
      final company = world.companies[playerCompany.index];
      final days = advance(simulation, 60);
      expect(company.isActive, isTrue);
      expect(
        days.expand((day) => day.events),
        contains(
          isA<PaymentOverdue>()
              .having((e) => e.reason, 'reason', EntryReason.rent)
              .having((e) => e.due, 'due', Day.parse('2026-02-01')),
        ),
      );

      // February's rent, due on day 31, is 30 days overdue after day 61.
      final windUp = simulation.step();
      expect(windUp.day, Day.parse('2026-03-04'));
      // Two rents of 600.00, March's unpaid principal of 83.33, and the rest
      // of the loan falling due: 3 days of interest and 833.34. The company
      // has 6.00 for its creditors; the guarantor pays the rest of the loan.
      expect(
        windUp.events.whereType<CompanyLiquidated>().single,
        isA<CompanyLiquidated>()
            .having((e) => e.owed, 'owed', Money.parse('2117.15'))
            .having((e) => e.paid, 'paid', Money.parse('6.00'))
            .having((e) => e.guaranteed, 'guaranteed', Money.parse('914.56'))
            .having((e) => e.writtenOff, 'writtenOff', Money.parse('1196.59')),
      );
      expect(company.status, CompanyStatus.liquidated);
      expect(
        world.stores
            .where((s) => s.company == playerCompany)
            .map((s) => s.status),
        everyElement(StoreStatus.closed),
      );
      expect(world.loans, isEmpty);
      expect(world.bank.accounts[AccountKind.loans], Money.zero);
      final owner = world.persons[player.index];
      expect(cash(owner), Money.parse('2085.44'));
      expect(owner.bankruptcies, 1);
      expect(owner.lastBankruptcy, windUp.day);
      expect(invariantViolations(world), isEmpty);
    });

    test('the owner can start again, at a higher rate for a while', () {
      final simulation = failingGame();
      advance(simulation, 61);
      expect(simulation.observe(player).vacantSites, [corner, lane]);
      expect(
        apply(simulation, [
          SetPrice(
            player,
            store: playerStore,
            product: milkBudget,
            price: Money(99),
          ),
          OpenStore(
            player,
            site: corner,
            name: 'Fresh Start',
            capital: Money.parse('500.00'),
          ),
        ]),
        ['storeClosed'],
      );
      final company = simulation.world.companies.last;
      expect(company.name, 'Fresh Start');
      apply(simulation, [
        TakeLoan(
          player,
          company: company.id,
          amount: Money.parse('100.00'),
          termMonths: 12,
          guarantee: true,
        ),
      ]);
      // 5% + 2% for the guarantee + 5% for the recent bankruptcy.
      expect(simulation.world.loans.single.rate, Fx.parse('0.12'));
    });

    test('saves continue identically through a liquidation', () {
      final straight = failingGame();
      advance(straight, 70);
      final interrupted = failingGame();
      advance(interrupted, 40);
      final resumed = Simulation.load(
        dearLane,
        interrupted.save(),
        systems: quietSystems,
      );
      advance(resumed, 30);
      expect(resumed.stateHash(), straight.stateHash());
    });
  });

  test('an AI owner opens a store where it expects a quick payback', () {
    final expanding = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"name": "Rival", "cash": "2000.00" }',
            '"name": "Rival", "cash": "2000.00", "strategy": "steady" }',
          )
          .replaceFirst(
            '"expansionPaybackMonths": 0',
            '"expansionPaybackMonths": 24',
          )
          .replaceFirst(
            '"expansionIntervalDays": 365',
            '"expansionIntervalDays": 0',
          ),
    );
    final simulation = Simulation.newGame(expanding, seed: 1);
    final world = simulation.world;
    // The rival looks for sites on the 10th of each month, once in profit.
    advance(simulation, 9);
    expect(world.stores, hasLength(2));
    simulation.step();
    // 60 households × 0.30 a day, a 0.4 / 1.5 share by location, less 100.00
    // rent: 44.00 a month repays the 250.00 fit-out in 6 months.
    final store = world.stores.last;
    expect(store.site, lane);
    expect(store.company, CompanyId(1));
    expect(store.opensOn, start + 14);
    // It funds the fit-out, three months' rent and two weeks of stock.
    expect(cash(world.persons[rival.index]), Money.parse('1226.00'));
    advance(simulation, 10);
    expect(store.status, StoreStatus.open);
    expect(store.listedProducts, 2);
    expect(
      store.history.at(SalesCount.sold, milkBudget, start + 19),
      greaterThan(0),
    );
    expect(world.stores, hasLength(3), reason: 'no site left to expand to');
  });

  test('a local shopkeeper never opens another store', () {
    final local = loadScenario(
      testScenarioJson
          .replaceFirst(
            '"name": "Rival", "cash": "2000.00" }',
            '"name": "Rival", "cash": "2000.00", "strategy": "steady", '
                '"local": true }',
          )
          .replaceFirst(
            '"expansionPaybackMonths": 0',
            '"expansionPaybackMonths": 24',
          )
          .replaceFirst(
            '"expansionIntervalDays": 365',
            '"expansionIntervalDays": 0',
          ),
    );
    expect(local.persons[rival.index].local, isTrue);
    final simulation = Simulation.newGame(local, seed: 1);
    advance(simulation, 60);
    expect(simulation.world.stores, hasLength(2));
    // It still runs its own store.
    expect(
      simulation.world.stores[rivalStore.index].listedProducts,
      greaterThan(0),
    );
  });
}
