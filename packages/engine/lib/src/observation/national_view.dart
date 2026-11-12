import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../countries/country_table.dart';
import '../countries/shop_bridge.dart' show formatTrades;
import '../state/world_state.dart';
import '../systems/national.dart';

/// A chain by formula, as anyone sees it: its trade, shops in all and by
/// region, and a year's sales at last month's pace.
typedef NationalChainView = ({
  String name,
  int trade,
  int stores,
  List<int> regional,
  Money yearSales,
  bool independent,
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
  });

  final CompanyId company;
  final int trade;
  final FormatId format;
  final StrategyId strategy;

  /// By region.
  final List<BlockRegionView> regions;

  /// Oldest first, at most two years.
  final List<BlockMonth> months;

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
    required CountryEconomy economy,
  }) : _economy = economy;

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

  /// Its prices against the start.
  final Fx priceIndex;

  /// Each region's wages and rents against the country's average.
  final List<Fx> wageLevels;
  final List<Fx> rentLevels;
  final CountryEconomy _economy;

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
              name: chain.def.name,
              trade: chain.def.trade,
              stores: chain.stores,
              regional: List<int>.unmodifiable(chain.regionalStores),
              yearSales: chain.months.isEmpty
                  ? Money.zero
                  : chain.months.last.sales.timesInt(12),
              independent: chain.def.independent,
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
                ),
          ],
          priceIndex: country.priceIndex,
          wageLevels: List.unmodifiable(country.wageLevels),
          rentLevels: List.unmodifiable(country.rentLevels),
          economy: economy,
        );
      }(),
  ];
}
