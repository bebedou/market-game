import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/money.dart';
import '../state/brands.dart';
import '../state/entities.dart';
import '../state/taxation.dart' show taxGain;
import '../state/store.dart';
import '../state/valuation.dart';
import '../state/world_state.dart';
import '../state/software.dart';
import '../systems/settlement.dart' show billInstallment;
import '../systems/software.dart' show closeSoftware;

/// Puts [amount] of [holder]'s cash into [company] as capital: its owner's,
/// or its parent company's.
void injectCapital(
  Ledger ledger,
  LedgerParty holder,
  Company company,
  Money amount,
) {
  ledger.pay(
    payer: holder,
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
  taxGain(world, content, ledger, seller, gain);
  for (final loan in world.loans) {
    if (loan.company == company.id && loan.guarantor == seller.id) {
      loan.guarantor = buyer.id;
    }
  }
  company
    ..owner = buyer.id
    ..injected = price - financed;
}

/// Sells [software] alone to the rival making [offer], out of a company
/// that holds other businesses: the company is paid the price, a gain taxed
/// with its profit, and trades on without it; its investors keep their
/// share of the company.
void sellSoftwareBusiness(
  WorldState world,
  Ledger ledger,
  Software software,
  SoftwareOffer offer,
) {
  ledger.pay(
    payer: world.elsewhere,
    payerAccount: AccountKind.investments,
    payee: world.companies[software.company.index],
    payeeAccount: AccountKind.disposals,
    amount: offer.price,
    reason: EntryReason.softwareSale,
  );
  final market = world.softwareMarket!;
  closeSoftware(
    world,
    market,
    software,
    SoftwareStatus.sold,
    to: market.rivals[offer.rival.index],
  );
}

/// Sells [software]'s company whole to the rival making [offer], beyond the
/// simulation: its loans and bills are settled, the buyer making up any
/// shortfall, and its cash goes with it; its owner gets their share of the
/// price and books the gain over what they put in, taxed as a dividend;
/// outside investors get theirs beyond the simulation. Its customers go to
/// the buyer, its people leave, and the company is [CompanyStatus.sold].
void sellSoftware(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Software software,
  SoftwareOffer offer,
) {
  final company = world.companies[software.company.index];
  // Whoever holds it sells: its parent company, or its owner's holding.
  final LedgerParty seller = switch (company.parent) {
    final parent? => world.companies[parent.index],
    null => world.persons[company.owner.index],
  };
  for (final loan in world.loans) {
    if (loan.company == company.id && loan.outstanding > Money.zero) {
      billInstallment(world, ledger, loan, all: true);
    }
  }
  final owed = company.payables.fold(
    Money.zero,
    (sum, payable) => sum + payable.amount,
  );
  final short = owed - company.accounts[AccountKind.cash];
  if (short > Money.zero) {
    ledger.pay(
      payer: world.elsewhere,
      payerAccount: AccountKind.investments,
      payee: company,
      payeeAccount: AccountKind.equity,
      amount: short,
      reason: EntryReason.softwareSale,
    );
  }
  for (final payable in company.payables) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.payables,
      payee: world.party(payable.creditor),
      payeeAccount: payable.creditorAccount,
      amount: payable.amount,
      reason: payable.reason,
    );
  }
  company.payables.clear();
  world.loans.removeWhere(
    (loan) => loan.company == company.id && loan.outstanding == Money.zero,
  );
  final left = company.accounts[AccountKind.cash];
  if (left > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.equity,
      payee: world.elsewhere,
      payeeAccount: AccountKind.investments,
      amount: left,
      reason: EntryReason.softwareSale,
    );
  }
  final proceeds = offer.price.times(software.stake);
  if (proceeds > Money.zero) {
    ledger.pay(
      payer: world.elsewhere,
      payerAccount: AccountKind.investments,
      payee: seller,
      payeeAccount: AccountKind.disposals,
      amount: proceeds,
      reason: EntryReason.softwareSale,
    );
  }
  if (company.injected > Money.zero) {
    ledger.post(
      seller,
      debit: AccountKind.disposals,
      credit: AccountKind.investments,
      amount: company.injected,
      reason: EntryReason.softwareSale,
    );
  }
  // A parent's gain is its income, taxed with its profit.
  if (seller is Person) {
    taxGain(world, content, ledger, seller, proceeds - company.injected);
  }
  final market = world.softwareMarket!;
  closeSoftware(
    world,
    market,
    software,
    SoftwareStatus.sold,
    to: market.rivals[offer.rival.index],
  );
  company
    ..injected = Money.zero
    ..director = null
    ..status = CompanyStatus.sold;
}
