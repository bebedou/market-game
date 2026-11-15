import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/factory_sales.dart';
import '../state/world_state.dart';
import '../systems/factory_sales.dart';
import '../systems/national.dart' show gameCountry;

/// A chain's contract with one of the player's factories.
typedef ContractView = ({
  int number,
  String chain,
  CountryId country,
  ProductId product,
  int units,
  Money price,
  Day starts,
  Day ends,
  int delivered,
  int short,
  bool ended,

  /// The price its chain asks it be cut to, and until when; null if none.
  Money? proposal,
  Day? answerBy,

  /// The day its price next follows its country's prices.
  Day nextIndexation,
});

/// A rival producer, as anyone sees it.
typedef ProducerView = ({
  String name,

  /// The chain whose plant it is, if any.
  String? chain,
  FactoryKindId kind,
  CountryId country,

  /// How far its goods are over the standard.
  Fx lead,

  /// The share of its capacity in use.
  Fx busy,
  int won,
});

/// Every rival producer, as anyone sees it.
List<ProducerView> producerViews(WorldState world) => List.unmodifiable([
  for (final producer in world.producers)
    (
      name: producer.name,
      chain: producer.chain,
      kind: producer.kind,
      country: producer.country,
      lead: producer.lead,
      busy: producer.capacity <= Money.zero
          ? Fx.zero
          : Fx.raw(
              mulDivRound(
                (producer.capacity - producer.freeOn(world.today)).cents,
                Fx.scale,
                producer.capacity.cents,
              ),
            ),
      won: producer.won,
    ),
]);

/// A chain's tender, open or lately closed, as anyone sees it, with the
/// player's bid.
typedef TenderView = ({
  int number,
  CountryId country,
  String chain,
  ProductId product,
  int units,
  int months,
  Fx floor,

  /// The producer price when it opened, what bids are weighed against.
  Money reference,
  Day opens,
  Day closes,
  TenderStatus status,
  FactoryId? bidFactory,
  Money? bidPrice,
  String? winner,
  Money? winningPrice,
});

/// One of a factory's products as it sells to chains: what wholesalers
/// charge, the producer price chains pay, what a unit costs it to make at
/// full use of its shifts, and how far it is over the standard.
typedef SalesLine = ({
  ProductId product,
  Money wholesale,
  Money producerPrice,
  Money unitCost,
  Fx lead,
});

/// How one of the player's factories sells to other companies.
final class FactorySalesView {
  const FactorySalesView({
    required this.size,
    required this.enlargedOn,
    required this.enlargeCost,
    required this.reliability,
    required this.independentShare,
    required this.contracts,
    required this.committed,
    required this.lines,
    required this.market,
  });

  /// Its size, by index into the scenario's sizes; the day works enlarging
  /// it end, if under way; and what enlarging it to the next size would
  /// cost, null at the largest.
  final int size;
  final Day? enlargedOn;
  final Money? enlargeCost;

  /// How reliably it has delivered its contracts, from 0 to 1.
  final Fx reliability;

  /// The share of independent shops' goods it supplies, in millionths.
  final int independentShare;

  /// Its contracts, running and lately ended, in the order won.
  final List<ContractView> contracts;

  /// The units a month its running contracts take.
  final int committed;
  final List<SalesLine> lines;

  /// What shops in the countries it serves spend a month on goods it makes:
  /// every chain's and the independents'.
  final Money market;
}

/// The first anniversary of [starts] after [today].
Day _nextAnniversary(Day starts, Day today) {
  var month = monthOf(starts) + 12;
  while (Day.fromDate(month ~/ 12, month % 12 + 1, 1) <= today) {
    month += 12;
  }
  return Day.fromDate(month ~/ 12, month % 12 + 1, 1);
}

/// Every tender kept, as anyone sees it.
List<TenderView> tenderViews(WorldState world) => List.unmodifiable([
  for (final tender in world.tenders)
    (
      number: tender.number,
      country: tender.country,
      chain: tender.chain,
      product: tender.product,
      units: tender.units,
      months: tender.months,
      floor: tender.floor,
      reference: tender.reference,
      opens: tender.opens,
      closes: tender.closes,
      status: tender.status,
      bidFactory: tender.bidFactory,
      bidPrice: tender.bidPrice,
      winner: tender.winner,
      winningPrice: tender.winningPrice,
    ),
]);

/// How [factory] sells to other companies, or null if the scenario has no
/// such sales.
FactorySalesView? factorySalesView(
  WorldState world,
  ContentDb content,
  Factory factory,
) {
  final factories = content.factories!;
  final sales = factories.sales;
  if (sales == null) return null;
  final kind = factories.sized(factory.kind, factory.size);
  final today = world.today;
  final next = factory.size + 1;
  final economy = world.macroOf(factory.country);
  // A unit's cost at full use of its shifts, at least one.
  final shifts = factory.shifts > 0 ? factory.shifts : 1;
  final days = daysInMonth(today.date.year, today.date.month);
  final capacity = kind.shiftUnits * shifts * days;
  final running =
      kind.shiftWage
          .times(economy.wageIndex)
          .times(content.countries[factory.country.index].service)
          .timesInt(shifts * days) +
      kind.site.times(economy.priceIndex);
  final perUnit = capacity <= 0 ? Money.zero : Money(running.cents ~/ capacity);
  var market = Money.zero;
  final national = world.national;
  if (national != null) {
    for (final (n, country) in national.countries.indexed) {
      final game = gameCountry(content, n);
      if (game == null || !factory.servesCountry(game)) continue;
      for (final chain in country.chains) {
        if (chain.boughtBy != null) continue;
        final goods = chain.months.lastOrNull?.goods ?? Money.zero;
        final trade = national.table.trades[chain.def.trade].key;
        for (final product in content.products) {
          if (!kindMakes(kind, product)) continue;
          market += goods.times(tradeProductShare(content, trade, product));
        }
      }
    }
  }
  final contracts = [
    for (final contract in world.contracts)
      if (contract.factory == factory.id) contract,
  ];
  return FactorySalesView(
    size: factory.size,
    enlargedOn: factory.enlargedOn,
    enlargeCost: next >= factories.sizes.length
        ? null
        : (factories.sized(factory.kind, next).buildCost - kind.buildCost)
              .times(economy.priceIndex),
    reliability: factory.reliability,
    independentShare: factory.independentShare,
    contracts: List.unmodifiable([
      for (final contract in contracts)
        (
          number: contract.number,
          chain: contract.chain,
          country: contract.country,
          product: contract.product,
          units: contract.units,
          price: contract.price,
          starts: contract.starts,
          ends: contract.ends,
          delivered: contract.delivered,
          short: contract.short,
          ended: contract.ended,
          proposal: contract.proposal,
          answerBy: contract.answerBy,
          nextIndexation: _nextAnniversary(contract.starts, world.today),
        ),
    ]),
    committed: contracts
        .where((contract) => !contract.ended && today < contract.ends)
        .fold(0, (sum, contract) => sum + contract.units),
    lines: List.unmodifiable([
      for (final product in content.products)
        if (kindMakes(kind, product))
          () {
            final wholesale = wholesalePrice(
              world,
              content,
              factory.country,
              product,
            );
            return (
              product: product.id,
              wholesale: wholesale,
              producerPrice: wholesale.times(sales.producerPrice),
              unitCost:
                  materialsCost(
                    kind,
                    product,
                    economy.priceIndex,
                    saved: factorySaving(world, factory, product.id),
                  ) +
                  perUnit,
              lead: factoryLead(world, factory, product.id),
            );
          }(),
    ]),
    market: market,
  );
}
