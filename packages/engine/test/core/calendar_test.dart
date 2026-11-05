import 'package:engine/src/core/calendar.dart';
import 'package:test/test.dart';

void main() {
  test('converts known dates', () {
    expect(Day.fromDate(1970, 1, 1), Day(0));
    expect(Day.fromDate(1969, 12, 31), Day(-1));
    expect(Day.fromDate(2000, 3, 1), Day(11017));
    expect(Day.fromDate(2024, 2, 29), Day(19782));
    expect(Day.fromDate(2026, 1, 1), Day(20454));
    expect(Day(20454).date, (year: 2026, month: 1, day: 1));
  });

  test('round-trips every day from 1900 to 2100', () {
    final first = Day.fromDate(1900, 1, 1);
    final last = Day.fromDate(2100, 12, 31);
    var expected = (year: 1900, month: 1, day: 1);
    for (var day = first; day <= last; day = day + 1) {
      final (:year, :month, day: dayOfMonth) = day.date;
      expect((year: year, month: month, day: dayOfMonth), expected);
      expect(Day.fromDate(year, month, dayOfMonth), day);
      expected = dayOfMonth < daysInMonth(year, month)
          ? (year: year, month: month, day: dayOfMonth + 1)
          : month < 12
          ? (year: year, month: month + 1, day: 1)
          : (year: year + 1, month: 1, day: 1);
    }
  });

  test('follows the Gregorian leap-year rule', () {
    expect(isLeapYear(2024), isTrue);
    expect(isLeapYear(2026), isFalse);
    expect(isLeapYear(1900), isFalse);
    expect(isLeapYear(2000), isTrue);
  });

  test('parses and formats ISO dates', () {
    expect(Day.parse('2026-10-26').toIsoString(), '2026-10-26');
    expect(Day.parse('2024-02-29'), Day(19782));
    for (final text in ['2026-02-29', '2026-13-01', '2026-1-1', 'today', '']) {
      expect(() => Day.parse(text), throwsFormatException, reason: text);
    }
  });
}
