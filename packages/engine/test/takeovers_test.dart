@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/systems/takeovers.dart' show openBid;
import 'package:test/test.dart';

/// The prototype with the countries' national figures and the stock market,
/// its player and their first company rich enough to take companies over.
final _content = loadScenario(
  File('../../content/scenarios/prototype.json')
      .readAsStringSync()
      .replaceFirst(
        '"name": "You", "cash": "20000.00"',
        '"name": "You", "cash": "500000000.00"',
      )
      .replaceFirst(
        '"name": "Corner Shop", "owner": "player", "cash": "15000.00"',
        '"name": "Corner Shop", "owner": "player", "cash": "3000000000.00"',
      ),
  national: loadCountryTable(
    File('../../content/countries/euro.json').readAsStringSync(),
    File('../../content/countries/calibration.json').readAsStringSync(),
  ),
  stocks: File('../../content/stocks/companies.json').readAsStringSync(),
);

final _def = _content.stocks!;

Simulation _game({int seed = 1}) => Simulation.newGame(_content, seed: seed);

Money _cash(Simulation game) =>
    game.world.persons[game.world.player.index].accounts[AccountKind.cash];

/// The smallest company by formula on the market.
int _smallest(Simulation game) {
  final market = game.world.stocks!;
  var best = -1;
  for (final (i, listing) in _def.listings.indexed) {
    if (listing.kind != ListingKind.formula) continue;
    if (best < 0 || market.stocks[i].cap < market.stocks[best].cap) best = i;
  }
  return best;
}

/// Plays until bid [number] has closed.
void _untilClosed(Simulation game, int number) {
  for (var d = 0; d < 40; d++) {
    final bid = game.world.stocks!.bids.firstWhere((b) => b.number == number);
    if (bid.status != BidStatus.open) return;
    game.step();
  }
}

Refusal? _submit(Simulation game, Command command) {
  game.submit(command);
  final result = game.step();
  return result.rejections
      .where((r) => identical(r.command, command))
      .firstOrNull
      ?.reason;
}

/// A game whose first company has taken over the smallest clothing chain
/// and run it a few months, so that it earns.
Simulation _earning() {
  final game = _game();
  final market = game.world.stocks!;
  var i = -1;
  for (final (n, listing) in _def.listings.indexed) {
    if (listing.kind != ListingKind.chain ||
        _def.sectors[listing.sector].trade != 'clothing') {
      continue;
    }
    if (i < 0 || market.stocks[n].cap < market.stocks[i].cap) i = n;
  }
  game.submit(
    BidForCompany(
      game.world.player,
      stock: i,
      premium: Fx.parse('0.40'),
      bidder: 0,
      format: _content.formats.indexWhere((f) => f.key == 'clothing'),
      strategy: 0,
    ),
  );
  for (var d = 0; d < 150; d++) {
    game.step();
  }
  return game;
}

void main() {
  test('a bid well over the price wins control of a company by formula', () {
    final game = _game();
    final i = _smallest(game);
    final before = _cash(game);
    expect(
      _submit(
        game,
        BidForCompany(
          game.world.player,
          stock: i,
          premium: Fx.parse('0.40'),
          bidder: holdingOwner,
        ),
      ),
      isNull,
    );
    final bid = game.world.stocks!.bids.single;
    _untilClosed(game, bid.number);
    expect(bid.status, BidStatus.won);
    final stock = game.world.stocks!.stocks[i];
    expect(stock.controller, holdingOwner);
    expect(game.world.stocks!.playersUnits(i) * 2 > stock.shares, isTrue);
    expect(_cash(game) < before, isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a bid barely over the price is turned down', () {
    final game = _game();
    final i = _smallest(game);
    _submit(
      game,
      BidForCompany(
        game.world.player,
        stock: i,
        premium: Fx.parse('0.01'),
        bidder: holdingOwner,
      ),
    );
    final bid = game.world.stocks!.bids.single;
    _untilClosed(game, bid.number);
    expect(bid.status, BidStatus.lost);
    expect(game.world.stocks!.stocks[i].controller, isNull);
  });

  test('a chain won joins the bidding company as its shops', () {
    final game = _game();
    final market = game.world.stocks!;
    // The smallest clothing chain.
    var i = -1;
    for (final (n, listing) in _def.listings.indexed) {
      if (listing.kind != ListingKind.chain ||
          _def.sectors[listing.sector].trade != 'clothing') {
        continue;
      }
      if (i < 0 || market.stocks[n].cap < market.stocks[i].cap) i = n;
    }
    final format = _content.formats.indexWhere((f) => f.key == 'clothing');
    final player = game.world.player;
    expect(
      _submit(
        game,
        BidForCompany(
          player,
          stock: i,
          premium: Fx.parse('0.40'),
          bidder: holdingOwner,
        ),
      )?.key,
      'chainNeedsCompany',
    );
    expect(
      _submit(
        game,
        BidForCompany(
          player,
          stock: i,
          premium: Fx.parse('0.40'),
          bidder: 0,
          format: format,
          strategy: 0,
        ),
      ),
      isNull,
    );
    final bid = market.bids.single;
    _untilClosed(game, bid.number);
    expect(bid.status, BidStatus.won);
    expect(market.stocks[i].listed, isFalse);
    final listing = _def.listings[i];
    final country = game.world.national!.countries.firstWhere(
      (c) => c.def.key == _content.countries[listing.country.index].national,
    );
    expect(country.chains[listing.link].boughtBy, 0);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a controlled company takes its levers and director', () {
    final game = _game();
    final i = _smallest(game);
    _submit(
      game,
      BidForCompany(
        game.world.player,
        stock: i,
        premium: Fx.parse('0.40'),
        bidder: holdingOwner,
      ),
    );
    _untilClosed(game, game.world.stocks!.bids.single.number);
    final player = game.world.player;
    expect(
      _submit(
        game,
        RunListed(
          player,
          stock: i,
          payout: Fx.parse('0.9'),
          growth: 1,
          debt: Fx.parse('2'),
          director: _content.directors!.grades.length - 1,
        ),
      ),
      isNull,
    );
    while (!game.today.isFirstOfMonth) {
      game.step();
    }
    game.step();
    final stock = game.world.stocks!.stocks[i];
    expect(stock.management, managementGrades.length - 1);
    expect(stock.payoutLever, Fx.parse('0.9'));
    expect(
      _submit(game, RunListed(player, stock: i, growth: 3))?.key,
      'growthRange',
    );
  });

  test('a controlled company merges a smaller rival in', () {
    final game = _game();
    final market = game.world.stocks!;
    // The second smallest of a sector and country takes the smallest.
    final small = _smallest(game);
    final sector = _def.listings[small].sector;
    final country = _def.listings[small].country;
    var bigger = -1;
    for (final (n, listing) in _def.listings.indexed) {
      if (n == small ||
          listing.kind != ListingKind.formula ||
          listing.sector != sector ||
          listing.country != country) {
        continue;
      }
      if (bigger < 0 || market.stocks[n].cap < market.stocks[bigger].cap) {
        bigger = n;
      }
    }
    final player = game.world.player;
    _submit(
      game,
      BidForCompany(
        player,
        stock: bigger,
        premium: Fx.parse('0.40'),
        bidder: holdingOwner,
      ),
    );
    _untilClosed(game, market.bids.single.number);
    expect(market.stocks[bigger].controller, holdingOwner);
    final own = market.stocks[bigger].share;
    final theirs = market.stocks[small].share;
    expect(
      _submit(
        game,
        BuyRival(player, via: bigger, stock: small, premium: Fx.parse('0.4')),
      ),
      isNull,
    );
    _untilClosed(game, market.bids.last.number);
    expect(market.bids.last.status, BidStatus.won);
    expect(market.stocks[small].running, isFalse);
    // Its own share drifts a little over the month the bid is open.
    expect(market.stocks[bigger].share > own * 98 ~/ 100 + theirs, isTrue);
  });

  test('a controlled company sold goes to a raider', () {
    final game = _game();
    final i = _smallest(game);
    final player = game.world.player;
    _submit(
      game,
      BidForCompany(
        player,
        stock: i,
        premium: Fx.parse('0.40'),
        bidder: holdingOwner,
      ),
    );
    final market = game.world.stocks!;
    _untilClosed(game, market.bids.single.number);
    final before = _cash(game);
    expect(_submit(game, SellControlled(player, stock: i)), isNull);
    final sale = market.bids.last;
    expect(isRaider(sale.bidder), isTrue);
    _untilClosed(game, sale.number);
    expect(sale.status, BidStatus.won);
    expect(market.playersUnits(i), 0);
    expect(_cash(game) > before, isTrue);
    expect(isRaider(market.stocks[i].controller!), isTrue);
  });

  test('the holding borrows on the shares it buys and repays monthly', () {
    final game = _game();
    final i = _smallest(game);
    final player = game.world.player;
    final market = game.world.stocks!;
    final stock = market.stocks[i];
    final cost = stock.price
        .times(Fx.parse('1.4'))
        .timesInt(stock.shares);
    // Borrow a tenth of it.
    final borrow = Money(cost.cents ~/ 10);
    expect(
      _submit(
        game,
        BidForCompany(
          player,
          stock: i,
          premium: Fx.parse('0.40'),
          bidder: holdingOwner,
          borrow: borrow,
          termMonths: 24,
        ),
      ),
      isNull,
    );
    _untilClosed(game, market.bids.single.number);
    expect(market.bids.single.status, BidStatus.won);
    expect(market.loans, hasLength(1));
    final owed = market.loans.single.outstanding;
    while (!game.today.isFirstOfMonth) {
      game.step();
    }
    game.step();
    expect(market.loans.single.outstanding < owed, isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test("a company of the player's lists, sharing its payouts", () {
    final game = _earning();
    final player = game.world.player;
    final company = game.world.companies[0];
    final cash = company.accounts[AccountKind.cash];
    expect(
      _submit(
        game,
        ListCompany(
          player,
          company: company.id,
          share: Fx.parse('0.25'),
          newShares: true,
        ),
      ),
      isNull,
    );
    final market = game.world.stocks!;
    final i = market.stocks.length - 1;
    final stock = market.stocks[i];
    expect(stock.own!.company, company.id.index);
    expect(stock.listed, isTrue);
    expect(company.accounts[AccountKind.cash] > cash, isTrue);
    // Three quarters are the player's.
    final mine = market.unitsOf(i, holdingOwner);
    expect((mine * 100 / stock.shares).round(), 75);
    expect(
      _submit(
        game,
        ListCompany(
          player,
          company: company.id,
          share: Fx.parse('0.25'),
          newShares: true,
        ),
      )?.key,
      'companyListed',
    );
    final view = game.observe(player);
    expect(view.listedCompanies, [company.id]);
    expect(invariantViolations(game.world), isEmpty);
  });

  test("a listed company of the player's under half can be taken over", () {
    final game = _earning();
    final player = game.world.player;
    final company = game.world.companies[0];
    _submit(
      game,
      ListCompany(
        player,
        company: company.id,
        share: Fx.parse('0.60'),
        newShares: false,
      ),
    );
    final market = game.world.stocks!;
    final i = market.stocks.length - 1;
    final before = _cash(game);
    final bid = openBid(
      game.world,
      null,
      _def,
      market,
      i,
      raiderOwner(0),
      market.stocks[i].price.times(Fx.parse('1.4')),
    );
    _untilClosed(game, bid.number);
    expect(bid.status, BidStatus.won);
    expect(company.owner == player, isFalse);
    expect(market.stocks[i].running, isFalse);
    expect(market.playersUnits(i), 0);
    expect(_cash(game) > before, isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('a game with bids saves, loads and replays to the same state', () {
    final game = _game(seed: 5);
    final i = _smallest(game);
    game.submit(
      BidForCompany(
        game.world.player,
        stock: i,
        premium: Fx.parse('0.40'),
        bidder: holdingOwner,
      ),
    );
    for (var d = 0; d < 50; d++) {
      game.step();
    }
    final loaded = Simulation.load(_content, game.save());
    expect(loaded.stateHash(), game.stateHash());
    for (var d = 0; d < 20; d++) {
      game.step();
      loaded.step();
    }
    expect(loaded.stateHash(), game.stateHash());
    expect(
      Simulation.replay(_content, game.save()).stateHash(),
      game.stateHash(),
    );
  });
}
