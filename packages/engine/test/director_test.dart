import 'package:engine/engine.dart';
import 'package:engine/src/core/rng.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/policies/director.dart';
import 'package:engine/src/policies/manager.dart';
import 'package:engine/src/policies/retail_policy.dart'
    show Judgment, operatingReserve;
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'acquisitions_test.dart' show tradingJson;
import 'support/fixtures.dart';

const novice = DirectorGradeId(0);
const star = DirectorGradeId(1);
const clerk = ManagerGradeId(0);

/// The test scenario with directors for hire.
String withDirectors(String json) => json.replaceFirst(
  '"suppliers": [',
  '"directors": { "judgmentError": "0.40", "coaching": "0.50", "grades": [\n'
      '    { "id": "novice", "name": "Novice", "skill": "0.50", "salary": "2.00" },\n'
      '    { "id": "star", "name": "Star", "skill": "1.00", "salary": "3.00" }\n'
      '  ] },\n'
      '  "suppliers": [',
);

HireDirector hire({
  DirectorGradeId grade = star,
  Growth growth = Growth.none,
  bool payout = false,
  bool borrows = false,
  CompanyId company = playerCompany,
  StrategyId strategy = steady,
  ManagerGradeId managerGrade = clerk,
}) => HireDirector(
  player,
  company: company,
  grade: grade,
  strategy: strategy,
  managerGrade: managerGrade,
  growth: growth,
  payout: payout,
  borrows: borrows,
);

/// A scenario where owners enlarge and open stores: the player's store has
/// one slot, filled, with organic milk waiting, and the company 5,000.00.
final growing = loadScenario(
  withDirectors(testScenarioJson)
      .replaceFirst(
        '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
        '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
      )
      .replaceFirst('"cash": "500.00" }', '"cash": "5000.00" }')
      .replaceFirst(
        '"shelfSlots": 2, "storageUnits": 400',
        '"shelfSlots": 1, "storageUnits": 400',
      )
      .replaceFirst(
        '"milk_budget": "0.95", "milk_premium": "1.69"',
        '"milk_budget": "0.95"',
      ),
);

/// A scenario where owners open stores: the company has 5,000.00 and the
/// lane is vacant, while the player's store has nothing to grow for.
final opening = loadScenario(
  withDirectors(testScenarioJson)
      .replaceFirst(
        '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
        '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
      )
      .replaceFirst('"cash": "500.00" }', '"cash": "5000.00" }'),
);

void main() {
  final content = loadScenario(withDirectors(testScenarioJson));
  final start = content.startDay;

  List<Memo> memos(Simulation simulation) =>
      simulation.observe(player).companies.first.memos;

  test('loads the grades on offer, or none', () {
    expect(content.directors!.grades.map((grade) => grade.key), [
      'novice',
      'star',
    ]);
    expect(content.directors!.judgmentError, Fx.parse('0.40'));
    expect(loadScenario(testScenarioJson).directors, isNull);
  });

  test('are hired, rebriefed and let go by the owner', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final invalid = {
      hire(grade: const DirectorGradeId(5)): 'unknownDirectorGrade',
      hire(strategy: const StrategyId(3)): 'unknownStrategy',
      hire(managerGrade: const ManagerGradeId(5)): 'unknownManagerGrade',
      hire(company: const CompanyId(1)): 'notYourCompany',
      FireDirector(player, company: playerCompany):
          'noDirector',
    };
    invalid.keys.forEach(simulation.submit);
    simulation.submit(hire(grade: novice));
    final result = simulation.step();
    expect({
      for (final rejection in result.rejections)
        rejection.command: rejection.reason.key,
    }, invalid);
    Director? director() => simulation.observe(player).companies.first.director;
    expect(director()?.grade, novice);
    expect(director()?.hiredOn, start);

    simulation
      ..submit(hire(grade: novice, growth: Growth.open, payout: true))
      ..step();
    expect(director()?.growth, Growth.open);
    expect(director()?.payout, isTrue);
    expect(director()?.hiredOn, start, reason: 'the same director, rebriefed');
    simulation
      ..submit(hire())
      ..step();
    expect(director()?.hiredOn, start + 2, reason: 'a new director');
    simulation
      ..submit(FireDirector(player, company: playerCompany))
      ..step();
    expect(director(), isNull);

    final none = Simulation.newGame(
      loadScenario(testScenarioJson),
      seed: 1,
      systems: quietSystems,
    )..submit(hire());
    expect(none.step().rejections.single.reason.key, 'noDirectors');
  });

  test('are paid daily, at the wage index, and kept in the cushion', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final before = cashCushion(
      simulation.observe(player),
      content,
      simulation.observe(player).companies.first,
    );
    simulation.submit(hire(grade: novice));
    final paid = [
      for (final entry in simulation.step().entries)
        if (entry.reason == EntryReason.salary)
          (entry.party.type, entry.debit, entry.amount, entry.store),
    ];
    expect(paid, [
      (PartyType.company, AccountKind.salaries, Money.parse('2.00'), null),
      // Billed, then paid the same day.
      (PartyType.company, AccountKind.payables, Money.parse('2.00'), null),
      (PartyType.households, AccountKind.cash, Money.parse('2.00'), null),
    ]);
    final view = simulation.observe(player);
    // The clerk the director hired today isn't counted yet.
    expect(
      cashCushion(view, content, view.companies.first) - before,
      Money.parse('2.00').timesInt(defaultCushionDays),
    );
  });

  test('hire a manager for each store without one', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    )..submit(hire());
    simulation
      ..step()
      ..step();
    final manager = simulation
        .observe(player)
        .companies
        .first
        .stores
        .single
        .manager!;
    expect(manager.grade, clerk);
    expect(manager.strategy, steady);
    expect(manager.duties, directorManagerDuties);
    expect(manager.duties[ManagerDuty.investing.index], isFalse);
    expect(memos(simulation), [
      isA<ManagerHired>()
          .having((memo) => memo.day, 'day', start + 1)
          .having((memo) => memo.store, 'store', playerStore)
          .having((memo) => memo.grade, 'grade', clerk),
    ]);
    simulation.step();
    expect(memos(simulation), hasLength(1), reason: 'once');
  });

  test('close a store losing money over its last year, two years after it '
      'opened', () {
    // Rent and no shoppers: a store that only loses money.
    final losing = loadScenario(
      withDirectors(testScenarioJson)
          .replaceFirst(
            '"location": "0.50", "rent": "0.00"',
            '"location": "0.50", "rent": "100.00"',
          )
          .replaceFirst('"cash": "500.00" }', '"cash": "50000.00" }'),
    );
    final simulation = Simulation.newGame(
      losing,
      seed: 1,
      systems: quietSystems,
    )..submit(hire());
    final twoYears = Day.fromDate(2028, 1, 1);
    while (simulation.world.today < twoYears) {
      simulation.step();
    }
    expect(
      simulation.world.stores[playerStore.index].status,
      isNot(StoreStatus.closed),
    );
    simulation.step();
    expect(
      simulation.world.stores[playerStore.index].status,
      StoreStatus.closed,
    );
    final closed = memos(simulation).whereType<StoreClosed>().single;
    expect(closed.day, twoYears);
    expect(closed.store, playerStore);
    expect(closed.sales, Money.zero);
    expect(closed.loss.cents, greaterThan(120000));
  });

  test('enlarge stores only if the brief allows it', () {
    (int, List<Memo>) run(Growth growth) {
      final simulation = Simulation.newGame(growing, seed: 1)
        ..submit(hire(growth: growth));
      for (var i = 0; i < 120; i++) {
        simulation.step();
      }
      return (simulation.world.stores[playerStore.index].area, memos(simulation));
    }

    final (kept, quiet) = run(Growth.none);
    expect(kept, 100);
    expect(quiet.whereType<StoreEnlarged>(), isEmpty);
    final (enlarged, said) = run(Growth.invest);
    expect(enlarged, greaterThan(100));
    expect(said.whereType<StoreEnlarged>(), isNotEmpty);
  });

  group('on the first of the month', () {
    // The first of February, the director hired on the first of January.
    (Simulation, Observation) firstOfFebruary(Director brief) {
      final simulation = Simulation.newGame(opening, seed: 1)
        ..submit(
          hire(
            grade: brief.grade,
            growth: brief.growth,
            payout: brief.payout,
            borrows: brief.borrows,
          ),
        );
      for (var i = 0; i < 31; i++) {
        simulation.step();
      }
      return (simulation, simulation.observe(player));
    }

    // The company's reserve; the scenario has no taxes.
    Money reserve(Observation view) => operatingReserve(
      view,
      view.companies.first,
      opening.strategies.single.reserveDays,
    )!;

    Director brief({
      Growth growth = Growth.open,
      bool payout = true,
      bool borrows = false,
    }) => Director(
      grade: star,
      strategy: steady,
      managerGrade: clerk,
      growth: growth,
      payout: payout,
      borrows: borrows,
      hiredOn: start,
    );

    test('open a store at the best vacant site, from the company', () {
      final (_, view) = firstOfFebruary(brief());
      final company = view.companies.first;
      expect(view.today, Day.fromDate(2026, 2, 1));
      expect(company.retainedEarnings.cents, isPositive);
      final directives = <Directive>[];
      final commands = direct(
        view,
        opening,
        company,
        reserve(view) + Money.parse('2000.00'),
        const {},
        directives,
      );
      // Fitting out is spent from the month's profit, leaving none to pay.
      expect(commands.map((command) => command.runtimeType), [OpenStore]);
      final open = commands.first as OpenStore;
      expect(open.site, lane);
      expect(open.company, playerCompany);
      expect(open.capital, Money.zero, reason: "from the company's cash");
      expect(directives.map((d) => d.memo), [
        isA<StoreOpened>()
            .having((memo) => memo.site, 'site', lane)
            .having((memo) => memo.cost, 'fit-out', Money.parse('250.00')),
      ]);
      expect(directives.map((d) => d.command), commands);
    });

    test('pay the owner the profit kept, as far as cash allows', () {
      final (_, view) = firstOfFebruary(brief(growth: Growth.invest));
      final company = view.companies.first;
      List<Command> paid(Money beyondReserve) => direct(
        view,
        opening,
        company,
        reserve(view) + beyondReserve,
        const {},
        [],
      );
      expect(paid(Money.parse('2000.00')).map((c) => c.toString()), [
        'PayDividend(actor: 0, company: 0, '
            'amount: ${company.retainedEarnings.toDecimalString()})',
      ]);
      expect(paid(Money.parse('10.00')).map((c) => c.toString()), [
        'PayDividend(actor: 0, company: 0, amount: 10.00)',
      ]);
    });

    test('save for a store they can not pay for yet, keeping the profit', () {
      final (_, view) = firstOfFebruary(brief());
      final company = view.companies.first;
      final directives = <Directive>[];
      // 100.00 beyond the reserve: short of a new store's starting capital.
      final commands = direct(
        view,
        opening,
        company,
        reserve(view) + Money.parse('100.00'),
        const {},
        directives,
      );
      expect(commands, isEmpty);
      expect(directives.single.command, isNull);
      expect(
        directives.single.memo,
        isA<ProfitKept>()
            .having((memo) => memo.site, 'site', lane)
            .having((memo) => memo.store, 'store', isNull),
      );
    });

    test('borrow what a store lacks, if the brief lets them, on its '
        'earnings and over the longest term', () {
      final (_, view) = firstOfFebruary(brief(borrows: true));
      final company = view.companies.first;
      final directives = <Directive>[];
      final credit = view.companyCredits[playerCompany.index]!;
      expect(credit.cents, greaterThan(100000));
      final commands = direct(
        view,
        opening,
        company,
        reserve(view) + Money.parse('100.00'),
        const {},
        directives,
      );
      // No dividend: what there was to spare went into the store.
      final open = commands.single as OpenStore;
      expect(open.site, lane);
      expect(open.borrow.cents % 100000, 0, reason: 'a round thousand');
      expect(open.borrow.cents, greaterThan(0));
      expect(open.termMonths, opening.finance.maxTermMonths);
      expect(
        directives.single.memo,
        isA<StoreOpened>().having((m) => m.borrowed, 'borrowed', open.borrow),
      );
    });

    test('save instead, if the bank would not lend that much', () {
      final (_, view) = firstOfFebruary(brief(borrows: true));
      final directives = <Directive>[];
      final credit = view.companyCredits[playerCompany.index]!;
      final commands = direct(
        view,
        opening,
        view.companies.first,
        reserve(view) - credit,
        const {},
        directives,
      );
      expect(commands, isEmpty);
      expect(directives.single.memo, isA<ProfitKept>());
    });

    test('borrow nothing while the company has the cash', () {
      final (_, view) = firstOfFebruary(brief(borrows: true));
      final directives = <Directive>[];
      final commands = direct(
        view,
        opening,
        view.companies.first,
        reserve(view) + Money.parse('2000.00'),
        const {},
        directives,
      );
      final open = commands.whereType<OpenStore>().single;
      expect(open.borrow, Money.zero);
      expect(open.termMonths, 0);
    });

    test('pay out nothing, and grow nothing, unless the brief says so', () {
      final (_, view) = firstOfFebruary(
        brief(growth: Growth.invest, payout: false),
      );
      final directives = <Directive>[];
      expect(
        direct(
          view,
          opening,
          view.companies.first,
          Money.parse('4000.00'),
          const {},
          directives,
        ),
        isEmpty,
      );
      expect(directives, isEmpty);
    });

    test('carry it out in the game, and keep the memos', () {
      final (simulation, _) = firstOfFebruary(brief());
      simulation.step();
      final view = simulation.observe(player);
      expect(
        view.companies.first.stores.map((store) => store.site),
        [corner, lane],
      );
      expect(
        memos(simulation).map((memo) => memo.runtimeType),
        [ManagerHired, StoreOpened],
      );
      // The new store gets its manager the next day.
      simulation.step();
      expect(memos(simulation).last, isA<ManagerHired>());
    });
  });

  group('allowed to borrow', () {
    /// A year into a game of the trading scenario, on the first of January,
    /// with a director who may buy, and [borrows] if said so.
    (ContentDb, Observation) aYearIn({required bool borrows}) {
      final trading = loadScenario(withDirectors(tradingJson()));
      final simulation = Simulation.newGame(
        trading,
        seed: 1,
        systems: testSystems,
      );
      runScripted(simulation, 364);
      simulation.submit(hire(growth: Growth.buy, borrows: borrows));
      runScripted(simulation, 1);
      return (trading, simulation.observe(player));
    }

    Money reserve(Observation view, ContentDb trading) => operatingReserve(
      view,
      view.companies.first,
      trading.strategies.single.reserveDays,
    )!;

    test('buy a profitable rival the bank will lend for', () {
      final (trading, view) = aYearIn(borrows: true);
      final value = view.valuations[rivalStore.index]!;
      expect(value.earnings.cents, isPositive);
      // The company has all but half of what the bank would lend, its
      // earnings and the store's counted, towards the price and the reserve.
      final room =
          view.companyCredits[playerCompany.index]! +
          value.earnings.times(Fx.parse('2'));
      final directives = <Directive>[];
      final commands = direct(
        view,
        trading,
        view.companies.first,
        reserve(view, trading) +
            value.price +
            value.price.times(Fx.parse('0.25')) -
            Money(room.cents ~/ 2),
        const {},
        directives,
      );
      final buy = commands.whereType<BuyStore>().single;
      expect(buy.store, rivalStore);
      expect(buy.borrow.cents, greaterThan(0));
      expect(buy.termMonths, trading.finance.maxTermMonths);
      final memo = directives
          .map((directive) => directive.memo)
          .whereType<StoreBought>()
          .single;
      expect(memo.price, value.price);
      expect(memo.borrowed, buy.borrow);
      expect(
        memo.paybackMonths,
        allOf(greaterThan(0), lessThanOrEqualTo(buyoutPaybackMonths)),
      );
    });

    test('leave a profitable rival alone, without saving for it, if the bank '
        "won't lend enough", () {
      final (trading, view) = aYearIn(borrows: true);
      final directives = <Directive>[];
      final commands = direct(
        view,
        trading,
        view.companies.first,
        reserve(view, trading) - Money.parse('1000000.00'),
        const {},
        directives,
      );
      expect(commands.whereType<BuyStore>(), isEmpty);
      expect(directives.map((d) => d.memo).whereType<ProfitKept>(), isEmpty);
    });

    test('borrow for works they would otherwise save for', () {
      final simulation = Simulation.newGame(growing, seed: 1)
        ..submit(hire(growth: Growth.invest, payout: true, borrows: true));
      final directives = <Directive>[];
      // The first first of the month with works worth doing.
      List<Command> commands = const [];
      for (var i = 0; i < 800 && commands.isEmpty; i++) {
        simulation.step();
        final view = simulation.observe(player);
        final company = view.companies.first;
        if (!view.today.isFirstOfMonth ||
            view.companyCredits[playerCompany.index]! <
                Money.parse('2000.00')) {
          continue;
        }
        directives.clear();
        final reserve = operatingReserve(
          view,
          company,
          growing.strategies.single.reserveDays,
        )!;
        commands = direct(view, growing, company, reserve, const {}, directives)
            .where((command) => command is TakeLoan || command is ExpandStore)
            .toList();
      }
      final loan = commands.first as TakeLoan;
      expect(commands.last, isA<ExpandStore>());
      expect(loan.guarantee, isFalse);
      expect(loan.termMonths, growing.finance.maxTermMonths);
      expect(loan.amount.cents % 100000, 0, reason: 'a round thousand');
      final memo = directives
          .map((directive) => directive.memo)
          .whereType<StoreEnlarged>()
          .single;
      expect(memo.borrowed, loan.amount);
      expect(memo.cost <= loan.amount, isTrue);
    });

    test('leave profitable rivals alone otherwise', () {
      final (trading, view) = aYearIn(borrows: false);
      expect(
        direct(
          view,
          trading,
          view.companies.first,
          reserve(view, trading) + Money.parse('1000000.00'),
          const {},
          [],
        ).whereType<BuyStore>(),
        isEmpty,
      );
    });

    test('carry it out in the game: a loan on the earnings, no guarantee, '
        'and a game that plays on identically', () {
      final short = loadScenario(
        withDirectors(testScenarioJson).replaceFirst(
          '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
          '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
        ),
      );
      final simulation = Simulation.newGame(short, seed: 1)
        ..submit(hire(growth: Growth.open, borrows: true));
      final world = simulation.world;
      for (var i = 0; i < 400 && world.loans.isEmpty; i++) {
        simulation.step();
      }
      final loan = world.loans.single;
      expect(loan.guarantor, isNull);
      expect(loan.installmentsLeft, short.finance.maxTermMonths);
      expect(world.storeAt(lane)?.company, playerCompany);
      final memo = simulation
          .observe(player)
          .companies
          .first
          .memos
          .whereType<StoreOpened>()
          .single;
      expect(memo.borrowed, loan.principal);
      expect(invariantViolations(world), isEmpty);

      final loaded = Simulation.load(short, simulation.save());
      expect(loaded.stateHash(), simulation.stateHash());
      for (var i = 0; i < 40; i++) {
        simulation.step();
        loaded.step();
      }
      expect(loaded.stateHash(), simulation.stateHash());
    });
  });

  test('briefs and memos from before loans read with none', () {
    final brief = StateWriter()
      ..writeInt(star.index)
      ..writeInt(steady.index)
      ..writeInt(clerk.index)
      ..writeInt(Growth.open.index)
      ..writeBool(true)
      ..writeInt(start.number);
    expect(
      Director.read(StateReader(brief.toBytes(), version: 21)).borrows,
      isFalse,
    );
    final memo = StateWriter()
      ..writeInt(StoreBought.tag)
      ..writeInt(start.number)
      ..writeInt(rivalStore.index)
      ..writeInt(70000)
      ..writeInt(20);
    expect(
      (Memo.read(StateReader(memo.toBytes(), version: 21)) as StoreBought)
          .borrowed,
      Money.zero,
    );
    final command = StateWriter()
      ..writeInt(HireDirector.tag)
      ..writeInt(player.index)
      ..writeInt(playerCompany.index)
      ..writeInt(star.index)
      ..writeInt(steady.index)
      ..writeInt(clerk.index)
      ..writeInt(Growth.open.index)
      ..writeBool(true);
    expect(
      (Command.read(StateReader(command.toBytes(), version: 21)) as HireDirector)
          .borrows,
      isFalse,
    );
  });

  test('memos and briefs survive a save, and play on identically', () {
    final simulation = Simulation.newGame(growing, seed: 1)
      ..submit(hire(growth: Growth.open, payout: true));
    for (var i = 0; i < 40; i++) {
      simulation.step();
    }
    expect(memos(simulation), isNotEmpty);
    final loaded = Simulation.load(growing, simulation.save());
    expect(loaded.stateHash(), simulation.stateHash());
    for (var i = 0; i < 40; i++) {
      simulation.step();
      loaded.step();
    }
    expect(loaded.stateHash(), simulation.stateHash());
  });

  test("sharpen their managers' judgment by their skill", () {
    final directors = content.directors!;
    expect(directors.kept(null), Fx.one);
    expect(directors.kept(novice), Fx.parse('0.75'));
    expect(directors.kept(star), Fx.parse('0.50'));
    final store = Simulation.newGame(
      content,
      seed: 1,
    ).observe(player).companies.first.stores.single;
    Judgment judge(Fx kept) => misjudgment(
      content,
      store,
      content.managers.grades[clerk.index],
      (entity) => Rng.keyed(1, RngStream.manager, 0, entity),
      kept: kept,
    );
    final alone = judge(Fx.one);
    final coached = judge(directors.kept(star));
    for (final (i, factor) in alone.demand.indexed) {
      // The same draw, half as far off.
      expect(
        ((coached.demand[i] - Fx.one).raw * 2 - (factor - Fx.one).raw).abs(),
        lessThanOrEqualTo(2),
      );
    }
  });

  test('of full skill and full coaching leave their managers judging '
      "exactly, as the owner's policy does", () {
    final coached = loadScenario(
      withDirectors(testScenarioJson)
          .replaceFirst('"coaching": "0.50"', '"coaching": "1.00"'),
    );
    final simulation = Simulation.newGame(coached, seed: 1)
      ..submit(
        HireManager(
          player,
          store: playerStore,
          grade: clerk,
          strategy: steady,
          duties: const [true, true, true, true, true],
        ),
      )
      ..submit(hire())
      ..step();
    for (var i = 0; i < 20; i++) {
      final view = simulation.observe(player);
      final managed = manage(
        view,
        coached,
        (entity) => Rng.keyed(1, RngStream.manager, 0, entity),
      );
      final owned = RetailPolicy(coached.strategies.single)
          .decide(view, coached)
          .where(
            (command) => command is! PayDividend && command is! InjectCapital,
          );
      expect(
        managed.map((c) => c.toString()).toSet(),
        owned.map((c) => c.toString()).toSet(),
        reason: 'day $i',
      );
      simulation.step();
    }
  });

  test('every kind of memo reads back as written', () {
    final day = Day.fromDate(2027, 3, 1);
    final all = <Memo>[
      ManagerHired(day, store: playerStore, grade: clerk),
      StoreClosed(
        day,
        store: playerStore,
        sales: Money.parse('900.00'),
        loss: Money.parse('40.00'),
      ),
      StoreEnlarged(day, store: playerStore, cost: Money.parse('200.00')),
      StoreConverted(
        day,
        store: playerStore,
        format: const FormatId(1),
        cost: Money.parse('300.00'),
      ),
      StoreOpened(
        day,
        site: lane,
        format: const FormatId(0),
        cost: Money.parse('250.00'),
        paybackMonths: 8,
      ),
      StoreBought(
        day,
        store: rivalStore,
        price: Money.parse('700.00'),
        paybackMonths: 20,
        borrowed: Money.parse('500.00'),
      ),
      ProfitPaid(day, amount: Money.parse('120.00')),
      ProfitKept(day, site: lane, needed: Money.parse('800.00')),
      ProfitKept(day, store: playerStore, needed: Money.parse('200.00')),
    ];
    final writer = StateWriter();
    for (final memo in all) {
      memo.write(writer);
    }
    final reader = StateReader(writer.toBytes());
    final again = StateWriter();
    for (var i = 0; i < all.length; i++) {
      final memo = Memo.read(reader);
      expect(memo.runtimeType, all[i].runtimeType);
      memo.write(again);
    }
    expect(again.toBytes(), writer.toBytes());
  });
}
