import '../accounting/ledger.dart';
import '../content/software_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../state/factory.dart' show monthOf;
import '../state/labs.dart' show dailyPay;
import '../state/orders.dart';
import '../state/software.dart';
import '../state/software_rules.dart';
import '../state/talent.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'settlement.dart';
import 'tick_system.dart';

/// Entity keys within [RngStream.software], one range per kind of draw.
const _rivalKeys = 1000000;
const _foundingKey = 2000000;
const _offerKeys = 3000000;

/// Runs the world market for software and the products of software
/// companies.
///
/// Every day, each product's customers pay their share of a month, and its
/// people, offices, marketing and serving those customers are billed to its
/// company. On the first of the month the market turns: the standard rises,
/// every product's people build it further, first versions close enough to
/// the standard go on sale, rivals start up or fold, and the customers who
/// change products that month, with those new to software, go to products
/// by how far ahead they are, their price, their marketing and what their
/// customers say. Runs before settlement, which pays the bills.
final class SoftwareSystem implements TickSystem {
  const SoftwareSystem();

  @override
  void run(WorldState world, TickContext context) {
    final def = context.content.software;
    final market = world.softwareMarket;
    if (def == null || market == null) return;
    final first = context.day.isFirstOfMonth;
    if (first || !world.keyPeople.any((person) => person.forSoftware)) {
      _people(world, context, def, monthly: first);
    }
    if (first) _month(world, context, def, market);
    _bill(world, context, def, market);
  }

  /// The market for software people: candidates there too long are taken,
  /// new ones come until it is full, and those at work count a month.
  void _people(
    WorldState world,
    TickContext context,
    SoftwareDef def, {
    required bool monthly,
  }) {
    var waiting = 0;
    for (final person in world.keyPeople) {
      if (!person.forSoftware) continue;
      switch (person.status) {
        case KeyStatus.candidate:
          if (context.day.number - person.since.number >= def.candidateDays) {
            person.status = KeyStatus.gone;
          } else {
            waiting++;
          }
        case KeyStatus.employed:
          final software = world.software[person.software!.index];
          if (!software.running ||
              !world.companies[software.company.index].isActive) {
            person
              ..status = KeyStatus.gone
              ..software = null;
          } else if (monthly) {
            person.monthsWorked++;
          }
        case KeyStatus.gone:
      }
    }
    for (; waiting < def.candidates; waiting++) {
      final id = KeyPersonId(world.keyPeople.length);
      world.keyPeople.add(
        _candidate(
          def,
          id,
          context.day,
          context.rng(RngStream.software, id.index),
        ),
      );
    }
  }

  void _month(
    WorldState world,
    TickContext context,
    SoftwareDef def,
    SoftwareMarket market,
  ) {
    final day = context.day;
    final reference = softwareReferencePrice(world, def);
    market.standard += def.rise;
    // The players' products.
    for (final software in world.software) {
      if (!software.running) continue;
      if (!world.companies[software.company.index].isActive) {
        closeSoftware(world, market, software, SoftwareStatus.closed);
        continue;
      }
      final power = softwareBuildPower(world, def, software.id);
      software.level += softwareProgress(
        def,
        power,
        software.level - market.standard,
      );
      if (software.status == SoftwareStatus.building &&
          software.level >= market.standard - def.launchGap) {
        software
          ..status = SoftwareStatus.selling
          ..launchedOn = day;
        context.events.add(
          SoftwareLaunched(software: software.id, company: software.company),
        );
      }
      if (software.offer case final offer? when offer.expires < day) {
        software.offer = null;
      }
    }
    // The rivals.
    final leader = _leaderEdge(world, def, market);
    final rest = market.rest;
    for (final rival in market.rivals) {
      if (rival.status == RivalStatus.folded) continue;
      final rng = context.rng(RngStream.software, _rivalKeys + rival.id.index);
      if (!rival.rest) {
        // Its share of the market a month ago against the month before.
        final lost =
            partsOf(rival.customers, market.customers) <
            partsOf(rival.customersBefore, market.customersBefore);
        if (rival.selling && lost) {
          // Losing customers, it puts more into its product, up to what
          // would hold it level with the best.
          final most = steadyPace(def, leader);
          final raised = rival.basePace + def.response;
          rival.basePace = raised < most
              ? raised
              : most > rival.basePace
              ? most
              : rival.basePace;
        }
        final swing =
            (def.paceSpread * rival.basePace) *
            (rng.nextFx().timesInt(2) - Fx.one);
        rival.pace =
            rival.basePace +
            (rival.pace - rival.basePace) * const Fx.raw(8000) +
            swing;
        if (rival.pace.isNegative) rival.pace = Fx.zero;
      }
      final lead = rival.level - market.standard;
      final ahead = lead > Fx.zero ? lead : Fx.zero;
      rival.level += rival.pace.div(Fx.one + def.hardness * ahead);
      if (rival.status == RivalStatus.building &&
          rival.level >= market.standard - def.launchGap) {
        rival
          ..status = RivalStatus.selling
          ..launchedOn = day;
        context.events.add(RivalLaunched(rival: rival.id));
      }
      final startup = rival.id.index >= def.rivals.length;
      if (startup &&
          monthOf(day) - monthOf(rival.founded) >= def.foldMonths &&
          rival.customers < def.foldCustomers) {
        rival.status = RivalStatus.folded;
        rest.customers += rival.customers;
        rival.customers = 0;
        if (rival.launchedOn != null) {
          context.events.add(RivalFolded(rival: rival.id));
        }
      }
    }
    _found(world, context, def, market);
    _turn(world, context, def, market, reference);
    final best = bestRivalLead(market);
    for (final software in world.software) {
      if (!software.running) continue;
      software.record(
        SoftwareMonth(
          day: day,
          customers: software.customers,
          revenue: software.price.timesInt(software.customers),
          lead: software.level - market.standard,
          bestRival: best,
        ),
      );
      _offer(world, context, def, market, software);
    }
  }

  /// The furthest any product selling stands ahead, with its appeal.
  Fx _leaderEdge(WorldState world, SoftwareDef def, SoftwareMarket market) {
    var best = Fx.zero;
    for (final rival in market.rivals) {
      if (!rival.selling) continue;
      final edge = rival.level - market.standard;
      if (edge > best) best = edge;
    }
    for (final software in world.software) {
      if (software.status != SoftwareStatus.selling) continue;
      final edge = software.level - market.standard;
      if (edge > best) best = edge;
    }
    return best;
  }

  /// Now and then a rival starts up, its team drawn as anyone's is.
  void _found(
    WorldState world,
    TickContext context,
    SoftwareDef def,
    SoftwareMarket market,
  ) {
    final rng = context.rng(RngStream.software, _foundingKey);
    if (rng.nextFx() >= def.foundingChance) return;
    final engineers = <Fx>[];
    final designers = <Fx>[];
    for (var i = 0; i < def.startupTeam; i++) {
      final power = def.levels[_drawLevel(def, rng)].power;
      (rng.nextInt(2) == 0 ? engineers : designers).add(power);
    }
    final taken = {for (final rival in market.rivals) rival.name};
    var name = def.startupNames[rng.nextInt(def.startupNames.length)];
    for (var n = 2; taken.contains(name); n++) {
      name = '${def.startupNames[rng.nextInt(def.startupNames.length)]} $n';
    }
    market.rivals.add(
      SoftwareRival(
        id: SoftwareRivalId(market.rivals.length),
        name: name,
        founded: context.day,
        status: RivalStatus.building,
        level: market.standard - def.startGap,
        customers: 0,
        price: def.startupPrice,
        marketingShare: const Fx.raw(1000),
        marketingBudget: def.startupMarketing,
        pace: teamPower(engineers, def.decay) * def.progress,
        basePace: teamPower(engineers, def.decay) * def.progress,
        appeal: softwareAppeal(def, teamPower(designers, def.decay)),
      ),
    );
  }

  /// The month's customers: some of every product's leave, the market grows
  /// or shrinks with the economy, and those choosing go where they are
  /// drawn.
  void _turn(
    WorldState world,
    TickContext context,
    SoftwareDef def,
    SoftwareMarket market,
    Money reference,
  ) {
    market.customersBefore = market.customers;
    for (final rival in market.rivals) {
      rival.customersBefore = rival.customers;
    }
    final demand = softwareDemand(world, context.content);
    final yearly = def.growth - def.cycle * (Fx.one - demand);
    final growth = mulDivRound(market.customers, yearly.raw, Fx.scale * 12);
    // Every product selling, rivals then players', with its customers, its
    // edge, its price and its marketing.
    final products =
        <({int customers, Fx edge, Money price, Money marketing})>[];
    for (final rival in market.rivals) {
      products.add(
        rival.selling
            ? (
                customers: rival.customers,
                edge: rival.level - market.standard + rival.appeal,
                price: reference.times(rival.price),
                marketing:
                    reference
                        .timesInt(rival.customers)
                        .times(rival.marketingShare) +
                    rival.marketingBudget,
              )
            : (
                customers: 0,
                edge: Fx.zero,
                price: reference,
                marketing: Money.zero,
              ),
      );
    }
    for (final software in world.software) {
      final selling = software.status == SoftwareStatus.selling;
      products.add(
        selling
            ? (
                customers: software.customers,
                edge:
                    software.level -
                    market.standard +
                    softwareAppeal(
                      def,
                      softwarePower(world, def, software.id, KeyRole.designer),
                    ),
                price: software.price,
                marketing: software.marketing,
              )
            : (
                customers: 0,
                edge: Fx.zero,
                price: reference,
                marketing: Money.zero,
              ),
      );
    }
    final leaving = List.filled(products.length, 0);
    final weights = List.filled(products.length, 0);
    var pool = growth;
    var total = 0;
    for (final (i, product) in products.indexed) {
      final selling = i < market.rivals.length
          ? market.rivals[i].selling
          : world.software[i - market.rivals.length].status ==
                SoftwareStatus.selling;
      if (!selling) continue;
      final churn = softwareChurn(def, product.edge, product.price, reference);
      leaving[i] = mulDivRound(product.customers, churn.raw, Fx.scale);
      pool += leaving[i];
      weights[i] = softwareWeight(
        softwareReach(def, product.marketing, product.customers),
        softwarePull(def, product.edge),
        softwarePriceDraw(def, product.price, reference),
      );
      total += weights[i];
    }
    if (pool < 0) pool = 0;
    final gains = total > 0
        ? shareOut(pool, weights)
        : List.filled(products.length, 0);
    final placed = gains.fold(0, (sum, gain) => sum + gain);
    final restIndex = market.rest.id.index;
    // What rounding leaves, and a shrinking market's losses beyond its
    // leavers, fall to everyone else.
    gains[restIndex] += pool - placed;
    for (var i = 0; i < products.length; i++) {
      final after = products[i].customers - leaving[i] + gains[i];
      if (i < market.rivals.length) {
        market.rivals[i].customers = after;
      } else {
        world.software[i - market.rivals.length].customers = after;
      }
    }
    market.customers = 0;
    for (final rival in market.rivals) {
      if (rival.customers < 0) {
        // Only everyone else can run short, in a market shrinking fast.
        rival.customers = 0;
      }
      market.customers += rival.customers;
    }
    for (final software in world.software) {
      market.customers += software.customers;
    }
  }

  /// Now and then the biggest rival offers to buy a software company that
  /// sells enough, for what it is worth and a premium.
  void _offer(
    WorldState world,
    TickContext context,
    SoftwareDef def,
    SoftwareMarket market,
    Software software,
  ) {
    if (software.status != SoftwareStatus.selling || software.offer != null) {
      return;
    }
    if (software.price.timesInt(software.customers) < def.offerRevenue) return;
    final rng = context.rng(RngStream.software, _offerKeys + software.id.index);
    if (rng.nextFx() >= def.offerChance) return;
    SoftwareRival? buyer;
    for (final rival in market.rivals) {
      if (!rival.selling || rival.rest) continue;
      if (buyer == null || rival.customers > buyer.customers) buyer = rival;
    }
    if (buyer == null) return;
    final worth = softwareWorth(world, context.content, def, software).worth;
    final premium =
        def.minPremium + (def.maxPremium - def.minPremium) * rng.nextFx();
    final price = worth.times(premium);
    if (price <= Money.zero) return;
    software.offer = SoftwareOffer(
      rival: buyer.id,
      price: price,
      expires: context.day + def.offerDays,
    );
    context.events.add(
      SoftwareOfferMade(
        software: software.id,
        company: software.company,
        rival: buyer.id,
        price: price,
      ),
    );
  }

  /// A day of every running product: its customers pay, and its costs are
  /// billed.
  void _bill(
    WorldState world,
    TickContext context,
    SoftwareDef def,
    SoftwareMarket market,
  ) {
    final day = context.day;
    final days = daysInMonth(day.date.year, day.date.month);
    for (final software in world.software) {
      if (!software.running) continue;
      final company = world.companies[software.company.index];
      if (!company.isActive) continue;
      final revenue = Money(
        mulDivRound(software.price.cents, software.customers, days),
      );
      if (revenue > Money.zero) {
        context.ledger.pay(
          payer: world.elsewhere,
          payerAccount: AccountKind.spending,
          payee: company,
          payeeAccount: AccountKind.revenue,
          amount: revenue,
          reason: EntryReason.subscription,
        );
      }
      void charge(
        AccountKind account,
        EntryReason reason,
        Money amount, {
        bool services = true,
      }) {
        if (amount <= Money.zero) return;
        bill(
          context.ledger,
          company,
          account,
          Payable(
            creditor: services
                ? world.services.partyRef
                : world.elsewhere.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: reason,
            amount: amount,
            due: day,
          ),
        );
      }

      charge(
        AccountKind.spending,
        EntryReason.serving,
        revenue.times(def.serving),
      );
      // Marketing starts with the first version: before, there is nothing
      // to sell.
      if (software.status == SoftwareStatus.selling) {
        charge(
          AccountKind.marketing,
          EntryReason.marketing,
          Money(mulDivRound(software.marketing.cents, 1, days)),
        );
      }
      charge(
        AccountKind.spending,
        EntryReason.office,
        Money(mulDivRound(softwareOffice(world, def, software).cents, 1, days)),
      );
      final level = softwareWageLevel(world, context.content, software.country);
      for (final person in softwarePeople(world, software.id)) {
        charge(
          AccountKind.salaries,
          EntryReason.salary,
          dailyPay(softwareSalary(def, person, level)),
          services: false,
        );
      }
    }
  }
}

/// Ends [software] with [status]: its people leave and its customers go to
/// [to], or to everyone else.
void closeSoftware(
  WorldState world,
  SoftwareMarket market,
  Software software,
  SoftwareStatus status, {
  SoftwareRival? to,
}) {
  for (final person in softwarePeople(world, software.id)) {
    person
      ..status = KeyStatus.gone
      ..software = null;
  }
  (to ?? market.rest).customers += software.customers;
  software
    ..customers = 0
    ..offer = null
    ..status = status;
}

/// A level drawn as common as [def] has them.
int _drawLevel(SoftwareDef def, Rng rng) {
  var draw = rng.nextFx();
  var level = 0;
  while (level < def.levels.length - 1 && draw >= def.levels[level].share) {
    draw -= def.levels[level++].share;
  }
  return level;
}

/// A candidate for software work drawn from [rng], as a lab's are: a role, a
/// level as common as [def] has it, and a repute that is right half the
/// time, a level short a quarter and a level over a quarter.
KeyPerson _candidate(SoftwareDef def, KeyPersonId id, Day day, Rng rng) {
  final role = KeyRole.values[rng.nextInt(KeyRole.values.length)];
  final level = _drawLevel(def, rng);
  var repute = level + const [-1, 0, 0, 1][rng.nextInt(4)];
  if (repute < 0) repute = 0;
  if (repute >= def.levels.length) repute = def.levels.length - 1;
  final first = def.firstNames[rng.nextInt(def.firstNames.length)];
  final last = def.lastNames[rng.nextInt(def.lastNames.length)];
  return KeyPerson(
    id: id,
    name: '$first $last',
    role: role,
    level: level,
    repute: repute,
    since: day,
    forSoftware: true,
  );
}
