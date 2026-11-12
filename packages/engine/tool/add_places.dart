// Lays out the districts that content/countries/build_places.py wrote to
// places.json: the first of each city as a market played in full, with the
// sites, shops and owners the generator gives it, and the others as rows that
// sleep. Writes what to add to the scenario to places_built.json, for
// insert_places.py to put in prototype.json.
//
//   dart run tool/add_places.dart [--seed 1]
import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/neighbourhoods.dart';

void main(List<String> args) {
  final seed = args.contains('--seed')
      ? int.parse(args[args.indexOf('--seed') + 1])
      : 1;
  final root = Platform.script.resolve('../../../content/');
  final scenarioText = File(
    root.resolve('scenarios/prototype.json').toFilePath(),
  ).readAsStringSync();
  final places =
      jsonDecode(
            File(
              root.resolve('countries/places.json').toFilePath(),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  // The scenario with the countries, their suppliers and every district as
  // a row, for the generator to lay the starting ones out.
  final scenario = jsonDecode(scenarioText) as Map<String, dynamic>;
  final rows = [
    for (final place in places['places'] as List)
      {
        for (final MapEntry(:key, :value)
            in (place as Map<String, dynamic>).entries)
          if (key != 'start') key: value,
      },
  ];
  final starts = [
    for (final place in places['places'] as List)
      if ((place as Map<String, dynamic>)['start'] == true)
        place['id'] as String,
  ];
  final withRows = {
    ...scenario,
    'countries': places['countries'],
    'suppliers': [
      ...scenario['suppliers'] as List,
      ...places['suppliers'] as List,
    ],
    'neighbourhoods': [...scenario['neighbourhoods'] as List, ...rows],
  };
  final content = loadScenario(jsonEncode(withRows));
  final firstNew = (scenario['neighbourhoods'] as List).length;
  final woken = <WokenNeighbourhood>[
    for (var i = firstNew; i < content.neighbourhoods.length; i++)
      if (starts.contains(content.neighbourhoods[i].key))
        () {
          final sleeper = newSleeper(content, i, seed: seed);
          return (
            row: i,
            day: content.startDay,
            priceIndex: Fx.one,
            households: sleeper.households,
            shops: sleeper.shops,
          );
        }(),
  ];
  final built =
      jsonDecode(withNeighbourhoods(content, woken, seed: seed).source)
          as Map<String, dynamic>;
  List<dynamic> added(String list) =>
      (built[list] as List).skip((scenario[list] as List).length).toList();

  // A starting city's market as the scenario writes one: its market in euros
  // and mix, not the households they come to.
  final markets = [
    for (final market in added('markets'))
      () {
        final place = rows.firstWhere((row) => row['id'] == market['id']);
        return {
          'id': place['id'],
          'name': place['name'],
          'country': place['country'],
          'market': place['market'],
          'mix': place['mix'],
          'growth': place['growth'],
          'agents': market['agents'],
          'priceLevel': place['priceLevel'],
          'wageLevel': place['wageLevel'],
          'incomeLevel': place['incomeLevel'],
        };
      }(),
  ];
  // Ids of their own, as the generator gives `<place>_<site>_owner` and the
  // like to the shops it lays out when the city sleeps and is planned again.
  String renamed(String id) => id.replaceFirstMapped(
    RegExp(r'_(\d+)_(store|co|owner)$'),
    (match) =>
        '_${const {'store': 'shop', 'co': 'company', 'owner': 'owner'}[match[2]]}_${match[1]}',
  );
  final stores = [
    for (final store in added('stores'))
      {
        ...store as Map<String, dynamic>,
        'id': renamed(store['id'] as String),
        'company': renamed(store['company'] as String),
      },
  ];
  final companies = [
    for (final company in added('companies'))
      {
        ...company as Map<String, dynamic>,
        'id': renamed(company['id'] as String),
        'owner': renamed(company['owner'] as String),
      },
  ];
  // Most owners are shopkeepers who keep the shop they have; each city's
  // balanced grocer is a chain that may grow, as in the French cities.
  final persons = [
    for (final person in added('persons'))
      {
        ...person as Map<String, dynamic>,
        'id': renamed(person['id'] as String),
        if (person['strategy'] != 'balanced') 'local': true,
      },
  ];
  final sleeping = [
    for (final row in rows)
      if (!starts.contains(row['id'])) row,
  ];
  final out = {
    'countries': places['countries'],
    'suppliers': places['suppliers'],
    'markets': markets,
    'sites': added('sites'),
    'stores': stores,
    'companies': companies,
    'persons': persons,
    'neighbourhoods': sleeping,
  };
  File(
    root.resolve('countries/places_built.json').toFilePath(),
  ).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(out)}\n');
  for (final market in markets) {
    final here = [
      for (final site in added('sites'))
        if (site['market'] == market['id']) site['id'],
    ];
    final shops = [
      for (final store in stores)
        if (here.contains(store['site']))
          '${store['name']} (${store['format']})',
    ];
    stdout.writeln(
      '${market['name']}: ${here.length} sites, ${shops.join(', ')}',
    );
  }
}
