import '../accounting/ledger.dart';
import '../core/ids.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// Writes off stock lots that expire today.
final class SpoilageSystem implements TickSystem {
  const SpoilageSystem();

  @override
  void run(WorldState world, TickContext context) {
    for (final store in world.stores) {
      final company = world.companies[store.company.index];
      for (final (product, stock) in store.stock.indexed) {
        final expired = stock.expire(context.day);
        if (expired.units == 0) continue;
        context.ledger.post(
          company,
          debit: AccountKind.writeOffs,
          credit: AccountKind.inventory,
          amount: expired.cost,
          reason: EntryReason.spoilage,
          store: store.id,
          product: ProductId(product),
          units: expired.units,
        );
      }
    }
  }
}
