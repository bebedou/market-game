import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

final _content = loadScenario(testScenarioJson);

void main() {
  test('a holding start begins with the money chosen, within a range', () {
    final usual = startTerms(_content, const GameStart.holding('H')).$1!;
    final chosen = startTerms(
      _content,
      GameStart.holding('H', cash: Money.parse('250000.00')),
    ).$1!;
    expect(chosen.personalCash, Money.parse('250000.00'));
    expect(chosen.personalCash, isNot(usual.personalCash));
    for (final cash in [Money.parse('9999.99'), maxStartingCash + Money(1)]) {
      expect(
        startTerms(_content, GameStart.holding('H', cash: cash)).$2?.key,
        'startCashRange',
      );
    }
    final game = Simulation.newGame(
      _content,
      seed: 1,
      start: GameStart.holding('Bebedou', cash: Money.parse('250000.00')),
    );
    expect(
      game.world.persons[player.index].accounts[AccountKind.cash],
      Money.parse('250000.00'),
    );
    // Replayed, it starts the same way.
    expect(
      Simulation.replay(_content, game.save()).stateHash(),
      game.stateHash(),
    );
  });

  test('the holding is named at the start, renamed since, and kept in a '
      'save', () {
    final game = Simulation.newGame(
      _content,
      seed: 1,
      start: const GameStart.holding('Bebedou'),
    );
    expect(game.observe(player).holdingName, 'Bebedou');
    game.submit(const RenameHolding(player, name: 'Hénon Capital'));
    expect(game.step().rejections, isEmpty);
    expect(game.observe(player).holdingName, 'Hénon Capital');
    expect(game.observe(rival).holdingName, isNull);
    game.submit(const RenameHolding(rival, name: 'Pas à moi'));
    expect(game.step().rejections.single.reason.key, 'notYourCompany');
    final loaded = Simulation.load(_content, game.save());
    expect(loaded.world.holdingName, 'Hénon Capital');
    expect(loaded.stateHash(), game.stateHash());
  });
}
