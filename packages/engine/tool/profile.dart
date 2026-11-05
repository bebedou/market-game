// Times where a simulated day goes: each tick system, each AI's decision,
// and the rest (observations, commands, managers), for one seed.
//
//   dart run tool/profile.dart [scenario] [days]
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/world_state.dart';
import 'package:engine/src/systems/tick_system.dart';

final _clocks = <String, Stopwatch>{};

Stopwatch _clock(String name) => _clocks.putIfAbsent(name, Stopwatch.new);

final class _TimedSystem implements TickSystem {
  _TimedSystem(this.system);

  final TickSystem system;

  @override
  void run(WorldState world, TickContext context) {
    final clock = _clock('system ${system.runtimeType}')..start();
    system.run(world, context);
    clock.stop();
  }
}

final class _TimedPolicy implements Policy {
  _TimedPolicy(this.policy);

  final Policy policy;

  @override
  List<Command> decide(Observation view, ContentDb content) {
    final clock = _clock('decide')..start();
    final commands = policy.decide(view, content);
    clock.stop();
    return commands;
  }
}

void main(List<String> args) {
  final scenario = args.isEmpty ? 'prototype' : args[0];
  final days = args.length > 1 ? int.parse(args[1]) : 2000;
  final path = scenario.endsWith('.json')
      ? scenario
      : Platform.script
            .resolve('../../../content/scenarios/$scenario.json')
            .toFilePath();
  final content = loadScenario(File(path).readAsStringSync());
  final policies = {
    for (final MapEntry(:key, :value) in standardPolicies(content).entries)
      key: _TimedPolicy(value),
    content.player: _TimedPolicy(
      ownerPolicy(content.strategies.firstWhere((s) => s.key == 'discount')),
    ),
  };
  final simulation = Simulation.newGame(
    content,
    seed: 1,
    systems: [for (final system in standardSystems) _TimedSystem(system)],
    policies: policies,
  );
  final total = Stopwatch()..start();
  for (var i = 0; i < days; i++) {
    simulation.step();
  }
  total.stop();
  final observe = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    for (final actor in policies.keys) {
      simulation.observe(actor);
    }
  }
  observe.stop();
  final measured = _clocks.values.fold(
    0,
    (sum, c) => sum + c.elapsedMicroseconds,
  );
  stdout.writeln(
    '$days days in ${total.elapsedMilliseconds} ms '
    '(${(total.elapsedMicroseconds / days / 1000).toStringAsFixed(2)} ms a day); '
    '${simulation.world.cohorts.length} cohorts, '
    '${simulation.world.stores.length} stores, ${policies.length} AIs',
  );
  for (final MapEntry(:key, :value)
      in _clocks.entries.toList()..sort(
        (a, b) => b.value.elapsedMicroseconds - a.value.elapsedMicroseconds,
      )) {
    stdout.writeln(
      '  ${key.padRight(28)}${(value.elapsedMicroseconds / days / 1000).toStringAsFixed(3).padLeft(8)} ms a day',
    );
  }
  stdout
    ..writeln(
      '  ${'other (observe, apply, …)'.padRight(28)}'
      '${((total.elapsedMicroseconds - measured) / days / 1000).toStringAsFixed(3).padLeft(8)} ms a day',
    )
    ..writeln(
      '  one observation              '
      '${(observe.elapsedMicroseconds / 200 / policies.length / 1000).toStringAsFixed(3)} ms',
    );
}
