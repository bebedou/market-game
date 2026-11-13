import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';

/// A country's regions for one trade at a time: the player's shops run by
/// formula there, their share and sales and where they rank, a tile for
/// each region shaded by their share and marked with their shops, and where
/// a new shop would earn most. A region's tile opens its page.
class NationalMap extends StatefulWidget {
  const NationalMap({super.key, required this.country});

  final CountryId country;

  @override
  State<NationalMap> createState() => _NationalMapState();
}

class _NationalMapState extends State<NationalMap> {
  int? _trade;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final national = nationalOf(game, widget.country);
    final economy = game.national;
    if (national == null || economy == null || national.def.regions.isEmpty) {
      return const SizedBox.shrink();
    }
    final trades = economy.table.trades;
    final trade = _trade ?? _usualTrade(game, national);
    final name = tradeName(trades[trade].key, trades[trade].name);
    final ours = _Ours.of(national, trade);
    final regions = national.def.regions;
    final market = national.markets[trade].fold(
      Money.zero,
      (sum, m) => sum + m,
    );
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final room = _room(game, national, trade);
    // Where the player's shops rank among the chains of the trade.
    final rivals = [
      for (final chain in national.chains)
        if (chain.trade == trade && !chain.independent && chain.stores > 0)
          chain.yearSales,
    ];
    final rank = 1 + rivals.where((sales) => sales > ours.yearSales).length;
    final year = game.today.date.year;
    var opened = 0;
    var closed = 0;
    for (final block in ours.blocks) {
      for (final month in block.months) {
        if (month.start.date.year != year) continue;
        opened += month.opened;
        closed += month.closed;
      }
    }
    return Section(
      title: tr('market.regionsTitle'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (t, option) in trades.indexed)
              ChoiceChip(
                label: Text(tradeName(option.key, option.name)),
                selected: t == trade,
                onSelected: (_) => setState(() => _trade = t),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Line(tr('market.regionsShops'), '${ours.stores}', strong: true),
        if (ours.stores > 0) ...[
          Line(
            tr('market.shareOf', {'trade': name.toLowerCase()}),
            tinyShare(ours.yearSales, market),
          ),
          Line(tr('market.salesAYear'), money(ours.yearSales, cents: false)),
          Line(
            tr('market.profitAYear'),
            signedMoney(ours.yearProfit, cents: false),
            color: gainColor(context, ours.yearProfit.cents.sign),
          ),
          Line(
            tr('market.rankAmongChains'),
            tr('market.rankOf', {'rank': rank, 'count': rivals.length + 1}),
          ),
          Line(
            tr('market.openedThisYear'),
            tr('market.openedAndClosed', {'opened': opened, 'closed': closed}),
          ),
        ],
        const SizedBox(height: 10),
        _TileMap(
          regions: regions,
          shops: ours.shops,
          shares: [
            for (final (r, sales) in ours.sales.indexed)
              national.markets[trade][r].cents == 0
                  ? 0.0
                  : sales.cents / national.markets[trade][r].cents,
          ],
          ink: ledger.ink,
          paper: ledger.paper,
          muted: ledger.muted,
          onTap: (r) => openRegion(context, widget.country, trade, r),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr('market.tileKey'),
            style: theme.textTheme.bodySmall?.copyWith(color: ledger.muted),
          ),
        ),
        if (room.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tr('market.whereRoom'), style: theme.textTheme.titleSmall),
          for (final (:region, :profit, :months) in room.take(3))
            Line(
              regions[region].name,
              signedMoney(profit, cents: false),
              color: ledger.gain,
              hint: tr('market.paysBackIn', {'count': months}),
            ),
          Hint(tr('market.whereRoomHint')),
        ],
        Hint(tr('market.regionsHint')),
      ],
    );
  }
}

/// The national figures by formula for the game's [country], as the player
/// sees them; null without them.
NationalCountryView? nationalOf(SimulationController game, CountryId country) =>
    game.view.national.where((n) => n.country == country).firstOrNull;

/// A national trade's name in the language in use, by its [key] in the
/// national table, else its [name] there.
String tradeName(String key, String name) =>
    trMaybe('market.nationalTrades.$key') ?? name;

/// The trade to show first: the player's shops run by formula, else those
/// they run by hand there, else the first.
int _usualTrade(SimulationController game, NationalCountryView national) {
  if (national.blocks.firstOrNull case final block?) return block.trade;
  final content = game.content;
  for (final (_, store) in game.myStores) {
    if (store.status == StoreStatus.closed) continue;
    if (national.tradeOf(content, store.format) case final trade?) {
      return trade;
    }
  }
  return 0;
}

/// The player's shops run by formula in one trade of a country, all their
/// companies' together, region by region.
final class _Ours {
  _Ours(this.blocks, int regions)
    : shops = List.filled(regions, 0),
      sales = List.filled(regions, Money.zero),
      profit = List.filled(regions, Money.zero),
      pending = List.filled(regions, 0) {
    for (final block in blocks) {
      for (final (r, region) in block.regions.indexed) {
        shops[r] += region.trading + region.pending;
        pending[r] += region.pending;
        sales[r] += region.yearSales;
        profit[r] += region.yearProfit;
      }
    }
  }

  factory _Ours.of(NationalCountryView national, int trade) => _Ours([
    for (final block in national.blocks)
      if (block.trade == trade) block,
  ], national.def.regions.length);

  final List<CompanyBlockView> blocks;

  /// Shops trading or being fitted out, by region.
  final List<int> shops;
  final List<int> pending;
  final List<Money> sales;
  final List<Money> profit;

  int get stores => shops.fold(0, (sum, n) => sum + n);
  Money get yearSales => sales.fold(Money.zero, (sum, m) => sum + m);
  Money get yearProfit => profit.fold(Money.zero, (sum, m) => sum + m);
}

/// Who a new shop of [trade] in a country would be for, of what kind and
/// run how: the player's shops run by formula there, else the company
/// looked at with a shop of that kind or a director's strategy for it, else
/// the trade's first kind of shop, run as its balanced strategy has it.
({CompanyId company, FormatId format, StrategyId strategy})? _newShopFor(
  SimulationController game,
  NationalCountryView national,
  int trade,
) {
  final content = game.content;
  for (final block in national.blocks) {
    if (block.trade == trade) {
      return (
        company: block.company,
        format: block.format,
        strategy: block.strategy,
      );
    }
  }
  final company = game.company;
  FormatId? format;
  for (final store in company?.stores ?? const <StoreView>[]) {
    if (store.status != StoreStatus.closed &&
        national.tradeOf(content, store.format) == trade) {
      format = store.format;
      break;
    }
  }
  final director = company == null ? null : game.directorOf(company);
  if (format == null &&
      director != null &&
      national.tradeOf(
            content,
            content.strategies[director.strategy.index].format,
          ) ==
          trade) {
    format = content.strategies[director.strategy.index].format;
  }
  format ??= [
    for (final option in content.formats)
      if (national.tradeOf(content, option.id) == trade) option.id,
  ].firstOrNull;
  if (format == null) return null;
  final strategies = [
    for (final option in content.strategies)
      if (option.format == format) option,
  ];
  if (strategies.isEmpty) return null;
  final strategy =
      director != null &&
          content.strategies[director.strategy.index].format == format
      ? director.strategy
      : strategies
            .firstWhere(
              (s) => s.marketPosition == Fx.zero,
              orElse: () => strategies.first,
            )
            .id;
  // Without a company yet, as a newcomer's first shop would.
  return (
    company: company?.id ?? const CompanyId(-1),
    format: format,
    strategy: strategy,
  );
}

/// Each region where a new shop of [trade] would earn, soonest paid back
/// first: what it would add a year, and how soon its fitting out, at the
/// region's costs, would pay back.
List<({int region, Money profit, int months})> _room(
  SimulationController game,
  NationalCountryView national,
  int trade,
) {
  final shop = _newShopFor(game, national, trade);
  if (shop == null) return const [];
  final content = game.content;
  final room = [
    for (final (r, _) in national.def.regions.indexed)
      if (national.newShop(
            content,
            company: shop.company,
            format: shop.format,
            strategy: shop.strategy,
            region: r,
          )
          case (sales: _, :final profit) when profit > Money.zero)
        (
          region: r,
          profit: profit,
          months:
              (national.fitOut(content, shop.format, r).cents * 12 +
                  profit.cents -
                  1) ~/
              profit.cents,
        ),
  ];
  // As a director would see them: soonest paid back first.
  room.sort((a, b) {
    final byMonths = a.months.compareTo(b.months);
    if (byMonths != 0) return byMonths;
    final byProfit = b.profit.cents.compareTo(a.profit.cents);
    return byProfit != 0 ? byProfit : a.region - b.region;
  });
  return room;
}

/// [part] of [whole] as a percentage, to its first figure that isn't
/// nought when small: a few shops are a sliver of a country.
String tinyShare(Money part, Money whole) {
  if (whole.cents <= 0 || part.cents <= 0) return percentOf(decimalText('0'));
  final share = part.cents * 100 / whole.cents;
  return percentOf(
    decimalText(
      share >= 10
          ? share.toStringAsFixed(0)
          : share >= 0.1
          ? share.toStringAsFixed(1)
          : share.toStringAsPrecision(1),
    ),
  );
}

/// "HF" for Hauts-de-France, "PACA" for Provence-Alpes-Côte d'Azur, "Bay"
/// for Bayern: the capitals of a name of several words, the first three
/// letters of one, four where three would be [taken].
String regionMark(String name, Set<String> taken) {
  final words = name
      .split(RegExp(r"[\s\-]+"))
      .map((w) => w.contains("'") ? w.substring(w.indexOf("'") + 1) : w)
      .where((w) => w.isNotEmpty)
      .toList();
  final capitals = [
    for (final word in words)
      if (word[0] != word[0].toLowerCase()) word[0],
  ];
  if (capitals.length > 1) return capitals.join();
  final word = words.first;
  final short = word.length <= 3 ? word : word.substring(0, 3);
  return taken.contains(short) && word.length > 3
      ? word.substring(0, 4)
      : short;
}

/// The regions as tiles laid out roughly as on a map, each shaded by
/// [shares] against the most and marked with [shops].
class _TileMap extends StatelessWidget {
  const _TileMap({
    required this.regions,
    required this.shops,
    required this.shares,
    required this.ink,
    required this.paper,
    required this.muted,
    required this.onTap,
  });

  final List<NationalRegion> regions;
  final List<int> shops;
  final List<double> shares;
  final Color ink;
  final Color paper;
  final Color muted;
  final void Function(int region) onTap;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var cols = 1;
    var rows = 1;
    for (final region in regions) {
      if (region.col + 1 > cols) cols = region.col + 1;
      if (region.row + 1 > rows) rows = region.row + 1;
    }
    // Marks, the first of a short name taking it before the next.
    final taken = <String>{};
    final marks = [
      for (final region in regions)
        () {
          final mark = regionMark(region.name, taken);
          taken.add(mark);
          return mark;
        }(),
    ];
    final most = shares.fold(0.0, (a, b) => b > a ? b : a);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = (constraints.maxWidth - _gap * (cols - 1)) / cols;
        final tile = room < 64 ? room : 64.0;
        final width = cols * tile + (cols - 1) * _gap;
        return Center(
          child: SizedBox(
            width: width,
            height: rows * tile + (rows - 1) * _gap,
            child: Stack(
              children: [
                for (final (r, region) in regions.indexed)
                  Positioned(
                    left: region.col * (tile + _gap),
                    top: region.row * (tile + _gap),
                    width: tile,
                    height: tile,
                    child: () {
                      // Light paper for none; ink deepening with the share.
                      final depth = most <= 0 || shares[r] <= 0
                          ? 0.04
                          : 0.10 + 0.70 * shares[r] / most;
                      final dark = depth > 0.45;
                      return Semantics(
                        button: true,
                        label: tr('market.tileLabel', {
                          'region': region.name,
                          'count': shops[r],
                        }),
                        excludeSemantics: true,
                        child: Material(
                          color: Color.alphaBlend(
                            ink.withValues(alpha: depth),
                            paper,
                          ),
                          shape: Border.all(
                            color: ink.withValues(alpha: 0.6),
                            width: 0.5,
                          ),
                          child: InkWell(
                            onTap: () => onTap(r),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  marks[r],
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: figures(
                                    theme.textTheme.labelSmall,
                                  ).copyWith(color: dark ? paper : muted),
                                ),
                                Text(
                                  '${shops[r]}',
                                  style: figures(
                                    theme.textTheme.bodyMedium,
                                  ).copyWith(color: dark ? paper : ink),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens region [region] of the game's [country] for [trade]: its
/// households, market and shops, the player's there, the chains', and what
/// a new shop would earn.
void openRegion(
  BuildContext context,
  CountryId country,
  int trade,
  int region,
) {
  final national = nationalOf(context.game, country);
  if (national == null) return;
  context.openPage(
    national.def.regions[region].name,
    (context) => [
      _RegionFigures(country: country, trade: trade, region: region),
    ],
  );
}

class _RegionFigures extends StatelessWidget {
  const _RegionFigures({
    required this.country,
    required this.trade,
    required this.region,
  });

  final CountryId country;
  final int trade;
  final int region;

  /// [level] against the country's as a change: 0.9 is −10%.
  static String _against(Fx level) =>
      '${level >= Fx.one ? '+' : '−'}${percent((level - Fx.one).abs(), decimals: 0)}';

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final national = nationalOf(game, country);
    final economy = game.national;
    if (national == null || economy == null) return const SizedBox.shrink();
    final r = region;
    final trades = economy.table.trades;
    final name = tradeName(trades[trade].key, trades[trade].name);
    final ours = _Ours.of(national, trade);
    final market = national.markets[trade][r];
    final room = _room(game, national, trade);
    final next = room.where((option) => option.region == r).firstOrNull;
    final chains = [
      for (final chain in national.chains)
        if (chain.trade == trade && chain.regional[r] > 0) chain,
    ]..sort((a, b) => b.regional[r].compareTo(a.regional[r]));
    final ledger = Ledger.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('market.regionMarket', {
            'region': national.def.regions[r].name,
            'trade': name,
          }),
          children: [
            Line(tr('market.regionHouseholds'), _count(national.households[r])),
            Line(tr('market.regionSpend'), yearlyAmount(market)),
            Line(tr('market.regionStores'), _count(national.stores[trade][r])),
            Line(tr('market.regionWages'), _against(national.wageLevels[r])),
            Line(tr('market.regionRents'), _against(national.rentLevels[r])),
          ],
        ),
        Section(
          title: tr('market.regionYours'),
          children: [
            Line(
              tr('market.regionsShops'),
              '${ours.shops[r]}',
              strong: true,
              hint: ours.pending[r] > 0
                  ? tr('market.fittingOutCount', {'count': ours.pending[r]})
                  : null,
            ),
            if (ours.shops[r] > 0) ...[
              Line(
                tr('market.shareOf', {'trade': name.toLowerCase()}),
                tinyShare(ours.sales[r], market),
              ),
              Line(tr('market.salesAYear'), money(ours.sales[r], cents: false)),
              Line(
                tr('market.profitAYear'),
                signedMoney(ours.profit[r], cents: false),
                color: gainColor(context, ours.profit[r].cents.sign),
              ),
            ],
            if (next != null)
              Line(
                tr('market.newShopEarns'),
                signedMoney(next.profit, cents: false),
                color: ledger.gain,
                hint: tr('market.paysBackIn', {'count': next.months}),
              )
            else
              Line(tr('market.newShopEarns'), '—'),
          ],
        ),
        Section(
          title: tr('market.regionChains'),
          children: [
            for (final chain in chains)
              Line(
                chain.independent ? tr('market.independents') : chain.name,
                _count(chain.regional[r]),
              ),
            Hint(
              chains.isEmpty
                  ? tr('market.noChainsHere')
                  : tr('market.chainsHereHint'),
            ),
          ],
        ),
      ],
    );
  }
}

/// [n] with the language's thousands separators.
String _count(int n) => money(Money(n * 100), cents: false);

/// A market's year in billions, or millions, of euros, as the statistics
/// count.
String yearlyAmount(Money amount) {
  final euros = amount.cents / 100;
  return euros >= 1e9
      ? tr('market.billions', {
          'count': decimalText((euros / 1e9).toStringAsFixed(1)),
        })
      : tr('market.millions', {
          'count': decimalText(
            (euros / 1e6).toStringAsFixed(euros >= 1e8 ? 0 : 1),
          ),
        });
}
