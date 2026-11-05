import '../core/fx.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../persistence/state_io.dart';

/// Households of one segment in one market that shop together: [weight]
/// identical households, each with the needs below. Population change adds
/// and removes households, so a cohort may stand for none for a while.
final class HouseholdCohort {
  HouseholdCohort({
    required this.id,
    required this.market,
    required this.segment,
    required this.preferredSlot,
    required this.needs,
    required this.loyalty,
    required this.perceivedPrices,
    required this.proximity,
    required this.incomeRank,
    this.weight = 1,
  });

  HouseholdCohort.read(this.id, StateReader reader, {required this.incomeRank})
    : market = MarketId(reader.readInt()),
      segment = SegmentId(reader.readInt()),
      preferredSlot = reader.readInt(),
      needs = _readFxList(reader),
      loyalty = _readFxList(reader),
      perceivedPrices = _readFxList(reader),
      proximity = _readFxList(reader),
      weight = reader.version >= 7 ? reader.readInt() : 1;

  final CohortId id;
  final MarketId market;
  final SegmentId segment;

  /// The slot of the day the cohort likes to shop in, a [DaySlot] index.
  final int preferredSlot;

  /// Unmet need per category in units, indexed by [CategoryId].
  final List<Fx> needs;

  /// Habit strength toward each store, from 0 to 1, indexed by [StoreId].
  final List<Fx> loyalty;

  /// What the cohort believes each store charges, as the store's basket
  /// price over the same basket at reference prices, indexed by [StoreId].
  /// Exact after a visit; drifts toward the truth by word of mouth.
  final List<Fx> perceivedPrices;

  /// How close the cohort lives to each site, from 0 (far) to 1 (next door),
  /// indexed by [SiteId]. It adds to the site's location in the convenience
  /// the cohort sees in a store there.
  final List<Fx> proximity;

  /// How many households the cohort stands for.
  int weight;

  /// Where the cohort's households stand among their segment's incomes,
  /// from 0 (poorest) to 1 (richest). It follows from the seed and the
  /// cohort's ID, so it isn't saved.
  final Fx incomeRank;

  /// The rank of cohort [id] in a world of [seed].
  static Fx rankFor(int seed, CohortId id) =>
      Rng.keyed(seed, RngStream.income, 0, id.index).nextFx();

  void write(StateWriter writer) {
    writer
      ..writeInt(market.index)
      ..writeInt(segment.index)
      ..writeInt(preferredSlot);
    for (final list in [needs, loyalty, perceivedPrices, proximity]) {
      writer.writeInt(list.length);
      for (final value in list) {
        writer.writeInt(value.raw);
      }
    }
    writer.writeInt(weight);
  }
}

List<Fx> _readFxList(StateReader reader) => [
  for (var i = 0, n = reader.readInt(); i < n; i++) Fx.raw(reader.readInt()),
];
