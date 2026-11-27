/// Fixed assets: shop fittings and plants, carried at cost less wear.
///
/// Fitting out a shop, opening shops across a country or in a district run
/// by formula, and building or enlarging a plant are investments: the money
/// goes into [AccountKind.fixedAssets], and each thing bought keeps its own
/// book value ([Store.fittings], [Factory.book], `CompanyBlock.fittings`,
/// [SleepingShop.fittings]), which a company's account sums (see
/// [fixedAssetsByCompany], checked by the invariants). On the first of each month
/// every book value wears by twice its straight-line rate over its life
/// ([FinanceDef.fittingsLifeYears], [FinanceDef.plantLifeYears]), charged as
/// depreciation. A sale hands the book value to the buyer as part of the
/// price; a closure writes it off.
library;

import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'entities.dart';
import 'factory.dart';
import 'sleepers.dart';
import 'store.dart';
import 'world_state.dart';

/// A book value below this is written off whole at the next month's wear.
const _smallestBook = Money(100);

/// What a month wears off [book], for a thing that serves [lifeYears]:
/// twice the straight-line rate on what is left.
Money monthsWear(Money book, int lifeYears) {
  if (book <= Money.zero) return Money.zero;
  if (book <= _smallestBook) return book;
  return Money(mulDivRound(book.cents, 2, lifeYears * 12));
}

/// [company] pays [payee] [amount] for fittings or a plant, carried as a
/// fixed asset. The caller adds it to the thing's own book value.
void invest(
  Ledger ledger,
  Company company, {
  required LedgerParty payee,
  required AccountKind payeeAccount,
  required Money amount,
  StoreId? store,
  FactoryId? factory,
}) {
  if (amount <= Money.zero) return;
  ledger.pay(
    payer: company,
    payerAccount: AccountKind.fixedAssets,
    payee: payee,
    payeeAccount: payeeAccount,
    amount: amount,
    reason: EntryReason.investment,
    store: store,
    factory: factory,
  );
}

/// Writes [book] of [company]'s fixed assets off, as what they stood for
/// closes. The caller clears the thing's own book value.
void writeOffFixed(
  Ledger ledger,
  Company company,
  Money book, {
  StoreId? store,
  FactoryId? factory,
}) {
  if (book <= Money.zero) return;
  ledger.post(
    company,
    debit: AccountKind.writeOffs,
    credit: AccountKind.fixedAssets,
    amount: book,
    reason: EntryReason.closure,
    store: store,
    factory: factory,
  );
}

/// [seller] gives up [book] of fixed assets it sold, against the sale's
/// gain.
void sellFixed(
  Ledger ledger,
  Company seller,
  Money book, {
  EntryReason reason = EntryReason.storeSale,
  StoreId? store,
  FactoryId? factory,
}) {
  if (book <= Money.zero) return;
  ledger.post(
    seller,
    debit: AccountKind.disposals,
    credit: AccountKind.fixedAssets,
    amount: book,
    reason: reason,
    store: store,
    factory: factory,
  );
}

/// [buyer] carries what it paid for fittings it bought, [book] as the
/// seller carried them, out of [paid], the price beyond the stock it first
/// booked as a business asset; never more than [paid]. Returns what it
/// carries.
Money buyFixed(
  Ledger ledger,
  Company buyer,
  Money book,
  Money paid, {
  EntryReason reason = EntryReason.storeSale,
  StoreId? store,
}) {
  final carried = book < paid ? book : paid;
  carryFixed(ledger, buyer, carried, reason: reason, store: store);
  return carried > Money.zero ? carried : Money.zero;
}

/// [buyer] carries [amount] of what it paid for a business, first booked
/// as a business asset, as the fixed assets it bought.
void carryFixed(
  Ledger ledger,
  Company buyer,
  Money amount, {
  EntryReason reason = EntryReason.storeSale,
  StoreId? store,
}) {
  if (amount <= Money.zero) return;
  ledger.post(
    buyer,
    debit: AccountKind.fixedAssets,
    credit: AccountKind.businessAssets,
    amount: amount,
    reason: reason,
    store: store,
  );
}

/// What each company's shops, plants and shops by formula stand at in its
/// books, by company index: what its fixed-assets account must come to.
List<Money> fixedAssetsByCompany(WorldState world) {
  final totals = List.filled(world.companies.length, Money.zero);
  for (final store in world.stores) {
    totals[store.company.index] += store.fittings;
  }
  for (final factory in world.factories) {
    totals[factory.company.index] += factory.book;
  }
  for (final district in world.sleepers) {
    for (final shop in district.shops) {
      if (shop.company case final id?) totals[id.index] += shop.fittings;
    }
  }
  if (world.national case final national?) {
    for (final country in national.countries) {
      for (final block in country.blocks) {
        totals[block.company] += block.fittings;
      }
    }
  }
  return totals;
}

/// On the first of the month: every company's fixed assets wear by a
/// month, charged as depreciation.
void depreciate(WorldState world, ContentDb content, Ledger ledger) {
  final finance = content.finance;
  final wear = List.filled(world.companies.length, Money.zero);
  for (final store in world.stores) {
    final worn = monthsWear(store.fittings, finance.fittingsLifeYears);
    store.fittings -= worn;
    wear[store.company.index] += worn;
  }
  for (final factory in world.factories) {
    final worn = monthsWear(factory.book, finance.plantLifeYears);
    factory.book -= worn;
    wear[factory.company.index] += worn;
  }
  for (final district in world.sleepers) {
    for (final shop in district.shops) {
      final company = shop.company;
      if (company == null) continue;
      final worn = monthsWear(shop.fittings, finance.fittingsLifeYears);
      shop.fittings -= worn;
      wear[company.index] += worn;
    }
  }
  if (world.national case final national?) {
    for (final country in national.countries) {
      for (final block in country.blocks) {
        final worn = monthsWear(block.fittings, finance.fittingsLifeYears);
        block.fittings -= worn;
        wear[block.company] += worn;
      }
    }
  }
  for (final (i, worn) in wear.indexed) {
    if (worn <= Money.zero) continue;
    ledger.post(
      world.companies[i],
      debit: AccountKind.depreciation,
      credit: AccountKind.fixedAssets,
      amount: worn,
      reason: EntryReason.depreciation,
    );
  }
}
