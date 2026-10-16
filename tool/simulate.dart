import 'dart:convert';
import 'dart:io';

import '../lib/domain/economy.dart';
import '../lib/simulation/simulation.dart';

/// Runs with the Dart CLI alone: dart tool/simulate.dart --days 10000 --seed 42.
void main(List<String> args) {
  var days = 30;
  var seed = 42;
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length || !['--days', '--seed'].contains(args[i])) {
      stderr.writeln('Usage: dart tool/simulate.dart [--days N] [--seed N]');
      exitCode = 64;
      return;
    }
    final value = int.tryParse(args[i + 1]);
    if (value == null || value < 0) {
      stderr.writeln('Days and seed must be nonnegative integers.');
      exitCode = 64;
      return;
    }
    if (args[i] == '--days') {
      days = value;
    }
    if (args[i] == '--seed') {
      seed = value;
    }
  }
  final simulation = Simulation.neighborhood(seed: seed);
  final profits = {for (final s in simulation.stores) s.id: 0};
  final revenues = {for (final s in simulation.stores) s.id: 0};
  for (var i = 0; i < days; i++) {
    final report = simulation.advanceDay(); // Audits every day's invariants.
    for (final s in simulation.stores) {
      profits[s.id] = profits[s.id]! + report.businesses[s.id]!.profit;
      revenues[s.id] = revenues[s.id]! + report.businesses[s.id]!.revenue;
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'days': simulation.day, 'seed': seed,
    'households': consumerSegments.fold<int>(0, (n, s) => n + s.households),
    'cashConserved': simulation.ledger.totalCash == simulation.ledger.conservedCash,
    'retailRevenueCents': revenues, 'retailProfitCents': profits,
    'stores': {for (final s in simulation.stores) s.id: {
      'cashCents': simulation.ledger.balance(s.id), 'isOpen': s.isOpen,
      'inventoryValueCents': inventoryValue(s.inventory),
    }},
    'lastDayMarketShares': simulation.lastReport?.marketShares,
    'randomState': simulation.random.state,
    'journalEntriesRetained': simulation.ledger.entries.length,
  }));
}
