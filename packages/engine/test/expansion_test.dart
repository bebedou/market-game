import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<TickResult> advance(Simulation simulation, int days) => [
  for (var i = 0; i < days; i++) simulation.step(),
];

void main() {
  test('bigger stores draw more shoppers, and say so', () {
    // The same two stores and prices, with shoppers who like size.
    final likesSize = testScenarioJson
        .replaceFirst('"sizeWeight": "0"', '"sizeWeight": "3"')
        .replaceAll('"location": "0.60"', '"location": "0.50"');
    final equal = loadScenario(likesSize);
    final bigger = loadScenario(
      likesSize.replaceFirst(
        '"area": 100, "maxArea": 140 },\n    { "id": "lane"',
        '"area": 400, "maxArea": 400 },\n    { "id": "lane"',
      ),
    );
    expect(bigger.sites[square.index].area, 400);
    (int, int) trips(ContentDb content) {
      final simulation = Simulation.newGame(content, seed: 4);
      var player = 0;
      var rival = 0;
      for (final day in advance(simulation, 20)) {
        player += day.attribution.visits[playerStore.index];
        rival += day.attribution.visits[rivalStore.index];
      }
      return (player, rival);
    }

    final (playerEqual, rivalEqual) = trips(equal);
    final (playerSmaller, rivalBigger) = trips(bigger);
    expect(rivalBigger * playerEqual, greaterThan(rivalEqual * playerSmaller));

    // With stocked shelves, households form habits, and leave them.
    final simulation = Simulation.newGame(bigger, seed: 4);
    final days = [
      for (var i = 0; i < 40; i++)
        (simulation..submitAll(scriptedCommands(simulation.today))).step(),
    ];
    final causes = {
      for (final day in days)
        for (final MapEntry(:key) in day.attribution.switches.entries)
          if (key.to == rivalStore) key.cause,
    };
    expect(causes, contains(SwitchCause.size));
  });
}

extension on Simulation {
  void submitAll(List<Command> commands) => commands.forEach(submit);
}
