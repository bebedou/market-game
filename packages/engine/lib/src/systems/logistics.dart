import '../accounting/ledger.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/entities.dart';
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'tick_system.dart';

/// Delivers orders that arrive today. Each line becomes a stock lot, as far
/// as storage allows; the store is invoiced for what it accepted, by the
/// wholesaler, or on a factory's order by the factory's company for what it
/// made and by the wholesaler for the rest.
final class LogisticsSystem implements TickSystem {
  const LogisticsSystem();

  @override
  void run(WorldState world, TickContext context) {
    final arriving = [
      for (final order in world.orders)
        if (order.arrival <= context.day) order,
    ];
    world.orders.removeWhere((order) => order.arrival <= context.day);
    // A shop takes a factory's order and others arriving the same day in
    // the order of their products, as it would one delivery: which goods a
    // full stockroom turns away doesn't hang on where they were ordered.
    final merged = <StoreId>{
      for (final order in arriving)
        if (order.factory != null &&
            arriving.where((other) => other.store == order.store).length > 1)
          order.store,
    };
    final done = <StoreId>{};
    for (final order in arriving) {
      if (!merged.contains(order.store)) {
        final invoice = _Invoice();
        for (final line in order.lines) {
          _take(world, context, order, line, invoice);
        }
        _bill(world, context, order, invoice);
        continue;
      }
      if (!done.add(order.store)) continue;
      final orders = [
        for (final other in arriving)
          if (other.store == order.store) other,
      ];
      final lines =
          [
            for (final (i, other) in orders.indexed)
              for (final (j, line) in other.lines.indexed) (i, j, line),
          ]..sort((a, b) {
            final byProduct = a.$3.product.index - b.$3.product.index;
            if (byProduct != 0) return byProduct;
            return a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;
          });
      final invoices = [for (final _ in orders) _Invoice()];
      for (final (i, _, line) in lines) {
        _take(world, context, orders[i], line, invoices[i]);
      }
      for (final (i, other) in orders.indexed) {
        _bill(world, context, other, invoices[i]);
      }
    }
  }

  /// Delivers [line] of [order], as far as the store has room, adding what
  /// it is billed to [invoice].
  void _take(
    WorldState world,
    TickContext context,
    PurchaseOrder order,
    OrderLine line,
    _Invoice invoice,
  ) {
    final store = world.stores[order.store.index];
    final company = world.companies[store.company.index];
    final factory = switch (order.factory) {
      final id? => world.factories[id.index],
      null => null,
    };
    final maker = factory == null
        ? null
        : world.companies[factory.company.index];
    // A factory closed or wound up since delivers nothing: the wholesaler
    // whose price it charged does.
    final making =
        factory != null &&
        factory.status == FactoryStatus.running &&
        maker!.isActive;
    final product = context.content.products[line.product.index];
    void refuse(int units, RefusalReason reason) => context.events.add(
      DeliveryRefused(
        order: order.number,
        store: store.id,
        product: product.id,
        units: units,
        reason: reason,
      ),
    );
    if (store.prices[product.id.index] == null) {
      refuse(line.quantity, RefusalReason.notListed);
      return;
    }
    final space = store.storageUnits - store.unitsOnHand;
    final accepted = line.quantity < space ? line.quantity : space;
    if (accepted < line.quantity) {
      refuse(line.quantity - accepted, RefusalReason.storageFull);
    }
    if (accepted == 0) return;
    final shelfLife = product.shelfLifeDays;
    store.stock[product.id.index].receive(
      accepted,
      line.unitPrice,
      shelfLife == null ? null : context.day + shelfLife,
    );
    final cost = line.unitPrice.timesInt(accepted);
    context.ledger.post(
      company,
      debit: AccountKind.inventory,
      credit: AccountKind.payables,
      amount: cost,
      reason: EntryReason.delivery,
      store: store.id,
      product: product.id,
      units: accepted,
    );
    if (factory == null) {
      invoice.add(order.supplier, cost);
      return;
    }
    final fromFactory = making
        ? (line.made < accepted ? line.made : accepted)
        : 0;
    final bought = accepted - fromFactory;
    if (bought > 0) {
      invoice.add(line.from ?? order.supplier, line.unitPrice.timesInt(bought));
      context.boughtIn.add((
        factory: factory.id,
        product: product.id,
        units: bought,
      ));
    }
    if (fromFactory > 0) {
      final value = line.unitPrice.timesInt(fromFactory);
      invoice.made += value;
      _make(
        world,
        context,
        factory,
        maker!,
        store.market,
        line,
        value,
        own: maker.owner == company.owner,
        units: fromFactory,
      );
    }
  }

  /// Bills [order]'s store for what [invoice] holds: each wholesaler on its
  /// terms, and the factory's company on factories' terms.
  void _bill(
    WorldState world,
    TickContext context,
    PurchaseOrder order,
    _Invoice invoice,
  ) {
    final company =
        world.companies[world.stores[order.store.index].company.index];
    for (final MapEntry(key: id, value: amount) in invoice.wholesale.entries) {
      if (amount <= Money.zero) continue;
      final supplier = context.content.suppliers[id.index];
      company.payables.add(
        Payable(
          creditor: world.suppliers[supplier.id.index].partyRef,
          creditorAccount: AccountKind.revenue,
          reason: EntryReason.supplierPayment,
          amount: amount,
          due: context.day + supplier.paymentTermsDays,
          order: order.number,
        ),
      );
    }
    if (invoice.made > Money.zero) {
      final factory = world.factories[order.factory!.index];
      company.payables.add(
        Payable(
          creditor: world.companies[factory.company.index].partyRef,
          creditorAccount: AccountKind.receivables,
          reason: EntryReason.supplierPayment,
          amount: invoice.made,
          due: context.day + context.content.factories!.paymentTermsDays,
          order: order.number,
        ),
      );
    }
  }

  /// Books [factory]'s side of [units] of [line] delivered, worth [value]:
  /// what it is owed, and the materials and any freight they took, billed
  /// by everyone beyond the districts played in full.
  void _make(
    WorldState world,
    TickContext context,
    Factory factory,
    Company maker,
    MarketId market,
    OrderLine line,
    Money value, {
    required bool own,
    required int units,
  }) {
    final content = context.content;
    final factories = content.factories!;
    final kind = factories.kinds[factory.kind.index];
    final product = content.products[line.product.index];
    final ledger = context.ledger;
    ledger.post(
      maker,
      debit: AccountKind.receivables,
      credit: own ? AccountKind.ownGoods : AccountKind.revenue,
      amount: value,
      reason: EntryReason.factorySale,
      product: product.id,
      units: units,
      factory: factory.id,
    );
    void owe(AccountKind expense, EntryReason reason, Money amount) {
      if (amount <= Money.zero) return;
      ledger.post(
        maker,
        debit: expense,
        credit: AccountKind.payables,
        amount: amount,
        reason: reason,
        product: product.id,
        units: units,
        factory: factory.id,
      );
      maker.payables.add(
        Payable(
          creditor: world.elsewhere.partyRef,
          creditorAccount: AccountKind.revenue,
          reason: reason,
          amount: amount,
          due: context.day,
          factory: factory.id,
        ),
      );
    }

    owe(
      AccountKind.costOfGoods,
      EntryReason.materials,
      materialsCost(
        kind,
        product,
        world.macroOf(factory.country).priceIndex,
      ).timesInt(units),
    );
    if (content.countryOf(market) != factory.country) {
      owe(
        AccountKind.overheads,
        EntryReason.freight,
        value.times(factories.freight),
      );
    }
  }
}

/// What one order's delivery is billed: by each wholesaler, and by the
/// factory for what it made.
final class _Invoice {
  final wholesale = <SupplierId, Money>{};
  var made = Money.zero;

  void add(SupplierId supplier, Money amount) =>
      wholesale[supplier] = (wholesale[supplier] ?? Money.zero) + amount;
}
