import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'acquisitions_test.dart' show tradingJson;
import 'support/fixtures.dart';

void main() {
  final two = Fx.parse('2');

  /// The trading scenario [days] in, so that stores have earnings.
  (ContentDb, Simulation) trading({
    int days = 40,
    bool taxes = false,
    String playerCash = '1000.00',
  }) {
    final content = loadScenario(
      tradingJson(taxes: taxes, playerCash: playerCash),
    );
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: testSystems,
    );
    runScripted(simulation, days);
    return (content, simulation);
  }

  /// Applies [commands] in the next step and returns the rejection reasons.
  List<String> apply(Simulation simulation, List<Command> commands) {
    commands.forEach(simulation.submit);
    return [
      for (final rejection in simulation.step().rejections)
        rejection.reason.key,
    ];
  }

  Money cash(LedgerParty party) => party.accounts[AccountKind.cash];

  test("without a guarantee, the bank lends two years of the stores' "
      'earnings, less what the company owes it', () {
    final (content, simulation) = trading();
    final view = simulation.observe(player);
    final earnings = view.valuations[playerStore.index]!.earnings;
    expect(earnings.cents, greaterThan(100000));
    final credit = view.companyCredits[playerCompany.index]!;
    expect(credit, earnings.times(two));
    expect(view.guaranteeRoom, view.cash.times(two));
    final half = Money(credit.cents ~/ 2);
    TakeLoan unguaranteed(Money amount) => TakeLoan(
      player,
      company: playerCompany,
      amount: amount,
      termMonths: 24,
      guarantee: false,
    );
    expect(
      apply(simulation, [unguaranteed(credit + Money(1)), unguaranteed(half)]),
      [
        'bankLendsAtMost',
      ],
    );
    final loan = simulation.world.loans.single;
    expect((loan.outstanding, loan.guarantor), (half, null));
    expect(
      loan.rate,
      lendingRate(
        content,
        view.macro.policyRate,
        view.today,
        guaranteed: false,
      ),
    );
    final after = simulation.observe(player);
    expect(
      after.companyCredits[playerCompany.index],
      after.valuations[playerStore.index]!.earnings.times(two) - half,
    );
    // A guarantee doesn't draw on the earnings, nor they on it.
    expect(after.guaranteeRoom, after.cash.times(two));
  });

  test('a store bought on credit borrows on earnings first, its own '
      "included, then on the owner's guarantee; a loan refused buys "
      'nothing', () {
    final (content, simulation) = trading();
    final world = simulation.world;
    var view = simulation.observe(player);
    var value = view.valuations[rivalStore.index]!;
    final companyCash = view.companies.single.cash;
    final credit =
        view.companyCredits[playerCompany.index]! + value.earnings.times(two);
    BuyStore buy(Money borrow) => BuyStore(
      player,
      store: rivalStore,
      company: playerCompany,
      borrow: borrow,
      termMonths: 24,
    );
    expect(
      apply(simulation, [
        buy(credit + view.guaranteeRoom + Money(1)),
        buy(value.price - companyCash - Money(1)),
      ]),
      [
        'bankWillNotLend',
        'cannotPayPrice',
      ],
    );
    expect(world.loans, isEmpty);
    expect(world.stores[rivalStore.index].company, CompanyId(1));

    view = simulation.observe(player);
    value = view.valuations[rivalStore.index]!;
    final carried =
        view.companyCredits[playerCompany.index]! + value.earnings.times(two);
    final guaranteed = Money.parse('100.00');
    expect(apply(simulation, [buy(carried + guaranteed)]), isEmpty);
    expect(world.stores[rivalStore.index].company, playerCompany);
    expect(
      [
        for (final loan in world.loans)
          (loan.outstanding, loan.guarantor, loan.installmentsLeft),
      ],
      [(carried, null, 24), (guaranteed, player, 24)],
    );
    final after = simulation.observe(player);
    expect(after.guaranteeRoom, after.cash.times(two) - guaranteed);
    expect(invariantViolations(world), isEmpty);
    expect(
      Simulation.replay(
        content,
        simulation.save(),
        systems: testSystems,
      ).stateHash(),
      simulation.stateHash(),
    );
  });

  test("a new company borrows only on its owner's guarantee", () {
    final (_, simulation) = trading();
    final world = simulation.world;
    final companies = world.companies.length;
    final capital = Money.parse('100.00');
    final room = (simulation.observe(player).cash - capital).times(two);
    OpenStore open(Money borrow) => OpenStore(
      player,
      site: lane,
      name: 'Lane Shop',
      capital: capital,
      borrow: borrow,
      termMonths: 12,
    );
    expect(apply(simulation, [open(room + Money(1))]), [
      'bankWillNotLend',
    ]);
    expect(world.companies, hasLength(companies));
    expect(world.storeAt(lane), isNull);

    expect(apply(simulation, [open(Money.parse('200.00'))]), isEmpty);
    final company = world.companies.last;
    expect(company.name, 'Lane Shop');
    final loan = world.loans.single;
    expect(
      (loan.company, loan.outstanding, loan.guarantor),
      (company.id, Money.parse('200.00'), player),
    );
    expect(invariantViolations(world), isEmpty);
  });

  test('a company bought on credit borrows on its own earnings, so the '
      'buyer pays only the rest; the seller is taxed on the whole price', () {
    final (_, simulation) = trading(
      days: 30,
      taxes: true,
      playerCash: '5000.00',
    );
    final world = simulation.world;
    const target = CompanyId(1);
    BuyCompany buy(Money borrow) =>
        BuyCompany(player, company: target, borrow: borrow, termMonths: 36);
    var view = simulation.observe(player);
    final credit = view.companyCredits[target.index]!;
    expect(credit.cents, greaterThan(0));
    expect(apply(simulation, [buy(credit + Money(1))]), [
      'bankLendsItAtMost',
    ]);
    expect(world.loans, isEmpty);
    expect(world.companies[target.index].owner, rival);

    view = simulation.observe(player);
    final price = view.companyPrices[target.index]!;
    final borrow = view.companyCredits[target.index]!;
    final playerCash = cash(world.persons[player.index]);
    final rivalCash = cash(world.persons[rival.index]);
    final result = (simulation..submit(buy(borrow))).step();
    expect(result.rejections, isEmpty);
    final company = world.companies[target.index];
    expect(company.owner, player);
    expect(company.injected, price - borrow);
    expect(cash(world.persons[player.index]), playerCash - (price - borrow));
    expect(
      world.persons[player.index].accounts[AccountKind.investments],
      price - borrow,
    );
    // The rival had put nothing in: the whole price is a gain, taxed at 30%.
    final tax = price.times(Fx.parse('0.30'));
    expect(cash(world.persons[rival.index]), rivalCash + price - tax);
    final loan = world.loans.single;
    expect(
      (loan.company, loan.outstanding, loan.guarantor, loan.installmentsLeft),
      (target, borrow, null, 36),
    );
    // The company paid its part of the price out of the loan, handing back
    // that much capital.
    final paid = result.entries.firstWhere(
      (entry) =>
          entry.reason == EntryReason.companySale &&
          entry.party == company.partyRef,
    );
    expect((paid.debit, paid.amount), (AccountKind.equity, borrow));
    expect(invariantViolations(world), isEmpty);
  });

  test('commands with a loan read back, and older ones with none', () {
    final commands = [
      OpenStore(
        player,
        site: lane,
        name: 'Lane',
        company: playerCompany,
        borrow: Money.parse('250.00'),
        termMonths: 12,
      ),
      BuyStore(
        player,
        store: rivalStore,
        company: playerCompany,
        borrow: Money.parse('1234.56'),
        termMonths: 60,
      ),
      BuyCompany(
        player,
        company: CompanyId(1),
        borrow: Money.parse('99.00'),
        termMonths: 84,
      ),
    ];
    for (final command in commands) {
      final writer = StateWriter();
      command.write(writer);
      expect(
        Command.read(StateReader(writer.toBytes())).toString(),
        command.toString(),
      );
    }
    final old = StateWriter()
      ..writeInt(BuyStore.tag)
      ..writeInt(player.index)
      ..writeInt(rivalStore.index)
      ..writeInt(playerCompany.index);
    expect(
      Command.read(StateReader(old.toBytes(), version: 20)).toString(),
      BuyStore(player, store: rivalStore, company: playerCompany).toString(),
    );
  });
}
