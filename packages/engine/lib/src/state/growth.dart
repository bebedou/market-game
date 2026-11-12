import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import 'cohort.dart';
import 'entities.dart';
import 'market.dart';
import 'store.dart';
import 'world_state.dart';

/// Brings a saved [world] up to [content] that has grown since: products,
/// categories, people, suppliers, sites and markets appended to their lists
/// join the world on its current day, as they would have at the start;
/// markets gain households of segments they lacked; the opening stores on
/// new sites open, with their companies; a labour market added since starts
/// at its natural rate; and new countries' economies start as the first's
/// stands. Content that hasn't grown changes nothing.
void growWorld(WorldState world, ContentDb content) {
  final day = world.today;
  world.growEconomies(content);
  // A save from before the labour market starts at the natural rate; it is
  // never below 1% once modelled.
  if (content.macro.labour case final labour?) {
    for (final macro in world.economies) {
      if (macro.unemployment == Fx.zero) {
        macro.unemployment = labour.naturalUnemployment;
      }
    }
  }
  final oldSites = world.cohorts.isEmpty
      ? world.stores.fold(
          0,
          (most, s) => s.site.index >= most ? s.site.index + 1 : most,
        )
      : world.cohorts.first.proximity.length;

  // Products, categories and segments added at the end of their lists.
  final products = content.products.length;
  for (final store in world.stores) {
    while (store.prices.length < products) {
      store.prices.add(null);
    }
    while (store.stock.length < products) {
      store.stock.add(Stock());
    }
    store.history.grow(products);
  }
  for (final report in world.periodReports) {
    report.growProducts(products);
  }
  // A new category's need starts as at the start of a game.
  for (final cohort in world.cohorts) {
    final segment = content.segments[cohort.segment.index];
    for (var c = cohort.needs.length; c < content.categories.length; c++) {
      cohort.needs.add(
        segment.buysRarely(CategoryId(c), content.demand)
            ? Rng.keyed(
                world.seed,
                RngStream.needs,
                c,
                cohort.id.index,
              ).nextFx()
            : Fx.zero,
      );
    }
  }
  for (var i = world.persons.length; i < content.persons.length; i++) {
    final setup = content.persons[i];
    world.persons.add(
      Person(
        id: PersonId(i),
        name: setup.name,
        accounts: Accounts.opening(setup.cash),
      ),
    );
    world.moneySupply += setup.cash;
  }
  for (var i = world.suppliers.length; i < content.suppliers.length; i++) {
    world.suppliers.add(Supplier(id: SupplierId(i), accounts: Accounts()));
  }

  // Households learn how far they live from the new sites.
  for (final cohort in world.cohorts) {
    for (
      var site = cohort.proximity.length;
      site < content.sites.length;
      site++
    ) {
      cohort.proximity.add(
        Rng.keyed(world.seed, RngStream.sites, site, cohort.id.index).nextFx(),
      );
    }
  }

  // Existing markets gain households of segments they didn't have.
  for (var m = 0; m < world.households.length; m++) {
    final market = content.markets[m];
    final present = {
      for (final cohort in world.cohorts)
        if (cohort.market == market.id) cohort.segment.index,
    };
    final missing = [
      for (final segment in content.segments)
        if (!present.contains(segment.id.index) &&
            market.households[segment.id.index] > 0)
          segment,
    ];
    if (missing.isEmpty) continue;
    _join(
      world,
      content,
      newCohorts(
        content,
        world.seed,
        market,
        world.cohorts.length,
        day,
        only: missing,
      ),
    );
    // The newcomers are counted on arrival, as a census of the day.
    final census = world.markets[m].censuses;
    final households = world.cohorts
        .where((cohort) => cohort.market == market.id)
        .fold(0, (sum, cohort) => sum + cohort.weight);
    if (census.last.day == day) census.removeLast();
    census.add((day: day, households: households));
    if (census.length > MarketState.censusesKept) census.removeAt(0);
  }

  for (var m = world.households.length; m < content.markets.length; m++) {
    final market = content.markets[m];
    world.households.add(Households(market: market.id, accounts: Accounts()));
    final cohorts = newCohorts(
      content,
      world.seed,
      market,
      world.cohorts.length,
      day,
    );
    world.markets.add(
      MarketState.initial(
        market.id,
        day,
        cohorts.fold(0, (sum, cohort) => sum + cohort.weight),
      ),
    );
    _join(world, content, cohorts);
  }

  for (final setup in content.stores) {
    if (setup.site.index < oldSites || world.storeAt(setup.site) != null) {
      continue;
    }
    final opening = content.companies[setup.company.index];
    final company =
        world.companies
            .where((c) => c.name == opening.name && c.owner == opening.owner)
            .firstOrNull ??
        world.addCompany(opening.name, opening.owner, cash: opening.cash);
    world.addStore(
      content,
      name: setup.name,
      company: company.id,
      site: content.sites[setup.site.index],
      prices: setup.prices,
      staff: setup.staff,
      opensOn: day,
      format: setup.format,
      area: setup.area,
    );
  }
}

/// Adds [cohorts] to [world], neutral toward every store and believing its
/// prices as they are.
void _join(WorldState world, ContentDb content, List<HouseholdCohort> cohorts) {
  for (final cohort in cohorts) {
    final segment = content.segments[cohort.segment.index];
    for (final store in world.stores) {
      cohort.loyalty.add(content.demand.neutralLoyalty);
      cohort.perceivedPrices.add(
        segment.priceIndex(
              content.products,
              store.prices,
              priceLevel:
                  world.macroAt(content, store.market).priceIndex *
                  content.markets[store.market.index].priceLevel,
              references: content.references[content
                  .countryOf(store.market)
                  .index],
            ) ??
            Fx.one,
      );
    }
    world.cohorts.add(cohort);
  }
}

/// Why [world], read from a save without its content's structure, can't be
/// grown into [content]: lists the world mirrors must not be longer than the
/// content's. Null if it fits.
String? growthProblem(WorldState world, ContentDb content) {
  if (world.persons.length > content.persons.length) return 'fewer people';
  if (world.suppliers.length > content.suppliers.length) {
    return 'fewer suppliers';
  }
  if (world.households.length > content.markets.length) return 'fewer markets';
  for (final cohort in world.cohorts) {
    if (cohort.proximity.length > content.sites.length) return 'fewer sites';
    if (cohort.needs.length > content.categories.length) {
      return 'fewer categories';
    }
    if (cohort.segment.index >= content.segments.length) {
      return 'fewer segments';
    }
  }
  for (final store in world.stores) {
    if (store.prices.length > content.products.length) {
      return 'fewer products';
    }
  }
  return null;
}
