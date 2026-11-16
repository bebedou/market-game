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
        Section(
          title: tr('stocks.sectors.title'),
          children: [
            for (final (s, _) in def.sectors.indexed)
              _SectorRow(sector: s, stocks: view.stocks),
            Hint(tr('stocks.howPricesMove')),
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
        .where((h) => !h.index && h.of == stock.index)
        .firstOrNull;
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
            if (holding == null)
              Hint(tr('stocks.noStake'))
            else
              Line(
                tr('stocks.you'),
                share(holding.units, stock.shares),
                hint: tr('stocks.youHold', {
                  'units': compactCount(holding.units),
                  'value': money(holding.value, cents: false),
                }),
              ),
          ],
        ),
        if (stock.listed)
          Section(
            title: tr('stocks.deal'),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => context.openPage(
                      tr('stocks.buy'),
                      (_) => [TradePage(of: stock.index, buy: true)],
                    ),
                    child: Text(tr('stocks.buy')),
                  ),
                  if (holding != null)
                    OutlinedButton(
                      onPressed: () => context.openPage(
                        tr('stocks.sell'),
                        (_) => [TradePage(of: stock.index, buy: false)],
                      ),
                      child: Text(tr('stocks.sell')),
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
        .where((h) => h.index == widget.index && h.of == widget.of)
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
            Hint(tr('stocks.taxHint')),
          ],
        ),
        Section(
          title: tr('stocks.holdings'),
          children: [
            for (final holding in view.holdings)
              IndexRow(
                title: holding.index
                    ? view.exchanges[holding.of].indexName
                    : view.stocks[holding.of].name,
                subtitle: tr('stocks.holdingLine', {
                  'units': compactCount(holding.units),
                  'cost': money(holding.cost, cents: false),
                }),
                value: money(holding.value, cents: false),
                valueColor: holding.value < holding.cost
                    ? ledger.loss
                    : ledger.gain,
                onTap: () => holding.index
                    ? _openExchange(context, view.exchanges[holding.of])
                    : _openStock(context, view.stocks[holding.of]),
              ),
          ],
        ),
      ],
    );
  }
}
