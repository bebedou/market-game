import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../countries/country_table.dart' show NationalCountry;
import '../countries/shop_bridge.dart' show formatTrades;
import '../state/buying_terms.dart';
import '../state/director.dart';
import '../state/entities.dart';
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/national_value.dart';
import '../state/orders.dart';
import '../state/store.dart';
import '../state/taxation.dart';
import '../state/world_state.dart';
import 'closure.dart';
import 'events.dart';
import 'sleepers.dart' show formulaGoodsExtra;
import 'tick_system.dart';
import 'factory_sales.dart' show billMaking, kindShare;

/// [world]'s countries by formula, made the first time they are needed and
/// run up to this month, each country in the phase of the cycle the game had
/// it in (see [WorldState.regimeLog]). Null without a national table, or
/// with one country. A saved game from before they were kept rebuilds them
/// this way.
CountryEconomy? currentNational(WorldState world, ContentDb content) {
  final table = content.national;
  if (table == null || world.cycle == null) return null;
  final regimes = content.macro.regimes;
  // The table's phase for each of the game's regimes, by key.
  final phase = [
    for (final regime in regimes)
      switch (table.regimes.indexWhere((r) => r.key == regime.key)) {
        -1 => 0,
        final i => i,
      },
  ];
  // Each country of the table: its column in the log, or the shared cycle's.
  final columns = [
    for (final country in table.countries)
      switch (content.countries.indexWhere((c) => c.national == country.key)) {
        -1 => content.countries.length,
        final i => i,
      },
  ];
  final economy = world.national ??= CountryEconomy(
    table,
    seed: world.seed,
    start: content.startDay,
  );
  final months = 1 + world.regimeLog.length;
  while (economy.monthsRun < months) {
    _brief(world, content, economy);
    _ownPlants(world, content, economy);
    final run = economy.monthsRun;
    final logged = run == 0 ? null : world.regimeLog[run - 1];
    economy.advanceMonth(
      regimes: [
        for (final column in columns)
          phase[logged == null
              ? content.macro.startRegime.index
              : logged[column]],
      ],
    );
  }
  return economy;
}

/// Sets what each chain's own plants save it on its goods this month: for
/// each plant, its share of the chain's needs of its kind, times that
/// kind's share of the chain's goods, times what making them saves.
void _ownPlants(WorldState world, ContentDb content, CountryEconomy economy) {
  final factories = content.factories;
  final sales = factories?.sales;
  for (final (n, country) in economy.countries.indexed) {
    final game = gameCountry(content, n);
    for (final chain in country.chains) {
      var saving = Fx.zero;
      if (factories != null && sales != null && game != null) {
        final trade = economy.table.trades[chain.def.trade].key;
        for (final plant in world.chainPlants) {
          if (plant.country != game || plant.chain != chain.def.name) continue;
          saving +=
              plant.share *
              kindShare(content, factories, trade, plant.kind) *
              sales.plantSaving;
        }
      }
      chain.ownSaving = saving;
    }
  }
}

/// The chance, each month, that a chain offers for a company's shops run
/// by formula across a country.
const offerChance = Fx.raw(400);

/// The fewest shops a chain offers for.
const offerMinimumShops = 10;

/// How long a chain's offer stays open.
const offerDays = 30;

/// Sets each company's shops by formula for the month to come: their
/// company's buying terms, and the marketing its director judges pays best,
/// or else the strategy's (none more for a chain it bought).
void _brief(WorldState world, ContentDb content, CountryEconomy economy) {
  for (final (i, country) in economy.countries.indexed) {
    final home = gameCountry(content, i);
    for (final block in country.blocks) {
      final company = world.companies[block.company];
      block.discount = buyingDiscount(content, company);
      block.strain = _strain(content, company.director);
      block.quality = _quality(world, content, company, block, home);
      final floor = block.name == null
          ? content.strategies[block.strategy].marketingShare
          : Fx.zero;
      block.marketing = company.director == null
          ? floor
          : economy.bestMarketing(country, block.trade, block, floor: floor);
    }
  }
}

/// What the quality of the goods its owner's factories make adds to the
/// pull of [company]'s shops run by formula in [country], [block]: each
/// product's lead over the market's standard, by its share of the shops'
/// goods and by how much of what they sold of it last month the factory
/// can make in a month, times what a point of quality draws. Nothing in
/// their first month.
Fx _quality(
  WorldState world,
  ContentDb content,
  Company company,
  CompanyBlock block,
  CountryId? country,
) {
  final factories = content.factories;
  final labs = factories?.labs;
  final goods = block.months.lastOrNull?.goods ?? Money.zero;
  if (labs == null ||
      country == null ||
      world.factories.isEmpty ||
      goods <= Money.zero) {
    return Fx.zero;
  }
  final level = world.macroOf(country).priceIndex;
  var total = Fx.zero;
  for (final (:product, :share) in formatGoodsMix(
    content,
    content.formats[block.format],
  )) {
    final factory = _factoryFor(world, content, company, country, product);
    if (factory == null) continue;
    final lead = factoryLead(world, factory, product.id);
    if (lead <= Fx.zero) continue;
    final kind = factories!.sized(factory.kind, factory.size);
    final quote = marketQuote(
      content,
      country,
      product,
      kind.minOrderUnits,
      level,
    );
    if (quote == null || quote.price <= Money.zero) continue;
    final wanted = goods.times(share).cents;
    final able = quote.price.cents * factory.monthCapacity(kind, world.today);
    total += wanted <= able
        ? share * lead
        : share * lead * Fx.raw(mulDivRound(able, Fx.scale, wanted));
  }
  return labs.nationalPull * total;
}

/// How far past what [director]'s grade runs well they grow the company's
/// shops run by formula: the rate over their grade's, less one; nothing
/// within it or without them. Left to judge, only a character who pushes
/// past their grade's rate strains.
Fx _strain(ContentDb content, Director? director) {
  if (director == null || !director.allows(Growth.open)) return Fx.zero;
  final limit = content.directors!.grades[director.grade.index].growth;
  final rate = content.directors!.growthRateOf(director);
  if (limit <= Fx.zero || rate <= limit) return Fx.zero;
  return rate.div(limit) - Fx.one;
}

/// The game's country for the table's country at [index], if it plays it.
CountryId? gameCountry(ContentDb content, int index) {
  final key = content.national!.countries[index].key;
  final found = content.countries.indexWhere((c) => c.national == key);
  return found < 0 ? null : CountryId(found);
}

/// What shops of [format] run by formula in [country] spend, as shares of
/// sales, priced and stocked as [strategy] has it: goods at its markup with
/// what the formula's shops pay beyond the list, its marketing, and the
/// format's staff and premises as settled shops there have them.
ShopCosts nationalCosts(
  FormatDef format,
  StrategyDef strategy,
  CountryId country,
) {
  final national = format.national!;
  return (
    goods:
        Fx.one.div(Fx.one + strategy.markup) *
        (Fx.one + formulaGoodsExtra(format)),
    marketing: strategy.marketingShare,
    staff: national.staffIn(country),
    premises: national.premisesIn(country),
  );
}

/// What fitting out one shop of a format whose national figures are
/// [national] costs in [region] of [country], for [trade]: its national
/// fitting out at the country's prices and the region's cost level.
Money nationalFitOut(
  FormatNational national,
  CountryState country,
  int trade,
  int region,
) => national.fitOut
    .times(country.priceIndex)
    .times(country.costLevels[trade][region]);

/// Whether [store], of a company its director runs, goes to formula: open,
/// with no works under way, of a kind the countries by formula have, in a
/// country the table plays.
bool absorbable(WorldState world, ContentDb content, Store store) {
  if (store.status != StoreStatus.open || store.works != null) return false;
  final company = world.companies[store.company.index];
  if (company.director == null || !company.isActive) return false;
  final format = content.formats[store.format.index];
  final trade = formatTrades[format.key];
  final table = content.national;
  return format.national != null &&
      table != null &&
      table.trades.any((t) => t.key == trade) &&
      tableCountry(content, content.markets[store.market.index].country) !=
          null;
}

/// The region of the table's country at [index] that [market] is in: the
/// one the scenario names, or else the most populous.
int marketRegion(CountryState country, MarketDef market) =>
    regionNamed(country.def, market.region);

/// The region of [country] the national table keys [key], or its most
/// populous without one.
int regionNamed(NationalCountry country, String? key) {
  final regions = country.regions;
  final named = regions.indexWhere((r) => r.key == key);
  if (named >= 0) return named;
  var best = 0;
  for (var r = 1; r < regions.length; r++) {
    if (regions[r].population > regions[best].population) best = r;
  }
  return best;
}

/// The shops [owner]'s companies hold in the table's country at [index], by
/// trade then region: by formula, those being fitted out counted, and in
/// districts, asleep and played in full. The competition authority counts
/// them all as one owner's.
List<List<int>> ownerShopGrid(
  WorldState world,
  ContentDb content,
  CountryEconomy economy,
  int index,
  PersonId owner,
) {
  final country = economy.countries[index];
  final trades = economy.table.trades;
  final grid = [for (final _ in trades) List.filled(country.regionCount, 0)];
  for (final block in country.blocks) {
    if (world.companies[block.company].owner != owner) continue;
    for (var r = 0; r < country.regionCount; r++) {
      grid[block.trade][r] += block.regions[r].stores;
    }
  }
  final game = gameCountry(content, index);
  if (game == null) return grid;
  int? tradeOf(FormatId format) {
    final key = formatTrades[content.formats[format.index].key];
    final t = trades.indexWhere((trade) => trade.key == key);
    return t < 0 ? null : t;
  }

  for (final store in world.stores) {
    if (store.status == StoreStatus.closed ||
        world.companies[store.company.index].owner != owner) {
      continue;
    }
    final market = content.markets[store.market.index];
    final t = tradeOf(store.format);
    if (market.country != game || t == null) continue;
    grid[t][marketRegion(country, market)]++;
  }
  for (final sleeper in world.sleepers) {
    final row = content.neighbourhoods[sleeper.row];
    if (row.country != game) continue;
    final r = regionNamed(country.def, row.region);
    for (final shop in sleeper.shops) {
      final company = shop.company;
      final t = tradeOf(shop.format);
      if (company == null ||
          t == null ||
          world.companies[company.index].owner != owner) {
        continue;
      }
      grid[t][r]++;
    }
  }
  return grid;
}

/// The shops of [trade] [owner]'s companies hold in the table's country at
/// [index] (see [ownerShopGrid]): in [region], or across it if null.
int ownerShops(
  WorldState world,
  ContentDb content,
  CountryEconomy economy,
  int index,
  PersonId owner,
  int trade, {
  int? region,
}) {
  final held = ownerShopGrid(world, content, economy, index, owner)[trade];
  return region == null ? held.fold(0, (sum, n) => sum + n) : held[region];
}

/// A director runs a company by formula: on the first of each month, every
/// store of a company with a director that is [absorbable] joins its shops
/// of its kind by formula in the region it trades in, as a settled shop,
/// under the director's strategy. It does so before the countries run the
/// month, so it trades there from the day it leaves the districts. Its stock
/// is sold at cost to everyone beyond the districts played in full, what
/// the company paid for it beyond its stock stays its business asset,
/// carried by the shops by formula, and its site is free.
void absorbDirected(WorldState world, TickContext context) {
  final content = context.content;
  if (content.national == null || !context.day.isFirstOfMonth) return;
  for (final store in world.stores) {
    if (!absorbable(world, content, store)) continue;
    // As the countries stood last month, so the shop joins the one to come.
    final economy = world.national ?? currentNational(world, content);
    if (economy == null) return;
    final company = world.companies[store.company.index];
    final market = content.markets[store.market.index];
    final index = tableCountry(content, market.country)!;
    final country = economy.countries[index];
    final format = content.formats[store.format.index];
    final trade = economy.table.trades.indexWhere(
      (t) => t.key == formatTrades[format.key],
    );
    final region = marketRegion(country, market);
    var stock = Money.zero;
    for (final product in store.stock) {
      stock += product.clear().cost;
    }
    if (stock > Money.zero) {
      context.ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.inventory,
        amount: stock,
        reason: EntryReason.storeSale,
        store: store.id,
      );
    }
    final strategy = _strategyFor(content, company, store);
    final block = economy.open(
      index,
      company: company.id.index,
      trade: trade,
      format: format.id.index,
      strategy: strategy.id.index,
      region: region,
      count: 1,
      perStore: format.national!.salesIn(market.country),
      price: Fx.one + strategy.marketPosition,
      costs: nationalCosts(format, strategy, market.country),
      settled: true,
    );
    block.cost += store.boughtFor;
    store.boughtFor = Money.zero;
    closeStore(world, context.ledger, store);
    context.events.add(
      StoreAbsorbed(
        store: store.id,
        company: company.id,
        country: market.country,
        region: region,
      ),
    );
  }
}

/// How [store] is run once its director's: their strategy if it is for its
/// kind of shop, else its manager's if that is, else its kind's at the
/// market's prices.
StrategyDef _strategyFor(ContentDb content, Company company, Store store) {
  final director = content.strategies[company.director!.strategy.index];
  if (director.format == store.format) return director;
  if (store.manager?.strategy case final managed?
      when content.strategies[managed.index].format == store.format) {
    return content.strategies[managed.index];
  }
  final fitting = [
    for (final option in content.strategies)
      if (option.format == store.format) option,
  ];
  return fitting.where((s) => s.marketPosition == Fx.zero).firstOrNull ??
      fitting.firstOrNull ??
      director;
}

/// The table's country for the game's [country], if the table has it.
int? tableCountry(ContentDb content, CountryId country) {
  final table = content.national;
  if (table == null) return null;
  final key = content.countries[country.index].national;
  final found = table.countries.indexWhere((c) => c.key == key);
  return found < 0 ? null : found;
}

/// Runs the countries by formula each month, on its first, and books each
/// month of companies' shops run by formula there in their accounts,
/// against everyone beyond the districts played in full: their sales, and
/// their goods, marketing, staff and premises. Each country taxes what they
/// made there.
final class NationalSystem implements TickSystem {
  const NationalSystem();

  @override
  void run(WorldState world, TickContext context) {
    absorbDirected(world, context);
    if (!context.day.isFirstOfMonth) return;
    final economy = currentNational(world, context.content);
    if (economy == null) return;
    final posted = world.nationalPosted;
    for (final (i, country) in economy.countries.indexed) {
      final home = gameCountry(context.content, i);
      for (final block in country.blocks) {
        final company = world.companies[block.company];
        if (!company.isActive) continue;
        for (final month in block.months) {
          if (posted != null && month.start.number <= posted.number) continue;
          final made = home == null
              ? Money.zero
              : _supply(world, context, block, month, home);
          _book(world, context.ledger, block, month, made: made);
          if (home != null) {
            recordDistrictMonth(
              world,
              company.id,
              home,
              month.start.date.year,
              sales: month.sales,
              profit: month.profit,
            );
          }
        }
      }
    }
    // Everything up to this month is in the books.
    world.nationalPosted = context.day;
    _offers(world, context, economy);
  }

  /// Chains' offers for companies' shops run by formula: those past their
  /// day go, and now and then, with [offerChance] a month, the chain of
  /// their trade with the most cash offers for shops that have traded a
  /// year, at least [offerMinimumShops] of them, at their price and a
  /// premium of a tenth to three tenths, open [offerDays] days.
  void _offers(WorldState world, TickContext context, CountryEconomy economy) {
    economy.offers.removeWhere(
      (offer) => offer.expires.number < context.day.number,
    );
    final content = context.content;
    if (content.acquisitions == null) return;
    for (final (i, country) in economy.countries.indexed) {
      if (gameCountry(content, i) == null) continue;
      for (final (b, block) in country.blocks.indexed) {
        if (!world.companies[block.company].isActive ||
            block.months.length < 12 ||
            block.stores < offerMinimumShops ||
            economy.offers.any((offer) => offer.block == block)) {
          continue;
        }
        final rng = context.rng(RngStream.countries, 700000 + i * 1000 + b);
        if (!rng.chance(offerChance)) continue;
        final value = valueBlock(content, economy, country, block);
        if (value == null || value.price <= Money.zero) continue;
        final premium = Fx.raw(1000 + rng.nextInt(2001));
        final price = value.price.times(Fx.one + premium);
        final buyer = nationalBuyer(economy, country, block, price);
        if (buyer == null) continue;
        economy.offers.add(
          NationalOffer(
            number: economy.nextOffer++,
            country: i,
            block: block,
            chain: buyer,
            price: price,
            expires: context.day + offerDays,
          ),
        );
      }
    }
  }

  /// Books [month] of [block]: its sales from everyone beyond the districts
  /// played in full, and its costs to them, but for the goods worth [made]
  /// that the owner's factories made, which [_supply] booked.
  void _book(
    WorldState world,
    Ledger ledger,
    CompanyBlock block,
    BlockMonth month, {
    Money made = Money.zero,
  }) {
    final company = world.companies[block.company];
    if (month.sales > Money.zero) {
      ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.revenue,
        amount: month.sales,
        reason: EntryReason.sale,
      );
    }
    for (final (amount, account, reason) in [
      (month.goods - made, AccountKind.costOfGoods, EntryReason.costOfSale),
      (month.marketing, AccountKind.marketing, EntryReason.marketing),
      (month.staff, AccountKind.wages, EntryReason.wages),
      (month.premises, AccountKind.rent, EntryReason.rent),
    ]) {
      if (amount <= Money.zero) continue;
      ledger.pay(
        payer: company,
        payerAccount: account,
        payee: world.elsewhere,
        payeeAccount: AccountKind.revenue,
        amount: amount,
        reason: reason,
      );
    }
  }

  /// What the owner's factories make of [block]'s goods for [month] in the
  /// game's [country], booked as for shops run by hand: each category its
  /// shops sell that a running factory of the owner's, serving the
  /// country, makes, as many units of each product as the shops' goods buy
  /// at what their wholesalers would charge, as far as the month's capacity
  /// left goes. The shops' company owes the factory's that price; the
  /// factory owes its materials and any freight. Returns what the shops
  /// owe, at the market price.
  Money _supply(
    WorldState world,
    TickContext context,
    CompanyBlock block,
    BlockMonth month,
    CountryId country,
  ) {
    final content = context.content;
    final factories = content.factories;
    if (factories == null ||
        world.factories.isEmpty ||
        month.goods <= Money.zero) {
      return Money.zero;
    }
    final company = world.companies[block.company];
    final format = content.formats[block.format];
    final level = world.macroOf(country).priceIndex;
    final terms = Fx.one - buyingDiscount(content, company);
    var owed = Money.zero;
    for (final (:product, :share) in formatGoodsMix(content, format)) {
      final factory = _factoryFor(world, content, company, country, product);
      if (factory == null) continue;
      final kind = factories.sized(factory.kind, factory.size);
      final quote = marketQuote(
        content,
        country,
        product,
        kind.minOrderUnits,
        level,
      );
      if (quote == null || quote.price <= Money.zero) continue;
      final price = quote.price.times(terms);
      if (price <= Money.zero) continue;
      final wanted = mulDivRound(
        month.goods.times(share).cents,
        1,
        price.cents,
      );
      final left = factory.capacityLeft(kind, context.day);
      final units = wanted < left ? wanted : left;
      if (units <= 0) continue;
      final value = price.timesInt(units);
      final maker = world.companies[factory.company.index];
      final ledger = context.ledger;
      // The shops' goods, owed to the factory's company on its terms.
      ledger.post(
        company,
        debit: AccountKind.costOfGoods,
        credit: AccountKind.payables,
        amount: value,
        reason: EntryReason.costOfSale,
        product: product.id,
        units: units,
      );
      company.payables.add(
        Payable(
          creditor: maker.partyRef,
          creditorAccount: AccountKind.receivables,
          reason: EntryReason.supplierPayment,
          amount: value,
          due: context.day + factories.paymentTermsDays,
        ),
      );
      ledger.post(
        maker,
        debit: AccountKind.receivables,
        credit: AccountKind.ownGoods,
        amount: value,
        reason: EntryReason.factorySale,
        product: product.id,
        units: units,
        factory: factory.id,
      );
      final (:materials, :freight) = billMaking(
        world,
        ledger,
        kind,
        factory,
        product,
        units,
        value,
        abroad: factory.country != country,
      );
      factory.recordMade(
        context.day,
        units,
        own: true,
        margin: value - materials - freight,
      );
      owed += value;
    }
    return owed;
  }
}

/// The running factory of [company]'s owner, in any of their companies,
/// that makes [product] and serves [country], with the most left to make
/// this month; the first built of equals.
Factory? _factoryFor(
  WorldState world,
  ContentDb content,
  Company company,
  CountryId country,
  ProductDef product,
) {
  final factories = content.factories!;
  Factory? best;
  var bestLeft = 0;
  for (final factory in world.factories) {
    final maker = world.companies[factory.company.index];
    if (!factory.runsOn(world.today) ||
        !factory.servesCountry(country) ||
        maker.owner != company.owner ||
        !maker.isActive) {
      continue;
    }
    final kind = factories.sized(factory.kind, factory.size);
    if (!kindMakes(kind, product)) continue;
    final left = factory.capacityLeft(kind, world.today);
    if (left > bestLeft) {
      best = factory;
      bestLeft = left;
    }
  }
  return best;
}

/// What share of a shop of [format]'s goods, at what they cost, each
/// product it may sell takes, as households buy them by their habits: a
/// thousand of each kind, at normal income and prices.
List<({ProductDef product, Fx share})> formatGoodsMix(
  ContentDb content,
  FormatDef format,
) {
  final costs = <int>[];
  var total = 0;
  for (final product in content.products) {
    final c = product.category.index;
    if (!format.sells[c]) {
      costs.add(0);
      continue;
    }
    var units = Fx.zero;
    for (final segment in content.segments) {
      var premium = segment.premiumShare[c];
      if (premium > Fx.one) premium = Fx.one;
      final tier = product.tier == ProductTier.premium
          ? premium
          : Fx.one - premium;
      units += (segment.dailyUnits[c] * tier).timesInt(1000);
    }
    final cost = product.baseCost.times(units).cents;
    costs.add(cost);
    total += cost;
  }
  return [
    for (final product in content.products)
      if (costs[product.id.index] > 0 && total > 0)
        (
          product: product,
          share: Fx.raw(mulDivRound(costs[product.id.index], Fx.scale, total)),
        ),
  ];
}
