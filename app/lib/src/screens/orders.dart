import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../visuals.dart';
import '../widgets.dart';

/// Days of sales an order suggestion averages.
const _forecastDays = 14;

/// Days of sales an order suggestion covers beyond the lead time.
const _coverDays = 7;

/// Suppliers and ordering, deliveries on their way, and unpaid bills.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.company;
    final store = game.store;
    if (company == null || store == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(tr('orders.noStore')),
        ),
      );
    }
    final canOrder =
        company.status == CompanyStatus.active &&
        store.status != StoreStatus.closed;
    return ListView(
      key: const PageStorageKey('orders'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        Section(
          title: tr('orders.suppliers'),
          icon: Icons.warehouse_outlined,
          children: [
            Hint(
              tr('orders.orderingFor', {
                'store': game.view.shelves[store.id.index].name,
              }),
            ),
            if (game.delegates(store, ManagerDuty.ordering))
              Hint(tr('orders.managerOrders')),
            // The player's factories making what the store sells, whose
            // goods it buys only from them.
            for (final factory in _factories(game, store))
              _FactoryTile(
                factory: factory,
                store: store,
                onOrder: canOrder
                    ? () => _order(
                        context,
                        game,
                        Seller.factory(game, factory, store),
                        store,
                      )
                    : null,
              ),
            // Only suppliers of what the store's format sells, and not
            // what the player's factories make for it.
            for (final supplier in game.content.suppliers)
              if (supplier.country == game.content.countryOf(store.market) &&
                  game.content.products.any(
                    (product) =>
                        supplier.carries[product.id.index] &&
                        game.content.formats[store.format.index].sells[product
                            .category
                            .index] &&
                        game.view.factoryFor(game.content, store, product) ==
                            null,
                  ))
                _SupplierTile(
                  supplier: supplier,
                  onOrder: canOrder
                      ? () => _order(
                          context,
                          game,
                          Seller.wholesaler(supplier),
                          store,
                        )
                      : null,
                ),
          ],
        ),
        Section(
          title: tr('orders.ordersBills'),
          children: [
            IndexRow(
              title: tr('orders.onTheWay'),
              subtitle: company.orders.isEmpty
                  ? tr('orders.nothingOnOrder')
                  : tr('orders.ordersSummary', {
                      'count': company.orders.length,
                      'date': shortDate(company.orders.first.arrival),
                    }),
              value: company.orders.isEmpty
                  ? null
                  : money(
                      company.orders.fold(
                        Money.zero,
                        (sum, order) =>
                            sum +
                            order.lines.fold(
                              Money.zero,
                              (sum, line) =>
                                  sum + line.unitPrice.timesInt(line.quantity),
                            ),
                      ),
                      cents: false,
                    ),
              onTap: () => context.openPage(
                tr('orders.onTheWay'),
                (_) => [const _OnTheWay()],
              ),
            ),
            IndexRow(
              title: tr('common.unpaidBills'),
              subtitle: company.bills.isEmpty
                  ? tr('orders.allPaid')
                  : tr('orders.billsSummary', {'count': company.bills.length}),
              stamp: company.bills.any((bill) => bill.due < game.today)
                  ? tr('orders.overdue')
                  : null,
              value: company.bills.isEmpty
                  ? null
                  : money(
                      company.bills.fold(
                        Money.zero,
                        (sum, bill) => sum + bill.amount,
                      ),
                      cents: false,
                    ),
              onTap: () => context.openPage(
                tr('common.unpaidBills'),
                (_) => [const _Bills()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The player's factories that make something [store] sells for it.
  static List<FactoryView> _factories(
    SimulationController game,
    StoreView store,
  ) {
    final found = <FactoryView>[];
    for (final product in game.content.products) {
      if (!game.content.formats[store.format.index].sells[product
          .category
          .index]) {
        continue;
      }
      final factory = game.view.factoryFor(game.content, store, product);
      if (factory != null && !found.any((f) => f.id == factory.id)) {
        found.add(factory);
      }
    }
    return found;
  }

  static String _creditorName(SimulationController game, PartyRef creditor) =>
      switch (creditor.type) {
        PartyType.supplier => game.content.suppliers[creditor.index].name,
        PartyType.company => tr('orders.creditors.factory', {
          'company': game.companyName(CompanyId(creditor.index)),
        }),
        PartyType.landlords => tr('orders.creditors.rent'),
        PartyType.bank => tr('orders.creditors.bank'),
        PartyType.households => tr('orders.creditors.wages'),
        PartyType.services => tr('orders.creditors.services'),
        PartyType.government => tr('orders.creditors.taxes'),
        PartyType.person || PartyType.elsewhere => tr('orders.creditors.other'),
      };

  void _order(
    BuildContext context,
    SimulationController game,
    Seller seller,
    StoreView store,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GameScope(
      controller: game,
      child: OrderSheet(seller: seller, store: store),
    ),
  );
}

/// What an order sheet buys from: a wholesaler of the store's country, or
/// one of the player's factories, which charges what the wholesalers would.
final class Seller {
  Seller.wholesaler(SupplierDef this.supplier)
    : factory = null,
      name = supplier.name,
      leadTimeDays = supplier.leadTimeDays,
      paymentTermsDays = supplier.paymentTermsDays,
      minOrderUnits = supplier.minOrderUnits,
      country = supplier.country,
      _content = null;

  Seller.factory(
    SimulationController game,
    FactoryView this.factory,
    StoreView store,
  ) : supplier = null,
      name = factory.name,
      leadTimeDays = factoryLeadTime(
        game.content.factories!,
        game.content.factories!.kinds[factory.kind.index],
        factory.country,
        game.content.countryOf(store.market),
      ),
      paymentTermsDays = game.content.factories!.paymentTermsDays,
      minOrderUnits =
          game.content.factories!.kinds[factory.kind.index].minOrderUnits,
      country = game.content.countryOf(store.market),
      _content = game.content;

  final SupplierDef? supplier;
  final FactoryView? factory;
  final String name;
  final int leadTimeDays;
  final int paymentTermsDays;
  final int minOrderUnits;

  /// Whose prices it charges: its own country's, or the store's.
  final CountryId country;
  final ContentDb? _content;

  /// Whether it sells [store] [product].
  bool sells(SimulationController game, StoreView store, ProductDef product) {
    if (supplier case final supplier?) {
      return supplier.carries[product.id.index] &&
          game.view.factoryFor(game.content, store, product) == null;
    }
    return game.view.factoryFor(game.content, store, product)?.id ==
        factory!.id;
  }

  Money unitPrice(ProductDef product, int quantity, Fx level) {
    if (supplier case final supplier?) {
      return supplier.unitPrice(product, quantity, level);
    }
    return marketQuote(_content!, country, product, quantity, level)?.price ??
        Money.zero;
  }

  Command order(PersonId actor, StoreId store, List<OrderQuantity> lines) =>
      switch (supplier) {
        final supplier? => PlaceOrder(
          actor,
          store: store,
          supplier: supplier.id,
          lines: lines,
        ),
        null => OrderFromFactory(
          actor,
          store: store,
          factory: factory!.id,
          lines: lines,
        ),
      };
}

/// One of the player's factories, as the store's supplier of what it makes.
class _FactoryTile extends StatelessWidget {
  const _FactoryTile({
    required this.factory,
    required this.store,
    required this.onOrder,
  });

  final FactoryView factory;
  final StoreView store;
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final seller = Seller.factory(game, factory, store);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(factory.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        [
          tr('orders.yourFactory'),
          tr('orders.deliversIn', {'count': seller.leadTimeDays}),
          tr('orders.payWithin', {'days': seller.paymentTermsDays}),
          tr('orders.perProduct', {'units': seller.minOrderUnits}),
          tr('orders.atWholesale'),
        ].join(' · '),
      ),
      trailing: OutlinedButton(
        onPressed: onOrder,
        child: Text(tr('orders.order')),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({required this.supplier, required this.onOrder});

  final SupplierDef supplier;
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final discounts = [
      for (final tier in supplier.volumeDiscounts)
        tr('orders.discount', {
          'share': percent(tier.discount, decimals: 0),
          'units': tier.minUnits,
        }),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(supplier.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        [
          tr('orders.deliversIn', {'count': supplier.leadTimeDays}),
          supplier.paymentTermsDays == 0
              ? tr('orders.cashOnDelivery')
              : tr('orders.payWithin', {'days': supplier.paymentTermsDays}),
          tr('orders.perProduct', {'units': supplier.minOrderUnits}),
          ...discounts,
        ].join(' · '),
      ),
      isThreeLine: true,
      trailing: OutlinedButton(
        onPressed: onOrder,
        child: Text(tr('orders.order')),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final OrderView order;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final total = order.lines.fold(
      Money.zero,
      (sum, line) => sum + line.unitPrice.timesInt(line.quantity),
    );
    final factory = switch (order.factory) {
      final id? => game.factory(id),
      null => null,
    };
    final store = game.myStores
        .where((pair) => pair.$2.id == order.store)
        .firstOrNull
        ?.$2;
    final lead = factory != null && store != null
        ? Seller.factory(game, factory, store).leadTimeDays
        : game.content.suppliers[order.supplier.index].leadTimeDays;
    final left = order.arrival.number - game.today.number;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Line(
            tr('orders.arriving', {
              'supplier':
                  factory?.name ??
                  game.content.suppliers[order.supplier.index].name,
              'weekday': weekday(order.arrival),
              'date': shortDate(order.arrival),
            }),
            money(total),
            hint: [
              for (final line in order.lines)
                '${line.quantity} ${game.content.products[line.product.index].name}',
            ].join(', '),
          ),
          LevelBar(lead == 0 ? 1 : 1 - left / lead, height: 4),
        ],
      ),
    );
  }
}

/// Picks quantities of each product [seller] sells, for [store].
class OrderSheet extends StatefulWidget {
  const OrderSheet({super.key, required this.seller, required this.store});

  final Seller seller;
  final StoreView store;

  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  final _quantities = <ProductId, int>{};

  Seller get _supplier => widget.seller;

  /// The store as of today: the clock may run while the sheet is open.
  StoreView get _store => context.game.company!.stores.firstWhere(
    (store) => store.id == widget.store.id,
    orElse: () => widget.store,
  );

  /// The products the supplier sells that the store stocks, or will.
  List<ProductDef> _products(SimulationController game) => [
    for (final product in game.content.products)
      if (_supplier.sells(game, _store, product) &&
          game.priceOf(_store, product.id) != null)
        product,
  ];

  /// Enough for a week after delivery, or the shelf life if shorter, less
  /// what will be left by then, at the recent pace of sales and stockouts;
  /// in whole minimum orders. Without history, it assumes what the
  /// scenario's AI owners of the same format expect a new store to sell.
  int _suggestion(SimulationController game, ProductDef product) {
    final id = product.id;
    final sales = _store.sales;
    // Units wanted over [days], rounded up.
    int over(int days) {
      if (sales.days == 0) {
        // Strategies for the same kind of business.
        final content = game.content;
        final channel = content.formatChannels[_store.format.index];
        final strategies = [
          for (final strategy in content.strategies)
            if (content.formatChannels[strategy.format.index] == channel)
              strategy,
        ];
        final daily = strategies.fold(
          0,
          (sum, strategy) => sum + strategy.openingForecast.raw,
        );
        final per = strategies.length * Fx.scale;
        return (daily * days + per - 1) ~/ per;
      }
      final recorded = sales.days < _forecastDays ? sales.days : _forecastDays;
      final units =
          sales.total(SalesCount.sold, id, recorded) +
          sales.total(SalesCount.outOfStock, id, recorded);
      return (units * days + recorded - 1) ~/ recorded;
    }

    var cover = _coverDays;
    if (product.shelfLifeDays case final life? when life < cover) cover = life;
    var left =
        _store.stock[id.index] +
        _store.onOrder[id.index] -
        over(_supplier.leadTimeDays);
    if (left < 0) left = 0;
    final need = over(cover) - left;
    final minimum = _supplier.minOrderUnits;
    return need <= 0 ? 0 : (need + minimum - 1) ~/ minimum * minimum;
  }

  /// Fills in [_suggestion]s, scaled down to fit the free storage.
  void _suggest(SimulationController game, List<ProductDef> products) {
    final suggested = {
      for (final product in products) product.id: _suggestion(game, product),
    };
    final total = suggested.values.fold(0, (sum, units) => sum + units);
    var free =
        _store.storageUnits -
        _store.stock.fold(0, (sum, units) => sum + units) -
        _store.onOrder.fold(0, (sum, units) => sum + units);
    if (free < 0) free = 0;
    final minimum = _supplier.minOrderUnits;
    setState(() {
      suggested.forEach((product, units) {
        _quantities[product] = total <= free
            ? units
            : units * free ~/ total ~/ minimum * minimum;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final products = _products(game);
    final level = game.view.economy(_supplier.country).priceIndex;
    final minimum = _supplier.minOrderUnits;
    var units = 0;
    var total = Money.zero;
    var tooSmall = false;
    for (final product in products) {
      final quantity = _quantities[product.id] ?? 0;
      if (quantity == 0) continue;
      units += quantity;
      total += _supplier.unitPrice(product, quantity, level).timesInt(quantity);
      if (quantity < minimum) tooSmall = true;
    }
    final stocked =
        _store.stock.fold(0, (sum, units) => sum + units) +
        _store.onOrder.fold(0, (sum, units) => sum + units);
    final overflow = stocked + units - _store.storageUnits;
    final company = game.company!;
    final free = company.cash - company.committed;
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
                  tr('orders.orderFrom', {'supplier': _supplier.name}),
                  style: theme.textTheme.titleLarge,
                ),
                Hint(
                  tr('orders.arrives', {
                    'date': shortDate(game.today + _supplier.leadTimeDays),
                    'minimum': minimum,
                  }),
                ),
                if (products.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(tr('orders.suggest')),
                      onPressed: () => _suggest(game, products),
                    ),
                  ),
                if (products.isEmpty) Hint(tr('orders.nothingStocked')),
                for (final product in products)
                  _QuantityRow(
                    product: product,
                    store: _store,
                    unitPrice: _supplier.unitPrice(
                      product,
                      _quantities[product.id] ?? minimum,
                      level,
                    ),
                    quantity: _quantities[product.id] ?? 0,
                    step: minimum,
                    onChanged: (quantity) =>
                        setState(() => _quantities[product.id] = quantity),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Line(
                  tr('orders.units', {'units': units}),
                  money(total),
                  strong: true,
                ),
                Line(
                  _supplier.paymentTermsDays == 0
                      ? tr('orders.paidOnDelivery')
                      : tr('orders.dueAfter', {
                          'days': _supplier.paymentTermsDays,
                        }),
                  tr('orders.freeCash', {'amount': money(free - total)}),
                  color: gainColor(context, (free - total).cents.sign),
                ),
                if (overflow > 0)
                  Hint(
                    tr('orders.overflow', {
                      'storage': _store.storageUnits,
                      'overflow': overflow,
                    }),
                  ),
                if (tooSmall)
                  Hint(tr('orders.needAtLeast', {'minimum': minimum})),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: units == 0 || tooSmall
                      ? null
                      : () {
                          game.submit(
                            _supplier.order(game.player, _store.id, [
                              for (final product in products)
                                if ((_quantities[product.id] ?? 0) > 0)
                                  (
                                    product: product.id,
                                    quantity: _quantities[product.id]!,
                                  ),
                            ]),
                          );
                          Navigator.pop(context);
                        },
                  child: Text(tr('orders.placeOrder')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.product,
    required this.store,
    required this.unitPrice,
    required this.quantity,
    required this.step,
    required this.onChanged,
  });

  final ProductDef product;
  final StoreView store;
  final Money unitPrice;
  final int quantity;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final id = product.id;
    final sold = store.sales.total(SalesCount.sold, id, _forecastDays);
    final days = store.sales.days < _forecastDays
        ? store.sales.days
        : _forecastDays;
    return Row(
      children: [
        Expanded(
          child: Line(
            product.name,
            '',
            hint: tr('orders.quantityLine', {
              'price': money(unitPrice),
              'stock': store.stock[id.index],
              'coming': store.onOrder[id.index] > 0
                  ? ' +${store.onOrder[id.index]}'
                  : '',
              'sells': days == 0
                  ? ''
                  : tr('orders.sellsPerDay', {'units': _perDay(sold, days)}),
            }),
          ),
        ),
        CountStepper(
          value: quantity ~/ step,
          max: 100,
          label: '$quantity',
          onChanged: (count) => onChanged(count * step),
        ),
      ],
    );
  }

  static String _perDay(int units, int days) {
    final tenths = (units * 10 + days ~/ 2) ~/ days;
    return '${tenths ~/ 10}${tr('format.decimal')}${tenths % 10}';
  }
}

/// The company's orders on their way.
class _OnTheWay extends StatelessWidget {
  const _OnTheWay();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.company;
    if (company == null) return Hint(tr('orders.noCompany'));
    return Section(
      title: tr('orders.onTheWay'),
      icon: Icons.local_shipping_outlined,
      children: [
        if (company.orders.isEmpty) Hint(tr('orders.nothingOnOrderHint')),
        for (final order in company.orders) _OrderTile(order: order),
      ],
    );
  }
}

/// The company's bills not yet paid, the overdue in red.
class _Bills extends StatelessWidget {
  const _Bills();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.company;
    if (company == null) return Hint(tr('orders.noCompany'));
    return Section(
      title: tr('common.unpaidBills'),
      icon: Icons.receipt_long_outlined,
      children: [
        if (company.bills.isEmpty) Hint(tr('orders.allPaidHint')),
        for (final bill in company.bills)
          Line(
            OrdersScreen._creditorName(game, bill.creditor),
            money(bill.amount),
            hint: bill.due < game.today
                ? tr('orders.overdueSince', {'date': shortDate(bill.due)})
                : tr('orders.due', {'date': shortDate(bill.due)}),
            color: bill.due < game.today
                ? Theme.of(context).colorScheme.error
                : null,
          ),
      ],
    );
  }
}
