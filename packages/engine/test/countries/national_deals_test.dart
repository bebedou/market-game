@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/credit.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

final _table = loadCountryTable(
  File('../../content/countries/euro.json').readAsStringSync(),
  File('../../content/countries/calibration.json').readAsStringSync(),
);

final _json = File('../../content/scenarios/prototype.json').readAsStringSync();

/// The scenario with the national figures, its player as rich as [cash].
ContentDb _scenario(String cash) => loadScenario(
  _json.replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "$cash"',
  ),
  national: _table,
);

final _content = _scenario('3000000.00');

final _player = _content.player;
const _company = CompanyId(0);
final _france = _content.countries.firstWhere((c) => c.key == 'fr').id;
final _frIndex = _table.countries.indexWhere((c) => c.key == 'fr');
final _grocery = _table.trades.indexWhere((t) => t.key == 'grocery');
final _grocer = _content.strategies.firstWhere((s) => s.key == 'balanced');

Simulation _game({ContentDb? content, String capital = '500000.00'}) {
  final game = Simulation.newGame(
    content ?? _content,
    seed: 1,
    citiesAsleep: true,
  );
  game.submit(
    InjectCapital(_player, company: _company, amount: Money.parse(capital)),
  );
  expect(game.step().rejections, isEmpty);
  return game;
}

OpenNational _open({int count = 10, int region = 0}) => OpenNational(
  _player,
  company: _company,
  country: _france,
  region: region,
  format: _grocer.format,
  strategy: _grocer.id,
  count: count,
);

List<String> _apply(Simulation game, List<Command> commands) {
  commands.forEach(game.submit);
  return [for (final r in game.step().rejections) r.reason.key];
}

void _advance(Simulation game, int days) {
  for (var i = 0; i < days; i++) {
    game.step();
  }
}

CountryState _fr(Simulation game) => game.national!.countries[_frIndex];

CompanyBlock _own(Simulation game) =>
    _fr(game).blocks.firstWhere((b) => b.company == 0 && b.name == null);

void main() {
  test('rival chains open where shops pay and leave where they do not, '
      "keeping count by region", () {
    CountryEconomy economy({required bool crowded}) {
      final economy = CountryEconomy(_table, seed: 4);
      if (crowded) {
        economy.open(
          _frIndex,
          company: 0,
          trade: _grocery,
          format: 0,
          strategy: 1,
          region: 0,
          count: 600,
          perStore: Money.parse('384000.00'),
          price: Fx.one,
          costs: (
            goods: Fx.parse('0.70'),
            marketing: Fx.parse('0.01'),
            staff: Fx.parse('0.09'),
            premises: Fx.parse('0.07'),
          ),
        );
      }
      for (var month = 0; month < 36; month++) {
        economy.advanceMonth();
      }
      return economy;
    }

    int rivalsIn(CountryEconomy economy, int region) {
      var stores = 0;
      for (final chain in economy.countries[_frIndex].chains) {
        if (chain.def.trade == _grocery) stores += chain.regional[region];
      }
      return stores;
    }

    final alone = economy(crowded: false);
    final crowded = economy(crowded: true);
    // Where the company crowds the region, rivals have opened less there.
    expect(rivalsIn(crowded, 0), lessThan(rivalsIn(alone, 0)));
    for (final chain in crowded.countries[_frIndex].chains) {
      expect(
        chain.stores,
        chain.regional.fold(0, (sum, n) => sum + n),
        reason: chain.def.name,
      );
    }
  });

  test('buying terms grow with what a company buys, in all its shops', () {
    expect(buyingDiscountAt(_content, Money.zero), Fx.zero);
    expect(
      buyingDiscountAt(_content, Money.parse('30000000.00')),
      Fx.parse('0.03'),
    );
    final game = _game();
    final twin = _game();
    expect(_apply(game, [_open(count: 20)]), isEmpty);
    _advance(game, 400);
    _advance(twin, 400);
    final big = game.world.companies[0];
    final small = twin.world.companies[0];
    expect(big.goodsMonths, hasLength(12));
    expect(
      buyingDiscount(_content, big) > buyingDiscount(_content, small),
      isTrue,
    );
    expect(_own(game).discount, buyingDiscount(_content, big));
    // The same order for its shop in Lyon costs it less.
    // The dearest the store lists that a supplier at home carries, for the
    // terms to show in its cents.
    final store = game.world.stores[0];
    final supplier = _content.suppliers.firstWhere(
      (s) => s.country == _content.countries.first.id,
    );
    final product = _content.products
        .where(
          (p) =>
              supplier.carries[p.id.index] && store.prices[p.id.index] != null,
        )
        .reduce((a, b) => a.baseCost > b.baseCost ? a : b);
    PlaceOrder order() => PlaceOrder(
      _player,
      store: const StoreId(0),
      supplier: supplier.id,
      lines: [(product: product.id, quantity: supplier.minOrderUnits)],
    );
    expect(_apply(game, [order()]), isEmpty);
    expect(_apply(twin, [order()]), isEmpty);
    Money paid(Simulation sim) => sim.world.orders
        .lastWhere((o) => o.store == const StoreId(0))
        .lines
        .first
        .unitPrice;
    expect(
      paid(game) < paid(twin),
      isTrue,
      reason: '${paid(game)} ${paid(twin)}',
    );
    expect(invariantViolations(game.world), isEmpty);
  });

  test("the owner's factory makes for its shops across the country", () {
    final game = _game();
    final drinks = _content.factories!.kinds.firstWhere(
      (k) => k.key == 'drinks',
    );
    expect(
      _apply(game, [
        BuildFactory(
          _player,
          kind: drinks.id,
          country: _france,
          name: 'Boissons',
          company: _company,
          shifts: 2,
        ),
        _open(count: 10),
      ]),
      isEmpty,
    );
    _advance(game, drinks.buildDays + 70);
    final factory = game.world.factories.single;
    expect(factory.recentOwnUnits(game.today), greaterThan(0));
    final company = game.world.companies[0];
    // Made for its own shops, never counted as sales.
    expect(company.accounts[AccountKind.ownGoods], isNot(Money.zero));
    expect(invariantViolations(game.world), isEmpty);
  });

  test("a director spends on marketing what pays best, building the brand's "
      'pull', () {
    final game = _game(capital: '2000000.00');
    game.submit(
      HireDirector(
        _player,
        company: _company,
        grade: _content.directors!.grades.last.id,
        strategy: _grocer.id,
        managerGrade: _content.managers.grades.last.id,
        growth: Growth.open,
        payout: false,
        nationalPace: 5,
        nationalRegions: const ['FRE', 'FRF', 'FR1'],
      ),
    );
    _advance(game, 500);
    final block = _own(game);
    expect(block.marketing >= _grocer.marketingShare, isTrue);
    expect(block.goodwill > Money.zero, isTrue);
    expect(
      game.national!.brandFactor(_fr(game), _grocery, block) > Fx.one,
      isTrue,
    );
  });

  test('a chain is bought whole at its price, its shops then the '
      "company's, under its name", () {
    final rich = _scenario('5000000000.00');
    final game = _game(content: rich, capital: '1000.00');
    _advance(game, 40);
    final country = _fr(game);
    final (:chain, :format, :strategy) = _cheapest(rich, game);
    final value = valueChainOf(rich, game, chain);
    BuyNationalChain buy() => BuyNationalChain(
      _player,
      company: _company,
      country: _france,
      chain: country.chains.indexOf(chain),
      format: format,
      strategy: strategy,
    );
    // Without the cash, it can't.
    expect(_apply(game, [buy()]), ['cannotPayPrice']);
    final stores = chain.stores;
    expect(
      _apply(game, [
        InjectCapital(_player, company: _company, amount: value.timesInt(2)),
      ]),
      isEmpty,
    );
    expect(_apply(game, [buy()]), isEmpty);
    final block = country.blocks.single;
    expect(block.name, chain.def.name);
    expect(block.stores, stores);
    expect(chain.isTrading, isFalse);
    expect(chain.boughtBy, 0);
    final company = game.world.companies[0];
    expect(company.accounts[AccountKind.businessAssets], value);
    // Gone, it can't be bought again.
    expect(_apply(game, [buy()]), ['chainNotForSale']);
    _advance(game, 60);
    expect(block.months, isNotEmpty);
    expect(block.months.last.sales > Money.zero, isTrue);
    expect(invariantViolations(game.world), isEmpty);
  });

  test(
    'its shops are sold to the chain with the most cash, at their price',
    () {
      final game = _game();
      expect(_apply(game, [_open(count: 12)]), isEmpty);
      _advance(game, 120);
      final country = _fr(game);
      final block = _own(game);
      final view = game
          .observe(_player)
          .national
          .firstWhere((n) => n.country == _france);
      final mine = view.blocks.single;
      final buyer = country.chains.firstWhere((c) => c.def.name == mine.buyer);
      final before = buyer.stores;
      final cash = game.world.companies[0].accounts[AccountKind.cash];
      expect(
        _apply(game, [
          SellNational(
            _player,
            company: _company,
            country: _france,
            block: country.blocks.indexOf(block),
          ),
        ]),
        isEmpty,
      );
      expect(country.blocks, isEmpty);
      expect(buyer.stores, before + 12);
      expect(game.world.companies[0].accounts[AccountKind.cash] > cash, isTrue);
      expect(invariantViolations(game.world), isEmpty);
    },
  );

  test("a chain's offer is accepted, or turned down", () {
    final game = _game();
    expect(_apply(game, [_open(count: 12)]), isEmpty);
    _advance(game, 120);
    final economy = game.national!;
    final country = _fr(game);
    final block = _own(game);
    final chain = country.chains.firstWhere(
      (c) => c.def.trade == _grocery && !c.def.independent,
    );
    NationalOffer offer(Money price) {
      final made = NationalOffer(
        number: economy.nextOffer++,
        country: _frIndex,
        block: block,
        chain: chain,
        price: price,
        expires: game.today + 30,
      );
      economy.offers.add(made);
      return made;
    }

    final declined = offer(Money.parse('100000.00'));
    expect(
      _apply(game, [DeclineNationalOffer(_player, offer: declined.number)]),
      isEmpty,
    );
    expect(economy.offers, isEmpty);
    expect(country.blocks, contains(block));
    final accepted = offer(Money.parse('900000.00'));
    final before = chain.stores;
    final cash = game.world.companies[0].accounts[AccountKind.cash];
    expect(
      _apply(game, [AcceptNationalOffer(_player, offer: accepted.number)]),
      isEmpty,
    );
    expect(country.blocks, isEmpty);
    expect(chain.stores, before + 12);
    expect(
      game.world.companies[0].accounts[AccountKind.cash] - cash >=
          Money.parse('900000.00') - Money.parse('50000.00'),
      isTrue,
    );
    expect(
      _apply(game, [AcceptNationalOffer(_player, offer: accepted.number)]),
      ['unknownOffer'],
    );
  });

  test("the bank lends on the shops' earnings, and the company is worth "
      'more', () {
    final game = _game();
    final twin = _game();
    expect(_apply(game, [_open(count: 20)]), isEmpty);
    twin.step();
    _advance(game, 200);
    _advance(twin, 200);
    final company = game.world.companies[0];
    final other = twin.world.companies[0];
    expect(
      earningsRoom(game.world, _content, company) >
          earningsRoom(twin.world, _content, other),
      isTrue,
    );
  });

  test('saves, loads and replays the same, with a chain bought and an '
      'offer open', () {
    final rich = _scenario('5000000000.00');
    final game = _game(content: rich, capital: '1000.00');
    _advance(game, 40);
    final country = _fr(game);
    final (:chain, :format, :strategy) = _cheapest(rich, game);
    final value = valueChainOf(rich, game, chain);
    expect(
      _apply(game, [
        InjectCapital(_player, company: _company, amount: value.timesInt(2)),
      ]),
      isEmpty,
    );
    expect(
      _apply(game, [
        BuyNationalChain(
          _player,
          company: _company,
          country: _france,
          chain: country.chains.indexOf(chain),
          format: format,
          strategy: strategy,
        ),
      ]),
      isEmpty,
    );
    final economy = game.national!;
    economy.offers.add(
      NationalOffer(
        number: economy.nextOffer++,
        country: _frIndex,
        block: country.blocks.single,
        chain: country.chains.firstWhere(
          (c) =>
              c.def.trade == chain.def.trade &&
              c.isTrading &&
              !c.def.independent,
        ),
        price: Money.parse('1000000.00'),
        expires: game.today + 30,
      ),
    );
    _advance(game, 10);
    final loaded = Simulation.load(rich, game.save());
    expect(loaded.stateHash(), game.stateHash());
    expect(loaded.national!.offers.single.price, Money.parse('1000000.00'));
    expect(
      loaded.national!.countries[_frIndex].blocks.single.name,
      chain.def.name,
    );
    _advance(game, 40);
    _advance(loaded, 40);
    expect(loaded.stateHash(), game.stateHash());
  });
}

/// The cheapest chain of France to buy whole in [game], the kind of shop
/// its trade's shops run as, and a strategy for it.
({Chain chain, FormatId format, StrategyId strategy}) _cheapest(
  ContentDb content,
  Simulation game,
) {
  final country = _fr(game);
  Chain? best;
  for (final chain in country.chains) {
    if (chain.def.independent || !chain.isTrading) continue;
    if (best == null ||
        valueChainOf(content, game, chain) <
            valueChainOf(content, game, best)) {
      best = chain;
    }
  }
  final trade = game.national!.table.trades[best!.def.trade].key;
  final format = content.formats.firstWhere(
    (f) => f.national != null && formatTrades[f.key] == trade,
  );
  final strategy = content.strategies.firstWhere((s) => s.format == format.id);
  return (chain: best, format: format.id, strategy: strategy.id);
}

/// What [chain] sells for in [game], as the commands price it.
Money valueChainOf(ContentDb content, Simulation game, Chain chain) {
  final view = game
      .observe(content.player)
      .national
      .firstWhere((n) => n.country == _france);
  return view.chains.firstWhere((c) => c.name == chain.def.name).value!.price;
}
