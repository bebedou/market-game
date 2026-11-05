import 'dart:convert';

import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';

/// The trade each of the shop-level game's formats counts under.
const formatTrades = {
  'grocery': 'grocery',
  'supermarket': 'grocery',
  'fastfood': 'restaurants',
  'steakhouse': 'restaurants',
  'finedining': 'restaurants',
  'electronics': 'electronics',
};

/// What the full simulation's shops turn into sales of what households want,
/// per trade, from the numbers fitted by `tool/calibrate_countries.dart`.
Map<String, Fx> shopCapture(String calibrationJson) {
  final root = jsonDecode(calibrationJson) as Map<String, Object?>;
  final capture = root['capture']! as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in capture.entries)
      key: Fx.parse(value! as String),
  };
}

/// What households in a shop-level [market] want to spend on what [formats]
/// sell, in the year starting at [year] whole years after the start, by formula
/// from the scenario alone: households by type times what they buy, at normal
/// prices. [priceIndex] and [demand] are the year's averages from the macro
/// phase.
Money shopMarketWants(
  ContentDb content,
  MarketDef market, {
  required Set<String> formats,
  required int year,
  required Fx priceIndex,
  required Fx demand,
}) {
  final categories = <int>{
    for (final format in content.formats)
      if (formats.contains(format.key))
        for (final (c, sold) in format.sells.indexed)
          if (sold) c,
  };
  final middle = Day(content.startDay.number + year * 365 + 182);
  var total = Money.zero;
  for (final segment in content.segments) {
    var households = market.households[segment.id.index];
    if (households == 0) continue;
    // The growth up to the middle of the year.
    final rate = market.growth[segment.id.index];
    var grown = Fx.one;
    for (var y = 0; y < year; y++) {
      grown += grown * rate;
    }
    grown += grown * Fx.raw(mulDivRound(rate.raw, 1, 2));
    households = mulDivRound(households, grown.raw, Fx.scale);
    var perHousehold = Money.zero;
    for (final c in categories) {
      var units = segment.dailyUnits[c].timesInt(365) * demand;
      final adoption = content.categories[c].diffusion?.adoption(middle);
      if (adoption != null) units *= adoption;
      perHousehold += _typicalPrice(content, segment, market, c).times(units);
    }
    total += perHousehold.timesInt(households);
  }
  return total.times(market.priceLevel).times(priceIndex);
}

/// The price of what a household of [segment] picks in category [c].
Money _typicalPrice(
  ContentDb content,
  SegmentDef segment,
  MarketDef market,
  int c,
) {
  final prices = {
    for (final tier in ProductTier.values)
      tier: [
        for (final product in content.products)
          if (product.category.index == c && product.tier == tier)
            product.referencePrice.cents,
      ],
  };
  int mean(List<int> cents) =>
      mulDivRound(cents.fold(0, (sum, v) => sum + v), 1, cents.length);
  final budget = prices[ProductTier.budget]!;
  final premium = prices[ProductTier.premium]!;
  if (budget.isEmpty) return Money(mean(premium));
  if (premium.isEmpty) return Money(mean(budget));
  var share = segment.premiumShare[c] * market.incomeLevel;
  if (share > Fx.one) share = Fx.one;
  return Money(mean(budget)).times(Fx.one - share) +
      Money(mean(premium)).times(share);
}
