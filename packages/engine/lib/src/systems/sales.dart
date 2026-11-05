import '../accounting/ledger.dart';
import '../core/ids.dart';
import '../state/store.dart';
import '../state/world_state.dart';

/// Sells up to [wanted] units of [product] at the store's shelf price, oldest
/// lots first, to the households of the store's market. Returns the units
/// sold. Every demand model sells through here.
int sellUnits(
  WorldState world,
  Ledger ledger,
  Store store,
  ProductId product,
  int wanted,
) {
  final price = store.prices[product.index];
  if (price == null || wanted <= 0) return 0;
  final taken = store.stock[product.index].take(wanted);
  if (taken.units == 0) return 0;
  final company = world.companies[store.company.index];
  ledger
    ..pay(
      payer: world.households[store.market.index],
      payerAccount: AccountKind.spending,
      payee: company,
      payeeAccount: AccountKind.revenue,
      amount: price.timesInt(taken.units),
      reason: EntryReason.sale,
      store: store.id,
      product: product,
      units: taken.units,
    )
    ..post(
      company,
      debit: AccountKind.costOfGoods,
      credit: AccountKind.inventory,
      amount: taken.cost,
      reason: EntryReason.costOfSale,
      store: store.id,
      product: product,
      units: taken.units,
    );
  return taken.units;
}
