import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'orders.dart';

/// Days of sales the store screen sums.
const recentDays = 7;

/// The cheapest unit price any supplier asks for [product] at its minimum
/// order, at today's prices; null if nobody sells it.
Money? supplierCost(SimulationController game, ProductDef product) {
  Money? best;
  for (final supplier in game.content.suppliers) {
    if (!supplier.carries[product.id.index]) continue;
    final price = supplier.unitPrice(
      product,
      supplier.minOrderUnits,
      game.view.macro.priceIndex,
    );
    if (best == null || price < best) best = price;
  }
  return best;
}

/// The parts of the shop tab.
enum ShopPart { shelves, supplies, running }

/// One of the player's stores, in three parts: its shelves (each product's
/// price, stock, sales and misses), its supplies (suppliers, orders and
/// bills), and its running (the site and its size, the manager, staff and
/// marketing).
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key, required this.part, required this.onPart});

  final ShopPart part;
  final ValueChanged<ShopPart> onPart;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final store = game.store;
    if (store == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(tr('store.noStore')),
        ),
      );
    }
    final format = game.content.formats[store.format.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SegmentedButton<ShopPart>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ShopPart.shelves,
                label: Text(tr('store.parts.shelves')),
              ),
              ButtonSegment(
                value: ShopPart.supplies,
                label: Text(tr('store.parts.supplies')),
              ),
              ButtonSegment(
                value: ShopPart.running,
                label: Text(tr('store.parts.running')),
              ),
            ],
            selected: {part},
            onSelectionChanged: (picked) => onPart(picked.single),
          ),
        ),
        Expanded(
          child: switch (part) {
            ShopPart.shelves => ListView(
              key: const PageStorageKey('shelves'),
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                // Only what the store's format sells.
                for (final category in game.content.categories)
                  if (format.sells[category.id.index])
                    _Category(store: store, category: category),
              ],
            ),
            ShopPart.supplies => const OrdersScreen(),
            // A short page, laid out whole rather than lazily.
            ShopPart.running => SingleChildScrollView(
              key: const PageStorageKey('running'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StoreHeader(store: store),
                  _Running(store: store),
                ],
              ),
            ),
          },
        ),
      ],
    );
  }
}

/// The store's running as a contents: its staff, its manager, its
/// marketing and what it could become, each a page.
class _Running extends StatelessWidget {
  const _Running({required this.store});

  final StoreView store;

  /// Pages for the store being looked at, as it is when they show.
  static List<Widget> Function(BuildContext) _page(
    Widget Function(StoreView store) build,
  ) =>
      (context) => switch (context.game.store) {
        final store? => [build(store)],
        null => [Hint(tr('store.youHaveNoStore'))],
      };

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final format = content.formats[store.format.index];
    final staff = game.staffOf(store);
    final wages = content.operations.slotWage
        .times(game.wageLevel(store.market))
        .times(format.wageFactor)
        .timesInt(staff.fold(0, (sum, count) => sum + count));
    final manager = game.managerOf(store);
    final share = game.marketingOf(store);
    final channel = content.formatChannels[format.id.index];
    final target = content.formats
        .where(
          (other) =>
              content.formatChannels[other.id.index] == channel &&
              other.fitOut > format.fitOut,
        )
        .firstOrNull;
    return Section(
      title: tr('store.runningIt'),
      children: [
        IndexRow(
          title: tr('store.staffHours'),
          subtitle: staff.every((count) => count == 0)
              ? tr('store.nobodyOnStaff')
              : tr('store.staffSummary', {'staff': staff.join(' · ')}),
          value: money(wages, cents: false),
          onTap: () => context.openPage(
            tr('store.staffHours'),
            _page((store) => _Staffing(store: store)),
          ),
        ),
        IndexRow(
          title: tr('store.manager'),
          subtitle: manager == null
              ? tr('store.noManager')
              : tr('store.managerSummary', {
                  'grade': content.managers.grades[manager.grade.index].name,
                  'strategy': content.strategies[manager.strategy.index].name
                      .toLowerCase(),
                }),
          onTap: () => context.openPage(
            tr('store.manager'),
            _page((store) => _ManagerCard(store: store)),
          ),
        ),
        IndexRow(
          title: tr('store.marketing'),
          subtitle: share == Fx.zero
              ? tr('store.none')
              : tr('store.marketingSummary', {'share': percent(share)}),
          value: share == Fx.zero
              ? null
              : money(game.recentDailySales(store).times(share)),
          onTap: () => context.openPage(
            tr('store.marketing'),
            _page((store) => _Marketing(store: store)),
          ),
        ),
        if (game.content.demand.reputationWeight > Fx.zero)
          IndexRow(
            title: tr('store.reputation'),
            subtitle: tr('store.reputationPitch'),
            value: percent(store.reputation, decimals: 0),
            onTap: () => context.openPage(
              tr('store.reputation'),
              _page((store) => _Reputation(store: store)),
            ),
          ),
        if (target != null)
          IndexRow(
            title: tr('store.become', {'format': aFormat(target)}),
            subtitle: tr('store.becomeSummary', {
              'slots': target.slotBonus,
              'storage': target.storageBonus,
            }),
            onTap: () => context.openPage(
              tr('store.become', {'format': aFormat(target)}),
              _page((store) => _Conversion(store: store)),
            ),
          ),
      ],
    );
  }
}

/// What the store would sell for today, what that rests on, and who would
/// buy it.
class SaleSection extends StatelessWidget {
  const SaleSection({super.key, required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final view = game.view;
    final value = view.valuations[store.id.index];
    final terms = game.content.acquisitions;
    if (value == null || terms == null) return const SizedBox.shrink();
    // Earnings beyond the fair return are worth this many years of them.
    final years = Fx.one
        .div(terms.capitalization)
        .toDecimalString()
        .replaceFirst(RegExp(r'\.?0+$'), '')
        .replaceFirst('.', tr('format.decimal'));
    final name = game.storeName(store.id);
    final buyer = store.buyer;
    final gain = value.price - value.stock - store.boughtFor;
    final young = game.today.number - store.opensOn.number < salesHistoryDays;
    final pending = game.pending.any(
      (c) => c is SellStore && c.store == store.id,
    );
    return Section(
      title: tr('store.sell', {'store': name}),
      mark: Ledger.of(context).trade(game.content.formats[store.format.index]),
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
          color: young ? null : gainColor(context, value.earnings.cents.sign),
          hint: tr('store.atLastSales'),
        ),
        Line(
          tr('common.fittings'),
          money(value.fittings, cents: false),
          hint: tr('store.fittingsHint'),
        ),
        Line(tr('common.stockAtCost'), money(value.stock, cents: false)),
        Line(
          store.boughtFor > Money.zero
              ? tr('store.gainOverPaid')
              : tr('store.gain'),
          signedMoney(gain, cents: false),
          color: gainColor(context, gain.cents.sign),
          hint: tr('store.taxedWithProfit'),
        ),
        Hint(
          buyer == null
              ? tr('store.noBuyerHint', {
                  'reserve': percent(terms.buyerReserve, decimals: 0),
                })
              : tr('store.priceHint', {
                  'years': years,
                  'ret': percent(terms.tangibleReturn, decimals: 0),
                  'floor': percent(terms.distressFloor, decimals: 0),
                }),
        ),
        if (pending)
          Hint(tr('store.soldTomorrow'))
        else
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sell_outlined, size: 18),
              onPressed: buyer == null
                  ? null
                  : () async {
                      final buyerName = view.companyNames[buyer.index];
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            tr('store.sellQuestion', {'store': name}),
                          ),
                          content: Text(
                            tr('store.sellBody', {
                              'buyer': buyerName,
                              'price': money(value.price, cents: false),
                            }),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(tr('common.keepIt')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(tr('common.sell')),
                            ),
                          ],
                        ),
                      );
                      if (yes ?? false) {
                        game.submit(SellStore(game.player, store: store.id));
                      }
                    },
              label: Text(
                buyer == null
                    ? tr('store.noBuyer')
                    : tr('store.sellTo', {
                        'buyer': view.companyNames[buyer.index],
                      }),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final site = game.content.sites[store.site.index];
    final listed = [
      for (final product in game.content.products)
        if (game.priceOf(store, product.id) != null) product,
    ].length;
    final stocked = store.stock.fold(0, (sum, units) => sum + units);
    final name = game.storeName(store.id);
    final renaming = name != game.view.shelves[store.id.index].name;
    final (status, statusColor) = switch (store.status) {
      StoreStatus.open => (tr('store.open'), gainTone(context, 1)),
      StoreStatus.building => (
        tr('store.opens', {'date': shortDate(store.opensOn)}),
        scheme.tertiary,
      ),
      StoreStatus.closed => (tr('common.closed'), scheme.error),
    };
    final format = game.content.formats[store.format.index];
    return Section(
      title: renaming ? tr('store.fromTomorrow', {'name': name}) : name,
      mark: Ledger.of(context).trade(format),
      trailing: store.status == StoreStatus.closed
          ? null
          : IconButton(
              tooltip: tr('store.rename'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => showRename(context, game, store),
            ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(status, color: statusColor),
            Text(
              [
                format.name,
                site.name,
                if (game.content.markets.length > 1)
                  game.content.markets[store.market.index].name,
                tr('common.locationLine', {
                  'location': percent(site.location, decimals: 0),
                }),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Capacity(
                label: tr('store.shelfSlotsUsed'),
                used: listed,
                of: store.shelfSlots,
                unit: '',
              ),
              const SizedBox(height: 8),
              _Capacity(
                label: tr('store.storageUsed'),
                used: stocked,
                of: store.storageUnits,
                unit: tr('store.unitsSuffix'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _Size(store: store),
      ],
    );
  }
}

/// How much of a capacity is used, as a line and a bar.
class _Capacity extends StatelessWidget {
  const _Capacity({
    required this.label,
    required this.used,
    required this.of,
    required this.unit,
  });

  final String label;
  final int used;
  final int of;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = of == 0 ? 0.0 : used / of;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              tr('store.usedOf', {'used': used, 'of': of, 'unit': unit}),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LevelBar(
          fill,
          color: fill > 0.95
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary,
        ),
      ],
    );
  }
}

class _Staffing extends StatelessWidget {
  const _Staffing({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final operations = game.content.operations;
    final staff = game.staffOf(store);
    final days = store.sales.days < recentDays ? store.sales.days : recentDays;
    // A restaurant's crew costs more than a shop assistant.
    final wage = operations.slotWage
        .times(game.wageLevel(store.market))
        .times(game.content.formats[store.format.index].wageFactor);
    final total = staff.fold(0, (sum, count) => sum + count);
    final closed = store.status == StoreStatus.closed;
    final managed = game.delegates(store, ManagerDuty.staffing);
    return Section(
      title: tr('store.staffHours'),
      icon: Icons.schedule,
      children: [
        Hint(
          managed
              ? tr('store.managerSetsStaff')
              : tr('store.staffHint', {'visits': operations.visitsPerStaff}),
        ),
        for (final slot in DaySlot.values)
          Row(
            children: [
              Icon(
                slotIcon(slot),
                size: 22,
                color: staff[slot.index] == 0
                    ? Theme.of(context).colorScheme.outline
                    : Theme.of(context).colorScheme.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Line(
                  slotName(slot),
                  '',
                  hint: staff[slot.index] == 0
                      ? tr('common.closed')
                      : days == 0
                      ? tr('store.noShoppersYet')
                      : tr('store.slotDetails', {
                          'shoppers': store.sales.visits(slot, days) ~/ days,
                          'service': percent(
                            store.service[slot.index],
                            decimals: 0,
                          ),
                        }),
                ),
              ),
              CountStepper(
                value: staff[slot.index],
                max: operations.maxStaffPerSlot,
                enabled: !closed && !managed,
                onChanged: (count) => game.submit(
                  SetStaffing(
                    game.player,
                    store: store.id,
                    staff: [
                      for (final s in DaySlot.values)
                        s == slot ? count : staff[s.index],
                    ],
                  ),
                ),
              ),
            ],
          ),
        Line(
          tr('store.wages'),
          tr('common.perDay', {'amount': money(wage.timesInt(total))}),
          hint: tr('store.perPersonSlot', {'wage': money(wage)}),
        ),
      ],
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({required this.store, required this.category});

  final StoreView store;
  final CategoryDef category;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return Section(
      title: category.name,
      icon: categoryIcon(category),
      children: [
        for (final product in game.content.products)
          if (product.category == category.id)
            _ProductTile(store: store, product: product),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.store, required this.product});

  final StoreView store;
  final ProductDef product;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final id = product.id;
    final price = game.priceOf(store, id);
    final listed = price != null;
    final cost = supplierCost(game, product);
    final sales = store.sales;
    int recent(SalesCount count) => sales.total(count, id, recentDays);
    final rivals = [
      for (final shelf in game.view.shelves)
        if (shelf.id != store.id &&
            shelf.status == StoreStatus.open &&
            shelf.market == store.market)
          ?shelf.prices[id.index],
    ]..sort((a, b) => a.cents.compareTo(b.cents));
    final missed = [
      if (recent(SalesCount.outOfStock) case final units when units > 0)
        tr('store.missOutOfStock', {'units': units}),
      if (recent(SalesCount.overpriced) case final units when units > 0)
        tr('store.missTooDear', {'units': units}),
      if (recent(SalesCount.notListed) case final units when units > 0)
        tr('store.missNotStocked', {'units': units}),
    ];
    final slotsFull =
        [
          for (final p in game.content.products)
            if (game.priceOf(store, p.id) != null) p,
        ].length >=
        store.shelfSlots;
    final details = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final managedPrice = listed && game.delegates(store, ManagerDuty.pricing);
    final managedRange = game.delegates(store, ManagerDuty.assortment);
    final stock = store.stock[id.index];
    final sold = recent(SalesCount.sold);
    final days = sales.days < recentDays ? sales.days : recentDays;
    // Days the stock and what is coming last at the recent pace; null
    // without sales.
    final cover = sold == 0 || days == 0
        ? null
        : (stock + store.onOrder[id.index]) * days ~/ sold;
    final coverColor = cover == null
        ? theme.colorScheme.outline
        : cover < 2
        ? theme.colorScheme.error
        : cover < 5
        ? theme.colorScheme.tertiary
        : gainTone(context, 1);
    final marginShare = listed && cost != null && price.cents > 0
        ? (price.cents - cost.cents) * 100 ~/ price.cents
        : null;
    return InkWell(
      onTap:
          store.status == StoreStatus.closed ||
              managedPrice ||
              (!listed && managedRange)
          ? null
          : () => _editPrice(context, game, price, cost, rivals),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.name,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Pill(
                        product.tier == ProductTier.premium
                            ? tr('store.premium')
                            : tr('store.budget'),
                        color: product.tier == ProductTier.premium
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.primary,
                      ),
                      if (game.isPending(store.id, id)) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: theme.colorScheme.secondary,
                        ),
                      ],
                    ],
                  ),
                  if (managedPrice)
                    Text(
                      tr('store.pricedByManager'),
                      style: details?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        listed ? money(price) : tr('store.notStocked'),
                        style: listed
                            ? figures(
                                theme.textTheme.titleMedium,
                              ).copyWith(fontWeight: FontWeight.w600)
                            : theme.textTheme.titleMedium,
                      ),
                      if (cost != null)
                        Text(
                          tr('store.cost', {'cost': money(cost)}),
                          style: details,
                        ),
                      if (marginShare != null)
                        Pill(
                          tr('store.marginPill', {
                            'margin': _margin(price!, cost!),
                          }),
                          color: marginShare >= 30
                              ? gainTone(context, 1)
                              : marginShare >= 15
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.error,
                        ),
                    ],
                  ),
                  Text(
                    rivals.isEmpty
                        ? tr('store.noRival')
                        : tr('store.rivals', {
                            'low': money(rivals.first),
                            'high': rivals.length > 1
                                ? '–${money(rivals.last)}'
                                : '',
                          }),
                    style: details,
                  ),
                  if (listed) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: LevelBar(
                            cover == null ? (stock > 0 ? 1 : 0) : cover / 14,
                            color: coverColor,
                            height: 5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(switch (cover) {
                          null =>
                            stock > 0
                                ? tr('store.noSalesYet')
                                : tr('store.empty'),
                          0 => tr('store.underADay'),
                          1 => tr('store.aDay'),
                          _ => tr('common.daysOfStock', {'cover': cover}),
                        }, style: details?.copyWith(color: coverColor)),
                      ],
                    ),
                  ],
                  Text(
                    tr('store.stockLine', {
                      'stock': stock,
                      'coming': store.onOrder[id.index] > 0
                          ? tr('store.coming', {
                              'units': store.onOrder[id.index],
                            })
                          : '',
                      'sold': sold,
                      'days': recentDays,
                    }),
                    style: details,
                  ),
                  if (missed.isNotEmpty)
                    Text(
                      tr('store.missed', {'misses': missed.join(', ')}),
                      style: details?.copyWith(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
            Switch(
              value: listed,
              onChanged:
                  store.status == StoreStatus.closed ||
                      managedRange ||
                      (!listed && slotsFull)
                  ? null
                  : (on) => on
                        ? _list(context, game, cost, rivals)
                        : _delist(context, game),
            ),
          ],
        ),
      ),
    );
  }

  static String _margin(Money price, Money cost) =>
      price.cents == 0 ? '–' : share(price.cents - cost.cents, price.cents);

  Future<void> _editPrice(
    BuildContext context,
    SimulationController game,
    Money? price,
    Money? cost,
    List<Money> rivals,
  ) async {
    if (price == null) return _list(context, game, cost, rivals);
    final next = await askAmount(
      context,
      title: tr('store.priceOf', {'product': product.name}),
      message: _priceContext(cost, rivals),
      initial: price,
      action: tr('store.setPrice'),
    );
    if (next != null) {
      game.submit(
        SetPrice(
          game.player,
          store: store.id,
          product: product.id,
          price: next,
        ),
      );
    }
  }

  Future<void> _list(
    BuildContext context,
    SimulationController game,
    Money? cost,
    List<Money> rivals,
  ) async {
    final price = await askAmount(
      context,
      title: tr('store.stockProduct', {'product': product.name}),
      message: tr('store.stockMessage', {
        'context': _priceContext(cost, rivals),
      }),
      initial:
          store.prices[product.id.index] ??
          (rivals.isNotEmpty ? rivals.first : cost?.times(Fx.parse('1.5'))),
      action: tr('store.stockIt'),
    );
    if (price != null) {
      game.submit(
        ListProduct(
          game.player,
          store: store.id,
          product: product.id,
          price: price,
        ),
      );
    }
  }

  Future<void> _delist(BuildContext context, SimulationController game) async {
    final stock = store.stock[product.id.index];
    if (stock > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('store.stopSelling', {'product': product.name})),
          content: Text(tr('store.stopSellingBody', {'stock': stock})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('common.keepIt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('store.stopSellingAction')),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    game.submit(
      DelistProduct(game.player, store: store.id, product: product.id),
    );
  }

  static String _priceContext(Money? cost, List<Money> rivals) => [
    if (cost != null) tr('store.suppliersFrom', {'cost': money(cost)}),
    if (rivals.isNotEmpty)
      rivals.length > 1
          ? tr('store.rivalsChargeRange', {
              'low': money(rivals.first),
              'high': money(rivals.last),
            })
          : tr('store.rivalsCharge', {'price': money(rivals.first)}),
  ].join(' ');
}

/// Who runs the store for the player, if anyone, and the way to hire, brief
/// or let them go.
class _ManagerCard extends StatelessWidget {
  const _ManagerCard({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final manager = game.managerOf(store);
    final content = game.content;
    final closed = store.status == StoreStatus.closed;
    final directed = game.view.companies.any(
      (company) =>
          company.director != null &&
          company.stores.any((other) => other.id == store.id),
    );
    void brief() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GameScope(
        controller: game,
        child: ManagerSheet(store: store),
      ),
    );
    if (manager == null) {
      return Section(
        title: tr('store.manager'),
        icon: Icons.badge_outlined,
        children: [
          Hint(tr('store.managerPitch')),
          if (directed && !closed) Hint(tr('store.directorHiresTomorrow')),
          if (!closed)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: brief,
                child: Text(tr('store.hireManager')),
              ),
            ),
        ],
      );
    }
    final grade = content.managers.grades[manager.grade.index];
    final strategy = content.strategies[manager.strategy.index];
    return Section(
      title: tr('store.manager'),
      icon: Icons.badge_outlined,
      children: [
        Line(
          capitalized(managerOf(grade)),
          tr('common.perDay', {
            'amount': money(grade.salary.times(game.wageLevel(store.market))),
          }),
          strong: true,
          hint: tr('store.managerSince', {
            'strategy': strategy.name,
            'date': shortDate(manager.hiredOn),
            'year': manager.hiredOn.date.year,
          }),
        ),
        Hint(
          tr('store.looksAfter', {
            'duties': [
              for (final duty in ManagerDuty.values)
                if (manager.duties[duty.index]) dutyName(duty),
            ].join(', '),
          }),
        ),
        if (directed) Hint(tr('store.directorRehires')),
        if (!closed)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: brief,
                child: Text(tr('common.changeBrief')),
              ),
              TextButton(
                onPressed: () =>
                    game.submit(FireManager(game.player, store: store.id)),
                child: Text(tr('common.letGo')),
              ),
            ],
          ),
      ],
    );
  }
}

/// Picks a manager's grade, strategy and duties, for hiring or a new brief.
class ManagerSheet extends StatefulWidget {
  const ManagerSheet({super.key, required this.store});

  final StoreView store;

  @override
  State<ManagerSheet> createState() => _ManagerSheetState();
}

class _ManagerSheetState extends State<ManagerSheet> {
  ManagerGradeId? _grade;
  StrategyId? _strategy;
  List<bool>? _duties;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final current = game.managerOf(widget.store);
    final grades = content.managers.grades;
    final grade = _grade ?? current?.grade ?? grades[grades.length ~/ 2].id;
    // Strategies that run this kind of business: a convenience store's run a
    // supermarket too.
    final channel = content.formatChannels[widget.store.format.index];
    final strategies = [
      for (final option in content.strategies)
        if (content.formatChannels[option.format.index] == channel) option,
    ];
    final strategy =
        _strategy ??
        current?.strategy ??
        strategies
            .firstWhere(
              (s) => s.marketPosition == Fx.zero,
              orElse: () => strategies.first,
            )
            .id;
    final duties =
        _duties ??
        current?.duties ??
        [
          for (final duty in ManagerDuty.values)
            duty == ManagerDuty.ordering || duty == ManagerDuty.pricing,
        ];
    final wageIndex = game.wageLevel(widget.store.market);
    Widget choice({
      required bool selected,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      title: Text(title),
      subtitle: Text(subtitle),
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
                      ? tr('store.hireManager')
                      : tr('store.briefManager'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(tr('common.who'), style: theme.textTheme.titleSmall),
                for (final option in grades)
                  choice(
                    selected: option.id == grade,
                    title: tr('store.gradeLine', {
                      'grade': option.name,
                      'salary': money(option.salary.times(wageIndex)),
                    }),
                    subtitle: _misjudges(content, option),
                    onTap: () => setState(() => _grade = option.id),
                  ),
                const SizedBox(height: 8),
                Text(tr('store.strategy'), style: theme.textTheme.titleSmall),
                for (final option in strategies)
                  choice(
                    selected: option.id == strategy,
                    title: option.name,
                    subtitle: _stance(option),
                    onTap: () => setState(() => _strategy = option.id),
                  ),
                const SizedBox(height: 8),
                Text(tr('store.duties'), style: theme.textTheme.titleSmall),
                for (final duty in ManagerDuty.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: duties[duty.index],
                    title: Text(capitalized(dutyName(duty))),
                    subtitle: Text(switch (duty) {
                      ManagerDuty.ordering => tr('store.dutyHints.ordering'),
                      ManagerDuty.pricing => tr('store.dutyHints.pricing'),
                      ManagerDuty.assortment => tr(
                        'store.dutyHints.assortment',
                      ),
                      ManagerDuty.staffing => tr('store.dutyHints.staffing'),
                      ManagerDuty.investing => tr('store.dutyHints.investing'),
                    }),
                    onChanged: (on) => setState(
                      () => _duties = [
                        for (final d in ManagerDuty.values)
                          d == duty ? on! : duties[d.index],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: duties.contains(true)
                  ? () {
                      game.submit(
                        HireManager(
                          game.player,
                          store: widget.store.id,
                          grade: grade,
                          strategy: strategy,
                          duties: duties,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(
                current == null
                    ? tr('common.hire')
                    : current.grade == grade
                    ? tr('common.updateBrief')
                    : tr('store.replaceManager'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _misjudges(ContentDb content, ManagerGradeDef grade) {
    final unskilled = Fx.one - grade.skill;
    return tr('store.misjudges', {
      'demand': percent(
        content.managers.forecastError * unskilled,
        decimals: 0,
      ),
      'prices': percent(content.managers.priceError * unskilled, decimals: 0),
    });
  }

  static String _stance(StrategyDef strategy) {
    final position = strategy.marketPosition;
    final against = position == Fx.zero
        ? tr('store.pricesWithMarket')
        : tr(position.raw < 0 ? 'store.pricesBelow' : 'store.pricesAbove', {
            'share': percent(
              position.raw < 0 ? -position : position,
              decimals: 0,
            ),
          });
    final hours = [
      for (final slot in DaySlot.values)
        if (strategy.hours[slot.index]) slotName(slot).toLowerCase(),
    ];
    final stance = tr('store.stance', {
      'against': against,
      'markup': percent(strategy.markup, decimals: 0),
      'hours': hours.join(', '),
    });
    return switch (stanceAdvice(strategy)) {
      final advice? => '$stance. $advice',
      null => stance,
    };
  }
}

/// The store's floor area, works under way, and the way to enlarge it.
class _Size extends StatelessWidget {
  const _Size({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final expansion = content.expansion;
    final site = content.sites[store.site.index];
    final works = store.works;
    final pending = game.pending.any(
      (command) => command is ExpandStore && command.store == store.id,
    );
    final room = store.area + expansion.stepArea <= site.maxArea;
    final canEnlarge =
        works == null &&
        !pending &&
        room &&
        store.status != StoreStatus.closed &&
        game.company?.status == CompanyStatus.active;
    return Row(
      children: [
        Expanded(
          child: Line(
            tr('store.floorArea'),
            tr('common.areaM2', {'area': store.area}),
            hint: switch (works) {
              (:final area, :final done, format: final next?) =>
                tr('store.becoming', {
                  'format': aFormat(game.content.formats[next.index]),
                  'area': area,
                  'date': shortDate(done),
                }),
              (:final area, :final done, format: null) => tr('store.growing', {
                'area': area,
                'date': shortDate(done),
              }),
              null when pending => tr('store.worksTomorrow'),
              null when !room => tr('store.asBigAsAllowed'),
              null => tr('store.roomFor', {'area': site.maxArea}),
            },
          ),
        ),
        if (canEnlarge)
          TextButton(
            onPressed: () => _confirm(context, game),
            child: Text(tr('store.enlarge')),
          ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, SimulationController game) async {
    final content = game.content;
    final expansion = content.expansion;
    final site = content.sites[store.site.index];
    final level = game.view.macro.priceIndex;
    final area = store.area + expansion.stepArea;
    final format = content.formats[store.format.index];
    final rent = (site.rentFor(store.area) + format.overheadsFor(store.area))
        .times(level);
    final newRent = (site.rentFor(area) + format.overheadsFor(area)).times(
      level,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('store.enlargeTo', {'area': area})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Line(tr('store.worksPaidNow'), money(expansion.cost(level))),
            Line(
              tr('store.readyIn'),
              tr('common.nDays', {'days': expansion.buildDays}),
            ),
            Line(
              tr('store.rentUpkeep'),
              tr('common.perMonth', {'amount': money(newRent, cents: false)}),
              hint: tr('store.rentNow', {'amount': money(rent, cents: false)}),
            ),
            Line(tr('store.shelfSlots'), '+${expansion.shelfSlots}'),
            Line(
              tr('store.storage'),
              tr('store.plusUnits', {'units': expansion.storageUnits}),
            ),
            Hint(tr('store.keepsTrading')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('common.notNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('store.enlarge')),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      game.submit(ExpandStore(game.player, store: store.id));
    }
  }
}

/// Asks for a new name for [store], and for its company too if it shares
/// the name.
Future<void> showRename(
  BuildContext context,
  SimulationController game,
  StoreView store,
) => showDialog<void>(
  context: context,
  builder: (_) => GameScope(
    controller: game,
    child: _RenameDialog(store: store),
  ),
);

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.store});

  final StoreView store;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name;
  late bool _company;
  late final CompanyId? _owner;

  @override
  void initState() {
    super.initState();
    final game = GameScope.read(context);
    final name = game.storeName(widget.store.id);
    _name = TextEditingController(text: name);
    _owner = game.company?.id;
    _company = _owner != null && game.companyName(_owner) == name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final name = _name.text.trim();
    final owner = _owner;
    return AlertDialog(
      title: Text(tr('store.renameStore')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('common.storeName')),
            onChanged: (_) => setState(() {}),
          ),
          if (owner != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _company,
              title: Text(tr('store.renameCompany')),
              subtitle: Text(
                tr('store.companyNow', {'company': game.companyName(owner)}),
              ),
              onChanged: (on) => setState(() => _company = on ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: name.isEmpty
              ? null
              : () {
                  game.submit(
                    RenameStore(
                      game.player,
                      store: widget.store.id,
                      name: name,
                    ),
                  );
                  if (_company && owner != null) {
                    game.submit(
                      RenameCompany(game.player, company: owner, name: name),
                    );
                  }
                  Navigator.pop(context);
                },
          child: Text(tr('store.rename')),
        ),
      ],
    );
  }
}

/// What the store spends on advertising each day, set with a slider.
class _Marketing extends StatelessWidget {
  const _Marketing({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final demand = game.content.demand;
    final share = game.marketingOf(store);
    final pending = share != store.marketingShare;
    // Half a percent a step, up to the most a store may spend.
    final steps = maxMarketingShare.raw ~/ 50;
    final sales = game.recentDailySales(store);
    final cost = sales.times(share);
    final half = demand.halfGoodwill.times(game.view.macro.priceIndex);
    final goodwill = store.goodwill.cents;
    final pull = goodwill <= 0 ? 0.0 : goodwill / (goodwill + half.cents);
    final managed = game.delegates(store, ManagerDuty.pricing);
    // The pull a share builds up to: the goodwill at which what wears off
    // each day equals what it spends.
    double settles(Fx level) {
      final built =
          sales.times(level).cents / (demand.goodwillDecay.raw / Fx.scale);
      return built <= 0 ? 0 : built / (built + half.cents);
    }

    return Section(
      title: tr('store.marketing'),
      icon: Icons.campaign_outlined,
      trailing: pending
          ? Icon(
              Icons.schedule,
              size: 18,
              color: Theme.of(context).colorScheme.secondary,
            )
          : null,
      children: [
        Line(
          share == Fx.zero
              ? tr('store.noMarketing')
              : tr('store.ofSales', {'share': percent(share)}),
          share == Fx.zero
              ? ''
              : tr('store.aboutPerDay', {'amount': money(cost)}),
          strong: true,
          hint: tr('store.salesBeen', {'amount': money(sales, cents: false)}),
        ),
        Slider(
          value: (share.raw ~/ 50).clamp(0, steps).toDouble(),
          max: steps.toDouble(),
          divisions: steps,
          label: percent(Fx.raw(share.raw)),
          onChanged: store.status == StoreStatus.closed || managed
              ? null
              : (next) => game.submit(
                  SetMarketing(
                    game.player,
                    store: store.id,
                    share: Fx.raw(next.round() * 50),
                  ),
                ),
        ),
        Row(
          children: [
            Expanded(child: LevelBar(pull)),
            const SizedBox(width: 8),
            Text(
              tr('store.ofTheMost', {'share': percentOf((pull * 100).round())}),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        if (managed) Hint(tr('store.managerSetsMarketing')),
        Hint(tr('store.marketingHint')),
        const SizedBox(height: 8),
        Text(
          tr('store.ladderTitle'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final level in _ladder)
          Line(
            tr('store.ofSales', {'share': percent(level, decimals: 0)}),
            percentOf((settles(level) * 100).round()),
            strong: level == share,
            hint: tr('store.aboutPerMonth', {
              'amount': money(sales.times(level).timesInt(30), cents: false),
            }),
          ),
        Hint(tr('store.ladderHint')),
      ],
    );
  }
}

/// Shares of sales the marketing page prices out.
final _ladder = [
  for (final share in ['0.01', '0.03', '0.05', '0.08', '0.12']) Fx.parse(share),
];

/// What shoppers think of the store, and how it builds.
class _Reputation extends StatelessWidget {
  const _Reputation({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final demand = context.game.content.demand;
    return Section(
      title: tr('store.reputation'),
      icon: Icons.star_outline,
      children: [
        Line(
          tr('store.reputation'),
          percent(store.reputation, decimals: 0),
          strong: true,
        ),
        LevelBar(store.reputation.raw / Fx.scale),
        Hint(
          tr('store.reputationHint', {
            'months': (demand.reputationDays / 30).round(),
            'opening': percent(demand.openingReputation, decimals: 0),
            'established': percent(demand.establishedReputation, decimals: 0),
          }),
        ),
        Hint(tr('store.reputationAdvice')),
      ],
    );
  }
}

/// Turning the store into the bigger format of its kind: a convenience
/// store into a supermarket.
class _Conversion extends StatelessWidget {
  const _Conversion({required this.store});

  final StoreView store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final current = content.formats[store.format.index];
    final channel = content.formatChannels[current.id.index];
    final target = content.formats
        .where(
          (format) =>
              content.formatChannels[format.id.index] == channel &&
              format.fitOut > current.fitOut,
        )
        .firstOrNull;
    if (target == null) return const SizedBox.shrink();
    final site = content.sites[store.site.index];
    final level = game.view.macro.priceIndex;
    final cost = conversionCost(
      content,
      site,
      store.format,
      store.area,
      target,
      level,
    );
    final company = game.company;
    final free = company == null
        ? Money.zero
        : company.cash - company.committed;
    final pending = game.pending.any(
      (command) => command is ConvertStore && command.store == store.id,
    );
    final area = target.minArea > store.area ? target.minArea : store.area;
    final reason = target.minArea > site.maxArea
        ? tr('store.siteTooSmall', {
            'format': aFormat(target),
            'area': target.minArea,
            'most': site.maxArea,
          })
        : store.works != null
        ? tr('store.worksAreUnderWay')
        : store.status != StoreStatus.open
        ? tr('store.onlyOpen')
        : free < cost
        ? tr('store.needMoreCash', {'amount': money(cost - free, cents: false)})
        : null;
    return Section(
      title: tr('store.become', {'format': aFormat(target)}),
      icon: formatIcon(target),
      children: [
        Line(
          tr('store.worksPaidNow'),
          money(cost, cents: false),
          hint: tr('store.conversionDetails', {
            'area': area,
            'slots': target.slotBonus,
            'storage': target.storageBonus,
            'days': site.buildDays,
          }),
        ),
        Hint(reason ?? tr('store.conversionPitch')),
        if (pending)
          Hint(tr('store.worksStartTomorrow'))
        else
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: Icon(formatIcon(target), size: 18),
              onPressed: reason != null
                  ? null
                  : () => game.submit(
                      ConvertStore(
                        game.player,
                        store: store.id,
                        format: target.id,
                      ),
                    ),
              label: Text(tr('store.convertTo', {'format': aFormat(target)})),
            ),
          ),
      ],
    );
  }
}
