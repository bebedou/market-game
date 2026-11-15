import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../content/factory_sales_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../countries/shop_bridge.dart' show formatTrades;
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/factory_sales.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'national.dart' show formatGoodsMix, gameCountry;
import 'tick_system.dart';

/// Entity keys within [RngStream.factorySales]: a rival's bid on a tender,
/// a chain's month for a product.
const _bidKeys = 1000000;
const _chainKeys = 50000000;

/// How factories sell to companies beyond their owner's.
///
/// On the first of the month: running contracts are delivered, before the
/// owner's shops order, each as far as the month's capacity goes, with a
/// penalty on what falls short; tenders due close, the player's bid
/// weighed against rival producers' by price, quality and reliability; and
/// chains open new tenders for products the player's factories make, in
/// countries they serve. On the last day of the month, independent shops
/// buy at each factory's list price what its share of their goods comes
/// to, from what capacity is left. Runs before the national economy, which
/// buys for the owner's own shops run by formula.
final class FactorySalesSystem implements TickSystem {
  const FactorySalesSystem();

  @override
  void run(WorldState world, TickContext context) {
    final factories = context.content.factories;
    final sales = factories?.sales;
    if (factories == null || sales == null) return;
    final day = context.day;
    if (day.isFirstOfMonth) {
      _deliver(world, context, factories, sales);
      final economy = world.national;
      _close(world, context, factories, sales);
      if (economy != null) _open(world, context, factories, sales, economy);
      _prune(world, sales, day);
    }
    if (day.date.day == daysInMonth(day.date.year, day.date.month)) {
      final economy = world.national;
      if (economy != null) {
        _independents(world, context, factories, sales, economy);
      }
    }
  }

  void _deliver(
    WorldState world,
    TickContext context,
    FactoriesDef factories,
    FactorySalesDef sales,
  ) {
    final day = context.day;
    for (final contract in world.contracts) {
      if (!contract.runsOn(day)) continue;
      final factory = world.factories[contract.factory.index];
      final maker = world.companies[factory.company.index];
      if (!factory.runsOn(day) || !maker.isActive) {
        contract.ended = true;
        continue;
      }
      final kind = factories.sized(factory.kind, factory.size);
      final left = factory.capacityLeft(kind, day);
      final units = contract.units < left ? contract.units : left;
      final short = contract.units - units;
      if (units > 0) {
        sellGoods(
          world,
          context,
          kind,
          factory,
          contract.country,
          context.content.products[contract.product.index],
          units,
          contract.price,
        );
      }
      if (short > 0) {
        final penalty = contract.price
            .timesInt(short)
            .times(sales.shortfallPenalty);
        if (penalty > Money.zero) {
          billFactory(
            world,
            context.ledger,
            factory,
            AccountKind.spending,
            EntryReason.contractPenalty,
            penalty,
          );
        }
        final missed = Fx.raw(mulDivRound(short, Fx.scale, contract.units));
        final lower = factory.reliability - sales.reliabilityLoss * missed;
        factory.reliability = lower.isNegative ? Fx.zero : lower;
      } else {
        final higher = factory.reliability + sales.reliabilityGain;
        factory.reliability = higher > Fx.one ? Fx.one : higher;
      }
      contract
        ..delivered += units
        ..short += short;
    }
  }

  void _close(
    WorldState world,
    TickContext context,
    FactoriesDef factories,
    FactorySalesDef sales,
  ) {
    final day = context.day;
    final content = context.content;
    for (final tender in world.tenders) {
      if (tender.status != TenderStatus.open || day < tender.closes) continue;
      final product = content.products[tender.product.index];
      Producer? best;
      Money? bestPrice;
      var bestWeighed = Money.zero;
      final bidders = <Producer>[];
      for (final (i, producer) in world.producers.indexed) {
        if (producer.country != tender.country ||
            !kindMakes(factories.kinds[producer.kind.index], product) ||
            producer.lead < tender.floor) {
          continue;
        }
        bidders.add(producer);
        final rng = context.rng(
          RngStream.factorySales,
          _bidKeys + tender.number * 100 + i,
        );
        final swing =
            sales.producerSpread * (rng.nextFx().timesInt(2) - Fx.one);
        final price = tender.reference.times(
          Fx.one - producer.discount + swing,
        );
        final weighed = weighBid(sales, price, producer.lead, Fx.one);
        if (best == null || weighed < bestWeighed) {
          best = producer;
          bestPrice = price;
          bestWeighed = weighed;
        }
      }
      final bidder = _playerBid(world, content, factories, tender);
      final player = bidder == null
          ? null
          : weighBid(
              sales,
              tender.bidPrice!,
              factoryLead(world, bidder, tender.product),
              bidder.reliability,
            );
      if (bidder != null &&
          player != null &&
          (best == null || player < bestWeighed)) {
        final starts = _firstOfMonthAfter(day, 1);
        world.contracts.add(
          Contract(
            number: tender.number,
            factory: bidder.id,
            country: tender.country,
            chain: tender.chain,
            product: tender.product,
            units: tender.units,
            price: tender.bidPrice!,
            starts: starts,
            ends: _firstOfMonthAfter(day, 1 + tender.months),
          ),
        );
        tender
          ..status = TenderStatus.won
          ..winner = bidder.name
          ..winningPrice = tender.bidPrice;
        for (final producer in bidders) {
          final raised = producer.discount + sales.producerPushBack;
          producer.discount = raised > sales.maxDiscount
              ? sales.maxDiscount
              : raised;
        }
      } else if (best != null) {
        tender
          ..status = TenderStatus.lost
          ..winner = best.name
          ..winningPrice = bestPrice;
        best.won++;
        if (bidder != null) {
          final eased = best.discount - Fx.raw(sales.producerPushBack.raw ~/ 2);
          best.discount = eased < sales.minDiscount ? sales.minDiscount : eased;
        }
      } else {
        tender.status = TenderStatus.lapsed;
      }
      if (tender.bidFactory != null) {
        context.events.add(
          TenderClosed(
            number: tender.number,
            won: tender.status == TenderStatus.won,
          ),
        );
      }
    }
  }

  /// The factory of the player's whose bid on [tender] still stands: it
  /// runs, makes the product, serves the country and meets the floor.
  Factory? _playerBid(
    WorldState world,
    ContentDb content,
    FactoriesDef factories,
    Tender tender,
  ) {
    final id = tender.bidFactory;
    if (id == null || tender.bidPrice == null) return null;
    final factory = world.factories[id.index];
    final company = world.companies[factory.company.index];
    if (!factory.runsOn(world.today) ||
        !company.isActive ||
        company.owner != world.player ||
        !factory.servesCountry(tender.country) ||
        !kindMakes(
          factories.kinds[factory.kind.index],
          content.products[tender.product.index],
        ) ||
        factoryLead(world, factory, tender.product) < tender.floor) {
      return null;
    }
    return factory;
  }

  void _open(
    WorldState world,
    TickContext context,
    FactoriesDef factories,
    FactorySalesDef sales,
    CountryEconomy economy,
  ) {
    final content = context.content;
    final day = context.day;
    for (final (n, country) in economy.countries.indexed) {
      final game = gameCountry(content, n);
      if (game == null) continue;
      final made = madeFor(world, content, factories, game);
      if (made.isEmpty) continue;
      for (final (c, chain) in country.chains.indexed) {
        if (chain.def.independent ||
            !chain.isTrading ||
            chain.boughtBy != null) {
          continue;
        }
        final goods = chain.months.lastOrNull?.goods ?? Money.zero;
        if (goods <= Money.zero) continue;
        final trade = economy.table.trades[chain.def.trade].key;
        for (final product in made) {
          final share = tradeProductShare(content, trade, product);
          if (share <= Fx.zero) continue;
          final rng = context.rng(
            RngStream.factorySales,
            _chainKeys + n * 1000000 + c * 1000 + product.id.index,
          );
          if (rng.nextFx() >= sales.tenderChance) continue;
          final lot = sales.lotShares[rng.nextInt(sales.lotShares.length)];
          final months = sales.termMonths[rng.nextInt(sales.termMonths.length)];
          final floor =
              sales.qualityFloors[rng.nextInt(sales.qualityFloors.length)];
          final wholesale = wholesalePrice(world, content, game, product);
          if (wholesale <= Money.zero) continue;
          final units = mulDivRound(
            goods.times(share).times(lot).cents,
            1,
            wholesale.cents,
          );
          if (units <= 0) continue;
          world.tenders.add(
            Tender(
              number: world.nextTenderNumber++,
              country: game,
              chain: chain.def.name,
              product: product.id,
              units: units,
              months: months,
              floor: floor,
              reference: wholesale.times(sales.producerPrice),
              opens: day,
              closes: day + sales.openDays,
            ),
          );
          context.events.add(TenderOpened(number: world.tenders.last.number));
        }
      }
    }
  }

  void _prune(WorldState world, FactorySalesDef sales, Day day) {
    final month = monthOf(day);
    world.tenders.removeWhere(
      (tender) =>
          tender.status != TenderStatus.open &&
          month - monthOf(tender.closes) > sales.resultMonths,
    );
    world.contracts.removeWhere(
      (contract) =>
          (contract.ended || contract.ends <= day) &&
          month - monthOf(contract.ends) > sales.resultMonths,
    );
  }

  void _independents(
    WorldState world,
    TickContext context,
    FactoriesDef factories,
    FactorySalesDef sales,
    CountryEconomy economy,
  ) {
    final content = context.content;
    final day = context.day;
    for (final factory in world.factories) {
      final maker = world.companies[factory.company.index];
      final discount = factory.rivalDiscount;
      if (!factory.runsOn(day) || !maker.isActive) continue;
      final kind = factories.sized(factory.kind, factory.size);
      final products = [
        for (final product in content.products)
          if (kindMakes(kind, product)) product,
      ];
      var lead = Fx.zero;
      for (final product in products) {
        lead += factoryLead(world, factory, product.id);
      }
      if (products.isNotEmpty) lead = Fx.raw(lead.raw ~/ products.length);
      // Shares of a whole country's independents run small: in millionths.
      final offered = discount == null
          ? Fx.zero
          : discount + sales.qualityWeight * lead;
      final aim = offered.isNegative
          ? 0
          : mulDivRound(
              sales.independentResponse.raw * 100,
              offered.raw,
              Fx.scale,
            );
      factory.independentShare += mulDivRound(
        aim - factory.independentShare,
        sales.independentMove.raw,
        Fx.scale,
      );
      if (discount == null || factory.independentShare <= 0) continue;
      for (final (n, country) in economy.countries.indexed) {
        final game = gameCountry(content, n);
        if (game == null || !factory.servesCountry(game)) continue;
        for (final chain in country.chains) {
          if (!chain.def.independent) continue;
          final goods = chain.months.lastOrNull?.goods ?? Money.zero;
          if (goods <= Money.zero) continue;
          final trade = economy.table.trades[chain.def.trade].key;
          for (final product in products) {
            final share = tradeProductShare(content, trade, product);
            if (share <= Fx.zero) continue;
            final wholesale = wholesalePrice(world, content, game, product);
            if (wholesale <= Money.zero) continue;
            final wanted = mulDivRound(
              mulDivRound(
                goods.times(share).cents,
                factory.independentShare,
                1000000,
              ),
              1,
              wholesale.cents,
            );
            final left = factory.capacityLeft(kind, day);
            final units = wanted < left ? wanted : left;
            if (units <= 0) continue;
            final price = factoryPrice(wholesale, rivalDiscount: discount);
            sellGoods(
              world,
              context,
              kind,
              factory,
              game,
              product,
              units,
              price,
            );
            billFactory(
              world,
              context.ledger,
              factory,
              AccountKind.overheads,
              EntryReason.freight,
              price.timesInt(units).times(sales.independentDelivery),
              product: product.id,
              units: units,
            );
          }
        }
      }
    }
  }
}

/// The first of the month [months] months after [day]'s.
Day _firstOfMonthAfter(Day day, int months) {
  final target = monthOf(day) + months;
  return Day.fromDate(target ~/ 12, target % 12 + 1, 1);
}

/// What a bid of [price] for goods [lead] over the standard, from a
/// supplier of [reliability], comes to as the chain weighs it: quality
/// counts as a cheaper price, unreliability as a dearer one.
Money weighBid(FactorySalesDef sales, Money price, Fx lead, Fx reliability) {
  var factor = Fx.one - sales.qualityWeight * lead;
  if (factor < const Fx.raw(5000)) factor = const Fx.raw(5000);
  final doubt = sales.reliabilityWeight * (Fx.one - reliability);
  return price.times(factor).times(Fx.one + doubt);
}

/// What a shop's wholesalers charge for [product] in [country] today, at
/// the largest orders: what chains' goods are counted in.
Money wholesalePrice(
  WorldState world,
  ContentDb content,
  CountryId country,
  ProductDef product,
) {
  final quote = marketQuote(
    content,
    country,
    product,
    1000000,
    world.macroOf(country).priceIndex,
  );
  return quote?.price ?? Money.zero;
}

/// The share of what shops of the trade [tradeKey] spend on goods that goes
/// on [product], from the goods mix of the trade's first format.
Fx tradeProductShare(ContentDb content, String tradeKey, ProductDef product) {
  for (final format in content.formats) {
    if (formatTrades[format.key] != tradeKey) continue;
    for (final entry in formatGoodsMix(content, format)) {
      if (entry.product.id == product.id) return entry.share;
    }
    return Fx.zero;
  }
  return Fx.zero;
}

/// The products the running factories that serve [country] make, in order.
List<ProductDef> madeFor(
  WorldState world,
  ContentDb content,
  FactoriesDef factories,
  CountryId country,
) {
  final made = <ProductDef>[];
  for (final product in content.products) {
    for (final factory in world.factories) {
      if (!factory.runsOn(world.today) ||
          !world.companies[factory.company.index].isActive ||
          !factory.servesCountry(country) ||
          !kindMakes(factories.kinds[factory.kind.index], product)) {
        continue;
      }
      made.add(product);
      break;
    }
  }
  return made;
}

/// Books [units] of [product] that [factory] sells to a company beyond its
/// owner's, in [country], at [price] a unit: paid from beyond the
/// simulation, with its materials and any freight owed.
void sellGoods(
  WorldState world,
  TickContext context,
  FactoryKindDef kind,
  Factory factory,
  CountryId country,
  ProductDef product,
  int units,
  Money price,
) {
  final maker = world.companies[factory.company.index];
  final value = price.timesInt(units);
  context.ledger.pay(
    payer: world.elsewhere,
    payerAccount: AccountKind.spending,
    payee: maker,
    payeeAccount: AccountKind.revenue,
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
    saved: factorySaving(world, factory, product.id),
  ).timesInt(units);
  final freight = factory.country == country
      ? Money.zero
      : value.times(kind.freight);
  billFactory(
    world,
    context.ledger,
    factory,
    AccountKind.costOfGoods,
    EntryReason.materials,
    materials,
    product: product.id,
    units: units,
  );
  billFactory(
    world,
    context.ledger,
    factory,
    AccountKind.overheads,
    EntryReason.freight,
    freight,
    product: product.id,
    units: units,
  );
  factory.recordMade(
    context.day,
    units,
    own: false,
    margin: value - materials - freight,
  );
}

/// Bills [factory]'s company [amount] for [reason], owed to everyone
/// beyond the simulation today.
void billFactory(
  WorldState world,
  Ledger ledger,
  Factory factory,
  AccountKind expense,
  EntryReason reason,
  Money amount, {
  ProductId? product,
  int units = 0,
}) {
  if (amount <= Money.zero) return;
  final company = world.companies[factory.company.index];
  ledger.post(
    company,
    debit: expense,
    credit: AccountKind.payables,
    amount: amount,
    reason: reason,
    product: product,
    units: units,
    factory: factory.id,
  );
  company.payables.add(
    Payable(
      creditor: world.elsewhere.partyRef,
      creditorAccount: AccountKind.revenue,
      reason: reason,
      amount: amount,
      due: world.today,
      factory: factory.id,
    ),
  );
}
