import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../directors.dart';
import '../format.dart';
import '../l10n.dart';
import '../letters.dart';
import '../loans.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'exchange.dart' show ExchangeEntry, change;
import 'financials.dart';
import 'shop.dart';
import 'world.dart';

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
            if (active.isEmpty) Hint(tr('finance.noCompany')),
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
              DirectorSection(company: current),
            FinancialsSection(company: current.id),
            if (current.status == CompanyStatus.active)
              ExchangeEntry(company: current),
            _CompanyCard(company: current),
            if (current.memos.isNotEmpty) _Letters(company: current),
          ],
      ],
    );

/// Opens the sheet that hires [company]'s director or changes their brief.
void showDirectorSheet(BuildContext context, CompanyView company) {
  showGameSheet(context, context.game, _DirectorSheet(company: company));
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
                onPressed: () => showGameSheet(
                  context,
                  game,
                  _CushionSheet(company: company),
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
                onPressed: () => showGameSheet(
                  context,
                  game,
                  _BorrowSheet(company: company),
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
class DirectorSection extends StatelessWidget {
  const DirectorSection({super.key, required this.company});

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
    final person = directorPerson(game, company, director);
    final ledger = Ledger.of(context);
    final theme = Theme.of(context);
    final record = _recordOf(company, director);
    final shops = shopsOf(game.view, company);
    final sales = salesSince(game, company, director);
    final saying = motto(content, person);
    final past = pastLine(grade, person);
    return Section(
      title: tr('finance.director'),
      icon: Icons.badge_outlined,
      children: [
        PersonHeader(
          person: person,
          line: directorLine(content, grade, person),
          value: tr('common.perMonth', {
            'amount': money(monthly, cents: false),
          }),
        ),
        if (saying != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              tr('directors.saying', {'text': saying}),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: titleFont,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            tr(
              'directors.recordSince.${person?.female ?? false ? 'woman' : 'man'}',
              {
                'date': shortDate(director.hiredOn),
                'year': director.hiredOn.date.year,
              },
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: ledger.muted),
          ),
        ),
        Line(
          tr('directors.shops'),
          record.shopsAtHire < 0
              ? '$shops'
              : tr('directors.thenNow', {
                  'then': record.shopsAtHire,
                  'now': shops,
                }),
        ),
        Line(
          tr('directors.openedBoughtClosed'),
          '${record.opened} · ${record.bought} · ${record.closed}',
        ),
        if (sales != null)
          Line(
            tr('directors.salesMonth'),
            change(sales.now, sales.then),
            color: gainColor(context, (sales.now - sales.then).cents.sign),
            hint: tr('directors.thenNow', {
              'then': money(sales.then, cents: false),
              'now': money(sales.now, cents: false),
            }),
          ),
        Line(tr('directors.paidYou'), money(record.paid, cents: false)),
        if (past != null) Hint(tr('directors.before', {'past': past})),
        if (characterPitch(
              content,
              person,
              content.strategies[director.strategy.index],
            )
            case final pitch?)
          Hint(pitch),
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

/// [director]'s record: as kept, or, for one hired before records were
/// kept, as far as [company]'s memos since they came go back.
DirectorRecord _recordOf(CompanyView company, Director director) {
  if (director.record.shopsAtHire >= 0) return director.record;
  var record = director.record;
  for (final memo in company.memos) {
    if (memo.day.number >= director.hiredOn.number) {
      record = record.noting(memo);
    }
  }
  return record;
}

/// A director's name and line, with a figure on the right.
class PersonHeader extends StatelessWidget {
  const PersonHeader({
    super.key,
    required this.person,
    required this.line,
    this.value,
  });

  final DirectorPerson? person;
  final String line;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (person case final person?)
                  Text(person.name, style: theme.textTheme.titleMedium),
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ledger.muted,
                  ),
                ),
              ],
            ),
          ),
          if (value case final value?) ...[
            const SizedBox(width: 8),
            Text(value, style: figures(theme.textTheme.bodyMedium)),
          ],
        ],
      ),
    );
  }
}

/// Who may run the company: the director in place, then this month's
/// shortlist; or, in a scenario without persons, the grades.
typedef _Option = ({
  DirectorGradeId grade,
  DirectorPerson? person,
  DirectorPerson? shown,
  bool current,
});

/// Picks a director and brief, for hiring or a new brief.
class _DirectorSheet extends StatefulWidget {
  const _DirectorSheet({required this.company});

  final CompanyView company;

  @override
  State<_DirectorSheet> createState() => _DirectorSheetState();
}

class _DirectorSheetState extends State<_DirectorSheet> {
  int? _pick;
  Growth? _growth;
  bool? _payout;
  bool? _borrows;
  ManagerGradeId? _managerGrade;
  StrategyId? _strategy;
  Fx? _rate;
  bool? _auto;
  Set<String>? _regions;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final current = game.directorOf(widget.company);
    final directors = content.directors!;
    final grades = directors.grades;
    final shortlist = directorShortlist(
      content,
      game.view,
      widget.company,
      game.countryOfCompany(widget.company),
    );
    final options = <_Option>[
      if (current != null)
        (
          grade: current.grade,
          person: current.person,
          shown: directorPerson(game, widget.company, current),
          current: true,
        ),
      if (shortlist.isNotEmpty)
        for (final (:grade, :person) in shortlist)
          if (!samePerson(current?.person, person))
            (grade: grade, person: person, shown: person, current: false)
          else
            for (final option in grades)
              if (current == null || current.grade != option.id)
                (grade: option.id, person: null, shown: null, current: false),
    ];
    // The director in place, or else one of the middle grade.
    final fallback = options.indexWhere(
      (o) => o.current || o.grade == grades[grades.length ~/ 2].id,
    );
    final chosen =
        options[(_pick ?? (fallback < 0 ? 0 : fallback)).clamp(
          0,
          options.length - 1,
        )];
    final grade = chosen.grade;
    final character = directors.characterOfPerson(chosen.shown);
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
        _strategy ?? current?.strategy ?? balancedStrategy(strategies);
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
    final auto = _auto ?? current?.nationalAuto ?? false;
    final rate = _rate ?? current?.nationalRate ?? Fx.zero;
    final gradeDef = grades[grade.index];
    // What they grow it at left to judge, as their character paces it.
    final judged = gradeDef.growth * character.pace;
    // What the director grows the chain at, and so opens this month.
    final growing = auto ? judged : rate;
    final growsAtAll = growing > Fx.zero;
    final planned = nationally
        ? _planned(
            game,
            widget.company,
            countries,
            content.strategies[strategy.index].format,
            growing,
          )
        : (opens: 0, shops: 0);
    final picked = _regions ?? {...?current?.nationalRegions};
    // This year's shops run by formula: opened and closed, their fitting
    // out and what they earned.
    final year = game.today.date.year;
    var opened = 0;
    var closed = 0;
    var earned = Money.zero;
    var hasBlocks = false;
    // Its biggest shops run by formula, whose marketing and brand show.
    CompanyBlockView? biggest;
    for (final country in countries) {
      for (final block in country.blocks) {
        if (block.company != widget.company.id) continue;
        hasBlocks = true;
        if (biggest == null || block.stores > biggest.stores) {
          biggest = block;
        }
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
    Money monthly(_Option option) => grades[option.grade.index].salary
        .times(directors.characterOfPerson(option.shown).salary)
        .times(wageIndex)
        .timesInt(30);
    return SheetFrame(
      footer: FilledButton(
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
              person: chosen.person,
              nationalRate: nationally && !auto ? rate : Fx.zero,
              nationalAuto: nationally && auto,
              nationalRegions: [
                if (nationally && growsAtAll)
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
                  'amount': money(monthly(chosen), cents: false),
                })
              : chosen.current
              ? tr('common.updateBrief')
              : tr('finance.replaceDirector'),
        ),
      ),
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
        Text(
          shortlist.isEmpty ? tr('common.who') : tr('directors.shortlist'),
          style: theme.textTheme.titleSmall,
        ),
        for (final (i, option) in options.indexed)
          if (option.shown == null)
            ChoiceTile(
              selected: identical(option, chosen),
              title: tr('finance.gradeLine', {
                'grade': grades[option.grade.index].name,
                'salary': money(monthly(option), cents: false),
              }),
              subtitle: _gradeHint(content, grades[option.grade.index]),
              onTap: () => setState(() => _pick = i),
            )
          else
            _CandidateTile(
              person: option.shown!,
              line: [
                directorLine(content, grades[option.grade.index], option.shown),
                if (option.current) tr('directors.inPlace'),
              ].join(' · '),
              salary: money(monthly(option), cents: false),
              about: [
                if (pastLine(grades[option.grade.index], option.shown)
                    case final past?)
                  tr('directors.before', {'past': past}),
                ?characterPitch(
                  content,
                  option.shown,
                  content.strategies[strategy.index],
                ),
              ].join(' '),
              selected: identical(option, chosen),
              onTap: () => setState(() => _pick = i),
            ),
        if (shortlist.isNotEmpty) ...[
          Hint(_gradeHint(content, gradeDef, character)),
          Hint(tr('directors.shortlistHint')),
        ],
        const SizedBox(height: 8),
        Text(tr('finance.howFar'), style: theme.textTheme.titleSmall),
        for (final option in Growth.values)
          ChoiceTile(
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
          Text(tr('finance.payingForIt'), style: theme.textTheme.titleSmall),
          ChoiceTile(
            selected: !borrows,
            title: tr('finance.onlyEarnings'),
            onTap: () => setState(() => _borrows = false),
          ),
          ChoiceTile(
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
          Text(tr('finance.acrossCountry'), style: theme.textTheme.titleSmall),
          Text(tr('finance.growRate')),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final option in _rates)
                ChoiceChip(
                  label: Text(
                    option == Fx.zero
                        ? tr('finance.rateOff')
                        : percent(option, decimals: 0),
                  ),
                  selected: !auto && rate == option,
                  onSelected: (_) => setState(() {
                    _auto = false;
                    _rate = option;
                  }),
                ),
              ChoiceChip(
                label: Text(tr('finance.rateAsJudged')),
                selected: auto,
                onSelected: (_) => setState(() => _auto = true),
              ),
            ],
          ),
          Hint(tr('finance.growRateHint')),
          if (growsAtAll)
            Line(
              tr('finance.thisMonth'),
              tr('finance.aboutShops', {
                'count': planned.opens,
                'total': planned.shops,
              }),
            ),
          Line(
            capitalized(
              tr('finance.runsWellUpTo', {
                'director': chosen.shown?.name ?? aDirector(gradeDef),
              }),
            ),
            tr('finance.aMonth', {
              'rate': percent(gradeDef.growth, decimals: 1),
            }),
          ),
          if (character.pace != Fx.one)
            Line(
              tr('directors.leftToJudge'),
              tr('finance.aMonth', {'rate': percent(judged, decimals: 1)}),
            ),
          Line(
            tr('finance.slowsPast'),
            tr('finance.ofItsTrade', {
              'share': percent(content.directors!.criticalShare, decimals: 0),
            }),
          ),
          if (growing > gradeDef.growth) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Stamp(tr('finance.beyondPace')),
            ),
            Hint(tr('finance.beyondPaceHint')),
          ],
          Hint(
            tr('finance.nationalPaceHint', {
              'cost': money(
                national.fitOut.times(countries.first.priceIndex),
                cents: false,
              ),
            }),
          ),
          if (growsAtAll) ...[
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
                  : tr('finance.nationalOnly', {'count': picked.length}),
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
        if (content.buyingTerms != null &&
            widget.company.goodsBought > Money.zero) ...[
          const SizedBox(height: 8),
          Text(tr('finance.whatSizeBuys'), style: theme.textTheme.titleSmall),
          Line(
            tr('finance.buyingTerms'),
            '−${percent(widget.company.buyingDiscount)}',
            color: Ledger.of(context).gain,
            hint: tr('finance.boughtThisYear', {
              'amount': money(widget.company.goodsBought, cents: false),
            }),
          ),
          Line(
            tr('finance.atTwice', {
              'amount': money(
                widget.company.goodsBought.timesInt(2),
                cents: false,
              ),
            }),
            '−${percent(buyingDiscountAt(content, widget.company.goodsBought.timesInt(2)))}',
          ),
          if (biggest != null) ...[
            Line(
              tr('finance.nationalMarketing'),
              percent(biggest.marketing),
              hint: current == null
                  ? tr('finance.marketingStrategy')
                  : tr('finance.marketingDirector'),
            ),
            Line(
              tr('finance.brandPull'),
              '+${percent(biggest.brandPull)}',
              color: Ledger.of(context).gain,
            ),
          ],
          Hint(tr('finance.whatSizeBuysHint')),
        ],
        const SizedBox(height: 8),
        Text(tr('finance.theProfit'), style: theme.textTheme.titleSmall),
        ChoiceTile(
          selected: !payout,
          title: tr('finance.keepInCompany'),
          onTap: () => setState(() => _payout = false),
        ),
        ChoiceTile(
          selected: payout,
          title: tr('finance.sendMe'),
          subtitle: tr('finance.sendMeHint'),
          onTap: () => setState(() => _payout = true),
        ),
        const SizedBox(height: 8),
        Text(tr('finance.managersHire'), style: theme.textTheme.titleSmall),
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
                onSelected: (_) => setState(() => _managerGrade = option.id),
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
                onSelected: (_) => setState(() => _strategy = option.id),
              ),
          ],
        ),
        if (stanceAdvice(content.strategies[strategy.index]) case final advice?)
          Hint(advice),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// What a director of [grade] and [character] does to their managers'
/// misjudgment, and how far they misjudge a new store.
String _gradeHint(
  ContentDb content,
  DirectorGradeDef grade, [
  DirectorCharacterDef character = DirectorCharacterDef.plain,
]) {
  final directors = content.directors!;
  return tr('finance.gradeHint', {
    'cuts': percent(
      directors.coaching * grade.skill * character.coaching,
      decimals: 0,
    ),
    'error': percent(
      directors.judgmentError * (Fx.one - grade.skill),
      decimals: 0,
    ),
  });
}

/// A candidate on the shortlist, or the director in place: their portrait,
/// name and line, pay, past and what their character changes.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.person,
    required this.line,
    required this.salary,
    required this.about,
    required this.selected,
    required this.onTap,
  });

  final DirectorPerson person;
  final String line;
  final String salary;
  final String about;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? ledger.shade : null,
            border: Border(bottom: BorderSide(color: ledger.rule, width: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.name,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          tr('common.perMonth', {'amount': salary}),
                          style: figures(theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                    Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ledger.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(about, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? ledger.ink : ledger.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rates a brief may grow a chain at, a month.
final _rates = [
  Fx.zero,
  Fx.parse('0.01'),
  Fx.parse('0.02'),
  Fx.parse('0.04'),
  Fx.parse('0.06'),
  maxNationalRate,
];

/// What a director growing [company]'s shops of [format] at [rate] opens
/// this month across [countries], and its shops of that trade there.
({int opens, int shops}) _planned(
  SimulationController game,
  CompanyView company,
  List<NationalCountryView> countries,
  FormatId format,
  Fx rate,
) {
  final view = game.view;
  final content = game.content;
  var opens = 0;
  var shops = 0;
  for (final country in countries) {
    final trade = country.tradeOf(content, format);
    if (trade == null) continue;
    shops += nationalChainShops(view, content, company, country, trade);
    opens += nationalBudget(view, content, company, country, trade, rate);
  }
  return (opens: opens, shops: shops);
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
    final director = company.director;
    final letters = directorLetters(
      company,
      game.reports(ReportPeriod.month, company: company.id),
      game.content,
      game.view,
      by: director == null ? null : directorPerson(game, company, director),
      since: director?.hiredOn,
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
          if (letter.by case final by?)
            Text(
              by.name.split(' ').first,
              style: text?.copyWith(fontStyle: FontStyle.italic, fontSize: 17),
            )
          else
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
            title: Text(tr('finance.holdingGuarantees')),
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
