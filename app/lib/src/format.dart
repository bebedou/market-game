import 'package:engine/engine.dart';

import 'l10n.dart';

/// An amount with thousands separators, such as `12,345` or `12.67`: cents
/// only below a thousand, where they matter, and not at all without
/// [cents]. The separators are the language's.
String money(Money amount, {bool cents = true}) {
  var value = amount.cents.abs();
  var fraction = '';
  if (cents && value < 100000) {
    fraction =
        '${tr('format.decimal')}'
        '${(value % 100).toString().padLeft(2, '0')}';
    value ~/= 100;
  } else {
    value = (value + 50) ~/ 100;
  }
  final separator = tr('format.group');
  final digits = value.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(separator);
    grouped.write(digits[i]);
  }
  final sign = amount.cents < 0 && grouped.toString() != '0' ? '−' : '';
  return '$sign$grouped$fraction';
}

/// Like [money], with a `+` on gains.
String signedMoney(Money amount, {bool cents = true}) => amount > Money.zero
    ? '+${money(amount, cents: cents)}'
    : money(amount, cents: cents);

/// [money] without separators, as the player would type it: for filling in
/// a field.
String moneyInput(Money amount) => decimalText(amount.toDecimalString());

/// A number written with a point, such as `1.5`, in the language's way.
String decimalText(String number) =>
    number.replaceFirst('.', tr('format.decimal'));

/// A rate or index as a plain number in the language's way, such as `1.0412`.
String fxText(Fx value) => decimalText(value.toDecimalString());

/// [value], a number already written out, as a percentage: `25%`.
String percentOf(Object value) => tr('format.percent', {'value': value});

/// A rate such as `0.025` as the number of a percentage, `2.5`.
String percentNumber(Fx rate, {int decimals = 1}) {
  var factor = 1;
  for (var i = 0; i < decimals; i++) {
    factor *= 10;
  }
  // Fx is in ten-thousandths, so percent × 10^decimals is raw × factor / 100.
  final scaled = (rate.raw.abs() * factor + 50) ~/ 100;
  final digits = scaled.toString().padLeft(decimals + 1, '0');
  final split = digits.length - decimals;
  final text = decimals == 0
      ? digits
      : '${digits.substring(0, split)}${tr('format.decimal')}'
            '${digits.substring(split)}';
  return '${rate.raw < 0 && scaled > 0 ? '−' : ''}$text';
}

/// A rate such as `0.025` as `2.5%`.
String percent(Fx rate, {int decimals = 1}) =>
    percentOf(percentNumber(rate, decimals: decimals));

/// A date in the real world, such as `4 Nov 2026`.
String calendarDate(DateTime date) => tr('format.date', {
  'day': date.day,
  'month': trList('format.months')[date.month - 1],
  'year': date.year,
});

/// A loan's length: "1 year", "7 years" or "18 months".
String termName(int months) => months % 12 != 0
    ? tr('terms.months', {'count': months})
    : tr('terms.years', {'count': months ~/ 12});

/// [part] out of [whole] as a whole percentage, or `–` if [whole] is zero.
String share(int part, int whole) =>
    whole == 0 ? '–' : percentOf((part * 100 + whole ~/ 2) ~/ whole);

String weekday(Day day) => trList('format.weekdays')[(day.number + 3) % 7];

/// `Thu 1 Jan 2026`.
String longDate(Day day) => tr('format.longDate', {
  'weekday': weekday(day),
  'day': day.date.day,
  'month': trList('format.months')[day.date.month - 1],
  'year': day.date.year,
});

/// `1 Jan`.
String shortDate(Day day) => tr('format.shortDate', {
  'day': day.date.day,
  'month': trList('format.months')[day.date.month - 1],
});

/// The month alone, as it reads within a sentence: `January`.
String monthOnly(Day day) => trList('format.monthNames')[day.date.month - 1];

/// `January 2026`, with a capital unless [capital] is false, where the
/// language gives its months none within a sentence.
String monthName(Day day, {bool capital = true}) {
  final month = monthOnly(day);
  return tr('format.monthYear', {
    'month': capital ? capitalized(month) : month,
    'year': day.date.year,
  });
}

/// [text] with its first letter a capital.
String capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// [text] with its first letter small.
String uncapitalized(String text) =>
    text.isEmpty ? text : '${text[0].toLowerCase()}${text.substring(1)}';

String slotName(DaySlot slot) => tr('terms.slots.${slot.name}');

/// Why shoppers went elsewhere, as the end of a sentence.
String causeText(SwitchCause cause) => tr('terms.causes.${cause.name}');

/// How long a cash cushion lasts: "2 weeks", or "10 days" when it isn't
/// whole weeks.
String cushionLength(int days) => days > 0 && days % 7 == 0
    ? tr('terms.weeks', {'count': days ~/ 7})
    : tr('terms.days', {'count': days});

/// "a convenience store", "a fast-food restaurant": one store of [format].
/// The scenario's translation says it; without one, its name will do.
String aFormat(FormatDef format) =>
    trMaybe('scenario.formats.${format.key}.a') ?? format.name.toLowerCase();

/// "a trainee manager": one manager of [grade].
String aManager(ManagerGradeDef grade) =>
    trMaybe('scenario.managers.grades.${grade.key}.a') ??
    grade.name.toLowerCase();

/// "trainee manager": a manager of [grade], with no article.
String managerOf(ManagerGradeDef grade) =>
    trMaybe('scenario.managers.grades.${grade.key}.one') ??
    grade.name.toLowerCase();

/// "trainee managers": several managers of [grade].
String managersOf(ManagerGradeDef grade) =>
    trMaybe('scenario.managers.grades.${grade.key}.many') ??
    grade.name.toLowerCase();

/// "a promoted manager", "a star director": one director of [grade].
String aDirector(DirectorGradeDef grade) =>
    trMaybe('scenario.directors.grades.${grade.key}.a') ??
    grade.name.toLowerCase();

/// "a recession": the [regime] the economy has entered.
String aRegime(RegimeDef regime) =>
    trMaybe('scenario.macro.regimes.${regime.key}.a') ??
    regime.name.toLowerCase();

/// "a quick survey": one study of [tier].
String aStudy(ResearchTierDef tier) =>
    trMaybe('scenario.research.${tier.key}.a') ?? tier.name.toLowerCase();

/// What to know before running stores by [strategy], if anything.
String? stanceAdvice(StrategyDef strategy) =>
    trMaybe('scenario.strategies.${strategy.key}.advice');

/// How far a director may grow a company, as a short phrase.
String growthName(Growth growth) => tr('terms.growth.${growth.name}');

/// What a manager does, as a short phrase.
String dutyName(ManagerDuty duty) => tr('terms.duties.${duty.name}');

String missText(MissReason reason) => tr('terms.misses.${reason.name}');

/// `A, B and C`.
String listText(List<String> items) => items.length == 1
    ? items.single
    : tr('format.listAnd', {
        'head': items.take(items.length - 1).join(', '),
        'last': items.last,
      });

/// Why the engine refused a command, as the end of a sentence, in the
/// language in use.
String refusalText(Refusal refusal, ContentDb content) =>
    tr('refusals.${refusal.key}', {
      if (refusal.amount case final amount?) 'amount': money(amount),
      'count': ?refusal.count,
      if (refusal.product case final product?)
        'product': content.products[product.index].name,
      if (refusal.supplier case final supplier?)
        'supplier': content.suppliers[supplier.index].name,
      if (refusal.format case final format?)
        'format': aFormat(content.formats[format.index]),
      if (refusal.toFormat case final format?)
        'toFormat': aFormat(content.formats[format.index]),
    });

/// Parses an amount typed by the player: `12.5`, `12,5`, `1,234.50` or
/// `1.234,50`. A lone separator before exactly three digits groups thousands
/// where the language writes them so; otherwise it marks the decimals. Null if
/// it isn't an amount.
Money? parseMoney(String text) {
  var cleaned = text.replaceAll(RegExp(r'\s'), '');
  final point = cleaned.lastIndexOf('.');
  final comma = cleaned.lastIndexOf(',');
  if (point >= 0 && comma >= 0) {
    // Both: the last one marks the decimals.
    final decimal = point > comma ? '.' : ',';
    final group = point > comma ? ',' : '.';
    cleaned = cleaned.replaceAll(group, '').replaceFirst(decimal, '.');
  } else if (point >= 0 || comma >= 0) {
    final mark = point >= 0 ? '.' : ',';
    final last = point >= 0 ? point : comma;
    final groups =
        cleaned.indexOf(mark) != last ||
        (mark == tr('format.group') && cleaned.length - last - 1 == 3);
    cleaned = groups
        ? cleaned.replaceAll(mark, '')
        : cleaned.replaceFirst(mark, '.');
  }
  try {
    return Money.parse(cleaned);
  } on FormatException {
    return null;
  }
}
