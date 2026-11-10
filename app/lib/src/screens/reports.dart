import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// Weekly and monthly results, why they changed, and market research.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.week;

  /// The start of the report picked; null for the latest complete one.
  Day? _picked;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final reports = game.reports(_period);
    var index = reports.lastIndexWhere((report) => report.complete);
    if (index < 0) index = reports.length - 1;
    if (_picked case final picked?) {
      final found = reports.indexWhere((report) => report.start == picked);
      if (found >= 0) index = found;
    }
    final report = index < 0 ? null : reports[index];
    final previous = index > 0 ? reports[index - 1] : null;
    return ListView(
      key: const PageStorageKey('reports'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: SegmentedButton<ReportPeriod>(
            segments: [
              ButtonSegment(
                value: ReportPeriod.week,
                label: Text(tr('reports.week')),
              ),
              ButtonSegment(
                value: ReportPeriod.month,
                label: Text(tr('reports.month')),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (selected) => setState(() {
              _period = selected.single;
              _picked = null;
            }),
          ),
        ),
        if (report == null)
          Section(
            title: tr('reports.noResults'),
            children: [Hint(tr('reports.startOnceRuns'))],
          )
        else ...[
          if (reports.length > 1)
            Section(
              title: _period == ReportPeriod.week
                  ? tr('common.profitByWeek')
                  : tr('common.profitByMonth'),
              icon: Icons.bar_chart_rounded,
              children: [
                BarChart(
                  [for (final report in reports) report.tradingProfit.cents],
                  selected: index,
                  onSelect: (i) => setState(() => _picked = reports[i].start),
                ),
                Hint(tr('reports.tapBar')),
              ],
            ),
          _PeriodPicker(
            report: report,
            onPrevious: index > 0
                ? () => setState(() => _picked = reports[index - 1].start)
                : null,
            onNext: index < reports.length - 1
                ? () => setState(() => _picked = reports[index + 1].start)
                : null,
          ),
          Section(
            title: _period == ReportPeriod.week
                ? tr('reports.thisWeek')
                : tr('reports.thisMonth'),
            children: [
              IndexRow(
                title: tr('reports.whatHappened'),
                subtitle: explainChange(game, report, previous).first,
                onTap: () => context.openPage(
                  tr('reports.whatHappened'),
                  (_) => [_WhatChanged(report: report, previous: previous)],
                ),
              ),
              IndexRow(
                title: tr('common.profitAndLoss'),
                subtitle: tr('reports.salesSummary', {
                  'amount': money(_sales(report), cents: false),
                }),
                value: signedMoney(report.tradingProfit, cents: false),
                valueColor: gainColor(context, report.tradingProfit.cents.sign),
                onTap: () => context.openPage(
                  tr('common.profitAndLoss'),
                  (_) => [_Results(report: report)],
                ),
              ),
              for (final store in report.stores) ...[
                IndexRow(
                  title: tr('reports.shoppersAt', {
                    'store': game.view.shelves[store.store.index].name,
                  }),
                  subtitle: tr('reports.tripsPitch'),
                  value: '${store.visits}',
                  onTap: () => context.openPage(
                    tr('reports.shoppers'),
                    (_) => [_Shoppers(report: report, store: store)],
                  ),
                ),
                IndexRow(
                  title: tr('reports.productsAt', {
                    'store': game.view.shelves[store.store.index].name,
                  }),
                  subtitle: tr('reports.productsPitch'),
                  onTap: () => context.openPage(
                    tr('reports.products'),
                    (_) => [_Products(store: store)],
                  ),
                ),
              ],
            ],
          ),
        ],
        Section(
          title: tr('reports.research'),
          children: [
            IndexRow(
              title: tr('reports.marketResearch'),
              subtitle: tr('reports.studies', {
                'count': game.view.reports.length,
              }),
              onTap: () => context.openPage(
                tr('reports.marketResearch'),
                (_) => [const _Research()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `Week of 5 Jan` or `January 2026`.
String periodName(PeriodReport report) => switch (report.period) {
  ReportPeriod.week => tr('reports.weekOf', {'date': shortDate(report.start)}),
  ReportPeriod.month => monthName(report.start),
};

/// The period as it reads within a sentence: `the week of 5 Jan`.
String _periodInSentence(PeriodReport report) => switch (report.period) {
  ReportPeriod.week => tr('reports.theWeekOf', {
    'date': shortDate(report.start),
  }),
  ReportPeriod.month => monthName(report.start, capital: false),
};

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.report,
    required this.onPrevious,
    required this.onNext,
  });

  final PeriodReport report;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = report.end.number - report.start.number;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: tr('reports.earlier'),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Column(
              children: [
                Text(periodName(report), style: theme.textTheme.titleMedium),
                Text(
                  report.complete
                      ? report.days < length
                            ? tr('reports.daysRecorded', {'days': report.days})
                            : tr('reports.complete')
                      : tr('reports.soFar', {
                          'days': report.days,
                          'length': length,
                        }),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: tr('reports.later'),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// The lines of a profit and loss statement, as accounts and labels. Each
/// account's flow takes away from profit.
const _costs = [
  (AccountKind.costOfGoods, 'reports.costs.goods'),
  (AccountKind.wages, 'reports.costs.wages'),
  (AccountKind.salaries, 'reports.costs.salaries'),
  (AccountKind.writeOffs, 'reports.costs.writeOffs'),
  (AccountKind.interest, 'reports.costs.interest'),
  (AccountKind.research, 'reports.costs.research'),
  (AccountKind.marketing, 'reports.costs.marketing'),
];

/// What lies between trading profit and profit.
const _beyondTrading = [
  (AccountKind.openingCosts, 'reports.beyond.invested'),
  (AccountKind.taxes, 'reports.beyond.tax'),
  (AccountKind.debtRelief, 'reports.beyond.debts'),
];

Money _sales(PeriodReport report) => -report.flow(AccountKind.revenue);

int _visits(PeriodReport report) =>
    report.stores.fold(0, (sum, store) => sum + store.visits);

/// Explains, in a few sentences, how [report]'s profit differs from
/// [previous]'s: the lines that moved it most, and where shoppers and sales
/// went.
List<String> explainChange(
  SimulationController game,
  PeriodReport report,
  PeriodReport? previous,
) {
  final content = game.content;
  final view = game.view;
  final lines = <String>[];
  if (previous == null) {
    lines.add(
      tr('reports.profitOnSales', {
        'profit': signedMoney(report.tradingProfit),
        'sales': money(_sales(report)),
      }),
    );
  } else {
    final change = report.tradingProfit - previous.tradingProfit;
    lines.add(
      tr(change >= Money.zero ? 'reports.profitUp' : 'reports.profitDown', {
        'profit': signedMoney(report.tradingProfit),
        'change': money(change.cents < 0 ? -change : change),
        'period': _periodInSentence(previous),
      }),
    );
    if (report.days != previous.days) {
      lines.add(
        tr('reports.daysCompared', {
          'days': report.days,
          'before': previous.days,
        }),
      );
    }
    final movers = <(String, Money)>[
      (tr('common.sales'), _sales(report) - _sales(previous)),
      for (final (kind, label) in _costs)
        (tr(label), previous.flow(kind) - report.flow(kind)),
    ]..sort((a, b) => b.$2.cents.abs().compareTo(a.$2.cents.abs()));
    for (final (label, impact) in movers.take(3)) {
      if (impact == Money.zero) continue;
      var detail = '';
      if (label == tr('common.sales')) {
        final visits = _visits(report) - _visits(previous);
        detail = tr('reports.moverTrips', {
          'trips': '${visits >= 0 ? '+' : ''}$visits',
        });
      }
      lines.add(
        tr('reports.mover', {
          'line': label,
          'impact': signedMoney(impact),
          'detail': detail,
        }),
      );
    }
  }

  // Trips won from and lost to each rival on balance, and what drew them
  // most.
  final net = <StoreId, int>{};
  final drew = <StoreId, Map<SwitchCause, int>>{};
  final took = <StoreId, Map<SwitchCause, int>>{};
  for (final store in report.stores) {
    store.gained.forEach((key, trips) {
      net[key.store] = (net[key.store] ?? 0) + trips;
      final causes = drew[key.store] ??= {};
      causes[key.cause] = (causes[key.cause] ?? 0) + trips;
    });
    store.lost.forEach((key, trips) {
      net[key.store] = (net[key.store] ?? 0) - trips;
      final causes = took[key.store] ??= {};
      causes[key.cause] = (causes[key.cause] ?? 0) + trips;
    });
  }
  SwitchCause? most(Map<SwitchCause, int>? causes) => causes?.entries
      .fold<MapEntry<SwitchCause, int>?>(
        null,
        (best, e) => best == null || e.value > best.value ? e : best,
      )
      ?.key;
  final rivals = net.entries.where((e) => e.value != 0).toList()
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  for (final MapEntry(key: store, value: trips) in rivals.take(2)) {
    final name = view.shelves[store.index].name;
    if (trips > 0) {
      final cause = most(drew[store]);
      lines.add(
        cause == null
            ? tr('reports.netGain', {'trips': trips, 'store': name})
            : tr('reports.netGainWhy', {
                'trips': trips,
                'store': name,
                'cause': causeText(cause),
              }),
      );
    } else {
      final cause = most(took[store]);
      lines.add(
        cause == null
            ? tr('reports.netLoss', {'trips': -trips, 'store': name})
            : tr('reports.netLossWhy', {
                'trips': -trips,
                'store': name,
                'cause': causeText(cause),
              }),
      );
    }
  }

  // The biggest missed sales.
  final misses = <(ProductDef, MissReason, int)>[
    for (final store in report.stores)
      for (final product in content.products)
        for (final reason in [MissReason.outOfStock, MissReason.overpriced])
          if (store.missed(reason, product.id) case final units when units > 0)
            (product, reason, units),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  for (final (product, reason, units) in misses.take(2)) {
    lines.add(
      tr('reports.notSold', {
        'units': units,
        'product': product.name,
        'reason': missText(reason),
      }),
    );
  }
  return lines;
}

class _WhatChanged extends StatelessWidget {
  const _WhatChanged({required this.report, required this.previous});

  final PeriodReport report;
  final PeriodReport? previous;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return Section(
      title: tr('reports.whatHappened'),
      icon: Icons.lightbulb_outline,
      children: [
        for (final line in explainChange(game, report, previous))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(line)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.report});

  final PeriodReport report;

  @override
  Widget build(BuildContext context) {
    final sales = _sales(report);
    final gross = sales - report.flow(AccountKind.costOfGoods);
    final scheme = Theme.of(context).colorScheme;
    // Rent and overheads are paid on the first for the month; the period
    // bears its days' share.
    final occupancy =
        report.flow(AccountKind.rent) +
        report.flow(AccountKind.overheads) -
        report.rentPaidAhead;
    final other =
        report.flow(AccountKind.writeOffs) +
        report.flow(AccountKind.interest) +
        report.flow(AccountKind.research) +
        report.flow(AccountKind.salaries) +
        report.flow(AccountKind.marketing);
    return Section(
      title: tr('common.profitAndLoss'),
      icon: Icons.receipt_long_outlined,
      children: [
        if (sales > Money.zero) ...[
          SplitBar([
            (
              label: tr('reports.shares.goods'),
              value: report.flow(AccountKind.costOfGoods).cents,
              color: scheme.secondary,
            ),
            (
              label: tr('reports.shares.wages'),
              value: report.flow(AccountKind.wages).cents,
              color: scheme.tertiary,
            ),
            (
              label: tr('reports.shares.rent'),
              value: occupancy.cents,
              color: scheme.primary.withValues(alpha: 0.55),
            ),
            (
              label: tr('reports.shares.other'),
              value: other.cents,
              color: scheme.outline,
            ),
            (
              label: tr('common.profit'),
              value: report.tradingProfit.cents,
              color: gainTone(context, 1),
            ),
          ]),
          const SizedBox(height: 10),
        ],
        Line(tr('common.sales'), money(sales), strong: true),
        for (final (kind, label) in _costs)
          if (report.flow(kind) != Money.zero)
            Line(tr(label), money(-report.flow(kind))),
        if (occupancy != Money.zero)
          Line(
            tr('reports.occupancy'),
            money(-occupancy),
            hint: tr('reports.occupancyHint'),
          ),
        Line(
          tr('reports.grossMargin'),
          '${money(gross)} (${share(gross.cents, sales.cents)})',
          hint: tr('reports.grossMarginHint'),
        ),
        const Divider(),
        Line(
          tr('reports.tradingProfit'),
          signedMoney(report.tradingProfit),
          strong: true,
          color: gainColor(context, report.tradingProfit.cents.sign),
          hint: tr('reports.tradingProfitHint'),
        ),
        if (report.rentPaidAhead != Money.zero)
          Line(
            report.rentPaidAhead > Money.zero
                ? tr('reports.paidAhead')
                : tr('reports.paidEarlier'),
            signedMoney(-report.rentPaidAhead),
            hint: report.rentPaidAhead > Money.zero
                ? tr('reports.paidAheadHint')
                : tr('reports.paidEarlierHint'),
          ),
        for (final (kind, label) in _beyondTrading)
          if (report.flow(kind) != Money.zero)
            Line(tr(label), money(-report.flow(kind))),
        if (report.flow(AccountKind.disposals) != Money.zero)
          Line(
            tr('reports.gainOnStores'),
            signedMoney(-report.flow(AccountKind.disposals)),
            color: gainColor(
              context,
              -report.flow(AccountKind.disposals).cents.sign,
            ),
            hint: tr('reports.gainOnStoresHint'),
          ),
        if (report.profit != report.tradingProfit)
          Line(
            tr('common.profit'),
            signedMoney(report.profit),
            color: gainColor(context, report.profit.cents.sign),
            hint: tr('reports.profitKeptHint'),
          ),
        if (report.flow(AccountKind.dividends) != Money.zero)
          Line(
            tr('reports.dividendsPaid'),
            money(report.flow(AccountKind.dividends)),
          ),
      ],
    );
  }
}

class _Shoppers extends StatelessWidget {
  const _Shoppers({required this.report, required this.store});

  final PeriodReport report;
  final StoreReport store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final shelves = game.view.shelves;
    List<Widget> switches(Map<SwitchKey, int> trips, String wording) {
      final sorted = trips.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final MapEntry(key: (:store, :cause), value: count) in sorted)
          Line(
            tr(wording, {'store': shelves[store.index].name}),
            '$count',
            hint: causeText(cause),
          ),
      ];
    }

    return Section(
      title: tr('reports.shoppersAt', {
        'store': shelves[store.store.index].name,
      }),
      icon: Icons.groups_2_outlined,
      children: [
        Line(
          tr('reports.shoppingTrips'),
          '${store.visits}',
          strong: true,
          hint: report.days == 0
              ? null
              : tr('reports.tripsPerDay', {
                  'trips': store.visits ~/ report.days,
                }),
        ),
        if (store.gained.isNotEmpty) ...[
          Hint(tr('reports.cameHere')),
          ...switches(store.gained, 'reports.fromStore'),
        ],
        if (store.lost.isNotEmpty) ...[
          Hint(tr('reports.wentElsewhere')),
          ...switches(store.lost, 'reports.toStore'),
        ],
      ],
    );
  }
}

class _Products extends StatelessWidget {
  const _Products({required this.store});

  final StoreReport store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return Section(
      title: tr('reports.products'),
      icon: Icons.inventory_2_outlined,
      children: [
        for (final product in game.content.products)
          if (_active(product.id))
            Line(
              product.name,
              money(store.revenue(product.id)),
              hint: [
                tr('reports.soldUnits', {'units': store.sold(product.id)}),
                tr('reports.marginLine', {
                  'amount': money(
                    store.revenue(product.id) - store.costOfGoods(product.id),
                  ),
                }),
                if (store.spoiled(product.id) > 0)
                  tr('reports.spoiled', {'units': store.spoiled(product.id)}),
                for (final reason in MissReason.values)
                  if (store.missed(reason, product.id) case final units
                      when units > 0)
                    '$units ${missText(reason)}',
              ].join(' · '),
            ),
      ],
    );
  }

  bool _active(ProductId product) =>
      store.sold(product) > 0 ||
      store.spoiled(product) > 0 ||
      MissReason.values.any((reason) => store.missed(reason, product) > 0);
}

class _Research extends StatefulWidget {
  const _Research();

  @override
  State<_Research> createState() => _ResearchState();
}

class _ResearchState extends State<_Research> {
  /// The city to study; the selected store's until the player picks one.
  MarketId? _market;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.company;
    final content = game.content;
    final level = game.view.macro.priceIndex;
    final canBuy = company != null && company.status == CompanyStatus.active;
    final market = _market ?? game.store?.market ?? content.markets.first.id;
    return Section(
      title: tr('reports.marketResearch'),
      icon: Icons.science_outlined,
      children: [
        Hint(tr('reports.studiesPitch')),
        if (content.markets.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DropdownButtonFormField<MarketId>(
              initialValue: market,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('reports.cityToStudy')),
              items: [
                for (final option in content.markets)
                  DropdownMenuItem(value: option.id, child: Text(option.name)),
              ],
              onChanged: (next) => setState(() => _market = next),
            ),
          ),
        for (final tier in content.researchTiers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tier.name),
            subtitle: Text(
              tr('reports.studyCost', {
                'cost': money(tier.cost.times(level)),
                'error': percent(tier.error, decimals: 0),
              }),
            ),
            trailing: TextButton(
              onPressed: canBuy
                  ? () => game.submit(
                      BuyResearch(
                        game.player,
                        company: company.id,
                        market: market,
                        tier: tier.id,
                      ),
                    )
                  : null,
              child: Text(tr('common.buy')),
            ),
          ),
        for (final report in game.view.reports.reversed)
          _StudyTile(report: report),
      ],
    );
  }
}

class _StudyTile extends StatelessWidget {
  const _StudyTile({required this.report});

  final ResearchReport report;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final tier = content.researchTiers[report.tier.index];
    final theme = Theme.of(context);
    return ExpansionTile(
      // Its own key, so its open state isn't confused with the list's
      // scroll position in the page storage.
      key: PageStorageKey('study ${report.number}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        tr('reports.studyTitle', {
          'study': tier.name,
          'date': shortDate(report.asOf),
          'year': report.asOf.date.year,
        }),
      ),
      subtitle: Text(
        tr('reports.studySubtitle', {
          'market': content.markets[report.market.index].name,
          'error': percent(tier.error, decimals: 0),
        }),
      ),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A study bought before the scenario grew covers fewer segments.
        for (final segment in content.segments.take(report.segments.length))
          if (report.segments[segment.id.index].households > 0) ...[
            Text(segment.name, style: theme.textTheme.titleSmall),
            _segment(
              game,
              report.segments[segment.id.index],
              report.segments.fold(0, (sum, each) => sum + each.households),
            ),
            const SizedBox(height: 8),
          ],
        Text(tr('reports.unitShares'), style: theme.textTheme.titleSmall),
        for (final (:store, :share) in report.unitShares)
          Line(
            game.view.shelves[store.index].name,
            percent(share, decimals: 0),
            hint: content
                .formats[game.view.shelves[store.index].format.index]
                .name,
          ),
      ],
    );
  }

  /// [estimate]'s segment, its households a share of [households] in all.
  Widget _segment(
    SimulationController game,
    SegmentEstimate estimate,
    int households,
  ) {
    final content = game.content;
    final slots = [
      for (final slot in DaySlot.values)
        '${slotName(slot).toLowerCase()} ${percent(estimate.slotShares[slot.index], decimals: 0)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Line(
          tr('reports.shareOfShoppers'),
          percent(
            Fx.raw((estimate.households * Fx.scale / households).round()),
            decimals: 0,
          ),
        ),
        for (final category in content.categories.take(
          estimate.dailyUnits.length,
        ))
          Line(
            category.name,
            tr('reports.perDayEach', {
              'units': fxText(estimate.dailyUnits[category.id.index]),
            }),
            hint: tr('reports.choosePremium', {
              'share': percent(
                estimate.premiumShare[category.id.index],
                decimals: 0,
              ),
            }),
          ),
        Line(
          tr('reports.priceSensitivity'),
          fxText(estimate.priceSensitivity),
          hint: tr('reports.priceSensitivityHint', {
            'tolerance': percent(estimate.priceTolerance, decimals: 0),
          }),
        ),
        Hint(tr('reports.shopsIn', {'slots': slots.join(', ')})),
      ],
    );
  }
}
