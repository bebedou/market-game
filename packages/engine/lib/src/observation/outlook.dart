import '../content/content_db.dart';
import '../content/household_demand.dart';
import '../core/calendar.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/store.dart';
import 'observation.dart';

/// What a new shop might do on a site, by estimate.
typedef ShopOutlook = ({
  /// A settled year's sales, at today's prices.
  Money sales,

  /// A settled year's profit before tax.
  Money profit,

  /// What households here spend on what the shop's channel sells, a year.
  Money spending,

  /// Its share of that: a shop takes nothing from any other channel's.
  Fx share,

  /// The shops of its channel trading here now.
  int rivals,
});

/// What a typical new shop of a format does with its neighbourhood's trade,
/// fitted to new shops opened in test games.
final class ShopHabits {
  const ShopHabits({
    required this.capture,
    required this.draw,
    required this.goodsExtra,
    required this.peakStaff,
    this.unitsPerVisit = 1,
  });

  /// What it turns into sales of what households here would buy from it.
  final Fx capture;

  /// How it draws shoppers against the shops already here, for its site.
  final Fx draw;

  /// What its goods cost beyond the list: what it throws away, less what its
  /// suppliers take off for volume.
  final Fx goodsExtra;

  /// The staff it keeps for its busiest hours, against its average: shoppers
  /// don't come evenly through the day.
  final Fx peakStaff;

  final int unitsPerVisit;
}

const _grocer = ShopHabits(
  capture: Fx.raw(9500),
  draw: Fx.raw(9000),
  goodsExtra: Fx.raw(-200),
  peakStaff: Fx.raw(14000),
  unitsPerVisit: 3,
);

ShopHabits habitsOf(FormatDef format) => switch (format.key) {
  'fastfood' => const ShopHabits(
    capture: Fx.one,
    draw: Fx.raw(9000),
    goodsExtra: Fx.raw(2200),
    peakStaff: Fx.raw(17000),
  ),
  'steakhouse' => const ShopHabits(
    capture: Fx.one,
    draw: Fx.one,
    goodsExtra: Fx.raw(1600),
    peakStaff: Fx.raw(16000),
  ),
  'finedining' => const ShopHabits(
    capture: Fx.one,
    draw: Fx.raw(14000),
    goodsExtra: Fx.raw(3000),
    peakStaff: Fx.raw(17000),
  ),
  'electronics' => const ShopHabits(
    capture: Fx.raw(11000),
    draw: Fx.raw(9000),
    goodsExtra: Fx.zero,
    peakStaff: Fx.raw(15000),
  ),
  _ => _grocer,
};

/// How much a rival's prices against normal weigh on who shoppers choose.
const _priceWeight = Fx.raw(50000);
const _dearest = Fx.raw(500);
const _cheapest = Fx.raw(-1500);

/// What [households], by segment, buy in a year of what [format] sells: at
/// normal prices; at what the goods cost; at that cost at the place's prices,
/// which a strategy's markup goes on; and how many units that is. They buy dearer
/// the more they have to spend, as [power] says against normal, and a downturn
/// has them trade down by [premiumShift]. [scale] is the place's for the
/// format's channel ([MarketDef.scale]); [costLevel] its country's
/// ([ContentDb.costLevel]).
({Money spending, Money goods, Money atLevel, Fx units}) tradeDemand(
  ContentDb content, {
  required List<int> households,
  required Fx incomeLevel,
  required Fx priceLevel,
  required Fx priceIndex,
  required Day today,
  required FormatDef format,
  Fx power = Fx.one,
  Fx premiumShift = Fx.zero,
  Fx scale = Fx.one,
  Fx costLevel = Fx.one,
  List<Money>? references,
}) => householdDemand(
  content.segments,
  content.products,
  content.categories,
  households: households,
  incomeLevel: incomeLevel,
  priceLevel: priceLevel,
  priceIndex: priceIndex,
  today: today,
  sells: format.sells,
  power: power,
  premiumShift: premiumShift,
  scale: scale,
  costLevel: costLevel,
  references: references,
);

/// What households in [market] buy in a year of what [format] sells. Households
/// by type are the scenario's mix at the latest census.
({Money spending, Money goods, Money atLevel, Fx units}) _demand(
  Observation view,
  ContentDb content,
  MarketDef market,
  FormatDef format,
) => tradeDemand(
  content,
  households: _counted(view, market),
  incomeLevel: market.incomeLevel,
  priceLevel: market.priceLevel,
  priceIndex: view.economyAt(content, market.id).priceIndex,
  today: view.today,
  format: format,
  scale: market.scaleOf(content.formatChannels[format.id.index]),
  costLevel: content.costLevel(market.country),
  references: content.references[market.country.index],
);

/// [market]'s households by segment, its scenario's mix at the latest census.
List<int> _counted(Observation view, MarketDef market) {
  final mix = market.households.fold(0, (sum, count) => sum + count);
  // A neighbourhood still asleep has had no census: it's as its plan says.
  final census = market.id.index < view.households.length
      ? view.households[market.id.index]
      : mix;
  return [
    for (final count in market.households)
      mix == 0 ? 0 : mulDivRound(count, census, mix),
  ];
}

/// What [households], [market]'s own by default, spend a year on [channel]'s
/// goods at normal prices, at [priceIndex], on [today] (the scenario's start
/// by default): at the start, the market the scenario gave the place.
Money marketSpending(
  ContentDb content,
  MarketDef market,
  int channel, {
  List<int>? households,
  Fx priceIndex = Fx.one,
  Day? today,
}) => householdDemand(
  content.segments,
  content.products,
  content.categories,
  households: households ?? market.households,
  incomeLevel: market.incomeLevel,
  priceLevel: market.priceLevel,
  priceIndex: priceIndex,
  today: today ?? content.startDay,
  sells: channelSells(
    content.formats,
    content.formatChannels,
    channel,
    content.categories.length,
  ),
  scale: market.scaleOf(channel),
  references: content.references[market.country.index],
).spending;

/// What households in [market] spend a year on [channel]'s goods at today's
/// normal prices, as many as the latest census counts: the trade's market.
Money channelSpending(
  Observation view,
  ContentDb content,
  MarketDef market,
  int channel,
) => marketSpending(
  content,
  market,
  channel,
  households: _counted(view, market),
  priceIndex: view.economyAt(content, market.id).priceIndex,
  today: view.today,
);

/// How a shop's [location] and [area] draw shoppers, as they weigh size.
Fx shopPull(ContentDb content, Fx location, int area) =>
    location *
    Fx.raw(mulDivRound(area, Fx.scale, area + content.demand.halfSizeArea));

/// A year's wages for a shop serving [unitsServed] a year: staff for the
/// shoppers, and for every slot it opens at all.
Money yearlyWages(
  ContentDb content,
  FormatDef format,
  StrategyDef strategy, {
  required Fx wageIndex,
  required Fx wageLevel,
  required Fx unitsServed,
  required int unitsPerVisit,
  required Fx peak,
}) {
  final visits = Fx.raw(mulDivRound(unitsServed.raw, 1, 365 * unitsPerVisit));
  final staff = Fx.raw(
    mulDivRound(
      (visits * strategy.serviceTarget * peak).raw,
      1,
      format.visitsPerStaff,
    ),
  );
  final slots = Fx.fromInt(strategy.hours.where((open) => open).length);
  // There's only so much room for staff, however many shoppers come.
  final most = slots.timesInt(content.operations.maxStaffPerSlot);
  return content.operations.slotWage
      .times(wageIndex * wageLevel * format.wageFactor)
      .times(staff > most ? most : (staff > slots ? staff : slots))
      .timesInt(365);
}

/// What households in [market] spend in a year on what [format] sells: all the
/// trade there is for its shops to share.
Money tradeSpending(
  Observation view,
  ContentDb content,
  MarketDef market,
  FormatDef format,
) => _demand(view, content, market, format).spending;

/// The strategy a well-run shop of [format] follows: the balanced one of its
/// channel if it has one, or else its channel's first.
StrategyDef usualStrategy(ContentDb content, FormatDef format) {
  final channel = content.formatChannels[format.id.index];
  final own = [
    for (final strategy in content.strategies)
      if (content.formatChannels[strategy.format.index] == channel) strategy,
  ];
  if (own.isEmpty) return content.strategies.first;
  return own.firstWhere(
    (strategy) => strategy.key == 'balanced',
    orElse: () => own.first,
  );
}

/// How a shop's shelf [prices] against normal draw shoppers: a cheaper one
/// more.
Fx _priceDraw(
  ContentDb content,
  List<Money?> prices,
  MarketDef market,
  MacroView macro,
) {
  final level = macro.priceIndex * market.priceLevel;
  var atShelf = 0;
  var normal = 0;
  for (final (p, price) in prices.indexed) {
    if (price == null) continue;
    atShelf += price.cents;
    normal += content
        .referenceIn(content.products[p], market.country)
        .times(level)
        .cents;
  }
  if (normal == 0) return Fx.one;
  return priceDraw(Fx.raw(mulDivRound(atShelf - normal, Fx.scale, normal)));
}

/// How prices [gap] above normal draw shoppers, within what lasts: a shop far
/// from normal doesn't stay there, as a new game's dear shops soon settle.
Fx priceDraw(Fx gap) {
  if (gap > _dearest) gap = _dearest;
  if (gap < _cheapest) gap = _cheapest;
  return gap.isNegative
      ? Fx.one.div(expNeg(_priceWeight * -gap))
      : expNeg(_priceWeight * gap);
}

/// What a new shop of [format] on [site] might do, from what anyone can see,
/// or, for a neighbourhood still asleep, from its plan ([content] being
/// `Simulation.plan`):
/// who lives in the neighbourhood and buys what, the rivals of its own channel
/// on its streets and their prices, and what the site and staff cost. It
/// assumes normal prices
/// and a shop that is run well, past its first months, with no manager.
ShopOutlook shopOutlook(
  Observation view,
  ContentDb content,
  SiteDef site,
  FormatDef format,
) {
  final market = content.markets[site.market.index];
  final habits = habitsOf(format);
  final macro = view.economyAt(content, market.id);
  final (:spending, :goods, :units, atLevel: _) = _demand(
    view,
    content,
    market,
    format,
  );
  Fx pull(Fx location, int area) => shopPull(content, location, area);
  final channel = content.formatChannels[format.id.index];
  final mine = pull(site.location, site.area) * habits.draw;
  var total = mine;
  var rivals = 0;
  // Shops of a neighbourhood asleep are in its plan alone.
  if (market.id.index >= view.households.length) {
    for (final store in content.stores) {
      final there = content.sites[store.site.index];
      if (there.market != market.id ||
          content.formatChannels[store.format.index] != channel) {
        continue;
      }
      total +=
          pull(there.location, store.area ?? there.area) *
          _priceDraw(content, store.prices, market, macro);
      rivals++;
    }
  }
  for (final shelf in view.shelves) {
    if (shelf.market != market.id ||
        content.formatChannels[shelf.format.index] != channel ||
        shelf.status == StoreStatus.closed) {
      continue;
    }
    total +=
        pull(shelf.location, shelf.area) *
        _priceDraw(content, shelf.prices, market, macro);
    rivals++;
  }
  final share = mine.div(total);
  final served = share * habits.capture;
  final sales = spending.times(served);
  final bought = goods.times(served);

  final strategy = usualStrategy(content, format);
  final wages = yearlyWages(
    content,
    format,
    strategy,
    wageIndex: macro.wageIndex,
    wageLevel: market.wageLevel,
    unitsServed: units * served,
    unitsPerVisit: habits.unitsPerVisit,
    peak: habits.peakStaff,
  );
  final premises = (site.rent + format.overheadsFor(site.area))
      .times(macro.priceIndex)
      .timesInt(12);
  final profit =
      sales -
      bought -
      bought.times(habits.goodsExtra) -
      sales.times(strategy.marketingShare) -
      wages -
      premises;
  return (
    sales: sales,
    profit: profit,
    spending: spending,
    share: share,
    rivals: rivals,
  );
}
