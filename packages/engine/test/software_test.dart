import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:engine/src/state/software.dart';
import 'package:engine/src/state/software_rules.dart';
import 'package:engine/src/state/talent.dart';
import 'package:engine/src/systems/software.dart';
import 'package:engine/src/systems/tick_system.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The test town with a software market of a million customers at 10 a
/// month, half with one rival two points over the standard and half with
/// everyone else at it. People are of two levels, power 1 at 100 a month or
/// power 3 at 300; a month of power 1 builds a point; the standard rises a
/// point a month; a new product starts ten points under it and sells once
/// within five. A tenth of every product's customers leave each month.
final softwareContent = loadScenario(
  testScenarioJson
      .replaceFirst(
        '"name": "Player", "cash": "1000.00"',
        '"name": "Player", "cash": "100000.00"',
      )
      .replaceFirst('  "suppliers": [', '''
  "software": {
    "customers": 1000000, "price": "10.00", "growth": "0", "cycle": "0",
    "standard": "1.00", "rise": "0.01", "startGap": "0.10", "launchGap": "0.05",
    "progress": "0.01", "designerBuild": "0.5", "decay": "0.5", "hardness": "0", "appeal": "0.02",
    "draw": "10", "drawFloor": "-4", "drawCap": "3", "priceElasticity": 1,
    "churn": "0.10", "churnSteepness": "0", "minChurn": "0", "maxChurn": "1",
    "marketingScale": "100.00", "reachPerCustomer": 100, "serving": "0.20", "office": "0",
    "maxPeople": 2, "candidates": 6, "candidateDays": 60, "revealMonths": 2,
    "levels": [
      { "share": "0.50", "power": "1", "salary": "100.00" },
      { "share": "0.50", "power": "3", "salary": "300.00" }
    ],
    "firstNames": ["Ada"], "lastNames": ["Roux"],
    "baseMultiple": "2", "growthMultiple": "0", "minMultiple": "1", "maxMultiple": "10",
    "valuationCycle": "0", "teamMonths": 10, "teamPaceCap": "3",
    "maxRoundShare": "0.25", "roundMonths": 2,
    "offerChance": "1", "offerRevenue": "1.00", "minPremium": "1.5", "maxPremium": "1.5", "offerDays": 30,
    "foundingChance": "0", "startupTeam": 2, "startupMarketing": "0", "startupPrice": "1",
    "foldMonths": 12, "foldCustomers": 0, "startupNames": ["Nova"],
    "paceSpread": "0", "response": "0",
    "rivals": [
      { "name": "Big", "share": "0.50", "lead": "0.02", "price": "1", "marketing": "0" },
      { "name": "Everyone else", "share": "0.50", "lead": "0", "price": "1", "marketing": "0", "rest": true }
    ]
  },
  "suppliers": ['''),
);

/// The quiet pipeline with the software market run before settlement.
final softwareSystems = <TickSystem>[
  for (final system in quietSystems) ...[
    if (system.runtimeType.toString() == 'SettlementSystem')
      const SoftwareSystem(),
    system,
  ],
];

void main() {
  Simulation newGame() =>
      Simulation.newGame(softwareContent, seed: 1, systems: softwareSystems);

  /// A game with the player's software company started with [capital].
  (Simulation, Software) started({String capital = '50000.00'}) {
    final game = newGame();
    game.submit(
      StartSoftware(
        player,
        name: 'Tessel',
        country: softwareContent.countries.first.id,
        capital: Money.parse(capital),
      ),
    );
    game.step();
    return (game, game.world.software.single);
  }

  /// Hires the first software candidate, of [level] if given, into
  /// [software].
  KeyPerson hire(Simulation game, Software software, [int? level]) {
    final person = game.world.keyPeople.firstWhere(
      (p) =>
          p.forSoftware &&
          p.status == KeyStatus.candidate &&
          (level == null || p.level == level),
    );
    game.submit(
      HireSoftwarePerson(player, software: software.id, person: person.id),
    );
    game.step();
    return person;
  }

  void toNextMonth(Simulation game) {
    do {
      game.step();
    } while (!game.today.isFirstOfMonth);
    // The first of the month itself, when the market turns.
    game.step();
  }

  int allCustomers(Simulation game) =>
      game.world.softwareMarket!.rivals.fold(
        0,
        (sum, rival) => sum + rival.customers,
      ) +
      game.world.software.fold(0, (sum, s) => sum + s.customers);

  test('a new world opens the software market as the scenario sets it out', () {
    final game = newGame();
    final market = game.world.softwareMarket!;
    expect(market.customers, 1000000);
    expect(market.standard, Fx.one);
    expect(market.rivals.map((r) => r.customers), [500000, 500000]);
    expect(market.rest.name, 'Everyone else');
  });

  test('a software company is a company of its own, building its product', () {
    final (game, software) = started();
    final company = game.world.companies[software.company.index];
    expect(company.owner, player);
    expect(company.accounts[AccountKind.cash], Money.parse('50000.00'));
    expect(software.status, SoftwareStatus.building);
    expect(software.level, Fx.parse('0.90'));
    expect(software.price, Money.parse('10.00'));
    expect(software.stake, Fx.one);
    // Shops can't open in it.
    game.submit(
      OpenStore(player, site: lane, name: 'Corner', company: software.company),
    );
    final result = game.step();
    expect(result.rejections.single.reason.key, 'softwareOnly');
  });

  test('starting one takes a name and the cash', () {
    final game = newGame();
    for (final (command, key) in [
      (
        StartSoftware(
          player,
          name: ' Tessel',
          country: softwareContent.countries.first.id,
        ),
        'nameRule',
      ),
      (
        StartSoftware(
          player,
          name: 'Tessel',
          country: softwareContent.countries.first.id,
          capital: Money.parse('200000.00'),
        ),
        'notEnoughHoldingCash',
      ),
    ]) {
      game.submit(command);
      expect(game.step().rejections.single.reason.key, key);
    }
  });

  test('its people build it month by month, and it sells once near enough', () {
    final (game, software) = started();
    final person = hire(game, software, 1);
    expect(person.software, software.id);
    expect(softwarePeople(game.world, software.id), [person]);
    final launches = <SoftwareLaunched>[];
    final before = software.level;
    var months = 0;
    while (software.status == SoftwareStatus.building) {
      do {
        launches.addAll(game.step().events.whereType<SoftwareLaunched>());
      } while (!game.today.isFirstOfMonth);
      launches.addAll(game.step().events.whereType<SoftwareLaunched>());
      months++;
    }
    // Power 3 at a point a month, or 1 if a designer, who builds at half.
    final pace = person.role == KeyRole.engineer
        ? Fx.parse('0.03')
        : Fx.parse('0.015');
    expect(software.level, before + pace.timesInt(months));
    expect(
      software.level >= game.world.softwareMarket!.standard - Fx.parse('0.05'),
      isTrue,
    );
    expect(launches.single.software, software.id);
    expect(software.launchedOn, isNotNull);
  });

  test('a team holds as many as the scenario allows, software people only', () {
    final (game, software) = started();
    hire(game, software);
    hire(game, software);
    final third = game.world.keyPeople.firstWhere(
      (p) => p.forSoftware && p.status == KeyStatus.candidate,
    );
    game.submit(
      HireSoftwarePerson(player, software: software.id, person: third.id),
    );
    expect(game.step().rejections.single.reason.key, 'teamFull');
  });

  test('customers go where they are drawn, and none are lost', () {
    final (game, software) = started();
    hire(game, software, 1);
    while (software.status == SoftwareStatus.building) {
      toNextMonth(game);
    }
    game.submit(
      SetSoftwareMarketing(
        player,
        software: software.id,
        budget: Money.parse('1000.00'),
      ),
    );
    for (var month = 0; month < 6; month++) {
      toNextMonth(game);
      expect(allCustomers(game), game.world.softwareMarket!.customers);
    }
    expect(software.customers, greaterThan(0));
    expect(software.history, isNotEmpty);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('customers pay a day of their month every day', () {
    final (game, software) = started();
    software
      ..status = SoftwareStatus.selling
      ..customers = 3100;
    final company = game.world.companies[software.company.index];
    final revenue = company.accounts[AccountKind.revenue];
    final day = game.step();
    // 3,100 at 10 a month over January's 31 days, less nothing else.
    expect(day.day.date.month, 1);
    expect(
      company.accounts[AccountKind.revenue] - revenue,
      -Money.parse('1000.00'),
    );
  });

  test('a round sells a share to investors at what the company is worth', () {
    final (game, software) = started();
    hire(game, software, 1);
    final def = softwareContent.software!;
    final worth = softwareWorth(game.world, softwareContent, def, software);
    final company = game.world.companies[software.company.index];
    final cash = company.accounts[AccountKind.cash];
    game.submit(
      RaiseRound(player, software: software.id, share: Fx.parse('0.20')),
    );
    game.step();
    final round = software.rounds.single;
    expect(round.value, worth.worth);
    expect(round.money, roundMoney(worth.worth, Fx.parse('0.20')));
    expect(software.investors, Fx.parse('0.20'));
    expect(software.stake, Fx.parse('0.80'));
    expect(company.accounts[AccountKind.cash] > cash, isTrue);
    // The next waits two months, and none sells more than a quarter.
    for (final (share, key) in [
      (Fx.parse('0.10'), 'roundTooSoon'),
      (Fx.parse('0.30'), 'roundShareRange'),
    ]) {
      game.submit(RaiseRound(player, software: software.id, share: share));
      expect(game.step().rejections.single.reason.key, key);
    }
  });

  test("dividends go to the owner and the investors by their shares", () {
    final (game, software) = started();
    software.investors = Fx.parse('0.40');
    final company = game.world.companies[software.company.index];
    // Profit to pay out from: a month's revenue booked by hand.
    software
      ..status = SoftwareStatus.selling
      ..customers = 31000;
    game.step();
    final owner = game.world.persons[player.index];
    final cash = owner.accounts[AccountKind.cash];
    game.submit(
      PayDividend(player, company: company.id, amount: Money.parse('1000.00')),
    );
    final result = game.step();
    expect(result.rejections, isEmpty);
    // 600 to the owner, less the dividend tax.
    final taxes = softwareContent.taxesOf(softwareContent.countries.first.id);
    final tax = taxes == null
        ? Money.zero
        : Money.parse('600.00').times(taxes.dividendRate);
    expect(
      owner.accounts[AccountKind.cash] - cash,
      Money.parse('600.00') - tax,
    );
  });

  test('a rival buys the company: the owner gets their share, it ends', () {
    final (game, software) = started();
    hire(game, software, 1);
    software
      ..status = SoftwareStatus.selling
      ..customers = 10000
      ..investors = Fx.parse('0.25');
    toNextMonth(game);
    final offer = software.offer!;
    final big = game.world.softwareMarket!.rivals.first;
    expect(offer.rival, big.id);
    final bigCustomers = big.customers;
    final customers = software.customers;
    final owner = game.world.persons[player.index];
    final cash = owner.accounts[AccountKind.cash];
    final company = game.world.companies[software.company.index];
    final injected = company.injected;
    game.submit(AcceptSoftwareOffer(player, software: software.id));
    game.step();
    expect(software.status, SoftwareStatus.sold);
    expect(company.status, CompanyStatus.sold);
    expect(company.accounts[AccountKind.cash], Money.zero);
    expect(big.customers, bigCustomers + customers);
    expect(softwarePeople(game.world, software.id), isEmpty);
    final proceeds = offer.price.times(Fx.parse('0.75'));
    final taxes = softwareContent.taxesOf(softwareContent.countries.first.id);
    final gain = proceeds - injected;
    final tax = taxes == null || gain <= Money.zero
        ? Money.zero
        : gain.times(taxes.dividendRate);
    expect(owner.accounts[AccountKind.cash] - cash, proceeds - tax);
    expect(invariantViolations(game.world), isEmpty);
  });

  test('shutting down lets its people go and its customers leave', () {
    final (game, software) = started();
    hire(game, software);
    software
      ..status = SoftwareStatus.selling
      ..customers = 5000;
    final rest = game.world.softwareMarket!.rest;
    final restCustomers = rest.customers;
    game.submit(ShutDownSoftware(player, software: software.id));
    game.step();
    expect(software.status, SoftwareStatus.closed);
    expect(software.customers, 0);
    expect(rest.customers, restCustomers + 5000);
    expect(softwarePeople(game.world, software.id), isEmpty);
    game.submit(
      SetSoftwarePrice(
        player,
        software: software.id,
        price: Money.parse('9.00'),
      ),
    );
    expect(game.step().rejections.single.reason.key, 'softwareClosed');
  });

  test('a software company survives a save', () {
    final (game, software) = started();
    hire(game, software, 1);
    game.submit(
      RaiseRound(player, software: software.id, share: Fx.parse('0.25')),
    );
    for (var day = 0; day < 70; day++) {
      game.step();
    }
    final loaded = Simulation.load(
      softwareContent,
      game.save(),
      systems: softwareSystems,
    );
    expect(loaded.stateHash(), game.stateHash());
    final view = loaded
        .observe(player)
        .companies
        .firstWhere((c) => c.id == software.company)
        .software!;
    expect(view.rounds, hasLength(1));
    expect(view.team, hasLength(1));
  });

  test('its owner sees how far it is from selling and what it is worth', () {
    final (game, software) = started();
    hire(game, software, 1);
    final view = game
        .observe(player)
        .companies
        .firstWhere((c) => c.id == software.company)
        .software!;
    expect(view.status, SoftwareStatus.building);
    // The standard rose a point on the first of the month it started.
    expect(view.toLaunch, Fx.parse('0.06'));
    expect(view.monthsToLaunch, isNotNull);
    expect(view.team.single.salary, isNot(Money.zero));
    expect(view.worth.worth > Money.zero, isTrue);
    final market = game.observe(player).softwareMarket!;
    expect(market.rivals.map((r) => r.name), ['Big', 'Everyone else']);
    expect(market.rivals.first.lead, Fx.parse('0.02'));
  });
}
