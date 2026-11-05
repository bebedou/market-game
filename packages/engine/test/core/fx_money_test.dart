import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  group('Fx', () {
    test('parses decimal text without floating point', () {
      expect(Fx.parse('0.15').raw, 1500);
      expect(Fx.parse('-1.5').raw, -15000);
      expect(Fx.parse('3').raw, 30000);
      expect(Fx.parse('+0.0001').raw, 1);
      expect(Fx.parse('007.25').raw, 72500);
    });

    test('rejects malformed text and excess precision', () {
      for (final text in ['', '1.', '.5', '1e3', 'abc', '0.12345', '1.2.3']) {
        expect(() => Fx.parse(text), throwsFormatException, reason: text);
      }
    });

    test('formats with four decimals', () {
      expect(Fx.raw(1500).toDecimalString(), '0.1500');
      expect(Fx.raw(-15000).toDecimalString(), '-1.5000');
      expect(Fx.raw(1).toDecimalString(), '0.0001');
    });

    test('multiplies and divides with half-away-from-zero rounding', () {
      expect(Fx.parse('0.1') * Fx.parse('0.1'), Fx.parse('0.01'));
      expect(Fx.parse('0.0001') * Fx.parse('0.5'), Fx.parse('0.0001'));
      expect(-Fx.parse('0.0001') * Fx.parse('0.5'), -Fx.parse('0.0001'));
      expect(Fx.one.div(Fx.fromInt(3)), Fx.parse('0.3333'));
      expect(Fx.fromInt(2).div(Fx.fromInt(3)), Fx.parse('0.6667'));
      expect(Fx.one.div(-Fx.fromInt(3)), -Fx.parse('0.3333'));
      expect(Fx.parse('2.5').roundToInt(), 3);
      expect(Fx.parse('-2.5').roundToInt(), -3);
    });
  });

  group('Money', () {
    test('parses and formats cents', () {
      expect(Money.parse('12.34').cents, 1234);
      expect(Money.parse('-0.05').cents, -5);
      expect(Money(123456).toDecimalString(), '1234.56');
      expect(Money(-5).toDecimalString(), '-0.05');
      expect(() => Money.parse('1.234'), throwsFormatException);
    });

    test('scales by Fx and rounds to the cent', () {
      expect(Money(101).times(Fx.parse('0.5')), Money(51));
      expect(Money(-101).times(Fx.parse('0.5')), Money(-51));
      expect(Money.parse('19.99').times(Fx.parse('1.2')), Money.parse('23.99'));
      expect(Money.parse('2.49').timesInt(12), Money.parse('29.88'));
    });

    test('handles amounts near the top of the safe range', () {
      final huge = Money(9007199254740000);
      expect(huge.times(Fx.one), huge);
      expect(huge.times(Fx.parse('0.5')), Money(4503599627370000));
      expect(huge + Money(991), Money(9007199254740991));
    });
  });
}
