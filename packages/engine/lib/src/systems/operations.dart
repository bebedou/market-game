import '../core/fx.dart';
import '../state/brands.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The operations phase: stores whose fit-out is finished open their doors,
/// finished enlargements come into use, and each slot's service level is set
/// from today's staff and yesterday's shoppers.
final class OperationsSystem implements TickSystem {
  const OperationsSystem();

  @override
  void run(WorldState world, TickContext context) {
    final expansion = context.content.expansion;
    for (final store in world.stores) {
      final perStaff =
          context.content.formats[store.format.index].visitsPerStaff;
      if (store.status == StoreStatus.building &&
          store.opensOn <= context.day) {
        store.status = StoreStatus.open;
      }
      if (store.works case (
        :final area,
        :final done,
        :final format,
      ) when done <= context.day) {
        final steps = (area - store.area) ~/ expansion.stepArea;
        store
          ..area = area
          ..shelfSlots += steps * expansion.shelfSlots
          ..storageUnits += steps * expansion.storageUnits
          ..works = null
          ..enlargedOn = context.day;
        if (format != null) {
          final next = context.content.formats[format.index];
          store
            ..format = format
            ..shelfSlots += next.slotBonus
            ..storageUnits += next.storageBonus;
          // A brand is for one type of business only.
          if (store.brand case final id?
              when world.brands[id.index].format != format) {
            takeOverName(
              world,
              context.content,
              store,
              world.companies[store.company.index].owner,
            );
          }
        }
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
