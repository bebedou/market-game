import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'books.dart';
import 'exchange.dart' show HoldingRow, PortfolioPage;
import 'factory.dart';
import 'finance.dart';
import 'shop.dart';
import 'software.dart';
import 'start.dart';

/// The holding at a glance, the owner's layout A (its name is in the top
/// bar): its net worth, what needs doing, what is being built, its own
/// books (cash, shares, companies, loans), its portfolio, its companies,
/// each opening its own dashboard, its brands, the stores the player runs
/// by hand, the factories, software, the news and profit. Stores under a
/// director are on their company's dashboard; the companies' money and
/// deals are in Finance.
class HoldingScreen extends StatelessWidget {
  const HoldingScreen({super.key, required this.onOpen});

  /// Switches to another tab.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return ListView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        const _Masthead(),
        ..._toDo(context, game, onOpen),
        _BeingBuilt(onOpen: onOpen),
        const _HoldingBooks(),
        _Portfolio(onOpen: onOpen),
        _Companies(onOpen: onOpen),
        const _Brands(),
        _Stores(onOpen: onOpen),
        const FactoriesSection(),
        const SoftwareSection(),
        const _Reading(),
      ],
    );
  }

  /// What needs doing, across the holding or at [only] company.
  static List<Widget> _toDo(
    BuildContext context,
    SimulationController game,
    OpenTab onOpen, {
    CompanyId? only,
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
        if ((only == null || company.id == only) &&
            _belowCushion(game, company))
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
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
  static bool _belowCushion(SimulationController game, CompanyView company) =>
      company.status == CompanyStatus.active &&
      company.stores.any(
        (store) =>
            store.status != StoreStatus.closed &&
            game.delegates(store, ManagerDuty.ordering),
      ) &&
      company.cash - company.committed < game.cushion(company);

  /// "Store name: ", to say where a to-do is once there are several stores.
  static String _at(SimulationController game, StoreView store) =>
      game.myStores.length > 1
      ? tr('common.namePrefix', {'name': game.storeName(store.id)})
      : '';
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

/// The top of the page: what the holding spans, its net worth with this and
/// last week's profit, and net worth over the past weeks or months.
class _Masthead extends StatelessWidget {
  const _Masthead({this.company});

  /// The company whose masthead it is, with its worth; the holding's, with
  /// its net worth, if null.
  final CompanyView? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final view = game.view;
    final company = this.company;
    final weeks = game.holdingProfits(ReportPeriod.week, company: company?.id);
    // Weeks that are over, the running one left out.
    final done = [
      for (final week in weeks)
        if (week.start + 7 <= game.today) week,
    ];
    final recent = done.length > 4 ? done.sublist(done.length - 4) : done;
    final before = done.length >= 8
        ? done.sublist(done.length - 8, done.length - 4)
        : null;
    Money total(List<HoldingPeriod> list) =>
        list.fold(Money.zero, (sum, week) => sum + week.trading);
    final latest = total(recent);
    final earlier = before == null ? null : total(before);
    final change = earlier == null || earlier <= Money.zero
        ? null
        : ((latest - earlier).cents * 100 / earlier.cents).round();
    final bars = done.length > 12 ? done.sublist(done.length - 12) : done;
    final active = view.companies.where(
      (company) => company.status == CompanyStatus.active,
    );
    final trading = [
      for (final (owner, store) in game.myStores)
        if (owner.status == CompanyStatus.active &&
            (company == null || owner.id == company.id) &&
            store.status != StoreStatus.closed)
          store,
    ];
    final cities = {for (final store in trading) store.market};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              if (company == null)
                tr('common.companies', {'count': active.length}),
              tr('common.stores', {'count': trading.length}),
              if (game.content.markets.length > 1)
                tr('common.cities', {'count': cities.length}),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company == null
                          ? tr('common.netWorth')
                          : tr('dashboard.worth'),
                      style: theme.textTheme.labelSmall,
                    ),
                    AnimatedMoney(
                      company == null
                          ? game.netWorth
                          : SimulationController.worthOf(company),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (recent.isNotEmpty)
                _WeekFigure(
                  label: tr('dashboard.lastWeeks', {'count': recent.length}),
                  amount: latest,
                  change: change,
                )
              else if (weeks.lastOrNull case final week?)
                _WeekFigure(
                  label: tr('dashboard.thisWeek', {'count': week.days}),
                  amount: week.trading,
                ),
            ],
          ),
          Text(
            company == null
                ? tr('dashboard.netWorthHint')
                : tr('dashboard.companyWorthHint'),
            style: theme.textTheme.bodySmall,
          ),
          if (bars.length >= 2) ...[
            const SizedBox(height: 8),
            BarChart([for (final week in bars) week.trading.cents], height: 40),
            Text(
              tr('dashboard.tradingWeeks', {'weeks': bars.length}),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Container(height: 2, color: theme.colorScheme.onSurface),
        ],
      ),
    );
  }
}

class _WeekFigure extends StatelessWidget {
  const _WeekFigure({required this.label, required this.amount, this.change});

  final String label;
  final Money amount;

  /// The change on the same span before, in percent, if there is one.
  final int? change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = this.change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            AnimatedMoney(
              amount,
              signed: true,
              colored: true,
              style: theme.textTheme.titleMedium,
            ),
            if (change != null) ...[
              const SizedBox(width: 6),
              Text(
                '${change >= 0 ? '▲' : '▼'} ${percentOf(change.abs())}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: gainColor(context, change.sign),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// How last week went at the store picked, in a few sentences: profit
/// against the week before, what moved it, where shoppers went.
class _LastWeek extends StatelessWidget {
  const _LastWeek();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final weeks = game.reports(ReportPeriod.week);
    final week = weeks[weeks.length - 2];
    final before = weeks.length > 2 ? weeks[weeks.length - 3] : null;
    return Section(
      title: periodName(week),
      children: [
        for (final line in explainChange(game, week, before))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line),
          ),
      ],
    );
  }
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
      ],
    );
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

/// Shoppers and sales across [company]'s stores, and its cash, with how
/// they moved.
class _KeyFigures extends StatelessWidget {
  const _KeyFigures({required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final scheme = Theme.of(context).colorScheme;
    final stores = [
      for (final (owner, store) in game.myStores)
        if (owner.id == company.id) store,
    ];
    final active = [if (company.status == CompanyStatus.active) company];
    final tiles = <Widget>[];
    if (stores.isNotEmpty) {
      final (shoppers, shoppersTrend) = recentAverage(
        _together([for (final store in stores) store.sales.dailyVisits]),
      );
      final (units, unitsTrend) = recentAverage(
        _together([for (final store in stores) store.sales.dailySold]),
      );
      tiles.addAll([
        StatTile(
          icon: Icons.groups_2_outlined,
          label: stores.length == 1
              ? tr('dashboard.shoppersDay')
              : tr('dashboard.shoppersDayAll'),
          value: Text(shoppers == null ? '–' : '$shoppers'),
          trend: shoppersTrend?.$1,
          trendSign: shoppersTrend?.$2 ?? 0,
        ),
        StatTile(
          icon: Icons.shopping_bag_outlined,
          label: stores.length == 1
              ? tr('dashboard.unitsDay')
              : tr('dashboard.unitsDayAll'),
          value: Text(units == null ? '–' : '$units'),
          trend: unitsTrend?.$1,
          trendSign: unitsTrend?.$2 ?? 0,
          color: scheme.tertiary,
        ),
      ]);
    }
    if (active.isNotEmpty) {
      final cash = active.fold(Money.zero, (sum, c) => sum + c.cash);
      final free = active.fold(
        Money.zero,
        (sum, c) => sum + c.cash - c.committed,
      );
      tiles.add(
        StatTile(
          icon: Icons.account_balance_outlined,
          label: active.length == 1
              ? tr('common.companyCash')
              : tr('dashboard.companiesCash'),
          value: AnimatedMoney(cash, cents: false),
          trend: tr('dashboard.free', {'amount': money(free, cents: false)}),
          trendSign: free.cents.sign,
          color: scheme.secondary,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Daily counts of several stores added up, aligned on today.
  static List<int> _together(List<List<int>> daily) {
    final length = daily.fold(
      0,
      (most, d) => d.length > most ? d.length : most,
    );
    return [
      for (var i = 0; i < length; i++)
        daily.fold(0, (sum, d) {
          final index = d.length - length + i;
          return index < 0 ? sum : sum + d[index];
        }),
    ];
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

/// The companies still trading: their stores, who runs them and their cash,
/// a line each that opens the company's dashboard. Then the offer of a
/// director for each that has none, and of another company.
class _Companies extends StatelessWidget {
  const _Companies({required this.onOpen});

  /// Switches to another tab, from a company's dashboard.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final directors = game.content.directors;
    final companies = game.activeCompanies;
    if (companies.isEmpty) return const SizedBox.shrink();
    return Section(
      title: companies.length == 1
          ? tr('common.yourCompany')
          : tr('common.yourCompanies'),
      children: [
        for (final company in companies)
          IndexRow(
            title: game.companyName(company.id),
            subtitle: [
              if (company.software != null)
                tr('software.kind')
              else
                _storeCount(company),
              if (directors != null && company.software == null)
                switch (game.directorOf(company)) {
                  final director? => tr('dashboard.runBy', {
                    'director': aDirector(
                      directors.grades[director.grade.index],
                    ),
                  }),
                  null => tr('common.noDirector'),
                },
            ].join(' · '),
            value: money(company.cash, cents: false),
            onTap: () => openCompanyDashboard(context, company, onOpen),
          ),
        if (directors != null)
          for (final company in companies)
            if (game.directorOf(company) == null && company.software == null)
              IndexRow(
                icon: Icons.badge_outlined,
                title: companies.length == 1
                    ? tr('common.hireDirector')
                    : tr('dashboard.hireDirectorFor', {
                        'company': game.companyName(company.id),
                      }),
                subtitle: tr('dashboard.directorPitch'),
                onTap: () => showDirectorSheet(context, company),
              ),
        IndexRow(
          icon: Icons.add_business_outlined,
          title: tr('common.startSubsidiary'),
          subtitle: tr('dashboard.subsidiaryPitch'),
          onTap: () => openStartBusiness(context, subsidiary: true),
        ),
      ],
    );
  }

  static String _storeCount(CompanyView company) {
    final trading = company.stores
        .where((store) => store.status != StoreStatus.closed)
        .length;
    return tr('common.stores', {'count': trading});
  }
}

/// The player's brands, each for one type of business, and the way to start
/// one.
class _Brands extends StatelessWidget {
  const _Brands();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    return Section(
      title: tr('dashboard.brands'),
      children: [
        for (final brand in game.myBrands)
          IndexRow(
            title: brand.name,
            subtitle:
                '${game.content.formats[brand.format.index].name} · '
                '${tr('common.stores', {'count': brand.shops})}',
            mark: ledger.trade(game.content.formats[brand.format.index]),
            onTap: null,
          ),
        IndexRow(
          icon: Icons.storefront_outlined,
          title: tr('dashboard.createBrand'),
          subtitle: tr('dashboard.createBrandPitch'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                GameScope(controller: game, child: const _CreateBrandDialog()),
          ),
        ),
      ],
    );
  }
}

/// A brand's name and its one type of business.
class _CreateBrandDialog extends StatefulWidget {
  const _CreateBrandDialog();

  @override
  State<_CreateBrandDialog> createState() => _CreateBrandDialogState();
}

class _CreateBrandDialogState extends State<_CreateBrandDialog> {
  final _name = TextEditingController();
  FormatId _format = const FormatId(0);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final name = _name.text.trim();
    final taken = game.view.brands.any(
      (brand) => brand.name.toLowerCase() == name.toLowerCase(),
    );
    return AlertDialog(
      title: Text(tr('dashboard.newBrand')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('dashboard.brandName'),
                errorText: taken ? tr('dashboard.brandTaken') : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              tr('dashboard.brandFormat'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final format in game.content.formats)
                  ChoiceChip(
                    avatar: Icon(formatIcon(format), size: 18),
                    label: Text(format.name),
                    selected: format.id == _format,
                    onSelected: (_) => setState(() => _format = format.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Hint(tr('dashboard.brandHint')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: name.isEmpty || taken
              ? null
              : () {
                  game.createBrand(name, _format);
                  Navigator.pop(context);
                },
          child: Text(tr('dashboard.createBrandButton')),
        ),
      ],
    );
  }
}

/// The stores the player runs by hand, those of companies without a
/// director, by company once there are several, a line each that opens it,
/// and the way to start another business; or, for [company]'s dashboard,
/// all of its stores.
class _Stores extends StatelessWidget {
  const _Stores({required this.onOpen, this.company});

  final OpenTab onOpen;
  final CompanyView? company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final only = company;
    // A director runs their company's stores: they are on its dashboard.
    bool shown(CompanyView owner) =>
        only == null ? game.directorOf(owner) == null : owner.id == only.id;
    final stores = [
      for (final entry in game.myStores)
        if (shown(entry.$1)) entry,
    ];
    final companies = [
      for (final company in game.view.companies)
        if (company.stores.isNotEmpty && shown(company)) company,
    ];
    final elsewhere = only == null && stores.length < game.myStores.length;
    if (only != null && stores.isEmpty) return const SizedBox.shrink();
    return Section(
      title: stores.length == 1
          ? tr('dashboard.yourStore')
          : tr('common.yourStores'),
      children: [
        for (final company in companies) ...[
          if (companies.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      game.companyName(company.id),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (company.status != CompanyStatus.active)
                    Pill(
                      tr('common.liquidated'),
                      color: theme.colorScheme.error,
                    )
                  else
                    Text(
                      tr('dashboard.cashLine', {
                        'amount': money(company.cash, cents: false),
                      }),
                      style: figures(theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          for (final (owner, store) in stores)
            if (owner.id == company.id)
              _StoreEntry(
                company: company,
                store: store,
                onTap: () {
                  game.selectStore(store.id);
                  onOpen(HomeTab.shop, part: ShopPart.shelves);
                },
              ),
        ],
        if (elsewhere) Hint(tr('dashboard.directorStoresHint')),
        if (only == null)
          IndexRow(
            icon: Icons.add,
            title: tr('common.startBusiness'),
            subtitle: tr('dashboard.startBusinessPitch'),
            onTap: () => openStartBusiness(context),
          ),
      ],
    );
  }
}

/// One of the player's stores on a line: its kind and place, shoppers,
/// this week's sales, and the worst of its troubles, stamped.
class _StoreEntry extends StatelessWidget {
  const _StoreEntry({
    required this.company,
    required this.store,
    required this.onTap,
  });

  final CompanyView company;
  final StoreView store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final week = game
        .reports(ReportPeriod.week, company: company.id)
        .lastOrNull
        ?.store(store.id);
    var sales = Money.zero;
    if (week != null) {
      for (final product in content.products) {
        sales += week.revenue(product.id);
      }
    }
    final (shoppers, _) = recentAverage(store.sales.dailyVisits);
    final (sold, _) = recentAverage(store.sales.dailySold);
    final listed = [
      for (final product in content.products)
        if (store.prices[product.id.index] != null) product.id.index,
    ];
    final stock = store.stock.fold(0, (sum, units) => sum + units);
    final coming = store.onOrder.fold(0, (sum, units) => sum + units);
    final cover = sold == null || sold == 0 ? null : (stock + coming) ~/ sold;
    final soldOut = listed.where((i) => store.stock[i] == 0).length;
    final open = store.status == StoreStatus.open;
    final trouble = [
      if (store.status == StoreStatus.closed) tr('common.closed'),
      if (open &&
          game.staffOf(store).every((staff) => staff == 0) &&
          !game.delegates(store, ManagerDuty.staffing))
        tr('dashboard.stampNoStaff'),
      if (open && listed.isNotEmpty && stock == 0) tr('dashboard.stampEmpty'),
      if (open && soldOut > 0 && soldOut < listed.length)
        tr('dashboard.stampSoldOut', {'count': soldOut}),
      if (open && cover != null && cover < 3)
        tr('common.daysOfStock', {'cover': cover}),
    ];
    final format = content.formats[store.format.index];
    return IndexRow(
      mark: Ledger.of(context).trade(format),
      title: game.storeName(store.id),
      subtitle: [
        format.name,
        if (content.markets.length > 1)
          content.markets[store.market.index].name,
        if (store.status == StoreStatus.building)
          tr('common.opensOn', {'date': shortDate(store.opensOn)})
        else if (shoppers != null)
          tr('dashboard.shoppersLine', {'shoppers': shoppers}),
        if (store.manager case final manager?)
          managerOf(content.managers.grades[manager.grade.index]),
        if (store.works != null) tr('dashboard.worksUnderWay'),
      ].join(' · '),
      stamp: trouble.firstOrNull,
      value: store.status == StoreStatus.building
          ? null
          : money(sales, cents: false),
      onTap: onTap,
    );
  }
}

/// What the holding is building: its stores being fitted out and its
/// factories under construction, with the day each opens, a line each that
/// opens it. Nothing while nothing is.
class _BeingBuilt extends StatelessWidget {
  const _BeingBuilt({required this.onOpen});

  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final ledger = Ledger.of(context);
    final stores = [
      for (final (company, store) in game.myStores)
        if (store.status == StoreStatus.building) (company, store),
    ];
    final factories = [
      for (final (company, factory) in game.myFactories)
        if (factory.building) (company, factory),
    ];
    if (stores.isEmpty && factories.isEmpty) return const SizedBox.shrink();
    return Section(
      title: tr('dashboard.beingBuilt'),
      children: [
        for (final (company, store) in stores)
          IndexRow(
            mark: ledger.trade(content.formats[store.format.index]),
            title: game.storeName(store.id),
            subtitle: [
              tr('common.opensOn', {'date': shortDate(store.opensOn)}),
              game.companyName(company.id),
            ].join(' · '),
            onTap: () {
              game.selectStore(store.id);
              onOpen(HomeTab.shop, part: ShopPart.running);
            },
          ),
        for (final (company, factory) in factories)
          IndexRow(
            mark: ledger.works,
            title: factory.name,
            subtitle: [
              tr('common.opensOn', {'date': shortDate(factory.opensOn)}),
              game.companyName(company.id),
            ].join(' · '),
            onTap: () => openFactoryPage(context, factory),
          ),
      ],
    );
  }
}

/// Opens [company]'s dashboard within the current tab.
void openCompanyDashboard(
  BuildContext context,
  CompanyView company,
  OpenTab onOpen,
) => context.openPage(
  context.game.companyName(company.id),
  (_) => [CompanyDashboard(id: company.id, onOpen: onOpen)],
);

/// A company at a glance, as the holding is: its worth and its weeks, what
/// needs doing there, who runs it, how its stores are doing, its stores and
/// factories, its software, and the way to its money in Finance.
class CompanyDashboard extends StatelessWidget {
  const CompanyDashboard({super.key, required this.id, required this.onOpen});

  final CompanyId id;

  /// Switches to another tab.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.view.companies
        .where((company) => company.id == id)
        .firstOrNull;
    if (company == null) return Hint(tr('finance.noCompany'));
    final active = company.status == CompanyStatus.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Masthead(company: company),
        ...HoldingScreen._toDo(context, game, onOpen, only: id),
        if (game.content.directors != null &&
            active &&
            company.software == null)
          DirectorSection(company: company),
        if (company.software == null) _KeyFigures(company: company),
        _Stores(onOpen: onOpen, company: company),
        FactoriesSection(company: id),
        if (company.software case final software?)
          Section(
            title: tr('software.yourOne'),
            children: [
              IndexRow(
                mark: Ledger.of(context).software,
                title: software.name,
                subtitle: softwareStatus(software),
                value: software.running
                    ? compactMoney(software.yourWorth)
                    : null,
                onTap: () => openSoftwarePage(context, software),
              ),
            ],
          ),
        Section(
          title: tr('dashboard.companyMoney'),
          children: [
            IndexRow(
              title: tr('dashboard.companyMoneyLine'),
              subtitle: tr('dashboard.inFinance'),
              value: money(company.cash, cents: false),
              onTap: () => openCompanyPage(context, company),
            ),
          ],
        ),
      ],
    );
  }
}

/// What there is to read: how last week went, the news, and profit over
/// time, each a page.
class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final weeks = game.reports(ReportPeriod.week);
    final profits = game.holdingProfits(ReportPeriod.week);
    final story = weeks.length > 1
        ? explainChange(
            game,
            weeks[weeks.length - 2],
            weeks.length > 2 ? weeks[weeks.length - 3] : null,
          )
        : null;
    final latest = game.alerts.firstOrNull;
    return Section(
      title: tr('dashboard.toRead'),
      children: [
        if (story != null)
          IndexRow(
            title: periodName(weeks[weeks.length - 2]),
            subtitle: story.first,
            onTap: () => context.openPage(
              tr('dashboard.lastWeek'),
              (_) => [const _LastWeek()],
            ),
          ),
        IndexRow(
          title: tr('common.news'),
          subtitle: latest == null ? tr('dashboard.pressPlay') : latest.message,
          value: game.alerts.isEmpty ? null : '${game.alerts.length}',
          onTap: () => context.openPage(
            tr('common.news'),
            (context) => [_News(game: context.game)],
          ),
        ),
        if (profits.length > 1)
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
