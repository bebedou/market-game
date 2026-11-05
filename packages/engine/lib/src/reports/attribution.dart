import 'dart:collection';

import '../content/content_db.dart';
import '../core/ids.dart';

/// Why a household shopped somewhere other than its habitual store: the
/// utility component that favored the chosen store most. Append only.
enum SwitchCause {
  /// The chosen store was believed cheaper.
  price,

  /// The chosen store has the better location.
  convenience,

  /// The habitual store has closed or has nothing on its shelves.
  closed,

  /// Nothing favored the chosen store: chance decided.
  variety,

  /// The chosen store is open when the household likes to shop; the
  /// habitual one isn't.
  hours,

  /// The chosen store had shorter queues.
  service,

  /// The chosen store is bigger.
  size,

  /// The chosen store advertises more.
  marketing,

  /// The chosen store has the better name.
  reputation,
}

/// A trip where a household left its habitual store [from] for [to].
typedef StoreSwitch = ({StoreId from, StoreId to, SwitchCause cause});

/// Why a store didn't sell a wanted item. Append only.
enum MissReason { notListed, outOfStock, overpriced }

/// Units of [product] that [store] didn't sell, why, and what the shoppers
/// did instead. [elsewhere] is the store they went to, for
/// [MissResponse.elsewhere] only.
typedef ItemMiss = ({
  StoreId store,
  ProductId product,
  MissReason reason,
  MissResponse response,
  StoreId? elsewhere,
});

/// Counts of why shoppers went where they did during one day, so reports can
/// explain gained and lost visits and sales.
final class Attribution {
  Attribution(int storeCount) : _visits = List.filled(storeCount, 0);

  final List<int> _visits;
  final _switches = <StoreSwitch, int>{};
  final _misses = <ItemMiss, int>{};

  /// Shopping trips per store, indexed by [StoreId]. Follow-up visits to buy
  /// a missing item elsewhere are counted in [misses] instead.
  List<int> get visits => UnmodifiableListView(_visits);

  /// Trips away from habitual stores.
  Map<StoreSwitch, int> get switches => UnmodifiableMapView(_switches);

  /// Units wanted but not sold, in order of first occurrence.
  Map<ItemMiss, int> get misses => UnmodifiableMapView(_misses);

  void addVisit(StoreId store, [int households = 1]) =>
      _visits[store.index] += households;

  void addSwitch(StoreSwitch key, [int households = 1]) =>
      _switches[key] = (_switches[key] ?? 0) + households;

  void addMiss(ItemMiss key, int units) {
    if (units > 0) _misses[key] = (_misses[key] ?? 0) + units;
  }
}
