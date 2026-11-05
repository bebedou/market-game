import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';

/// A census: the households counted in a market on a day.
typedef Census = ({Day day, int households});

/// How a market's population is moving: growth not yet whole households,
/// and the censuses taken so far.
final class MarketState {
  MarketState({
    required this.market,
    required this.pending,
    required this.censuses,
  });

  /// A market of [households] at its first census, on [day].
  MarketState.initial(this.market, Day day, int households)
    : pending = [],
      censuses = [(day: day, households: households)];

  MarketState.read(this.market, StateReader reader)
    : pending = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          Fx.raw(reader.readInt()),
      ],
      censuses = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          (day: Day(reader.readInt()), households: reader.readInt()),
      ];

  /// The most censuses kept.
  static const censusesKept = 40;

  final MarketId market;

  /// Growth owed to each segment, as a fraction of a household either way,
  /// indexed by [SegmentId]. Shorter than the segments in a save that
  /// predates population change; missing entries are zero.
  final List<Fx> pending;

  /// Oldest first; the first is the market's population at the start.
  final List<Census> censuses;

  void write(StateWriter writer) {
    writer.writeInt(pending.length);
    for (final value in pending) {
      writer.writeInt(value.raw);
    }
    writer.writeInt(censuses.length);
    for (final (:day, :households) in censuses) {
      writer
        ..writeInt(day.number)
        ..writeInt(households);
    }
  }
}
