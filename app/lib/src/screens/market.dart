import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../loans.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'national.dart';

/// The world outside: the country's economy on top, with its history a page
/// away, the player's patch, where to open next, then the competitors and the
/// cities, each a page of its own.
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
        if (game.content.countries.length > 1)
          const _Countries()
        else
          const _EconomySummary(country: CountryId(0)),
        const _YourPatch(),
        const _WhereToOpen(),
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

/// [amount] to the nearest thousand, for what is only an estimate.
String _roughly(Money amount) =>
    money(Money((amount.cents / 100000).round() * 100000), cents: false);

/// A page on what a shop of [format] might do in the market [key], then who
/// and what is there.
void _openNeighbourhood(
  BuildContext context,
  MarketDef market,
  FormatDef format,
) => context.openPage(
  market.name,
  (context) => [_Neighbourhood(marketKey: market.key, format: format)],
);

/// A neighbourhood's page: from its plan while it sleeps, from the game once
/// it wakes, which the player opening there does.
class _Neighbourhood extends StatelessWidget {
  const _Neighbourhood({required this.marketKey, required this.format});

  final String marketKey;
  final FormatDef format;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final awake = game.content.markets
        .where((market) => market.key == marketKey)
        .firstOrNull;
    final plan = awake == null ? game.plan : null;
    final market =
        awake ?? plan!.markets.firstWhere((market) => market.key == marketKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prospect(market: market, format: format, plan: plan),
        Section(
          title: tr('market.whoIsHere'),
          children: [
            if (plan == null)
              _City(market: market, open: true)
            else
              _PlannedCity(plan: plan, market: market),
          ],
        ),
      ],
    );
  }
}

/// Who and what is in a neighbourhood still asleep, and its free sites. Opening
/// on one wakes it.
class _PlannedCity extends StatelessWidget {
  const _PlannedCity({required this.plan, required this.market});

  final ContentDb plan;
  final MarketDef market;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final row = plan.neighbourhoods.indexWhere((r) => r.key == market.key);
    final taken = {
      for (final store in plan.stores)
        if (plan.sites[store.site.index].market == market.id) store.site.index,
    };
    final vacant = [
      for (final site in plan.sites)
        if (site.market == market.id && !taken.contains(site.id.index)) site,
    ];
    final sleeper = context.game.sleeper(row);
    if (sleeper == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MarketLines(content: plan, market: market),
        if (sleeper.opened > 0 || sleeper.closed > 0)
          Line(
            tr('market.openedClosed'),
            '${sleeper.opened} / ${sleeper.closed}',
          ),
        for (final shop in sleeper.shops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                TradeMark(
                  ledger.trade(plan.formats[shop.format.index]),
                  size: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name),
                      Text(
                        [
                          plan.formats[shop.format.index].name,
                          if (shop.sales.isNotEmpty)
                            tr('market.yearAbout', {
                              // A shop not a year old yet, at its pace.
                              'amount': _roughly(
                                Money(
                                  shop.yearSales.cents *
                                      12 ~/
                                      shop.sales.length,
                                ),
                              ),
                            }),
                        ].join(', '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Divider(),
        Text(tr('market.vacantSites'), style: theme.textTheme.titleSmall),
        for (final site in vacant) _VacantSite(site: site, wakeRow: row),
        Hint(tr('market.plannedHint')),
      ],
    );
  }
}

/// The player's own shops: what each earns, and what it sells against all that
/// households here spend on its trade. Its rivals are only those of its trade.
class _YourPatch extends StatelessWidget {
  const _YourPatch();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final stores = [
      for (final (_, store) in game.myStores)
        if (store.status != StoreStatus.closed) store,
    ];
    if (stores.isEmpty) return const SizedBox.shrink();
    return Section(
      title: tr('market.yourPatch'),
      children: [
        for (final store in stores)
          () {
            final market = content.markets[store.market.index];
            final format = content.formats[store.format.index];
            final (:revenue, :profit, :days) = store.recentMonths;
            final spending = tradeSpending(game.view, content, market, format);
            final known = days > 0 && spending > Money.zero;
            final share = known
                ? (revenue.cents * 365 / days / spending.cents * 100)
                      .clamp(0, 100)
                      .round()
                : 0;
            return IndexRow(
              title: game.view.shelves[store.id.index].name,
              subtitle: known
                  ? tr('market.patchLine', {
                      'city': market.name,
                      'share': percentOf(share),
                    })
                  : tr('market.patchTooSoon', {'city': market.name}),
              value: known ? money(profit, cents: false) : null,
              valueColor: known && profit.isNegative
                  ? Ledger.of(context).loss
                  : null,
              mark: Ledger.of(context).trade(format),
              onTap: () => _openNeighbourhood(context, market, format),
            );
          }(),
      ],
    );
  }
}

/// The neighbourhoods with room for a shop of the chosen trade, best first, by
/// what a new one on the best free site might earn.
class _WhereToOpen extends StatefulWidget {
  const _WhereToOpen();

  @override
  State<_WhereToOpen> createState() => _WhereToOpenState();
}

class _WhereToOpenState extends State<_WhereToOpen> {
  /// The most places shown before the player asks for them all.
  static const _shown = 8;

  FormatId? _format;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final content = game.content;
    final plan = game.plan;
    final vacant = [
      for (final id in view.vacantSites) content.sites[id.index],
      if (plan != null) ..._plannedVacant(plan, content),
    ];
    final formats = [
      for (final format in content.formats)
        if (vacant.any((site) => site.area >= format.minArea)) format,
    ];
    if (formats.isEmpty) return const SizedBox.shrink();
    // The player's own trade to begin with, while there's room for it.
    final wanted = _format ?? game.myStores.firstOrNull?.$2.format;
    final chosen = formats.firstWhere(
      (format) => format.id == wanted,
      orElse: () => formats.first,
    );
    final prospects = [
      ..._prospects(view, content, chosen),
      if (plan != null) ..._plannedProspects(view, plan, content, chosen),
    ]..sort((a, b) => b.$3.profit.cents.compareTo(a.$3.profit.cents));
    final shown = _all ? prospects : prospects.take(_shown);
    final ledger = Ledger.of(context);
    return Section(
      title: tr('market.whereToOpen'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final format in formats)
              ChoiceChip(
                label: Text(format.name),
                selected: format.id == chosen.id,
                onSelected: (_) => setState(() => _format = format.id),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (market, site, outlook) in shown)
          IndexRow(
            title: market.name,
            subtitle: [
              if (content.countries.length > 1)
                content.countries[market.country.index].name,
              tr('market.outlookLine', {
                'rent': money(
                  site.rent.times(view.economy(market.country).priceIndex),
                  cents: false,
                ),
                'rivals': outlook.rivals == 0
                    ? tr('market.noRivals')
                    : tr('market.nRivals', {'count': outlook.rivals}),
              }),
            ].join(' · '),
            value: _roughly(outlook.profit),
            valueColor: outlook.profit.isNegative ? ledger.loss : null,
            onTap: () => _openNeighbourhood(context, market, chosen),
          ),
        if (!_all && prospects.length > _shown)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text(tr('market.showAll', {'count': prospects.length})),
          ),
        Hint(tr('market.whereToOpenHint')),
      ],
    );
  }
}

/// For each market with a free site big enough for [format], that site which
/// would do best and what a new shop might do on it.
Iterable<(MarketDef, SiteDef, ShopOutlook)> _prospects(
  Observation view,
  ContentDb content,
  FormatDef format,
) sync* {
  for (final market in content.markets) {
    SiteDef? best;
    ShopOutlook? outlook;
    for (final id in view.vacantSites) {
      final site = content.sites[id.index];
      if (site.market != market.id || site.area < format.minArea) continue;
      final here = shopOutlook(view, content, site, format);
      if (outlook == null || here.profit > outlook.profit) {
        best = site;
        outlook = here;
      }
    }
    if (best != null) yield (market, best, outlook!);
  }
}

/// The sites free in [plan]'s neighbourhoods, those [content] doesn't hold yet.
Iterable<SiteDef> _plannedVacant(ContentDb plan, ContentDb content) sync* {
  final taken = {for (final store in plan.stores) store.site.index};
  for (final site in plan.sites.skip(content.sites.length)) {
    if (!taken.contains(site.id.index)) yield site;
  }
}

/// For each neighbourhood asleep with a free site big enough for [format], that
/// site which would do best and what a new shop might do on it.
Iterable<(MarketDef, SiteDef, ShopOutlook)> _plannedProspects(
  Observation view,
  ContentDb plan,
  ContentDb content,
  FormatDef format,
) sync* {
  final vacant = _plannedVacant(plan, content).toList();
  for (final market in plan.markets.skip(content.markets.length)) {
    SiteDef? best;
    ShopOutlook? outlook;
    for (final site in vacant) {
      if (site.market != market.id || site.area < format.minArea) continue;
      final here = shopOutlook(view, plan, site, format);
      if (outlook == null || here.profit > outlook.profit) {
        best = site;
        outlook = here;
      }
    }
    if (best != null) yield (market, best, outlook!);
  }
}

/// What a new shop of [format] might do in [market], by estimate; [plan] holds
/// the neighbourhood if it's still asleep.
class _Prospect extends StatelessWidget {
  const _Prospect({required this.market, required this.format, this.plan});

  final MarketDef market;
  final FormatDef format;
  final ContentDb? plan;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final content = game.content;
    final prospect =
        (plan == null
                ? _prospects(view, content, format)
                : _plannedProspects(view, plan!, content, format))
            .where((prospect) => prospect.$1.id == market.id)
            .firstOrNull;
    return Section(
      title: tr('market.prospectTitle', {'format': format.name}),
      mark: Ledger.of(context).trade(format),
      children: [
        Line(
          tr('market.spentHere'),
          tr('market.about', {
            'amount': _roughly(
              tradeSpending(view, plan ?? content, market, format),
            ),
          }),
        ),
        if (prospect case (_, final site, final outlook)) ...[
          Line(tr('market.bestSite'), site.name),
          Line(
            tr('market.newShopShare'),
            tr('market.about', {'amount': percent(outlook.share, decimals: 0)}),
          ),
          Line(
            tr('market.newShopSales'),
            tr('market.about', {'amount': _roughly(outlook.sales)}),
          ),
          Line(
            tr('market.newShopProfit'),
            tr('market.about', {'amount': _roughly(outlook.profit)}),
            strong: true,
            color: outlook.profit.isNegative ? Ledger.of(context).loss : null,
          ),
        ] else
          Hint(tr('market.noSiteFor')),
        Hint(tr('market.prospectHint')),
      ],
    );
  }
}

/// A country's economy at a glance: the turn of the cycle and its key
/// figures, and the way to its history.
class _EconomySummary extends StatelessWidget {
  const _EconomySummary({required this.country});

  final CountryId country;

  /// A multiple of the start as a change: ×1.0412 is +4.1%.
  static String _change(Fx multiple) =>
      '${multiple >= Fx.one ? '+' : '−'}${percent((multiple - Fx.one).abs())}';

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final macro = game.view.economy(country);
    final regime = game.content.macro.regimes[macro.regime.index];
    final many = game.content.countries.length > 1;
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
      title: many ? tr('market.economy') : tr('scenario.country'),
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
            many
                ? game.content.countries[country.index].name
                : tr('market.theEconomy'),
            (context) => [
              _EconomyCard(game: context.game, country: country),
              _EconomicHistory(country: country),
            ],
          ),
        ),
      ],
    );
  }
}

/// The countries of the game, for one that spans several: the central bank's
/// rate, then each country's turn of the cycle, its households and the
/// player's shops there, each the way to its page.
class _Countries extends StatelessWidget {
  const _Countries();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final mine = <int, int>{};
    for (final (_, store) in game.myStores) {
      if (store.status == StoreStatus.closed) continue;
      final country = content.countryOf(store.market).index;
      mine[country] = (mine[country] ?? 0) + 1;
    }
    final deepest = content.macro.regimes.reduce(
      (a, b) => b.demand < a.demand ? b : a,
    );
    return Section(
      title: tr('market.countries'),
      children: [
        Line(tr('market.centralBankRate'), percent(game.view.macro.policyRate)),
        for (final country in content.countries)
          () {
            final macro = game.view.economy(country.id);
            final regime = content.macro.regimes[macro.regime.index];
            final households = _nationalOf(game, country)?.totalHouseholds;
            return IndexRow(
              title: country.name,
              subtitle: [
                regime.name,
                if (households != null)
                  tr('market.nationalHouseholds', {
                    'count': decimalText(
                      (households / 1000000).toStringAsFixed(1),
                    ),
                  }),
                if (mine[country.id.index] case final shops?)
                  tr('market.yourShops', {'count': shops}),
              ].join(' · '),
              mark: regimeColor(regime),
              // Only the deepest phase, a recession, earns a stamp.
              stamp: regime == deepest ? regime.name : null,
              value: percent(macro.inflation),
              onTap: () => _openCountry(context, country),
            );
          }(),
        Hint(tr('market.countriesHint')),
      ],
    );
  }
}

/// [country] as its national statistics have it, run by formula; null
/// without them.
CountryState? _nationalOf(SimulationController game, CountryDef country) => game
    .national
    ?.countries
    .where((national) => national.def.key == country.national)
    .firstOrNull;

/// A country's page: its economy and taxes, its regions with the player's
/// shops run by formula there, its whole market by formula, and its places.
void _openCountry(BuildContext context, CountryDef country) => context.openPage(
  country.name,
  (context) => [
    _EconomySummary(country: country.id),
    _CountryTaxes(country: country),
    NationalMap(country: country.id),
    _NationalMarket(country: country),
    _CountryPlaces(country: country),
  ],
);

/// What a country takes: corporate tax on what shops make there, and
/// dividend tax from those who live there.
class _CountryTaxes extends StatelessWidget {
  const _CountryTaxes({required this.country});

  final CountryDef country;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final taxes = game.content.taxesOf(country.id);
    if (taxes == null) return const SizedBox.shrink();
    final level = game.view.economy(country.id).priceIndex;
    final flat =
        taxes.reducedRate == taxes.corporateRate ||
        taxes.reducedLimit == Money.zero;
    return Section(
      title: tr('finance.taxes'),
      children: [
        Line(
          tr('finance.corporateTax'),
          flat
              ? percent(taxes.corporateRate)
              : tr('finance.taxRates', {
                  'reduced': percent(taxes.reducedRate, decimals: 0),
                  'full': percent(taxes.corporateRate, decimals: 0),
                }),
          hint: flat
              ? null
              : tr('finance.taxRatesHint', {
                  'reduced': percent(taxes.reducedRate, decimals: 0),
                  'limit': money(taxes.reducedLimit.times(level), cents: false),
                }),
        ),
        Line(tr('finance.dividends'), percent(taxes.dividendRate)),
        Hint(tr('market.countryTaxesHint')),
      ],
    );
  }
}

/// A country's whole market by formula, trade by trade: what households
/// spend a year, how it moved, and the chains that share it, the player's
/// shops among them.
class _NationalMarket extends StatelessWidget {
  const _NationalMarket({required this.country});

  final CountryDef country;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final national = _nationalOf(game, country);
    final economy = game.national;
    if (national == null || economy == null) return const SizedBox.shrink();
    final content = game.content;
    // What the player's shops here sell a year, by the table's trade.
    final mine = <String, double>{};
    for (final (_, store) in game.myStores) {
      if (store.status == StoreStatus.closed ||
          content.countryOf(store.market) != country.id) {
        continue;
      }
      final trade = formatTrades[content.formats[store.format.index].key];
      final (:revenue, profit: _, :days) = store.recentMonths;
      if (trade == null || days == 0) continue;
      mine[trade] = (mine[trade] ?? 0) + revenue.cents * 365 / days;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (t, trade) in economy.table.trades.indexed)
          _NationalTrade(
            name: trMaybe('market.nationalTrades.${trade.key}') ?? trade.name,
            months: national.tradeMonths[t],
            chains: [
              for (final chain in national.chains)
                if (chain.def.trade == t && chain.isTrading) chain,
            ],
            mine: mine[trade.key],
          ),
        Hint(tr('market.nationalHint')),
      ],
    );
  }
}

/// One trade of a country's whole market.
class _NationalTrade extends StatelessWidget {
  const _NationalTrade({
    required this.name,
    required this.months,
    required this.chains,
    required this.mine,
  });

  final String name;
  final List<TradeMonth> months;
  final List<Chain> chains;

  /// What the player's shops sell a year in it, in cents; null for none.
  final double? mine;

  static int _sum(Iterable<TradeMonth> months) =>
      months.fold(0, (sum, month) => sum + month.market.cents);

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
    final count = months.length < 12 ? months.length : 12;
    final cents = _sum(months.skip(months.length - count));
    final yearly = cents * 12 / count;
    String? change;
    if (months.length >= 24) {
      final before = _sum(months.skip(months.length - 24).take(12));
      if (before > 0) {
        final moved = Fx.raw(((cents - before) * Fx.scale / before).round());
        change = tr('market.onTheYear', {
          'change': '${moved.isNegative ? '−' : '+'}${percent(moved.abs())}',
        });
      }
    }
    final last = months.last.market.cents;
    int sold(Chain chain) => chain.months.lastOrNull?.sales.cents ?? 0;
    final ranked = [...chains]
      ..sort((a, b) {
        final bySales = sold(b).compareTo(sold(a));
        return bySales != 0 ? bySales : a.def.name.compareTo(b.def.name);
      });
    // Whole points for chains; a shop's sliver of a country to its first
    // figure that isn't nought.
    String shareOf(double part) => percentOf(
      decimalText(
        part <= 0
            ? '0'
            : part >= 0.01
            ? (part * 100).toStringAsFixed(0)
            : (part * 100).toStringAsPrecision(1),
      ),
    );
    return Section(
      title: tr('market.nationalTitle', {
        'trade': name,
        'amount': _billions(yearly),
      }),
      children: [
        if (change != null) Hint(change),
        for (final chain in ranked)
          Line(
            chain.def.independent ? tr('market.independents') : chain.def.name,
            last == 0 ? '—' : shareOf(sold(chain) / last),
            hint: tr('common.stores', {'count': chain.stores}),
          ),
        if (mine case final sales? when yearly > 0)
          Line(tr('market.you'), shareOf(sales / yearly), strong: true),
      ],
    );
  }
}

/// [cents] a year, in billions or millions of euros, as the statistics
/// count.
String _billions(double cents) {
  final euros = cents / 100;
  return euros >= 1e9
      ? tr('market.billions', {
          'count': decimalText((euros / 1e9).toStringAsFixed(0)),
        })
      : tr('market.millions', {
          'count': decimalText((euros / 1e6).toStringAsFixed(0)),
        });
}

/// A country's cities and their districts: those played in full and those
/// run by formula until someone opens there, each the way to its page.
class _CountryPlaces extends StatelessWidget {
  const _CountryPlaces({required this.country});

  final CountryDef country;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final here = {
      for (final (_, store) in game.myStores)
        if (store.status != StoreStatus.closed)
          content.markets[store.market.index].key,
    };
    final places = <({String key, String name, bool awake})>[
      for (final market in content.markets)
        if (market.country == country.id)
          (key: market.key, name: market.name, awake: true),
      for (final (i, row) in content.neighbourhoods.indexed)
        if (row.country == country.id && game.sleeper(i) != null)
          (key: row.key, name: row.name, awake: false),
    ];
    final format =
        content.formats[(game.myStores.firstOrNull?.$2.format ??
                content.formats.first.id)
            .index];
    final cities = <String, List<({String key, String name, bool awake})>>{};
    for (final place in places) {
      (cities[_cityPart(place.name)] ??= []).add(place);
    }
    return Section(
      title: tr('market.cities'),
      children: [
        for (final MapEntry(key: city, value: districts) in cities.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(city, style: theme.textTheme.titleSmall),
          ),
          for (final place in districts)
            IndexRow(
              title: _districtPart(place.name),
              subtitle: [
                place.awake
                    ? tr('market.playedInFull')
                    : tr('market.runByFormula'),
                if (here.contains(place.key)) tr('market.youTradeHere'),
              ].join(' · '),
              onTap: () => context.openPage(
                place.name,
                (context) => [
                  _Neighbourhood(marketKey: place.key, format: format),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// "Lyon" of "Lyon, Part-Dieu".
String _cityPart(String name) => name.split(',').first.trim();

/// "Part-Dieu" of "Lyon, Part-Dieu", or the whole name without a district.
String _districtPart(String name) {
  final comma = name.indexOf(',');
  return comma < 0 ? name : name.substring(comma + 1).trim();
}

/// The economy month by month: inflation, the central bank's rate and
/// unemployment as lines, prices and wages against the start, and the
/// phases of the cycle.
class _EconomicHistory extends StatelessWidget {
  const _EconomicHistory({required this.country});

  final CountryId country;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final history = game.view.historyOf(country);
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
    // A chain's shops in the districts it trades in beyond the game's.
    final away = <int, List<(DistrictView, DistrictShop)>>{};
    for (final district in view.districts) {
      for (final shop in district.shops) {
        if (shop.company case final id?) {
          (away[id.index] ??= []).add((district, shop));
          byCompany[id.index] ??= [];
        }
      }
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
            away: away[company] ?? const [],
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
    required this.away,
    required this.mine,
  });

  final CompanyId company;
  final List<ShelfView> shelves;

  /// Its shops in districts beyond the game's, with each one's district.
  final List<(DistrictView, DistrictShop)> away;
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
    final formats = {
      for (final s in shelves) s.format,
      for (final (_, shop) in away) shop.format,
    };
    final cities = {for (final s in shelves) s.market};
    final districts = {for (final (district, _) in away) district.row};
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
          tr('common.stores', {'count': shelves.length + away.length}),
          if (last != null)
            tr('market.salesLine', {
              'amount': money(last.revenue, cents: false),
            }),
          if (content.markets.length > 1 || districts.isNotEmpty)
            tr('common.cities', {'count': cities.length + districts.length}),
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
        for (final (district, shop) in away)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                TradeMark(
                  Ledger.of(context).trade(content.formats[shop.format.index]),
                  size: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name),
                      Text(
                        '${content.formats[shop.format.index].name}, '
                        '${district.name}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  /// The brand to put it under; none keeps its name.
  BrandId? _brand;

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
            if ([
                  for (final brand in game.myBrands)
                    if (brand.format == shelf.format) brand,
                ]
                case final brands when brands.isNotEmpty)
              _BrandChoice(
                brands: brands,
                market: game.content.markets[shelf.market.index],
                chosen: _brand,
                noBrandHint: tr('market.noBrandBuy'),
                onChanged: (id) => setState(() => _brand = id),
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
                      brand: _brand,
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

/// The player's [brands] for a shop in [market], or none: a brand names the
/// shop after itself and its district.
class _BrandChoice extends StatelessWidget {
  const _BrandChoice({
    required this.brands,
    required this.market,
    required this.chosen,
    required this.noBrandHint,
    required this.onChanged,
  });

  final List<BrandView> brands;
  final MarketDef market;
  final BrandId? chosen;

  /// What happens to the name without a brand.
  final String noBrandHint;
  final ValueChanged<BrandId?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = brands.where((brand) => brand.id == chosen).firstOrNull;
    final comma = market.name.lastIndexOf(', ');
    final district = comma < 0 ? market.name : market.name.substring(comma + 2);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('market.brand'), style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final brand in brands)
                ChoiceChip(
                  label: Text(brand.name),
                  selected: brand.id == chosen,
                  onSelected: (_) => onChanged(brand.id),
                ),
              ChoiceChip(
                label: Text(tr('market.noBrand')),
                selected: picked == null,
                onSelected: (_) => onChanged(null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            picked == null
                ? noBrandHint
                : tr('market.brandNamed', {'name': '${picked.name} $district'}),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
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
        game.economyAt(shelf.market).priceIndex *
        content.markets[shelf.market.index].priceLevel;
    var sum = 0;
    var listed = 0;
    for (final product in content.products) {
      final price = shelf.prices[product.id.index];
      if (price == null) continue;
      final reference = content
          .referenceIn(product, content.countryOf(shelf.market))
          .times(level);
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
  const _EconomyCard({required this.game, required this.country});

  final SimulationController game;
  final CountryId country;

  @override
  Widget build(BuildContext context) {
    final macro = game.view.economy(country);
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
      for (final country in game.content.countries)
        if (game.content.markets.any((m) => m.country == country.id)) ...[
          if (game.content.countries.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                country.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          for (final market in game.content.markets)
            if (market.country == country.id) _City(market: market),
        ],
    ],
  );
}

/// One city: what living and trading there costs, its market by trade, its
/// stores and its vacant sites. Cities where the player trades start open.
class _City extends StatelessWidget {
  const _City({required this.market, this.open = false});

  final MarketDef market;

  /// Whether it starts open wherever the player trades.
  final bool open;

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
    String level(Fx value) => value == Fx.one
        ? tr('market.asUsual')
        : '${value < Fx.one ? '−' : '+'}'
              '${percent((value - Fx.one).abs(), decimals: 0)}';
    return ExpansionTile(
      // Its own key, so its open state isn't confused with the list's
      // scroll position in the page storage.
      key: PageStorageKey('city ${market.key}'),
      initiallyExpanded: open || here || content.markets.length == 1,
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
        _MarketLines(
          content: content,
          market: market,
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

/// What households in [market] spend a year on each trade at today's
/// prices, the player's share of the trades they're in there, and how the
/// market moved at the last census: none for a place asleep.
class _MarketLines extends StatelessWidget {
  const _MarketLines({
    required this.content,
    required this.market,
    this.censuses,
  });

  final ContentDb content;
  final MarketDef market;
  final List<Census>? censuses;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    // The player's sales here a year, by channel, at their recent pace.
    final yours = List.filled(content.channelCount, 0);
    for (final (_, store) in game.myStores) {
      if (store.market != market.id || store.status == StoreStatus.closed) {
        continue;
      }
      final (:revenue, profit: _, :days) = store.recentMonths;
      if (days == 0) continue;
      yours[content.formatChannels[store.format.index]] +=
          revenue.cents * 365 ~/ days;
    }
    final latest = censuses?.last;
    final previous = switch (censuses) {
      final list? when list.length > 1 => list[list.length - 2],
      _ => null,
    };
    final change =
        latest == null || previous == null || previous.households == 0
        ? null
        : Fx.raw(
            ((latest.households - previous.households) *
                    Fx.scale /
                    previous.households)
                .round(),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var channel = 0; channel < content.channelCount; channel++)
          () {
            final amount = channelSpending(view, content, market, channel);
            if (amount <= Money.zero) return const SizedBox.shrink();
            final format = content.formats.firstWhere(
              (format) => content.formatChannels[format.id.index] == channel,
            );
            final share = yours[channel] == 0
                ? null
                : Fx.raw((yours[channel] * Fx.scale / amount.cents).round());
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  TradeMark(ledger.trade(format), size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trMaybe('market.trades.${format.key}') ?? format.name,
                        ),
                        // Under its name, so a long one still fits a phone.
                        if (share != null)
                          Text(
                            tr('market.yourShare', {
                              'share': percent(
                                share > Fx.one ? Fx.one : share,
                                decimals: 0,
                              ),
                            }),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    _roughly(amount),
                    style: figures(theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            );
          }(),
        Text(
          switch ((latest, change)) {
            (null, _) => tr('market.marketHintAsleep'),
            (_, null) => tr('market.marketHintFirst'),
            (_, final rate?) => tr('market.marketHint', {
              'change': '${rate.isNegative ? '' : '+'}${percent(rate)}',
            }),
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: change == null
                ? theme.colorScheme.onSurfaceVariant
                : gainColor(context, change.raw.sign) ??
                      theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
  const _VacantSite({
    required this.site,
    this.subsidiary = false,
    this.wakeRow,
  });

  final SiteDef site;

  /// Whether to offer opening it as a company of its own.
  final bool subsidiary;

  /// The neighbourhood asleep that opening here would wake, if any.
  final int? wakeRow;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final level = game.economyAt(site.market).priceIndex;
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
            child: _OpenStoreDialog(
              site: site,
              subsidiary: subsidiary,
              wakeRow: wakeRow,
            ),
          ),
        ),
        child: Text(tr('market.open')),
      ),
    );
  }
}

class _OpenStoreDialog extends StatefulWidget {
  const _OpenStoreDialog({
    required this.site,
    this.subsidiary = false,
    this.wakeRow,
  });

  final SiteDef site;

  /// The neighbourhood asleep that opening here wakes, if any.
  final int? wakeRow;

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

  /// The brand picked, once the player has picked; before that, their first
  /// for the type of business.
  BrandId? _brand;
  bool _brandPicked = false;

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
        .times(game.economyAt(widget.site.market).priceIndex);
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
    // A site asleep is in the plan, not yet in the game's content.
    final source = widget.wakeRow != null
        ? (game.plan ?? game.content)
        : game.content;
    final market = source.markets[widget.site.market.index];
    final brands = [
      for (final brand in game.myBrands)
        if (brand.format == _format) brand,
    ];
    final brand = _brandPicked
        ? brands.where((brand) => brand.id == _brand).firstOrNull
        : brands.firstOrNull;
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
            if (brands.isNotEmpty)
              _BrandChoice(
                brands: brands,
                market: market,
                chosen: brand?.id,
                noBrandHint: tr('market.noBrandOpen'),
                onChanged: (id) => setState(() {
                  _brand = id;
                  _brandPicked = true;
                }),
              ),
            if (brand == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: tr('common.storeName')),
                onChanged: (_) => setState(() {}),
              ),
            ],
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
          onPressed:
              capital == null ||
                  (brand == null && _name.text.trim().isEmpty) ||
                  !ready
              ? null
              : () {
                  // The site's number is only settled once it has woken.
                  var site = widget.site.id;
                  if (widget.wakeRow case final row?) {
                    game.wake(row);
                    site = game.content.sites
                        .firstWhere((other) => other.key == widget.site.key)
                        .id;
                  }
                  game.submit(
                    OpenStore(
                      game.player,
                      site: site,
                      name: brand?.name ?? _name.text.trim(),
                      company: separate ? null : company.id,
                      capital: capital,
                      format: _format,
                      borrow: borrow ? amount : Money.zero,
                      termMonths: borrow ? _months : 0,
                      brand: brand?.id,
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
