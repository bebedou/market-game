// Reads fixtures and content from disk, which only the VM can.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

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
/// as the same game.
void playOn(Simulation game, {int days = 60}) {
  for (var day = 0; day < days; day++) {
    game.step();
  }
  expect(invariantViolations(game.world), isEmpty);
  final again = Simulation.load(game.content, game.save());
  expect(again.stateHash(), game.stateHash());
}

void main() {
  test('a save from before labs (format 31) loads and plays on', () {
    final game = Simulation.load(content(), fixture('save_v31'));
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
    playOn(game);
  });

  test('a save with a lab (format 32) keeps it, and its people', () {
    final game = Simulation.load(content(), fixture('save_v32'));
    final lab = plant(game).lab!;
    expect(lab.budget, Money.parse('1500.00'));
    expect(lab.project, isNotNull);
    expect(lab.people, hasLength(1));
    expect(lab.work > Money.zero, isTrue);
    playOn(game, days: 120);
    // Its work goes on: four months on, a generation has come or is nearer.
    final later = plant(game).lab!;
    expect(later.people, hasLength(1));
    expect(
      later.work != lab.work || later.lines.any((line) => line.lead > Fx.zero),
      isTrue,
    );
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
}
