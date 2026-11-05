/// Calendar dates from integer day numbers, without `DateTime`.
library;

/// A calendar date.
typedef CivilDate = ({int year, int month, int day});

/// A day, counted from 1970-01-01 (day 0).
///
/// Dates are derived with Howard Hinnant's integer civil-date algorithms, so
/// they are identical on every platform.
extension type const Day(int number) {
  /// The day of a valid calendar date.
  factory Day.fromDate(int year, int month, int day) {
    if (!isValidDate(year, month, day)) {
      throw ArgumentError('Invalid date: $year-$month-$day');
    }
    final y = month <= 2 ? year - 1 : year;
    final era = (y >= 0 ? y : y - 399) ~/ 400;
    final yearOfEra = y - era * 400;
    final shiftedMonth = month > 2 ? month - 3 : month + 9;
    final dayOfYear = (153 * shiftedMonth + 2) ~/ 5 + day - 1;
    final dayOfEra =
        yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
    return Day(era * 146097 + dayOfEra - 719468);
  }

  /// Parses an ISO date such as `"2026-01-01"`.
  factory Day.parse(String text) {
    final match = _isoDate.firstMatch(text);
    if (match == null) {
      throw FormatException('Expected a date like 2026-01-01', text);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (!isValidDate(year, month, day)) {
      throw FormatException('No such date', text);
    }
    return Day.fromDate(year, month, day);
  }

  bool get isFirstOfMonth => date.day == 1;

  CivilDate get date {
    final z = number + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final dayOfEra = z - era * 146097;
    final yearOfEra =
        (dayOfEra -
            dayOfEra ~/ 1460 +
            dayOfEra ~/ 36524 -
            dayOfEra ~/ 146096) ~/
        365;
    final dayOfYear =
        dayOfEra - (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100);
    final shiftedMonth = (5 * dayOfYear + 2) ~/ 153;
    final month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9;
    return (
      year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
      month: month,
      day: dayOfYear - (153 * shiftedMonth + 2) ~/ 5 + 1,
    );
  }

  Day operator +(int days) => Day(number + days);

  bool operator <(Day other) => number < other.number;
  bool operator <=(Day other) => number <= other.number;
  bool operator >(Day other) => number > other.number;
  bool operator >=(Day other) => number >= other.number;

  String toIsoString() {
    final (:year, :month, :day) = date;
    final yyyy = year.toString().padLeft(4, '0');
    final mm = month.toString().padLeft(2, '0');
    final dd = day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int daysInMonth(int year, int month) => switch (month) {
  2 => isLeapYear(year) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

bool isValidDate(int year, int month, int day) =>
    month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month);
