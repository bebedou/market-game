import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../outlines.dart';
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
        for (final offer in national.offers)
          _OfferRow(country: widget.country, offer: offer),
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
          for (final block in ours.blocks)
            _BlockWorth(country: widget.country, block: block),
        ],
        const SizedBox(height: 10),
        if (outlineOf(national.def.key) case final outline?)
          _InkMap(
            outline: outline,
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

/// The regions as an ink map, as in the country's outline, each shaded
/// by [shares] against the most and marked with [shops] where it has any;
/// a region tapped opens its page.
class _InkMap extends StatelessWidget {
  const _InkMap({
    required this.outline,
    required this.regions,
    required this.shops,
    required this.shares,
    required this.ink,
    required this.paper,
    required this.muted,
    required this.onTap,
  });

  final CountryOutline outline;
  final List<NationalRegion> regions;
  final List<int> shops;
  final List<double> shares;
  final Color ink;
  final Color paper;
  final Color muted;
  final void Function(int region) onTap;

  /// How deep the ink of region [r] is: light paper for none, deepening
  /// with its share.
  double _depth(int r, double most) =>
      most <= 0 || shares[r] <= 0 ? 0.04 : 0.10 + 0.70 * shares[r] / most;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = shares.fold(0.0, (a, b) => b > a ? b : a);
    // Larger regions first, so the smaller inside them are drawn over them.
    final order =
        [
          for (final (r, region) in regions.indexed)
            if (outline.regions.containsKey(region.key)) r,
        ]..sort(
          (a, b) => outline.regions[regions[b].key]!.area.compareTo(
            outline.regions[regions[a].key]!.area,
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 440 ? constraints.maxWidth : 440.0;
        final scale = width / outline.width;
        final height = outline.height * scale;
        // The smallest region under a touch, as the smaller lie on top.
        int? hit(Offset local) {
          final point = local / scale;
          for (final r in order.reversed) {
            if (outline.regions[regions[r].key]!.path.contains(point)) return r;
          }
          return null;
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (hit(details.localPosition) case final r?) onTap(r);
            },
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _InkPainter(
                        outline: outline,
                        paths: [
                          for (final r in order)
                            (
                              path: outline.regions[regions[r].key]!.path,
                              depth: _depth(r, most),
                            ),
                        ],
                        scale: scale,
                        ink: ink,
                        paper: paper,
                        muted: muted,
                      ),
                    ),
                  ),
                  for (final r in order)
                    Positioned(
                      left:
                          outline.regions[regions[r].key]!.label.dx * scale -
                          22,
                      top:
                          outline.regions[regions[r].key]!.label.dy * scale -
                          10,
                      width: 44,
                      height: 20,
                      child: IgnorePointer(
                        child: Semantics(
                          label: tr('market.tileLabel', {
                            'region': regions[r].name,
                            'count': shops[r],
                          }),
                          excludeSemantics: true,
                          child: Center(
                            child: shops[r] == 0
                                ? const SizedBox.shrink()
                                : Text(
                                    '${shops[r]}',
                                    style: figures(theme.textTheme.labelSmall)
                                        .copyWith(
                                          color: _depth(r, most) > 0.45
                                              ? paper
                                              : ink,
                                        ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws an ink map: each region filled with ink at its depth over the
/// paper and ruled round in ink, and the box of any inset.
class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.outline,
    required this.paths,
    required this.scale,
    required this.ink,
    required this.paper,
    required this.muted,
  });

  final CountryOutline outline;
  final List<({Path path, double depth})> paths;
  final double scale;
  final Color ink;
  final Color paper;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 / scale
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    for (final (:path, :depth) in paths) {
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = Color.alphaBlend(ink.withValues(alpha: depth), paper),
        )
        ..drawPath(path, line);
    }
    if (outline.inset case final box?) {
      canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 / scale
          ..color = muted,
      );
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
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

/// What a company's shops run by formula in one trade are worth, and the
/// way to sell them to the chain that would buy them.
class _BlockWorth extends StatelessWidget {
  const _BlockWorth({required this.country, required this.block});

  final CountryId country;
  final CompanyBlockView block;

  @override
  Widget build(BuildContext context) {
    final value = block.value;
    if (value == null) return const SizedBox.shrink();
    final buyer = block.buyer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Line(
          block.name == null
              ? tr('market.worth')
              : tr('market.worthOf', {'chain': block.name}),
          money(value.price, cents: false),
          hint: buyer == null
              ? tr('market.noBuyer')
              : tr('market.buyerWouldBe', {'chain': buyer}),
        ),
        if (buyer != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _sell(context, buyer, value.price),
              child: Text(tr('market.sellShops', {'count': block.stores})),
            ),
          ),
      ],
    );
  }

  Future<void> _sell(BuildContext context, String buyer, Money price) async {
    final game = context.game;
    final confirmed = await _confirm(
      context,
      title: tr('market.sellTitle', {'chain': buyer}),
      body: tr('market.sellBody', {
        'count': block.stores,
        'price': money(price, cents: false),
      }),
      action: tr('market.sellAction'),
    );
    if (!confirmed) return;
    game.submit(
      SellNational(
        game.player,
        company: block.company,
        country: country,
        block: block.index,
      ),
    );
  }
}

/// A chain's offer for the player's shops run by formula, with the way to
/// accept or turn it down.
class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.country, required this.offer});

  final CountryId country;
  final NationalOfferView offer;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final national = nationalOf(game, country);
    final block = national?.blocks
        .where((b) => b.index == offer.block)
        .firstOrNull;
    if (national == null || block == null) return const SizedBox.shrink();
    final trades = game.national!.table.trades;
    final trade = tradeName(trades[block.trade].key, trades[block.trade].name);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: ledger.ink)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Line(
            tr('market.offerFrom', {'chain': offer.chain}),
            money(offer.price, cents: false),
            strong: true,
            color: ledger.gain,
            hint: tr('market.offerFor', {
              'count': block.stores,
              'trade': trade.toLowerCase(),
              'date': shortDate(offer.expires),
            }),
          ),
          if (block.value case final value?)
            Hint(
              tr('market.offerAgainst', {
                'worth': money(value.price, cents: false),
              }),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => game.submit(
                  DeclineNationalOffer(game.player, offer: offer.number),
                ),
                child: Text(tr('market.declineOffer')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final confirmed = await _confirm(
                    context,
                    title: tr('market.sellTitle', {'chain': offer.chain}),
                    body: tr('market.sellBody', {
                      'count': block.stores,
                      'price': money(offer.price, cents: false),
                    }),
                    action: tr('market.sellAction'),
                  );
                  if (confirmed) {
                    game.submit(
                      AcceptNationalOffer(game.player, offer: offer.number),
                    );
                  }
                },
                child: Text(tr('market.acceptOffer')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks [title] with [body], to go ahead with [action] or not.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('common.notNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Opens the page of [chain], by its place among the chains of the game's
/// [country] in the national table: what it sells and earns, where its
/// shops are, what it would cost to buy whole, and the way to.
void openChain(BuildContext context, CountryId country, int chain) {
  final national = nationalOf(context.game, country);
  if (national == null) return;
  final def = national.chains.where((c) => c.index == chain).firstOrNull;
  if (def == null) return;
  context.openPage(
    def.name,
    (context) => [_ChainFigures(country: country, chain: chain)],
  );
}

class _ChainFigures extends StatelessWidget {
  const _ChainFigures({required this.country, required this.chain});

  final CountryId country;
  final int chain;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final national = nationalOf(game, country);
    final view = national?.chains.where((c) => c.index == chain).firstOrNull;
    if (national == null || view == null) return const SizedBox.shrink();
    final ledger = Ledger.of(context);
    final mine = {for (final company in game.view.companies) company.id};
    final value = view.value;
    // Where most of its shops are.
    final regions = [
      for (final (r, count) in view.regional.indexed)
        if (count > 0) (region: national.def.regions[r].name, count: count),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return Section(
      title: view.name,
      children: [
        if (view.boughtBy case final company? when mine.contains(company))
          Hint(tr('market.chainYours'))
        else ...[
          Line(tr('market.chainShops'), '${view.stores}', strong: true),
          Line(tr('market.salesAYear'), yearlyAmount(view.yearSales)),
          if (value != null) ...[
            Line(
              tr('market.earnsAYear'),
              signedMoney(value.earnings, cents: false),
              color: gainColor(context, value.earnings.cents.sign),
            ),
            Line(
              tr('market.chainPrice'),
              money(value.price, cents: false),
              strong: true,
            ),
            if (value.earnings > Money.zero)
              Line(
                tr('market.paysBackYears'),
                tr('market.yearsCount', {
                  'count': decimalText(
                    (value.price.cents / value.earnings.cents).toStringAsFixed(
                      1,
                    ),
                  ),
                }),
              ),
          ],
          if (regions.isNotEmpty)
            Line(
              tr('market.mostShopsIn'),
              regions.take(2).map((r) => r.region).join(', '),
            ),
          if (value != null && game.company != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => _buy(context, national, view, value),
                child: Text(tr('market.buyChain', {'chain': view.name})),
              ),
            ),
          ],
          Hint(tr('market.chainHint')),
        ],
        if (value == null && view.boughtBy == null)
          Text(
            tr('market.chainNotForSale'),
            style: TextStyle(color: ledger.muted),
          ),
      ],
    );
  }

  Future<void> _buy(
    BuildContext context,
    NationalCountryView national,
    NationalChainView view,
    NationalValue value,
  ) async {
    final game = context.game;
    final content = game.content;
    final company = game.company!;
    // Runs as the company's shops of the trade already do, or else as the
    // trade's first kind of shop that can run by formula.
    FormatId? format;
    for (final block in national.blocks) {
      if (block.trade == view.trade && block.company == company.id) {
        format = block.format;
      }
    }
    format ??= content.formats
        .firstWhere((f) => national.tradeOf(content, f.id) == view.trade)
        .id;
    final strategies = [
      for (final s in content.strategies)
        if (s.format == format) s,
    ];
    final director = game.directorOf(company);
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
    final short = value.price - company.cash;
    final borrow = short > Money.zero ? short : Money.zero;
    final term = content.finance.maxTermMonths;
    final confirmed = await _confirm(
      context,
      title: tr('market.buyChainTitle', {'chain': view.name}),
      body: [
        tr('market.buyChainBody', {
          'count': view.stores,
          'price': money(value.price, cents: false),
          'company': game.companyName(company.id),
        }),
        if (borrow > Money.zero)
          tr('market.buyChainLoan', {
            'amount': money(borrow, cents: false),
            'term': termName(term),
          }),
      ].join(' '),
      action: tr('market.buyAction'),
    );
    if (!confirmed) return;
    game.submit(
      BuyNationalChain(
        game.player,
        company: company.id,
        country: country,
        chain: chain,
        format: format,
        strategy: strategy,
        borrow: borrow,
        termMonths: borrow > Money.zero ? term : 0,
      ),
    );
  }
}
