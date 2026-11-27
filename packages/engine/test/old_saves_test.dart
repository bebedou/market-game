// Reads fixtures and content from disk, which only the VM can.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The prototype the fixtures were played on: the player rich enough for
/// shops across France and a drinks plant, with the national figures.
ContentDb content({String Function(String)? national}) => loadScenario(
  File(
    '../../content/scenarios/prototype.json',
  ).readAsStringSync().replaceFirst(
    '"name": "You", "cash": "20000.00"',
    '"name": "You", "cash": "600000.00"',
  ),
  national: loadCountryTable(
    (national ?? (json) => json)(
      File('../../content/countries/euro.json').readAsStringSync(),
    ),
    File('../../content/countries/calibration.json').readAsStringSync(),
  ),
);

/// A fixture: 150 days of a game, seed 11, the other cities asleep, three
/// grocers opened across France and a drinks plant built on the first day.
/// The format 32 one also set a lab going on day 60 with the first
/// candidate hired. Written by the commit before each format change.
SaveFile fixture(String name) => SaveFile(
  Uint8List.fromList(
    gzip.decode(File('test/fixtures/$name.bin.gz').readAsBytesSync()),
  ),
);

FactoryView plant(Simulation game) => game
    .observe(game.content.player)
    .companies
    .expand((company) => company.factories)
    .single;

/// Plays [days] more and checks the books hold and a save of it reads back
/// as the same game, from [scenario], the content it was loaded with.
void playOn(Simulation game, ContentDb scenario, {int days = 60}) {
  for (var day = 0; day < days; day++) {
    game.step();
  }
  expect(invariantViolations(game.world), isEmpty);
  final again = Simulation.load(scenario, game.save());
  expect(again.stateHash(), game.stateHash());
}

void main() {
  test('a save from before labs (format 31) loads and plays on', () {
    final scenario = content();
    final game = Simulation.load(scenario, fixture('save_v31'));
    expect(game.world.today, isNot(game.content.startDay));
    expect(game.national, isNotNull);
    expect(invariantViolations(game.world), isEmpty);
    final factory = plant(game);
    expect(factory.lab!.budget, Money.zero);
    expect(factory.lab!.people, isEmpty);
    for (final line in factory.lab!.lines) {
      expect(line.lead, Fx.zero);
    }
    final view = game.observe(game.content.player);
    for (final store in view.companies.expand((company) => company.stores)) {
      for (final product in game.content.products) {
        expect(store.qualityOf(product.id), Fx.zero);
      }
    }
    playOn(game, scenario);
  });

  test('a save with a lab (format 32) keeps it, and its people', () {
    final scenario = content();
    final game = Simulation.load(scenario, fixture('save_v32'));
    final lab = plant(game).lab!;
    expect(lab.budget, Money.parse('1500.00'));
    expect(lab.project, isNotNull);
    expect(lab.people, hasLength(1));
    expect(lab.work > Money.zero, isTrue);
    playOn(game, scenario, days: 120);
    // Its work goes on: four months on, a generation has come or is nearer.
    final later = plant(game).lab!;
    expect(later.people, hasLength(1));
    expect(
      later.work != lab.work || later.lines.any((line) => line.lead > Fx.zero),
      isTrue,
    );
  });

  test('a save with a district and a city woken before clothing loads, '
      'and the city has no clothing shops', () {
    // 120 days, seed 12, the other cities asleep, row 0 woken on day 20 and
    // the last row, Barcelona, on day 40; the scenario as it was.
    final plain = loadScenario(
      File('../../content/scenarios/prototype.json').readAsStringSync(),
      national: loadCountryTable(
        File('../../content/countries/euro.json').readAsStringSync(),
        File('../../content/countries/calibration.json').readAsStringSync(),
      ),
    );
    final game = Simulation.load(plain, fixture('save_v33_woken'));
    expect(
      [for (final wake in game.woken) wake.row],
      [0, game.content.neighbourhoods.length - 1],
    );
    expect(invariantViolations(game.world), isEmpty);
    final barcelona = game.content.markets.firstWhere(
      (market) => market.name == 'Barcelona, Gràcia',
    );
    final clothing = game.content.formats.firstWhere(
      (f) => f.key == 'clothing',
    );
    expect(
      game.world.stores.where(
        (store) => store.market == barcelona.id && store.format == clothing.id,
      ),
      isEmpty,
    );
    // The player's city gained the clothing sites, after the woken ones.
    expect(
      game.content.sites.where((site) => site.key.contains('_clothes_')),
      hasLength(2),
    );
    playOn(game, plain);
  });

  test('a save made with other national figures is refused, not misread', () {
    final game = Simulation.load(content(), fixture('save_v32'));
    game.step();
    final saved = game.save();
    // The same table loads; figures may change, rows may not.
    expect(() => Simulation.load(content(), saved), returnsNormally);
    expect(
      () => Simulation.load(
        content(
          national: (json) =>
              json.replaceFirst('"Hansemarkt"', '"Hansemarkt Nord"'),
        ),
        saved,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('national figures'),
        ),
      ),
    );
  });

  test("a holding saved at format 42, before mergers, a start's cash and "
      "the holding's own name, loads with the name it started with", () {
    // Written by 151811b on the test town: a holding start named Old
    // Holding, seed 7, 40 days.
    final scenario = loadScenario(testScenarioJson);
    final game = Simulation.load(scenario, fixture('save_v42_holding'));
    expect(game.world.holdingName, 'Old Holding');
    expect(game.world.start!.cash, isNull);
    expect(
      game.world.companies.where((company) => company.mergedInto != null),
      isEmpty,
    );
    expect(invariantViolations(game.world), isEmpty);
    playOn(game, scenario);
  });

  test("a save of format 42 in format 43's layout, as the builds after "
      '151811b wrote it, loads with what it holds', () {
    // Written as those builds did: a holding start named Mid Holding with
    // 250,000, renamed Renamed Holding on the first day, seed 7, 40 days.
    final scenario = loadScenario(testScenarioJson);
    final game = Simulation.load(scenario, fixture('save_v42_between'));
    expect(game.world.holdingName, 'Renamed Holding');
    expect(game.world.start!.cash, Money.parse('250000.00'));
    expect(invariantViolations(game.world), isEmpty);
    playOn(game, scenario);
  });

  test('a save from before shops were sized as they open (format 44) loads '
      'with its works done, its supermarkets as grocers, and those by '
      'formula with its other grocers', () {
    // Written by c2eec76: seed 13, the other cities asleep, a shop being
    // made a supermarket and the corner shop being enlarged, its manager
    // trusted with investing, both works in the log, and in France five
    // supermarkets and then ten grocers by formula being fitted out. Its works
    // finished, that build had the first at 220 m², 18 slots and 5,500 of
    // storage, and the corner shop at 160 m², 10 slots and 2,000.
    final scenario = content();
    final game = Simulation.load(scenario, fixture('save_v44_sizes'));
    final grocery = scenario.formats.firstWhere((f) => f.key == 'grocery');
    final big = game.world.stores.firstWhere((s) => s.name == 'To Be Big');
    expect(
      (big.format, big.area, big.shelfSlots, big.storageUnits),
      (grocery.id, 220, 18, 5500),
    );
    expect(grocery.isLargeAt(big.area), isTrue);
    final corner = game.world.stores.firstWhere((s) => s.name == 'Corner Shop');
    expect(
      (corner.area, corner.shelfSlots, corner.storageUnits),
      (160, 10, 2000),
    );
    expect(
      corner.manager!.duties,
      List.filled(ManagerDuty.values.length, true),
    );
    final france = game.national!.countries.firstWhere(
      (country) => country.def.key == 'fr',
    );
    // The five supermarkets, opened first, join the ten grocers, which keep
    // their draw and figures: the bigger block is the one kept.
    final blocks = [
      for (final block in france.blocks)
        if (block.company == 0) block,
    ];
    expect(
      [for (final block in blocks) (block.format, block.stores)],
      [(grocery.id.index, 15)],
    );
    expect(blocks.single.pull, const Fx.raw(2436));
    expect(blocks.single.perStore, Money.parse('384000.00'));
    // Enlarging and converting are gone from the log.
    expect(game.commandLog, hasLength(5));
    expect(invariantViolations(game.world), isEmpty);
    playOn(game, scenario);
  });

  test('a save from before fixed assets (format 46 or earlier) recognises '
      'its fittings at their worn cost, against a reserve', () {
    final scenario = content();
    final game = Simulation.load(scenario, fixture('save_v44_sizes'));
    final world = game.world;
    final company = world.companies[0];
    final accounts = company.accounts;
    // Its shops in full and across France carry their fittings now.
    final mine = world.stores.where(
      (s) => s.company == company.id && s.isTrading,
    );
    expect(mine.every((s) => s.fittings > Money.zero), isTrue);
    final france = game.national!.countries.firstWhere(
      (country) => country.def.key == 'fr',
    );
    final block = france.blocks.firstWhere((b) => b.company == 0);
    expect(block.fittings > Money.zero, isTrue);
    expect(accounts[AccountKind.fixedAssets] > Money.zero, isTrue);
    // Recognised against the reserve, not profit: none of its shops was
    // bought, so the reserve stands for all of them, and nothing has worn
    // yet.
    expect(accounts[AccountKind.reserves], -accounts[AccountKind.fixedAssets]);
    expect(accounts[AccountKind.depreciation], Money.zero);
    // Chains by formula carry theirs too.
    expect(france.chains.any((c) => c.fittings > Money.zero), isTrue);
    expect(invariantViolations(world), isEmpty);
    playOn(game, scenario);
    expect(accounts[AccountKind.depreciation] > Money.zero, isTrue);
  });
}
