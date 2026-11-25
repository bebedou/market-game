import '../core/fx.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The operations phase: stores whose fit-out is finished open their doors,
/// and each slot's service level is set from today's staff and yesterday's
/// shoppers.
final class OperationsSystem implements TickSystem {
  const OperationsSystem();

  @override
  void run(WorldState world, TickContext context) {
    for (final store in world.stores) {
      final perStaff = context.content.formats[store.format.index]
          .visitsPerStaffAt(store.area);
      if (store.status == StoreStatus.building &&
          store.opensOn <= context.day) {
        store.status = StoreStatus.open;
      }
      for (var slot = 0; slot < store.staff.length; slot++) {
        final capacity = store.staff[slot] * perStaff;
        final traffic = store.traffic[slot];
        store.service[slot] = traffic <= capacity
            ? Fx.one
            : Fx.raw(capacity * Fx.scale ~/ traffic);
        store.traffic[slot] = 0;
      }
    }
  }
}
