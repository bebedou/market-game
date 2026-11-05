import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../loans.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// The world outside: the country's economy on top, with its history a
/// page away, then the competitors and the cities, each a page of its own.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final here = {for (final (_, store) in game.myStores) store.market};
    final mine = {for (final company in view.companies) company.id};
    final trading = <CompanyId>{};
    final local = <CompanyId>{};
    for (final shelf in view.shelves) {
      if (shelf.status == StoreStatus.closed || mine.contains(shelf.company)) {
        continue;
      }
      trading.add(shelf.company);
      if (here.contains(shelf.market)) local.add(shelf.company);
    }
    final markets = game.content.markets.length;
    return ListView(
      key: const PageStorageKey('market'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        const _EconomySummary(),
        Section(
          title: tr('market.theMarket'),
          children: [
            IndexRow(
              title: tr('market.competitors'),
              subtitle: tr('market.competitorsSummary', {
                'count': trading.length,
                'local': here.isEmpty
                    ? ''
                    : tr('market.inYourCities', {'count': local.length}),
              }),
              onTap: () => context.openPage(
                tr('market.competitors'),
                (_) => [const _Competitors()],
              ),
            ),
            IndexRow(
              title: markets == 1
                  ? tr('market.theMarket')
                  : tr('market.cities'),
              subtitle: tr('market.citiesSummary', {
                'cities': markets == 1
                    ? ''
                    : tr('market.nCities', {'count': markets}),
                'vacant': view.vacantSites.length,
              }),
              onTap: () => context.openPage(
                tr('market.cities'),
                (context) => [_CitiesCard(game: context.game)],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The country's economy at a glance: the turn of the cycle and its key
/// figures, and the way to its history.
class _EconomySummary extends StatelessWidget {
  const _EconomySummary();

  /// A multiple of the start as a change: ×1.0412 is +4.1%.
  static String _change(Fx multiple) =>
      '${multiple >= Fx.one ? '+' : '−'}${percent((multiple - Fx.one).abs())}';

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final macro = game.view.macro;
    final regime = game.content.macro.regimes[macro.regime.index];
    final theme = Theme.of(context);
    Widget figure(String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            Text(
              value,
              style: figures(
                theme.textTheme.titleMedium,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
    return Section(
      title: tr('scenario.country'),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: regimeColor(regime), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(regime.name, style: theme.textTheme.titleSmall),
              Text(
                regime.demand >= Fx.one
                    ? tr('market.spendFreely')
                    : tr('market.cutBack'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Row(
          children: [
            figure(tr('market.inflation'), percent(macro.inflation)),
            figure(tr('market.centralBankRate'), percent(macro.policyRate)),
            if (game.content.macro.labour != null)
              figure(tr('market.unemployment'), percent(macro.unemployment)),
          ],
        ),
        Row(
          children: [
            figure(tr('market.prices'), _change(macro.priceIndex)),
            figure(tr('market.wages'), _change(macro.wageIndex)),
            figure(
              tr('market.buyingPower'),
              _change(
                game.content.demand.purchasingPower(
                  macro.wageIndex,
                  macro.priceIndex,
                ),
              ),
            ),
          ],
        ),
        Hint(tr('market.changeSinceStart')),
        IndexRow(
          title: tr('market.moreOnEconomy'),
          subtitle: tr('market.moreOnEconomyPitch'),
          onTap: () => context.openPage(
            tr('market.theEconomy'),
            (context) => [
              _EconomyCard(game: context.game),
              const _EconomicHistory(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The economy month by month: inflation, the central bank's rate and
/// unemployment as lines, prices and wages against the start, and the
/// phases of the cycle.
class _EconomicHistory extends StatelessWidget {
  const _EconomicHistory();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final history = game.view.history;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labour = game.content.macro.labour != null;
    double pct(Fx value) => value.raw / 100;
    return Section(
      title: tr('market.history'),
      icon: Icons.show_chart,
      children: [
        if (history.length < 2)
          Hint(tr('market.historyBuilds'))
        else ...[
          TrendChart(
            unit: '%',
            series: [
              (
                label: tr('market.inflation'),
                color: scheme.error,
                values: [for (final m in history) pct(m.inflation)],
              ),
              (
                label: tr('market.centralBankRate'),
                color: scheme.primary,
                values: [for (final m in history) pct(m.policyRate)],
              ),
              if (labour)
                (
                  label: tr('market.unemployment'),
                  color: scheme.tertiary,
                  values: [for (final m in history) pct(m.unemployment)],
                ),
            ],
          ),
          const SizedBox(height: 14),
          TrendChart(
            unit: '×',
            series: [
              (
                label: tr('market.prices'),
                color: scheme.secondary,
                values: [for (final m in history) m.priceIndex.raw / 10000],
              ),
              (
                label: tr('market.wages'),
                color: scheme.primary,
                values: [for (final m in history) m.wageIndex.raw / 10000],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('market.theCycle'), style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final month in history)
                    Expanded(
                      child: ColoredBox(
                        color: regimeColor(
                          game.content.macro.regimes[month.regime.index],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                monthName(history.first.day),
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                monthName(history.last.day),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final regime in game.content.macro.regimes)
                Pill(
                  regime.name,
                  icon: regimeIcon(regime),
                  color: regimeColor(regime),
                ),
            ],
          ),
          if (labour) Hint(tr('market.okun')),
        ],
      ],
    );
  }
}

/// Every company trading, rivals and the player's own: its public accounts
/// for the last years, what kinds of business it runs and where, and each
/// store's size, hours and prices against what shoppers expect.
class _Competitors extends StatelessWidget {
  const _Competitors();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final mine = {for (final company in view.companies) company.id};
    final byCompany = <int, List<ShelfView>>{};
    for (final shelf in view.shelves) {
      if (shelf.status == StoreStatus.closed) continue;
      (byCompany[shelf.company.index] ??= []).add(shelf);
    }
    Filing? latest(int company) => view.filings
        .where((f) => f.company.index == company)
        .fold<Filing?>(
          null,
          (best, f) => best == null || f.year > best.year ? f : best,
        );
    // The player's own first, then rivals in the player's cities.
    final here = {for (final (_, store) in game.myStores) store.market};
    int rank(int company) => mine.contains(CompanyId(company))
        ? 0
        : byCompany[company]!.any((shelf) => here.contains(shelf.market))
        ? 1
        : 2;
    final companies = byCompany.keys.toList()
      ..sort((a, b) {
        if (rank(a) != rank(b)) return rank(a).compareTo(rank(b));
        final ra = latest(a)?.revenue.cents ?? 0;
        final rb = latest(b)?.revenue.cents ?? 0;
        if (ra != rb) return rb.compareTo(ra);
        return byCompany[b]!.length.compareTo(byCompany[a]!.length);
      });
    final hasFilings = view.filings.isNotEmpty;
    return Section(
      title: tr('market.competitors'),
      icon: Icons.groups_outlined,
      children: [
        Hint(
          hasFilings ? tr('market.filingsKnown') : tr('market.filingsUnknown'),
        ),
        for (final company in companies)
          _CompanyTile(
            company: CompanyId(company),
            shelves: byCompany[company]!,
            mine: mine.contains(CompanyId(company)),
          ),
      ],
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.company,
    required this.shelves,
    required this.mine,
  });

  final CompanyId company;
  final List<ShelfView> shelves;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final content = game.content;
    final theme = Theme.of(context);
    final filings = [
      for (final filing in view.filings)
        if (filing.company == company) filing,
    ]..sort((a, b) => b.year.compareTo(a.year));
    final last = filings.firstOrNull;
    final before = filings.length > 1 ? filings[1] : null;
    final formats = {for (final s in shelves) s.format};
    final cities = {for (final s in shelves) s.market};
    String change(Money now, Money then) {
      if (then.cents == 0) return '';
      final pct = (now.cents - then.cents) * 100 ~/ then.cents.abs();
      return tr('market.changeOnYear', {
        'change': percentOf('${pct >= 0 ? '+' : ''}$pct'),
        'year': before!.year,
      });
    }

    return ExpansionTile(
      key: PageStorageKey('company ${company.index}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      leading: TradeMark(
        Ledger.of(context).trade(content.formats[formats.first.index]),
        size: 12,
      ),
      minTileHeight: 48,
      title: Row(
        children: [
          Flexible(
            child: Text(
              view.companyNames[company.index],
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (mine) ...[const SizedBox(width: 6), Pill(tr('market.you'))],
        ],
      ),
      subtitle: Text(
        [
          tr('common.stores', {'count': shelves.length}),
          if (last != null)
            tr('market.salesLine', {
              'amount': money(last.revenue, cents: false),
            }),
          if (content.markets.length > 1)
            tr('common.cities', {'count': cities.length}),
        ].join(' · '),
      ),
      children: [
        if (last != null) ...[
          Line(
            tr('market.salesYear', {'year': last.year}),
            money(last.revenue, cents: false),
            hint: before == null
                ? null
                : change(last.revenue, before.revenue).trim(),
          ),
          Line(
            tr('market.profitYear', {'year': last.year}),
            signedMoney(last.profit),
            color: gainColor(context, last.profit.cents.sign),
            hint: last.revenue.cents == 0
                ? null
                : tr('market.marginLine', {
                    'margin': percent(
                      Fx.raw(last.profit.cents * 10000 ~/ last.revenue.cents),
                      decimals: 0,
                    ),
                  }),
          ),
          if (filings.length > 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: BarChart([
                for (final filing in filings.reversed) filing.profit.cents,
              ]),
            ),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final format in formats)
              Pill(
                content.formats[format.index].name,
                icon: formatIcon(content.formats[format.index]),
              ),
          ],
        ),
        for (final shelf in shelves) _RivalStore(shelf: shelf, mine: mine),
        if (!mine && view.companyPrices[company.index] != null)
          _BuyCompany(company: company),
      ],
    );
  }
}

/// A rival company's asking price, and the button to buy it whole.
class _BuyCompany extends StatelessWidget {
  const _BuyCompany({required this.company});

  final CompanyId company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final price = view.companyPrices[company.index]!;
    final pending = game.pending.any(
      (c) => c is BuyCompany && c.company == company,
    );
    final room = view.companyCredits[company.index] ?? Money.zero;
    final credit = room.isNegative ? Money.zero : room;
    final short = price - view.cash - credit;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Line(
            tr('market.companyPrice'),
            money(price, cents: false),
            strong: true,
            hint: price == symbolicPrice
                ? tr('market.symbolicHint')
                : tr('market.companyPriceHint'),
          ),
          if (pending)
            Hint(tr('market.buyTomorrow'))
          else ...[
            Hint(
              short > Money.zero && credit > Money.zero
                  ? tr('market.paidBorrowShort', {
                      'credit': money(credit, cents: false),
                      'short': money(short, cents: false),
                    })
                  : short > Money.zero
                  ? tr('market.paidShort', {
                      'short': money(short, cents: false),
                    })
                  : credit > Money.zero
                  ? tr('market.paidCanBorrow')
                  : tr('market.paidCash'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.handshake_outlined, size: 18),
                onPressed: short > Money.zero
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => GameScope(
                          controller: game,
                          child: _BuyCompanyDialog(company: company),
                        ),
                      ),
                label: Text(tr('market.buyCompany')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirms buying a rival company whole, with what it would borrow on its
/// own earnings towards the price.
class _BuyCompanyDialog extends StatefulWidget {
  const _BuyCompanyDialog({required this.company});

  final CompanyId company;

  @override
  State<_BuyCompanyDialog> createState() => _BuyCompanyDialogState();
}

class _BuyCompanyDialogState extends State<_BuyCompanyDialog> {
  /// Whether it borrows: by default, when the player can't pay outright.
  bool? _borrow;
  late int _months = longestTerm(context.game.content);

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final company = widget.company;
    final price = view.companyPrices[company.index]!;
    final name = view.companyNames[company.index];
    final room = view.companyCredits[company.index] ?? Money.zero;
    final credit = room.isNegative ? Money.zero : room;
    final short = price - view.cash;
    final amount = credit < roundedUp(short) ? credit : roundedUp(short);
    final borrow = credit > Money.zero && (_borrow ?? short > Money.zero);
    final lent = borrow
        ? (amount > Money.zero
              ? amount
              : credit < price
              ? credit
              : price)
        : Money.zero;
    var earnings = Money.zero;
    for (final shelf in view.shelves) {
      if (shelf.company != company) continue;
      earnings += view.valuations[shelf.id.index]?.earnings ?? Money.zero;
    }
    final ready = price - lent <= view.cash;
    return AlertDialog(
      title: Text(tr('market.buyQuestion', {'name': name})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Line(
              tr('common.askingPrice'),
              money(price, cents: false),
              strong: true,
            ),
            Line(
              tr('market.storesEarnYear'),
              signedMoney(earnings, cents: false),
              color: gainColor(context, earnings.cents.sign),
              hint: tr('market.theirLastSales'),
            ),
            Line(tr('common.ownCash'), money(view.cash, cents: false)),
            if (credit > Money.zero)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market.itBorrowsOnEarnings')),
                subtitle: borrow
                    ? null
                    : Text(
                        tr('market.upToPayLess', {
                          'amount': money(credit, cents: false),
                        }),
                      ),
                value: borrow,
                onChanged: (on) => setState(() => _borrow = on),
              ),
            if (borrow) ...[
              LoanTerms(
                view: view,
                content: game.content,
                amount: lent,
                credit: credit,
                guarantee: Money.zero,
                months: _months,
                onMonths: (months) => setState(() => _months = months),
                label: tr('market.itBorrows'),
                note: earnings > Money.zero
                    ? tr('market.storesEarnMonth', {
                        'amount': money(
                          Money(earnings.cents ~/ 12),
                          cents: false,
                        ),
                      })
                    : null,
              ),
              Line(
                tr('market.youPay'),
                money(price - lent, cents: false),
                strong: true,
              ),
            ],
            Hint(
              ready
                  ? tr('market.tomorrowBody')
                  : tr('market.needMoreOwn', {
                      'amount': money(price - lent - view.cash, cents: false),
                    }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: !ready
              ? null
              : () {
                  game.submit(
                    BuyCompany(
                      game.player,
                      company: company,
                      borrow: lent,
                      termMonths: borrow ? _months : 0,
                    ),
                  );
                  Navigator.pop(context);
                },
          child: Text(tr('market.buyCompany')),
        ),
      ],
    );
  }
}

/// Picks which of the player's companies buys [shelf], and confirms.
class BuyStoreDialog extends StatefulWidget {
  const BuyStoreDialog({super.key, required this.game, required this.shelf});

  final SimulationController game;
  final ShelfView shelf;

  @override
  State<BuyStoreDialog> createState() => _BuyStoreDialogState();
}

class _BuyStoreDialogState extends State<BuyStoreDialog> {
  late CompanyId _buyer = _companies
      .reduce((best, c) => c.cash > best.cash ? c : best)
      .id;

  /// Whether to borrow: by default, when the company can't pay outright.
  bool? _borrow;
  late int _months = longestTerm(widget.game.content);

  List<CompanyView> get _companies => widget.game.activeCompanies;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final view = game.view;
    final shelf = widget.shelf;
    final value = view.valuations[shelf.id.index]!;
    final buyer = _companies.firstWhere((c) => c.id == _buyer);
    final short = value.price - buyer.cash;
    final young = game.today.number - shelf.opensOn.number < salesHistoryDays;
    // Enough to keep the company's bills, orders and cushion covered.
    final amount = roundedUp(
      value.price - (buyer.cash - buyer.committed - game.cushion(buyer)),
    );
    final borrow = amount > Money.zero && (_borrow ?? short > Money.zero);
    // The bank counts the store's own earnings too.
    final room =
        (view.companyCredits[buyer.id.index] ?? Money.zero) +
        value.earnings.times(game.content.finance.earningsMultiple);
    final terms = LoanTerms(
      view: view,
      content: game.content,
      amount: amount,
      credit: room.isNegative ? Money.zero : room,
      guarantee: view.guaranteeRoom,
      months: _months,
      onMonths: (months) => setState(() => _months = months),
      note: young || value.earnings <= Money.zero
          ? null
          : tr('market.storeEarnsMonth', {
              'amount': money(Money(value.earnings.cents ~/ 12), cents: false),
            }),
    );
    final ready = borrow ? terms.split != null : short <= Money.zero;
    return AlertDialog(
      title: Text(tr('market.buyQuestion', {'name': shelf.name})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Line(
              tr('common.askingPrice'),
              money(value.price, cents: false),
              strong: true,
            ),
            Line(
              tr('common.earnsYear'),
              young
                  ? tr('common.tooNew')
                  : signedMoney(value.earnings, cents: false),
              color: young
                  ? null
                  : gainColor(context, value.earnings.cents.sign),
              hint: tr('store.atLastSales'),
            ),
            Line(tr('common.fittings'), money(value.fittings, cents: false)),
            Line(tr('common.stockAtCost'), money(value.stock, cents: false)),
            const SizedBox(height: 8),
            if (_companies.length > 1)
              DropdownButton<CompanyId>(
                value: _buyer,
                isExpanded: true,
                items: [
                  for (final company in _companies)
                    DropdownMenuItem(
                      value: company.id,
                      child: Text(
                        '${game.companyName(company.id)} · '
                        '${money(company.cash, cents: false)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _buyer = id!),
              )
            else
              Hint(
                tr('market.paidBy', {
                  'company': game.companyName(buyer.id),
                  'cash': money(buyer.cash, cents: false),
                }),
              ),
            if (amount > Money.zero)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market.borrowFromBank')),
                subtitle: borrow
                    ? null
                    : Text(
                        short > Money.zero
                            ? tr('market.needsMore', {
                                'amount': money(short, cents: false),
                              })
                            : tr('market.keepCushion'),
                      ),
                value: borrow,
                onChanged: (on) => setState(() => _borrow = on),
              ),
            if (borrow) terms,
            Hint(
              !borrow && short > Money.zero
                  ? tr('market.needsMoreBorrow', {
                      'amount': money(short, cents: false),
                    })
                  : tr('market.keepsStock'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: !ready
              ? null
              : () {
                  game.submit(
                    BuyStore(
                      game.player,
                      store: shelf.id,
                      company: _buyer,
                      borrow: borrow ? amount : Money.zero,
                      termMonths: borrow ? _months : 0,
                    ),
                  );
                  Navigator.pop(context);
                },
          child: Text(borrow ? tr('market.buyWithLoan') : tr('common.buy')),
        ),
      ],
    );
  }
}

/// One store: where, what, how big, when it opens, and its prices against
/// what shoppers there expect.
class _RivalStore extends StatelessWidget {
  const _RivalStore({required this.shelf, required this.mine});

  final ShelfView shelf;

  /// Whether it is one of the player's.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final level =
        game.view.macro.priceIndex *
        content.markets[shelf.market.index].priceLevel;
    var sum = 0;
    var listed = 0;
    for (final product in content.products) {
      final price = shelf.prices[product.id.index];
      if (price == null) continue;
      final reference = product.referencePrice.times(level);
      sum += price.cents * 10000 ~/ reference.cents;
      listed++;
    }
    final index = listed == 0 ? null : Fx.raw(sum ~/ listed);
    final value = game.view.valuations[shelf.id.index];
    final pending = game.pending.any(
      (c) => c is BuyStore && c.store == shelf.id,
    );
    final line = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Line(
        shelf.name,
        index == null
            ? tr('market.nothingListed')
            : tr('market.pricesLevel', {'level': percent(index, decimals: 0)}),
        color: index == null
            ? null
            : index > Fx.parse('1.05')
            ? theme.colorScheme.error
            : index < Fx.parse('0.95')
            ? gainTone(context, 1)
            : null,
        hint: [
          if (content.markets.length > 1)
            content.markets[shelf.market.index].name,
          content.sites[shelf.site.index].name,
          tr('common.areaM2', {'area': shelf.area}),
          tr('market.nProducts', {'count': listed}),
          if (shelf.status == StoreStatus.building) tr('market.beingFitted'),
        ].join(' · '),
      ),
    );
    if (mine || value == null) return line;
    final struggling = value.price < value.stock + value.fittings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        Row(
          children: [
            Expanded(
              child: Text(
                tr(struggling ? 'market.askingLosing' : 'market.asking', {
                  'price': money(value.price, cents: false),
                }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: struggling
                      ? gainTone(context, 1)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (pending)
              Text(
                tr('market.buyingTomorrow'),
                style: theme.textTheme.bodySmall,
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
      ],
    );
  }
}

class _EconomyCard extends StatelessWidget {
  const _EconomyCard({required this.game});

  final SimulationController game;

  @override
  Widget build(BuildContext context) {
    final macro = game.view.macro;
    final regime = game.content.macro.regimes[macro.regime.index];
    final color = regimeColor(regime);
    final theme = Theme.of(context);
    Widget figure(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Section(
      title: tr('market.economy'),
      icon: Icons.public,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(regime.name, style: theme.textTheme.titleMedium),
                    Text(
                      regime.demand >= Fx.one
                          ? tr('market.spendFreely')
                          : tr('market.cutBack'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            figure(tr('market.inflation'), percent(macro.inflation)),
            figure(tr('market.centralBankRate'), percent(macro.policyRate)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            figure(
              tr('market.pricesSinceStart'),
              '×${fxText(macro.priceIndex)}',
            ),
            figure(tr('market.wagesSinceStart'), '×${fxText(macro.wageIndex)}'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            figure(
              tr('market.purchasingPower'),
              '×${fxText(game.content.demand.purchasingPower(macro.wageIndex, macro.priceIndex))}',
            ),
            if (game.content.macro.labour != null)
              figure(tr('market.unemployment'), percent(macro.unemployment)),
          ],
        ),
        Hint(tr('market.economyHint')),
      ],
    );
  }
}

class _CitiesCard extends StatelessWidget {
  const _CitiesCard({required this.game});

  final SimulationController game;

  @override
  Widget build(BuildContext context) => Section(
    title: game.content.markets.length == 1
        ? tr('market.market')
        : tr('market.cities'),
    icon: Icons.location_city,
    children: [
      for (final market in game.content.markets) _City(market: market),
    ],
  );
}

/// One city: what living and trading there costs, its households, its
/// stores and its vacant sites. Cities where the player trades start open.
class _City extends StatelessWidget {
  const _City({required this.market});

  final MarketDef market;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final content = game.content;
    final theme = Theme.of(context);
    final mine = {for (final company in view.companies) company.id};
    final trading = [
      for (final shelf in view.shelves)
        if (shelf.market == market.id && shelf.status != StoreStatus.closed)
          shelf,
    ];
    final vacant = [
      for (final id in view.vacantSites)
        if (content.sites[id.index].market == market.id)
          content.sites[id.index],
    ];
    final biggest = trading.fold(
      1,
      (most, shelf) => shelf.area > most ? shelf.area : most,
    );
    final here = trading.any((shelf) => mine.contains(shelf.company));
    final households = view.censuses[market.id.index].last.households;
    String level(Fx value) => value == Fx.one
        ? tr('market.asUsual')
        : '${value < Fx.one ? '−' : '+'}'
              '${percent((value - Fx.one).abs(), decimals: 0)}';
    return ExpansionTile(
      // Its own key, so its open state isn't confused with the list's
      // scroll position in the page storage.
      key: PageStorageKey('city ${market.key}'),
      initiallyExpanded: here || content.markets.length == 1,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      leading: Icon(
        here ? Icons.storefront_outlined : Icons.location_on_outlined,
        size: 20,
      ),
      minTileHeight: 48,
      title: Text(
        market.name,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        tr('market.citySummary', {
          'households': households,
          'stores': tr('common.stores', {'count': trading.length}),
          'vacant': vacant.isEmpty
              ? ''
              : tr('market.nVacant', {'count': vacant.length}),
        }),
      ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Pill(
              tr('market.pricesPill', {'level': level(market.priceLevel)}),
              icon: Icons.sell_outlined,
            ),
            Pill(
              tr('market.wagesPill', {'level': level(market.wageLevel)}),
              icon: Icons.badge_outlined,
            ),
            Pill(
              tr('market.incomesPill', {'level': level(market.incomeLevel)}),
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
        Hint(tr('market.levelsHint')),
        const SizedBox(height: 6),
        _Population(
          name: tr('common.households'),
          censuses: view.censuses[market.id.index],
        ),
        const SizedBox(height: 6),
        for (final shelf in trading)
          _StoreRow(
            shelf: shelf,
            mine: mine.contains(shelf.company),
            biggest: biggest,
          ),
        if (vacant.isNotEmpty) ...[
          const Divider(),
          Text(tr('market.vacantSites'), style: theme.textTheme.titleSmall),
          for (final site in vacant) _VacantSite(site: site),
        ],
      ],
    );
  }
}

/// A market's households at the latest census, how that compares with the
/// one before, and the trend since the first.
class _Population extends StatelessWidget {
  const _Population({required this.name, required this.censuses});

  final String name;
  final List<Census> censuses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = censuses.last;
    final previous = censuses.length > 1 ? censuses[censuses.length - 2] : null;
    final change = previous == null
        ? null
        : latest.households - previous.households;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Line(
          name,
          tr('market.nHouseholds', {'count': latest.households}),
          hint: switch (change) {
            null => tr('market.censusNext', {'year': latest.day.date.year}),
            _ => tr('market.censusChange', {
              'change': '${change >= 0 ? '+' : ''}$change',
              'year': latest.day.date.year,
            }),
          },
          color: change == null ? null : gainColor(context, change.sign),
        ),
        if (censuses.length >= 3) ...[
          const SizedBox(height: 4),
          Sparkline(
            [for (final census in censuses) census.households],
            color: theme.colorScheme.secondary,
            height: 32,
          ),
          Hint(
            tr('market.censusesSince', {'year': censuses.first.day.date.year}),
          ),
        ],
      ],
    );
  }
}

/// One store in the market: owner, site, size against the biggest, and
/// opening slots.
class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.shelf,
    required this.mine,
    required this.biggest,
  });

  final ShelfView shelf;
  final bool mine;
  final int biggest;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = mine ? scheme.primary : scheme.secondary;
    final products = shelf.prices.where((price) => price != null).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          TradeMark(
            Ledger.of(context).trade(game.content.formats[shelf.format.index]),
            size: 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        shelf.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      Pill(tr('market.you')),
                    ],
                  ],
                ),
                Text(
                  [
                    game.view.companyNames[shelf.company.index],
                    game.content.formats[shelf.format.index].name,
                    game.content.sites[shelf.site.index].name,
                    shelf.status == StoreStatus.building
                        ? tr('market.beingFitted')
                        : tr('market.nProducts', {'count': products}),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: LevelBar(shelf.area / biggest, color: accent),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tr('common.areaM2', {'area': shelf.area}),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Hours(open: shelf.openSlots),
        ],
      ),
    );
  }
}

/// Which slots of the day a store opens, as four marks.
class _Hours extends StatelessWidget {
  const _Hours({required this.open});

  final List<bool> open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: [
        for (final slot in DaySlot.values)
          if (open[slot.index]) slotName(slot),
      ].join(', '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final slot in DaySlot.values)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: open[slot.index]
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }
}

/// Starting a new business: a city, then a vacant site there to open a
/// store of any kind on.
class NewBusiness extends StatefulWidget {
  const NewBusiness({super.key, this.subsidiary = false});

  /// Whether this is a company of its own for the holding, the first store
  /// offered as such.
  final bool subsidiary;

  @override
  State<NewBusiness> createState() => _NewBusinessState();
}

class _NewBusinessState extends State<NewBusiness> {
  MarketId? _market;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final vacant = [
      for (final id in game.view.vacantSites) content.sites[id.index],
    ];
    final cities = [
      for (final market in content.markets)
        if (vacant.any((site) => site.market == market.id)) market,
    ];
    // The player's first city by default, while it has room.
    final home = game.myStores.firstOrNull?.$2.market;
    final market =
        _market ??
        (cities.any((city) => city.id == home) ? home : cities.firstOrNull?.id);
    return Section(
      title: widget.subsidiary
          ? tr('common.startSubsidiary')
          : tr('common.startBusiness'),
      children: [
        Hint(
          widget.subsidiary
              ? tr('market.subsidiaryHint')
              : tr('market.businessHint'),
        ),
        if (cities.isEmpty) Hint(tr('market.noVacant')),
        if (content.markets.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final city in cities)
                  ChoiceChip(
                    label: Text(city.name),
                    selected: city.id == market,
                    onSelected: (_) => setState(() => _market = city.id),
                  ),
              ],
            ),
          ),
        for (final site in vacant)
          if (site.market == market)
            _VacantSite(site: site, subsidiary: widget.subsidiary),
      ],
    );
  }
}

class _VacantSite extends StatelessWidget {
  const _VacantSite({required this.site, this.subsidiary = false});

  final SiteDef site;

  /// Whether to offer opening it as a company of its own.
  final bool subsidiary;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final level = game.view.macro.priceIndex;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(site.name),
      subtitle: Text(
        tr('market.vacantDetails', {
          'area': site.area,
          'most': site.maxArea,
          'location': percent(site.location, decimals: 0),
          'rent': money(site.rent.times(level), cents: false),
          'cost': money(site.openingCost.times(level), cents: false),
          'days': site.buildDays,
        }),
      ),
      trailing: OutlinedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => GameScope(
            controller: game,
            child: _OpenStoreDialog(site: site, subsidiary: subsidiary),
          ),
        ),
        child: Text(tr('market.open')),
      ),
    );
  }
}

class _OpenStoreDialog extends StatefulWidget {
  const _OpenStoreDialog({required this.site, this.subsidiary = false});

  final SiteDef site;

  /// Whether it opens as a company of its own unless the player says not.
  final bool subsidiary;

  @override
  State<_OpenStoreDialog> createState() => _OpenStoreDialogState();
}

class _OpenStoreDialogState extends State<_OpenStoreDialog> {
  late final _name = TextEditingController(
    text: tr('market.defaultStoreName', {'site': widget.site.name}),
  );
  final _capital = TextEditingController();
  late bool _newCompany = widget.subsidiary;
  FormatId _format = const FormatId(0);

  /// Whether to borrow: by default, when the company can't pay outright.
  bool? _borrow;
  late int _months = longestTerm(context.game.content);

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.company;
    final hasCompany =
        company != null && company.status == CompanyStatus.active;
    final separate = _newCompany || !hasCompany;
    // The formats this site is big enough for.
    final formats = [
      for (final format in game.content.formats)
        if (format.minArea <= widget.site.area) format,
    ];
    final cost = widget.site.openingCost
        .times(game.content.formats[_format.index].fitOut)
        .times(game.view.macro.priceIndex);
    final capital = _capital.text.isEmpty
        ? Money.zero
        : parseMoney(_capital.text);
    final view = game.view;
    final finance = game.content.finance;
    // What the company has beyond its bills, orders and cushion.
    final spare =
        (separate
            ? Money.zero
            : company.cash - company.committed - game.cushion(company)) +
        (capital ?? Money.zero);
    final short =
        cost - (separate ? Money.zero : company.cash) - (capital ?? Money.zero);
    final amount = roundedUp(cost - spare);
    final borrow = amount > Money.zero && (_borrow ?? short > Money.zero);
    final room = separate
        ? Money.zero
        : view.companyCredits[company.id.index] ?? Money.zero;
    // The capital put in no longer backs a guarantee.
    final guarantee =
        view.guaranteeRoom -
        (capital ?? Money.zero).times(finance.guaranteeMultiple);
    final terms = LoanTerms(
      view: view,
      content: game.content,
      amount: amount,
      credit: room.isNegative ? Money.zero : room,
      guarantee: guarantee.isNegative ? Money.zero : guarantee,
      months: _months,
      onMonths: (months) => setState(() => _months = months),
      note: separate ? tr('market.newCompanyNote') : null,
    );
    final ready = borrow ? terms.split != null : short <= Money.zero;
    return AlertDialog(
      title: Text(tr('market.openStoreAt', {'site': widget.site.name})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('market.fittingCosts', {
                'cost': money(cost),
                'days': widget.site.buildDays,
              }),
            ),
            if (formats.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final format in formats)
                    ChoiceChip(
                      avatar: Icon(formatIcon(format), size: 18),
                      label: Text(format.name),
                      selected: format.id == _format,
                      onSelected: (_) => setState(() => _format = format.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('common.storeName')),
            ),
            if (hasCompany)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market.asNewCompany')),
                subtitle: Text(
                  _newCompany
                      ? tr('market.ownBooks')
                      : tr('market.ownedBy', {
                          'company': game.view.companyNames[company.id.index],
                        }),
                ),
                value: _newCompany,
                onChanged: (on) => setState(() => _newCompany = on),
              ),
            TextField(
              controller: _capital,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('market.capitalFromCash'),
                helperText: tr('market.youHave', {
                  'cash': money(game.view.cash),
                }),
                errorText: capital == null ? tr('common.notAnAmount') : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (amount > Money.zero)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market.borrowFromBank')),
                subtitle: borrow
                    ? null
                    : Text(
                        short > Money.zero
                            ? tr('market.needsMore', {
                                'amount': money(short, cents: false),
                              })
                            : tr('market.keepCushion'),
                      ),
                value: borrow,
                onChanged: (on) => setState(() => _borrow = on),
              ),
            if (borrow) terms,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: capital == null || _name.text.trim().isEmpty || !ready
              ? null
              : () {
                  game.submit(
                    OpenStore(
                      game.player,
                      site: widget.site.id,
                      name: _name.text.trim(),
                      company: separate ? null : company.id,
                      capital: capital,
                      format: _format,
                      borrow: borrow ? amount : Money.zero,
                      termMonths: borrow ? _months : 0,
                    ),
                  );
                  Navigator.pop(context);
                },
          child: Text(borrow ? tr('market.openWithLoan') : tr('market.open')),
        ),
      ],
    );
  }
}
