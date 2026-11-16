import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// Lots older than this many days are old: what the shop offers a jobber.
const oldDays = 180;

/// The age bands the rails show, in days: up to each bound, the last open.
const _bands = [60, 120, oldDays];

/// Whether [format] sells goods that go out of fashion.
bool sellsFashion(ContentDb content, FormatDef format) =>
    content.categories.any(
      (category) => format.sells[category.id.index] && category.fashion != null,
    );

/// The products of [store]'s that go out of fashion, as the content lists
/// them.
Iterable<ProductDef> _fashionGoods(ContentDb content, StoreView store) {
  final format = content.formats[store.format.index];
  return content.products.where(
    (product) =>
        format.sells[product.category.index] &&
        content.categories[product.category.index].fashion != null,
  );
}

/// [store]'s lots of [product], oldest first.
List<LotAge> _lotsOf(StoreView store, ProductId product) =>
    product.index < store.lots.length ? store.lots[product.index] : const [];

/// A shop's rails by age, what is on order for it, and what to do about
/// both: a clothing shop's stock at a glance.
class Rails extends StatelessWidget {
  const Rails({super.key, required this.store, required this.onOrder});

  final StoreView store;

  /// Opens the shop's supplies, to order a collection.
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final goods = _fashionGoods(content, store).toList();
    final bands = List.filled(_bands.length + 1, 0);
    var units = 0;
    var worth = 0;
    for (final product in goods) {
      for (final lot in _lotsOf(store, product.id)) {
        var band = 0;
        while (band < _bands.length && lot.days > _bands[band]) {
          band++;
        }
        bands[band] += lot.units;
      }
      final here = _lotsOf(
        store,
        product.id,
      ).fold(0, (sum, lot) => sum + lot.units);
      units += here;
      worth += store.fashionOf(product.id).raw * here;
    }
    final (:oldUnits, :cost, :paid) = _old(content, store);
    final orders = [
      for (final order in game.company?.orders ?? const <OrderView>[])
        if (order.store == store.id) order,
    ];
    final canAct = store.status != StoreStatus.closed;
    return Section(
      title: tr('rails.title'),
      icon: Icons.checkroom_outlined,
      children: [
        for (final (i, count) in bands.indexed)
          Line(tr('rails.band$i'), tr('rails.units', {'count': count})),
        if (units > 0)
          Hint(
            tr('rails.worth', {
              'worth': percent(Fx.raw(worth ~/ units), decimals: 0),
            }),
          )
        else
          Hint(tr('rails.empty')),
        IndexRow(
          icon: Icons.view_list_outlined,
          title: tr('rails.eachLine'),
          subtitle: tr('rails.eachLineHint'),
          onTap: () => context.openPage(
            tr('rails.eachLine'),
            (_) => [LinesPage(store: store.id)],
          ),
        ),
        if (oldUnits > 0 && canAct)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: OutlinedButton(
              onPressed: () => _clear(context, oldUnits, cost, paid),
              child: Text(tr('rails.clear')),
            ),
          ),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Text(
            tr('rails.onOrder'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (orders.isEmpty) Hint(tr('rails.nothingOnOrder')),
        for (final order in orders)
          Line(
            tr('rails.order', {
              'units': order.lines.fold<int>(
                0,
                (sum, line) => sum + line.quantity,
              ),
              'supplier': order.factory == null
                  ? content.suppliers[order.supplier.index].name
                  : game.factory(order.factory!)?.name ?? '',
            }),
            shortDate(order.arrival),
          ),
        Hint(
          game.delegates(store, ManagerDuty.ordering)
              ? tr('rails.managerOrders')
              : tr('rails.youOrder'),
        ),
        if (canAct)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton.tonal(
              onPressed: onOrder,
              child: Text(tr('rails.orderCollection')),
            ),
          ),
      ],
    );
  }

  /// The old lots of [store]: their units, what they cost and what a jobber
  /// pays for them.
  static ({int oldUnits, Money cost, Money paid}) _old(
    ContentDb content,
    StoreView store,
  ) {
    var units = 0;
    var cost = Money.zero;
    var paid = Money.zero;
    for (final product in _fashionGoods(content, store)) {
      final fashion = content.categories[product.category.index].fashion!;
      for (final lot in _lotsOf(store, product.id)) {
        if (lot.days <= oldDays) continue;
        final value = lot.unitCost.timesInt(lot.units);
        units += lot.units;
        cost += value;
        paid += value.times(fashion.clearance);
      }
    }
    return (oldUnits: units, cost: cost, paid: paid);
  }

  Future<void> _clear(
    BuildContext context,
    int units,
    Money cost,
    Money paid,
  ) async {
    final game = context.game;
    final confirmed = await confirm(
      context,
      title: tr('rails.clearQuestion'),
      body: tr('rails.clearBody', {
        'units': units,
        'paid': money(paid, cents: false),
        'cost': money(cost, cents: false),
      }),
      action: tr('rails.clearConfirm'),
    );
    if (!confirmed) return;
    for (final product in _fashionGoods(game.content, store)) {
      if (_lotsOf(store, product.id).any((lot) => lot.days > oldDays)) {
        game.submit(
          ClearStock(
            game.player,
            store: store.id,
            product: product.id,
            days: oldDays + 1,
          ),
        );
      }
    }
  }
}

/// Each line of a shop that goes out of fashion: how old its stock is, what
/// it has kept of its appeal, and how far its price is marked down.
class LinesPage extends StatelessWidget {
  const LinesPage({super.key, required this.store});

  final StoreId store;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final view = game.myStores
        .map((entry) => entry.$2)
        .where((s) => s.id == store)
        .firstOrNull;
    if (view == null) return Hint(tr('rails.gone'));
    final country = content.countryOf(view.market);
    final level = content.markets[view.market.index].priceLevel;
    final rows = <Widget>[];
    for (final product in _fashionGoods(content, view)) {
      final price = view.prices[product.id.index];
      if (price == null) continue;
      final lots = _lotsOf(view, product.id);
      final units = lots.fold(0, (sum, lot) => sum + lot.units);
      final age = units == 0
          ? 0
          : lots.fold(0, (sum, lot) => sum + lot.days * lot.units) ~/ units;
      final worth = view.fashionOf(product.id);
      final normal = content.references[country.index][product.id.index].times(
        level,
      );
      final down = normal <= Money.zero
          ? Fx.zero
          : Fx.one - Fx.raw(price.cents * Fx.scale ~/ normal.cents);
      rows.add(
        _LineRow(
          name: product.name,
          price: money(price),
          worth: worth,
          details: [
            if (units == 0)
              tr('rails.lineEmpty')
            else ...[
              _age(age),
              tr('rails.lineWorth', {'worth': percent(worth, decimals: 0)}),
              tr('rails.units', {'count': units}),
            ],
            // A price under normal is a markdown on goods that have faded.
            if (worth < Fx.one && down.raw >= 200)
              tr('rails.markedDown', {'share': percent(down, decimals: 0)}),
          ].join(' · '),
        ),
      );
    }
    return Section(
      title: tr('rails.eachLine'),
      icon: Icons.checkroom_outlined,
      children: [
        Hint(tr('rails.linesHint')),
        if (rows.isEmpty) Hint(tr('rails.noLines')),
        ...rows,
      ],
    );
  }

  static String _age(int days) {
    final months = (days + 15) ~/ 30;
    return months == 0
        ? tr('rails.newLine')
        : tr('rails.monthsOld', {'months': months});
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.name,
    required this.price,
    required this.worth,
    required this.details,
  });

  final String name;
  final String price;
  final Fx worth;
  final String details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
              Text(price, style: figures(theme.textTheme.bodyLarge)),
            ],
          ),
          const SizedBox(height: 4),
          LevelBar(worth.raw / Fx.scale),
          const SizedBox(height: 2),
          Text(
            details,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
