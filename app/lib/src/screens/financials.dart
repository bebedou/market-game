import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../financials.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// Opens all the player's companies' figures, added up.
void openHoldingFinancials(BuildContext context) => context.openPage(
  tr('common.allCompanies'),
  (context) => const [FinancialsSection()],
);

/// The companies picked: one, or all the player's if [company] is null.
List<CompanyView> _companies(SimulationController game, CompanyId? company) => [
  for (final current in game.view.companies)
    if (company == null || current.id == company) current,
];

bool _gone(List<CompanyView> companies) =>
    companies.every((company) => company.status != CompanyStatus.active);

String _name(SimulationController game, CompanyId? company) =>
    company == null ? tr('common.allCompanies') : game.companyName(company);

/// A rate, or a dash if there is none to show.
String _rate(Fx? rate, {int decimals = 1}) =>
    rate == null ? '–' : percent(rate, decimals: decimals);

/// How long a young company has traded.
String _length(int days) => days < 60
    ? tr('terms.days', {'count': days})
    : tr('terms.months', {'count': (days / 30.44).round()});

/// The key figures of a company, or of all the player's, and the ways into
/// the detail.
class FinancialsSection extends StatelessWidget {
  const FinancialsSection({super.key, this.company});

  /// Whose; all the player's companies if null.
  final CompanyId? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final companies = _companies(game, company);
    final financials = financialsOf(game, companies);
    final recent = financials.recent;
    if (recent == null) {
      return Section(
        title: tr('financials.title'),
        icon: Icons.query_stats,
        children: [Hint(tr('financials.nothingYet'))],
      );
    }
    final before = financials.before;
    final gone = _gone(companies);
    final full = [
      for (final year in financials.years.reversed)
        if (!year.soFar) year,
    ];
    final sales = _growth(recent.sales, before);
    return Section(
      title: tr('financials.title'),
      icon: Icons.query_stats,
      children: [
        Hint(
          [
            financials.young
                ? tr('financials.sinceFounding', {
                    'length': _length(recent.days),
                  })
                : gone
                ? tr('financials.itsLast12')
                : tr('financials.last12'),
            if (before != null) tr('financials.againstYearBefore'),
            if (company == null) tr('financials.addedUp'),
          ].join(', '),
        ),
        _Tiles([
          StatTile(
            icon: Icons.payments_outlined,
            label: tr('common.sales'),
            value: Text(money(recent.sales, cents: false)),
            trend: sales?.$1,
            trendSign: sales?.$2 ?? 0,
          ),
          _rateTile(
            context,
            tr('financials.operatingMargin'),
            Icons.storefront_outlined,
            recent.operatingMargin,
            before?.operatingMargin,
          ),
          _rateTile(
            context,
            tr('financials.netMargin'),
            Icons.account_balance_outlined,
            recent.netMargin,
            before?.netMargin,
          ),
          _rateTile(
            context,
            financials.young
                ? tr('financials.roicYearRate')
                : tr('financials.roic'),
            Icons.savings_outlined,
            recent.roic,
            before?.roic,
            decimals: 0,
          ),
        ]),
        Hint(
          gone
              ? tr('financials.noRoicLiquidated')
              : recent.days < Results.roicDays
              ? tr('financials.roicAfterThree')
              : recent.capital <= Money.zero
              ? tr('financials.noRoicBills')
              : tr('financials.roicExplained'),
        ),
        if (full.length > 1) ...[const SizedBox(height: 6), _YearBars(full)],
        IndexRow(
          title: tr('common.profitAndLoss'),
          subtitle: tr('financials.fromSalesDown'),
          onTap: () => context.openPage(
            tr('common.profitAndLoss'),
            (context) => [_ProfitAndLoss(company: company)],
          ),
        ),
        IndexRow(
          title: tr('financials.balanceSheet'),
          subtitle: company == null
              ? tr('financials.ownedAll')
              : tr('financials.ownedOne'),
          onTap: () => context.openPage(
            tr('financials.balanceSheet'),
            (context) => [_BalanceSheet(company: company)],
          ),
        ),
        IndexRow(
          title: tr('financials.yearByYear'),
          subtitle: tr('financials.sinceYear', {
            'year': financials.years.last.year,
          }),
          onTap: () => context.openPage(
            tr('financials.yearByYear'),
            (context) => [_YearByYear(company: company)],
          ),
        ),
      ],
    );
  }

  Widget _rateTile(
    BuildContext context,
    String label,
    IconData icon,
    Fx? rate,
    Fx? before, {
    int decimals = 1,
  }) {
    final trend = _points(rate, before, decimals: decimals);
    return StatTile(
      icon: icon,
      label: label,
      value: Text(
        _rate(rate, decimals: decimals),
        style: TextStyle(
          color: rate != null && rate.raw < 0 ? gainTone(context, -1) : null,
        ),
      ),
      trend: trend?.$1,
      trendSign: trend?.$2 ?? 0,
    );
  }

  /// Sales against the year [before], scaled to a year, and which way.
  (String, int)? _growth(Money now, Results? before) {
    if (before == null) return null;
    final then = before.perYear(before.sales);
    if (then <= Money.zero) return null;
    final change = ((now.cents - then.cents) * 100 / then.cents).round();
    return change == 0
        ? (tr('financials.level'), 0)
        : ('${change > 0 ? '▲' : '▼'} ${percentOf(change.abs())}', change.sign);
  }

  /// A rate's change in points, and which way.
  (String, int)? _points(Fx? now, Fx? then, {required int decimals}) {
    if (now == null || then == null) return null;
    final change = now.raw - then.raw;
    if (change.abs() < (decimals == 0 ? 50 : 5)) {
      return (tr('financials.level'), 0);
    }
    final points = tr('financials.points', {
      'value': percentNumber(Fx.raw(change.abs()), decimals: decimals),
    });
    return ('${change > 0 ? '▲' : '▼'} $points', change.sign);
  }
}

/// Key figures two by two, like the Holding's.
class _Tiles extends StatelessWidget {
  const _Tiles(this.tiles);

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: tiles[i + 1]),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Net profit each full year as bars, the years beneath, oldest first.
class _YearBars extends StatelessWidget {
  const _YearBars(this.years);

  final List<YearResults> years;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarChart([for (final year in years) year.net.cents], height: 70),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final year in years)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${year.year}', style: style),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(tr('financials.netProfitEachYear'), style: style),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// A row of a ruled table: the first cell at the left, the figures lined up
/// at the right and shrunk rather than cut off.
class _Columns extends StatelessWidget {
  const _Columns(
    this.cells, {
    required this.flex,
    this.header = false,
    this.strong = false,
    this.colors = const {},
  });

  final List<String> cells;
  final List<int> flex;
  final bool header;

  /// A total, under a rule of ink.
  final bool strong;

  /// Inks by column.
  final Map<int, Color?> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = header
        ? theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )
        : strong
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          top: strong
              ? BorderSide(color: theme.colorScheme.onSurface)
              : BorderSide.none,
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          for (final (i, cell) in cells.indexed)
            Expanded(
              flex: flex[i],
              child: i == 0
                  ? Text(cell, style: base?.copyWith(color: colors[i]))
                  : Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            cell,
                            style: (header ? base : figures(base))?.copyWith(
                              color: colors[i],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// From sales down to net profit, beside each line's share of sales and the
/// year before.
class _ProfitAndLoss extends StatelessWidget {
  const _ProfitAndLoss({required this.company});

  final CompanyId? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final companies = _companies(game, company);
    final financials = financialsOf(game, companies);
    final recent = financials.recent;
    final before = financials.before;
    if (recent == null) {
      return Section(
        title: _name(game, company),
        children: [Hint(tr('financials.nothingYet'))],
      );
    }
    final flex = before == null ? const [15, 10, 7] : const [12, 9, 6, 9];
    final rows = <Widget>[];
    void add(
      String label,
      Money Function(Results) line, {
      bool cost = false,
      bool strong = false,
    }) {
      final now = line(recent);
      final then = before?.perYear(line(before));
      if (!strong && now == Money.zero && (then ?? now) == Money.zero) return;
      String shown(Money amount) =>
          money(cost ? -amount : amount, cents: false);
      rows.add(
        _Columns(
          [
            label,
            shown(now),
            _rate(recent.shareOfSales(now)),
            if (then != null) shown(then),
          ],
          flex: flex,
          strong: strong,
          colors: {
            if (strong && now.isNegative) 1: gainTone(context, -1),
            if (strong && then != null && then.isNegative)
              3: gainTone(context, -1),
          },
        ),
      );
    }

    add(tr('common.sales'), (r) => r.sales, strong: true);
    add(tr('financials.lines.goodsSold'), (r) => r.goods, cost: true);
    add(tr('financials.lines.spoiled'), (r) => r.spoiled, cost: true);
    add(tr('financials.lines.grossProfit'), (r) => r.gross, strong: true);
    add(tr('financials.lines.staff'), (r) => r.staff, cost: true);
    add(tr('financials.lines.premises'), (r) => r.premises, cost: true);
    add(tr('financials.lines.marketing'), (r) => r.marketing, cost: true);
    add(tr('financials.lines.research'), (r) => r.research, cost: true);
    add(
      tr('financials.lines.operatingProfit'),
      (r) => r.operating,
      strong: true,
    );
    add(tr('financials.lines.interest'), (r) => r.interest, cost: true);
    add(tr('financials.lines.works'), (r) => r.works, cost: true);
    add(tr('financials.lines.tax'), (r) => r.tax, cost: true);
    add(tr('financials.lines.oneOffs'), (r) => r.oneOffs);
    add(tr('financials.lines.netProfit'), (r) => r.net, strong: true);
    return Section(
      title: _name(game, company),
      children: [
        _Columns(
          [
            '',
            financials.young ? _length(recent.days) : tr('financials.months12'),
            tr('financials.percentOfSales'),
            if (before != null) tr('financials.yearBefore'),
          ],
          flex: flex,
          header: true,
        ),
        ...rows,
        Hint(tr('financials.operatingHint')),
        if (before != null && before.months < 12)
          Hint(tr('financials.scaledHint', {'months': before.months})),
      ],
    );
  }
}

/// What the company owns and owes today, and the money it has tied up.
class _BalanceSheet extends StatelessWidget {
  const _BalanceSheet({required this.company});

  final CompanyId? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final companies = _companies(game, company);
    final financials = financialsOf(game, companies);
    final recent = financials.recent;
    Money balance(AccountKind kind) => financials.balance(kind);
    final bought = balance(AccountKind.businessAssets);
    final kept = financials.retainedEarnings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: _name(game, company),
          children: [
            Hint(tr('financials.asOfToday')),
            Line(tr('common.cash'), money(balance(AccountKind.cash))),
            Line(
              tr('common.stockAtCost'),
              money(balance(AccountKind.inventory)),
            ),
            if (bought != Money.zero)
              Line(
                tr('financials.storesBought'),
                money(bought),
                hint: tr('financials.storesBoughtHint'),
              ),
            if (balance(AccountKind.investments) != Money.zero)
              Line(
                tr('financials.stakes'),
                money(balance(AccountKind.investments)),
              ),
            Line(
              tr('common.unpaidBills'),
              money(balance(AccountKind.payables)),
            ),
            if (balance(AccountKind.loans) != Money.zero)
              Line(tr('financials.loans'), money(balance(AccountKind.loans))),
            Line(
              tr('financials.netAssets'),
              money(financials.netAssets),
              strong: true,
            ),
            const Divider(),
            Line(
              tr('financials.capitalIn'),
              money(-balance(AccountKind.equity)),
            ),
            Line(
              tr('financials.profitKept'),
              signedMoney(kept),
              color: gainColor(context, kept.cents.sign),
            ),
            Hint(tr('financials.fitOutSpent')),
          ],
        ),
        if (!_gone(companies))
          Section(
            title: tr('financials.tiedUp'),
            children: [
              Line(
                tr('financials.fitOutAtCost'),
                money(financials.fitOut),
                hint: tr('financials.fitOutHint'),
              ),
              if (bought != Money.zero)
                Line(tr('financials.storesBought'), money(bought)),
              Line(
                tr('common.stockAtCost'),
                money(balance(AccountKind.inventory)),
              ),
              Line(
                tr('common.unpaidBills'),
                money(balance(AccountKind.payables)),
              ),
              Line(
                tr('financials.tiedUpToday'),
                money(financials.capital),
                strong: true,
              ),
              if (recent != null) ...[
                Line(
                  tr('financials.average'),
                  money(recent.capital),
                  hint: tr('financials.averageHint'),
                ),
                Line(
                  tr('financials.roic'),
                  _rate(recent.roic, decimals: 0),
                  hint: tr('financials.roicHint'),
                ),
              ],
              Hint(tr('financials.noWear')),
            ],
          ),
      ],
    );
  }
}

/// Each year as filed, and the margins of those whose reports are still kept.
class _YearByYear extends StatelessWidget {
  const _YearByYear({required this.company});

  /// Filed: year, sales, net profit, net margin, stores.
  static const _filed = [6, 11, 11, 7, 6];

  /// In detail: year, gross, operating and net margins, ROIC.
  static const _detail = [6, 8, 8, 8, 8];

  final CompanyId? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final years = financialsOf(game, _companies(game, company)).years;
    if (years.isEmpty) {
      return Section(
        title: _name(game, company),
        children: [Hint(tr('financials.nothingYet'))],
      );
    }
    final full = [
      for (final year in years.reversed)
        if (!year.soFar) year,
    ];
    String label(YearResults year) => '${year.year}${year.soFar ? '*' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: _name(game, company),
          children: [
            if (full.length > 1) _YearBars(full),
            _Columns(
              [
                '',
                tr('common.sales'),
                tr('financials.lines.netProfit'),
                tr('financials.margin'),
                tr('financials.stores'),
              ],
              flex: _filed,
              header: true,
            ),
            for (final year in years)
              _Columns(
                [
                  label(year),
                  money(year.sales, cents: false),
                  signedMoney(year.net, cents: false),
                  year.sales.cents == 0
                      ? '–'
                      : percent(
                          Fx.raw(
                            (year.net.cents * Fx.scale / year.sales.cents)
                                .round(),
                          ),
                        ),
                  '${year.stores}',
                ],
                flex: _filed,
                colors: {2: gainColor(context, year.net.cents.sign)},
              ),
            if (years.any((year) => year.soFar))
              Hint(tr('financials.yearSoFar')),
          ],
        ),
        Section(
          title: tr('financials.marginsRoic'),
          children: [
            _Columns(
              [
                '',
                tr('financials.gross'),
                tr('financials.operating'),
                tr('financials.net'),
                tr('financials.roic'),
              ],
              flex: _detail,
              header: true,
            ),
            for (final year in years)
              if (year.detail case final detail?)
                _Columns([
                  label(year),
                  _rate(detail.grossMargin),
                  _rate(detail.operatingMargin),
                  _rate(detail.netMargin),
                  _rate(detail.roic, decimals: 0),
                ], flex: _detail),
            Hint(tr('financials.marginsHint')),
          ],
        ),
      ],
    );
  }
}
