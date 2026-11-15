import '../content/factory_sales_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// The save version from which factories come in sizes and sell to other
/// companies: rival producers, tenders and contracts.
const factorySalesVersion = 36;

/// A rival producer, run by formula: it bids for chains' tenders for its
/// kind of goods in its country at its [discount] on the producer price,
/// raising the discount when it loses to the player and easing it when it
/// wins.
final class Producer {
  Producer({
    required this.name,
    required this.kind,
    required this.country,
    required this.lead,
    required this.discount,
    this.won = 0,
  });

  Producer.read(StateReader reader)
    : name = reader.readString(),
      kind = FactoryKindId(reader.readInt()),
      country = CountryId(reader.readInt()),
      lead = Fx.raw(reader.readInt()),
      discount = Fx.raw(reader.readInt()),
      won = reader.readInt();

  final String name;
  final FactoryKindId kind;
  final CountryId country;

  /// How far its goods are over the standard.
  final Fx lead;
  Fx discount;

  /// Tenders it has won.
  int won;

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(kind.index)
      ..writeInt(country.index)
      ..writeInt(lead.raw)
      ..writeInt(discount.raw)
      ..writeInt(won);
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
      ended = reader.readBool();

  /// The number of the tender it came from.
  final int number;
  final FactoryId factory;
  final CountryId country;
  final String chain;
  final ProductId product;
  final int units;
  final Money price;
  final Day starts;
  final Day ends;

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
      ..writeBool(ended);
  }
}
