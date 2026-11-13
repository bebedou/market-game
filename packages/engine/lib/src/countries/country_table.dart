import 'dart:convert';

import '../content/scenario_loader.dart' show ContentException;
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';

/// One phase of the shared business cycle.
final class CycleRegime {
  const CycleRegime({
    required this.key,
    required this.name,
    required this.meanMonths,
    required this.inflation,
    required this.realWageGrowth,
    required this.demand,
  });

  final String key;
  final String name;
  final int meanMonths;

  /// Yearly rates.
  final Fx inflation;
  final Fx realWageGrowth;

  /// What households buy against a normal year, at the size of the shop-level
  /// game's cycle; see [CountryTable.amplitude].
  final Fx demand;
}

/// A slice of households by income.
final class IncomeClass {
  const IncomeClass({
    required this.key,
    required this.name,
    required this.priceFactor,
  });

  final String key;
  final String name;

  /// How price-sensitive the class is against the average household.
  final Fx priceFactor;
}

/// A line of business that households spend on.
final class Trade {
  const Trade({
    required this.key,
    required this.name,
    required this.description,
    required this.cycle,
    required this.incomeElasticity,
    required this.riseResponse,
    required this.cutResponse,
    required this.staffFixed,
  });

  final String key;
  final String name;
  final String description;

  /// How far its sales move when household consumption moves by one.
  final Fx cycle;

  /// How far spending per household moves when real income moves by one.
  final Fx incomeElasticity;

  /// How far a chain's sales fall per unit of price above the trade's average,
  /// and rise per unit below it, from the controlled runs of the full
  /// simulation. Shoppers punish a rise far more than they reward a cut.
  final Fx riseResponse;
  final Fx cutResponse;

  /// The share of staff costs that goes with having the store open, whatever
  /// it sells, from the full simulation.
  final Fx staffFixed;
}

/// One income class in one country, as it was in the table's year.
final class ClassRow {
  const ClassRow({
    required this.households,
    required this.income,
    required this.spending,
  });

  final int households;

  /// Net income per household per year.
  final Money income;

  /// Spending per household per year before VAT, indexed by trade.
  final List<Money> spending;
}

/// How a trade's sales were spent in one country, by the sellers' accounts.
final class TradeRow {
  const TradeRow({
    required this.goods,
    required this.staff,
    required this.other,
    required this.stores,
    required this.turnover,
  });

  /// Shares of sales.
  final Fx goods;
  final Fx staff;
  final Fx other;

  /// Shops in the trade, chains and independents.
  final int stores;

  /// What sellers reported selling, kept as a check on what households say
  /// they spent. Nothing in the model reads it.
  final Money turnover;

  /// What a typical business keeps before tax: to it, new shops open or close.
  Fx get normalMargin => Fx.one - goods - staff - other;
}

/// One region of a country: its people, their income, and where it sits on
/// the country's tile map.
final class NationalRegion {
  const NationalRegion({
    required this.key,
    required this.name,
    required this.population,
    required this.income,
    required this.col,
    required this.row,
  });

  final String key;
  final String name;
  final int population;

  /// Households' disposable income per inhabitant a year.
  final Money income;

  /// Its square on the tile map, from the top left.
  final int col;
  final int row;
}

/// How regions differ within a country: how wages and rents follow income,
/// how much thicker a chain's shops are in its home regions, and how crowded
/// a region gets for one chain.
final class RegionalTuning {
  const RegionalTuning({
    required this.wages,
    required this.rents,
    required this.home,
    required this.saturation,
  });

  /// How far a region's wages and rents move, against the country's, when its
  /// income per head is higher by one.
  final Fx wages;
  final Fx rents;

  /// How many times thicker a chain's shops are in its home regions.
  final Fx home;

  /// The share of a trade's shops in a region at which one chain's shops
  /// draw half what each would alone.
  final Fx saturation;

  static const none = RegionalTuning(
    wages: Fx.zero,
    rents: Fx.zero,
    home: Fx.one,
    saturation: Fx.one,
  );
}

/// How marketing across a country builds a company's pull there: what it
/// spends adds to its goodwill, which loses [decay] of itself a month, and
/// goodwill G pulls up to [pull] more shoppers, half that at G = [half] of
/// the trade's yearly market. Spread over more shops, the same share of
/// sales buys a big chain more.
final class BrandTuning {
  const BrandTuning({
    required this.pull,
    required this.half,
    required this.decay,
  });

  final Fx pull;
  final Fx half;
  final Fx decay;

  static const none = BrandTuning(pull: Fx.zero, half: Fx.one, decay: Fx.one);
}

/// A chain as the table starts it, or a trade's independents taken together.
final class ChainDef {
  const ChainDef({
    required this.name,
    required this.trade,
    required this.stores,
    required this.share,
    required this.price,
    required this.independent,
    this.home = const [],
  });

  final String name;
  final int trade;
  final int stores;

  /// Its share of the trade's sales.
  final Fx share;

  /// Its prices against the trade's average.
  final Fx price;
  final bool independent;

  /// The regions where its shops are thicker on the ground, by index into
  /// [NationalCountry.regions].
  final List<int> home;
}

final class NationalCountry {
  NationalCountry({
    required this.key,
    required this.name,
    required this.population,
    required this.cycle,
    required this.householdGrowth,
    required this.realGrowth,
    required this.corporateTax,
    required this.classes,
    required this.trades,
    required this.chains,
    this.regions = const [],
  });

  final String key;
  final String name;
  final int population;

  /// Its regions; none for a country taken whole.
  final List<NationalRegion> regions;

  /// How far household consumption moves when the euro area's moves by one.
  final Fx cycle;

  /// Yearly rates. Real income also moves with the cycle.
  final Fx householdGrowth;
  final Fx realGrowth;
  final Fx corporateTax;

  /// Indexed by [CountryTable.classes].
  final List<ClassRow> classes;

  /// Indexed by [CountryTable.trades].
  final List<TradeRow> trades;
  final List<ChainDef> chains;

  /// Each region's income per head against the country's average, by
  /// [regions].
  late final List<Fx> incomeLevels = () {
    // In whole euros, to stay safe in the products.
    var people = 0;
    var income = 0;
    for (final region in regions) {
      people += region.population;
      income += region.income.cents ~/ 100 * region.population;
    }
    final mean = people == 0 ? 1 : income ~/ people;
    return [
      for (final region in regions)
        Fx.raw(mulDivRound(region.income.cents ~/ 100, Fx.scale, mean)),
    ];
  }();
}

/// Countries described by their statistics: the input to [CountryEconomy].
final class CountryTable {
  CountryTable({
    required this.key,
    required this.asOf,
    required this.startDay,
    required this.amplitude,
    required this.storeResponse,
    required this.fitOut,
    required this.startRegime,
    required this.regimes,
    required this.classes,
    required this.trades,
    required this.countries,
    this.regional = RegionalTuning.none,
    this.brands = BrandTuning.none,
  }) : meanRealWageGrowth = _meanRealWageGrowth(regimes);

  final String key;

  /// The year the statistics describe.
  final int asOf;
  final Day startDay;

  /// How much of the shop-level game's cycle real economies show: its
  /// recessions are far deeper than any in the data.
  final Fx amplitude;

  /// How fast stores open or close, as a yearly share of a chain's stores per
  /// unit of margin above or below normal.
  final Fx storeResponse;

  /// What a new store costs to fit out, as a share of a store's yearly sales.
  final Fx fitOut;
  final int startRegime;
  final List<CycleRegime> regimes;
  final List<IncomeClass> classes;
  final List<Trade> trades;
  final List<NationalCountry> countries;
  final RegionalTuning regional;

  /// How companies' marketing across a country builds their pull.
  final BrandTuning brands;

  /// The cycle's real wage growth over its phases' expected lengths, so that
  /// a country's trend is what it grows through a whole cycle.
  final Fx meanRealWageGrowth;

  static Fx _meanRealWageGrowth(List<CycleRegime> regimes) {
    var months = 0;
    var growth = Fx.zero;
    for (final regime in regimes) {
      months += regime.meanMonths;
      growth += regime.realWageGrowth.timesInt(regime.meanMonths);
    }
    return Fx.raw(growth.raw ~/ months);
  }
}

/// Parses and validates a country table and the numbers fitted to the full
/// simulation, [calibrationJson], which `tool/calibrate_countries.dart` writes.
/// Unknown fields are errors, to catch typos, as in a scenario.
CountryTable loadCountryTable(String tableJson, String calibrationJson) {
  final root = _Reader('', jsonDecode(tableJson));
  final calibration = _Reader('calibration', jsonDecode(calibrationJson));
  final rises = calibration.object('riseResponse');
  final cuts = calibration.object('cutResponse');
  final fixed = calibration.object('staffFixed');
  calibration.object('capture');

  final classes = [
    for (final node in root.objects('classes'))
      IncomeClass(
        key: node.text('id'),
        name: node.text('name'),
        priceFactor: node.fx('priceFactor'),
      ),
  ];
  final trades = [
    for (final node in root.objects('trades'))
      Trade(
        key: node.text('id'),
        name: node.text('name'),
        description: node.text('description'),
        cycle: node.fx('cycle'),
        incomeElasticity: node.fx('incomeElasticity'),
        riseResponse: rises.fx(node.peek('id')),
        cutResponse: cuts.fx(node.peek('id')),
        staffFixed: fixed.fx(node.peek('id')),
      ),
  ];
  final tradeIndex = {for (final (i, t) in trades.indexed) t.key: i};
  final classIndex = {for (final (i, c) in classes.indexed) c.key: i};
  final regimes = [
    for (final node in root.objects('regimes'))
      CycleRegime(
        key: node.text('id'),
        name: node.text('name'),
        meanMonths: node.whole('meanMonths'),
        inflation: node.fx('inflation'),
        realWageGrowth: node.fx('realWageGrowth'),
        demand: node.fx('demand'),
      ),
  ];
  final startRegime = regimes.indexWhere(
    (regime) => regime.key == root.peek('startRegime'),
  );
  if (startRegime < 0) root.fail('startRegime', 'no such regime');

  final countries = <NationalCountry>[];
  for (final node in root.objects('countries')) {
    final rows = List<ClassRow?>.filled(classes.length, null);
    for (final row in node.objects('classes')) {
      final index = classIndex[row.peek('class')];
      if (index == null) row.fail('class', 'no such class');
      final spending = row.object('spending');
      rows[index] = ClassRow(
        households: row.whole('households'),
        income: row.money('income'),
        spending: [for (final t in trades) spending.money(t.key)],
      );
      row
        ..text('class')
        ..finish();
      spending.finish();
    }
    if (rows.contains(null)) node.fail('classes', 'one row per class');
    final tradeRows = node.object('trades');
    final regions = [
      for (final region in node.objects('regions', optional: true))
        _region(region),
    ];
    final regionIndex = {for (final (i, r) in regions.indexed) r.key: i};
    final chains = <ChainDef>[];
    final shares = List.filled(trades.length, Fx.zero);
    for (final chain in node.objects('chains')) {
      final trade = tradeIndex[chain.peek('trade')];
      if (trade == null) chain.fail('trade', 'no such trade');
      final share = chain.fx('share');
      shares[trade] += share;
      chains.add(
        ChainDef(
          name: chain.text('name'),
          trade: trade,
          stores: chain.whole('stores'),
          share: share,
          price: chain.fx('price'),
          independent: chain.flag('independent'),
          home: [
            for (final key in chain.strings('home', optional: true))
              regionIndex[key] ?? chain.fail('home', 'no such region $key'),
          ],
        ),
      );
      chain
        ..text('trade')
        ..finish();
    }
    for (final (i, total) in shares.indexed) {
      if (total != Fx.one) {
        node.fail('chains', '${trades[i].key} shares add up to $total');
      }
    }
    countries.add(
      NationalCountry(
        key: node.text('id'),
        name: node.text('name'),
        population: node.whole('population'),
        cycle: node.fx('cycle'),
        householdGrowth: node.fx('householdGrowth'),
        realGrowth: node.fx('realGrowth'),
        corporateTax: node.fx('corporateTax'),
        classes: rows.cast<ClassRow>(),
        trades: [
          for (final trade in trades) _tradeRow(tradeRows.object(trade.key)),
        ],
        chains: chains,
        regions: regions,
      ),
    );
    tradeRows.finish();
    node.finish();
  }
  final table = CountryTable(
    key: root.text('id'),
    asOf: root.whole('asOf'),
    startDay: _day(root, 'startDate'),
    amplitude: root.fx('amplitude'),
    storeResponse: root.fx('storeResponse'),
    fitOut: root.fx('fitOut'),
    startRegime: startRegime,
    regimes: regimes,
    classes: classes,
    trades: trades,
    countries: countries,
    regional: switch (root.optionalObject('regional')) {
      final node? => () {
        final tuning = RegionalTuning(
          wages: node.fx('wages'),
          rents: node.fx('rents'),
          home: node.fx('home'),
          saturation: node.fx('saturation'),
        );
        node.finish();
        return tuning;
      }(),
      null => RegionalTuning.none,
    },
    brands: switch (root.optionalObject('brands')) {
      final node? => () {
        final tuning = BrandTuning(
          pull: node.fx('pull'),
          half: node.fx('half'),
          decay: node.fx('decay'),
        );
        node.finish();
        return tuning;
      }(),
      null => BrandTuning.none,
    },
  );
  root
    ..text('startRegime')
    ..strings('sources')
    ..finish();
  return table;
}

NationalRegion _region(_Reader node) {
  final tile = node.wholes('tile');
  if (tile.length != 2) node.fail('tile', 'expected a column and a row');
  final region = NationalRegion(
    key: node.text('id'),
    name: node.text('name'),
    population: node.whole('population'),
    income: node.money('income'),
    col: tile[0],
    row: tile[1],
  );
  node.finish();
  return region;
}

TradeRow _tradeRow(_Reader node) {
  final row = TradeRow(
    goods: node.fx('goods'),
    staff: node.fx('staff'),
    other: node.fx('other'),
    stores: node.whole('stores'),
    turnover: node.money('turnover'),
  );
  node.finish();
  return row;
}

Day _day(_Reader node, String key) {
  try {
    return Day.parse(node.text(key));
  } on FormatException catch (e) {
    node.fail(key, e.message);
  }
}

/// One JSON object, read field by field. It remembers what was read, so that
/// [finish] can reject what wasn't.
final class _Reader {
  _Reader(this.path, Object? value)
    : _map = switch (value) {
        final Map<String, Object?> map => map,
        _ => throw ContentException(path, 'expected an object'),
      };

  final String path;
  final Map<String, Object?> _map;
  final List<String> _read = [];

  Never fail(String key, String message) =>
      throw ContentException(path.isEmpty ? key : '$path.$key', message);

  Object? _value(String key) {
    _read.add(key);
    return _map[key];
  }

  /// A string field, not yet counted as read.
  String peek(String key) => switch (_map[key]) {
    final String text => text,
    _ => fail(key, 'expected a string'),
  };

  String text(String key) {
    _read.add(key);
    return peek(key);
  }

  int whole(String key) => switch (_value(key)) {
    final int value when value >= 0 => value,
    _ => fail(key, 'expected a whole number'),
  };

  bool flag(String key) => switch (_value(key)) {
    null => false,
    final bool value => value,
    _ => fail(key, 'expected true or false'),
  };

  Fx fx(String key) {
    try {
      return Fx.parse(text(key));
    } on FormatException catch (e) {
      fail(key, e.message);
    }
  }

  Money money(String key) {
    try {
      return Money.parse(text(key));
    } on FormatException catch (e) {
      fail(key, e.message);
    }
  }

  List<String> strings(String key, {bool optional = false}) =>
      switch (_value(key)) {
        final List<Object?> list => list.cast<String>(),
        null when optional => const [],
        _ => fail(key, 'expected a list'),
      };

  List<int> wholes(String key) => switch (_value(key)) {
    final List<Object?> list => [
      for (final item in list)
        item is int && item >= 0 ? item : fail(key, 'expected whole numbers'),
    ],
    _ => fail(key, 'expected a list'),
  };

  _Reader object(String key) => _Reader('$path.$key', _value(key));

  _Reader? optionalObject(String key) =>
      _map.containsKey(key) ? object(key) : null;

  List<_Reader> objects(String key, {bool optional = false}) =>
      switch (_value(key)) {
        final List<Object?> list => [
          for (final (i, item) in list.indexed) _Reader('$path.$key[$i]', item),
        ],
        null when optional => const [],
        _ => fail(key, 'expected a list'),
      };

  /// Fails on any field that wasn't read.
  void finish() {
    for (final key in _map.keys) {
      if (!_read.contains(key)) fail(key, 'unknown field');
    }
  }
}
