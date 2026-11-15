import '../content/factory_sales_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The save version from which factories come in sizes and sell to other
/// companies: rival producers, tenders and contracts.
const factorySalesVersion = 36;

/// The save version from which rival producers develop their goods and
/// have a capacity, chains build plants, and contracts are indexed,
/// renegotiated and broken.
const contractsVersion = 37;

/// What a rival producer has promised a chain a month, at producer prices,
/// until [ends].
typedef Commitment = ({Money value, Day ends});

/// A rival producer, run by formula: it bids for chains' tenders for its
/// kind of goods in its country at its [discount] on the producer price,
/// raising the discount when it loses to the player and easing it when it
/// wins, and as far as its [capacity] goes. Its goods move toward the lead
/// its development aims at, [aim], which it raises after losing to the
/// player. A chain's own plant is one too, making first its [own] share of
/// its chain's goods.
final class Producer {
  Producer({
    required this.name,
    required this.kind,
    required this.country,
    required this.lead,
    required this.discount,
    this.won = 0,
    Fx? aim,
    this.capacity = Money.zero,
    this.own = Money.zero,
    this.chain,
  }) : aim = aim ?? lead,
       commitments = [];

  Producer.read(StateReader reader)
    : name = reader.readString(),
      kind = FactoryKindId(reader.readInt()),
      country = CountryId(reader.readInt()),
      lead = Fx.raw(reader.readInt()),
      discount = Fx.raw(reader.readInt()),
      won = reader.readInt(),
      aim = Fx.zero,
      capacity = Money.zero,
      own = Money.zero,
      commitments = [] {
    aim = lead;
    if (reader.version < contractsVersion) return;
    aim = Fx.raw(reader.readInt());
    capacity = Money(reader.readInt());
    own = Money(reader.readInt());
    chain = reader.readBool() ? reader.readString() : null;
    for (var i = 0, n = reader.readInt(); i < n; i++) {
      commitments.add((
        value: Money(reader.readInt()),
        ends: Day(reader.readInt()),
      ));
    }
  }

  final String name;
  final FactoryKindId kind;
  final CountryId country;

  /// How far its goods are over the standard, and the lead its development
  /// aims at.
  Fx lead;
  Fx aim;
  Fx discount;

  /// Tenders it has won.
  int won;

  /// What it can make a month, at producer prices; zero until first sized.
  Money capacity;

  /// What its own chain takes of it a month, if it is a chain's plant.
  Money own;

  /// The chain that owns it, if any.
  String? chain;

  /// What it has promised chains, a month each.
  final List<Commitment> commitments;

  /// What it has free a month: its capacity less its chain's share and its
  /// promises running on [day].
  Money freeOn(Day day) {
    var free = capacity - own;
    for (final commitment in commitments) {
      if (day < commitment.ends) free -= commitment.value;
    }
    return free;
  }

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(kind.index)
      ..writeInt(country.index)
      ..writeInt(lead.raw)
      ..writeInt(discount.raw)
      ..writeInt(won)
      ..writeInt(aim.raw)
      ..writeInt(capacity.cents)
      ..writeInt(own.cents)
      ..writeBool(chain != null);
    if (chain case final chain?) writer.writeString(chain);
    writer.writeInt(commitments.length);
    for (final commitment in commitments) {
      writer
        ..writeInt(commitment.value.cents)
        ..writeInt(commitment.ends.number);
    }
  }
}

/// The rival producers [sales] sets out.
List<Producer> initialProducers(FactorySalesDef sales) => [
  for (final def in sales.producers)
    Producer(
      name: def.name,
      kind: def.kind,
      country: def.country,
      lead: def.lead,
      discount: def.discount,
    ),
];

/// A chain's own plant for a kind of goods in a country: it makes [share]
/// of what the chain buys of them, which the chain then doesn't put out to
/// tender, and sells the rest of its capacity as rival [producer].
final class ChainPlant {
  ChainPlant({
    required this.country,
    required this.chain,
    required this.kind,
    required this.share,
    required this.producer,
    required this.built,
  });

  ChainPlant.read(StateReader reader)
    : country = CountryId(reader.readInt()),
      chain = reader.readString(),
      kind = FactoryKindId(reader.readInt()),
      share = Fx.raw(reader.readInt()),
      producer = reader.readInt(),
      built = Day(reader.readInt());

  final CountryId country;
  final String chain;
  final FactoryKindId kind;
  final Fx share;

  /// Its place in the world's producers.
  final int producer;
  final Day built;

  void write(StateWriter writer) {
    writer
      ..writeInt(country.index)
      ..writeString(chain)
      ..writeInt(kind.index)
      ..writeInt(share.raw)
      ..writeInt(producer)
      ..writeInt(built.number);
  }
}

/// Append only.
enum TenderStatus {
  open,

  /// Awarded to the player's factory that bid.
  won,

  /// Awarded to a rival producer.
  lost,

  /// Nobody bid that the chain could take.
  lapsed,
}

/// A chain seeking a supplier for part of what it buys of one product, in
/// one country: so many units a month for so many months, of goods at
/// least so far over the standard. Open until [closes]; the player's
/// factory may bid, and rival producers do.
final class Tender {
  Tender({
    required this.number,
    required this.country,
    required this.chain,
    required this.product,
    required this.units,
    required this.months,
    required this.floor,
    required this.reference,
    required this.opens,
    required this.closes,
    this.status = TenderStatus.open,
    this.bidFactory,
    this.bidPrice,
    this.winner,
    this.winningPrice,
  });

  Tender.read(StateReader reader)
    : number = reader.readInt(),
      country = CountryId(reader.readInt()),
      chain = reader.readString(),
      product = ProductId(reader.readInt()),
      units = reader.readInt(),
      months = reader.readInt(),
      floor = Fx.raw(reader.readInt()),
      reference = Money(reader.readInt()),
      opens = Day(reader.readInt()),
      closes = Day(reader.readInt()),
      status = TenderStatus.values[reader.readInt()],
      bidFactory = switch (reader.readNullableInt()) {
        final index? => FactoryId(index),
        null => null,
      },
      bidPrice = switch (reader.readNullableInt()) {
        final cents? => Money(cents),
        null => null,
      },
      winner = reader.readBool() ? reader.readString() : null,
      winningPrice = switch (reader.readNullableInt()) {
        final cents? => Money(cents),
        null => null,
      };

  final int number;
  final CountryId country;

  /// The chain's name.
  final String chain;
  final ProductId product;

  /// What it wants a month, and for how many months.
  final int units;
  final int months;

  /// The least lead over the standard it asks of the goods.
  final Fx floor;

  /// The producer price when it opened: what bids are weighed against.
  final Money reference;
  final Day opens;
  final Day closes;
  TenderStatus status;

  /// The player's bid, if any: the factory to supply it and its price a
  /// unit.
  FactoryId? bidFactory;
  Money? bidPrice;

  /// Who won it and at what price a unit, once closed: the player's
  /// factory's name, or a rival's.
  String? winner;
  Money? winningPrice;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(country.index)
      ..writeString(chain)
      ..writeInt(product.index)
      ..writeInt(units)
      ..writeInt(months)
      ..writeInt(floor.raw)
      ..writeInt(reference.cents)
      ..writeInt(opens.number)
      ..writeInt(closes.number)
      ..writeInt(status.index)
      ..writeNullableInt(bidFactory?.index)
      ..writeNullableInt(bidPrice?.cents)
      ..writeBool(winner != null);
    if (winner case final winner?) writer.writeString(winner);
    writer.writeNullableInt(winningPrice?.cents);
  }
}

/// A chain's contract with the player's factory: [units] a month of
/// [product] at [price] a unit, delivered on the first of each month from
/// [starts] until [ends].
final class Contract {
  Contract({
    required this.number,
    required this.factory,
    required this.country,
    required this.chain,
    required this.product,
    required this.units,
    required this.price,
    required this.starts,
    required this.ends,
    required this.priceIndex,
    this.delivered = 0,
    this.short = 0,
    this.ended = false,
  });

  Contract.read(StateReader reader)
    : number = reader.readInt(),
      factory = FactoryId(reader.readInt()),
      country = CountryId(reader.readInt()),
      chain = reader.readString(),
      product = ProductId(reader.readInt()),
      units = reader.readInt(),
      price = Money(reader.readInt()),
      starts = Day(reader.readInt()),
      ends = Day(reader.readInt()),
      delivered = reader.readInt(),
      short = reader.readInt(),
      ended = reader.readBool(),
      priceIndex = reader.version >= contractsVersion
          ? Fx.raw(reader.readInt())
          : Fx.zero,
      proposal = reader.version >= contractsVersion
          ? switch (reader.readNullableInt()) {
              final cents? => Money(cents),
              null => null,
            }
          : null,
      answerBy = reader.version >= contractsVersion
          ? switch (reader.readNullableInt()) {
              final day? => Day(day),
              null => null,
            }
          : null;

  /// The number of the tender it came from.
  final int number;
  final FactoryId factory;
  final CountryId country;
  final String chain;
  final ProductId product;
  final int units;

  /// What a unit sells for, indexed to its country's prices each year.
  Money price;
  final Day starts;
  final Day ends;

  /// Its country's price index when [price] was last set; zero for a
  /// contract from an older save, set at its next month.
  Fx priceIndex;

  /// The price the chain asks it be cut to, and the day it puts the rest
  /// out to tender unless agreed.
  Money? proposal;
  Day? answerBy;

  /// Units delivered so far, and short of what was due.
  int delivered;
  int short;

  /// Whether it ended early, its factory closed.
  bool ended;

  /// Whether it is due on [day].
  bool runsOn(Day day) => !ended && starts <= day && day < ends;

  void write(StateWriter writer) {
    writer
      ..writeInt(number)
      ..writeInt(factory.index)
      ..writeInt(country.index)
      ..writeString(chain)
      ..writeInt(product.index)
      ..writeInt(units)
      ..writeInt(price.cents)
      ..writeInt(starts.number)
      ..writeInt(ends.number)
      ..writeInt(delivered)
      ..writeInt(short)
      ..writeBool(ended)
      ..writeInt(priceIndex.raw)
      ..writeNullableInt(proposal?.cents)
      ..writeNullableInt(answerBy?.number);
  }
}
