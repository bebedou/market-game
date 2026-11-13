import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../letters.dart';
import '../loans.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'financials.dart';
import 'market.dart';
import 'store.dart';

/// Money and deals: each company's accounts, borrowing and paying
/// yourself, the taxes, rival stores going cheap, and the player's stores
/// for sale.
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final companies = view.companies;
    final active = game.activeCompanies;
    final selling = game.content.acquisitions != null;
    final cash = active.fold(Money.zero, (sum, c) => sum + c.cash);
    final free = active.fold(
      Money.zero,
      (sum, c) => sum + c.cash - c.committed,
    );
    final owed = active.fold(
      Money.zero,
      (sum, c) => sum - c.balance(AccountKind.loans),
    );
    final cheap = _struggling(game);
    final stores = [
      for (final (company, store) in game.myStores)
        if (company.status == CompanyStatus.active &&
            store.status != StoreStatus.closed)
          store,
    ];
    final wanted = stores.where((store) => store.buyer != null).length;
    return ListView(
      key: const PageStorageKey('finance'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Section(
          title: tr('finance.money'),
          children: [
            if (active.isNotEmpty) ...[
              Line(
                active.length == 1
                    ? tr('common.companyCash')
                    : tr('finance.yourCompaniesCash'),
                money(cash),
                strong: true,
              ),
              Line(
                tr('finance.freeToSpend'),
                money(free),
                hint: tr('finance.lessBills'),
                color: gainColor(context, free.cents.sign),
              ),
              if (owed > Money.zero) Line(tr('finance.owedBank'), money(owed)),
            ],
            Line(tr('common.ownCash'), money(view.cash)),
            if (companies.isEmpty) Hint(tr('finance.noCompany')),
          ],
        ),
        if (companies.isNotEmpty)
          Section(
            title: companies.length == 1
                ? tr('common.yourCompany')
                : tr('common.yourCompanies'),
            children: [
              if (companies.length > 1)
                IndexRow(
                  title: tr('common.allCompanies'),
                  subtitle: tr('finance.allPitch'),
                  onTap: () => openHoldingFinancials(context),
                ),
              for (final company in [
                ...companies.where((c) => c.status == CompanyStatus.active),
                ...companies.where((c) => c.status != CompanyStatus.active),
              ])
                IndexRow(
                  title: game.companyName(company.id),
                  subtitle: company.status != CompanyStatus.active
                      ? tr('common.liquidated')
                      : [
                          tr('finance.profitKept', {
                            'amount': signedMoney(
                              company.retainedEarnings,
                              cents: false,
                            ),
                          }),
                          if (company.loans.isNotEmpty)
                            tr('finance.loansCount', {
                              'count': company.loans.length,
                            }),
                          if (game.content.directors != null)
                            company.director != null
                                ? tr('finance.runByDirector')
                                : tr('common.noDirector'),
                          tr('finance.companyPitch'),
                        ].join(' · '),
                  value: money(company.cash, cents: false),
                  onTap: () => openCompanyPage(context, company),
                ),
            ],
          ),
        Section(
          title: tr('finance.taxesDeals'),
          children: [
            if (game.content.taxesOf(game.countryOfCompany(game.company)) !=
                    null &&
                game.company != null)
              IndexRow(
                title: tr('finance.taxes'),
                subtitle: tr('finance.dueNextJanuary'),
                value: money(_yearSoFar(game).due, cents: false),
                onTap: () => context.openPage(
                  tr('finance.taxes'),
                  (_) => [const _Taxes()],
                ),
              ),
            if (selling) ...[
              IndexRow(
                title: tr('finance.goingCheap'),
                subtitle: cheap.isEmpty
                    ? tr('finance.noRivalLosing')
                    : tr('finance.cheapSummary', {'count': cheap.length}),
                value: cheap.isEmpty
                    ? null
                    : money(cheap.first.$2.price, cents: false),
                onTap: () => context.openPage(
                  tr('finance.goingCheap'),
                  (_) => [const _Bargains()],
                ),
              ),
              if (stores.isNotEmpty)
                IndexRow(
                  title: stores.length == 1
                      ? tr('finance.sellYourStore')
                      : tr('finance.sellAStore'),
                  subtitle: wanted == 0
                      ? tr(
                          stores.length == 1
                              ? 'finance.noChainIt'
                              : 'finance.noChainThem',
                        )
                      : stores.length == 1
                      ? tr('finance.chainWouldBuy')
                      : tr('finance.storesWithBuyer', {'wanted': wanted}),
                  onTap: () => context.openPage(
                    tr('finance.selling'),
                    (context) => [
                      for (final (company, store) in context.game.myStores)
                        if (company.status == CompanyStatus.active &&
                            store.status != StoreStatus.closed)
                          SaleSection(store: store),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Opens [company]'s page: who runs it, its financials and accounts, and what
/// its directors wrote.
void openCompanyPage(BuildContext context, CompanyView company) =>
    context.openPage(
      context.game.companyName(company.id),
      (context) => [
        for (final current in context.game.view.companies)
          if (current.id == company.id) ...[
            if (context.game.content.directors != null &&
                current.status == CompanyStatus.active)
              _DirectorSection(company: current),
            FinancialsSection(company: current.id),
            _CompanyCard(company: current),
            if (current.memos.isNotEmpty) _Letters(company: current),
          ],
      ],
    );

/// Opens the sheet that hires [company]'s director or changes their brief.
void showDirectorSheet(BuildContext context, CompanyView company) {
  final game = context.game;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GameScope(
      controller: game,
      child: _DirectorSheet(company: company),
    ),
  );
}

/// Rival stores losing money, a month or more after opening, cheapest
/// first, with their asking prices.
List<(ShelfView, Valuation)> _struggling(SimulationController game) {
  final view = game.view;
  final mine = {for (final company in view.companies) company.id};
  return [
    for (final shelf in view.shelves)
      if (shelf.status != StoreStatus.closed && !mine.contains(shelf.company))
        if (view.valuations[shelf.id.index] case final value?
            when value.earnings.isNegative &&
                game.today.number - shelf.opensOn.number >= salesHistoryDays)
          (shelf, value),
  ]..sort((a, b) => a.$2.price.cents.compareTo(b.$2.price.cents));
}

/// The company's profit so far this year, before the tax billed on last
/// year, and the tax due on it if the year ended today.
({Money profit, Money due}) _yearSoFar(SimulationController game) {
  final company = game.company;
  final country = game.countryOfCompany(company);
  final taxes = game.content.taxesOf(country)!;
  final year = game.today.date.year;
  var profit = Money.zero;
  if (company != null) {
    for (final month in game.reports(ReportPeriod.month, company: company.id)) {
      if (month.start.date.year != year) continue;
      profit += month.profit + month.flow(AccountKind.taxes);
    }
  }
  final carried = company?.lossCarried ?? Money.zero;
  return (
    profit: profit,
    // Each country takes its part where the company trades in several.
    due: company != null && company.countryTaxes.isNotEmpty
        ? company.taxAccrued
        : taxes.corporateTax(
            profit - carried,
            game.view.economy(country).priceIndex,
          ),
  );
}

/// Rival stores losing money, cheapest first: what turning one round
/// would cost.
class _Bargains extends StatelessWidget {
  const _Bargains();

  /// The most listed.
  static const shown = 12;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final struggling = _struggling(game);
    return Section(
      title: tr('finance.goingCheap'),
      children: [
        Hint(
          struggling.isEmpty
              ? tr('finance.bargainsNone')
              : tr('finance.bargainsSome'),
        ),
        for (final (shelf, value) in struggling.take(shown))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ledger.rule, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                TradeMark(ledger.trade(content.formats[shelf.format.index])),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shelf.name, overflow: TextOverflow.ellipsis),
                      Text(
                        [
                          content.formats[shelf.format.index].name,
                          if (content.markets.length > 1)
                            content.markets[shelf.market.index].name,
                          tr('finance.losesYear', {
                            'amount': money(-value.earnings, cents: false),
                          }),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  money(value.price, cents: false),
                  style: figures(theme.textTheme.bodyMedium),
                ),
                if (game.pending.any(
                  (c) => c is BuyStore && c.store == shelf.id,
                ))
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(tr('finance.tomorrow')),
                  )
                else
                  TextButton(
                    onPressed: game.activeCompanies.isEmpty
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                BuyStoreDialog(game: game, shelf: shelf),
                          ),
                    child: Text(tr('common.buy')),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final active = company.status == CompanyStatus.active;
    return Section(
      title: game.companyName(company.id),
      icon: Icons.account_balance_outlined,
      trailing: active
          ? null
          : Pill(
              tr('common.liquidated'),
              color: Theme.of(context).colorScheme.error,
            ),
      children: [
        Line(tr('common.cash'), money(company.cash), strong: true),
        Line(
          tr('finance.spokenFor'),
          money(company.committed),
          hint: tr('finance.billsOnWay'),
        ),
        Line(
          tr('common.freeCash'),
          money(company.cash - company.committed),
          color: gainColor(
            context,
            (company.cash - company.committed).cents.sign,
          ),
        ),
        if (active)
          Row(
            children: [
              Expanded(
                child: Line(
                  tr('finance.cushion'),
                  money(game.cushion(company)),
                  hint: tr('finance.cushionHint', {
                    'length': cushionLength(game.cushionDays(company)),
                  }),
                ),
              ),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => GameScope(
                    controller: game,
                    child: _CushionSheet(company: company),
                  ),
                ),
                child: Text(tr('finance.change')),
              ),
            ],
          ),
        Line(
          tr('finance.profitKeptFounding'),
          signedMoney(company.retainedEarnings),
          hint: tr('finance.dividendsFromThis'),
        ),
        if (active) _BankLine(company: company),
        if (company.loans.isNotEmpty) ...[
          const Divider(),
          for (final loan in company.loans)
            Row(
              children: [
                Expanded(
                  child: Line(
                    tr('finance.loanNumber', {'number': loan.number}),
                    money(loan.outstanding),
                    hint: tr(
                      loan.guaranteed
                          ? 'finance.loanTermsGuaranteed'
                          : 'finance.loanTerms',
                      {
                        'rate': percent(loan.rate),
                        'left': loan.installmentsLeft,
                      },
                    ),
                  ),
                ),
                if (active)
                  TextButton(
                    onPressed: () => _repay(context, game, loan),
                    child: Text(tr('finance.repay')),
                  ),
              ],
            ),
        ],
        if (active) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add_card, size: 18),
                onPressed: () => _inject(context, game),
                label: Text(tr('finance.addCapital')),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.savings_outlined, size: 18),
                onPressed: () => _dividend(context, game),
                label: Text(tr('finance.payDividend')),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_balance, size: 18),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => GameScope(
                    controller: game,
                    child: _BorrowSheet(company: company),
                  ),
                ),
                label: Text(tr('finance.borrow')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _inject(BuildContext context, SimulationController game) async {
    final amount = await askAmount(
      context,
      title: tr('finance.addCapital'),
      message: tr('finance.addCapitalBody', {'cash': money(game.view.cash)}),
      action: tr('finance.add'),
    );
    if (amount != null) {
      game.submit(
        InjectCapital(game.player, company: company.id, amount: amount),
      );
    }
  }

  Future<void> _dividend(
    BuildContext context,
    SimulationController game,
  ) async {
    final amount = await askAmount(
      context,
      title: tr('finance.payADividend'),
      message: tr('finance.dividendBody', {
        'kept': money(company.retainedEarnings),
        'tax': switch (game.content.taxesOf(game.residence)) {
          final taxes? => tr('finance.dividendTax', {
            'rate': percent(taxes.dividendRate, decimals: 0),
          }),
          null => '',
        },
      }),
      action: tr('finance.pay'),
    );
    if (amount != null) {
      game.submit(
        PayDividend(game.player, company: company.id, amount: amount),
      );
    }
  }

  Future<void> _repay(
    BuildContext context,
    SimulationController game,
    LoanView loan,
  ) async {
    final amount = await askAmount(
      context,
      title: tr('finance.repayLoan', {'number': loan.number}),
      message: tr('finance.repayBody', {'left': money(loan.outstanding)}),
      initial: loan.outstanding,
      action: tr('finance.repay'),
    );
    if (amount != null) {
      game.submit(RepayLoan(game.player, loan: loan.number, amount: amount));
    }
  }
}

/// Who runs the company: its director and their brief, or the offer of one.
class _DirectorSection extends StatelessWidget {
  const _DirectorSection({required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final director = game.directorOf(company);
    void brief() => showDirectorSheet(context, company);
    if (director == null) {
      return Section(
        title: tr('finance.director'),
        icon: Icons.badge_outlined,
        children: [
          Hint(tr('finance.directorPitch')),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: brief,
              child: Text(tr('common.hireDirector')),
            ),
          ),
        ],
      );
    }
    final grade = content.directors!.grades[director.grade.index];
    final monthly = directorSalary(
      game.view,
      content,
      company,
      director,
    ).timesInt(30);
    return Section(
      title: tr('finance.director'),
      icon: Icons.badge_outlined,
      children: [
        Line(
          grade.name,
          tr('common.perMonth', {'amount': money(monthly, cents: false)}),
          hint: tr('finance.since', {
            'date': shortDate(director.hiredOn),
            'year': director.hiredOn.date.year,
          }),
        ),
        Hint(
          tr('finance.directorBrief', {
            'growth': director.growth == Growth.none
                ? tr('finance.keepsStores')
                : tr('finance.growsBy', {'how': growthName(director.growth)}),
            'borrows': director.borrows ? tr('finance.borrowingShort') : '',
            'profit': tr(
              director.payout ? 'finance.sendsProfit' : 'finance.keepsProfit',
            ),
            'managers': managersOf(
              content.managers.grades[director.managerGrade.index],
            ),
            'strategy': content.strategies[director.strategy.index].name
                .toLowerCase(),
          }),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: brief,
              child: Text(tr('common.changeBrief')),
            ),
            TextButton(
              onPressed: () =>
                  game.submit(FireDirector(game.player, company: company.id)),
              child: Text(tr('common.letGo')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Picks a director's grade and brief, for hiring or a new brief.
class _DirectorSheet extends StatefulWidget {
  const _DirectorSheet({required this.company});

  final CompanyView company;

  @override
  State<_DirectorSheet> createState() => _DirectorSheetState();
}

class _DirectorSheetState extends State<_DirectorSheet> {
  DirectorGradeId? _grade;
  Growth? _growth;
  bool? _payout;
  bool? _borrows;
  ManagerGradeId? _managerGrade;
  StrategyId? _strategy;
  int? _pace;
  Set<String>? _regions;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final current = game.directorOf(widget.company);
    final grades = content.directors!.grades;
    final grade = _grade ?? current?.grade ?? grades[grades.length ~/ 2].id;
    final growth = _growth ?? current?.growth ?? Growth.invest;
    final payout = _payout ?? current?.payout ?? true;
    // Borrowing is for growing.
    final borrows =
        growth != Growth.none && (_borrows ?? current?.borrows ?? false);
    final managers = content.managers.grades;
    final managerGrade =
        _managerGrade ??
        current?.managerGrade ??
        managers[managers.length ~/ 2].id;
    // Strategies that run the kinds of business the company has.
    final channels = {
      for (final store in widget.company.stores)
        if (store.status != StoreStatus.closed)
          content.formatChannels[store.format.index],
    };
    final fitting = [
      for (final option in content.strategies)
        if (channels.contains(content.formatChannels[option.format.index]))
          option,
    ];
    final strategies = fitting.isEmpty ? content.strategies : fitting;
    final strategy =
        _strategy ??
        current?.strategy ??
        strategies
            .firstWhere(
              (s) => s.marketPosition == Fx.zero,
              orElse: () => strategies.first,
            )
            .id;
    final wageIndex = game.view
        .economy(game.countryOfCompany(widget.company))
        .wageIndex;
    // Shops run by formula across the countries the company trades in, for
    // a kind of shop that can be run so.
    final national = content
        .formats[content.strategies[strategy.index].format.index]
        .national;
    final homes = {
      for (final store in widget.company.stores)
        if (store.status != StoreStatus.closed) content.countryOf(store.market),
    };
    final countries = [
      for (final country in game.view.national)
        if (country.country != null &&
            country.def.regions.isNotEmpty &&
            (homes.contains(country.country) ||
                country.blocks.any((b) => b.company == widget.company.id)))
          country,
    ];
    final nationally =
        national != null &&
        countries.isNotEmpty &&
        (growth == Growth.open || growth == Growth.buy);
    final pace = _pace ?? current?.nationalPace ?? 0;
    final picked = _regions ?? {...?current?.nationalRegions};
    // This year's shops run by formula: opened and closed, their fitting
    // out and what they earned.
    final year = game.today.date.year;
    var opened = 0;
    var closed = 0;
    var earned = Money.zero;
    var hasBlocks = false;
    for (final country in countries) {
      for (final block in country.blocks) {
        if (block.company != widget.company.id) continue;
        hasBlocks = true;
        for (final month in block.months) {
          if (month.start.date.year != year) continue;
          opened += month.opened;
          closed += month.closed;
          earned += month.profit;
        }
      }
    }
    var fittingOut = Money.zero;
    for (final memo in widget.company.memos) {
      if (memo is NationalOpened && memo.day.date.year == year) {
        fittingOut += memo.cost;
      }
    }
    Money monthly(DirectorGradeDef option) =>
        option.salary.times(wageIndex).timesInt(30);
    Widget choice({
      required bool selected,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      onTap: onTap,
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Text(
                  current == null
                      ? tr('common.hireDirector')
                      : tr('finance.briefDirector'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  tr('finance.runsFor', {
                    'company': game.companyName(widget.company.id),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(tr('common.who'), style: theme.textTheme.titleSmall),
                for (final option in grades)
                  choice(
                    selected: option.id == grade,
                    title: tr('finance.gradeLine', {
                      'grade': option.name,
                      'salary': money(monthly(option), cents: false),
                    }),
                    subtitle: tr('finance.gradeHint', {
                      'cuts': percent(
                        Fx.one - content.directors!.kept(option.id),
                        decimals: 0,
                      ),
                      'error': percent(
                        content.directors!.judgmentError *
                            (Fx.one - option.skill),
                        decimals: 0,
                      ),
                    }),
                    onTap: () => setState(() => _grade = option.id),
                  ),
                const SizedBox(height: 8),
                Text(tr('finance.howFar'), style: theme.textTheme.titleSmall),
                for (final option in Growth.values)
                  choice(
                    selected: option == growth,
                    title: switch (option) {
                      Growth.none => tr('finance.growth.none'),
                      Growth.invest => tr('finance.growth.invest'),
                      Growth.open => tr('finance.growth.open'),
                      Growth.buy => tr('finance.growth.buy'),
                    },
                    subtitle: switch (option) {
                      Growth.none => tr('finance.growthHints.none'),
                      Growth.invest => tr('finance.growthHints.invest'),
                      Growth.open => tr('finance.growthHints.open'),
                      Growth.buy => tr('finance.growthHints.buy'),
                    },
                    onTap: () => setState(() => _growth = option),
                  ),
                if (growth != Growth.none) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr('finance.payingForIt'),
                    style: theme.textTheme.titleSmall,
                  ),
                  choice(
                    selected: !borrows,
                    title: tr('finance.onlyEarnings'),
                    onTap: () => setState(() => _borrows = false),
                  ),
                  choice(
                    selected: borrows,
                    title: tr('finance.borrowShort'),
                    subtitle: growth == Growth.buy
                        ? tr('finance.onEarningsBuy', {
                            'years': buyoutPaybackMonths ~/ 12,
                          })
                        : tr('finance.onEarnings'),
                    onTap: () => setState(() => _borrows = true),
                  ),
                ],
                if (nationally) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr('finance.acrossCountry'),
                    style: theme.textTheme.titleSmall,
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(tr('finance.nationalPace'))),
                      CountStepper(
                        value: pace,
                        max: maxNationalPace,
                        label: pace == 0 ? tr('finance.nationalOff') : null,
                        onChanged: (value) => setState(() => _pace = value),
                      ),
                    ],
                  ),
                  Hint(
                    tr('finance.nationalPaceHint', {
                      'cost': money(
                        national.fitOut.times(countries.first.priceIndex),
                        cents: false,
                      ),
                    }),
                  ),
                  if (pace > 0) ...[
                    for (final country in countries) ...[
                      if (countries.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            content.countries[country.country!.index].name,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final region in country.def.regions)
                            FilterChip(
                              label: Text(region.name),
                              selected: picked.contains(region.key),
                              onSelected: (on) => setState(
                                () => _regions = on
                                    ? ({...picked, region.key})
                                    : ({...picked}..remove(region.key)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    Hint(
                      picked.isEmpty
                          ? tr('finance.nationalAnywhere')
                          : tr('finance.nationalOnly', {
                              'count': picked.length,
                            }),
                    ),
                  ],
                  if (hasBlocks) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr('finance.nationalThisYear'),
                      style: theme.textTheme.labelSmall,
                    ),
                    Line(
                      tr('market.openedThisYear'),
                      tr('market.openedAndClosed', {
                        'opened': opened,
                        'closed': closed,
                      }),
                    ),
                    Line(
                      tr('finance.fittingOut'),
                      money(Money.zero - fittingOut, cents: false),
                    ),
                    Line(
                      tr('finance.earnedByThem'),
                      signedMoney(earned, cents: false),
                      color: gainColor(context, earned.cents.sign),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Text(
                  tr('finance.theProfit'),
                  style: theme.textTheme.titleSmall,
                ),
                choice(
                  selected: !payout,
                  title: tr('finance.keepInCompany'),
                  onTap: () => setState(() => _payout = false),
                ),
                choice(
                  selected: payout,
                  title: tr('finance.sendMe'),
                  subtitle: tr('finance.sendMeHint'),
                  onTap: () => setState(() => _payout = true),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('finance.managersHire'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final option in managers)
                      ChoiceChip(
                        label: Text(
                          tr('store.gradeLine', {
                            'grade': option.name,
                            'salary': money(option.salary.times(wageIndex)),
                          }),
                        ),
                        selected: option.id == managerGrade,
                        onSelected: (_) =>
                            setState(() => _managerGrade = option.id),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final option in strategies)
                      ChoiceChip(
                        label: Text(option.name),
                        selected: option.id == strategy,
                        onSelected: (_) =>
                            setState(() => _strategy = option.id),
                      ),
                  ],
                ),
                if (stanceAdvice(content.strategies[strategy.index])
                    case final advice?)
                  Hint(advice),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: () {
                game.submit(
                  HireDirector(
                    game.player,
                    company: widget.company.id,
                    grade: grade,
                    strategy: strategy,
                    managerGrade: managerGrade,
                    growth: growth,
                    payout: payout,
                    borrows: borrows,
                    nationalPace: nationally ? pace : 0,
                    nationalRegions: [
                      if (nationally && pace > 0)
                        for (final country in countries)
                          for (final region in country.def.regions)
                            if (picked.contains(region.key)) region.key,
                    ],
                  ),
                );
                Navigator.pop(context);
              },
              child: Text(
                current == null
                    ? tr('finance.hireFor', {
                        'amount': money(
                          monthly(grades[grade.index]),
                          cents: false,
                        ),
                      })
                    : current.grade == grade
                    ? tr('common.updateBrief')
                    : tr('finance.replaceDirector'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The director's monthly letters, newest first: the latest two, or [all].
class _Letters extends StatelessWidget {
  const _Letters({required this.company, this.all = false});

  final CompanyView company;
  final bool all;

  static const _shown = 2;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final letters = directorLetters(
      company,
      game.reports(ReportPeriod.month, company: company.id),
      game.content,
      game.view,
    );
    return Section(
      title: tr('finance.letters'),
      icon: Icons.mail_outline,
      children: [
        for (final letter in all ? letters : letters.take(_shown))
          _LetterCard(letter: letter),
        if (!all && letters.length > _shown)
          IndexRow(
            title: tr('finance.earlierLetters'),
            subtitle: tr('finance.nMore', {'count': letters.length - _shown}),
            onTap: () => context.openPage(
              tr('finance.letters'),
              (context) => [
                for (final current in context.game.view.companies)
                  if (current.id == company.id)
                    _Letters(company: current, all: true),
              ],
            ),
          ),
      ],
    );
  }
}

/// One letter, on a slightly darker paper, in the serif of the ledger.
class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.letter});

  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(fontFamily: titleFont);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ledger.shade,
        border: Border.all(color: ledger.rule, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(monthName(letter.month), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final paragraph in letter.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(paragraph, style: text),
            ),
          Text(
            tr('finance.yourDirector'),
            style: text?.copyWith(
              fontStyle: FontStyle.italic,
              color: ledger.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BorrowSheet extends StatefulWidget {
  const _BorrowSheet({required this.company});

  final CompanyView company;

  @override
  State<_BorrowSheet> createState() => _BorrowSheetState();
}

class _BorrowSheetState extends State<_BorrowSheet> {
  final _amount = TextEditingController(text: moneyInput(Money.parse('5000')));
  late int _months = longestTerm(context.game.content);

  /// Whether the player guarantees it: by default, when the company's
  /// earnings carry nothing more.
  bool? _guarantee;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final view = game.view;
    final room = view.companyCredits[widget.company.id.index] ?? Money.zero;
    final credit = room.isNegative ? Money.zero : room;
    final guarantee = _guarantee ?? credit == Money.zero;
    final limit = guarantee ? view.guaranteeRoom : credit;
    final rate = lendingRate(
      content,
      view.macro.policyRate,
      view.today,
      guaranteed: guarantee,
      lastBankruptcy: view.lastBankruptcy,
    );
    final amount = parseMoney(_amount.text);
    final tooMuch = amount != null && amount > limit;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('finance.borrowFromBank'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('finance.amount'),
              helperText: tr('finance.bankLendsUpTo', {'amount': money(limit)}),
              errorText: amount == null
                  ? tr('common.notAnAmount')
                  : tooMuch
                  ? tr('finance.moreThanBank', {'amount': money(limit)})
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final option in loanTerms)
                if (option <= content.finance.maxTermMonths)
                  ChoiceChip(
                    label: Text(termName(option)),
                    selected: option == _months,
                    onSelected: (_) => setState(() => _months = option),
                  ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('finance.guaranteePersonally')),
            subtitle: Text(
              guarantee
                  ? tr('finance.guaranteeOn', {
                      'amount': money(view.guaranteeRoom, cents: false),
                    })
                  : tr('finance.guaranteeOff', {
                      'years': earningsYears(content),
                      'amount': money(credit, cents: false),
                    }),
            ),
            value: guarantee,
            onChanged: (on) => setState(() => _guarantee = on),
          ),
          Line(
            tr('common.perYear', {'amount': percent(rate)}),
            tr('common.perMonth', {
              'amount': money(
                firstPayment(amount ?? Money.zero, rate, _months),
                cents: false,
              ),
            }),
            hint: tr('finance.firstPaymentHint'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: amount == null || amount <= Money.zero || tooMuch
                ? null
                : () {
                    game.submit(
                      TakeLoan(
                        game.player,
                        company: widget.company.id,
                        amount: amount,
                        termMonths: _months,
                        guarantee: guarantee,
                      ),
                    );
                    Navigator.pop(context);
                  },
            child: Text(tr('finance.askBank')),
          ),
        ],
      ),
    );
  }
}

/// What the bank would still lend [company]: on its stores' earnings, and on
/// the player's guarantee.
class _BankLine extends StatelessWidget {
  const _BankLine({required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final room = view.companyCredits[company.id.index] ?? Money.zero;
    final credit = room.isNegative ? Money.zero : room;
    final guarantee = view.guaranteeRoom;
    final years = earningsYears(game.content);
    return Line(
      tr('finance.bankLends'),
      credit + guarantee > Money.zero
          ? tr('finance.upTo', {
              'amount': money(credit + guarantee, cents: false),
            })
          : tr('finance.nothingMore'),
      hint: credit > Money.zero && guarantee > Money.zero
          ? tr('finance.bankBoth', {
              'credit': money(credit, cents: false),
              'years': years,
              'guarantee': money(guarantee, cents: false),
            })
          : credit > Money.zero
          ? tr('finance.bankCredit', {'years': years})
          : guarantee > Money.zero
          ? tr('finance.bankGuarantee')
          : tr('finance.bankNothing'),
    );
  }
}

/// How much cash the company keeps for wages, rent and the bank, and each
/// store's share of it.
class _CushionSheet extends StatefulWidget {
  const _CushionSheet({required this.company});

  final CompanyView company;

  @override
  State<_CushionSheet> createState() => _CushionSheetState();
}

class _CushionSheetState extends State<_CushionSheet> {
  int? _days;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = widget.company;
    final days = _days ?? game.cushionDays(company);
    final shares = <(String, Money)>[
      for (final store in company.stores)
        if (store.status != StoreStatus.closed)
          (
            game.storeName(store.id),
            storeCushion(game.view, game.content, store, days),
          ),
      for (final loan in company.loans)
        (
          tr('finance.loanNextPayment', {'number': loan.number}),
          nextInstallment(loan),
        ),
      if (company.taxAccrued > Money.zero)
        (tr('finance.taxSoFar'), company.taxAccrued),
    ];
    var total = Money.zero;
    for (final (_, amount) in shares) {
      total += amount;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('finance.cashCushion'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr('finance.cushionPitch'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final option in const [7, 14, 28])
                ChoiceChip(
                  label: Text(cushionLength(option)),
                  selected: days == option,
                  onSelected: (_) => setState(() => _days = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (name, amount) in shares) Line(name, money(amount)),
          Line(tr('finance.cushion'), money(total), strong: true),
          Line(
            tr('common.freeCash'),
            money(company.cash - company.committed),
            hint: tr('finance.cashLessBills'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              game.submit(
                SetCushion(game.player, company: company.id, days: days),
              );
              Navigator.pop(context);
            },
            child: Text(
              tr('finance.keepWages', {'length': cushionLength(days)}),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the state takes: the rates, and what the player's company owes on
/// this year so far.
class _Taxes extends StatelessWidget {
  const _Taxes();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final company = game.company;
    final country = game.countryOfCompany(company);
    final taxes = content.taxesOf(country)!;
    final level = game.view.economy(country).priceIndex;
    final carried = company?.lossCarried ?? Money.zero;
    final (:profit, :due) = _yearSoFar(game);
    final dividends = content.taxesOf(game.residence) ?? taxes;
    final abroad = [
      for (final due in company?.countryTaxes ?? const <CountryTax>[])
        if (due.sales > Money.zero || due.tax > Money.zero) due,
    ];
    String rates(TaxDef taxes) =>
        taxes.reducedRate == taxes.corporateRate ||
            taxes.reducedLimit == Money.zero
        ? percent(taxes.corporateRate, decimals: 1)
        : tr('finance.taxRates', {
            'reduced': percent(taxes.reducedRate, decimals: 0),
            'full': percent(taxes.corporateRate, decimals: 0),
          });
    return Section(
      title: tr('finance.taxes'),
      icon: Icons.account_balance,
      children: [
        Line(
          content.countries.length > 1
              ? tr('finance.corporateTaxIn', {
                  'country': content.countries[country.index].name,
                })
              : tr('finance.corporateTax'),
          rates(taxes),
          hint: taxes.reducedLimit == Money.zero
              ? null
              : tr('finance.taxRatesHint', {
                  'reduced': percent(taxes.reducedRate, decimals: 0),
                  'limit': money(taxes.reducedLimit.times(level), cents: false),
                }),
        ),
        Line(
          tr('finance.dividends'),
          percent(dividends.dividendRate, decimals: 1),
          hint: content.countries.length > 1
              ? tr('finance.dividendsWhere', {
                  'country': content.countries[game.residence.index].name,
                })
              : tr('finance.dividendsHint'),
        ),
        if (abroad.length > 1) ...[
          const Divider(),
          for (final due in abroad)
            Line(
              tr('finance.taxInCountry', {
                'country': content.countries[due.country.index].name,
                'rate': rates(content.taxesOf(due.country) ?? taxes),
              }),
              money(due.tax),
              hint: tr('finance.taxBase', {'base': signedMoney(due.base)}),
            ),
          Hint(tr('finance.taxByCountryHint')),
        ],
        if (company != null) ...[
          const Divider(),
          Line(
            tr('finance.profitThisYear'),
            signedMoney(profit),
            color: gainColor(context, profit.cents.sign),
          ),
          if (carried > Money.zero)
            Line(
              tr('finance.lossesCarried'),
              money(carried),
              hint: tr('finance.lossesHint'),
            ),
          Line(
            tr('finance.taxDue'),
            money(due),
            strong: true,
            hint: tr('finance.ifYearEnded'),
          ),
        ],
        Hint(tr('finance.taxHint')),
      ],
    );
  }
}
