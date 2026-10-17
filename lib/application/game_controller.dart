import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/economy.dart';
import '../simulation/simulation.dart';

class ActivityEntry {
  const ActivityEntry({
    required this.day,
    required this.message,
    this.warning = false,
    this.revenue,
    this.profit,
  });

  final int day;
  final String message;
  final bool warning;
  final int? revenue;
  final int? profit;
}

/// Owns presentation state and one timer; the economic engine has no clock.
class GameController extends ChangeNotifier {
  GameController({Simulation? simulation, Duration Function()? now})
    : _simulation =
          simulation ?? Simulation.neighborhood(automateAllStores: true),
      _now = now ?? _monotonicClock() {
    final existing = _simulation.lastReport;
    if (existing != null) {
      _reports.add(existing);
    }
  }

  final Simulation _simulation;
  final Duration Function() _now;
  final List<DailyReport> _reports = [];
  final List<ActivityEntry> _activity = [];
  final Map<String, int> _lastWarningDay = {};
  Timer? _timer;
  Duration? _startedAt;
  double _fraction = 0;
  int _speed = 1;
  bool _playing = false;
  bool _foreground = true;
  bool _disposed = false;
  String? _error;

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  Simulation get simulation => _simulation;
  bool get isPlaying => _playing;
  bool get isForeground => _foreground;
  int get speed => _speed;
  String? get error => _error;
  Duration get dayDuration => Duration(microseconds: 15000000 ~/ _speed);
  List<DailyReport> get reports => List.unmodifiable(_reports);
  List<ActivityEntry> get activity => List.unmodifiable(_activity.reversed);
  BusinessReport? reportFor(String id) =>
      _simulation.lastReport?.businesses[id];
  int get retailCash => _simulation.stores.fold(
    0,
    (n, s) => n + _simulation.ledger.balance(s.id),
  );
  int get retailProfit =>
      _simulation.stores.fold(0, (n, s) => n + (reportFor(s.id)?.profit ?? 0));

  double get dayProgress {
    final start = _startedAt;
    if (!_playing || start == null) {
      return _fraction;
    }
    final elapsed = (_now() - start).inMicroseconds;
    return (_fraction + elapsed / dayDuration.inMicroseconds).clamp(0.0, 1.0);
  }

  void play() {
    if (_disposed || _playing || !_foreground || _error != null) {
      return;
    }
    _playing = true;
    _schedule();
    notifyListeners();
  }

  void pause() {
    if (_disposed || !_playing) {
      return;
    }
    _fraction = dayProgress;
    _playing = false;
    _cancelTimer();
    notifyListeners();
  }

  void setSpeed(int value) {
    if (![1, 3, 10].contains(value)) {
      throw ArgumentError('Unsupported speed.');
    }
    if (_disposed || value == _speed) {
      return;
    }
    _fraction = dayProgress;
    _cancelTimer();
    _speed = value;
    if (_playing) {
      _schedule();
    }
    notifyListeners();
  }

  void setForeground(bool value) {
    if (_disposed || value == _foreground) {
      return;
    }
    if (!value) {
      pause();
    }
    _foreground = value;
    notifyListeners();
  }

  /// A deliberate complete day while paused. Resets any partial day's clock.
  void nextDay() {
    if (_disposed || _playing || !_foreground || _error != null) {
      return;
    }
    _fraction = 0;
    _advance();
    notifyListeners();
  }

  void _schedule() {
    _startedAt = _now();
    final remaining = ((1 - _fraction) * dayDuration.inMicroseconds).round();
    _timer = Timer(Duration(microseconds: remaining), () {
      _timer = null;
      _startedAt = null;
      _fraction = 0;
      if (!_playing || _disposed) {
        return;
      }
      _advance();
      // Schedule from completion: delayed callbacks never simulate time away.
      if (_playing) {
        _schedule();
      }
      notifyListeners();
    });
  }

  void _advance() {
    try {
      final report = _simulation.advanceDay();
      _reports.add(report);
      if (_reports.length > 30) {
        _reports.removeAt(0);
      }
      _activity.add(
        ActivityEntry(
          day: report.day,
          message: 'Neighborhood day completed',
          revenue: report.retailRevenue,
          profit: retailProfit,
        ),
      );
      for (final message in report.notifications) {
        final previous = _lastWarningDay[message];
        if (previous == null || report.day - previous >= 3) {
          _activity.add(
            ActivityEntry(day: report.day, message: message, warning: true),
          );
          _lastWarningDay[message] = report.day;
        }
      }
      if (_activity.length > 80) {
        _activity.removeRange(0, _activity.length - 80);
      }
    } catch (error, stack) {
      _playing = false;
      _cancelTimer();
      _error = 'The day could not be completed. Simulation paused.';
      debugPrint('Simulation tick failed: $error\n$stack');
    }
  }

  /// Coverage uses up to seven completed days of actual sales, not intentions.
  double? stockCoverage(String productId, {String? storeId}) {
    final store = _simulation.stores.singleWhere(
      (s) => s.id == (storeId ?? _simulation.player.id),
    );
    if (_reports.isEmpty) {
      return null;
    }
    final recent = _reports.skip(_reports.length > 7 ? _reports.length - 7 : 0);
    final sold = recent.fold<int>(
      0,
      (n, r) => n + (r.businesses[store.id]?.unitsSold[productId] ?? 0),
    );
    if (sold == 0) {
      return null;
    }
    return store.inventory[productId]!.quantity / (sold / recent.length);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _playing = false;
    _cancelTimer();
    super.dispose();
  }
}
