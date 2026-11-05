import '../accounting/ledger.dart';
import '../state/store.dart';
import '../state/world_state.dart';

/// Closes [store] for good: undelivered orders are cancelled, unsold stock
/// is written off, and its site is free for anyone.
void closeStore(WorldState world, Ledger ledger, Store store) {
  world.orders.removeWhere((order) => order.store == store.id);
  final company = world.companies[store.company.index];
  for (var product = 0; product < store.prices.length; product++) {
    store.prices[product] = null;
    final cleared = store.stock[product].clear();
    if (cleared.units == 0) continue;
    ledger.post(
      company,
      debit: AccountKind.writeOffs,
      credit: AccountKind.inventory,
      amount: cleared.cost,
      reason: EntryReason.closure,
      store: store.id,
      units: cleared.units,
    );
  }
  store
    ..status = StoreStatus.closed
    ..manager = null
    ..works = null;
}
