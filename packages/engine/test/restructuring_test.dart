import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart';
import 'package:engine/src/state/entities.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/systems/taxes.dart';
import 'package:engine/src/systems/tick_system.dart';
import 'package:test/test.dart';

import 'acquisitions_test.dart' show tradingJson;
import 'support/fixtures.dart';

/// The test town where businesses change hands, dividends taxed at 30%, the
/// player well off and a rival with the cash to buy.
final _content = loadScenario(
  tradingJson(
    taxes: true,
    playerCash: '100000.00',
    rivalCash: '50000.00',
    rivalCompanyCash: '100.00',
    expanding: true,
  ),
);

/// The player's shops: the town's one kind of shop, its own trade.
const _shops = 'store';

Simulation _game({List<TickSystem>? systems}) => Simulation.newGame(
  _content,
  seed: 1,
  systems: systems ?? quietSystems,
  policies: const {},
);

/// Founds [name] with [capital], under [parent] if given.
Company _found(
  Simulation game,
  String name,
  String capital, {
  CompanyId? parent,
}) {
  game.submit(
    FoundCompany(
      player,
      name: name,
      capital: Money.parse(capital),
      parent: parent,
    ),
  );
  expect(game.step().rejections, isEmpty);
  return game.world.companies.last;
}

/// [command] applied, with no refusal.
void _apply(Simulation game, Command command) {
  game.submit(command);
  expect(game.step().rejections, isEmpty);
  expect(invariantViolations(game.world), isEmpty);
}

/// The refusal [command] meets.
String _refused(Simulation game, Command command) {
  game.submit(command);
  return game.step().rejections.single.reason.key;
}

/// The player's shops' book value.
Money _book(Simulation game, CompanyId company) {
  final (:stock, :bought) = businessBook(
    businessParts(game.world, game.content, company, _shops),
  );
  return stock + bought;
}

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

Company _company(Simulation game, CompanyId id) =>
    game.world.companies[id.index];

/// Stocks the player's shop with milk, so it stands at something in the
/// books.
void _stocked(Simulation game) {
  game.submit(
    PlaceOrder(
      player,
      store: playerStore,
      supplier: bulk,
      lines: [(product: milkBudget, quantity: 60)],
    ),
  );
  for (
    var day = 0;
    day < 30 && _book(game, playerCompany) == Money.zero;
    day++
  ) {
    game.step();
  }
  expect(_book(game, playerCompany) > Money.zero, isTrue);
}

void main() {
  test('a business moves beside at its book value, paid in cash', () {
    final game = _game();
    _stocked(game);
    final other = _found(game, 'Autre', '10000.00');
    final book = _book(game, playerCompany);
    expect(book > Money.zero, isTrue);
    final cash = other.accounts[AccountKind.cash];
    _apply(
      game,
      MoveBusiness(
        player,
        company: playerCompany,
        business: _shops,
        to: other.id,
      ),
    );
    expect(game.world.stores[playerStore.index].company, other.id);
    final giver = _company(game, playerCompany);
    expect(giver.accounts[AccountKind.inventory], Money.zero);
    expect(giver.accounts[AccountKind.disposals], Money.zero);
    expect(other.accounts[AccountKind.cash] < cash, isTrue);
  });

  test('made a company of its own, a business is its old company\'s capital '
      'in it', () {
    final game = _game();
    _stocked(game);
    final book = _book(game, playerCompany);
    _apply(
      game,
      MoveBusiness(
        player,
        company: playerCompany,
        business: _shops,
        name: 'Filiale',
      ),
    );
    final spun = game.world.companies.last;
    expect(spun.name, 'Filiale');
    expect(spun.parent, playerCompany);
    expect(spun.injected, book);
    expect(game.world.stores[playerStore.index].company, spun.id);
    expect(
      _company(game, playerCompany).accounts[AccountKind.investments],
      book,
    );
  });

  test('moved up the tree, a business is a dividend in kind and pays the '
      'dividend rate', () {
    final game = _game();
    _stocked(game);
    final group = _found(game, 'Groupe', '20000.00');
    final subsidiary = _found(game, 'Filiale', '5000.00', parent: group.id);
    _apply(
      game,
      MoveBusiness(
        player,
        company: playerCompany,
        business: _shops,
        to: subsidiary.id,
      ),
    );
    final book = _book(game, subsidiary.id);
    final taxes = group.accounts[AccountKind.taxes];
    _apply(
      game,
      MoveBusiness(
        player,
        company: subsidiary.id,
        business: _shops,
        to: group.id,
      ),
    );
    expect(game.world.stores[playerStore.index].company, group.id);
    expect(group.accounts[AccountKind.dividendsReceived] < Money.zero, isTrue);
    expect(
      group.accounts[AccountKind.taxes] - taxes,
      book.times(Fx.parse('0.30')),
    );
  });

  test('a company moves under another as capital, back up as a dividend in '
      'kind, and never under one of its own', () {
    final game = _game();
    final group = _found(game, 'Groupe', '20000.00');
    final other = _found(game, 'Autre', '3000.00');
    _apply(game, MoveCompany(player, company: other.id, under: group.id));
    expect(other.parent, group.id);
    expect(group.injected, Money.parse('23000.00'));
    expect(group.accounts[AccountKind.investments], Money.parse('3000.00'));
    expect(
      _refused(game, MoveCompany(player, company: group.id, under: other.id)),
      'underItsOwn',
    );
    expect(
      _refused(game, MoveCompany(player, company: other.id, under: group.id)),
      'alreadyThere',
    );
    final holding = game.world.persons[player.index];
    final taxes = holding.accounts[AccountKind.taxes];
    _apply(game, MoveCompany(player, company: other.id));
    expect(other.parent, isNull);
    expect(group.accounts[AccountKind.investments], Money.zero);
    expect(holding.accounts[AccountKind.taxes] - taxes, Money.parse('900.00'));
  });

  test('a company merges beside, the other taking all it has, owes and '
      'holds', () {
    final game = _game();
    final other = _found(game, 'Autre', '10000.00');
    final merged = _company(game, playerCompany);
    final capital = merged.injected + other.injected;
    final cash =
        merged.accounts[AccountKind.cash] + other.accounts[AccountKind.cash];
    final subsidiary = _found(game, 'Filiale', '100.00', parent: merged.id);
    _apply(game, MergeCompany(player, company: merged.id, into: other.id));
    expect(merged.status, CompanyStatus.merged);
    expect(merged.mergedInto, other.id);
    expect(game.world.stores[playerStore.index].company, other.id);
    expect(subsidiary.parent, other.id);
    expect(other.injected, capital);
    expect(other.accounts[AccountKind.cash] > Money.zero, isTrue);
    expect(other.accounts[AccountKind.cash] <= cash, isTrue);
    expect(merged.accounts.netAssets, Money.zero);
  });

  test('a subsidiary merges up, its kept profit paying the dividend rate; '
      'cousins do not merge', () {
    final game = _game();
    final group = _found(game, 'Groupe', '20000.00');
    final subsidiary = _found(game, 'Filiale', '5000.00', parent: group.id);
    final cousin = _found(game, 'Cousine', '100.00', parent: playerCompany);
    expect(
      _refused(
        game,
        MergeCompany(player, company: cousin.id, into: subsidiary.id),
      ),
      'mergeWhere',
    );
    _earn(game, subsidiary, Money.parse('2000.00'));
    final taxes = group.accounts[AccountKind.taxes];
    _apply(game, MergeCompany(player, company: subsidiary.id, into: group.id));
    expect(subsidiary.status, CompanyStatus.merged);
    expect(group.accounts[AccountKind.investments], Money.zero);
    expect(group.accounts[AccountKind.taxes] - taxes, Money.parse('600.00'));
  });

  test("a merged company's year is taxed, billed to the one it went into", () {
    final game = _game(systems: [const TaxSystem(), ...testSystems]);
    _stocked(game);
    final group = _found(game, 'Groupe', '20000.00');
    final subsidiary = _found(game, 'Filiale', '5000.00', parent: group.id);
    // The shop trades for the subsidiary until the autumn, then it merges.
    _apply(
      game,
      MoveBusiness(
        player,
        company: playerCompany,
        business: _shops,
        to: subsidiary.id,
      ),
    );
    while (game.today.date.month < 10) {
      game.step();
    }
    _apply(game, MergeCompany(player, company: subsidiary.id, into: group.id));
    while (game.today.date.year == 2026) {
      game.step();
    }
    game.step();
    final filing = game.world.filings.where(
      (filing) => filing.company == subsidiary.id && filing.year == 2026,
    );
    expect(filing.single.profit > Money.zero, isTrue);
    expect(
      group.payables.any((bill) => bill.reason == EntryReason.corporateTax),
      isTrue,
    );
  });

  test('a business sells on the spot to the owner of its kind best able to '
      'pay, the money its company\'s', () {
    final game = _game();
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    final cash = _company(game, playerCompany).accounts[AccountKind.cash];
    _apply(
      game,
      SellBusiness(player, company: playerCompany, business: _shops),
    );
    expect(game.world.stores[playerStore.index].company, const CompanyId(1));
    expect(
      _company(game, playerCompany).accounts[AccountKind.cash] > cash,
      isTrue,
    );
  });

  test('a company holding shops alone sells whole to the owner best able to '
      'pay; one holding subsidiaries waits', () {
    final game = _game();
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    final sold = _company(game, playerCompany);
    final subsidiary = _found(game, 'Filiale', '100.00', parent: sold.id);
    expect(
      _refused(game, SellCompany(player, company: sold.id)),
      'hasSubsidiaries',
    );
    _apply(game, MergeCompany(player, company: subsidiary.id, into: sold.id));
    final holding = game.world.persons[player.index];
    final cash = holding.accounts[AccountKind.cash];
    _apply(game, SellCompany(player, company: sold.id));
    expect(sold.owner, rival);
    expect(holding.accounts[AccountKind.cash] > cash, isTrue);
  });

  test('restructuring survives a save and replays the same', () {
    final game = _game();
    _stocked(game);
    final group = _found(game, 'Groupe', '20000.00');
    final other = _found(game, 'Autre', '3000.00');
    _apply(game, MoveCompany(player, company: other.id, under: group.id));
    _apply(
      game,
      MoveBusiness(
        player,
        company: playerCompany,
        business: _shops,
        to: other.id,
      ),
    );
    _apply(game, MergeCompany(player, company: other.id, into: group.id));
    final loaded = Simulation.load(
      _content,
      game.save(),
      systems: quietSystems,
      policies: const {},
    );
    expect(loaded.stateHash(), game.stateHash());
    expect(loaded.world.companies[other.id.index].mergedInto, group.id);
    final replayed = Simulation.replay(
      _content,
      game.save(),
      systems: quietSystems,
      policies: const {},
    );
    expect(replayed.stateHash(), game.stateHash());
  });
}
