import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/money.dart';
import '../state/brands.dart';
import '../state/entities.dart';
import '../state/store.dart';
import '../state/valuation.dart';
import '../state/world_state.dart';

/// Puts [amount] of [person]'s cash into [company] as capital.
void injectCapital(
  Ledger ledger,
  Person person,
  Company company,
  Money amount,
) {
  ledger.pay(
    payer: person,
    payerAccount: AccountKind.investments,
    payee: company,
    payeeAccount: AccountKind.equity,
    amount: amount,
    reason: EntryReason.capitalInjection,
  );
  company.injected += amount;
}

/// Hands [store] to [buyer] for [price] in cash. The seller books the gain,
/// or loss, over the stock and what it had paid for the store; the buyer
/// carries the price beyond the stock as a business asset, or books a gain
/// if it paid less than the stock cost.
void transferStore(
  WorldState world,
  Ledger ledger,
  Store store,
  Company buyer,
  Money price,
) {
  final seller = world.companies[store.company.index];
  var stock = Money.zero;
  for (final product in store.stock) {
    stock += product.value;
  }
  ledger
    ..pay(
      payer: buyer,
      payerAccount: AccountKind.businessAssets,
      payee: seller,
      payeeAccount: AccountKind.disposals,
      amount: price,
      reason: EntryReason.storeSale,
      store: store.id,
    )
    ..post(
      seller,
      debit: AccountKind.disposals,
      credit: AccountKind.inventory,
      amount: stock,
      reason: EntryReason.storeSale,
      store: store.id,
    )
    ..post(
      buyer,
      debit: AccountKind.inventory,
      credit: AccountKind.businessAssets,
      amount: stock,
      reason: EntryReason.storeSale,
      store: store.id,
    );
  if (store.boughtFor > Money.zero) {
    ledger.post(
      seller,
      debit: AccountKind.disposals,
      credit: AccountKind.businessAssets,
      amount: store.boughtFor,
      reason: EntryReason.storeSale,
      store: store.id,
    );
  }
  if (price < stock) {
    ledger.post(
      buyer,
      debit: AccountKind.businessAssets,
      credit: AccountKind.disposals,
      amount: stock - price,
      reason: EntryReason.storeSale,
      store: store.id,
    );
  }
  store
    ..company = buyer.id
    ..boughtFor = price > stock ? price - stock : Money.zero
    ..acquiredOn = world.today;
}

/// Sells [store] at its asking price to the [bestBuyer], whose owner first
/// puts in whatever its company lacks for the price and the reserve.
/// Returns the buyer, or null if there is none.
Company? sellToBestBuyer(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Store store,
) {
  final value = valueStore(world, content, store);
  if (value == null) return null;
  final buyer = bestBuyer(world, content, store, value.price);
  if (buyer == null) return null;
  final needed =
      value.price + value.price.times(content.acquisitions!.buyerReserve);
  final cash = buyer.accounts[AccountKind.cash];
  if (cash < needed) {
    injectCapital(
      ledger,
      world.persons[buyer.owner.index],
      buyer,
      needed - cash,
    );
  }
  transferStore(world, ledger, store, buyer, value.price);
  takeOverName(world, content, store, buyer.owner);
  return buyer;
}

/// Hands [company] to [buyer] for [price]. The company pays [financed] of
/// it out of what it has just borrowed, handing that much of its capital
/// back, and the buyer pays the rest from personal cash. The seller books
/// the gain or loss over the capital they had in it and pays the flat tax
/// on a gain; the buyer's capital in it is what they paid. The buyer takes
/// over the seller's guarantees of its loans.
void transferCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Company company,
  Person buyer,
  Money price, {
  Money financed = Money.zero,
}) {
  final seller = world.persons[company.owner.index];
  if (financed > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.equity,
      payee: seller,
      payeeAccount: AccountKind.disposals,
      amount: financed,
      reason: EntryReason.companySale,
    );
  }
  if (price > financed) {
    ledger.pay(
      payer: buyer,
      payerAccount: AccountKind.investments,
      payee: seller,
      payeeAccount: AccountKind.disposals,
      amount: price - financed,
      reason: EntryReason.companySale,
    );
  }
  if (company.injected > Money.zero) {
    ledger.post(
      seller,
      debit: AccountKind.disposals,
      credit: AccountKind.investments,
      amount: company.injected,
      reason: EntryReason.companySale,
    );
  }
  final gain = price - company.injected;
  if (content.taxesOf(world.residence(content, seller.id)) case final taxes?
      when gain > Money.zero) {
    final tax = gain.times(taxes.dividendRate);
    if (tax > Money.zero) {
      ledger.pay(
        payer: seller,
        payerAccount: AccountKind.taxes,
        payee: world.government,
        payeeAccount: AccountKind.revenue,
        amount: tax,
        reason: EntryReason.capitalGainsTax,
      );
    }
  }
  for (final loan in world.loans) {
    if (loan.company == company.id && loan.guarantor == seller.id) {
      loan.guarantor = buyer.id;
    }
  }
  company
    ..owner = buyer.id
    ..injected = price - financed;
}
