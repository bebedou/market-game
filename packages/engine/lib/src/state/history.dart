import '../core/calendar.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';

/// Days of daily sales counts each store keeps.
const int salesHistoryDays = 28;

/// What a daily sales count measures. Append only.
enum SalesCount {
  /// Units sold.
  sold,

  /// Units wanted while the product was out of stock.
  outOfStock,

  /// Units wanted of a product the store doesn't list.
  notListed,

  /// Units refused for their price.
  overpriced,
}

/// One store's daily [SalesCount]s per product for the last
/// [salesHistoryDays] days, in a ring indexed by day. The close phase records
/// into it; the owner reads it through observations.
final class SalesHistory {
  SalesHistory(this._productCount)
    : _counts = List.filled(
        SalesCount.values.length * _productCount * salesHistoryDays,
        0,
      ),
      _traffic = List.filled(slotCount * salesHistoryDays, 0);

  SalesHistory.read(StateReader reader)
    : _productCount = reader.readInt(),
      _counts = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
      ],
      _traffic = [
        for (var i = 0, n = reader.readInt(); i < n; i++) reader.readInt(),
      ];

  /// Slots of the day.
  static const slotCount = 4;

  int _productCount;

  /// Products counted, those of the scenario when the store opened or the
  /// game was last loaded.
  int get productCount => _productCount;

  /// Indexed by [SalesCount], then product, then day modulo the window.
  List<int> _counts;

  /// Visits indexed by slot, then day modulo the window.
  final List<int> _traffic;

  /// Visits in [slot] on [day], one of the last [salesHistoryDays] recorded.
  int visitsAt(int slot, Day day) =>
      _traffic[slot * salesHistoryDays + day.number % salesHistoryDays];

  /// Records [day]'s visits per slot.
  void recordTraffic(Day day, List<int> visits) {
    for (var slot = 0; slot < slotCount; slot++) {
      _traffic[slot * salesHistoryDays + day.number % salesHistoryDays] =
          visits[slot];
    }
  }

  int _index(SalesCount count, int product, Day day) =>
      (count.index * productCount + product) * salesHistoryDays +
      day.number % salesHistoryDays;

  /// The [count] of [product] on [day], which must be one of the last
  /// [salesHistoryDays] days recorded.
  int at(SalesCount count, ProductId product, Day day) =>
      _counts[_index(count, product.index, day)];

  /// Records [day]'s counts, indexed by [SalesCount] then [ProductId],
  /// replacing those of the day [salesHistoryDays] earlier.
  void record(Day day, List<List<int>> counts) {
    for (final count in SalesCount.values) {
      for (var product = 0; product < productCount; product++) {
        _counts[_index(count, product, day)] = counts[count.index][product];
      }
    }
  }

  /// Counts [products] from now on, the new ones from zero: the scenario
  /// gained products since the game was saved.
  void grow(int products) {
    if (products <= _productCount) return;
    final counts = List.filled(
      SalesCount.values.length * products * salesHistoryDays,
      0,
    );
    for (var count = 0; count < SalesCount.values.length; count++) {
      for (var product = 0; product < _productCount; product++) {
        for (var day = 0; day < salesHistoryDays; day++) {
          counts[(count * products + product) * salesHistoryDays + day] =
              _counts[(count * _productCount + product) * salesHistoryDays +
                  day];
        }
      }
    }
    _counts = counts;
    _productCount = products;
  }

  void write(StateWriter writer) {
    writer
      ..writeInt(_productCount)
      ..writeInt(_counts.length);
    _counts.forEach(writer.writeInt);
    writer.writeInt(_traffic.length);
    _traffic.forEach(writer.writeInt);
  }
}
