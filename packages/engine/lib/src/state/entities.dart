import '../accounting/ledger.dart';
import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';
import 'director.dart';
import 'orders.dart';

/// The player or an AI owner. Personal wealth is separate from the companies
/// the person owns.
final class Person implements LedgerParty {
  Person({
    required this.id,
    required this.name,
    required this.accounts,
    this.bankruptcies = 0,
    this.lastBankruptcy,
  });

  Person.read(this.id, StateReader reader)
    : name = reader.readString(),
      accounts = Accounts.read(reader),
      bankruptcies = reader.readInt(),
      lastBankruptcy = switch (reader.readNullableInt()) {
        final day? => Day(day),
        null => null,
      };

  final PersonId id;
  final String name;

  @override
  final Accounts accounts;

  /// How many of the person's companies have been liquidated.
  int bankruptcies;

  /// When the latest one was, which banks remember for a while.
  Day? lastBankruptcy;

  @override
  PartyRef get partyRef => (type: PartyType.person, index: id.index);

  void write(StateWriter writer) {
    writer.writeString(name);
    accounts.write(writer);
    writer
      ..writeInt(bankruptcies)
      ..writeNullableInt(lastBankruptcy?.number);
  }
}

/// Append only.
enum CompanyStatus { active, liquidated }

/// A company, wholly owned by one person.
/// The days of wages a company's cash cushion holds unless its owner says
/// otherwise, and the most it may.
const defaultCushionDays = 14;
const maxCushionDays = 90;

final class Company implements LedgerParty {
  Company({
    required this.id,
    required this.name,
    required this.owner,
    required this.accounts,
    required this.founded,
    this.status = CompanyStatus.active,
    this.injected = Money.zero,
    this.lossCarried = Money.zero,
    this.cushionDays = defaultCushionDays,
    this.director,
  }) : payables = [],
       memos = [];

  Company.read(this.id, StateReader reader)
    : name = reader.readString(),
      owner = PersonId(reader.readInt()),
      accounts = Accounts.read(reader),
      founded = Day(reader.readInt()),
      status = CompanyStatus.values[reader.readInt()],
      injected = Money(reader.readInt()),
      payables = [
        for (var i = 0, n = reader.readInt(); i < n; i++) Payable.read(reader),
      ],
      lossCarried = reader.version >= 12 ? Money(reader.readInt()) : Money.zero,
      cushionDays = reader.version >= 14
          ? reader.readInt()
          : defaultCushionDays,
      director = reader.version >= 16 && reader.readBool()
          ? Director.read(reader)
          : null,
      memos = [
        if (reader.version >= 16)
          for (var i = 0, n = reader.readInt(); i < n; i++) Memo.read(reader),
      ];

  final CompanyId id;
  String name;

  /// Who owns it, which changes when it is sold.
  PersonId owner;

  @override
  final Accounts accounts;
  final Day founded;
  CompanyStatus status;

  /// Capital the owner has put in, which is lost if the company fails: for
  /// an owner who bought it, the price paid plus capital put in since.
  Money injected;

  /// Unpaid bills, in the order they were billed.
  final List<Payable> payables;

  /// Past losses not yet set against a year's profit for tax.
  Money lossCarried;

  /// How many days of wages its cash cushion holds, on top of a month's
  /// rent and each loan's next payment: see `cashCushion`.
  int cushionDays;

  /// Who runs it for its owner, if anyone.
  Director? director;

  /// What its directors did, oldest first, up to [maxMemos].
  final List<Memo> memos;

  bool get isActive => status == CompanyStatus.active;

  @override
  PartyRef get partyRef => (type: PartyType.company, index: id.index);

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(owner.index);
    accounts.write(writer);
    writer
      ..writeInt(founded.number)
      ..writeInt(status.index)
      ..writeInt(injected.cents)
      ..writeInt(payables.length);
    for (final payable in payables) {
      payable.write(writer);
    }
    writer
      ..writeInt(lossCarried.cents)
      ..writeInt(cushionDays)
      ..writeBool(director != null);
    director?.write(writer);
    writer.writeInt(memos.length);
    for (final memo in memos) {
      memo.write(writer);
    }
  }

  /// Keeps [memo], dropping the oldest beyond [maxMemos].
  void remember(Memo memo) {
    memos.add(memo);
    if (memos.length > maxMemos) memos.removeAt(0);
  }
}

/// A supplier's books. Suppliers are outside the simulation in the
/// prototype, so this is all the state they have.
final class Supplier implements LedgerParty {
  Supplier({required this.id, required this.accounts});

  Supplier.read(this.id, StateReader reader) : accounts = Accounts.read(reader);

  final SupplierId id;

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.supplier, index: id.index);

  void write(StateWriter writer) => accounts.write(writer);
}

/// The households of one market, as one party in the books. Their cash goes
/// negative as they shop until household income exists.
final class Households implements LedgerParty {
  Households({required this.market, required this.accounts});

  Households.read(this.market, StateReader reader)
    : accounts = Accounts.read(reader);

  final MarketId market;

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.households, index: market.index);

  void write(StateWriter writer) => accounts.write(writer);
}

/// The bank, which lends from its reserves and earns interest. It is outside
/// the simulation in the prototype.
final class Bank implements LedgerParty {
  Bank({required this.accounts});

  Bank.read(StateReader reader) : accounts = Accounts.read(reader);

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.bank, index: 0);

  void write(StateWriter writer) => accounts.write(writer);
}

/// Business services outside the simulation; so far, market research firms.
final class Services implements LedgerParty {
  Services({required this.accounts});

  Services.read(StateReader reader) : accounts = Accounts.read(reader);

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.services, index: 0);

  void write(StateWriter writer) => accounts.write(writer);
}

/// The owners of every site, who collect rent and fit out new stores.
/// The state's books: taxes are paid here.
final class Government implements LedgerParty {
  Government({required this.accounts});

  Government.read(StateReader reader) : accounts = Accounts.read(reader);

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.government, index: 0);

  void write(StateWriter writer) => accounts.write(writer);
}

final class Landlords implements LedgerParty {
  Landlords({required this.accounts});

  Landlords.read(StateReader reader) : accounts = Accounts.read(reader);

  @override
  final Accounts accounts;

  @override
  PartyRef get partyRef => (type: PartyType.landlords, index: 0);

  void write(StateWriter writer) => accounts.write(writer);
}
