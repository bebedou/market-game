import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// [sector]'s name in the player's language, or the table's own.
String sectorName(ContentDb content, int sector) {
  final def = content.stocks!.sectors[sector];
  return trMaybe('stocks.sectors.${def.key}') ?? def.name;
}

/// How far [now] stands from [before], signed, as a percentage.
String change(Money now, Money before) {
  if (before <= Money.zero) return percent(Fx.zero);
  final raw = (now.cents - before.cents) * 10000 ~/ before.cents;
  final text = percent(Fx.raw(raw));
  return raw > 0 ? '+$text' : text.replaceFirst('-', '−');
}

Color? _changeColor(Ledger ledger, Money now, Money before) => now > before
    ? ledger.gain
    : now < before
    ? ledger.loss
    : null;

/// A price or an index, with its cents.
String _price(Money price) => money(price);

/// [multiple] as a price-to-earnings figure, or a dash.
String _multiple(Fx? multiple) => multiple == null
    ? '—'
    : decimalText((multiple.raw ~/ 1000 / 10).toString());

String _ratingName(AnalystRating rating) => tr('stocks.ratings.${rating.name}');

String _managementName(int? grade) => grade == null
    ? tr('stocks.unproven')
    : tr('stocks.management.${managementGrades[grade]}');

String _exchangeName(ContentDb content, CountryId country) {
  final def = content.stocks!;
  return def.exchanges[def.exchangeOf(country)!].name;
}

void _openStock(BuildContext context, StockView stock) =>
    context.openPage(stock.name, (_) => [StockPage(stock: stock.index)]);

void _openExchange(BuildContext context, ExchangeView exchange) =>
    context.openPage(
      exchange.indexName,
      (_) => [ExchangePage(exchange: exchange.index)],
    );

/// The Market tab, the owner's layout A: the exchanges today, the player's
/// portfolio, then the sectors. Nothing to show without a stock market.
class ExchangeScreen extends StatelessWidget {
  const ExchangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final view = game.view.stocks;
    final ledger = Ledger.of(context);
    if (content.stocks == null || view == null) {
      return ListView(children: [Hint(tr('stocks.closed'))]);
    }
    final def = content.stocks!;
    final gain = view.worth - view.cost;
    return ListView(
      key: const PageStorageKey('stocks'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Section(
          title: tr('stocks.exchangesToday'),
          children: [
            for (final exchange in view.exchanges)
              IndexRow(
                title: exchange.indexName,
                subtitle: tr('stocks.todayLine', {
                  'change': change(exchange.level, exchange.previous),
                  'exchange': exchange.name,
                }),
                value: _price(exchange.level),
                valueColor: _changeColor(
                  ledger,
                  exchange.level,
                  exchange.previous,
                ),
                onTap: () => _openExchange(context, exchange),
              ),
          ],
        ),
        Section(
          title: tr('stocks.yourPortfolio'),
          children: [
            if (view.holdings.isEmpty)
              Hint(tr('stocks.noHoldings'))
            else ...[
              Line(
                tr('stocks.worth'),
                money(view.worth, cents: false),
                strong: true,
              ),
              Line(
                tr('stocks.sinceBought'),
                signedMoney(gain, cents: false),
                color: gain.isNegative ? ledger.loss : ledger.gain,
              ),
              Line(
                tr('stocks.dividendsYear'),
                money(view.dividends, cents: false),
              ),
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
        ),
        if (view.bids.any((b) => b.status == BidStatus.open))
          Section(
            title: tr('stocks.bidsOpen'),
            children: [
              for (final bid in view.bids)
                if (bid.status == BidStatus.open)
                  IndexRow(
                    title: view.stocks[bid.stock].name,
                    subtitle: tr('stocks.bidLine', {
                      'bidder': game.ownerName(bid.bidder),
                      'premium': change(bid.price, bid.reference),
                      'date': shortDate(bid.closes),
                    }),
                    value: money(bid.price),
                    onTap: () => _openStock(context, view.stocks[bid.stock]),
                  ),
            ],
          ),
        Section(
          title: tr('stocks.sectors.title'),
          children: [
            for (final (s, _) in def.sectors.indexed)
              _SectorRow(sector: s, stocks: view.stocks),
            Hint(tr('stocks.howPricesMove')),
          ],
        ),
        if (view.raiders.isNotEmpty)
          Section(
            title: tr('stocks.raiders'),
            children: [
              for (final raider in view.raiders)
                Line(
                  raider.name,
                  compactMoney(raider.worth),
                  hint: [
                    tr('stocks.styles.${raider.style.name}'),
                    if (raider.stakes.isEmpty)
                      tr('stocks.noStakes')
                    else
                      tr('stocks.holds', {
                        'names': raider.stakes
                            .take(2)
                            .map((i) => view.stocks[i].name)
                            .join(', '),
                      }),
                  ].join(' · '),
                ),
              Hint(tr('stocks.raidersHint')),
            ],
          ),
      ],
    );
  }
}

/// A sector's line on the Market tab: its companies, the median price to
/// earnings, stamped when well under or over its own usual.
class _SectorRow extends StatelessWidget {
  const _SectorRow({required this.sector, required this.stocks});

  final int sector;
  final List<StockView> stocks;

  @override
  Widget build(BuildContext context) {
    final content = context.game.content;
    final members = [
      for (final stock in stocks)
        if (stock.sector == sector && stock.listed) stock,
    ];
    final multiples = [
      for (final stock in members)
        if (stock.multiple case final multiple?) multiple.raw,
    ]..sort();
    final usual = [
      for (final stock in members)
        if (stock.averageMultiple case final multiple?) multiple.raw,
    ]..sort();
    final median = multiples.isEmpty ? null : multiples[multiples.length ~/ 2];
    final norm = usual.isEmpty ? null : usual[usual.length ~/ 2];
    String? stamp;
    if (median != null && norm != null && norm > 0) {
      if (median * 5 < norm * 4) stamp = tr('stocks.cheap');
      if (median * 4 > norm * 5) stamp = tr('stocks.dear');
    }
    return IndexRow(
      title: sectorName(content, sector),
      subtitle: tr('stocks.companies', {'count': members.length}),
      value: median == null
          ? null
          : tr('stocks.pe', {'value': _multiple(Fx.raw(median))}),
      stamp: stamp,
      onTap: () => context.openPage(
        sectorName(content, sector),
        (_) => [SectorPage(sector: sector)],
      ),
    );
  }
}

/// A sector's companies, biggest first, on one exchange or all of them.
class SectorPage extends StatefulWidget {
  const SectorPage({super.key, required this.sector});

  final int sector;

  @override
  State<SectorPage> createState() => _SectorPageState();
}

class _SectorPageState extends State<SectorPage> {
  CountryId? _country;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final view = game.view.stocks!;
    final ledger = Ledger.of(context);
    final def = content.stocks!;
    final stocks = [
      for (final stock in view.stocks)
        if (stock.sector == widget.sector &&
            stock.listed &&
            (_country == null || stock.country == _country))
          stock,
    ]..sort((a, b) => b.cap.cents.compareTo(a.cap.cents));
    return Section(
      title: sectorName(content, widget.sector),
      children: [
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: Text(tr('stocks.everywhere')),
              selected: _country == null,
              onSelected: (_) => setState(() => _country = null),
            ),
            for (final exchange in def.exchanges)
              ChoiceChip(
                label: Text(exchange.name),
                selected: _country == exchange.country,
                onSelected: (_) => setState(() => _country = exchange.country),
              ),
          ],
        ),
        for (final stock in stocks)
          IndexRow(
            title: stock.name,
            subtitle: [
              stock.ticker,
              if (_country == null) _exchangeName(content, stock.country),
              change(stock.price, stock.previous),
              tr('stocks.pe', {'value': _multiple(stock.multiple)}),
            ].join(' · '),
            value: _price(stock.price),
            valueColor: _changeColor(ledger, stock.price, stock.previous),
            onTap: () => _openStock(context, stock),
          ),
      ],
    );
  }
}

/// A listed company's page, as the owner's mockup has it: its price over
/// five years, what it rests on, what analysts say and how it is run, who
/// holds it, and the way to buy or sell.
class StockPage extends StatelessWidget {
  const StockPage({super.key, required this.stock});

  final int stock;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final ledger = Ledger.of(context);
    final view = game.view.stocks!;
    final stock = view.stocks[this.stock];
    final holding = view.holdings
        .where(
          (h) => !h.index && h.of == stock.index && h.owner == holdingOwner,
        )
        .firstOrNull;
    final bid = view.bids
        .where((b) => b.stock == stock.index && b.status == BidStatus.open)
        .firstOrNull;
    final controller = stock.controller;
    final mine = controller != null && isPlayers(controller);
    final biddable =
        stock.listed &&
        !mine &&
        (stock.kind == ListingKind.formula ||
            stock.kind == ListingKind.chain) &&
        (bid == null || !isPlayers(bid.bidder));
    final what = [
      sectorName(content, stock.sector),
      _exchangeName(content, stock.country),
      if (stock.stores case final stores?)
        tr('stocks.shops', {'count': compactCount(stores)}),
      if (stock.customers case final customers?)
        tr('stocks.customers', {'count': compactCount(customers)}),
    ].join(' · ');
    final perShare = stock.shares == 0
        ? Money.zero
        : Money(stock.yearProfit.cents ~/ stock.shares);
    final dividendYield = stock.cap <= Money.zero
        ? Fx.zero
        : Fx.raw(stock.yearDividends.cents * 10000 ~/ stock.cap.cents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: '${stock.name} · ${stock.ticker}',
          children: [
            Hint(what),
            Line(
              tr('stocks.price'),
              _price(stock.price),
              strong: true,
              hint: tr('stocks.today', {
                'change': change(stock.price, stock.previous),
              }),
              color: _changeColor(ledger, stock.price, stock.previous),
            ),
            if (stock.closes.length > 1)
              Sparkline(
                [for (final close in stock.closes) close.cents / 100],
                color: ledger.ink,
                height: 64,
              ),
            Hint(tr('stocks.chartSince', {'count': stock.closes.length})),
            if (!stock.listed) Hint(tr('stocks.delisted')),
          ],
        ),
        Section(
          title: tr('stocks.restsOn'),
          children: [
            Line(tr('stocks.cap'), compactMoney(stock.cap)),
            Line(tr('stocks.sales'), compactMoney(stock.yearRevenue)),
            Line(tr('stocks.perShare'), money(perShare)),
            Line(
              tr('stocks.multiple'),
              _multiple(stock.multiple),
              hint: stock.averageMultiple == null
                  ? null
                  : tr('stocks.usually', {
                      'value': _multiple(stock.averageMultiple),
                    }),
            ),
            Line(tr('stocks.yield'), percent(dividendYield)),
            Line(
              tr('stocks.debt'),
              stock.debtYears == null
                  ? tr('stocks.noDebt')
                  : tr('stocks.years', {
                      'value': decimalText(
                        (stock.debtYears!.raw ~/ 1000 / 10).toString(),
                      ),
                    }),
            ),
          ],
        ),
        Section(
          title: tr('stocks.judged'),
          children: [
            Line(tr('stocks.analysts'), _ratingName(stock.rating)),
            Line(
              tr('stocks.managementLabel'),
              _managementName(stock.management),
            ),
            Hint(tr('stocks.judgedHint')),
          ],
        ),
        Section(
          title: tr('stocks.whoHolds'),
          children: [
            if (controller != null)
              Line(
                tr('stocks.controlledBy'),
                game.ownerName(controller),
                color: mine ? ledger.gain : null,
              ),
            if (stock.holders.isEmpty)
              Hint(tr('stocks.noStake'))
            else
              for (final holder in stock.holders)
                Line(
                  game.ownerName(holder.owner),
                  share(holder.units, stock.shares),
                  hint: holder.owner == holdingOwner && holding != null
                      ? tr('stocks.youHold', {
                          'units': compactCount(holding.units),
                          'value': money(holding.value, cents: false),
                        })
                      : null,
                ),
          ],
        ),
        if (bid != null) BidSection(bid: bid, stock: stock),
        if (stock.listed || mine)
          Section(
            title: tr('stocks.deal'),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (stock.listed)
                    FilledButton(
                      onPressed: () => context.openPage(
                        tr('stocks.buy'),
                        (_) => [TradePage(of: stock.index, buy: true)],
                      ),
                      child: Text(tr('stocks.buy')),
                    ),
                  if (holding != null && stock.listed)
                    OutlinedButton(
                      onPressed: () => context.openPage(
                        tr('stocks.sell'),
                        (_) => [TradePage(of: stock.index, buy: false)],
                      ),
                      child: Text(tr('stocks.sell')),
                    ),
                  if (biddable)
                    OutlinedButton(
                      onPressed: () => context.openPage(
                        tr('stocks.bidForAll'),
                        (_) => [TakeoverBidPage(stock: stock.index)],
                      ),
                      child: Text(tr('stocks.bidForAll')),
                    ),
                  if (mine && stock.kind == ListingKind.formula)
                    FilledButton(
                      onPressed: () => context.openPage(
                        stock.name,
                        (_) => [ControlPage(stock: stock.index)],
                      ),
                      child: Text(tr('stocks.runIt')),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

/// An exchange's index: where it stands, its biggest companies, and the
/// way to buy or sell it as a whole.
class ExchangePage extends StatelessWidget {
  const ExchangePage({super.key, required this.exchange});

  final int exchange;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final view = game.view.stocks!;
    final exchange = view.exchanges[this.exchange];
    final members = [
      for (final stock in view.stocks)
        if (stock.listed && stock.country == exchange.country) stock,
    ]..sort((a, b) => b.cap.cents.compareTo(a.cap.cents));
    final total = members.fold(Money.zero, (sum, s) => sum + s.cap);
    final holding = view.holdings
        .where((h) => h.index && h.of == exchange.index)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: exchange.indexName,
          children: [
            Line(
              tr('stocks.level'),
              _price(exchange.level),
              strong: true,
              hint: tr('stocks.today', {
                'change': change(exchange.level, exchange.previous),
              }),
              color: _changeColor(ledger, exchange.level, exchange.previous),
            ),
            if (exchange.closes.length > 1)
              Sparkline(
                [for (final close in exchange.closes) close.cents / 100],
                color: ledger.ink,
                height: 64,
              ),
            Line(
              tr('stocks.listedThere'),
              tr('stocks.companies', {'count': members.length}),
            ),
            Line(tr('stocks.worthTogether'), compactMoney(total)),
            Hint(tr('stocks.indexHint')),
            if (holding != null)
              Line(
                tr('stocks.yourUnits'),
                money(holding.value, cents: false),
                hint: tr('stocks.units', {'count': holding.units}),
              ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => context.openPage(
                    tr('stocks.buyIndex'),
                    (_) => [
                      TradePage(of: exchange.index, buy: true, index: true),
                    ],
                  ),
                  child: Text(tr('stocks.buyIndex')),
                ),
                if (holding != null)
                  OutlinedButton(
                    onPressed: () => context.openPage(
                      tr('stocks.sellIndex'),
                      (_) => [
                        TradePage(of: exchange.index, buy: false, index: true),
                      ],
                    ),
                    child: Text(tr('stocks.sellIndex')),
                  ),
              ],
            ),
          ],
        ),
        Section(
          title: tr('stocks.biggest'),
          children: [
            for (final stock in members.take(10))
              IndexRow(
                title: stock.name,
                subtitle: [
                  stock.ticker,
                  sectorName(game.content, stock.sector),
                  change(stock.price, stock.previous),
                ].join(' · '),
                value: compactMoney(stock.cap),
                onTap: () => _openStock(context, stock),
              ),
          ],
        ),
      ],
    );
  }
}

/// Buying or selling shares of a company, or units of an index: how many,
/// at what price, the broker's fee, and for a big order how far it moves
/// the price.
class TradePage extends StatefulWidget {
  const TradePage({
    super.key,
    required this.of,
    required this.buy,
    this.index = false,
  });

  final int of;
  final bool buy;
  final bool index;

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final _amount = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final rules = content.stocks!.rules;
    final view = game.view.stocks!;
    final holding = view.holdings
        .where(
          (h) =>
              h.index == widget.index &&
              h.of == widget.of &&
              h.owner == holdingOwner,
        )
        .firstOrNull;
    final name = widget.index
        ? view.exchanges[widget.of].indexName
        : view.stocks[widget.of].name;
    final price = widget.index
        ? view.exchanges[widget.of].level
        : view.stocks[widget.of].price;
    final shares = widget.index ? 0 : view.stocks[widget.of].shares;
    final held = holding?.units ?? 0;
    if (_amount.text.isEmpty && !_sent && !widget.buy) {
      _amount.text = '$held';
    }
    // Buying, the player says how much to put in; selling, how many units.
    final cash = game.view.cash;
    int units;
    if (widget.buy) {
      final amount = parseMoney(_amount.text) ?? Money.zero;
      units = price <= Money.zero ? 0 : amount.cents ~/ price.cents;
    } else {
      units = int.tryParse(_amount.text.trim()) ?? 0;
    }
    final value = widget.index
        ? price.timesInt(units)
        : units <= 0
        ? Money.zero
        : orderValue(rules, price, shares, units, buy: widget.buy);
    final fee = orderFee(rules, value, index: widget.index);
    final valid =
        units > 0 &&
        (widget.buy ? value + fee <= cash : units <= held) &&
        !_sent;
    final impact = widget.index || units <= 0
        ? Fx.zero
        : Fx.raw(orderImpact(rules, units, shares) ~/ 100);
    return Section(
      title: name,
      children: [
        Line(tr('stocks.price'), _price(price)),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.numberWithOptions(decimal: widget.buy),
          decoration: InputDecoration(
            labelText: widget.buy ? tr('stocks.toPutIn') : tr('stocks.toSell'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.buy)
          Hint(tr('stocks.yourCash', {'cash': money(cash, cents: false)}))
        else
          Hint(tr('stocks.youHoldUnits', {'count': held})),
        Line(tr('stocks.unitCount'), compactCount(units)),
        Line(
          widget.buy ? tr('stocks.cost') : tr('stocks.proceeds'),
          money(value),
        ),
        Line(tr('stocks.fee'), money(fee)),
        if (widget.buy && units > 0 && value + fee > cash)
          Hint(tr('stocks.notEnough')),
        if (!widget.buy && units > held) Hint(tr('stocks.notThatMany')),
        if (impact > Fx.zero)
          Hint(tr('stocks.impact', {'change': percent(impact)})),
        if (!widget.buy && holding != null && units > 0 && units <= held)
          Line(
            tr('stocks.gain'),
            signedMoney(
              value - fee - Money(holding.cost.cents * units ~/ held),
              cents: false,
            ),
          ),
        Hint(widget.buy ? tr('stocks.buyHint') : tr('stocks.sellHint')),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: valid
                ? () {
                    final player = game.player;
                    game.submit(
                      widget.buy
                          ? BuyShares(
                              player,
                              of: widget.of,
                              units: units,
                              index: widget.index,
                            )
                          : SellShares(
                              player,
                              of: widget.of,
                              units: units,
                              index: widget.index,
                            ),
                    );
                    setState(() => _sent = true);
                  }
                : null,
            child: Text(widget.buy ? tr('stocks.buy') : tr('stocks.sell')),
          ),
        ),
        if (_sent) Hint(tr('stocks.sent')),
      ],
    );
  }
}

/// Everything the player holds, and what it has earned them.
class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final view = game.view.stocks!;
    final gain = view.worth - view.cost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('stocks.yourPortfolio'),
          children: [
            Line(
              tr('stocks.worth'),
              money(view.worth, cents: false),
              strong: true,
            ),
            Line(tr('stocks.paid'), money(view.cost, cents: false)),
            Line(
              tr('stocks.sinceBought'),
              signedMoney(gain, cents: false),
              color: gain.isNegative ? ledger.loss : ledger.gain,
            ),
            Line(
              tr('stocks.dividendsYear'),
              money(view.dividends, cents: false),
            ),
            if (view.lossCarried > Money.zero)
              Line(
                tr('stocks.lossCarried'),
                money(view.lossCarried, cents: false),
              ),
            for (final loan in view.loans)
              Line(
                tr('stocks.loanOn', {'name': view.stocks[loan.stock].name}),
                money(loan.outstanding, cents: false),
                color: ledger.loss,
                hint: tr('stocks.loanLine', {
                  'rate': percent(loan.rate),
                  'months': loan.installmentsLeft,
                }),
              ),
            Hint(tr('stocks.taxHint')),
          ],
        ),
        Section(
          title: tr('stocks.holdings'),
          children: [
            for (final holding in view.holdings) HoldingRow(holding: holding),
          ],
        ),
      ],
    );
  }
}

/// One holding of the player's, the holding's own or a company's: what it
/// is, how many and what they cost, whose, and what it is worth today, in
/// green above its cost and red below; it opens the stock or the index.
class HoldingRow extends StatelessWidget {
  const HoldingRow({super.key, required this.holding});

  final HoldingView holding;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final view = game.view.stocks!;
    return IndexRow(
      title: holding.index
          ? view.exchanges[holding.of].indexName
          : view.stocks[holding.of].name,
      subtitle: [
        tr('stocks.holdingLine', {
          'units': compactCount(holding.units),
          'cost': money(holding.cost, cents: false),
        }),
        if (holding.owner != holdingOwner) game.ownerName(holding.owner),
      ].join(' · '),
      value: money(holding.value, cents: false),
      valueColor: holding.value < holding.cost ? ledger.loss : ledger.gain,
      onTap: () => holding.index
          ? _openExchange(context, view.exchanges[holding.of])
          : _openStock(context, view.stocks[holding.of]),
    );
  }
}

/// A bid open for a company, on its page: who bids, at what, until when, how
/// much of the company would accept today, and, for someone else's bid,
/// whether the player offers their shares into it.
class BidSection extends StatelessWidget {
  const BidSection({super.key, required this.bid, required this.stock});

  final BidView bid;
  final StockView stock;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final ours = isPlayers(bid.bidder);
    final held = stock.holders
        .where((h) => isPlayers(h.owner))
        .fold(0, (sum, h) => sum + h.units);
    final half = bid.accepting > const Fx.raw(5000);
    return Section(
      title: tr('stocks.aBid'),
      mark: ours ? ledger.gain : ledger.loss,
      children: [
        Line(tr('stocks.bidder'), game.ownerName(bid.bidder)),
        Line(
          tr('stocks.bidPrice'),
          money(bid.price),
          hint: tr('stocks.overReference', {
            'premium': change(bid.price, bid.reference),
          }),
        ),
        Line(tr('stocks.closes'), shortDate(bid.closes)),
        Line(
          tr('stocks.accepting'),
          percent(bid.accepting, decimals: 0),
          color: half ? ledger.gain : ledger.loss,
          hint: tr('stocks.needsHalf'),
        ),
        if (!ours && held > 0) ...[
          Hint(bid.tender ? tr('stocks.tendering') : tr('stocks.notTendering')),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => game.submit(
                AnswerBid(game.player, bid: bid.number, tender: !bid.tender),
              ),
              child: Text(
                bid.tender ? tr('stocks.keepShares') : tr('stocks.tender'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The premiums a bid may offer, as choices.
const _premiums = [20, 30, 40, 50];

/// Bidding for every share of a company (the owner's mockup 1): the premium
/// over its price, what the shares the bidder lacks cost, who pays and what
/// they borrow, and how its shareholders are likely to answer. With [via],
/// a company the player controls bids, with debt, to merge it in.
class TakeoverBidPage extends StatefulWidget {
  const TakeoverBidPage({super.key, required this.stock, this.via});

  final int stock;
  final int? via;

  @override
  State<TakeoverBidPage> createState() => _TakeoverBidPageState();
}

class _TakeoverBidPageState extends State<TakeoverBidPage> {
  int _premium = 30;
  int? _bidder;
  final _borrow = TextEditingController();
  int _years = 5;
  bool _sent = false;

  @override
  void dispose() {
    _borrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final def = content.stocks!;
    final ledger = Ledger.of(context);
    final view = game.view.stocks!;
    final stock = view.stocks[widget.stock];
    final chain = stock.kind == ListingKind.chain;
    final companies = [
      for (final company in game.view.companies)
        if (company.status == CompanyStatus.active) company,
    ];
    final bidders = [
      if (!chain) holdingOwner,
      for (final c in companies) c.id.index,
    ];
    if (_bidder == null || !bidders.contains(_bidder)) {
      _bidder = bidders.isEmpty ? null : bidders.first;
    }
    final price = stock.price + stock.price.times(Fx.raw(_premium * 100));
    final players = stock.holders
        .where((h) => isPlayers(h.owner))
        .fold(0, (sum, h) => sum + h.units);
    final own = stock.holders
        .where((h) => h.owner == _bidder)
        .fold(0, (sum, h) => sum + h.units);
    final cost = price.timesInt(stock.shares - own);
    final reference = stock.analysts > stock.price
        ? stock.analysts
        : stock.price;
    final part = freeFloatAccepting(def, reference, price);
    final others = stock.holders
        .where((h) => !isPlayers(h.owner))
        .fold(0, (sum, h) => sum + h.units);
    final free = stock.shares - players - others;
    final likely = (players + free * part.raw ~/ Fx.scale) * 2 > stock.shares;
    final borrow = parseMoney(_borrow.text) ?? Money.zero;
    final cash = switch (_bidder) {
      null => Money.zero,
      holdingOwner => game.view.cash,
      final c => companies.firstWhere((company) => company.id.index == c).cash,
    };
    final enough = widget.via != null || cash + borrow >= cost;
    // A chain's shops take the bidder's national format of its trade.
    final format = chain
        ? content.formats.indexWhere(
            (f) =>
                f.national != null &&
                formatTrades[f.key] == def.sectors[stock.sector].trade,
          )
        : -1;
    final valid = !_sent && enough && (widget.via != null || _bidder != null);
    return Section(
      title: tr('stocks.bidFor', {'name': stock.name}),
      children: [
        Line(tr('stocks.price'), money(stock.price)),
        Text(tr('stocks.premium')),
        Wrap(
          spacing: 6,
          children: [
            for (final premium in _premiums)
              ChoiceChip(
                label: Text(percentOf(premium)),
                selected: _premium == premium,
                onSelected: (_) => setState(() => _premium = premium),
              ),
          ],
        ),
        Line(tr('stocks.bidPrice'), money(price), strong: true),
        Line(tr('stocks.youHoldShare'), share(players, stock.shares)),
        Line(
          tr('stocks.forTheRest', {
            'share': share(stock.shares - own, stock.shares),
          }),
          compactMoney(cost),
        ),
        if (widget.via == null) ...[
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _bidder,
            decoration: InputDecoration(labelText: tr('stocks.paidBy')),
            items: [
              for (final bidder in bidders)
                DropdownMenuItem(
                  value: bidder,
                  child: Text(game.ownerName(bidder)),
                ),
            ],
            onChanged: (value) => setState(() => _bidder = value),
          ),
          Line(tr('stocks.itsCash'), compactMoney(cash)),
          TextField(
            controller: _borrow,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('stocks.borrow')),
            onChanged: (_) => setState(() {}),
          ),
          if (borrow > Money.zero)
            Row(
              children: [
                Expanded(child: Text(tr('stocks.over'))),
                CountStepper(
                  value: _years,
                  min: 1,
                  max: content.finance.maxTermMonths ~/ 12,
                  label: termName(_years * 12),
                  onChanged: (value) => setState(() => _years = value),
                ),
              ],
            ),
          Hint(
            _bidder == holdingOwner
                ? tr('stocks.holdingBorrowHint')
                : tr('stocks.companyBorrowHint'),
          ),
          if (!enough)
            Hint(tr('stocks.notEnoughForBid', {'cost': compactMoney(cost)})),
        ] else
          Hint(tr('stocks.rivalHint')),
        Line(
          tr('stocks.shareholders'),
          likely ? tr('stocks.likelyYes') : tr('stocks.likelyNo'),
          color: likely ? ledger.gain : ledger.loss,
          hint: tr('stocks.freeFloatAccepts', {
            'share': percent(part, decimals: 0),
          }),
        ),
        Hint(chain ? tr('stocks.chainBidHint') : tr('stocks.bidHint')),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: valid
                ? () {
                    game.submit(
                      widget.via == null
                          ? BidForCompany(
                              game.player,
                              stock: stock.index,
                              premium: Fx.raw(_premium * 100),
                              bidder: _bidder!,
                              borrow: borrow,
                              termMonths: borrow > Money.zero ? _years * 12 : 0,
                              format: format,
                              strategy: chain ? 0 : -1,
                            )
                          : BuyRival(
                              game.player,
                              via: widget.via!,
                              stock: stock.index,
                              premium: Fx.raw(_premium * 100),
                            ),
                    );
                    setState(() => _sent = true);
                  }
                : null,
            child: Text(tr('stocks.makeBid')),
          ),
        ),
        if (_sent) Hint(tr('stocks.sent')),
      ],
    );
  }
}

/// The levers' choices.
const _payouts = [0, 25, 50, 75];
const _debts = [0, 1, 2, 4];

/// A company by formula the player controls (the owner's mockup 2): its
/// year, its levers, who runs it, smaller rivals to buy, and selling it.
class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.stock});

  final int stock;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  int? _payout;
  int? _growth;
  int? _debt;
  int? _director;
  bool _directorSet = false;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final view = game.view.stocks!;
    final stock = view.stocks[widget.stock];
    final controller = stock.controller;
    if (controller == null || !isPlayers(controller)) {
      return Hint(tr('stocks.noLongerYours'));
    }
    final payout = _payout ?? (stock.payoutLever?.raw ?? -100) ~/ 100;
    final growth = _growth ?? stock.growthLever;
    final debt = _debt ?? (stock.debtLever?.raw ?? -10000) ~/ 10000;
    final director = _directorSet ? _director : stock.director;
    final grades = content.directors?.grades ?? const <DirectorGradeDef>[];
    final rivals = [
      for (final other in view.stocks)
        if (other.listed &&
            other.index != stock.index &&
            other.kind == ListingKind.formula &&
            other.sector == stock.sector &&
            other.country == stock.country &&
            other.controller == null &&
            other.cap < stock.cap)
          other,
    ]..sort((a, b) => b.cap.cents.compareTo(a.cap.cents));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: stock.name,
          children: [
            Line(tr('stocks.controlledBy'), game.ownerName(controller)),
            Line(tr('stocks.sales'), compactMoney(stock.yearRevenue)),
            Line(tr('stocks.profitYear'), compactMoney(stock.yearProfit)),
            Line(tr('stocks.cap'), compactMoney(stock.cap)),
            Line(
              tr('stocks.debt'),
              stock.debtYears == null
                  ? tr('stocks.noDebt')
                  : tr('stocks.years', {
                      'value': decimalText(
                        (stock.debtYears!.raw ~/ 1000 / 10).toString(),
                      ),
                    }),
            ),
          ],
        ),
        Section(
          title: tr('stocks.levers'),
          children: [
            Text(tr('stocks.dividendLever')),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: Text(tr('stocks.asItWas')),
                  selected: payout < 0,
                  onSelected: (_) => setState(() => _payout = -1),
                ),
                for (final p in _payouts)
                  ChoiceChip(
                    label: Text(percentOf(p)),
                    selected: payout == p,
                    onSelected: (_) => setState(() => _payout = p),
                  ),
              ],
            ),
            Text(tr('stocks.growthLever')),
            Wrap(
              spacing: 6,
              children: [
                for (final (g, key) in [
                  (-1, 'slow'),
                  (0, 'steady'),
                  (1, 'fast'),
                ])
                  ChoiceChip(
                    label: Text(tr('stocks.pace.$key')),
                    selected: growth == g,
                    onSelected: (_) => setState(() => _growth = g),
                  ),
              ],
            ),
            Hint(tr('stocks.growthHint')),
            Text(tr('stocks.debtLever')),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: Text(tr('stocks.asItWas')),
                  selected: debt < 0,
                  onSelected: (_) => setState(() => _debt = -1),
                ),
                for (final d in _debts)
                  ChoiceChip(
                    label: Text(
                      d == 0
                          ? tr('stocks.noDebt')
                          : tr('terms.years', {'count': d}),
                    ),
                    selected: debt == d,
                    onSelected: (_) => setState(() => _debt = d),
                  ),
              ],
            ),
            Hint(tr('stocks.debtHint')),
            if (grades.isNotEmpty)
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: director,
                decoration: InputDecoration(labelText: tr('stocks.runBy')),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(tr('stocks.itsOwnManagement')),
                  ),
                  for (final (g, grade) in grades.indexed)
                    DropdownMenuItem(value: g, child: Text(grade.name)),
                ],
                onChanged: (value) => setState(() {
                  _director = value;
                  _directorSet = true;
                }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => game.submit(
                  RunListed(
                    game.player,
                    stock: stock.index,
                    payout: payout < 0 ? null : Fx.raw(payout * 100),
                    growth: growth,
                    debt: debt < 0 ? null : Fx.fromInt(debt),
                    director: director,
                  ),
                ),
                child: Text(tr('stocks.apply')),
              ),
            ),
          ],
        ),
        Section(
          title: tr('stocks.buyARival'),
          children: [
            if (rivals.isEmpty) Hint(tr('stocks.noRivals')),
            for (final rival in rivals.take(5))
              IndexRow(
                title: rival.name,
                subtitle: tr('stocks.pe', {'value': _multiple(rival.multiple)}),
                value: compactMoney(rival.cap),
                onTap: () => context.openPage(
                  tr('stocks.buyARival'),
                  (_) => [
                    TakeoverBidPage(stock: rival.index, via: stock.index),
                  ],
                ),
              ),
          ],
        ),
        Section(
          title: tr('stocks.sellIt'),
          children: [
            Hint(tr('stocks.sellItHint')),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => game.submit(
                  SellControlled(game.player, stock: stock.index),
                ),
                child: Text(tr('stocks.sellIt')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The shares of a company that may be listed, as choices.
const _listShares = [10, 25, 50, 75, 100];

/// On a company's page: where it stands on the exchange, or the way to list
/// it.
class ExchangeEntry extends StatelessWidget {
  const ExchangeEntry({super.key, required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view.stocks;
    if (game.content.stocks == null || view == null) {
      return const SizedBox.shrink();
    }
    final listed = view.stocks
        .where((s) => s.company == company.id && s.running)
        .firstOrNull;
    return Section(
      title: tr('stocks.onTheExchange'),
      children: [
        if (listed != null)
          IndexRow(
            title: '${listed.name} · ${listed.ticker}',
            subtitle: tr('stocks.yourStake', {
              'share': share(
                listed.holders
                    .where((h) => isPlayers(h.owner))
                    .fold(0, (sum, h) => sum + h.units),
                listed.shares,
              ),
            }),
            value: money(listed.price),
            onTap: () => _openStock(context, listed),
          )
        else
          IndexRow(
            title: tr('stocks.listIt'),
            subtitle: tr('stocks.listItPitch'),
            onTap: () => context.openPage(
              tr('stocks.listIt'),
              (_) => [ListCompanyPage(company: company.id)],
            ),
          ),
      ],
    );
  }
}

/// Listing a company of the player's (the owner's mockup 3): how much of
/// it, new shares or the player's own, what it raises, and what the player
/// keeps.
class ListCompanyPage extends StatefulWidget {
  const ListCompanyPage({super.key, required this.company});

  final CompanyId company;

  @override
  State<ListCompanyPage> createState() => _ListCompanyPageState();
}

class _ListCompanyPageState extends State<ListCompanyPage> {
  int _share = 25;
  bool _newShares = true;
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final worth = game.view.companyPrices[widget.company.index] ?? Money.zero;
    final newShares = _newShares && _share < 100;
    final sold = Fx.raw(_share * 100);
    final raises = newShares
        ? Money(worth.cents * _share ~/ (100 - _share))
        : worth.times(sold);
    final keep = newShares ? 100 - _share : 100 - _share;
    final safe = keep * 2 > 100;
    return Section(
      title: tr('stocks.listName', {'name': game.companyName(widget.company)}),
      children: [
        Line(tr('stocks.byItsBooks'), compactMoney(worth)),
        Text(tr('stocks.whatToSell')),
        Wrap(
          spacing: 6,
          children: [
            for (final s in _listShares)
              ChoiceChip(
                label: Text(percentOf(s)),
                selected: _share == s,
                onSelected: (_) => setState(() => _share = s),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: Text(tr('stocks.newShares')),
              selected: newShares,
              onSelected: _share < 100
                  ? (_) => setState(() => _newShares = true)
                  : null,
            ),
            ChoiceChip(
              label: Text(tr('stocks.yourShares')),
              selected: !newShares,
              onSelected: (_) => setState(() => _newShares = false),
            ),
          ],
        ),
        Line(
          newShares ? tr('stocks.raisesCompany') : tr('stocks.raisesYou'),
          compactMoney(raises),
        ),
        Line(
          tr('stocks.youKeep'),
          percentOf(keep),
          color: safe ? ledger.gain : ledger.loss,
        ),
        Hint(safe ? tr('stocks.keepControl') : tr('stocks.openToBids')),
        Hint(
          newShares ? tr('stocks.newSharesHint') : tr('stocks.yourSharesHint'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _sent
                ? null
                : () {
                    game.submit(
                      ListCompany(
                        game.player,
                        company: widget.company,
                        share: sold,
                        newShares: newShares,
                      ),
                    );
                    setState(() => _sent = true);
                  },
            child: Text(tr('stocks.listItButton')),
          ),
        ),
        if (_sent) Hint(tr('stocks.sent')),
      ],
    );
  }
}
