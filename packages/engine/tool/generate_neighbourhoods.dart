// Generates today's cities from their figures alone, writes the scenario, and
// prints what came out next to the hand-made cities. Play the result with
// tool/sim.dart --scenario to compare the two.
//
//   dart run tool/generate_neighbourhoods.dart --seed 1 --out generated.json
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/neighbourhoods.dart';

String summary(ContentDb content, MarketDef market) {
  final here = [
    for (final store in content.stores)
      if (content.sites[store.site.index].market == market.id) store,
  ];
  final counts = <String, int>{};
  for (final store in here) {
    final key = content.formats[store.format.index].key;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final sites = content.sites.where((site) => site.market == market.id).length;
  final shops = [
    for (final format in content.formats)
      if (counts[format.key] case final count?) '${format.key} $count',
  ].join(', ');
  return '$sites sites: $shops';
}

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seed = int.parse(option('--seed', '1'));
  final json = File(
    Platform.script
        .resolve('../../../content/scenarios/prototype.json')
        .toFilePath(),
  ).readAsStringSync();
  final content = loadScenario(json);
  final generated = generateScenario(
    json,
    rowsFromScenario(content),
    seed: seed,
  );
  final made = loadScenario(generated);
  for (final market in content.markets) {
    stdout
      ..writeln(market.name)
      ..writeln('  by hand    ${summary(content, market)}')
      ..writeln('  generated  ${summary(made, made.markets[market.id.index])}');
  }
  final out = option('--out', '');
  if (out.isNotEmpty) File(out).writeAsStringSync(generated);
}
