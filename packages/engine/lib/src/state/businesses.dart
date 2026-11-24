import '../content/content_db.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../countries/country_economy.dart';
import '../countries/shop_bridge.dart' show formatTrades;
import '../accounting/ledger.dart' show AccountKind;
import '../core/fx.dart';
import 'districts.dart' show monthsSinceStart, sitesOf, valueSleepingShop;
import 'entities.dart';
import 'factory.dart';
import 'factory_sales.dart' show Producer;
import 'national_value.dart' show nationalBuyer, valueBlock;
import 'sleepers.dart';
import 'software.dart';
import 'software_rules.dart';
import 'store.dart';
import 'valuation.dart' show bestBuyer, companyPrice, valueFactory, valueStore;
import 'world_state.dart';

/// The key of [format]'s trade, one business for every kind of shop of it,
/// whatever the countries.
String tradeKey(FormatDef format) => formatTrades[format.key] ?? format.key;

/// The key of a company's plants of [kind], one business.
String plantsKey(FactoryKindDef kind) => 'plants:${kind.key}';

/// The key of a company's software, one business.
const softwareBusiness = 'software';

/// One of a company's businesses part by part (the owner's design of
/// 2026-11-17): its shops of a trade in full, asleep in districts and
/// across countries; its plants of a kind; or its software.
final class BusinessParts {
  const BusinessParts({
    this.stores = const [],
    this.sleeping = const [],
    this.blocks = const [],
    this.plants = const [],
    this.software,
  });

  /// Its shops played in full, open or being fitted out.
  final List<Store> stores;

  /// Its shops in districts asleep, with their district.
  final List<(SleepingNeighbourhood, SleepingShop)> sleeping;

  /// Its shops across countries, by the country's place in the national
  /// table.
  final List<(int, CompanyBlock)> blocks;

  /// Its plants, running or being built.
  final List<Factory> plants;
  final Software? software;

  bool get isEmpty =>
      stores.isEmpty &&
      sleeping.isEmpty &&
      blocks.isEmpty &&
      plants.isEmpty &&
      software == null;
}

/// [company]'s business [business] (see [tradeKey], [plantsKey] and
/// [softwareBusiness]), part by part; empty if it has none.
BusinessParts businessParts(
  WorldState world,
  ContentDb content,
  CompanyId company,
  String business,
) {
  bool ofTrade(FormatId format) =>
      tradeKey(content.formats[format.index]) == business;
  final kinds = content.factories?.kinds;
  final software = softwareOf(world, company);
  return BusinessParts(
    stores: [
      for (final store in world.stores)
        if (store.company == company &&
            store.status != StoreStatus.closed &&
            ofTrade(store.format))
          store,
    ],
    sleeping: [
      for (final district in world.sleepers)
        for (final shop in district.shops)
          if (shop.company == company && ofTrade(shop.format)) (district, shop),
    ],
    blocks: [
      if (world.national case final national?)
        for (final (i, country) in national.countries.indexed)
          for (final block in country.blocks)
            if (block.company == company.index &&
                ofTrade(FormatId(block.format)))
              (i, block),
    ],
    plants: [
      if (kinds != null)
        for (final factory in world.factories)
          if (factory.company == company &&
              factory.status == FactoryStatus.running &&
              plantsKey(kinds[factory.kind.index]) == business)
            factory,
    ],
    software:
        business == softwareBusiness && software != null && software.running
        ? software
        : null,
  );
}

/// The keys of [company]'s businesses: its trades, its kinds of plant, its
/// software.
List<String> businessKeysOf(
  WorldState world,
  ContentDb content,
  CompanyId company,
) {
  final keys = <String>{};
  for (final store in world.stores) {
    if (store.company == company && store.status != StoreStatus.closed) {
      keys.add(tradeKey(content.formats[store.format.index]));
    }
  }
  for (final district in world.sleepers) {
    for (final shop in district.shops) {
      if (shop.company == company) {
        keys.add(tradeKey(content.formats[shop.format.index]));
      }
    }
  }
  if (world.national case final national?) {
    for (final country in national.countries) {
      for (final block in country.blocks) {
        if (block.company == company.index) {
          keys.add(tradeKey(content.formats[block.format]));
        }
      }
    }
  }
  if (content.factories?.kinds case final kinds?) {
    for (final factory in world.factories) {
      if (factory.company == company &&
          factory.status == FactoryStatus.running) {
        keys.add(plantsKey(kinds[factory.kind.index]));
      }
    }
  }
  if (softwareOf(world, company) case final software? when software.running) {
    keys.add(softwareBusiness);
  }
  return [...keys];
}

/// What [parts] stand at in their company's books: its shops' stock at cost
/// and what was paid for shops and chains bought; fitting out, plants and
/// software were spent, so count nothing.
({Money stock, Money bought}) businessBook(BusinessParts parts) {
  var stock = Money.zero;
  var bought = Money.zero;
  for (final store in parts.stores) {
    for (final product in store.stock) {
      stock += product.value;
    }
    bought += store.boughtFor;
  }
  for (final (_, block) in parts.blocks) {
    bought += block.cost;
  }
  return (stock: stock, bought: bought);
}

/// The biggest software rival still selling, who buys software sold on the
/// spot; null if none.
SoftwareRival? softwareBuyer(WorldState world) {
  SoftwareRival? best;
  for (final rival in world.softwareMarket?.rivals ?? const <SoftwareRival>[]) {
    if (!rival.selling || rival.rest) continue;
    if (best == null || rival.customers > best.customers) best = rival;
  }
  return best;
}

/// The rival producer who buys [factory] on the spot: one of its kind in
/// its country, else elsewhere; null if none makes its kind.
Producer? plantBuyer(WorldState world, Factory factory) {
  Producer? anywhere;
  for (final producer in world.producers) {
    if (producer.kind != factory.kind) continue;
    if (producer.country == factory.country) return producer;
    anywhere ??= producer;
  }
  return anywhere;
}

/// What [parts] sell for on the spot, each part to the buyer best able to
/// pay at its asking price, as shops sell (see [bestBuyer]): shops in full
/// to the owners of their kind, shops asleep to their district's own
/// shopkeepers, shops across countries to a chain of their trade, plants to
/// a rival producer of their kind, software to the biggest rival; its
/// [worth], what every part is asked, and whether each has a [buyer].
({Money worth, bool buyer}) businessSale(
  WorldState world,
  ContentDb content,
  BusinessParts parts,
) {
  var worth = Money.zero;
  var buyer = content.acquisitions != null;
  for (final store in parts.stores) {
    final value = valueStore(world, content, store);
    if (value == null) {
      buyer = false;
      continue;
    }
    worth += value.price;
    if (bestBuyer(world, content, store, value.price) == null) buyer = false;
  }
  final month = monthsSinceStart(content, world.today);
  for (final (district, shop) in parts.sleeping) {
    worth +=
        valueSleepingShop(
          world,
          content,
          sitesOf(world, content, district)[shop.site],
          shop,
          month,
          country: content.neighbourhoods[district.row].country,
        )?.price ??
        Money.zero;
  }
  if (world.national case final national?) {
    for (final (i, block) in parts.blocks) {
      final country = national.countries[i];
      final value = valueBlock(content, national, country, block);
      if (value == null) continue;
      worth += value.price;
      if (nationalBuyer(national, country, block, value.price) == null) {
        buyer = false;
      }
    }
  }
  for (final factory in parts.plants) {
    final value = valueFactory(world, content, factory);
    if (value == null) {
      buyer = false;
      continue;
    }
    worth += value.price;
    if (plantBuyer(world, factory) == null) buyer = false;
  }
  if (parts.software case final software?) {
    if (content.software case final def?) {
      worth += softwareWorth(world, content, def, software).business;
    }
    if (softwareBuyer(world) == null) buyer = false;
  }
  return (worth: worth, buyer: buyer);
}

/// Why [company]'s holdings are not its owner's alone to rearrange: listed,
/// or with outside investors; null if they are.
String? sharedHoldings(WorldState world, CompanyId company) {
  final listed =
      world.stocks?.stocks.any(
        (stock) => stock.own?.company == company.index && stock.running,
      ) ??
      false;
  if (listed) return 'listedRestructure';
  if (ownerShare(world, company) < Fx.one) return 'outsideInvestors';
  return null;
}

/// Who buys [company] whole on the spot, the richest of the game's other
/// owners who can pay its asking price, and for what; or why no one can: a
/// company holding subsidiaries, plants, software or shops across
/// countries sells those first, as buyers of a company take shops alone.
({Person? buyer, Money price, String? refusal}) companySale(
  WorldState world,
  ContentDb content,
  Company company,
) {
  ({Person? buyer, Money price, String? refusal}) no(String why) =>
      (buyer: null, price: Money.zero, refusal: why);
  if (sharedHoldings(world, company.id) case final why?) return no(why);
  if (world.companies.any(
    (other) => other.parent == company.id && other.isActive,
  )) {
    return no('hasSubsidiaries');
  }
  for (final key in businessKeysOf(world, content, company.id)) {
    final parts = businessParts(world, content, company.id, key);
    if (parts.blocks.isNotEmpty ||
        parts.plants.isNotEmpty ||
        parts.software != null) {
      return no('sellPartsFirst');
    }
  }
  final price = companyPrice(world, content, company);
  if (price == null) return no('nothingForSale');
  Person? buyer;
  for (final person in world.persons) {
    if (person.id == company.owner ||
        person.accounts[AccountKind.cash] < price ||
        !world.companies.any((c) => c.owner == person.id && c.isActive)) {
      continue;
    }
    if (buyer == null ||
        person.accounts[AccountKind.cash] > buyer.accounts[AccountKind.cash]) {
      buyer = person;
    }
  }
  if (buyer == null) return (buyer: null, price: price, refusal: 'noBuyer');
  return (buyer: buyer, price: price, refusal: null);
}
