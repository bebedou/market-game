import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../fundamentals.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// A company's books, the owner's layout B of 2026-11-27: given an asking
/// [price], first what the price pays for, its book value against the
/// goodwill above it; then the balance sheet; then, with its latest
/// [filing], its ratios against its sector's listed companies.
class CompanyBooks extends StatelessWidget {
  const CompanyBooks({
    super.key,
    required this.sheet,
    this.price,
    this.filing,
    this.sector,
    this.stocks = const [],
    this.titled = true,
  });

  final BalanceSheet sheet;
  final Money? price;
  final Filing? filing;

  /// The stock market's sector its trade is listed in, and the market's
  /// companies, for the medians it is judged against.
  final int? sector;
  final List<StockView> stocks;

  /// Whether it heads its balance sheet itself, as it does where no
  /// section does.
  final bool titled;

  @override
  Widget build(BuildContext context) {
    final ledger = Ledger.of(context);
    final equity = sheet.equity;
    final price = this.price;
    Widget? split;
    if (price != null) {
      split = equity >= price
          ? Line(
              tr('market.belowBook'),
              compactMoney(equity - price),
              color: ledger.gain,
            )
          : SplitBar([
              if (equity > Money.zero)
                (
                  label: tr('stocks.recordBook'),
                  value: equity.cents,
                  color: ledger.ink,
                ),
              (
                label: tr('market.goodwill'),
                value:
                    (price - (equity > Money.zero ? equity : Money.zero)).cents,
                color: ledger.rule,
              ),
            ]);
    }
    Line part(String key, Money amount, {bool owed = false}) =>
        Line(tr(key), compactMoney(owed ? -amount : amount));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (split != null) ...[
          Text(
            tr('market.pricePaysFor'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: ledger.muted),
          ),
          const SizedBox(height: 4),
          split,
          const SizedBox(height: 8),
        ],
        if (titled)
          Text(
            tr('stocks.balanceSheet'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        part('market.cash', sheet.cash),
        if (sheet.inventories > Money.zero)
          part('market.inventories', sheet.inventories),
        if (sheet.receivables > Money.zero)
          part('market.receivables', sheet.receivables),
        part('stocks.fixedAssets', sheet.fixedAssets),
        if (sheet.goodwill > Money.zero)
          part('market.goodwill', sheet.goodwill),
        if (sheet.shareholdings > Money.zero)
          part('market.shareholdings', sheet.shareholdings),
        if (sheet.payables > Money.zero)
          part('market.payables', sheet.payables, owed: true),
        if (sheet.loans > Money.zero)
          part('market.loans', sheet.loans, owed: true),
        Line(tr('stocks.equity'), compactMoney(equity), strong: true),
        if (filing case final filing?) ...[
          const SizedBox(height: 8),
          Text(
            tr('market.filedAccounts', {'year': filing.year}),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Line(tr('stocks.recordSales'), compactMoney(filing.revenue)),
          Line(tr('stocks.recordProfit'), compactMoney(filing.profit)),
          if (price != null) ..._againstSector(context, price, filing),
        ],
      ],
    );
  }

  /// P/E, price to book and return on equity, each stamped against its
  /// sector's median: below, in line (within a fifth) or above.
  List<Widget> _againstSector(
    BuildContext context,
    Money price,
    Filing filing,
  ) {
    final ledger = Ledger.of(context);
    final equity = sheet.equity;
    final profit = filing.profit;
    double? over(Money a, Money b) => b > Money.zero ? a.cents / b.cents : null;
    final rows = [
      (
        label: tr('stocks.multiple'),
        own: over(price, profit),
        median: _median((r) => r.pe),
        text: ratioText,
        higherIsBetter: false,
      ),
      (
        label: tr('stocks.priceToBook'),
        own: over(price, equity),
        median: _median((r) => r.pb),
        text: ratioText,
        higherIsBetter: false,
      ),
      (
        label: tr('stocks.returnOnEquity'),
        own: over(profit, equity),
        median: _median((r) => r.roe),
        text: ratioPercent,
        higherIsBetter: true,
      ),
    ];
    return [
      const SizedBox(height: 8),
      Text(
        tr('market.againstSector'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Line(
                  row.label,
                  row.text(row.own),
                  hint: row.median == null
                      ? null
                      : tr('stocks.sectorMedian', {
                          'value': row.text(row.median),
                        }),
                ),
              ),
              if (row.own != null && row.median != null) ...[
                const SizedBox(width: 8),
                _stamp(row.own!, row.median!, row.higherIsBetter, ledger),
              ],
            ],
          ),
        ),
    ];
  }

  double? _median(double? Function(StockRatios ratios) pick) {
    final sector = this.sector;
    return sector == null ? null : sectorMedian(stocks, sector, pick);
  }

  Widget _stamp(double own, double median, bool higherIsBetter, Ledger ledger) {
    if (median <= 0 || (own / median - 1).abs() <= 0.2) {
      return Stamp(tr('market.inLine'), color: ledger.muted);
    }
    final above = own > median;
    final good = above == higherIsBetter;
    return Stamp(
      tr(above ? 'market.above' : 'market.below'),
      color: good ? ledger.gain : ledger.loss,
    );
  }
}
