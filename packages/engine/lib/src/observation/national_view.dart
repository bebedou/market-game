import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../countries/country_table.dart';
import '../countries/shop_bridge.dart' show formatTrades;
import '../core/calendar.dart';
import '../state/buying_terms.dart';
import '../state/national_value.dart';
import '../state/world_state.dart';
import '../systems/national.dart';

/// A chain by formula, as anyone sees it: its trade, shops in all and by
/// region, and a year's sales at last month's pace.
typedef NationalChainView = ({
  /// Its place among the country's chains in the national table.
  int index,
  String name,
  int trade,
  int stores,
  List<int> regional,
  Money yearSales,
  bool independent,

  /// What it sells for whole, if it does.
  NationalValue? value,

  /// The company that bought it, if one did.
  CompanyId? boughtBy,
});

/// A chain's offer for the actor's shops run by formula: [block] is their
/// place among the country's blocks.
typedef NationalOfferView = ({
  int number,
  int block,
  String chain,
  Money price,
  Day expires,
});

/// A company's shops run by formula in one region: trading and being
/// fitted out, and the last twelve months' sales and profit.
typedef BlockRegionView = ({
  int trading,
  int pending,
  Money yearSales,
  Money yearProfit,
});

/// A company's shops of one kind run by formula across one country, as its
/// owner sees them.
final class CompanyBlockView {
  const CompanyBlockView({
    required this.company,
    required this.trade,
    required this.format,
    required this.strategy,
    required this.regions,
    required this.months,
    this.discount = Fx.zero,
    this.marketing = Fx.zero,
    this.brandPull = Fx.zero,
    this.name,
    this.index = 0,
    this.value,
    this.buyer,
  });

  final CompanyId company;
  final int trade;
  final FormatId format;
  final StrategyId strategy;

  /// By region.
  final List<BlockRegionView> regions;

  /// Oldest first, at most two years.
  final List<BlockMonth> months;

  /// What its suppliers take off its goods, the share of its sales it
  /// spends on marketing, and how much more its shops draw for it.
  final Fx discount;
  final Fx marketing;
  final Fx brandPull;

  /// The chain it was bought from; null for the company's own shops.
  final String? name;

  /// Its place among the country's blocks, what it sells for whole, and
  /// the chain that would buy it at that price, if any can.
  final int index;
  final NationalValue? value;
  final String? buyer;

  int get stores => regions.fold(0, (sum, r) => sum + r.trading + r.pending);
  Money get yearSales =>
      regions.fold(Money.zero, (sum, r) => sum + r.yearSales);
  Money get yearProfit =>
      regions.fold(Money.zero, (sum, r) => sum + r.yearProfit);
}

/// One country by formula, region by region, as an owner sees it: what
/// each region's households spend on each trade, the shops there, the
/// chains', and the owner's own shops run by formula. Worked out when asked
/// for, from the world as it stands.
final class NationalCountryView {
  NationalCountryView({
    required this.index,
    required this.country,
    required this.def,
    required this.households,
    required this.markets,
    required this.stores,
    required this.chains,
    required this.blocks,
    required this.priceIndex,
    required this.wageLevels,
    required this.rentLevels,
    required this.costLevels,
    required CountryEconomy economy,
    this.offers = const [],
    Map<int, Fx> discounts = const {},
  }) : _economy = economy,
       _discounts = discounts;

  /// Its place in the national table.
  final int index;

  /// The game's country it is, if the game plays it.
  final CountryId? country;
  final NationalCountry def;

  /// Households now, by region.
  final List<int> households;

  /// What households spend a year at last month's pace, by trade then
  /// region.
  final List<List<Money>> markets;

  /// Every shop of each trade, by trade then region.
  final List<List<int>> stores;
  final List<NationalChainView> chains;

  /// The owner's shops run by formula here.
  final List<CompanyBlockView> blocks;

  /// Chains' offers for them.
  final List<NationalOfferView> offers;

  /// Its prices against the start.
  final Fx priceIndex;

  /// Each region's wages and rents against the country's average.
  final List<Fx> wageLevels;
  final List<Fx> rentLevels;

  /// What a shop of each trade costs to run and fit out in each region
  /// against the country's, by trade then region.
  final List<List<Fx>> costLevels;
  final CountryEconomy _economy;

  /// The actor's companies' buying terms, by company index.
  final Map<int, Fx> _discounts;

  /// What fitting out one shop of [format] in [region] costs, or nothing if
  /// its shops can't run by formula.
  Money fitOut(ContentDb content, FormatId format, int region) {
    final national = content.formats[format.index].national;
    final trade = tradeOf(content, format);
    if (national == null || trade == null) return Money.zero;
    return national.fitOut.times(priceIndex).times(costLevels[trade][region]);
  }

  /// What one more settled shop of [company]'s [format] in [region] would
  /// add to its sales and profit a year, stocked and priced as [strategy]
  /// has it: as its shops there draw already, or as a first one would.
  ({Money sales, Money profit}) newShop(
    ContentDb content, {
    required CompanyId company,
    required FormatId format,
    required StrategyId strategy,
    required int region,
  }) {
    final def = content.formats[format.index];
    final trade = tradeOf(content, format);
    final national = def.national;
    if (trade == null || national == null || country == null) {
      return (sales: Money.zero, profit: Money.zero);
    }
    final rule = content.strategies[strategy.index];
    return _economy.outlookFor(
      index,
      company: company.index,
      trade: trade,
      format: format.index,
      region: region,
      perStore: national.salesIn(country!),
      price: Fx.one + rule.marketPosition,
      costs: nationalCosts(def, rule, country!),
      discount: _discounts[company.index] ?? Fx.zero,
    );
  }

  /// The national trade [format] counts under, if its shops can run by
  /// formula.
  int? tradeOf(ContentDb content, FormatId format) {
    final def = content.formats[format.index];
    if (def.national == null) return null;
    final key = formatTrades[def.key];
    final found = _economy.table.trades.indexWhere((t) => t.key == key);
    return found < 0 ? null : found;
  }
}

/// Every country by formula as [actor] sees them, by the national table;
/// empty without one.
List<NationalCountryView> nationalViews(
  WorldState world,
  ContentDb content,
  PersonId actor,
) {
  final economy = currentNational(world, content);
  if (economy == null) return const [];
  final mine = {
    for (final company in world.companies)
      if (company.owner == actor) company.id.index,
  };
  final discounts = {
    for (final index in mine)
      index: buyingDiscount(content, world.companies[index]),
  };
  return [
    for (final (i, country) in economy.countries.indexed)
      () {
        final def = country.def;
        final regions = country.regionCount;
        final people = def.regions.fold(0, (sum, r) => sum + r.population);
        final total = country.totalHouseholds;
        final chainViews = [
          for (final chain in country.chains)
            (
              index: country.chains.indexOf(chain),
              name: chain.def.name,
              trade: chain.def.trade,
              stores: chain.stores,
              regional: List<int>.unmodifiable(chain.regionalStores),
              yearSales: chain.months.isEmpty || !chain.isTrading
                  ? Money.zero
                  : chain.months.last.sales.timesInt(12),
              independent: chain.def.independent,
              value: valueChain(content, economy, country, chain),
              boughtBy: switch (chain.boughtBy) {
                final index? => CompanyId(index),
                null => null,
              },
            ),
        ];
        final stores = [
          for (final (t, _) in economy.table.trades.indexed)
            [
              for (var r = 0; r < regions; r++)
                () {
                  var count = 0;
                  for (final chain in chainViews) {
                    if (chain.trade == t) count += chain.regional[r];
                  }
                  for (final block in country.blocks) {
                    if (block.trade == t) count += block.regions[r].trading;
                  }
                  return count;
                }(),
            ],
        ];
        return NationalCountryView(
          index: i,
          country: gameCountry(content, i),
          def: def,
          households: [
            for (final region in def.regions)
              people == 0 ? 0 : mulDivRound(total, region.population, people),
            if (def.regions.isEmpty) total,
          ],
          markets: [
            for (final trade in country.regionSpend)
              [
                for (final region in trade)
                  region.fold(Money.zero, (sum, m) => sum + m).timesInt(12),
              ],
          ],
          stores: stores,
          chains: chainViews,
          blocks: [
            for (final block in country.blocks)
              if (mine.contains(block.company))
                CompanyBlockView(
                  company: CompanyId(block.company),
                  trade: block.trade,
                  format: FormatId(block.format),
                  strategy: StrategyId(block.strategy),
                  regions: [
                    for (final region in block.regions)
                      (
                        trading: region.trading,
                        pending: region.pending,
                        yearSales: region.yearSales,
                        yearProfit: region.yearProfit,
                      ),
                  ],
                  months: List.unmodifiable(block.months),
                  discount: block.discount,
                  marketing: block.marketing,
                  brandPull:
                      economy.brandFactor(country, block.trade, block) - Fx.one,
                  name: block.name,
                  index: country.blocks.indexOf(block),
                  value: valueBlock(content, economy, country, block),
                  buyer: switch (valueBlock(content, economy, country, block)) {
                    final value? => nationalBuyer(
                      country,
                      block.trade,
                      value.price,
                    )?.def.name,
                    null => null,
                  },
                ),
          ],
          priceIndex: country.priceIndex,
          wageLevels: List.unmodifiable(country.wageLevels),
          rentLevels: List.unmodifiable(country.rentLevels),
          costLevels: List.unmodifiable(country.costLevels),
          economy: economy,
          discounts: discounts,
          offers: [
            for (final offer in economy.offers)
              if (offer.country == i && mine.contains(offer.block.company))
                (
                  number: offer.number,
                  block: country.blocks.indexOf(offer.block),
                  chain: offer.chain.def.name,
                  price: offer.price,
                  expires: offer.expires,
                ),
          ],
        );
      }(),
  ];
}
