import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../state/history.dart';
import '../state/research.dart';
import '../state/store.dart';
import '../state/world_state.dart';

/// A study of [market] for [buyer], taken from the true state today: each
/// estimate is the true value off by up to the [tier]'s error, either way.
ResearchReport commissionStudy(
  WorldState world,
  ContentDb content, {
  required PersonId buyer,
  required MarketId market,
  required ResearchTierDef tier,
}) {
  final number = world.nextReportNumber++;
  final rng = Rng.keyed(
    world.seed,
    RngStream.research,
    world.today.number,
    number,
  );
  Fx estimate(Fx truth) {
    final error = (rng.nextFx().timesInt(2) - Fx.one) * tier.error;
    return truth + truth * error;
  }

  final regime = content.macro.regimes[world.macro.regime.index];
  final power =
      content.demand.purchasingPower(
        world.macro.wageIndex,
        world.macro.priceIndex,
      ) *
      content.markets[market.index].incomeLevel;
  final households = List.filled(content.segments.length, 0);
  for (final cohort in world.cohorts) {
    if (cohort.market == market) {
      households[cohort.segment.index] += cohort.weight;
    }
  }
  final segments = [
    for (final segment in content.segments)
      SegmentEstimate(
        households: estimate(
          Fx.fromInt(households[segment.id.index]),
        ).roundToInt(),
        dailyUnits: List.unmodifiable([
          for (final units in segment.dailyUnits)
            estimate(units * regime.demand),
        ]),
        premiumShare: List.unmodifiable([
          for (final share in segment.premiumShare)
            estimate(_clamp(share * power + regime.premiumShift)),
        ]),
        // Segment averages: households spread around them by income.
        priceSensitivity: estimate(segment.priceSensitivity.div(power)),
        priceTolerance: estimate(segment.priceTolerance * power),
        slotShares: List.unmodifiable([
          for (final share in segment.slotShares) estimate(share),
        ]),
      ),
  ];

  final trading = [
    for (final store in world.stores)
      if (store.market == market && store.status == StoreStatus.open) store,
  ];
  final sold = [for (final store in trading) _unitsSold(world, store)];
  // Shoppers choose among the stores of a channel, so a share is of that.
  final channelOf = content.formatChannels;
  final totals = List.filled(content.channelCount, 0);
  for (final (i, store) in trading.indexed) {
    totals[channelOf[store.format.index]] += sold[i];
  }
  return ResearchReport(
    number: number,
    buyer: buyer,
    market: market,
    tier: tier.id,
    asOf: world.today,
    segments: List.unmodifiable(segments),
    unitShares: List.unmodifiable([
      for (final (i, store) in trading.indexed)
        (
          store: store.id,
          share: totals[channelOf[store.format.index]] == 0
              ? Fx.zero
              : estimate(
                  Fx.fromInt(
                    sold[i],
                  ).div(Fx.fromInt(totals[channelOf[store.format.index]])),
                ),
        ),
    ]),
  );
}

/// Units [store] sold over the last [salesHistoryDays] days.
int _unitsSold(WorldState world, Store store) {
  var units = 0;
  for (var ago = 1; ago <= salesHistoryDays; ago++) {
    final day = world.today + -ago;
    if (day < store.opensOn) break;
    for (var product = 0; product < store.prices.length; product++) {
      units += store.history.at(SalesCount.sold, ProductId(product), day);
    }
  }
  return units;
}

Fx _clamp(Fx share) =>
    share.isNegative ? Fx.zero : (share > Fx.one ? Fx.one : share);
