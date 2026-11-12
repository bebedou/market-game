import '../content/content_db.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../reports/attribution.dart';
import '../state/cohort.dart';
import '../state/store.dart';
import '../state/world_state.dart';
import 'sales.dart';
import 'tick_system.dart';

/// The demand phase: needs accrue, households shop, and what they find
/// shapes where they shop next. See "Demand model" in Engine Architecture.md.
final class DemandSystem implements TickSystem {
  const DemandSystem();

  @override
  void run(WorldState world, TickContext context) {
    final day = _ShoppingDay(world, context);
    final shoppers = <HouseholdCohort>[];
    for (final cohort in world.cohorts) {
      day.accrueNeeds(cohort);
      day.hearPrices(cohort);
      if (day.shopsToday(cohort)) shoppers.add(cohort);
    }
    // Who reaches the shelves first matters when stock runs short.
    final rng = context.rng(RngStream.shoppingOrder, 0);
    for (var i = shoppers.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final swap = shoppers[i];
      shoppers[i] = shoppers[j];
      shoppers[j] = swap;
    }
    for (final cohort in shoppers) {
      _Trip(day, cohort).run();
    }
  }
}

/// What stays fixed while one day's households shop: the economy, stores by
/// market, each segment's actual price index at each store, and products by
/// tier.
final class _ShoppingDay {
  _ShoppingDay(this.world, this.context)
    : content = context.content,
      premiumShifts = [
        for (final country in context.content.countries)
          country.premiumShiftIn(
            context.content.macro.regimes[world
                .macroOf(country.id)
                .regime
                .index],
          ),
      ],
      priceLevels = [
        for (final country in context.content.countries)
          world.macroOf(country.id).priceIndex,
      ],
      purchasingPowers = [
        for (final country in context.content.countries)
          context.content.demand.purchasingPower(
            world.macroOf(country.id).wageIndex,
            world.macroOf(country.id).priceIndex,
          ),
      ],
      allStoresIn = [
        for (final market in context.content.markets)
          [
            for (final store in world.stores)
              if (store.market == market.id) store,
          ],
      ],
      storesIn = [
        for (final market in context.content.markets)
          [
            for (final store in world.stores)
              if (store.market == market.id &&
                  store.status == StoreStatus.open &&
                  store.hasHours)
                store,
          ],
      ],
      priceIndex = [
        for (final segment in context.content.segments)
          [
            for (final store in world.stores)
              segment.priceIndex(
                context.content.products,
                store.prices,
                priceLevel:
                    world.macroAt(context.content, store.market).priceIndex *
                    context.content.markets[store.market.index].priceLevel,
                references: context.content.references[context.content
                    .countryOf(store.market)
                    .index],
              ),
          ],
      ],
      _products = [
        for (final category in context.content.categories)
          [
            for (final tier in ProductTier.values)
              context.content.products
                  .where((p) => p.category == category.id && p.tier == tier)
                  .firstOrNull
                  ?.id,
          ],
      ],
      _wanted = List.filled(world.stores.length, 0),
      _credit = List.filled(world.stores.length, 0) {
    final maxNeedDays = content.demand.maxNeedDays;
    // A category still spreading is bought by the share that has adopted it.
    final adoption = [
      for (final category in content.categories)
        category.diffusion?.adoption(context.day),
    ];
    // Each country's households buy as its cycle has them, and unemployment
    // above its natural rate weighs on what they spend.
    final habitsIn = [
      for (final country in content.countries)
        () {
          final macro = world.macroOf(country.id);
          final demand = country.demandIn(
            content.macro.regimes[macro.regime.index],
          );
          final confidence = content.macro.labour?.confidenceFactor(
            macro.unemployment,
          );
          return [
            for (final segment in content.segments)
              [
                for (final (c, units) in segment.dailyUnits.indexed)
                  _withConfidence(switch (adoption[c]) {
                    final share? => units * demand * share,
                    null => units * demand,
                  }, confidence),
              ],
          ];
        }(),
    ];
    // Each market buys of each channel as much as its scale says.
    for (final market in content.markets) {
      final needs = <List<Fx>>[];
      final caps = <List<Fx>>[];
      for (final daily in habitsIn[market.country.index]) {
        final scaled = [
          for (final (c, units) in daily.indexed)
            units * market.scaleOf(content.categoryChannels[c]),
        ];
        needs.add(scaled);
        // A need carries over at most a few days' worth, but always up to a
        // whole unit, or what is bought less than weekly would never be.
        caps.add([
          for (final units in scaled)
            units == Fx.zero || units.timesInt(maxNeedDays) >= Fx.one
                ? units.timesInt(maxNeedDays)
                : Fx.one,
        ]);
      }
      dailyNeeds.add(needs);
      needCaps.add(caps);
    }
    final half = content.demand.halfSizeArea;
    final sizes = [
      for (final store in world.stores)
        Fx.raw(mulDivRound(store.area, Fx.scale, store.area + half)),
    ];
    for (final segment in content.segments) {
      sizeTerms.add([for (final size in sizes) segment.sizeWeight * size]);
    }
    for (final store in world.stores) {
      final slots = store.staff.length;
      slotFor.add([
        for (var preferred = 0; preferred < slots; preferred++)
          _nearestOpenSlot(store, preferred),
      ]);
    }
    final channels = content.channelCount;
    final channelOf = content.formatChannels;
    for (final stores in allStoresIn) {
      channelStoresIn.add([
        for (var channel = 0; channel < channels; channel++)
          [
            for (final store in stores)
              if (channelOf[store.format.index] == channel) store,
          ],
      ]);
    }
    for (final stores in storesIn) {
      openChannelStoresIn.add([
        for (var channel = 0; channel < channels; channel++)
          [
            for (final store in stores)
              if (channelOf[store.format.index] == channel) store,
          ],
      ]);
    }
    for (final segment in content.segments) {
      final prices = priceIndex[segment.id.index];
      shoppable.add([
        for (final byChannel in openChannelStoresIn)
          [
            for (final stores in byChannel)
              [
                for (final store in stores)
                  if (prices[store.id.index] != null) store,
              ],
          ],
      ]);
    }
    final tuning = content.demand;
    final halfPulls = [
      for (final level in priceLevels) tuning.halfGoodwill.times(level).cents,
    ];
    for (final store in world.stores) {
      final goodwill = store.goodwill.cents;
      final halfPull = halfPulls[content.countryOf(store.market).index];
      marketingTerms.add(
        goodwill <= 0 || tuning.marketingWeight == Fx.zero
            ? Fx.zero
            : tuning.marketingWeight *
                  Fx.raw(mulDivRound(goodwill, Fx.scale, goodwill + halfPull)),
      );
    }
    for (final market in content.markets) {
      final level = priceLevels[market.country.index] * market.priceLevel;
      references.add([
        for (final product in content.products)
          content.referenceIn(product, market.country).times(level),
      ]);
    }
  }

  /// The open stores of each market and channel that list something for
  /// each segment, indexed by [SegmentId], then [MarketId], then channel.
  final List<List<List<List<Store>>>> shoppable = [];

  /// Every store ever opened, and those open for business, per market and
  /// channel, indexed by [MarketId], then channel.
  final List<List<List<Store>>> channelStoresIn = [];
  final List<List<List<Store>>> openChannelStoresIn = [];

  /// The pull of each store's marketing, indexed by [StoreId]: the weight
  /// times its goodwill over its goodwill plus the half-pull goodwill.
  final List<Fx> marketingTerms = [];

  /// What households in each market think each product should cost today,
  /// indexed by [MarketId], then [ProductId].
  final List<List<Money>> references = [];

  static Fx _withConfidence(Fx units, Fx? confidence) =>
      confidence == null ? units : units * confidence;

  /// [preferred] if the store is staffed then, or else the nearest slot it
  /// is, later ones first on a tie; [preferred] if it never is.
  static int _nearestOpenSlot(Store store, int preferred) {
    final slots = store.staff.length;
    for (var distance = 0; distance < slots; distance++) {
      final later = (preferred + distance) % slots;
      if (store.staff[later] > 0) return later;
      final earlier = (preferred - distance + slots) % slots;
      if (store.staff[earlier] > 0) return earlier;
    }
    return preferred;
  }

  /// Each segment's need per household today, and the most it can carry
  /// over, indexed by [MarketId], then [SegmentId], then [CategoryId].
  final List<List<List<Fx>>> dailyNeeds = [];
  final List<List<List<Fx>>> needCaps = [];

  /// The pull of each store's size for each segment, indexed by [SegmentId],
  /// then [StoreId].
  final List<List<Fx>> sizeTerms = [];

  /// The slot each store serves a household that prefers each slot, indexed
  /// by [StoreId], then slot.
  final List<List<int>> slotFor = [];

  /// Scratch for one trip at a time: units looked for at each store, and the
  /// fill credit earned there as Fx raw values, indexed by [StoreId]. A trip
  /// clears what it used.
  final List<int> _wanted;
  final List<int> _credit;

  final WorldState world;
  final TickContext context;
  final ContentDb content;

  /// How far each country's households trade up or down today, by
  /// [CountryId].
  final List<Fx> premiumShifts;

  /// Each country's price index, which reference prices scale with, by
  /// [CountryId].
  final List<Fx> priceLevels;

  /// Each country's households' purchasing power against the start, by
  /// [CountryId].
  final List<Fx> purchasingPowers;

  /// Every store ever opened per market, closed ones included, indexed by
  /// [MarketId].
  final List<List<Store>> allStoresIn;

  /// Stores open for business per market, indexed by [MarketId].
  final List<List<Store>> storesIn;

  /// Indexed by [SegmentId], then [StoreId]; null where nothing is listed.
  final List<List<Fx?>> priceIndex;

  /// Indexed by [CategoryId], then [ProductTier].
  final List<List<ProductId?>> _products;

  /// The product of [tier] in [category], or the category's other product
  /// if there is none of that tier.
  ProductId? productIn(CategoryId category, ProductTier tier) =>
      _products[category.index][tier.index] ??
      _products[category.index][_other(tier).index];

  /// The other tier's product in [product]'s category, if any.
  ProductId? otherTier(ProductId product) {
    final definition = content.products[product.index];
    return _products[definition.category.index][_other(definition.tier).index];
  }

  static ProductTier _other(ProductTier tier) =>
      tier == ProductTier.budget ? ProductTier.premium : ProductTier.budget;

  void accrueNeeds(HouseholdCohort cohort) {
    final daily = dailyNeeds[cohort.market.index][cohort.segment.index];
    final caps = needCaps[cohort.market.index][cohort.segment.index];
    final needs = cohort.needs;
    for (var c = 0; c < needs.length; c++) {
      final need = needs[c] + daily[c];
      needs[c] = need > caps[c] ? caps[c] : need;
    }
  }

  /// Word of mouth: believed prices drift toward the actual ones.
  void hearPrices(HouseholdCohort cohort) {
    final segment = content.segments[cohort.segment.index];
    final actual = priceIndex[cohort.segment.index];
    for (final store in storesIn[cohort.market.index]) {
      final i = store.id.index;
      final price = actual[i];
      if (price == null) continue;
      final believed = cohort.perceivedPrices[i];
      if (believed == price) continue;
      cohort.perceivedPrices[i] =
          believed + segment.wordOfMouth * (price - believed);
    }
  }

  /// Cohorts shop every few days, spread across the week by ID, when at
  /// least one need has reached a whole unit.
  bool shopsToday(HouseholdCohort cohort) {
    final interval = content.segments[cohort.segment.index].tripIntervalDays;
    return cohort.weight > 0 &&
        (context.day.number + cohort.id.index) % interval == 0 &&
        cohort.needs.any((need) => need >= Fx.one);
  }
}

/// One cohort's shopping trip: where it goes, what it buys, and what it
/// learns.
final class _Trip {
  _Trip(this.day, this.cohort)
    : segment = day.content.segments[cohort.segment.index],
      stores = day.storesIn[cohort.market.index],
      actualPrices = day.priceIndex[cohort.segment.index],
      rng = day.context.rng(RngStream.shopping, cohort.id.index),
      _wanted = day._wanted,
      _credit = day._credit,
      _sizeTerms = day.sizeTerms[cohort.segment.index],
      _references = day.references[cohort.market.index] {
    final income = segment.relativeIncome(cohort.incomeRank);
    final market = day.content.markets[cohort.market.index];
    final power =
        day.purchasingPowers[market.country.index] * market.incomeLevel;
    premiumShift = day.premiumShifts[market.country.index];
    affluence = income * power;
    // Poorer households than the segment's average care more about price,
    // richer ones less; the segment's average stays its sensitivity, which
    // falls as purchasing power grows.
    priceSensitivity = (segment.priceSensitivity * (Fx.fromInt(2) - income))
        .div(power);
    priceTolerance = segment.priceTolerance * affluence;
  }

  final _ShoppingDay day;
  final HouseholdCohort cohort;
  final SegmentDef segment;

  /// The stores open for business in the cohort's market.
  final List<Store> stores;

  /// Indexed by [StoreId].
  final List<Fx?> actualPrices;
  final Rng rng;

  /// The households' income against their segment's average at the start,
  /// purchasing power included.
  late final Fx affluence;

  /// How far households in the cohort's country trade up or down today.
  late final Fx premiumShift;

  late final Fx priceSensitivity;

  /// How far above reference prices the households buy without balking.
  late final Fx priceTolerance;

  /// Units looked for at each store, and the fill credit earned there as Fx
  /// raw values, indexed by [StoreId]: the day's scratch, cleared by [_learn].
  final List<int> _wanted;
  final List<int> _credit;

  /// The pull of each store's size for the cohort's segment.
  final List<Fx> _sizeTerms;

  /// Reference prices in the cohort's market, indexed by [ProductId].
  final List<Money> _references;

  Attribution get _attribution => day.context.attribution;

  /// A trip to a store of each channel the cohort needs something from:
  /// groceries at a convenience store or a supermarket, a meal at a
  /// restaurant.
  void run() {
    final channels = day.content.channelCategories;
    for (var channel = 0; channel < channels.length; channel++) {
      final categories = channels[channel];
      if (categories.any(
        (category) => cohort.needs[category.index] >= Fx.one,
      )) {
        _visit(channel, categories);
      }
    }
  }

  void _visit(int channel, List<CategoryId> categories) {
    final market = cohort.market.index;
    final open = day.shoppable[cohort.segment.index][market][channel];
    if (open.isEmpty) return;
    final store = _choose(open);
    _attribution.addVisit(store.id, cohort.weight);
    _recordSwitch(store, day.channelStoresIn[market][channel]);
    for (final category in categories) {
      _shopFor(category, store);
    }
    _learn(day.channelStoresIn[market][channel]);
  }

  Fx _utility(Store store) {
    final i = store.id.index;
    return segment.convenienceWeight * _convenience(store) +
        segment.loyaltyWeight * cohort.loyalty[i] -
        _priceTerm(cohort.perceivedPrices[i]) +
        _serviceTerm(store) +
        _sizeTerm(store) +
        _marketingTerm(store) +
        _reputationTerm(store) -
        _hoursPenalty(store);
  }

  /// The pull of what everyone thinks of the store.
  Fx _reputationTerm(Store store) =>
      day.content.demand.reputationWeight * store.reputation;

  /// The pull of the store's size: the segment's weight times its area over
  /// its area plus the half-size area.
  Fx _sizeTerm(Store store) => _sizeTerms[store.id.index];

  /// The pull of the store's advertising.
  Fx _marketingTerm(Store store) => day.marketingTerms[store.id.index];

  /// What a store's believed price index costs it: dearer than expected
  /// weighs the loss aversion times more than cheaper helps.
  Fx _priceTerm(Fx perceived) {
    final gap = perceived - Fx.one;
    final aversion = day.content.demand.lossAversion;
    return gap > Fx.zero && aversion != Fx.one
        ? priceSensitivity * gap * aversion
        : priceSensitivity * gap;
  }

  /// Zero with no queues, down to minus the segment's weight.
  Fx _serviceTerm(Store store) =>
      segment.serviceWeight * (store.service[_slotAt(store)] - Fx.one);

  Fx _hoursPenalty(Store store) => store.staff[cohort.preferredSlot] > 0
      ? Fx.zero
      : day.content.demand.offHoursPenalty;

  /// The slot the cohort shops at [store]: its preferred one if the store is
  /// open then, or else the nearest one it is, later ones first on a tie.
  int _slotAt(Store store) => day.slotFor[store.id.index][cohort.preferredSlot];

  /// The store's location quality plus how close the cohort lives to it.
  Fx _convenience(Store store) =>
      store.location + cohort.proximity[store.site.index];

  /// Picks a store with probability proportional to `exp(utility)`.
  Store _choose(List<Store> open) {
    final utilities = [for (final store in open) _utility(store)];
    final best = utilities.reduce((a, b) => a > b ? a : b);
    final weights = [for (final u in utilities) expNeg(best - u).raw];
    var draw = rng.nextInt(weights.fold(0, (sum, weight) => sum + weight));
    var i = 0;
    while (draw >= weights[i]) {
      draw -= weights[i++];
    }
    return open[i];
  }

  /// Records a trip away from the habitual store of the format, the one of
  /// [rivals] the cohort is most loyal to beyond neutral, with the reason
  /// that weighed most.
  void _recordSwitch(Store chosen, List<Store> rivals) {
    Store? habitual;
    var strongest = day.content.demand.neutralLoyalty;
    for (final store in rivals) {
      final loyalty = cohort.loyalty[store.id.index];
      if (loyalty > strongest) {
        habitual = store;
        strongest = loyalty;
      }
    }
    if (habitual == null || habitual == chosen) return;
    _attribution.addSwitch((
      from: habitual.id,
      to: chosen.id,
      cause: _switchCause(habitual, chosen),
    ), cohort.weight);
  }

  SwitchCause _switchCause(Store habitual, Store chosen) {
    if (!stores.contains(habitual) || actualPrices[habitual.id.index] == null) {
      return SwitchCause.closed;
    }
    final perceived = cohort.perceivedPrices;
    var cause = SwitchCause.variety;
    var largest = Fx.zero;
    // The first of the largest gaps, in this order, wins.
    void weigh(SwitchCause candidate, Fx gap) {
      if (gap > largest) {
        cause = candidate;
        largest = gap;
      }
    }

    weigh(
      SwitchCause.price,
      priceSensitivity *
          (perceived[habitual.id.index] - perceived[chosen.id.index]),
    );
    weigh(
      SwitchCause.convenience,
      segment.convenienceWeight *
          (_convenience(chosen) - _convenience(habitual)),
    );
    weigh(SwitchCause.hours, _hoursPenalty(habitual) - _hoursPenalty(chosen));
    weigh(SwitchCause.service, _serviceTerm(chosen) - _serviceTerm(habitual));
    weigh(SwitchCause.size, _sizeTerm(chosen) - _sizeTerm(habitual));
    weigh(
      SwitchCause.marketing,
      _marketingTerm(chosen) - _marketingTerm(habitual),
    );
    weigh(
      SwitchCause.reputation,
      _reputationTerm(chosen) - _reputationTerm(habitual),
    );
    return cause;
  }

  /// Buys the whole units each household needs in [category], for all the
  /// cohort's households, starting at [store].
  void _shopFor(CategoryId category, Store store) {
    final units = cohort.needs[category.index].raw ~/ Fx.scale * cohort.weight;
    if (units == 0) return;
    // Richer households buy more premium.
    var share = segment.premiumShare[category.index] * affluence + premiumShift;
    if (share.isNegative) share = Fx.zero;
    if (share > Fx.one) share = Fx.one;
    final premium = rng.chance(share);
    final wanted = day.productIn(
      category,
      premium ? ProductTier.premium : ProductTier.budget,
    );
    if (wanted == null) return;
    final result = _buy(store, wanted, units);
    _wanted[store.id.index] += units;
    _credit[store.id.index] += result.bought * Fx.scale;
    var met = result.bought;
    if (result.reason case final reason?) {
      met += _respond(store, wanted, units - result.bought, reason);
    }
    cohort.needs[category.index] -= Fx.raw(
      mulDivRound(met, Fx.scale, cohort.weight),
    );
  }

  /// Handles [missing] units of [product] that [store] didn't sell, by the
  /// segment's odds. Returns the units no longer needed. What's too dear is
  /// no easier to pay in a few days, so households don't wait for it: they
  /// take a cheaper tier, never a dearer one, try another store, or go
  /// without.
  int _respond(Store store, ProductId product, int missing, MissReason reason) {
    void miss(
      Store at,
      MissReason why,
      MissResponse response,
      int units, {
      Store? elsewhere,
    }) => _attribution.addMiss((
      store: at.id,
      product: product,
      reason: why,
      response: response,
      elsewhere: elsewhere?.id,
    ), units);

    final tooDear = reason == MissReason.overpriced;
    final unmet = tooDear ? MissResponse.skip : MissResponse.delay;
    switch (_drawResponse()) {
      case MissResponse.substitute:
        final other = day.otherTier(product);
        final bought =
            other == null || (tooDear && !_isCheaper(store, other, product))
            ? 0
            : _buy(store, other, missing).bought;
        _credit[store.id.index] +=
            day.content.demand.substituteCredit.raw * bought;
        miss(store, reason, MissResponse.substitute, bought);
        miss(store, reason, unmet, missing - bought);
        return tooDear ? missing : bought;
      case MissResponse.elsewhere:
        final other = _bestOtherStore(store, product);
        if (other == null) {
          miss(store, reason, unmet, missing);
          return tooDear ? missing : 0;
        }
        miss(store, reason, MissResponse.elsewhere, missing, elsewhere: other);
        final there = _buy(other, product, missing);
        _wanted[other.id.index] += missing;
        _credit[other.id.index] += there.bought * Fx.scale;
        if (there.reason case final why?) {
          // Too dear at both, they go without; else they may yet find it.
          final givesUp = tooDear && why == MissReason.overpriced;
          miss(
            other,
            why,
            givesUp ? MissResponse.skip : MissResponse.delay,
            missing - there.bought,
          );
          if (givesUp) return missing;
        }
        return there.bought;
      case MissResponse.delay:
        miss(store, reason, unmet, missing);
        return tooDear ? missing : 0;
      case MissResponse.skip:
        miss(store, reason, MissResponse.skip, missing);
        return missing;
    }
  }

  /// Whether [store] sells [other] for less than [product], which it lists.
  bool _isCheaper(Store store, ProductId other, ProductId product) {
    final price = store.prices[other.index];
    return price != null && price < store.prices[product.index]!;
  }

  MissResponse _drawResponse() {
    final odds = segment.missResponses;
    var draw = rng.nextFx();
    var i = 0;
    while (draw >= odds[i]) {
      draw -= odds[i++];
    }
    return MissResponse.values[i];
  }

  /// The store the cohort likes best, other than [store], among those that
  /// list [product].
  Store? _bestOtherStore(Store store, ProductId product) {
    Store? best;
    var bestUtility = Fx.zero;
    for (final other in stores) {
      if (other == store || other.prices[product.index] == null) continue;
      final utility = _utility(other);
      if (best == null || utility > bestUtility) {
        best = other;
        bestUtility = utility;
      }
    }
    return best;
  }

  /// Tries to buy [units] of [product] at [store]. Returns the units bought
  /// and, if fewer than wanted, why.
  ({int bought, MissReason? reason}) _buy(
    Store store,
    ProductId product,
    int units,
  ) {
    final price = store.prices[product.index];
    if (price == null) return (bought: 0, reason: MissReason.notListed);
    if (store.stock[product.index].units == 0) {
      return (bought: 0, reason: MissReason.outOfStock);
    }
    if (!_accepts(price, day.content.products[product.index])) {
      return (bought: 0, reason: MissReason.overpriced);
    }
    final bought = sellUnits(
      day.world,
      day.context.ledger,
      store,
      product,
      units,
    );
    return (
      bought: bought,
      reason: bought < units ? MissReason.outOfStock : null,
    );
  }

  /// Whether the cohort accepts [price] for [product]. Within the segment's
  /// tolerance of the reference price it always does; beyond it, the chance
  /// falls off exponentially with the excess.
  bool _accepts(Money price, ProductDef product) {
    final reference = _references[product.id.index];
    final ratio = Fx.raw(mulDivRound(price.cents, Fx.scale, reference.cents));
    final excess = ratio - Fx.one - priceTolerance;
    return excess <= Fx.zero || rng.chance(expNeg(priceSensitivity * excess));
  }

  /// Each of [rivals], the format's stores, visited counts one visit in the
  /// slot it was visited. Prices at the stores visited are now known
  /// exactly. Loyalty moves toward each visited store's fill score, and
  /// fades toward neutral for the others, closed ones included.
  void _learn(List<Store> rivals) {
    final tuning = day.content.demand;
    for (final store in rivals) {
      final i = store.id.index;
      final loyalty = cohort.loyalty[i];
      if (_wanted[i] == 0) {
        cohort.loyalty[i] =
            loyalty + tuning.loyaltyDecay * (tuning.neutralLoyalty - loyalty);
        continue;
      }
      store.traffic[_slotAt(store)] += cohort.weight;
      cohort.perceivedPrices[i] = actualPrices[i]!;
      final fill = Fx.raw(mulDivRound(_credit[i], 1, _wanted[i]));
      cohort.loyalty[i] = loyalty + tuning.loyaltyRate * (fill - loyalty);
      _wanted[i] = 0;
      _credit[i] = 0;
    }
  }
}
