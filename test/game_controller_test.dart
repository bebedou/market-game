import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/application/game_controller.dart';
import 'package:market_game/simulation/simulation.dart';

void main() {
  test('A new or restored game starts paused without fabricating history', () {
    final game = GameController();
    expect(game.isPlaying, isFalse);
    expect(game.simulation.day, 0);
    expect(game.reports, isEmpty);
    expect(game.stockCoverage('water'), isNull);
    game.nextDay();
    final restored = GameController(
      simulation: Simulation.fromJson(
        jsonDecode(jsonEncode(game.simulation.toJson()))
            as Map<String, dynamic>,
      ),
    );
    expect(restored.isPlaying, isFalse);
    expect(restored.simulation.day, 1);
    expect(restored.reports.single.day, 1);
    game.dispose();
    restored.dispose();
  });

  for (final speed in [1, 3, 10]) {
    test(
      '$speed× completes exactly one day at its interval with one timer',
      () {
        fakeAsync((time) {
          final game = GameController(now: () => time.elapsed);
          game.setSpeed(speed);
          game.play();
          game.play();
          expect(time.nonPeriodicTimerCount, 1);
          time.elapse(game.dayDuration - const Duration(microseconds: 1));
          expect(game.simulation.day, 0);
          time.elapse(const Duration(microseconds: 1));
          expect(game.simulation.day, 1);
          expect(time.nonPeriodicTimerCount, 1);
          game.dispose();
          expect(time.nonPeriodicTimerCount, 0);
        });
      },
    );
  }

  test('Pause preserves partial progress and never catches up time away', () {
    fakeAsync((time) {
      final game = GameController(now: () => time.elapsed);
      game.play();
      time.elapse(const Duration(seconds: 6));
      game.pause();
      expect(game.dayProgress, closeTo(0.4, 0.000001));
      expect(time.nonPeriodicTimerCount, 0);
      time.elapse(const Duration(hours: 12));
      expect(game.simulation.day, 0);
      game.play();
      time.elapse(const Duration(milliseconds: 8999));
      expect(game.simulation.day, 0);
      time.elapse(const Duration(milliseconds: 1));
      expect(game.simulation.day, 1);
      game.dispose();
    });
  });

  test(
    'Changing speed preserves the elapsed fraction and replaces the timer',
    () {
      fakeAsync((time) {
        final game = GameController(now: () => time.elapsed);
        game.play();
        time.elapse(const Duration(seconds: 6));
        game.setSpeed(3);
        expect(game.dayProgress, closeTo(0.4, 0.000001));
        expect(time.nonPeriodicTimerCount, 1);
        time.elapse(const Duration(milliseconds: 2999));
        expect(game.simulation.day, 0);
        time.elapse(const Duration(milliseconds: 1));
        expect(game.simulation.day, 1);
        game.pause();
        game.setSpeed(10);
        expect(game.isPlaying, isFalse);
        expect(time.nonPeriodicTimerCount, 0);
        game.dispose();
      });
    },
  );

  test('Backgrounding pauses; returning requires explicit play', () {
    fakeAsync((time) {
      final game = GameController(now: () => time.elapsed);
      game.play();
      time.elapse(const Duration(seconds: 6));
      game.setForeground(false);
      game.play();
      game.nextDay();
      time.elapse(const Duration(hours: 1));
      expect(game.simulation.day, 0);
      expect(game.isPlaying, isFalse);
      game.setForeground(true);
      time.elapse(const Duration(seconds: 20));
      expect(game.simulation.day, 0);
      game.play();
      time.elapse(const Duration(seconds: 9));
      expect(game.simulation.day, 1);
      game.dispose();
    });
  });

  test('Manual steps work only while paused and reset the partial day', () {
    fakeAsync((time) {
      final game = GameController(now: () => time.elapsed);
      game.play();
      game.nextDay();
      expect(game.simulation.day, 0);
      time.elapse(const Duration(seconds: 6));
      game.pause();
      game.nextDay();
      expect(game.simulation.day, 1);
      expect(game.dayProgress, 0);
      game.play();
      time.elapse(const Duration(seconds: 14));
      expect(game.simulation.day, 1);
      time.elapse(const Duration(seconds: 1));
      expect(game.simulation.day, 2);
      game.dispose();
    });
  });

  test('Timed and manual ticks have exactly the same economic future', () {
    fakeAsync((time) {
      final game = GameController(now: () => time.elapsed);
      final reference = Simulation.neighborhood();
      game.setSpeed(3);
      game.play();
      time.elapse(const Duration(seconds: 15));
      for (var i = 0; i < 3; i++) {
        reference.advanceDay();
      }
      expect(
        jsonEncode(game.simulation.toJson()),
        jsonEncode(reference.toJson()),
      );
      game.dispose();
    });
  });

  test(
    'History and activity remain bounded and derive from settled reports',
    () {
      final game = GameController();
      for (var i = 0; i < 100; i++) {
        game.nextDay();
      }
      expect(game.reports.length, 30);
      expect(game.reports.first.day, 71);
      expect(game.reports.last.day, 100);
      expect(game.activity.length, lessThanOrEqualTo(80));
      expect(game.activity.first.day, 100);
      final recent = game.reports.skip(23);
      final waterSold = recent.fold<int>(
        0,
        (n, r) => n + r.businesses['player']!.unitsSold['water']!,
      );
      expect(
        game.stockCoverage('water'),
        closeTo(
          game.simulation.player.inventory['water']!.quantity / (waterSold / 7),
          0.000001,
        ),
      );
      game.dispose();
    },
  );

  test('Repeated stockout warnings are throttled to every third day', () {
    final sim = Simulation.neighborhood();
    sim.player.autoRestock = false;
    for (final stock in sim.player.inventory.values) {
      stock.remove(stock.quantity);
    }
    final game = GameController(simulation: sim);
    for (var i = 0; i < 7; i++) {
      game.nextDay();
    }
    expect(
      game.activity
          .where((a) => a.warning && a.message.startsWith('Corner & Co.'))
          .map((a) => a.day)
          .toList(),
      [7, 4, 1],
    );
    expect(game.stockCoverage('water'), isNull);
    game.dispose();
  });

  test('A tick failure pauses without a retry loop', () {
    fakeAsync((time) {
      final sim = Simulation.neighborhood();
      sim.player.prices['water'] = 0;
      final game = GameController(simulation: sim, now: () => time.elapsed);
      game.play();
      time.elapse(const Duration(seconds: 15));
      expect(game.error, isNotNull);
      expect(game.isPlaying, isFalse);
      expect(time.nonPeriodicTimerCount, 0);
      game.play();
      time.elapse(const Duration(hours: 1));
      expect(sim.day, 0);
      game.dispose();
    });
  });

  test(
    'Invalid speeds do not change state; disposal prevents future ticks',
    () {
      fakeAsync((time) {
        final game = GameController(now: () => time.elapsed);
        expect(() => game.setSpeed(2), throwsArgumentError);
        expect(game.speed, 1);
        game.play();
        game.dispose();
        game.play();
        game.nextDay();
        time.elapse(const Duration(hours: 1));
        expect(game.simulation.day, 0);
        expect(time.nonPeriodicTimerCount, 0);
      });
    },
  );
}
