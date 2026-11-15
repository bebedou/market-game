import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lab.dart' show points;

/// The most a bid may go under the producer price, in whole points.
const _maxUnder = 30;

/// [units] with the language's separators, shortened past a million.
String _units(int units) => compactCount(units);

/// What [factory] could make in a month at its most shifts.
int fullCapacity(SimulationController game, FactoryView factory) {
  final factories = game.content.factories!;
  return factories.sized(factory.kind, factory.size).shiftUnits *
      factories.maxShifts *
      30;
}

/// [tender]'s product as [factory] sells it to chains, if it makes it.
SalesLine? _line(FactoryView factory, ProductId product) {
  for (final line in factory.sales?.lines ?? const <SalesLine>[]) {
    if (line.product == product) return line;
  }
  return null;
}

/// The tenders [factory] may bid on: open, for its goods, in countries it
/// serves.
List<TenderView> openTendersFor(
  SimulationController game,
  FactoryView factory,
) => [
  for (final tender in game.view.tenders)
    if (tender.status == TenderStatus.open &&
        _line(factory, tender.product) != null &&
        factory.serves[tender.country.index])
      tender,
];

/// How far under [reference] [price] is, as a share.
Fx _underShare(Money price, Money reference) => reference <= Money.zero
    ? Fx.zero
    : Fx.one - Fx.raw(price.cents * Fx.scale ~/ reference.cents);

/// Opens [factory]'s sales desk within the current tab.
void openSalesDesk(BuildContext context, FactoryView factory) =>
    context.openPage(tr('sales.title'), (_) => [SalesDeskPage(id: factory.id)]);

/// The way into a factory's sales desk, with what it sells to others.
class SalesDeskEntry extends StatelessWidget {
  const SalesDeskEntry({super.key, required this.factory});

  final FactoryView factory;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final sales = factory.sales!;
    final running = sales.contracts.where(
      (c) => !c.ended && game.today < c.ends,
    );
    return IndexRow(
      icon: Icons.handshake_outlined,
      title: tr('sales.title'),
      subtitle: [
        tr('sales.contractsCount', {'count': running.length}),
        tr('sales.tendersCount', {
          'count': openTendersFor(game, factory).length,
        }),
      ].join(' · '),
      onTap: () => openSalesDesk(context, factory),
    );
  }
}

/// A factory's sales desk, the owner's layout B: its market, its
/// contracts, the tenders it may bid on, what lately won, and independent
/// shops.
class SalesDeskPage extends StatelessWidget {
  const SalesDeskPage({super.key, required this.id});

  final FactoryId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final factory = game.factory(id);
    final sales = factory?.sales;
    if (factory == null || sales == null) return Hint(tr('factory.gone'));
    final content = game.content;
    final capacity = fullCapacity(game, factory);
    final open = openTendersFor(game, factory);
    final closed = [
      for (final tender in game.view.tenders.reversed)
        if (tender.status == TenderStatus.won ||
            tender.status == TenderStatus.lost)
          if (_line(factory, tender.product) != null &&
              factory.serves[tender.country.index])
            tender,
    ].take(8).toList();
    final running = [
      for (final contract in sales.contracts)
        if (!contract.ended && game.today < contract.ends) contract,
    ];
    String product(ProductId id) => content.products[id.index].name;
    String country(CountryId id) => content.countries[id.index].name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: factory.name,
          mark: Ledger.of(context).works,
          children: [
            Line(
              tr('sales.market'),
              compactMoney(sales.market),
              hint: tr('sales.marketHint'),
            ),
            Line(
              tr('sales.committed'),
              tr('sales.ofCapacity', {
                'units': _units(sales.committed),
                'capacity': _units(capacity),
              }),
            ),
            Line(
              tr('sales.reliability'),
              percent(sales.reliability, decimals: 0),
            ),
            Hint(tr('sales.reliabilityHint')),
          ],
        ),
        Section(
          title: tr('sales.contracts'),
          children: [
            if (running.isEmpty) Hint(tr('sales.noContracts')),
            for (final contract in running)
              Line(
                [contract.chain, country(contract.country)].join(' · '),
                money(contract.price),
                hint: tr('sales.contractLine', {
                  'units': _units(contract.units),
                  'product': product(contract.product),
                  'date': shortDate(contract.ends),
                }),
              ),
          ],
        ),
        Section(
          title: tr('sales.tenders'),
          children: [
            if (open.isEmpty) Hint(tr('sales.noTenders')),
            for (final tender in open)
              IndexRow(
                title: tr('sales.seeks', {
                  'chain': tender.chain,
                  'product': product(tender.product),
                }),
                subtitle: tr('sales.tenderLine', {
                  'units': _units(tender.units),
                  'months': tender.months,
                  'date': shortDate(tender.closes),
                }),
                value: switch (game.bidOn(tender)) {
                  final price? => money(price),
                  null => null,
                },
                stamp: sales.committed + tender.units > capacity
                    ? tr('sales.tooBig')
                    : null,
                onTap: () => context.openPage(
                  tr('sales.bid'),
                  (_) => [BidPage(factory: id, tender: tender.number)],
                ),
              ),
          ],
        ),
        if (closed.isNotEmpty)
          Section(
            title: tr('sales.lately'),
            children: [
              for (final tender in closed)
                Line(
                  tr('sales.seeks', {
                    'chain': tender.chain,
                    'product': product(tender.product),
                  }),
                  tender.status == TenderStatus.won
                      ? tr('sales.won', {
                          'under': percent(
                            _underShare(tender.winningPrice!, tender.reference),
                            decimals: 0,
                          ),
                        })
                      : tr('sales.lostTo', {
                          'winner': tender.winner ?? '',
                          'under': percent(
                            _underShare(tender.winningPrice!, tender.reference),
                            decimals: 0,
                          ),
                        }),
                  color: tender.status == TenderStatus.won
                      ? gainColor(context, 1)
                      : null,
                ),
            ],
          ),
        Section(
          title: tr('sales.independents'),
          children: [
            Line(
              tr('sales.independentShare'),
              percentOf(
                decimalText(
                  (sales.independentShare / 10000).toStringAsFixed(3),
                ),
              ),
            ),
            Hint(
              factory.rivalDiscount == null
                  ? tr('sales.independentsOff')
                  : tr('sales.independentsOn', {
                      'discount': percent(factory.rivalDiscount!, decimals: 0),
                    }),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bidding on a tender: the prices, what the factory's goods cost it,
/// what the bid earns and whether it fits.
class BidPage extends StatefulWidget {
  const BidPage({super.key, required this.factory, required this.tender});

  final FactoryId factory;
  final int tender;

  @override
  State<BidPage> createState() => _BidPageState();
}

class _BidPageState extends State<BidPage> {
  int? _under;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final factory = game.factory(widget.factory);
    final tender = game.view.tenders
        .where((t) => t.number == widget.tender)
        .firstOrNull;
    final line = factory == null || tender == null
        ? null
        : _line(factory, tender.product);
    if (factory == null || tender == null || line == null) {
      return Hint(tr('sales.gone'));
    }
    final content = game.content;
    final sales = factory.sales!;
    final standing = game.bidOn(tender);
    final under =
        _under ??
        (standing == null
            ? 5
            : (_underOf(standing, tender.reference).raw + 50) ~/ 100);
    final price = tender.reference.times(Fx.one - Fx.raw(under * 100));
    final capacity = fullCapacity(game, factory);
    final fits = sales.committed + tender.units <= capacity;
    final earns = (price - line.unitCost).timesInt(tender.units);
    final good = line.lead >= tender.floor;
    final recent = [
      for (final other in game.view.tenders)
        if (other.product == tender.product &&
            other.country == tender.country &&
            other.winningPrice != null)
          _underOf(other.winningPrice!, other.reference),
    ];
    final open = tender.status == TenderStatus.open;
    return Section(
      title: tr('sales.seeks', {
        'chain': tender.chain,
        'product': content.products[tender.product.index].name,
      }),
      mark: Ledger.of(context).works,
      children: [
        Hint(
          tr('sales.tenderAsks', {
            'units': _units(tender.units),
            'months': tender.months,
            'floor': points(tender.floor),
            'date': shortDate(tender.closes),
            'country': content.countries[tender.country.index].name,
          }),
        ),
        Line(tr('sales.wholesale'), money(line.wholesale)),
        Line(
          tr('sales.producerPrice'),
          money(tender.reference),
          hint: tr('sales.producerPriceHint'),
        ),
        Line(tr('sales.unitCost'), money(line.unitCost)),
        Line(
          tr('sales.yourQuality'),
          tr('sales.points', {'points': points(line.lead)}),
          color: good ? null : Ledger.of(context).loss,
          hint: good ? null : tr('sales.belowFloor'),
        ),
        if (recent.isNotEmpty)
          Hint(
            tr('sales.recent', {
              'low': percent(
                recent.reduce((a, b) => a < b ? a : b),
                decimals: 0,
              ),
              'high': percent(
                recent.reduce((a, b) => a > b ? a : b),
                decimals: 0,
              ),
            }),
          ),
        const Divider(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('sales.yourBid'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            CountStepper(
              value: under,
              max: _maxUnder,
              label: tr('sales.under', {'under': under}),
              enabled: open,
              onChanged: (value) => setState(() => _under = value),
            ),
          ],
        ),
        Line(tr('sales.bidPrice'), money(price), strong: true),
        Line(
          tr('sales.earns'),
          compactMoney(earns),
          color: gainColor(context, earns.cents.sign),
        ),
        Line(
          tr('sales.fits'),
          fits
              ? tr('sales.fitsYes', {
                  'used': share(sales.committed + tender.units, capacity),
                })
              : tr('sales.fitsNo'),
          color: fits ? null : Ledger.of(context).loss,
        ),
        if (!fits) Hint(tr('sales.fitsNoHint')),
        const SizedBox(height: 8),
        if (open)
          Row(
            children: [
              FilledButton(
                onPressed: good
                    ? () => game.submit(
                        BidTender(
                          game.player,
                          tender: tender.number,
                          factory: factory.id,
                          price: price,
                        ),
                      )
                    : null,
                child: Text(
                  standing == null
                      ? tr('sales.placeBid')
                      : tr('sales.changeBid'),
                ),
              ),
              const SizedBox(width: 8),
              if (standing != null)
                TextButton(
                  onPressed: () => game.submit(
                    BidTender(
                      game.player,
                      tender: tender.number,
                      factory: factory.id,
                    ),
                  ),
                  child: Text(tr('sales.withdraw')),
                ),
            ],
          )
        else
          Hint(tr('sales.closed')),
      ],
    );
  }

  static Fx _underOf(Money price, Money reference) =>
      _underShare(price, reference);
}
