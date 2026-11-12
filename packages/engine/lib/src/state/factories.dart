import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import 'factory.dart';
import 'store.dart';
import 'world_state.dart';

/// What a shop in [country] would pay a wholesaler for [quantity] units of
/// [product] at [priceIndex], the country's: the cheapest of its suppliers
/// carrying it whose minimum order the quantity meets, or failing that the
/// one with the smallest minimum. Null if none of them carries it.
({SupplierDef supplier, Money price})? marketQuote(
  ContentDb content,
  CountryId country,
  ProductDef product,
  int quantity,
  Fx priceIndex,
) {
  SupplierDef? best;
  var bestPrice = Money.zero;
  SupplierDef? smallest;
  for (final supplier in content.suppliers) {
    if (supplier.country != country || !supplier.carries[product.id.index]) {
      continue;
    }
    if (smallest == null || supplier.minOrderUnits < smallest.minOrderUnits) {
      smallest = supplier;
    }
    if (quantity < supplier.minOrderUnits) continue;
    final price = supplier.unitPrice(product, quantity, priceIndex);
    if (best == null || price < bestPrice) {
      best = supplier;
      bestPrice = price;
    }
  }
  if (best != null) return (supplier: best, price: bestPrice);
  if (smallest == null) return null;
  return (
    supplier: smallest,
    price: smallest.unitPrice(product, quantity, priceIndex),
  );
}

/// What [factory] charges a shop: what the shop's wholesalers would, less
/// its discount for a rival's shop.
Money factoryPrice(Money market, {Fx? rivalDiscount}) =>
    rivalDiscount == null ? market : market.times(Fx.one - rivalDiscount);

/// The days [kind]'s goods take to reach a shop in [country] from a
/// factory in [home].
int factoryLeadTime(
  FactoriesDef factories,
  FactoryKindDef kind,
  CountryId home,
  CountryId country,
) => kind.leadTimeDays + (country == home ? 0 : factories.abroadDays);

/// What a unit of [product] takes in materials at [priceIndex], the
/// factory's country's.
Money materialsCost(FactoryKindDef kind, ProductDef product, Fx priceIndex) =>
    product.baseCost.times(kind.materials).times(priceIndex);

/// Whether [kind] makes [product].
bool kindMakes(FactoryKindDef kind, ProductDef product) =>
    kind.category == product.category;

/// The factory of [store]'s owner that makes [product] for it today, if
/// any: one running that makes its category and serves its country, the one
/// with the most left to make this month first, then the first built. Its
/// shops then buy the product only from it.
Factory? factoryFor(
  WorldState world,
  ContentDb content,
  Store store,
  ProductDef product,
) {
  final factories = content.factories;
  if (factories == null || world.factories.isEmpty) return null;
  final owner = world.companies[store.company.index].owner;
  final country = content.countryOf(store.market);
  Factory? best;
  var bestLeft = -1;
  for (final factory in world.factories) {
    if (!factory.runsOn(world.today) ||
        !factory.servesCountry(country) ||
        world.companies[factory.company.index].owner != owner ||
        !world.companies[factory.company.index].isActive) {
      continue;
    }
    final kind = factories.kinds[factory.kind.index];
    if (!kindMakes(kind, product)) continue;
    final left = factory.capacityLeft(kind, world.today);
    if (left > bestLeft) {
      best = factory;
      bestLeft = left;
    }
  }
  return best;
}
