import 'package:engine/engine.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/state/store.dart';
import 'package:test/test.dart';

void main() {
  final day = Day.parse('2026-01-01');

  Stock sample() => Stock()
    ..receive(10, Money(50), day + 5)
    ..receive(20, Money(60), day + 3)
    ..receive(5, Money(70), null);

  test('takes the oldest lots first', () {
    final stock = sample();
    expect(stock.take(15), (units: 15, cost: Money(10 * 50 + 5 * 60)));
    expect(stock.units, 20);
    expect(stock.lots.first.quantity, 15);
    expect(stock.take(100), (units: 20, cost: Money(15 * 60 + 5 * 70)));
    expect(stock.lots, isEmpty);
  });

  test('expires only lots whose expiry has come', () {
    final stock = sample();
    expect(stock.expire(day + 2), (units: 0, cost: Money.zero));
    expect(stock.expire(day + 3), (units: 20, cost: Money(20 * 60)));
    expect(stock.lots.map((lot) => lot.quantity), [10, 5]);
    expect(stock.expire(day + 1000), (units: 10, cost: Money(10 * 50)));
    expect(stock.units, 5);
  });

  test('values stock at cost and clears it', () {
    final stock = sample();
    expect(stock.value, Money(10 * 50 + 20 * 60 + 5 * 70));
    expect(stock.clear(), (units: 35, cost: Money(2050)));
    expect(stock.units, 0);
  });

  test('round-trips through the state encoding', () {
    final writer = StateWriter();
    sample().write(writer);
    final copy = Stock.read(StateReader(writer.toBytes()));
    expect(copy.lots.map((lot) => (lot.quantity, lot.unitCost, lot.expiry)), [
      (10, Money(50), day + 5),
      (20, Money(60), day + 3),
      (5, Money(70), null),
    ]);
  });
}
