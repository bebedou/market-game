import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../neighbourhoods/neighbourhood_generator.dart';
import 'brands.dart';
import 'sleepers.dart';
import 'valuation.dart';
import 'world_state.dart';

/// A free site in a district run by formula, as anyone can see it.
typedef DistrictSite = ({
  int number,
  String name,
  Fx location,
  int area,

  /// A month's rent, at a price index of 1.
  Money rent,
  Money openingCost,
  int shelfSlots,
});

/// A shop in a district run by formula, as anyone can see it.
typedef DistrictShop = ({
  int site,
  String name,
  FormatId format,
  Fx location,
  int area,

  /// A month's rent at its size, at a price index of 1.
  Money rent,

  /// The chain's company it belongs to; null for a shopkeeper of its own.
  CompanyId? company,

  /// When it opened, or last changed hands.
  Day since,

  /// Its asking price, where businesses change hands.
  Valuation? value,
});

/// A district run by formula, as anyone can see it: a chain weighs opening
/// or buying there as it would anywhere.
typedef DistrictView = ({
  /// Its place in the scenario's neighbourhoods.
  int row,
  String name,
  int households,
  Fx priceLevel,
  Fx incomeLevel,
  Fx wageLevel,

  /// What its households buy of each channel against their habits
  /// ([MarketDef.scale]).
  List<Fx> scale,
  List<DistrictSite> free,
  List<DistrictShop> shops,
});

/// Whole months from the scenario's start to [day].
int monthsSinceStart(ContentDb content, Day day) {
  final start = content.startDay.date;
  final now = day.date;
  return (now.year - start.year) * 12 + now.month - start.month;
}

/// The first day of [month] months from the scenario's start.
Day monthStart(ContentDb content, int month) {
  final start = content.startDay.date;
  // Months before the start come out right too: shops older than the game.
  final months = start.year * 12 + start.month - 1 + month;
  final year = months >= 0 ? months ~/ 12 : -((-months - 1) ~/ 12) - 1;
  return Day.fromDate(year, months - year * 12 + 1, 1);
}

/// [sleeper]'s sites, worked out once.
List<PlannedSite> sitesOf(
  WorldState world,
  ContentDb content,
  SleepingNeighbourhood sleeper,
) => sleeper.sites ??= plannedSites(content, sleeper.row, seed: world.seed);

/// The districts run by formula, as anyone can see them.
List<DistrictView> districtViews(WorldState world, ContentDb content) {
  final month = monthsSinceStart(content, world.today);
  return List.unmodifiable([
    for (final sleeper in world.sleepers)
      () {
        final row = content.neighbourhoods[sleeper.row];
        final sites = sitesOf(world, content, sleeper);
        final taken = {for (final shop in sleeper.shops) shop.site};
        return (
          row: sleeper.row,
          name: row.name,
          households: sleeper.households.fold(0, (sum, n) => sum + n),
          priceLevel: row.priceLevel,
          incomeLevel: row.incomeLevel,
          wageLevel: row.wageLevel,
          scale: row.scale,
          free: List<DistrictSite>.unmodifiable([
            for (final site in sites)
              if (!taken.contains(site.number))
                (
                  number: site.number,
                  name: site.name,
                  location: site.location,
                  area: site.area,
                  rent: site.rent,
                  openingCost: site.openingCost,
                  shelfSlots: site.shelfSlots,
                ),
          ]),
          shops: List<DistrictShop>.unmodifiable([
            for (final shop in sleeper.shops)
              (
                site: shop.site,
                name: shop.name,
                format: shop.format,
                location: sites[shop.site].location,
                area: shop.area,
                rent: sites[shop.site].rentFor(shop.area),
                company: shop.company,
                since: monthStart(
                  content,
                  shop.acquiredMonth ?? shop.openedMonth,
                ),
                value: valueSleepingShop(
                  world,
                  content,
                  sites[shop.site],
                  shop,
                  month,
                ),
              ),
          ]),
        );
      }(),
  ]);
}

/// [shop]'s asking price, as [valueStore] works one out: what its fittings
/// are worth worn down with age, and its year's profit beyond a fair return
/// on them. It holds no stock: the formula keeps none. Null where nothing
/// changes hands.
Valuation? valueSleepingShop(
  WorldState world,
  ContentDb content,
  PlannedSite site,
  SleepingShop shop,
  int month,
) {
  final terms = content.acquisitions;
  if (terms == null) return null;
  final format = content.formats[shop.format.index];
  final age = (month - shop.openedMonth) * 30;
  final used = age <= 0
      ? Fx.zero
      : age >= terms.fittingsLifeDays
      ? Fx.one
      : Fx.raw(mulDivRound(age, Fx.scale, terms.fittingsLifeDays));
  final wear = (Fx.one - terms.fittingsResidual) * used;
  final fittings = site.openingCost
      .times(format.fitOut)
      .times(world.macro.priceIndex)
      .times(Fx.one - wear);
  if (shop.sales.length < sleepingMonthsKept) {
    return (
      stock: Money.zero,
      fittings: fittings,
      earnings: Money.zero,
      price: fittings,
    );
  }
  final earnings = shop.yearProfit;
  final excess = earnings - fittings.times(terms.tangibleReturn);
  final price =
      fittings +
      Money(mulDivRound(excess.cents, Fx.scale, terms.capitalization.raw));
  final floor = fittings.times(terms.distressFloor);
  return (
    stock: Money.zero,
    fittings: fittings,
    earnings: earnings,
    price: price > floor ? price : floor,
  );
}

/// What a shop of [brand] on [site] in [sleeper]'s district is called: the
/// brand and the district, and the street too if the brand trades there
/// already.
String districtShopName(
  ContentDb content,
  SleepingNeighbourhood sleeper,
  Brand brand,
  PlannedSite site, {
  SleepingShop? except,
}) {
  final name =
      '${brand.name} ${districtOf(content.neighbourhoods[sleeper.row].name)}';
  final twin = sleeper.shops.any(
    (shop) => shop != except && shop.brand == brand.id,
  );
  return twin ? '$name, ${site.name}' : name;
}
