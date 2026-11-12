import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The chart of accounts, shared by every party.
///
/// Balances are stored debit-positive: assets and expenses are normally
/// positive; liabilities, equity and income normally negative. Append only:
/// saves store balances in this order.
enum AccountKind {
  cash,
  inventory,
  payables,
  equity,
  revenue,
  costOfGoods,

  /// Assets lost: spoiled or abandoned stock, loans that won't be repaid,
  /// investments in failed companies, guarantees paid.
  writeOffs,
  spending,

  /// Borrowed money owed (negative), or for the bank, lent money due back.
  loans,
  rent,
  interest,

  /// Fitting out a new store.
  openingCosts,

  /// Capital a person has put into companies.
  investments,

  /// Profit paid out to the owner: a debit for the company, income for the
  /// owner.
  dividends,

  /// Debts a liquidated company never paid, written off by its creditors.
  debtRelief,

  /// Pay for store staff: an expense for companies, income for households.
  wages,
  research,

  /// Pay for store managers: an expense for companies, income for
  /// households.
  salaries,

  /// Advertising: an expense for companies, income for services.
  marketing,

  /// Corporate tax for companies, dividend and capital gains tax for
  /// persons.
  taxes,

  /// What a company paid for stores it bought beyond their stock: their
  /// fittings and custom, an asset until it sells them.
  businessAssets,

  /// Gains on selling stores or companies (income), or losses.
  disposals,

  /// Energy, insurance, upkeep and card fees: an expense for companies,
  /// income for services.
  overheads,

  /// What buyers owe a company's factories for goods delivered.
  receivables,

  /// What a company's factories made for its owner's shops, at what the
  /// wholesalers would have charged them: income, kept apart from sales.
  ownGoods,
}

/// Accounts there were before saves recorded how many.
const int _accountsBeforeCount = 18;

/// One party's account balances. Only a [Ledger] changes them.
final class Accounts {
  Accounts() : _balances = List.filled(AccountKind.values.length, Money.zero);

  /// Opening books: [cash] in hand and [investments] in companies,
  /// balanced by equity.
  factory Accounts.opening(Money cash, {Money investments = Money.zero}) =>
      Accounts()
        .._balances[AccountKind.cash.index] = cash
        .._balances[AccountKind.investments.index] = investments
        .._balances[AccountKind.equity.index] = -(cash + investments);

  Accounts.read(StateReader reader) : _balances = readBalances(reader);

  /// Balances per [AccountKind] as written by [writeBalances], those of
  /// accounts added since zero.
  static List<Money> readBalances(StateReader reader) {
    final count = reader.version >= 10
        ? reader.readInt()
        : _accountsBeforeCount;
    return [
      for (var i = 0; i < count; i++) Money(reader.readInt()),
      for (var i = count; i < AccountKind.values.length; i++) Money.zero,
    ];
  }

  static void writeBalances(StateWriter writer, List<Money> balances) {
    writer.writeInt(balances.length);
    for (final balance in balances) {
      writer.writeInt(balance.cents);
    }
  }

  final List<Money> _balances;

  Money operator [](AccountKind kind) => _balances[kind.index];

  /// The sum of all balances: zero whenever the books balance.
  Money get total => _balances.fold(Money.zero, (sum, value) => sum + value);

  /// What is owned minus what is owed.
  Money get netAssets =>
      this[AccountKind.cash] +
      this[AccountKind.inventory] +
      this[AccountKind.receivables] +
      this[AccountKind.businessAssets] +
      this[AccountKind.investments] +
      this[AccountKind.payables] +
      this[AccountKind.loans];

  /// Profit kept since the start: net assets beyond the capital put in.
  Money get retainedEarnings => netAssets + this[AccountKind.equity];

  void write(StateWriter writer) => writeBalances(writer, _balances);
}

enum PartyType {
  person,
  company,
  supplier,
  households,
  bank,
  landlords,
  services,

  /// The state, which collects taxes.
  government,

  /// Everyone beyond the districts played in full: see `Elsewhere`.
  elsewhere,
}

/// Who a journal entry belongs to: a party type and its index.
typedef PartyRef = ({PartyType type, int index});

/// Anything with its own books.
abstract interface class LedgerParty {
  PartyRef get partyRef;
  Accounts get accounts;
}

enum EntryReason {
  delivery,
  supplierPayment,
  sale,
  costOfSale,
  spoilage,
  delisting,
  loan,
  loanRepayment,
  interest,
  rent,
  openingCosts,
  capitalInjection,
  dividend,

  /// Stock written off when a store closes.
  closure,

  /// Debts settled or written off when a company is liquidated.
  liquidation,

  /// A guarantor paying a liquidated company's loan.
  guaranteeCall,
  wages,
  research,
  salary,

  /// Building works enlarging a store.
  expansion,

  /// A store's daily marketing budget.
  marketing,

  /// A company's tax on last year's profit.
  corporateTax,

  /// An owner's tax on a dividend.
  dividendTax,

  /// A store changing hands, for its stock and the rest of its price.
  storeSale,

  /// A company changing hands.
  companySale,

  /// An owner's tax on the gain from selling a company.
  capitalGainsTax,

  /// A store's energy, insurance, upkeep and card fees for the month.
  overheads,

  /// A factory's goods delivered to a shop.
  factorySale,

  /// What a factory's goods took to make.
  materials,

  /// Carrying a factory's goods to another country.
  freight,
}

/// One double-entry posting in one party's books. [store], [product] and
/// [units] say what the money was for, so reports can explain it.
final class JournalEntry {
  const JournalEntry({
    required this.day,
    required this.party,
    required this.debit,
    required this.credit,
    required this.amount,
    required this.reason,
    this.store,
    this.product,
    this.units = 0,
    this.factory,
  });

  final Day day;
  final PartyRef party;
  final AccountKind debit;
  final AccountKind credit;
  final Money amount;
  final EntryReason reason;
  final StoreId? store;
  final ProductId? product;
  final int units;

  /// The factory it was for, if any.
  final FactoryId? factory;

  @override
  String toString() =>
      '${day.toIsoString()} ${party.type.name}#${party.index} '
      '${reason.name}: Dr ${debit.name} / Cr ${credit.name} '
      '${amount.toDecimalString()}';
}

/// Posts one day's journal entries. Every money movement goes through here.
///
/// Each entry stays within one party's books. Cash only changes hands
/// through [pay], which posts a matching entry on each side, so the total
/// cash in the world never changes.
final class Ledger {
  Ledger(this.day);

  final Day day;
  final List<JournalEntry> entries = [];

  /// An entry within [party]'s books that doesn't touch cash.
  void post(
    LedgerParty party, {
    required AccountKind debit,
    required AccountKind credit,
    required Money amount,
    required EntryReason reason,
    StoreId? store,
    ProductId? product,
    int units = 0,
    FactoryId? factory,
  }) {
    assert(
      debit != AccountKind.cash && credit != AccountKind.cash,
      'Cash only moves through pay()',
    );
    _record(
      party,
      debit,
      credit,
      amount,
      reason,
      store,
      product,
      units,
      factory,
    );
  }

  /// Cash moving from [payer] to [payee]. The payer debits [payerAccount]
  /// (what the money was spent on); the payee credits [payeeAccount] (what it
  /// was earned from).
  void pay({
    required LedgerParty payer,
    required AccountKind payerAccount,
    required LedgerParty payee,
    required AccountKind payeeAccount,
    required Money amount,
    required EntryReason reason,
    StoreId? store,
    ProductId? product,
    int units = 0,
    FactoryId? factory,
  }) {
    _record(
      payer,
      payerAccount,
      AccountKind.cash,
      amount,
      reason,
      store,
      product,
      units,
      factory,
    );
    _record(
      payee,
      AccountKind.cash,
      payeeAccount,
      amount,
      reason,
      store,
      product,
      units,
      factory,
    );
  }

  void _record(
    LedgerParty party,
    AccountKind debit,
    AccountKind credit,
    Money amount,
    EntryReason reason,
    StoreId? store,
    ProductId? product,
    int units,
    FactoryId? factory,
  ) {
    assert(!amount.isNegative, 'Entries are never negative: $amount');
    final balances = party.accounts._balances;
    balances[debit.index] += amount;
    balances[credit.index] -= amount;
    entries.add(
      JournalEntry(
        day: day,
        party: party.partyRef,
        debit: debit,
        credit: credit,
        amount: amount,
        reason: reason,
        store: store,
        product: product,
        units: units,
        factory: factory,
      ),
    );
  }
}
