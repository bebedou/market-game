import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/safe_int.dart';
import '../reports/attribution.dart';
import '../state/history.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The close phase: records each store's sales, misses and visits per slot
/// for the day into its sales history, and moves the reputation of each
/// open store that had shoppers toward how well it served them (see
/// [DemandTuning.reputationWeight]): the units it sold over those wanted of
/// what it lists, sold or missed for want of stock, times its service level
/// over the day's visits. A small store isn't blamed for its range.
final class CloseSystem implements TickSystem {
  const CloseSystem();

  @override
  void run(WorldState world, TickContext context) {
    final products = context.content.products.length;
    final counts = [
      for (final _ in world.stores)
        [for (final _ in SalesCount.values) List.filled(products, 0)],
    ];
    for (final entry in context.ledger.entries) {
      // A chain's month in a district run by formula is no store's.
      final (store, product) = (entry.store, entry.product);
      if (entry.reason != EntryReason.sale ||
          entry.party.type != PartyType.company ||
          store == null ||
          product == null) {
        continue;
      }
      counts[store.index][SalesCount.sold.index][product.index] += entry.units;
    }
    for (final MapEntry(key: miss, value: units)
        in context.attribution.misses.entries) {
      final count = switch (miss.reason) {
        MissReason.outOfStock => SalesCount.outOfStock,
        MissReason.notListed => SalesCount.notListed,
        MissReason.overpriced => SalesCount.overpriced,
      };
      counts[miss.store.index][count.index][miss.product.index] += units;
    }
    final tuning = context.content.demand;
    for (final store in world.stores) {
      final count = counts[store.id.index];
      store.history
        ..record(context.day, count)
        ..recordTraffic(context.day, store.traffic);
      if (tuning.reputationWeight == Fx.zero ||
          store.status != StoreStatus.open) {
        continue;
      }
      var sold = 0;
      var wanted = 0;
      for (var product = 0; product < products; product++) {
        final units = count[SalesCount.sold.index][product];
        sold += units;
        wanted += units + count[SalesCount.outOfStock.index][product];
      }
      var visits = 0;
      var served = 0;
      for (var slot = 0; slot < store.traffic.length; slot++) {
        visits += store.traffic[slot];
        served += store.service[slot].raw * store.traffic[slot];
      }
      if (wanted == 0 || visits == 0) continue;
      final quality =
          Fx.raw(mulDivRound(sold, Fx.scale, wanted)) *
          Fx.raw(served ~/ visits);
      store.reputation += Fx.raw(
        (quality - store.reputation).raw ~/ tuning.reputationDays,
      );
    }
  }
}
