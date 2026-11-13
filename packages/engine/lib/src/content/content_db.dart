import '../core/calendar.dart';
import '../countries/country_table.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';

/// Everything a scenario defines, loaded once and never changed: the
/// definitions the simulation runs on, and the initial world.
final class ContentDb {
  ContentDb({
    required this.scenarioId,
    required this.fingerprint,
    required this.structure,
    required this.markets,
    required this.sites,
    required this.categories,
    required this.formats,
    required this.products,
    required this.segments,
    required this.demand,
    required this.suppliers,
    required this.macro,
    required this.operations,
    required this.researchTiers,
    required this.managers,
    required this.expansion,
    required this.finance,
    this.taxes,
    this.acquisitions,
    this.buyingTerms,
    this.directors,
    this.factories,
    required this.strategies,
    required this.startDay,
    required this.persons,
    required this.companies,
    required this.stores,
    this.neighbourhoods = const [],
    this.countries = const [CountryDef.only],
    this.national,
    this.source = '',
  });

  /// The countries' national statistics, run by formula beside the game for
  /// the national view (see `Simulation.national`); null for none.
  final CountryTable? national;

  final String scenarioId;

  /// The countries places are in, at least one: a scenario that names none
  /// has one, with the scenario's taxes.
  final List<CountryDef> countries;

  /// [country]'s taxes: its own, or else the scenario's.
  TaxDef? taxesOf(CountryId country) => countries[country.index].taxes ?? taxes;

  /// The country [market] is in.
  CountryId countryOf(MarketId market) => markets[market.index].country;

  /// What goods cost wholesale in each country against the first, by
  /// [CountryId]: see [countryCostLevels].
  late final List<Fx> costLevels = countryCostLevels(
    products,
    suppliers,
    countries,
  );

  /// [costLevels] for [country].
  Fx costLevel(CountryId country) => costLevels[country.index];

  /// What households in each country think each product should cost, at a
  /// price index and a place's level of one, by [CountryId] then
  /// [ProductId]: see [countryReferences].
  late final List<List<Money>> references = countryReferences(
    products,
    countries,
    costLevels,
  );

  /// What households in [country] think [product] should cost, at a price
  /// index and a place's level of one.
  Money referenceIn(ProductDef product, CountryId country) =>
      references[country.index][product.id.index];

  /// Where [person] lives and pays tax on dividends, as the scenario has it:
  /// where it says, or else where the first of the scenario's stores that is
  /// theirs trades, or else the first country. A game's start may move the
  /// player (see `WorldState.residence`).
  CountryId residenceOf(PersonId person) {
    if (persons[person.index].country case final country?) return country;
    for (final store in stores) {
      if (companies[store.company.index].owner == person) {
        return countryOf(sites[store.site.index].market);
      }
    }
    return const CountryId(0);
  }

  /// Neighbourhoods not simulated until the player trades there: only their
  /// figures, from which they are generated (see `Simulation.submit`).
  final List<NeighbourhoodRow> neighbourhoods;

  /// The JSON this was loaded from, for growing it.
  final String source;

  /// A hash of the scenario's canonical JSON. A save only loads with the
  /// content it was made with, since IDs are positions in these lists.
  final int fingerprint;

  /// The IDs in every list, in order: what a save's world depends on. Saves
  /// carry it, and load into content whose numbers changed, or whose lists
  /// only grew at the end (see [ListGrowth]).
  final List<ContentList> structure;

  // Definitions.
  final List<MarketDef> markets;
  final List<SiteDef> sites;
  final List<CategoryDef> categories;

  /// The kinds of business a site can host.
  final List<FormatDef> formats;
  final List<ProductDef> products;

  /// Each format's channel, indexed by [FormatId]: formats that sell any
  /// category in common share one and compete for the same trips, as a
  /// convenience store and a supermarket do for groceries, while a trip to
  /// a fast food is a trip of its own. Channels are numbered in the order of
  /// their first format.
  late final List<int> formatChannels = _channels();

  /// The categories each channel sells, indexed by channel.
  late final List<List<CategoryId>> channelCategories = [
    for (var channel = 0; channel < channelCount; channel++)
      [
        for (final category in categories)
          if (formats.any(
            (format) =>
                formatChannels[format.id.index] == channel &&
                format.sells[category.id.index],
          ))
            category.id,
      ],
  ];

  int get channelCount =>
      formatChannels.fold(0, (most, c) => c >= most ? c + 1 : most);

  /// Each category's channel, indexed by [CategoryId]; a category no format
  /// sells has none, and counts as the first.
  late final List<int> categoryChannels = List.unmodifiable([
    for (final category in categories)
      () {
        for (final format in formats) {
          if (format.sells[category.id.index]) {
            return formatChannels[format.id.index];
          }
        }
        return 0;
      }(),
  ]);

  List<int> _channels() => formatChannelsOf(formats, categories.length);

  final List<SegmentDef> segments;
  final DemandTuning demand;
  final List<SupplierDef> suppliers;
  final MacroDef macro;
  final OperationsDef operations;
  final List<ResearchTierDef> researchTiers;
  final ManagersDef managers;
  final ExpansionDef expansion;
  final FinanceDef finance;

  /// Corporate and dividend taxes where a country has none of its own; null
  /// for none.
  final TaxDef? taxes;

  /// How stores and companies are priced for sale; null if none are ever
  /// sold.
  final AcquisitionDef? acquisitions;

  /// How a company's goods get cheaper the more it buys; null for none.
  final BuyingTermsDef? buyingTerms;

  /// Directors for hire; null if companies can't have one.
  final DirectorsDef? directors;

  /// Factories companies may build; null if they can't.
  final FactoriesDef? factories;
  final List<StrategyDef> strategies;

  // Initial world.
  final Day startDay;
  final List<PersonSetup> persons;

  /// The one person the player controls.
  PersonId get player => PersonId(persons.indexWhere((p) => p.isPlayer));

  final List<CompanySetup> companies;
  final List<StoreSetup> stores;
}

/// The figures a neighbourhood is generated from: who lives there and what
/// things cost. Sites, shops and owners all follow from these and a seed.
final class NeighbourhoodRow {
  const NeighbourhoodRow({
    required this.key,
    required this.name,
    required this.households,
    required this.growth,
    required this.priceLevel,
    required this.wageLevel,
    required this.incomeLevel,
    required this.rent,
    required this.typicalArea,
    required this.largestArea,
    required this.room,
    this.playerStartsHere = false,
    this.layout,
    this.scale = const [],
    this.country = const CountryId(0),
  });

  final String key;
  final String name;

  /// The country it is in.
  final CountryId country;

  /// The place's own market, sites and stores, as a scenario writes them,
  /// for a city of the game's run by formula: see `withCitiesAsleep`. Null
  /// for a place generated from its figures.
  final Map<String, Object?>? layout;

  /// Households, and their yearly growth, indexed by segment.
  final List<int> households;
  final List<Fx> growth;

  /// As [MarketDef.scale]: what households here buy of each channel against
  /// their segments' habits.
  final List<Fx> scale;

  /// [scale] for [channel].
  Fx scaleOf(int channel) => channel < scale.length ? scale[channel] : Fx.one;

  final Fx priceLevel;
  final Fx wageLevel;
  final Fx incomeLevel;

  /// A month's rent per m² of a grocer's site at a location of 0.5.
  final Money rent;

  /// A grocer's usual selling area, in m².
  final int typicalArea;

  /// The biggest grocer's site, in m²: where there's space for a supermarket.
  final int largestArea;

  /// How many m² a grocer's site can grow by.
  final int room;

  /// Whether the player's first store is here.
  final bool playerStartsHere;

  int get totalHouseholds => households.fold(0, (sum, count) => sum + count);
}

/// Each format's channel, indexed by [FormatId], as [ContentDb.formatChannels]
/// has them.
List<int> formatChannelsOf(List<FormatDef> formats, int categoryCount) {
  final channel = List.filled(formats.length, -1);
  var next = 0;
  for (final format in formats) {
    if (channel[format.id.index] >= 0) continue;
    // Every format reachable through shared categories joins it.
    final queue = [format];
    channel[format.id.index] = next;
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final other in formats) {
        if (channel[other.id.index] >= 0) continue;
        final shared = [
          for (var c = 0; c < categoryCount; c++)
            current.sells[c] && other.sells[c],
        ].any((both) => both);
        if (shared) {
          channel[other.id.index] = next;
          queue.add(other);
        }
      }
    }
    next++;
  }
  return List.unmodifiable(channel);
}

/// What goods cost wholesale in each country against the first, by
/// [CountryId]: over the products sold in both, the average of the lowest
/// price factor of its suppliers over the lowest of the first country's. One
/// for the first country, and for one with no suppliers of its own.
List<Fx> countryCostLevels(
  List<ProductDef> products,
  List<SupplierDef> suppliers,
  List<CountryDef> countries,
) {
  Fx? cheapest(CountryId where, ProductId product) {
    Fx? best;
    for (final supplier in suppliers) {
      if (supplier.country != where || !supplier.carries[product.index]) {
        continue;
      }
      if (best == null || supplier.priceFactor < best) {
        best = supplier.priceFactor;
      }
    }
    return best;
  }

  return [
    for (final country in countries)
      () {
        if (country.id.index == 0) return Fx.one;
        var sum = Fx.zero;
        var counted = 0;
        for (final product in products) {
          final here = cheapest(country.id, product.id);
          final first = cheapest(const CountryId(0), product.id);
          if (here == null || first == null) continue;
          sum += here.div(first);
          counted++;
        }
        return counted == 0 ? Fx.one : Fx.raw(mulDivRound(sum.raw, 1, counted));
      }(),
  ];
}

/// What households in each country think each product should cost, at a
/// price index and a place's level of one, by [CountryId] then [ProductId]:
/// its goods at the country's wholesale prices ([costLevels]), and what a
/// shop adds over them, its reference price beyond its base cost, at the
/// country's [CountryDef.service]. A shop's work is paid at local wages, so
/// where they are low a restaurant's meal, mostly work, is cheaper still
/// than a grocer's milk. The first country's are the products' own.
List<List<Money>> countryReferences(
  List<ProductDef> products,
  List<CountryDef> countries,
  List<Fx> costLevels,
) => [
  for (final country in countries)
    List.unmodifiable([
      for (final product in products)
        country.service == Fx.one && costLevels[country.id.index] == Fx.one
            ? product.referencePrice
            : product.baseCost.times(costLevels[country.id.index]) +
                  (product.referencePrice - product.baseCost).times(
                    country.service,
                  ),
    ]),
];

final class MarketDef {
  const MarketDef({
    required this.id,
    required this.key,
    required this.name,
    required this.households,
    required this.growth,
    this.agents,
    this.priceLevel = Fx.one,
    this.wageLevel = Fx.one,
    this.incomeLevel = Fx.one,
    this.scale = const [],
    this.country = const CountryId(0),
  });

  final MarketId id;
  final String key;
  final String name;

  /// The country it is in, whose economy, suppliers and taxes it has.
  final CountryId country;

  /// How many households of each segment live here at the start, indexed by
  /// [SegmentId]. A scenario gives a place its market in euros and the mix of
  /// who lives there, and these follow from them (see [placeSize]).
  final List<int> households;

  /// What households here buy of each channel's goods against what their
  /// segments' habits say, indexed by channel: what makes the market the
  /// scenario gave. Missing channels are one.
  final List<Fx> scale;

  /// [scale] for [channel].
  Fx scaleOf(int channel) => channel < scale.length ? scale[channel] : Fx.one;

  /// Each segment's yearly population growth before migration, which can be
  /// negative, indexed by [SegmentId].
  final List<Fx> growth;

  /// How many cohorts simulate the market's households, each standing for
  /// several; null for one cohort per household.
  final int? agents;

  /// How dear the market is: reference prices, what households here think
  /// normal, are this times the products' and the price index. Wholesale
  /// prices are its country's suppliers'.
  final Fx priceLevel;

  /// Staff and managers here are paid this times the usual, at the wage
  /// index.
  final Fx wageLevel;

  /// Households here are this much better off than the segment's average:
  /// it scales their affluence, as relative income does.
  final Fx incomeLevel;
}

/// A place in a market where a store can trade. A liquidated or closed
/// store frees its site for anyone to open a new store there.
final class SiteDef {
  const SiteDef({
    required this.id,
    required this.key,
    required this.name,
    required this.market,
    required this.location,
    required this.rent,
    required this.shelfSlots,
    required this.storageUnits,
    required this.openingCost,
    required this.buildDays,
    required this.area,
    required this.maxArea,
  });

  final SiteId id;
  final String key;
  final String name;
  final MarketId market;

  /// How convenient the site is, from 0 to 1.
  final Fx location;

  /// Rent per month, due on the first of the month.
  final Money rent;

  /// How many different products a store here can list.
  final int shelfSlots;

  /// How many units of stock fit, all products together.
  final int storageUnits;

  /// What fitting out a new store here costs, paid when it is opened.
  final Money openingCost;

  /// Days between opening a store here and its first trading day.
  final int buildDays;

  /// A new store's selling area, in square metres. [rent], [shelfSlots] and
  /// [storageUnits] are for this area.
  final int area;

  /// The most a store here can be enlarged to.
  final int maxArea;

  /// The monthly rent for [area] square metres here, at a price index of 1:
  /// in proportion to the site's rent for its own area.
  Money rentFor(int area) => Money(mulDivRound(rent.cents, area, this.area));
}

/// How stores grow: one step of floor area at a time.
final class ExpansionDef {
  const ExpansionDef({
    required this.stepArea,
    required this.shelfSlots,
    required this.storageUnits,
    required this.costPerSqm,
    required this.buildDays,
  });

  /// Square metres added by one enlargement.
  final int stepArea;

  /// Shelf slots and storage one enlargement adds.
  final int shelfSlots;
  final int storageUnits;

  /// Building cost per square metre, at a price index of 1.
  final Money costPerSqm;

  /// Days of works before the new space is in use. The store keeps trading.
  final int buildDays;

  /// What one enlargement costs at [priceLevel].
  Money cost(Fx priceLevel) => costPerSqm.timesInt(stepArea).times(priceLevel);
}

/// The labour market. Unemployment follows the output gap by Okun's law
/// (A. M. Okun, "Potential GNP: its measurement and significance", 1962):
/// it drifts each month [adjustment] of the way toward the natural rate less
/// the gap over [okunCoefficient]. Wage growth falls by [phillipsSlope] times
/// unemployment above its natural rate, the wage Phillips curve
/// (A. W. Phillips, "The relation between unemployment and the rate of change
/// of money wage rates", Economica 25, 1958; O. Blanchard and L. Katz, "Wage
/// dynamics", American Economic Review 82(2), 1992). Households spend
/// [confidence] times less for each point of unemployment above natural:
/// joblessness and the fear of it weigh on spending.
final class LabourDef {
  const LabourDef({
    required this.naturalUnemployment,
    required this.okunCoefficient,
    required this.adjustment,
    required this.phillipsSlope,
    required this.confidence,
  });

  final Fx naturalUnemployment;
  final Fx okunCoefficient;
  final Fx adjustment;
  final Fx phillipsSlope;
  final Fx confidence;

  /// Where unemployment heads with an [outputGap], at least 1%.
  Fx unemploymentTarget(Fx outputGap) {
    final target = naturalUnemployment - outputGap.div(okunCoefficient);
    final floor = Fx.parse('0.01');
    return target < floor ? floor : target;
  }

  /// What households spend against normal at [unemployment], at least half.
  Fx confidenceFactor(Fx unemployment) {
    final factor = Fx.one - confidence * (unemployment - naturalUnemployment);
    final floor = Fx.parse('0.5');
    return factor < floor ? floor : factor;
  }
}

/// Corporate tax on a year's profit, with a reduced rate on the first part
/// as for French small companies (15% up to 42,500, then 25%), losses carried
/// forward; and a flat tax on dividends paid to owners (30%, the French
/// prélèvement forfaitaire unique).
final class TaxDef {
  const TaxDef({
    required this.reducedRate,
    required this.reducedLimit,
    required this.corporateRate,
    required this.dividendRate,
  });

  final Fx reducedRate;

  /// The profit taxed at [reducedRate], at a price index of 1.
  final Money reducedLimit;
  final Fx corporateRate;
  final Fx dividendRate;

  /// The tax on a year's [profit], once losses are set against it, at
  /// [priceIndex].
  Money corporateTax(Money profit, Fx priceIndex) {
    if (profit <= Money.zero) return Money.zero;
    final limit = reducedLimit.times(priceIndex);
    if (profit <= limit) return profit.times(reducedRate);
    return limit.times(reducedRate) + (profit - limit).times(corporateRate);
  }
}

/// A country: its taxes, how its economy takes the business cycle it shares
/// with the others on its currency, its weight in its central bank's
/// averages, and what it calls the people, streets and shops generated in it.
final class CountryDef {
  const CountryDef({
    required this.id,
    required this.key,
    required this.name,
    this.taxes,
    this.follows = Fx.one,
    this.depth = Fx.one,
    this.weight = Fx.one,
    this.service = Fx.one,
    this.names,
    this.national,
  });

  /// The one country of a scenario that names none.
  static const only = CountryDef(id: CountryId(0), key: '', name: '');

  final CountryId id;
  final String key;
  final String name;

  /// Its own taxes; null for the scenario's.
  final TaxDef? taxes;

  /// The chance that it follows each turn of the shared cycle into the next
  /// regime, from 0 to 1. Below one it may also turn on its own, as often as
  /// it doesn't follow, so a country that never follows has a cycle of its
  /// own with the same mean durations.
  final Fx follows;

  /// How far its economy swings with the cycle against the usual: each
  /// regime's demand, trading down and output gap are this far from neutral.
  final Fx depth;

  /// How much it counts in its central bank's average inflation and output
  /// gap: the size of its economy, in any unit shared by its currency's
  /// countries.
  final Fx weight;

  /// What generated people, streets and shops are called here; null for the
  /// engine's own lists.
  final PlaceNames? names;

  /// Its country in the national table, for the national view; null for
  /// none.
  final String? national;

  /// What a shop's work costs here against the first country: its staff's
  /// wages, which the part of a shelf price beyond the goods follows (see
  /// [countryReferences]).
  final Fx service;

  /// [regime]'s multiplier on what households here consume.
  Fx demandIn(RegimeDef regime) => depth == Fx.one
      ? regime.demand
      : Fx.one + (regime.demand - Fx.one) * depth;

  /// [regime]'s shift of every segment's premium share here.
  Fx premiumShiftIn(RegimeDef regime) =>
      depth == Fx.one ? regime.premiumShift : regime.premiumShift * depth;

  /// [regime]'s output gap here.
  Fx outputGapIn(RegimeDef regime) =>
      depth == Fx.one ? regime.outputGap : regime.outputGap * depth;
}

/// What a country calls what is generated in it. A street is one of
/// [streetKinds] around one of [streets]; a shop, one of its format's words
/// in [shops] and a street's name. A kind or word holding `{}` puts the name
/// there ("{}straße", "{}-Markt"); otherwise the name follows it after a
/// space ("Rue Hugo", "Marché Hugo"). A format without words takes the
/// first format's.
final class PlaceNames {
  const PlaceNames({
    required this.first,
    required this.last,
    required this.streets,
    required this.streetKinds,
    required this.shops,
  });

  final List<String> first;
  final List<String> last;
  final List<String> streets;
  final List<String> streetKinds;

  /// Words for shops, by format key.
  final Map<String, List<String>> shops;

  /// [pattern] around [name].
  static String fill(String pattern, String name) => pattern.contains('{}')
      ? pattern.replaceAll('{}', name)
      : '$pattern $name';

  /// The words for a shop of [format], or the first format's.
  List<String> shopWords(String format) => shops[format] ?? shops.values.first;
}

/// How businesses are priced when they change hands, by the excess earnings
/// method (US Treasury, Revenue Ruling 68-609, 1968; still the standard way
/// of valuing small businesses): a store is worth its fittings and stock,
/// plus whatever its earnings beat a fair return on them by, capitalised at
/// a rate that prices in a small business's risk. A store earning less than
/// that return sells below what it holds, down to a distress floor.
/// Buying terms: what a company's suppliers take off its goods, by what it
/// bought over its last twelve months, V: [most] × V / (V + [half]), so
/// half the most at [half] a year.
final class BuyingTermsDef {
  const BuyingTermsDef({required this.most, required this.half});

  final Fx most;
  final Money half;
}

final class AcquisitionDef {
  const AcquisitionDef({
    required this.tangibleReturn,
    required this.capitalization,
    required this.distressFloor,
    required this.fittingsLifeDays,
    required this.fittingsResidual,
    required this.buyerReserve,
    required this.intervalDays,
  });

  /// The yearly return fittings and stock should earn.
  final Fx tangibleReturn;

  /// What a year's earnings beyond that return are divided by: 0.33 prices
  /// them at three years'.
  final Fx capitalization;

  /// The least share of its fittings and stock a store sells for.
  final Fx distressFloor;

  /// Days over which fittings wear down to [fittingsResidual] of their cost.
  final int fittingsLifeDays;
  final Fx fittingsResidual;

  /// The cash an AI buyer keeps beyond the price, as a share of it.
  final Fx buyerReserve;

  /// The least days between an AI owner's purchases or openings.
  final int intervalDays;
}

/// The bank's terms and the rules of insolvency.
final class FinanceDef {
  const FinanceDef({
    required this.bankReserves,
    required this.bankMargin,
    required this.guaranteedSpread,
    required this.unsecuredSpread,
    required this.bankruptcySpread,
    required this.reputationDays,
    required this.maxTermMonths,
    required this.guaranteeMultiple,
    required this.earningsMultiple,
    required this.graceDays,
  });

  /// The bank's opening cash, the most it can ever have lent out.
  final Money bankReserves;

  /// Added to the policy rate for every loan.
  final Fx bankMargin;

  /// Added to the base rate for loans the owner personally guarantees.
  final Fx guaranteedSpread;

  /// Added to the base rate for loans without a guarantee.
  final Fx unsecuredSpread;

  /// Added for owners who went bankrupt within [reputationDays].
  final Fx bankruptcySpread;
  final int reputationDays;
  final int maxTermMonths;

  /// A person may guarantee loans up to this multiple of their personal cash.
  final Fx guaranteeMultiple;

  /// Unguaranteed debt may reach this multiple of a year's earnings of the
  /// company's stores, counted as a buyer would (see `storeEarnings`).
  final Fx earningsMultiple;

  /// Days a bill may stay overdue before the company is liquidated.
  final int graceDays;
}

final class CategoryDef {
  const CategoryDef({
    required this.id,
    required this.key,
    required this.name,
    this.diffusion,
  });

  final CategoryId id;
  final String key;
  final String name;

  /// How the category spreads among households, if it is still new; null
  /// for one everybody already buys.
  final Diffusion? diffusion;
}

/// The Bass model of how a new product spreads (F. Bass, "A new product
/// growth for model consumer durables", Management Science 15(5), 1969):
/// households adopt it on their own at rate [innovation] and by imitating
/// those who have at rate [imitation], so the share that has adopted, `t`
/// years after [launched], is
///
///     F(t) = (1 − e^{−(p+q)t}) / (1 + (q/p)·e^{−(p+q)t})
///
/// an S-curve from slow beginnings through fast growth to saturation.
final class Diffusion {
  const Diffusion({
    required this.innovation,
    required this.imitation,
    required this.launched,
  });

  /// p, a year.
  final Fx innovation;

  /// q, a year.
  final Fx imitation;
  final Day launched;

  /// The share of households that buy the category on [day].
  Fx adoption(Day day) {
    final days = day.number - launched.number;
    if (days <= 0) return Fx.zero;
    final rate = innovation + imitation;
    final decay = expNeg(Fx.raw(mulDivRound(rate.raw, days, 365)));
    return (Fx.one - decay).div(Fx.one + imitation.div(innovation) * decay);
  }
}

/// A kind of business a site can host: what it sells, what fitting it out
/// costs, and how many customers one member of staff serves.
final class FormatDef {
  const FormatDef({
    required this.id,
    required this.key,
    required this.name,
    required this.sells,
    required this.fitOut,
    required this.visitsPerStaff,
    this.wageFactor = Fx.one,
    this.minArea = 0,
    this.slotBonus = 0,
    this.storageBonus = 0,
    this.overheads = Money.zero,
    this.national,
  });

  final FormatId id;
  final String key;
  final String name;

  /// Whether it sells each category, indexed by [CategoryId].
  final List<bool> sells;

  /// Fitting out costs the site's opening cost times this.
  final Fx fitOut;

  /// Customers one member of staff serves in a slot before queues form.
  final int visitsPerStaff;

  /// What a member of staff costs against a shop assistant: a restaurant's
  /// crew, kitchen and floor, costs more.
  final Fx wageFactor;

  /// The least selling area it trades in: a store converted to it is
  /// enlarged to this, and it can't open on a smaller site.
  final int minArea;

  /// Shelf slots and storage a store gains on becoming this format, beyond
  /// what its area adds.
  final int slotBonus;
  final int storageBonus;

  /// Energy, insurance, upkeep and card fees per square metre a month, at a
  /// price index of 1: what a store pays however much it sells.
  final Money overheads;

  /// The month's overheads for [area] square metres, at a price index of 1.
  Money overheadsFor(int area) => overheads.timesInt(area);

  /// What its shops run by formula across a country are sized on; null if
  /// it has none.
  final FormatNational? national;
}

/// A format's shops run by formula across a country: what fitting one out
/// costs, and what a settled one sells a year, country by country, both at
/// a price index of one. They are measured on the districts run by formula,
/// so that a shop earns about the same run by hand or by formula there (see
/// `tool/national_shops.dart`).
final class FormatNational {
  const FormatNational({
    required this.fitOut,
    required this.sales,
    required this.staff,
    required this.premises,
  });

  final Money fitOut;

  /// By [CountryId].
  final List<Money> sales;

  /// What a settled shop's staff and premises cost as shares of its sales,
  /// by [CountryId].
  final List<Fx> staff;
  final List<Fx> premises;

  Money salesIn(CountryId country) => sales[country.index];
  Fx staffIn(CountryId country) => staff[country.index];
  Fx premisesIn(CountryId country) => premises[country.index];
}

enum ProductTier { budget, premium }

final class ProductDef {
  const ProductDef({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.tier,
    required this.shelfLifeDays,
    required this.baseCost,
    required this.referencePrice,
  });

  final ProductId id;
  final String key;
  final String name;
  final CategoryId category;
  final ProductTier tier;

  /// Days before a delivered lot expires, or null for non-perishables.
  final int? shelfLifeDays;

  /// Reference wholesale cost before supplier margins and inflation.
  final Money baseCost;

  /// The shelf price households consider normal. Prices well above it make
  /// shoppers walk away from the item.
  final Money referencePrice;
}

/// A kind of household: how much it consumes, what it prefers, and how it
/// weighs price against convenience and habit.
final class SegmentDef {
  const SegmentDef({
    required this.id,
    required this.key,
    required this.name,
    required this.tripIntervalDays,
    required this.priceSensitivity,
    required this.convenienceWeight,
    required this.loyaltyWeight,
    required this.priceTolerance,
    required this.wordOfMouth,
    required this.missResponses,
    required this.dailyUnits,
    required this.premiumShare,
    required this.slotShares,
    required this.serviceWeight,
    required this.sizeWeight,
    required this.incomeSpread,
  });

  final SegmentId id;
  final String key;
  final String name;

  /// Days between shopping trips.
  final int tripIntervalDays;

  /// Utility lost per unit of relative price difference: at 8, a store
  /// believed 10% dearer loses 0.8. Also how fast overpriced items lose
  /// buyers beyond [priceTolerance].
  final Fx priceSensitivity;

  /// Utility per unit of store location quality.
  final Fx convenienceWeight;

  /// Utility per unit of loyalty, which runs from 0 to 1.
  final Fx loyaltyWeight;

  /// How far above its reference price an item can be priced before
  /// shoppers start refusing it: 0.10 is 10%.
  final Fx priceTolerance;

  /// The share of the gap between believed and actual store prices that
  /// closes each day without a visit.
  final Fx wordOfMouth;

  /// Odds of each response when a wanted item is missing or overpriced,
  /// indexed by [MissResponse]. They sum to one.
  final List<Fx> missResponses;

  /// Units consumed per household per day, indexed by [CategoryId].
  final List<Fx> dailyUnits;

  /// The chance of wanting the premium tier, indexed by [CategoryId].
  final List<Fx> premiumShare;

  /// The share of households that prefer to shop in each slot, indexed by
  /// [DaySlot]. They sum to one.
  final List<Fx> slotShares;

  /// Utility per unit of service: a store whose queues halve its service
  /// loses half this.
  final Fx serviceWeight;

  /// How much bigger stores draw the segment: utility gained from a store's
  /// size, up to this weight for a store of infinite area.
  final Fx sizeWeight;

  /// How far a household's income can be from the segment's average, either
  /// way, as a share of it: households spread evenly between one less and
  /// one plus this.
  final Fx incomeSpread;

  /// The income, against the segment's average, of a household at [rank]
  /// from 0 (poorest) to 1 (richest).
  Fx relativeIncome(Fx rank) =>
      Fx.one + incomeSpread * (rank.timesInt(2) - Fx.one);

  /// How expensive a shelf with [prices] (indexed by [ProductId]) is for
  /// this segment: its usual basket at those prices over the same basket at
  /// reference prices times [priceLevel], counting listed products only.
  /// The reference prices are [references], a country's, if given.
  /// Null if nothing is listed.
  Fx? priceIndex(
    List<ProductDef> products,
    List<Money?> prices, {
    Fx priceLevel = Fx.one,
    List<Money>? references,
  }) {
    var listed = false;
    var atShelf = 0;
    var atReference = 0;
    for (final product in products) {
      final price = prices[product.id.index];
      if (price == null) continue;
      listed = true;
      final share = premiumShare[product.category.index];
      final tierShare = product.tier == ProductTier.premium
          ? share
          : Fx.one - share;
      final weight = (dailyUnits[product.category.index] * tierShare).raw;
      atShelf = checkedSafe(atShelf + checkedSafe(price.cents * weight));
      atReference = checkedSafe(
        atReference +
            checkedSafe(
              (references?[product.id.index] ?? product.referencePrice).cents *
                  weight,
            ),
      );
    }
    if (!listed) return null;
    final reference = mulDivRound(atReference, priceLevel.raw, Fx.scale);
    if (reference <= 0) return Fx.one;
    return Fx.raw(mulDivRound(atShelf, Fx.scale, reference));
  }

  /// Whether households of the segment buy [category] less often than
  /// [DemandTuning.maxNeedDays] apart, so their need is floored at a unit.
  bool buysRarely(CategoryId category, DemandTuning demand) {
    final daily = dailyUnits[category.index];
    return daily > Fx.zero && daily.timesInt(demand.maxNeedDays) < Fx.one;
  }
}

/// The parts of the day a store can open. Append only.
enum DaySlot { morning, midday, evening, night }

/// What shoppers do about a wanted item that is missing or overpriced.
/// Append only: the order is part of the content format.
enum MissResponse {
  /// Buy the other tier of the same category in the same store.
  substitute,

  /// Go to the best other store that lists the item.
  elsewhere,

  /// Keep the need and buy on a later trip.
  delay,

  /// Drop the need.
  skip,
}

/// Demand constants shared by all segments.
final class DemandTuning {
  const DemandTuning({
    required this.neutralLoyalty,
    required this.loyaltyRate,
    required this.loyaltyDecay,
    required this.substituteCredit,
    required this.maxNeedDays,
    required this.offHoursPenalty,
    required this.halfSizeArea,
    required this.incomeEffect,
    this.marketingWeight = Fx.zero,
    this.halfGoodwill = const Money(100000),
    this.goodwillDecay = const Fx.raw(300),
    this.lossAversion = Fx.one,
    this.reputationWeight = Fx.zero,
    this.reputationDays = 365,
    this.establishedReputation = Fx.zero,
    this.openingReputation = Fx.zero,
  });

  /// Loyalty without any history: where every cohort starts, and where
  /// loyalty to stores it stops visiting drifts back to.
  final Fx neutralLoyalty;

  /// The share of the gap between loyalty and a visit's fill score that
  /// closes on each visit.
  final Fx loyaltyRate;

  /// The share of the gap between loyalty and [neutralLoyalty] that closes
  /// on each trip that skips the store.
  final Fx loyaltyDecay;

  /// How much a substituted unit counts toward a visit's fill score, where
  /// a unit bought as wanted counts one.
  final Fx substituteCredit;

  /// Unmet need is capped at this many days of consumption, but never below
  /// one unit, so things bought less often than that still get bought.
  final int maxNeedDays;

  /// Utility lost when a store isn't open in the slot a household prefers,
  /// so it must shop at another time.
  final Fx offHoursPenalty;

  /// The selling area, in square metres, at which a store's size draws half
  /// the pull a segment's size weight allows. Size has diminishing returns:
  /// a store's pull is its area over its area plus this.
  final int halfSizeArea;

  /// How much of the change in real wages reaches households' purchasing
  /// power, from 0 to 1.
  final Fx incomeEffect;

  /// The most a store's marketing adds to its pull, however much it spends.
  final Fx marketingWeight;

  /// Advertising builds goodwill, a stock that wears off (M. Nerlove and
  /// K. J. Arrow, "Optimal advertising policy under dynamic conditions",
  /// Economica 29, 1962): each day a store's goodwill loses [goodwillDecay]
  /// of itself and gains what it spent. Its pull is [marketingWeight] times
  /// goodwill over goodwill plus [halfGoodwill], at a price index of 1.
  final Money halfGoodwill;
  final Fx goodwillDecay;

  /// What a store's reputation adds to its pull at most, everyone knowing
  /// it. Its reputation, from 0 to 1, moves each day 1/[reputationDays] of
  /// the way toward how well it served that day: the share of what
  /// shoppers wanted that it had on its shelves, times how well its staff
  /// kept up. A store a city has known for years starts at
  /// [establishedReputation]; a new one at [openingReputation], and builds
  /// it.
  final Fx reputationWeight;
  final int reputationDays;
  final Fx establishedReputation;
  final Fx openingReputation;

  /// How much more a price above what households expect hurts a store than
  /// one as far below helps it: losses loom larger than gains (D. Kahneman
  /// and A. Tversky, "Prospect theory", Econometrica 47(2), 1979; for prices,
  /// G. Kalyanaram and R. Winer, "Empirical generalizations from reference
  /// price research", Marketing Science 14(3), 1995). One for none.
  final Fx lossAversion;

  /// Households' purchasing power against the start: one plus
  /// [incomeEffect] times the change in real wages, the wage index over the
  /// price index. Richer households care less about price, tolerate more
  /// above the reference, and buy more premium.
  Fx purchasingPower(Fx wageIndex, Fx priceIndex) =>
      Fx.one + incomeEffect * (wageIndex.div(priceIndex) - Fx.one);
}

/// The business cycle and the central bank's rule.
///
/// Each month the cycle may move on to the next regime in [regimes], with a
/// chance of one in its mean duration. Inflation is the regime's, nudged by
/// how shelf prices actually moved; the policy rate follows a Taylor rule.
/// The countries of a scenario share the cycle and the central bank, which
/// sets one rate for all (see [CountryDef]).
final class MacroDef {
  const MacroDef({
    required this.startRegime,
    required this.neutralRate,
    required this.inflationTarget,
    required this.inflationResponse,
    required this.gapResponse,
    required this.minRate,
    required this.retailFeedback,
    required this.regimes,
    this.labour,
  });

  final RegimeId startRegime;

  /// The real policy rate when inflation is on target and there is no gap.
  final Fx neutralRate;
  final Fx inflationTarget;

  /// How far the rate moves per unit of inflation above target.
  final Fx inflationResponse;

  /// How far the rate moves per unit of output gap.
  final Fx gapResponse;
  final Fx minRate;

  /// The weight of measured shelf-price inflation in the inflation rate,
  /// against the regime's own.
  final Fx retailFeedback;

  /// The cycle, in order; the last regime is followed by the first.
  final List<RegimeDef> regimes;

  /// The labour market, if unemployment is modelled.
  final LabourDef? labour;

  /// The policy rate for annual [inflation] and an [outputGap].
  Fx policyRate(Fx inflation, Fx outputGap) {
    final rate =
        neutralRate +
        inflationTarget +
        inflationResponse * (inflation - inflationTarget) +
        gapResponse * outputGap;
    return rate < minRate ? minRate : rate;
  }
}

/// One phase of the business cycle.
final class RegimeDef {
  const RegimeDef({
    required this.id,
    required this.key,
    required this.name,
    required this.meanMonths,
    required this.inflation,
    required this.realWageGrowth,
    required this.outputGap,
    required this.demand,
    required this.premiumShift,
    required this.migration,
  });

  final RegimeId id;
  final String key;
  final String name;
  final int meanMonths;

  /// Annual inflation.
  final Fx inflation;

  /// Annual wage growth beyond inflation.
  final Fx realWageGrowth;
  final Fx outputGap;

  /// Multiplier on what households consume.
  final Fx demand;

  /// Added to every segment's premium share: negative when households trade
  /// down.
  final Fx premiumShift;

  /// Yearly population change from people moving in or out during the
  /// regime, added to every segment's growth.
  final Fx migration;
}

/// How stores run: what staff cost and how many shoppers they can serve.
final class OperationsDef {
  const OperationsDef({
    required this.slotWage,
    required this.visitsPerStaff,
    required this.maxStaffPerSlot,
  });

  /// One staff member's pay for one slot of one day, at a wage index of 1.
  final Money slotWage;

  /// Shoppers one staff member serves in a slot before queues form.
  final int visitsPerStaff;
  final int maxStaffPerSlot;
}

/// A grade of market study: dearer ones are more accurate.
final class ResearchTierDef {
  const ResearchTierDef({
    required this.id,
    required this.key,
    required this.name,
    required this.cost,
    required this.error,
  });

  final ResearchTierId id;
  final String key;
  final String name;

  /// The price at a price index of 1.
  final Money cost;

  /// Each estimate is off by up to this share of the true value, either way.
  final Fx error;
}

/// Store managers for hire, and how their skill shows.
final class ManagersDef {
  const ManagersDef({
    required this.forecastError,
    required this.priceError,
    required this.grades,
  });

  /// How far, either way, a manager of no skill misjudges demand: each
  /// product's forecast and each slot's traffic for a week. A manager of
  /// skill s is off by up to (1 − s) times this.
  final Fx forecastError;

  /// How far, either way, a manager of no skill misjudges each product's
  /// right price for a week.
  final Fx priceError;
  final List<ManagerGradeDef> grades;
}

/// A grade of store manager: more skilled ones cost more.
final class ManagerGradeDef {
  const ManagerGradeDef({
    required this.id,
    required this.key,
    required this.name,
    required this.skill,
    required this.salary,
  });

  final ManagerGradeId id;
  final String key;
  final String name;

  /// From 0 to 1: how much of the misjudgment allowed by [ManagersDef] the
  /// manager avoids.
  final Fx skill;

  /// Pay per day at a wage index of 1.
  final Money salary;
}

/// Directors for hire, who run a whole company above its store managers,
/// and how their skill shows.
final class DirectorsDef {
  const DirectorsDef({
    required this.judgmentError,
    required this.coaching,
    required this.grades,
  });

  /// How far, either way, a director of no skill misjudges the margin a new
  /// store, or a rival's store for sale, would earn. A director of skill s
  /// is off by up to (1 − s) times this.
  final Fx judgmentError;

  /// How much of their managers' misjudgment a director of full skill takes
  /// away by checking their forecasts and prices: one of skill s takes away
  /// s times this.
  final Fx coaching;

  /// The share of their misjudgment the managers of a company keep under a
  /// director of [grade]; all of it without a director.
  Fx kept(DirectorGradeId? grade) =>
      grade == null ? Fx.one : Fx.one - coaching * grades[grade.index].skill;
  final List<DirectorGradeDef> grades;
}

/// A grade of director: more skilled ones cost more.
final class DirectorGradeDef {
  const DirectorGradeDef({
    required this.id,
    required this.key,
    required this.name,
    required this.skill,
    required this.salary,
  });

  final DirectorGradeId id;
  final String key;
  final String name;

  /// From 0 to 1: how much of the misjudgment allowed by [DirectorsDef] the
  /// director avoids.
  final Fx skill;

  /// Pay per day at a wage index of 1.
  final Money salary;
}

/// A wholesale supplier. Suppliers are outside the simulation in the
/// prototype: they sell from fixed terms and never run out, each in one
/// country.
final class SupplierDef {
  const SupplierDef({
    required this.id,
    required this.key,
    required this.name,
    required this.leadTimeDays,
    required this.paymentTermsDays,
    required this.priceFactor,
    required this.minOrderUnits,
    required this.volumeDiscounts,
    required this.carries,
    this.country = const CountryId(0),
  });

  final SupplierId id;
  final String key;
  final String name;

  /// The country it delivers in: stores buy only from their own country's.
  final CountryId country;

  /// Days between the order and the delivery.
  final int leadTimeDays;

  /// Days after delivery before the invoice is due; 0 is cash on delivery.
  final int paymentTermsDays;

  /// Multiplier on each product's base cost.
  final Fx priceFactor;

  /// The smallest quantity per order line.
  final int minOrderUnits;

  /// Discounts by line quantity, in increasing order of [VolumeDiscount.minUnits].
  final List<VolumeDiscount> volumeDiscounts;

  /// Whether the supplier sells each product, indexed by [ProductId].
  final List<bool> carries;

  /// The unit price for [quantity] units of [product] at [priceLevel],
  /// rounded to the cent.
  Money unitPrice(ProductDef product, int quantity, Fx priceLevel) {
    var discount = Fx.zero;
    for (final tier in volumeDiscounts) {
      if (quantity >= tier.minUnits) discount = tier.discount;
    }
    return product.baseCost.times(
      priceFactor * (Fx.one - discount) * priceLevel,
    );
  }
}

/// Factories a company can build to make goods its shops used to buy: the
/// first rung of owning the chain.
final class FactoriesDef {
  const FactoriesDef({
    required this.kinds,
    required this.abroadDays,
    required this.freight,
    required this.paymentTermsDays,
    required this.maxShifts,
  });

  final List<FactoryKindDef> kinds;

  /// The days a delivery to another country takes beyond one at home.
  final int abroadDays;

  /// What carrying goods to another country costs, as a share of what they
  /// sell for, for a kind that names no freight of its own.
  final Fx freight;

  /// Days after delivery before a shop pays a factory.
  final int paymentTermsDays;

  /// The most shifts a factory runs.
  final int maxShifts;
}

/// A kind of factory: the category it makes, both lines of it, and what it
/// costs to build and to run.
final class FactoryKindDef {
  const FactoryKindDef({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.buildCost,
    required this.buildDays,
    required this.shiftUnits,
    required this.shiftWage,
    required this.site,
    required this.materials,
    required this.leadTimeDays,
    required this.minOrderUnits,
    required this.freight,
    this.exports = true,
  });

  final FactoryKindId id;
  final String key;
  final String name;

  /// What it makes: every product of the category.
  final CategoryId category;

  /// Building and fitting it, at a price index of one.
  final Money buildCost;
  final int buildDays;

  /// What one shift makes in a day.
  final int shiftUnits;

  /// What one shift's staff are paid a day, at a wage index of one in the
  /// first country, whether or not it has anything to make.
  final Money shiftWage;

  /// The site's rent and running costs a month, at a price index of one,
  /// whatever it makes.
  final Money site;

  /// What making a unit costs in materials, as a share of its base cost.
  final Fx materials;

  /// Days to deliver in its own country.
  final int leadTimeDays;

  /// The smallest quantity per order line.
  final int minOrderUnits;

  /// What carrying its goods to another country costs, as a share of what
  /// they sell for: heavy, cheap goods such as drinks pay more of their
  /// price than light or dear ones.
  final Fx freight;

  /// Whether its goods travel to other countries: bread doesn't.
  final bool exports;
}

final class VolumeDiscount {
  const VolumeDiscount({required this.minUnits, required this.discount});

  final int minUnits;
  final Fx discount;
}

/// How an AI owner, or a strategy bot playing for the player, runs its
/// stores: price stance, stock levels and assortment. The retail policy
/// reads it.
final class StrategyDef {
  const StrategyDef({
    required this.id,
    required this.key,
    required this.name,
    required this.markup,
    required this.minMarkup,
    required this.marketPosition,
    required this.marketWeight,
    required this.maxPriceStep,
    required this.priceReviewDays,
    required this.maxOverpricedShare,
    required this.premiumBias,
    required this.assortmentReviewDays,
    required this.assortmentHysteresis,
    required this.forecastDays,
    required this.openingForecast,
    required this.safetyDays,
    required this.orderCycleDays,
    required this.reserveDays,
    required this.expansionPaybackMonths,
    required this.expansionIntervalDays,
    required this.marginPerHousehold,
    required this.hours,
    required this.serviceTarget,
    required this.openingTraffic,
    this.format = const FormatId(0),
    this.marketingShare = Fx.zero,
  });

  final StrategyId id;
  final String key;
  final String name;

  /// Target markup over unit cost: 0.40 prices at cost × 1.4.
  final Fx markup;

  /// The lowest markup it accepts.
  final Fx minMarkup;

  /// Where it wants its prices relative to competitors' average for the same
  /// product: -0.05 is 5% below.
  final Fx marketPosition;

  /// How far its target price moves from cost-plus toward that market
  /// position, from 0 to 1.
  final Fx marketWeight;

  /// The largest price change per review, as a share of the price.
  final Fx maxPriceStep;

  /// Days between price reviews.
  final int priceReviewDays;

  /// When more than this share of a product's would-be buyers refuse its
  /// price, the next review cuts the price.
  final Fx maxOverpricedShare;

  /// Multiplier on premium products' scores in assortment reviews; above 1
  /// favors premium.
  final Fx premiumBias;

  /// Days between assortment reviews.
  final int assortmentReviewDays;

  /// How much better an unlisted product must score than the weakest listed
  /// one to replace it: 0.25 is 25% better.
  final Fx assortmentHysteresis;

  /// Days of history behind the demand forecast.
  final int forecastDays;

  /// Daily units per product assumed for days without history.
  final Fx openingForecast;

  /// Days of demand held as safety stock beyond the lead time.
  final int safetyDays;

  /// Days of demand each order aims to cover.
  final int orderCycleDays;

  /// Days of average spending kept as cash; profit beyond it is paid to the
  /// owner as dividends each month.
  final int reserveDays;

  /// Opens a store at a vacant site when its estimated profit would repay
  /// the opening cost within this many months; 0 never expands.
  final int expansionPaybackMonths;

  /// An owner who already trades expands only while in profit, and no
  /// sooner than this many days after its latest store opened.
  final int expansionIntervalDays;

  /// The daily gross margin per household it assumes when judging a site.
  final Money marginPerHousehold;

  /// The slots its stores open, indexed by [DaySlot].
  final List<bool> hours;

  /// Staff per slot cover expected traffic times this: above 1 leaves room
  /// for busy days.
  final Fx serviceTarget;

  /// Visits per open slot per day it assumes before it has history.
  final int openingTraffic;

  /// The format this strategy runs, and opens when it expands.
  final FormatId format;

  /// The share of expected sales spent on marketing each day.
  final Fx marketingShare;
}

final class PersonSetup {
  const PersonSetup({
    required this.key,
    required this.name,
    required this.cash,
    required this.isPlayer,
    required this.strategy,
    this.local = false,
    this.country,
  });

  final String key;
  final String name;
  final Money cash;
  final bool isPlayer;

  /// Where they live and pay tax on their dividends, if the scenario says;
  /// otherwise where their first business is (see `residenceOf`).
  final CountryId? country;

  /// The strategy an AI policy runs this person's stores by; null for the
  /// player and for owners who never act.
  final StrategyId? strategy;

  /// A local shopkeeper, who runs the stores they have and never opens
  /// more, whatever the strategy says.
  final bool local;
}

final class CompanySetup {
  const CompanySetup({
    required this.key,
    required this.name,
    required this.owner,
    required this.cash,
  });

  final String key;
  final String name;
  final PersonId owner;
  final Money cash;
}

final class StoreSetup {
  const StoreSetup({
    required this.key,
    required this.name,
    required this.company,
    required this.site,
    required this.prices,
    required this.staff,
    this.format = const FormatId(0),
    this.area,
  });

  final String key;
  final String name;
  final CompanyId company;
  final SiteId site;
  final FormatId format;

  /// Its area, if works have taken it beyond its site's.
  final int? area;

  /// Staff per slot, indexed by [DaySlot]; a slot without staff is closed.
  final List<int> staff;

  /// Shelf price per product, indexed by [ProductId]; null if not listed.
  final List<Money?> prices;
}

/// One list of a scenario, by name, and its IDs in order.
typedef ContentList = ({String name, List<String> keys});

/// How a list of a scenario may change under a saved game.
enum ListGrowth {
  /// Only by entries added at the end, which join the world on load.
  append,

  /// Freely: only a new game reads it.
  free;

  static ListGrowth of(String list) => switch (list) {
    'companies' || 'stores' => free,
    _ => append,
  };
}
