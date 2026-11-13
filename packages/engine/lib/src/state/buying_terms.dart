import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'entities.dart';

/// What [company]'s goods bought over its latest twelve months add up to.
Money goodsBoughtInYear(Company company) =>
    company.goodsMonths.fold(Money.zero, (sum, month) => sum + month);

/// What [company]'s suppliers take off its goods, by what it bought over
/// its latest twelve months: in every shop it has, run by hand, in districts
/// run by formula and across countries, and for its factories' materials.
/// Nothing without the scenario's buying terms.
Fx buyingDiscount(ContentDb content, Company company) =>
    buyingDiscountAt(content, goodsBoughtInYear(company));

/// The buying terms on [bought] a year of goods.
Fx buyingDiscountAt(ContentDb content, Money bought) {
  final terms = content.buyingTerms;
  if (terms == null || bought <= Money.zero) return Fx.zero;
  // In euros, to stay safe in the division.
  final euros = bought.cents ~/ 100;
  return Fx.raw(
    mulDivRound(terms.most.raw, euros, euros + terms.half.cents ~/ 100),
  );
}

/// Counts the month just ended in [company]'s goods bought: its cost of
/// goods since the last count, keeping twelve months.
void countGoodsMonth(Company company) {
  final now = company.accounts[AccountKind.costOfGoods];
  final month = now - (company.goodsMark ?? now);
  company.goodsMonths.add(month.isNegative ? Money.zero : month);
  if (company.goodsMonths.length > 12) company.goodsMonths.removeAt(0);
  company.goodsMark = now;
}
