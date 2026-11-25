// How a player's first shop of each kind fares: a holding start opens one
// at the vacant site that would repay it soonest, as its own company with
// enough capital, hands it to an expert manager with every duty and the
// strategy of its kind, and plays on. Prints, per kind, the shop's profit
// in its months 2, 3, 6, 12 and 24 and what it made in all against its
// fitting out, averaged over the seeds.
//
//   dart run tool/new_shop_balance.dart [--seeds 1-3] [--days 730]
//       [--formats grocery,fastfood,...]
import 'dart:io';

import 'package:engine/engine.dart';

void main(List<String> args) {
  String option(String name, String fallback) =>
      args.contains(name) ? args[args.indexOf(name) + 1] : fallback;
  final seeds = option('--seeds', '1-3').split('-').map(int.parse).toList();
  final days = int.parse(option('--days', '730'));
  final root = Platform.script.resolve('../../../content/');
  final content = loadScenario(
    File(
      option(
        '--scenario',
        root.resolve('scenarios/prototype.json').toFilePath(),
      ),
    ).readAsStringSync(),
  );
  // Each format, and each one's large size by its own key: a supermarket.
  final formats = option(
    '--formats',
    [
      for (final f in content.formats) ...[f.key, ?f.large?.key],
    ].join(','),
  ).split(',');
  final expert = content.managers.grades.last.id;
  String k(num cents) => '${(cents / 100000).toStringAsFixed(1)}k';
  for (final key in formats) {
    final format = content.formats.firstWhere(
      (f) => f.key == key || f.large?.key == key,
    );
    final large = format.key != key;
    final strategies = [
      for (final s in content.strategies)
        if (s.format == format.id) s,
    ];
    // The trade's own strategy, or the balanced one where several share it.
    final strategy =
        strategies.where((s) => s.key == option('--use', '')).firstOrNull ??
        strategies
            .where((s) => s.key == 'balanced' || s.key == key)
            .firstOrNull ??
        (strategies.isEmpty
            ? content.strategies.firstWhere((s) => s.key == 'balanced')
            : strategies.first);
    final checkpoints = [2, 3, 6, 12, 24];
    final profits = {for (final m in checkpoints) m: <int>[]};
    final totals = <int>[];
    final fitOuts = <int>[];
    final sales = <int>[];
    final lastYears = <int>[];
    for (var seed = seeds.first; seed <= seeds.last; seed++) {
      final game = Simulation.newGame(
        content,
        seed: seed,
        start: GameStart.holding('H', cash: Money.parse('500000.00')),
      );
      final player = game.world.player;
      game.step();
      var view = game.observe(player);
      // The vacant site big enough that would repay the shop soonest.
      final owner = EntrepreneurPolicy(strategy);
      SiteDef? best;
      var bestArea = 0;
      var bestPayback = 1 << 30;
      for (final id in view.vacantSites) {
        final site = content.sites[id.index];
        final area = site
            .openingAreas(format)
            .where((area) => format.isLargeAt(area) == large)
            .firstOrNull;
        if (area == null) continue;
        final payback = owner.paybackMonths(view, content, site) ?? 1 << 29;
        if (best == null || payback < bestPayback) {
          best = site;
          bestArea = area;
          bestPayback = payback;
        }
      }
      if (best == null) continue;
      game.submit(
        OpenStore(
          player,
          site: best.id,
          name: '${format.name} ${best.name}',
          format: format.id,
          capital: Money.parse('150000.00'),
          area: bestArea,
        ),
      );
      final opening = game.step();
      if (opening.rejections.isNotEmpty) {
        stderr.writeln('$key: ${opening.rejections.single.reason.key}');
        continue;
      }
      final store = game.world.stores.last;
      game.submit(
        HireManager(
          player,
          store: store.id,
          grade: expert,
          strategy: strategy.id,
          duties: List.filled(ManagerDuty.values.length, true),
        ),
      );
      final company = store.company;
      final opened = game.today;
      final monthly = <int>[];
      var lastMonth = opened.date.month;
      var mark = Money.zero;
      Money result() {
        var profit = Money.zero;
        for (final report in game.reports(company, ReportPeriod.month)) {
          profit += report.profit;
        }
        return profit;
      }

      for (var day = 0; day < days; day++) {
        game.step();
        if (game.today.date.month != lastMonth) {
          lastMonth = game.today.date.month;
          final now = result();
          monthly.add((now - mark).cents);
          mark = now;
        }
      }
      for (final m in checkpoints) {
        if (m - 1 < monthly.length) profits[m]!.add(monthly[m - 1]);
      }
      totals.add(result().cents);
      lastYears.add(
        monthly
            .skip(monthly.length > 12 ? monthly.length - 12 : 0)
            .fold(0, (sum, m) => sum + m),
      );
      fitOuts.add(
        shopOpeningCost(
          content,
          best,
          format,
          view.economyAt(content, best.market).priceIndex,
          area: bestArea,
        ).cents,
      );
      view = game.observe(player);
      final shop = view.companies
          .expand((c) => c.stores)
          .where((s) => s.id == store.id)
          .firstOrNull;
      sales.add(shop?.recentMonths.revenue.cents ?? 0);
      if (args.contains('--detail')) {
        // The player's company's running costs, by kind, its last year.
        final flows = <AccountKind, Money>{};
        final mine = game.reports(company, ReportPeriod.month);
        for (final report in mine.skip(
          mine.length > 12 ? mine.length - 12 : 0,
        )) {
          for (final kind in [
            AccountKind.wages,
            AccountKind.salaries,
            AccountKind.rent,
            AccountKind.overheads,
            AccountKind.marketing,
            AccountKind.writeOffs,
          ]) {
            flows[kind] = (flows[kind] ?? Money.zero) + report.flow(kind);
          }
        }
        print(
          '   YOUR COSTS ${[for (final e in flows.entries) '${e.key.name} ${k(e.value.cents)}'].join('  ')}',
        );
        var sold = 0;
        final missed = <MissReason, int>{};
        for (final report in mine.skip(
          mine.length > 12 ? mine.length - 12 : 0,
        )) {
          final part = report.store(store.id);
          if (part == null) continue;
          for (final product in content.products) {
            sold += part.sold(product.id);
            for (final reason in MissReason.values) {
              missed[reason] =
                  (missed[reason] ?? 0) + part.missed(reason, product.id);
            }
          }
        }
        for (final product in content.products) {
          if (!format.sells[product.category.index]) continue;
          var units = 0;
          var out = 0;
          for (final report in mine.skip(
            mine.length > 12 ? mine.length - 12 : 0,
          )) {
            final part = report.store(store.id);
            if (part == null) continue;
            units += part.sold(product.id);
            out += part.missed(MissReason.outOfStock, product.id);
          }
          print(
            '     ${product.key.padRight(20)} sold $units out $out '
            'stock ${store.stock[product.id.index].units} '
            'price ${store.prices[product.id.index]?.toDecimalString()}',
          );
        }
        print(
          '   YOUR UNITS sold $sold  ${[for (final e in missed.entries) '${e.key.name} ${e.value}'].join('  ')}  staff now ${store.staff}',
        );
        // The player's shop against the others of its kind: their last
        // twelve months, what their goods and running cost, their staff,
        // site and prices.
        for (final other in game.world.stores) {
          if (other.format != format.id || other.status != StoreStatus.open) {
            continue;
          }
          var revenue = Money.zero;
          var goods = Money.zero;
          var running = Money.zero;
          var profit = Money.zero;
          final reports = game.reports(other.company, ReportPeriod.month);
          for (final report in reports.skip(
            reports.length > 12 ? reports.length - 12 : 0,
          )) {
            final part = report.store(other.id);
            if (part == null) continue;
            revenue += part.totalRevenue;
            for (final product in content.products) {
              goods += part.costOfGoods(product.id) + part.spoilage(product.id);
            }
            running += part.runningCosts;
            profit += part.profit;
          }
          var priced = 0;
          var normal = 0;
          for (final product in content.products) {
            if (other.prices[product.id.index] case final price?) {
              priced += price.cents;
              normal += content
                  .references[content
                      .countryOf(other.market)
                      .index][product.id.index]
                  .cents;
            }
          }
          final site = content.sites[other.site.index];
          print(
            '   ${other.company == company ? 'YOU ' : 'ai  '}'
            '${other.name.padRight(26).substring(0, 26)} '
            '${content.markets[other.market.index].key.padRight(14).substring(0, 14)} loc ${site.location} area ${other.area} '
            'staff ${other.staff.fold(0, (a, b) => a + b)} '
            'sales ${k(revenue.cents)} goods ${k(goods.cents)} '
            'running ${k(running.cents)} profit ${k(profit.cents)} '
            'prices ${normal == 0 ? '-' : (priced / normal).toStringAsFixed(2)}',
          );
        }
      }
    }
    double mean(List<int> values) =>
        values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    print(
      '${key.padRight(12)} ${strategy.key.padRight(11)} '
      '${[for (final m in checkpoints) 'm$m ${k(mean(profits[m]!))}'].join('  ')}'
      '  | all ${k(mean(totals))} vs fit-out ${k(mean(fitOuts))}'
      '  | last year ${k(mean(lastYears))}'
      '  | last year sales ${k(mean(sales))}',
    );
  }
}
