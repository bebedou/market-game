import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';

/// A market study bought by [buyer]: estimates of what is otherwise hidden,
/// taken from the true state on [asOf], each off by up to the tier's error.
final class ResearchReport {
  ResearchReport({
    required this.number,
    required this.buyer,
    required this.market,
    required this.tier,
    required this.asOf,
    required this.segments,
    required this.unitShares,
  });

  ResearchReport.read(StateReader reader)
    : number = reader.readInt(),
      buyer = PersonId(reader.readInt()),
      market = MarketId(reader.readInt()),
      tier = ResearchTierId(reader.readInt()),
      asOf = Day(reader.readInt()),
      segments = List.unmodifiable([
        for (var i = 0, n = reader.readInt(); i < n; i++)
          SegmentEstimate.read(reader),
      ]),
      unitShares = List.unmodifiable([
        for (var i = 0, n = reader.readInt(); i < n; i++)
          (store: StoreId(reader.readInt()), share: Fx.raw(reader.readInt())),
      ]);

  /// Report numbers count up from 1 across the whole world.
  final int number;
  final PersonId buyer;
  final MarketId market;
  final ResearchTierId tier;
  final Day asOf;

  /// Indexed by [SegmentId].
  final List<SegmentEstimate> segments;

  /// Each trading store's share of the units sold in the market over the
  /// last 28 days.
  final List<({StoreId store, Fx share})> unitShares;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(buyer.index)
      ..writeInt(market.index)
      ..writeInt(tier.index)
      ..writeInt(asOf.number)
      ..writeInt(segments.length);
    for (final segment in segments) {
      segment.write(writer);
    }
    writer.writeInt(unitShares.length);
    for (final (:store, :share) in unitShares) {
      writer
        ..writeInt(store.index)
        ..writeInt(share.raw);
    }
  }
}

/// What a study found about one segment of a market.
final class SegmentEstimate {
  SegmentEstimate({
    required this.households,
    required this.dailyUnits,
    required this.premiumShare,
    required this.priceSensitivity,
    required this.priceTolerance,
    required this.slotShares,
  });

  SegmentEstimate.read(StateReader reader)
    : households = reader.readInt(),
      dailyUnits = _readFxList(reader),
      premiumShare = _readFxList(reader),
      priceSensitivity = Fx.raw(reader.readInt()),
      priceTolerance = Fx.raw(reader.readInt()),
      slotShares = _readFxList(reader);

  final int households;

  /// Units per household per day, indexed by [CategoryId].
  final List<Fx> dailyUnits;

  /// Indexed by [CategoryId].
  final List<Fx> premiumShare;
  final Fx priceSensitivity;
  final Fx priceTolerance;

  /// Indexed by [DaySlot].
  final List<Fx> slotShares;

  void write(StateWriter writer) {
    writer.writeInt(households);
    _writeFxList(writer, dailyUnits);
    _writeFxList(writer, premiumShare);
    writer
      ..writeInt(priceSensitivity.raw)
      ..writeInt(priceTolerance.raw);
    _writeFxList(writer, slotShares);
  }
}

List<Fx> _readFxList(StateReader reader) => List.unmodifiable([
  for (var i = 0, n = reader.readInt(); i < n; i++) Fx.raw(reader.readInt()),
]);

void _writeFxList(StateWriter writer, List<Fx> values) {
  writer.writeInt(values.length);
  for (final value in values) {
    writer.writeInt(value.raw);
  }
}
