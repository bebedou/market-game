// This entry point deliberately runs without Flutter package configuration.
// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:convert';

import '../lib/simulation/simulation.dart';

/// CI compares this exact snapshot from the Dart VM and JavaScript runtimes.
void main() {
  final simulation = Simulation.neighborhood(seed: 42, automateAllStores: true);
  for (var day = 0; day < 365; day++) {
    simulation.advanceDay();
  }
  print(jsonEncode(simulation.toJson()));
}
