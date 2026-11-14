import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../state/buying_terms.dart';
import '../state/director.dart';
import '../state/entities.dart';
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/national_value.dart';
import '../state/orders.dart';
import '../state/taxation.dart';
import '../state/world_state.dart';
import 'sleepers.dart' show formulaGoodsExtra;
import 'tick_system.dart';

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
  for (final country in economy.countries) {
    for (final block in country.blocks) {
      final company = world.companies[block.company];
      block.discount = buyingDiscount(content, company);
      block.strain = _strain(content, company.director);
      final floor = block.name == null
          ? content.strategies[block.strategy].marketingShare
          : Fx.zero;
      block.marketing = company.director == null
          ? floor
          : economy.bestMarketing(country, block.trade, block, floor: floor);
    }
  }
}

/// How far past what [director]'s grade runs well their brief grows the
/// company's shops run by formula: the rate over their grade's, less one;
/// nothing as they judge, within it, or without them.
Fx _strain(ContentDb content, Director? director) {
  if (director == null ||
      director.nationalAuto ||
      !director.allows(Growth.open)) {
    return Fx.zero;
  }
  final limit = content.directors!.grades[director.grade.index].growth;
  if (limit <= Fx.zero || director.nationalRate <= limit) return Fx.zero;
  return director.nationalRate.div(limit) - Fx.one;
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
        final buyer = nationalBuyer(country, block.trade, price);
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
      final kind = factories.kinds[factory.kind.index];
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
      final materials = materialsCost(
        kind,
        product,
        world.macroOf(factory.country).priceIndex,
      ).timesInt(units);
      final freight = factory.country == country
          ? Money.zero
          : value.times(kind.freight);
      void owe(AccountKind expense, EntryReason reason, Money amount) {
        if (amount <= Money.zero) return;
        ledger.post(
          maker,
          debit: expense,
          credit: AccountKind.payables,
          amount: amount,
          reason: reason,
          product: product.id,
          units: units,
          factory: factory.id,
        );
        maker.payables.add(
          Payable(
            creditor: world.elsewhere.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: reason,
            amount: amount,
            due: context.day,
            factory: factory.id,
          ),
        );
      }

      owe(AccountKind.costOfGoods, EntryReason.materials, materials);
      owe(AccountKind.overheads, EntryReason.freight, freight);
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
    final kinds = content.factories!.kinds;
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
      final kind = kinds[factory.kind.index];
      if (!kindMakes(kind, product)) continue;
      final left = factory.capacityLeft(kind, world.today);
      if (left > bestLeft) {
        best = factory;
        bestLeft = left;
      }
    }
    return best;
  }
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
