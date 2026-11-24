import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../business.dart';
import '../controller.dart';
import '../directors.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../mail.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'business_page.dart' show arrow, toneColor;
import 'desk.dart' show DeskMail, DeskNews, answeredWith;
import 'company.dart';
import 'exchange.dart' show HoldingRow, PortfolioPage;
import 'shop.dart';
import 'start.dart';

/// The holding, the owner's layout B (2026-11-17): a company like the
/// others, the player its boss. Its name is in the top bar; then a verdict,
/// four key figures, what needs the player, its companies with their worth,
/// its own books, its shares, and what there is to read. Its companies'
/// businesses are on their pages.
class HoldingScreen extends StatelessWidget {
  const HoldingScreen({super.key, required this.onOpen});

  /// Switches to another tab.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    // Worked out once: the countries by formula take a while.
    final national = game.view.national;
    final companies = game.activeCompanies;
    final businesses = [
      for (final company in companies) ...businessesOf(game, company, national),
    ];
    final profits = monthlyProfits(game);
    final verdict = companies.isEmpty
        ? (tone: Tone.watch, text: tr('verdicts.noCompany'))
        : companyVerdict(profits, businesses);
    final debt = companies.fold(
      game.shareLoans,
      (sum, company) => sum + debtOf(company),
    );
    // The desk: what waits on the player, said in the verdict too.
    final waiting = [
      for (final mail in mailOf(game))
        if (answeredWith(game, mail) == null) mail,
    ].length;
    return ListView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        VerdictBox(
          waiting == 0
              ? verdict.text
              : '${verdict.text} ${tr('mail.verdict', {'count': waiting})}',
          color: toneColor(context, verdict.tone),
        ),
        FigureGrid([
          (
            label: tr('common.netWorth'),
            value: compactMoney(game.netWorth),
            values: null,
          ),
          (
            label: tr('businesses.figures.profit'),
            value: profits.isEmpty
                ? '–'
                : signedMoney(profits.last, cents: false),
            values: [for (final profit in profits) profit.cents],
          ),
          (
            label: tr('dashboard.cash'),
            value: compactMoney(game.view.cash),
            values: null,
          ),
          (
            label: tr('businesses.figures.debt'),
            value: compactMoney(debt),
            values: null,
          ),
        ]),
        DeskMail(
          onOpen: onOpen,
          toDo: toDoItems(context, game, onOpen, inSection: true),
        ),
        DeskNews(
          allNews: () => context.openPage(
            tr('common.news'),
            (context) => [_News(game: context.game)],
          ),
        ),
        _Companies(onOpen: onOpen),
        const _HoldingBooks(),
        _Portfolio(onOpen: onOpen),
        const _Profits(),
      ],
    );
  }
}

/// What needs doing, across the holding or at [only] company, each a line
/// ruled in red that opens where it is done; set inside a section if
/// [inSection].
List<Widget> toDoItems(
  BuildContext context,
  SimulationController game,
  OpenTab onOpen, {
  CompanyId? only,
  bool inSection = false,
}) {
  final stores = [
    for (final entry in game.myStores)
      if (only == null || entry.$1.id == only) entry,
  ];
  final active = game.view.companies.any(
    (company) => company.status == CompanyStatus.active,
  );
  final items = <(String, String, StoreView?, VoidCallback?)>[
    if (!active && only == null)
      (
        tr('dashboard.noCompany'),
        tr('dashboard.noCompanyDetail'),
        null,
        () => openStartBusiness(context),
      ),
    for (final company in game.view.companies)
      if ((only == null || company.id == only) && _belowCushion(game, company))
        (
          tr('dashboard.essentials'),
          tr('dashboard.essentialsDetail', {
            'at': game.view.companies.length > 1
                ? tr('common.namePrefix', {
                    'name': game.companyName(company.id),
                  })
                : '',
          }),
          null,
          () => onOpen(HomeTab.finance),
        ),
    for (final (company, store) in stores)
      if (company.status == CompanyStatus.active &&
          store.status != StoreStatus.closed) ...[
        if (store.listedProducts > 0 &&
            !game.delegates(store, ManagerDuty.ordering) &&
            !game.pending.any(
              (command) => command is PlaceOrder && command.store == store.id,
            ) &&
            [
              for (final product in game.content.products)
                if (store.prices[product.id.index] != null)
                  store.stock[product.id.index] +
                      store.onOrder[product.id.index],
            ].every((units) => units == 0))
          (
            tr('dashboard.emptyShelves'),
            tr('dashboard.emptyShelvesDetail', {'at': _at(game, store)}),
            store,
            () => onOpen(HomeTab.shop, part: ShopPart.supplies),
          ),
        if (game.staffOf(store).every((staff) => staff == 0) &&
            !game.delegates(store, ManagerDuty.staffing))
          (
            tr('dashboard.noStaff'),
            tr('dashboard.noStaffDetail', {'at': _at(game, store)}),
            store,
            () => onOpen(HomeTab.shop, part: ShopPart.running),
          ),
      ],
  ];
  final theme = Theme.of(context);
  final ledger = Ledger.of(context);
  return [
    for (final (title, detail, store, open) in items)
      FadeSlideIn(
        child: InkWell(
          onTap: open == null
              ? null
              : () {
                  if (store != null) game.selectStore(store.id);
                  open();
                },
          child: Container(
            margin: inSection
                ? const EdgeInsets.only(top: 8, bottom: 4)
                : const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: ledger.loss, width: 3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(detail, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (open != null) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
  ];
}

/// Whether [company] restocks through managers but its free cash is below
/// its cushion, so they buy only the essentials.
bool _belowCushion(SimulationController game, CompanyView company) =>
    company.status == CompanyStatus.active &&
    company.stores.any(
      (store) =>
          store.status != StoreStatus.closed &&
          game.delegates(store, ManagerDuty.ordering),
    ) &&
    company.cash - company.committed < game.cushion(company);

/// "Store name: ", to say where a to-do is once there are several stores.
String _at(SimulationController game, StoreView store) =>
    game.myStores.length > 1
    ? tr('common.namePrefix', {'name': game.storeName(store.id)})
    : '';

/// The holding's companies, a line each with who runs it, what it is
/// worth and whether its profit rose last month, opening its page; then
/// the way to start another business.
class _Companies extends StatelessWidget {
  const _Companies({required this.onOpen});

  /// Switches to another tab, from a company's page.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final directors = game.content.directors;
    // Those it holds directly; subsidiaries are on their parents' pages.
    final companies = [
      for (final company in game.activeCompanies)
        if (company.parent == null) company,
    ];
    return Section(
      title: companies.length == 1
          ? tr('common.yourCompany')
          : tr('common.yourCompanies'),
      children: [
        for (final company in companies)
          () {
            final profits = monthlyProfits(game, company: company.id);
            final director = game.directorOf(company);
            final last = profits.lastOrNull ?? Money.zero;
            final before = profits.length > 1
                ? profits[profits.length - 2]
                : Money.zero;
            return IndexRow(
              title: game.companyName(company.id),
              subtitle: [
                switch (director) {
                  final director? when directors != null =>
                    tr('dashboard.runBy', {
                      'director':
                          directorPerson(game, company, director)?.name ??
                          aDirector(directors.grades[director.grade.index]),
                    }),
                  _ => tr('businesses.runByYou'),
                },
                if (game.subsidiariesOf(company.id) case final subsidiaries
                    when subsidiaries.isNotEmpty)
                  tr('businesses.withSubsidiaries', {
                    'count': subsidiaries.length,
                  }),
              ].join(' · '),
              value:
                  '${compactMoney(SimulationController.worthOf(company))}'
                  '${arrow(last, before)}',
              onTap: () => openCompanyDashboard(context, company, onOpen),
            );
          }(),
        // The holding holds companies: a new business is one of its own.
        IndexRow(
          icon: Icons.add_business_outlined,
          title: companies.isEmpty
              ? tr('common.startBusiness')
              : tr('common.startSubsidiary'),
          subtitle: tr('dashboard.startBusinessPitch'),
          onTap: () =>
              openStartBusiness(context, subsidiary: companies.isNotEmpty),
        ),
      ],
    );
  }
}

class _News extends StatelessWidget {
  const _News({required this.game});

  final SimulationController game;

  @override
  Widget build(BuildContext context) => Section(
    title: tr('common.news'),
    icon: Icons.campaign_outlined,
    children: [
      if (game.alerts.isEmpty) Hint(tr('dashboard.pressPlay')),
      for (final alert in game.alerts)
        FadeSlideIn(key: ObjectKey(alert), child: AlertTile(alert)),
    ],
  );
}

/// The holding's own books: its cash, its shares at their price, what its
/// companies are worth, less what it owes on its shares, coming to its net
/// worth.
class _HoldingBooks extends StatelessWidget {
  const _HoldingBooks();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final ledger = Ledger.of(context);
    final loans = game.shareLoans;
    return Section(
      title: tr('dashboard.holdingBooks'),
      children: [
        Line(
          tr('dashboard.cash'),
          money(view.cash, cents: false),
          hint: switch (view.lastBankruptcy) {
            final day? => tr('dashboard.bankruptOn', {
              'date': shortDate(day),
              'year': day.date.year,
            }),
            null => null,
          },
        ),
        if (view.stocks != null)
          Line(tr('dashboard.shares'), money(view.portfolio, cents: false)),
        if (view.companies.isNotEmpty)
          Line(
            tr('dashboard.companiesWorth'),
            money(game.companiesWorth, cents: false),
            hint: view.listedCompanies.isEmpty
                ? null
                : tr('dashboard.companiesWorthHint'),
          ),
        if (loans > Money.zero)
          Line(
            tr('dashboard.shareLoans'),
            money(-loans, cents: false),
            color: ledger.loss,
          ),
        Line(
          tr('common.netWorth'),
          money(game.netWorth, cents: false),
          strong: true,
        ),
        ..._results(context, game),
        IndexRow(
          icon: Icons.edit_outlined,
          title: tr('dashboard.renameHolding'),
          subtitle: game.holdingName ?? tr('home.yourHolding'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => GameScope(
              controller: game,
              child: const _RenameHoldingDialog(),
            ),
          ),
        ),
      ],
    );
  }

  /// What the holding made of its own this year: dividends in, gains on
  /// what it sold, less fees, interest, taxes and what it wrote off; the
  /// lines it has, their sum, then its months' own results as a line.
  static List<Widget> _results(
    BuildContext context,
    SimulationController game,
  ) {
    final months = game.view.holdingMonths;
    if (months.isEmpty) return const [];
    final ledger = Ledger.of(context);
    // Income is a credit, so negative; costs a debit.
    const kinds = [
      ('dividendsIn', AccountKind.dividends),
      ('gains', AccountKind.disposals),
      ('fees', AccountKind.spending),
      ('interest', AccountKind.interest),
      ('taxes', AccountKind.taxes),
      ('writtenOff', AccountKind.writeOffs),
    ];
    Money own(HoldingMonth month) =>
        kinds.fold(Money.zero, (sum, kind) => sum - month.flow(kind.$2));
    final year = game.today.date.year;
    final thisYear = [
      for (final month in months)
        if (month.start.date.year == year) month,
    ];
    final shown = [
      for (final (key, kind) in kinds)
        if (thisYear.fold(Money.zero, (sum, m) => sum - m.flow(kind))
            case final amount when amount != Money.zero)
          (key, amount),
    ];
    // Its complete months, the last twelve.
    final current = ReportPeriod.month.startOf(game.today);
    final past = [
      for (final month in months)
        if (month.start != current) own(month),
    ];
    final trend = past.length > 12 ? past.sublist(past.length - 12) : past;
    final moving = trend.any((result) => result != Money.zero);
    if (shown.isEmpty && !moving) return const [];
    final total = shown.fold(Money.zero, (sum, line) => sum + line.$2);
    return [
      Hint(tr('dashboard.holdingResults', {'year': year})),
      for (final (key, amount) in shown)
        Line(
          tr('dashboard.results.$key'),
          signedMoney(amount, cents: false),
          color: amount < Money.zero ? ledger.loss : null,
        ),
      Line(
        tr('dashboard.results.total'),
        signedMoney(total, cents: false),
        color: gainColor(context, total.cents.sign),
        strong: true,
      ),
      if (moving && trend.length >= 2) ...[
        const SizedBox(height: 6),
        Sparkline([
          for (final result in trend) result.cents,
        ], color: ledger.ink),
        Hint(tr('dashboard.results.trend', {'months': trend.length})),
      ],
    ];
  }
}

/// The holding's portfolio, and its companies' shares: what they are worth
/// against what they cost, the year's dividends, the biggest lines and the
/// way to all of them; without shares, the way to the Market tab.
class _Portfolio extends StatelessWidget {
  const _Portfolio({required this.onOpen});

  /// Switches to another tab.
  final OpenTab onOpen;

  /// How many of the biggest holdings it shows.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final view = game.view.stocks;
    if (view == null) return const SizedBox.shrink();
    final gain = view.worth - view.cost;
    final biggest = [...view.holdings]
      ..sort((a, b) => b.value.cents.compareTo(a.value.cents));
    return Section(
      title: tr('stocks.yourPortfolio'),
      children: [
        if (view.holdings.isEmpty) ...[
          Hint(tr('stocks.noHoldings')),
          IndexRow(
            icon: Icons.candlestick_chart_outlined,
            title: tr('dashboard.toMarket'),
            onTap: () => onOpen(HomeTab.market),
          ),
        ] else ...[
          Line(
            tr('stocks.sinceBought'),
            signedMoney(gain, cents: false),
            color: gain.isNegative ? ledger.loss : ledger.gain,
          ),
          Line(tr('stocks.dividendsYear'), money(view.dividends, cents: false)),
          for (final holding in biggest.take(_shown))
            HoldingRow(holding: holding),
          if (view.holdings.length > _shown)
            IndexRow(
              title: tr('stocks.holdings'),
              subtitle: tr('stocks.holdingsCount', {
                'count': view.holdings.length,
              }),
              onTap: () => context.openPage(
                tr('stocks.holdings'),
                (_) => [const PortfolioPage()],
              ),
            ),
        ],
      ],
    );
  }
}

/// All the companies' profit, week by week or month by month, a line away.
class _Profits extends StatelessWidget {
  const _Profits();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final profits = game.holdingProfits(ReportPeriod.week);
    if (profits.length < 2) return const SizedBox.shrink();
    return Section(
      title: tr('common.profit'),
      children: [
        IndexRow(
          title: tr('dashboard.profitPeriods'),
          subtitle: tr('dashboard.allCompanies'),
          value: signedMoney(profits.last.trading, cents: false),
          valueColor: gainColor(context, profits.last.trading.cents.sign),
          onTap: () => context.openPage(
            tr('common.profit'),
            (_) => [const _HoldingProfit()],
          ),
        ),
      ],
    );
  }
}

/// All the companies' profit together, by week or by month.
class _HoldingProfit extends StatefulWidget {
  const _HoldingProfit();

  @override
  State<_HoldingProfit> createState() => _HoldingProfitState();
}

class _HoldingProfitState extends State<_HoldingProfit> {
  ReportPeriod _period = ReportPeriod.week;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final months = game.holdingProfits(ReportPeriod.month);
    final period = months.length > 1 ? _period : ReportPeriod.week;
    final periods = game.holdingProfits(period);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final week = period == ReportPeriod.week;
    final best = periods.fold(
      periods.first.trading,
      (most, p) => p.trading > most ? p.trading : most,
    );
    final worst = periods.fold(
      periods.first.trading,
      (least, p) => p.trading < least ? p.trading : least,
    );
    return Section(
      title: week ? tr('common.profitByWeek') : tr('common.profitByMonth'),
      icon: Icons.bar_chart_rounded,
      trailing: months.length > 1
          ? SegmentedButton<ReportPeriod>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(
                  value: ReportPeriod.week,
                  label: Text(tr('dashboard.weeks')),
                ),
                ButtonSegment(
                  value: ReportPeriod.month,
                  label: Text(tr('dashboard.months')),
                ),
              ],
              selected: {period},
              onSelectionChanged: (next) =>
                  setState(() => _period = next.single),
            )
          : null,
      children: [
        BarChart([for (final p in periods) p.trading.cents]),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                week
                    ? shortDate(periods.first.start)
                    : monthName(periods.first.start),
                style: style,
              ),
            ),
            Flexible(
              child: Text(
                week ? tr('dashboard.weekSoFar') : tr('dashboard.monthSoFar'),
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          ],
        ),
        Line(
          week ? tr('dashboard.bestWorstWeek') : tr('dashboard.bestWorstMonth'),
          '${signedMoney(best)}  ${signedMoney(worst)}',
        ),
        if (game.view.companies.length > 1)
          Hint(tr('dashboard.allCompaniesHint')),
      ],
    );
  }
}

/// The average of the last 7 days of [daily], and how it compares with the
/// 7 days before, if there were any.
(int?, (String, int)?) recentAverage(List<int> daily) {
  if (daily.isEmpty) return (null, null);
  final last = daily.length < 7 ? daily.length : 7;
  final recent = daily.skip(daily.length - last).fold(0, (a, b) => a + b);
  final average = (recent + last ~/ 2) ~/ last;
  if (daily.length < 14) return (average, null);
  final before = daily.skip(daily.length - 14).take(7).fold(0, (a, b) => a + b);
  if (before == 0) return (average, null);
  final change = (recent - before) * 100 ~/ before;
  return (
    average,
    (
      tr('dashboard.onWeekBefore', {
        'change': percentOf('${change >= 0 ? '+' : ''}$change'),
      }),
      change.sign,
    ),
  );
}

/// A new name for the holding.
class _RenameHoldingDialog extends StatefulWidget {
  const _RenameHoldingDialog();

  @override
  State<_RenameHoldingDialog> createState() => _RenameHoldingDialogState();
}

class _RenameHoldingDialogState extends State<_RenameHoldingDialog> {
  late final _name = TextEditingController(
    text: context.game.holdingName ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final name = _name.text.trim();
    return AlertDialog(
      title: Text(tr('dashboard.renameHolding')),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: maxNameLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: tr('newGame.holdingLabel')),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: name.isEmpty
              ? null
              : () {
                  game.submit(RenameHolding(game.player, name: name));
                  Navigator.pop(context);
                },
          child: Text(tr('store.rename')),
        ),
      ],
    );
  }
}
