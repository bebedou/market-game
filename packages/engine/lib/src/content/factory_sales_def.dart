import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';

/// A size of factory against the smallest, a workshop: how many times as
/// much it makes, what building up to it costs, what its shifts are paid
/// and its site costs, and the days enlarging to it takes.
final class FactorySizeDef {
  const FactorySizeDef({
    required this.key,
    required this.name,
    required this.capacity,
    required this.cost,
    required this.wages,
    required this.site,
    required this.buildDays,
  });

  final String key;
  final String name;
  final Fx capacity;
  final Fx cost;
  final Fx wages;
  final Fx site;
  final int buildDays;

  /// The size a scenario without sizes has: a workshop, as kinds are.
  static const workshop = FactorySizeDef(
    key: 'workshop',
    name: 'Workshop',
    capacity: Fx.one,
    cost: Fx.one,
    wages: Fx.one,
    site: Fx.one,
    buildDays: 0,
  );
}

/// How factories sell to companies beyond their owner's: the chains of the
/// countries by formula put out tenders that the owner's factories and
/// rival producers bid for, and independent shops buy at a factory's list
/// price.
final class FactorySalesDef {
  const FactorySalesDef({
    required this.producerPrice,
    required this.tenderChance,
    required this.lotShares,
    required this.termMonths,
    required this.openDays,
    required this.qualityFloors,
    required this.qualityWeight,
    required this.shortfallPenalty,
    required this.reliabilityLoss,
    required this.reliabilityGain,
    required this.reliabilityWeight,
    required this.independentResponse,
    required this.independentMove,
    required this.independentDelivery,
    required this.producerSpread,
    required this.producerPushBack,
    required this.minDiscount,
    required this.maxDiscount,
    required this.resultMonths,
    required this.producers,
    required this.producerCapacity,
    required this.capacityGrowth,
    required this.capacityUse,
    required this.aimPull,
    required this.leadSpread,
    required this.aimResponse,
    required this.minAim,
    required this.maxAim,
    required this.plantChance,
    required this.plantShares,
    required this.plantSpare,
    required this.plantSaving,
    required this.plantDiscount,
    required this.plantMinGoods,
    required this.breakMonths,
    required this.breakReliability,
    required this.drift,
    required this.answerDays,
  });

  /// What chains pay producers, as a share of what wholesalers charge
  /// shops: the price tenders are bid against.
  final Fx producerPrice;

  /// The chance each month that a chain seeks a supplier for one of the
  /// products a factory of the player's makes, in a country one serves.
  final Fx tenderChance;

  /// The share of what a chain buys of the product a tender is for, the
  /// months it runs, and the least lead it asks of the goods, drawn from
  /// these; it stays open [openDays].
  final List<Fx> lotShares;
  final List<int> termMonths;
  final int openDays;
  final List<Fx> qualityFloors;

  /// How much a point of quality counts against a point of price when bids
  /// are compared.
  final Fx qualityWeight;

  /// What a contract month's shortfall costs, as a share of what the
  /// undelivered goods would have sold for; how far a short month lowers a
  /// factory's reliability, as a share of the shortfall, and how far a
  /// full one restores it; and how much a point of unreliability counts
  /// against a bid, as price.
  final Fx shortfallPenalty;
  final Fx reliabilityLoss;
  final Fx reliabilityGain;
  final Fx reliabilityWeight;

  /// The share of independent shops' goods a factory comes to supply for
  /// each unit of discount and quality it offers (0.003: a tenth off wins
  /// three in ten thousand), and the share of the gap to it that closes
  /// each month.
  final Fx independentResponse;
  final Fx independentMove;

  /// What reaching scattered independent shops costs, as a share of what
  /// they pay.
  final Fx independentDelivery;

  /// How far a rival producer's bid wanders either side of its discount,
  /// how far its discount moves when it loses to the player (up) or wins
  /// (down by half), and the bounds of a discount.
  final Fx producerSpread;
  final Fx producerPushBack;
  final Fx minDiscount;
  final Fx maxDiscount;

  /// The months a closed tender is kept, as a guide to what wins.
  final int resultMonths;

  /// The rival producers at the start.
  final List<ProducerDef> producers;

  /// A rival producer's capacity when first sized, as a share of what the
  /// chains of its country buy of its kind of goods a month; how much it
  /// grows a month while used above [capacityUse].
  final Fx producerCapacity;
  final Fx capacityGrowth;
  final Fx capacityUse;

  /// How a producer's goods move: the share of the gap to the lead its
  /// development aims at that closes each month, give or take
  /// [leadSpread]; how far it raises its aim after losing to the player
  /// (and lowers it by a quarter of that after beating them); and the
  /// bounds of an aim.
  final Fx aimPull;
  final Fx leadSpread;
  final Fx aimResponse;
  final Fx minAim;
  final Fx maxAim;

  /// The chance each month that a chain buying at least [plantMinGoods] a
  /// month of a kind of goods builds a plant for them; the share of its
  /// needs such a plant makes, drawn from [plantShares]; the capacity
  /// beyond that it sells to others, as a share of its needs; what making
  /// them itself saves it on those goods; and its discount as a rival.
  final Fx plantChance;
  final List<Fx> plantShares;
  final Fx plantSpare;
  final Fx plantSaving;
  final Fx plantDiscount;
  final Money plantMinGoods;

  /// Breaking a contract costs this many months of it, and this much
  /// reliability.
  final int breakMonths;
  final Fx breakReliability;

  /// How far over what rivals would bid a contract's price must drift
  /// before its chain asks for a cut, and the days it gives for an answer.
  final Fx drift;
  final int answerDays;
}

/// A rival producer: the goods it makes, the country it sells in, how far
/// its goods are over the standard, and its discount on the producer price.
final class ProducerDef {
  const ProducerDef({
    required this.name,
    required this.kind,
    required this.country,
    required this.lead,
    required this.discount,
  });

  final String name;
  final FactoryKindId kind;
  final CountryId country;
  final Fx lead;
  final Fx discount;
}
