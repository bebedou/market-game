// Fits the numbers the countries run by formula borrow from the full simulation,
// and writes them to content/countries/calibration.json:
//
// - capture: what shops turn into sales of what households want, per trade;
// - staffFixed: the share of staff costs that goes with being open;
// - priceResponse: how far a shop's sales move with its prices, from controlled
//   runs: the same worlds with a shop in every city pinned at normal prices,
//   10% under and 10% over, so that nothing else differs but what follows. A
//   shop alone in its trade gets a rival next door first: without one, nobody
//   can go elsewhere and its prices tell nothing about competing.
//
//   dart run tool/calibrate_countries.dart [--seeds 4] [--write]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:engine/countries.dart';
import 'package:engine/engine.dart';

const trades = ['grocery', 'restaurants', 'electronics'];

/// One trade's figures over the fitted years of one run.
final class TradeFigures {
  double sales = 0;
  double wants = 0;
  double wages = 0;

  /// Store-months at wages, and sales at wages: what staff costs follow.
  double open = 0;
  double served = 0;

  /// The least-squares sums over each company's months, of wages on those two.
  double aa = 0, ab = 0, bb = 0, ay = 0, by = 0;

  void addMonth(double wage, double a, double b) {
    wages += wage;
    open += a;
    served += b;
    aa += a * a;
    ab += a * b;
    bb += b * b;
    ay += a * wage;
    by += b * wage;
  }

  void add(TradeFigures other) {
    sales += other.sales;
    wants += other.wants;
    wages += other.wages;
    open += other.open;
    served += other.served;
    aa += other.aa;
    ab += other.ab;
    bb += other.bb;
    ay += other.ay;
    by += other.by;
  }
}

String tradeOf(ContentDb content, FormatId format) =>
    formatTrades[content.formats[format.index].key]!;

Map<String, TradeFigures> runFit(String json, int seed) {
  final content = loadScenario(json);
  final balanced = content.strategies.firstWhere((s) => s.key == 'balanced');
  final simulation = Simulation.newGame(
    content,
    seed: seed,
    policies: {
      ...standardPolicies(content),
      content.player: ownerPolicy(balanced),
    },
  );
  final figures = {for (final trade in trades) trade: TradeFigures()};
  final startYear = content.startDay.date.year;
  var priceSum = 0.0;
  var demandSum = 0.0;
  // The formats trading in each market this year.
  final trading = <int, Set<String>>{};
  while (simulation.world.today.date.year < startYear + 5 ||
      !simulation.world.today.isFirstOfMonth ||
      simulation.world.today.date.month != 1) {
    simulation.step();
    final world = simulation.world;
    if (!world.today.isFirstOfMonth) continue;
    final macro = world.macro;
    final date = world.today.date;
    // The month just ended, in whole years since the start.
    final year = date.month == 1
        ? date.year - startYear - 1
        : date.year - startYear;
    final prices = macro.priceIndex.raw / Fx.scale;
    final wages = macro.wageIndex.raw / Fx.scale;
    priceSum += prices;
    demandSum +=
        content.macro.regimes[macro.regime.index].demand.raw / Fx.scale;
    if (year >= 1) {
      for (final (i, _) in world.companies.indexed) {
        final reports = simulation.reports(CompanyId(i), ReportPeriod.month);
        if (reports.length < 2) continue;
        final report = reports[reports.length - 2];
        final stores = [
          for (final store in report.stores)
            if (store.totalRevenue.cents > 0) store,
        ];
        if (stores.isEmpty) continue;
        final first = world.stores[stores.first.store.index];
        final market = content.markets[first.market.index];
        final level = market.priceLevel.raw / Fx.scale;
        final wageLevel = market.wageLevel.raw / Fx.scale;
        final sold = stores.fold(0, (sum, s) => sum + s.totalRevenue.cents);
        final trade = figures[tradeOf(content, first.format)]!;
        trade.addMonth(
          report.flow(AccountKind.wages).cents.toDouble(),
          stores.length * wageLevel * wages,
          sold / level * wageLevel * wages / prices,
        );
        for (final store in stores) {
          final state = world.stores[store.store.index];
          final name = tradeOf(content, state.format);
          figures[name]!.sales += store.totalRevenue.cents;
          (trading[state.market.index] ??= {}).add(
            content.formats[state.format.index].key,
          );
        }
      }
    }
    if (date.month == 1) {
      for (final market in content.markets) {
        final formats = trading[market.id.index];
        if (year < 1 || formats == null) continue;
        for (final trade in trades) {
          final here = {
            for (final format in formats)
              if (formatTrades[format] == trade) format,
          };
          if (here.isEmpty) continue;
          figures[trade]!.wants += shopMarketWants(
            content,
            market,
            formats: here,
            year: year,
            priceIndex: Fx.raw((priceSum / 12 * Fx.scale).round()),
            demand: Fx.raw((demandSum / 12 * Fx.scale).round()),
          ).cents;
        }
      }
      trading.clear();
      priceSum = 0;
      demandSum = 0;
    }
  }
  return figures;
}

/// Keeps one store's prices at the normal level times [factor], and leaves the
/// rest of what its owner does alone.
final class PinnedPrices implements Policy {
  PinnedPrices(this.inner, this.store, this.factor);

  final Policy inner;
  final StoreId store;
  final Fx factor;

  @override
  List<Command> decide(Observation view, ContentDb content) {
    final commands = [
      for (final command in inner.decide(view, content))
        if (command is! SetPrice || command.store != store) command,
    ];
    for (final company in view.companies) {
      for (final mine in company.stores) {
        if (mine.id != store) continue;
        final site = content.sites[mine.site.index];
        final level =
            view.macro.priceIndex *
            content.markets[site.market.index].priceLevel *
            factor;
        for (final (p, price) in mine.prices.indexed) {
          if (price == null) continue;
          final target = content.products[p].referencePrice.times(level);
          if (price != target) {
            commands.add(
              SetPrice(
                view.actor,
                store: store,
                product: ProductId(p),
                price: target,
              ),
            );
          }
        }
      }
    }
    return commands;
  }
}

/// [json] with a copy of every shop alone in its format in its city, under an
/// owner of its own on a vacant site there.
String withRivals(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final sites = (root['sites'] as List).cast<Map<String, dynamic>>();
  final stores = (root['stores'] as List).cast<Map<String, dynamic>>();
  final companies = (root['companies'] as List).cast<Map<String, dynamic>>();
  final persons = (root['persons'] as List).cast<Map<String, dynamic>>();
  final marketOf = {for (final site in sites) site['id']: site['market']};
  final taken = {for (final store in stores) store['site']};
  final counts = <(Object?, Object?), int>{};
  for (final store in stores) {
    final key = (marketOf[store['site']], store['format'] ?? 'grocery');
    counts[key] = (counts[key] ?? 0) + 1;
  }
  for (final store in List.of(stores)) {
    final market = marketOf[store['site']];
    if (counts[(market, store['format'] ?? 'grocery')] != 1) continue;
    final company = companies.firstWhere((c) => c['id'] == store['company']);
    final owner = persons.firstWhere((p) => p['id'] == company['owner']);
    if (owner['player'] == true) continue;
    final vacant = sites.where(
      (site) =>
          site['market'] == market &&
          !taken.contains(site['id']) &&
          (site['shelfSlots'] as int) >= (store['prices'] as Map).length,
    );
    if (vacant.isEmpty) continue;
    final site = vacant.first['id'];
    taken.add(site);
    persons.add({...owner, 'id': '${owner['id']}_rival'});
    companies.add({
      ...company,
      'id': '${company['id']}_rival',
      'owner': '${owner['id']}_rival',
    });
    stores.add({
      ...store,
      'id': '${store['id']}_rival',
      'company': '${company['id']}_rival',
      'site': site,
    });
  }
  return jsonEncode(root);
}

/// One shop per trade and city that isn't the player's, and the year's sales
/// of each after a first year to settle.
Map<String, double> runPinned(String json, int seed, int factorRaw) {
  final content = loadScenario(withRivals(json));
  final factor = Fx.raw(factorRaw);
  final policies = Map.of(standardPolicies(content));
  final treated = <StoreId, String>{};
  final seen = <(int, String)>{};
  for (final (i, def) in content.stores.indexed) {
    final owner = content.companies[def.company.index].owner;
    if (owner == content.player) continue;
    final site = content.sites[def.site.index];
    final trade = tradeOf(content, def.format);
    if (!seen.add((site.market.index, trade))) continue;
    final inner = policies[owner];
    if (inner == null) continue;
    policies[owner] = PinnedPrices(inner, StoreId(i), factor);
    treated[StoreId(i)] = trade;
  }
  final simulation = Simulation.newGame(
    content,
    seed: seed,
    policies: policies,
  );
  final sales = {for (final trade in trades) trade: 0.0};
  for (var day = 1; day <= 2 * 365; day++) {
    simulation.step();
    final world = simulation.world;
    if (day <= 365 || !world.today.isFirstOfMonth) continue;
    for (final store in treated.keys) {
      final company = world.stores[store.index].company;
      final reports = simulation.reports(company, ReportPeriod.month);
      if (reports.length < 2) continue;
      for (final report in reports[reports.length - 2].stores) {
        if (report.store == store) {
          sales[treated[store]!] =
              sales[treated[store]!]! + report.totalRevenue.cents;
        }
      }
    }
  }
  return sales;
}

/// Two amounts' least-squares fit of [y] on [a] and [b], as `(ka, kb)`.
(double, double) fit2(double aa, double ab, double bb, double ay, double by) {
  final det = aa * bb - ab * ab;
  return ((ay * bb - by * ab) / det, (aa * by - ab * ay) / det);
}

Future<void> main(List<String> args) async {
  final seeds = args.contains('--seeds')
      ? int.parse(args[args.indexOf('--seeds') + 1])
      : 4;
  final write = args.contains('--write');
  final root = Platform.script.resolve('../../../content/');
  final json = File(
    root.resolve('scenarios/prototype.json').toFilePath(),
  ).readAsStringSync();

  final fits = await Future.wait([
    for (var seed = 1; seed <= seeds; seed++)
      Isolate.run(() => runFit(json, seed)),
  ]);
  final capture = <String, String>{};
  final staffFixed = <String, String>{};
  for (final trade in trades) {
    final all = TradeFigures();
    for (final fit in fits) {
      all.add(fit[trade]!);
    }
    capture[trade] = (all.sales / all.wants).toStringAsFixed(4);
    final (perStore, perSale) = fit2(all.aa, all.ab, all.bb, all.ay, all.by);
    final fixed =
        (perStore * all.open / (perStore * all.open + perSale * all.served))
            .clamp(0.0, 1.0);
    staffFixed[trade] = fixed.toStringAsFixed(4);
    stdout.writeln(
      '$trade: capture ${capture[trade]}, staff fixed ${staffFixed[trade]}, '
      'wages are ${(all.wages / all.sales * 100).toStringAsFixed(1)}% of sales',
    );
  }

  final raws = [Fx.scale, 9000, 11000];
  final jobs = [
    for (var seed = 1; seed <= seeds; seed++)
      for (final raw in raws) (seed, raw),
  ];
  final pinned = await Future.wait([
    for (final (seed, raw) in jobs)
      Isolate.run(() => runPinned(json, seed, raw)),
  ]);
  double salesAt(String trade, int seed, int raw) {
    final index = jobs.indexOf((seed, raw));
    return pinned[index][trade]!;
  }

  final riseResponse = <String, String>{};
  final cutResponse = <String, String>{};
  for (final trade in trades) {
    final cuts = <double>[];
    final rises = <double>[];
    for (var seed = 1; seed <= seeds; seed++) {
      final normal = salesAt(trade, seed, Fx.scale);
      final low = salesAt(trade, seed, 9000);
      final high = salesAt(trade, seed, 11000);
      cuts.add(math.log(low / normal) / -math.log(0.9));
      rises.add(math.log(normal / high) / math.log(1.1));
    }
    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    double spread(List<double> v) => v.reduce(math.max) - v.reduce(math.min);
    riseResponse[trade] = math.max(mean(rises), 0.0).toStringAsFixed(4);
    cutResponse[trade] = math.max(mean(cuts), 0.0).toStringAsFixed(4);
    stdout.writeln(
      '$trade: a 10% rise moves sales '
      '${((math.exp(-mean(rises) * math.log(1.1)) - 1) * 100).toStringAsFixed(1)}%, '
      'a 10% cut ${((math.exp(-mean(cuts) * math.log(0.9)) - 1) * 100).toStringAsFixed(1)}%; '
      'response to rises ${mean(rises).toStringAsFixed(2)} '
      '(seeds span ${spread(rises).toStringAsFixed(2)}), '
      'to cuts ${mean(cuts).toStringAsFixed(2)} '
      '(seeds span ${spread(cuts).toStringAsFixed(2)})',
    );
  }

  if (write) {
    final out = File(root.resolve('countries/calibration.json').toFilePath());
    out.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'capture': capture, 'staffFixed': staffFixed, 'riseResponse': riseResponse, 'cutResponse': cutResponse})}\n',
    );
    stdout.writeln('wrote ${out.path}');
  }
}
