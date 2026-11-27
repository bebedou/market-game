import 'package:engine/engine.dart';

import 'format.dart';

/// The ratios analysts judge a listed company by, its price against its
/// earnings, sales and books; null where one means nothing (no profit, no
/// sales, no book value).
typedef StockRatios = ({
  double? pe,
  double? pb,
  double? evSales,
  double? roe,
  double? dividendYield,
  double? netDebtEquity,
});

double? _over(Money a, Money b) => b > Money.zero ? a.cents / b.cents : null;

/// [stock]'s [StockRatios].
StockRatios ratiosOf(StockView stock) {
  final equity = stock.equity;
  final netDebt = -stock.books.netCash;
  return (
    pe: stock.multiple == null ? null : stock.multiple!.raw / Fx.scale,
    pb: _over(stock.cap, equity),
    evSales: _over(stock.cap + netDebt, stock.yearRevenue),
    roe: _over(stock.yearProfit, equity),
    dividendYield: _over(stock.yearDividends, stock.cap),
    netDebtEquity: _over(netDebt, equity),
  );
}

/// The median of [pick] over the companies of [sector] still trading,
/// in every country; null where none has one.
double? sectorMedian(
  List<StockView> stocks,
  int sector,
  double? Function(StockRatios ratios) pick,
) => median([
  for (final stock in stocks)
    if (stock.sector == sector && stock.running) ?pick(ratiosOf(stock)),
]);

/// The middle of [values], or the mean of the two middle ones; null for
/// none.
double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// A ratio to two places, or a dash.
String ratioText(double? value) =>
    value == null ? '—' : decimalText(value.toStringAsFixed(2));

/// A ratio as a percentage to one place, or a dash.
String ratioPercent(double? value) => value == null
    ? '—'
    : percentOf(decimalText((value * 100).toStringAsFixed(1)));

/// The stock market's sector of [format]'s trade, by position; null where
/// the market lists none.
int? sectorOfFormat(ContentDb content, FormatDef format) {
  final trade = formatTrades[format.key];
  final sectors = content.stocks?.sectors;
  if (trade == null || sectors == null) return null;
  final index = sectors.indexWhere((sector) => sector.trade == trade);
  return index < 0 ? null : index;
}
