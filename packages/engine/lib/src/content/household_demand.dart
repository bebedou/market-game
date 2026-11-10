import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'content_db.dart';

/// What [households], by segment, buy in a year of the categories [sells]
/// says, as `tradeDemand` works it out, from the lists it reads, so a
/// scenario being loaded can use it.
({Money spending, Money goods, Money atLevel, Fx units}) householdDemand(
  List<SegmentDef> segments,
  List<ProductDef> products,
  List<CategoryDef> categories, {
  required List<int> households,
  required Fx incomeLevel,
  required Fx priceLevel,
  required Fx priceIndex,
  required Day today,
  required List<bool> sells,
  Fx power = Fx.one,
  Fx premiumShift = Fx.zero,
  Fx scale = Fx.one,
}) {
  final level = priceIndex * priceLevel;
  var spending = Money.zero;
  var goods = Money.zero;
  var atLevel = Money.zero;
  var units = Fx.zero;
  for (final segment in segments) {
    final count = households[segment.id.index];
    if (count == 0) continue;
    for (final product in products) {
      final c = product.category.index;
      if (!sells[c]) continue;
      var yearly = segment.dailyUnits[c].timesInt(365);
      final adoption = categories[c].diffusion?.adoption(today);
      if (adoption != null) yearly *= adoption;
      yearly *= scale;
      var premium =
          segment.premiumShare[c] * incomeLevel * power + premiumShift;
      if (premium.isNegative) premium = Fx.zero;
      if (premium > Fx.one) premium = Fx.one;
      final tier = product.tier == ProductTier.premium
          ? premium
          : Fx.one - premium;
      final bought = (yearly * tier).timesInt(count);
      spending += product.referencePrice.times(level).times(bought);
      goods += product.baseCost.times(priceIndex).times(bought);
      atLevel += product.baseCost.times(level).times(bought);
      units += bought;
    }
  }
  return (spending: spending, goods: goods, atLevel: atLevel, units: units);
}

/// Which categories [channel]'s formats sell, indexed by category, given
/// every format's channel.
List<bool> channelSells(
  List<FormatDef> formats,
  List<int> channels,
  int channel,
  int categoryCount,
) => [
  for (var c = 0; c < categoryCount; c++)
    formats.any(
      (format) => channels[format.id.index] == channel && format.sells[c],
    ),
];

/// A place's households by segment, and what they buy of each channel against
/// their habits ([MarketDef.scale]), from its [market], what it spends a year
/// on each channel's goods (by channel, at its prices on [today] and a price
/// index of 1), and the [mix] of who lives there, a share for each segment.
/// There are as many households as would spend the whole market by their
/// habits; each channel is then scaled to its own figure, and a channel with
/// no figure stays as habits have it. [unbought] lists channels with a market
/// that nobody here buys from.
({List<int> households, List<Fx> scale, List<int> unbought}) placeSize(
  List<SegmentDef> segments,
  List<ProductDef> products,
  List<CategoryDef> categories,
  List<FormatDef> formats, {
  required Map<int, Money> market,
  required List<Fx> mix,
  required Fx incomeLevel,
  required Fx priceLevel,
  required Day today,
}) {
  final channels = formatChannelsOf(formats, categories.length);
  final channelCount = channels.fold(0, (most, c) => c >= most ? c + 1 : most);
  final mixTotal = mix.fold(0, (sum, share) => sum + share.raw);
  Money spent(List<int> households, int channel) => householdDemand(
    segments,
    products,
    categories,
    households: households,
    incomeLevel: incomeLevel,
    priceLevel: priceLevel,
    priceIndex: Fx.one,
    today: today,
    sells: channelSells(formats, channels, channel, categories.length),
  ).spending;
  // Ten thousand households, by the mix, and what they'd spend: few enough
  // for the sums to stay exact on the web.
  const reference = 10000;
  final sample = [
    for (final share in mix)
      mixTotal == 0 ? 0 : mulDivRound(share.raw, reference, mixTotal),
  ];
  var wanted = 0;
  var bySample = 0;
  for (final MapEntry(key: channel, value: amount) in market.entries) {
    wanted += amount.cents;
    bySample += spent(sample, channel).cents;
  }
  final total = wanted == 0 || bySample == 0
      ? 0
      : mulDivRound(wanted, reference, bySample);
  final households = [
    for (final share in mix)
      mixTotal == 0 ? 0 : mulDivRound(share.raw, total, mixTotal),
  ];
  final scale = List.filled(channelCount, Fx.one);
  final unbought = <int>[];
  for (final MapEntry(key: channel, value: amount) in market.entries) {
    if (amount == Money.zero) {
      scale[channel] = Fx.zero;
      continue;
    }
    final habits = spent(households, channel);
    if (habits <= Money.zero) {
      unbought.add(channel);
      continue;
    }
    scale[channel] = Fx.raw(mulDivRound(amount.cents, Fx.scale, habits.cents));
  }
  return (
    households: List.unmodifiable(households),
    scale: List.unmodifiable(scale),
    unbought: unbought,
  );
}
