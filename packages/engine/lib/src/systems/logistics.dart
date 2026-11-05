import '../accounting/ledger.dart';
import '../core/money.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'tick_system.dart';

/// Delivers orders that arrive today. Each line becomes a stock lot, as far
/// as storage allows; the store is invoiced for what it accepted.
final class LogisticsSystem implements TickSystem {
  const LogisticsSystem();

  @override
  void run(WorldState world, TickContext context) {
    final arriving = [
      for (final order in world.orders)
        if (order.arrival <= context.day) order,
    ];
    world.orders.removeWhere((order) => order.arrival <= context.day);
    for (final order in arriving) {
      _deliver(world, context, order);
    }
  }

  void _deliver(WorldState world, TickContext context, PurchaseOrder order) {
    final store = world.stores[order.store.index];
    final company = world.companies[store.company.index];
    var invoice = Money.zero;
    for (final line in order.lines) {
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
        continue;
      }
      final space = store.storageUnits - store.unitsOnHand;
      final accepted = line.quantity < space ? line.quantity : space;
      if (accepted < line.quantity) {
        refuse(line.quantity - accepted, RefusalReason.storageFull);
      }
      if (accepted == 0) continue;
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
      invoice += cost;
    }
    if (invoice > Money.zero) {
      final supplier = context.content.suppliers[order.supplier.index];
      company.payables.add(
        Payable(
          creditor: world.suppliers[supplier.id.index].partyRef,
          creditorAccount: AccountKind.revenue,
          reason: EntryReason.supplierPayment,
          amount: invoice,
          due: context.day + supplier.paymentTermsDays,
          order: order.number,
        ),
      );
    }
  }
}
