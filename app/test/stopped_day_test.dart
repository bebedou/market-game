import 'package:engine/engine.dart';
// What a tick system is, to make one that fails.
import 'package:engine/src/state/world_state.dart';
import 'package:engine/src/systems/tick_system.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/saves.dart';

import 'support.dart';

/// Throws on [day], as an overflow check once did on 1 July 2053.
final class _FailsOn implements TickSystem {
  const _FailsOn(this.day);

  final Day day;

  @override
  void run(WorldState world, TickContext context) {
    if (context.day == day) throw StateError('a sum too big');
  }
}

void main() {
  testWidgets('a day that fails stops the clock there, saves nothing over '
      'the last good day, and says so', (tester) async {
    final saves = MemorySaveStore();
    final start = prototype.startDay;
    final game = SimulationController(
      prototype,
      Simulation.newGame(
        prototype,
        seed: 7,
        systems: [...standardSystems, _FailsOn(start + 2)],
      ),
      saves: saves,
    );
    game
      ..step()
      ..step();
    expect(() => game.step(), throwsStateError);
    expect(game.stopped?.day, start + 2);
    expect(game.stopped?.error, contains('a sum too big'));
    // It won't run again, nor save the day left half done.
    game.setSpeed(Speed.fast);
    expect(game.speed, Speed.paused);
    await game.save();
    expect(saves.file, isNull);
    await pumpGame(tester, game);
    expect(find.textContaining('couldn’t be played'), findsOneWidget);
    final play = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.play_arrow),
        matching: find.byType(IconButton),
      ),
    );
    expect(play.onPressed, isNull);
  });
}
