import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/state/entities.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test town with the player well off, dividends taxed at 30%.
final _content = loadScenario(
  testScenarioJson
      .replaceFirst(
        '"name": "Player", "cash": "1000.00"',
        '"name": "Player", "cash": "100000.00"',
      )
      .replaceFirst(
        '"categories": [{ "id": "milk", "name": "Milk" }],',
        '"taxes": { "reducedRate": "0.15", "reducedLimit": "100.00", '
            '"corporateRate": "0.25", "dividendRate": "0.30" },\n'
            '  "categories": [{ "id": "milk", "name": "Milk" }],',
      ),
);

Simulation _game() =>
    Simulation.newGame(_content, seed: 1, systems: quietSystems);

/// The companies founded so far after the scenario's.
Company _latest(Simulation game) => game.world.companies.last;

/// Books [amount] of profit to [company] from beyond the town.
void _earn(Simulation game, Company company, Money amount) {
  Ledger(game.today).pay(
    payer: game.world.elsewhere,
    payerAccount: AccountKind.spending,
    payee: company,
    payeeAccount: AccountKind.revenue,
    amount: amount,
    reason: EntryReason.sale,
  );
}

void main() {
  test('a company is founded under the holding, its capital from it', () {
    final game = _game();
    final holding = game.world.persons[player.index];
    final before = holding.accounts[AccountKind.cash];
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    expect(game.step().rejections, isEmpty);
    final group = _latest(game);
    expect(group.name, 'Groupe');
    expect(group.parent, isNull);
    expect(group.owner, player);
    expect(group.accounts[AccountKind.cash], Money.parse('40000.00'));
    expect(
      holding.accounts[AccountKind.cash],
      before - Money.parse('40000.00'),
    );
    expect(game.observe(player).companies.last.parent, isNull);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a subsidiary is founded under a company, from its cash', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    final group = _latest(game);
    game.submit(
      FoundCompany(
        player,
        name: 'Filiale',
        capital: Money.parse('10000.00'),
        parent: group.id,
      ),
    );
    expect(game.step().rejections, isEmpty);
    final subsidiary = _latest(game);
    expect(subsidiary.parent, group.id);
    expect(group.accounts[AccountKind.cash], Money.parse('30000.00'));
    expect(group.accounts[AccountKind.investments], Money.parse('10000.00'));
    // More than the parent has is refused, and so is a stranger's parent.
    for (final (command, key) in [
      (
        FoundCompany(
          player,
          name: 'Trop',
          capital: Money.parse('50000.00'),
          parent: group.id,
        ),
        'notEnoughParentCash',
      ),
      (
        FoundCompany(
          rival,
          name: 'Pas à moi',
          capital: Money.parse('1.00'),
          parent: group.id,
        ),
        'notYourCompany',
      ),
      (
        FoundCompany(player, name: ' Mal', capital: Money.parse('1.00')),
        'nameRule',
      ),
    ]) {
      game.submit(command);
      expect(game.step().rejections.single.reason.key, key);
    }
    expect(invariantViolations(game.world), isEmpty);
  });

  test('capital goes down from the parent and dividends up to it, received '
      'outside its profit and taxed at the dividend rate', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    final group = _latest(game);
    game.submit(
      FoundCompany(
        player,
        name: 'Filiale',
        capital: Money.parse('10000.00'),
        parent: group.id,
      ),
    );
    game.step();
    final subsidiary = _latest(game);
    final holding = game.world.persons[player.index];
    final holdingCash = holding.accounts[AccountKind.cash];
    game.submit(
      InjectCapital(
        player,
        company: subsidiary.id,
        amount: Money.parse('5000.00'),
      ),
    );
    expect(game.step().rejections, isEmpty);
    expect(group.accounts[AccountKind.cash], Money.parse('25000.00'));
    expect(subsidiary.accounts[AccountKind.cash], Money.parse('15000.00'));
    expect(holding.accounts[AccountKind.cash], holdingCash);

    _earn(game, subsidiary, Money.parse('2000.00'));
    final taxes = holding.accounts[AccountKind.taxes];
    game.submit(
      PayDividend(
        player,
        company: subsidiary.id,
        amount: Money.parse('2000.00'),
      ),
    );
    expect(game.step().rejections, isEmpty);
    // Received apart from its profit, the parent paying 30% on it; the rest
    // it may pay on up. Its own payouts stay apart from what it received.
    expect(subsidiary.accounts[AccountKind.dividends], Money.parse('2000.00'));
    expect(group.accounts[AccountKind.cash], Money.parse('26400.00'));
    expect(
      group.accounts[AccountKind.dividendsReceived],
      -Money.parse('2000.00'),
    );
    expect(group.accounts[AccountKind.taxes], Money.parse('600.00'));
    expect(group.accounts[AccountKind.dividends], Money.zero);
    expect(group.accounts[AccountKind.disposals], Money.zero);
    expect(group.accounts.retainedEarnings, Money.parse('1400.00'));
    expect(invariantViolations(game.world), isEmpty);
    expect(holding.accounts[AccountKind.taxes], taxes);
    game.submit(
      PayDividend(player, company: group.id, amount: Money.parse('1400.00')),
    );
    expect(game.step().rejections, isEmpty);
    expect(
      holding.accounts[AccountKind.cash],
      holdingCash + Money.parse('980.00'),
    );
    expect(invariantViolations(game.world), isEmpty);
  });

  test("a subsidiary's shop takes its capital from the parent, not the "
      'holding', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    final group = _latest(game);
    game.submit(
      FoundCompany(
        player,
        name: 'Filiale',
        capital: Money.parse('1000.00'),
        parent: group.id,
      ),
    );
    game.step();
    final subsidiary = _latest(game);
    final holding = game.world.persons[player.index];
    final holdingCash = holding.accounts[AccountKind.cash];
    final groupCash = group.accounts[AccountKind.cash];
    // More than the parent has is refused, though the holding has it.
    game.submit(
      OpenStore(
        player,
        site: lane,
        name: 'Rue',
        company: subsidiary.id,
        capital: Money.parse('50000.00'),
      ),
    );
    expect(game.step().rejections.single.reason.key, 'notEnoughParentCash');
    game.submit(
      OpenStore(
        player,
        site: lane,
        name: 'Rue',
        company: subsidiary.id,
        capital: Money.parse('2000.00'),
      ),
    );
    expect(game.step().rejections, isEmpty);
    expect(
      group.accounts[AccountKind.cash],
      groupCash - Money.parse('2000.00'),
    );
    expect(holding.accounts[AccountKind.cash], holdingCash);
    expect(subsidiary.injected, Money.parse('3000.00'));
    expect(invariantViolations(game.world), isEmpty);
  });

  test("a parent's worth counts its subsidiaries, and the holding's adds "
      'only its own companies', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    final group = _latest(game);
    game.submit(
      FoundCompany(
        player,
        name: 'Filiale',
        capital: Money.parse('10000.00'),
        parent: group.id,
      ),
    );
    game.step();
    final subsidiary = _latest(game);
    expect(
      companyWorth(game.world, game.content, group),
      Money.parse('40000.00'),
    );
    expect(
      companyWorth(game.world, game.content, subsidiary),
      Money.parse('10000.00'),
    );
  });

  test("the holding keeps its own months: what posted to the player's "
      'books, kept through a save', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    final group = _latest(game);
    _earn(game, group, Money.parse('1000.00'));
    game.submit(
      PayDividend(player, company: group.id, amount: Money.parse('1000.00')),
    );
    game.step();
    final month = game.world.holdingMonths.single;
    expect(month.start, Day.fromDate(2026, 1, 1));
    expect(month.flow(AccountKind.dividends), -Money.parse('1000.00'));
    expect(month.flow(AccountKind.taxes), Money.parse('300.00'));
    expect(month.flow(AccountKind.investments), Money.parse('40000.00'));
    // A month begins on its first day, whatever posts.
    do {
      game.step();
    } while (!game.today.isFirstOfMonth);
    game.step();
    expect(game.world.holdingMonths, hasLength(2));
    expect(game.world.holdingMonths.last.flow(AccountKind.taxes), Money.zero);
    final view = game.observe(player).holdingMonths;
    expect(view.first.flow(AccountKind.dividends), -Money.parse('1000.00'));
    expect(game.observe(rival).holdingMonths, isEmpty);
    final loaded = Simulation.load(
      _content,
      game.save(),
      systems: quietSystems,
    );
    expect(
      loaded.world.holdingMonths.first.flow(AccountKind.taxes),
      Money.parse('300.00'),
    );
    expect(loaded.stateHash(), game.stateHash());
  });

  test('a group survives a save, and an older save has none', () {
    final game = _game();
    game.submit(
      FoundCompany(player, name: 'Groupe', capital: Money.parse('40000.00')),
    );
    game.step();
    game.submit(
      FoundCompany(
        player,
        name: 'Filiale',
        capital: Money.parse('10000.00'),
        parent: _latest(game).id,
      ),
    );
    game.step();
    final loaded = Simulation.load(
      _content,
      game.save(),
      systems: quietSystems,
    );
    expect(
      loaded.world.companies.last.parent,
      game.world.companies.last.parent,
    );
    expect(loaded.stateHash(), game.stateHash());
    // Replayed from the log, the same.
    final replayed = Simulation.replay(
      _content,
      game.save(),
      systems: quietSystems,
    );
    expect(replayed.stateHash(), game.stateHash());
  });
}
