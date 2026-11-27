import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../content/software_def.dart';
import '../core/exp_neg.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'factory.dart' show FactoryStatus;
import 'stocks.dart';
import 'software.dart';
import 'store.dart' show StoreStatus;
import 'talent.dart';
import 'world_state.dart';

/// The key people building [software], in the order hired.
List<KeyPerson> softwarePeople(WorldState world, SoftwareId software) => [
  for (final person in world.keyPeople)
    if (person.status == KeyStatus.employed && person.software == software)
      person,
];

/// What a team of [powers] adds up to: the best counts in full, and each
/// next one [decay] of the one before, as more people must agree on more.
Fx teamPower(List<Fx> powers, Fx decay) {
  final sorted = List.of(powers)..sort((a, b) => b.raw.compareTo(a.raw));
  var total = Fx.zero;
  var weight = Fx.one;
  for (final power in sorted) {
    total += power * weight;
    weight = weight * decay;
  }
  return total;
}

/// What [software]'s people of [role] add up to, at their true levels or,
/// with [shown], as their employer takes them to be.
Fx softwarePower(
  WorldState world,
  SoftwareDef def,
  SoftwareId software,
  KeyRole role, {
  bool shown = false,
}) => teamPower([
  for (final person in softwarePeople(world, software))
    if (person.role == role)
      def
          .levels[shown ? person.shownLevel(def.revealMonths) : person.level]
          .power,
], def.decay);

/// What [software]'s whole team builds with: its engineers in full and its
/// designers at [SoftwareDef.designerBuild], the best first.
Fx softwareBuildPower(
  WorldState world,
  SoftwareDef def,
  SoftwareId software, {
  bool shown = false,
}) => teamPower([
  for (final person in softwarePeople(world, software))
    def
            .levels[shown ? person.shownLevel(def.revealMonths) : person.level]
            .power *
        (person.role == KeyRole.designer ? def.designerBuild : Fx.one),
], def.decay);

/// The level a month of [power]'s work adds to a product [lead] ahead of
/// the standard: less the further ahead it is.
Fx softwareProgress(SoftwareDef def, Fx power, Fx lead) {
  final ahead = lead > Fx.zero ? lead : Fx.zero;
  return (power * def.progress).div(Fx.one + def.hardness * ahead);
}

/// What designers of [power] add to a product, as lead.
Fx softwareAppeal(SoftwareDef def, Fx power) => power * def.appeal;

/// e to the power of [x], kept between e^-[limit] and e^[limit].
Fx expSigned(Fx x, Fx limit) {
  final kept = x > limit
      ? limit
      : x < -limit
      ? -limit
      : x;
  return kept.isNegative ? expNeg(-kept) : Fx.one.div(expNeg(kept));
}

/// How strongly a product [edge] ahead (its lead and its appeal) draws the
/// customers who change products.
Fx softwarePull(SoftwareDef def, Fx edge) {
  var x = def.draw * edge;
  if (x > def.drawCap) x = def.drawCap;
  if (x < def.drawFloor) x = def.drawFloor;
  return x.isNegative ? expNeg(-x) : Fx.one.div(expNeg(x));
}

/// [price] against the market's [reference], kept between a quarter and
/// four times.
Fx _priceRatio(Money price, Money reference) {
  if (price <= Money.zero || reference <= Money.zero) return Fx.one;
  var ratio = Fx.raw(mulDivRound(price.cents, Fx.scale, reference.cents));
  if (ratio < const Fx.raw(2500)) ratio = const Fx.raw(2500);
  if (ratio > const Fx.raw(40000)) ratio = const Fx.raw(40000);
  return ratio;
}

/// How a product at [price] draws against one at the market's [reference].
Fx softwarePriceDraw(SoftwareDef def, Money price, Money reference) {
  final cheaper = Fx.one.div(_priceRatio(price, reference));
  var draw = Fx.one;
  for (var i = 0; i < def.priceElasticity; i++) {
    draw = draw * cheaper;
  }
  return draw;
}

/// The share of its customers a product [edge] ahead at [price] loses a
/// month.
Fx softwareChurn(SoftwareDef def, Fx edge, Money price, Money reference) {
  final kept = expSigned(-(def.churnSteepness * edge), Fx.fromInt(3));
  var churn = def.churn * kept * _priceRatio(price, reference);
  if (churn < def.minChurn) churn = def.minChurn;
  if (churn > def.maxChurn) churn = def.maxChurn;
  return churn;
}

/// How many people a product reaches a month spending [marketing]: each
/// euro more reaches fewer.
int softwareReach(SoftwareDef def, Money marketing) => marketing > Money.zero
    ? isqrt(marketing.cents) * isqrt(def.marketingScale.cents)
    : 0;

/// How strongly a product [edge] ahead at [price] draws those choosing:
/// its pull times its price's draw.
Fx softwareDraw(SoftwareDef def, Fx edge, Money price, Money reference) =>
    softwarePull(def, edge) * softwarePriceDraw(def, price, reference);

/// A product of the software market as the month's turn weighs it: its
/// customers, its edge (its lead and its appeal), its price and its
/// marketing, and whether it sells.
typedef SoftwareProduct = ({
  int customers,
  Fx edge,
  Money price,
  Money marketing,
  bool selling,
});

/// Every product of [world]'s software market, rivals then players', at
/// the market's [reference] price.
List<SoftwareProduct> softwareProducts(
  WorldState world,
  SoftwareDef def,
  Money reference,
) {
  final market = world.softwareMarket!;
  final SoftwareProduct none = (
    customers: 0,
    edge: Fx.zero,
    price: reference,
    marketing: Money.zero,
    selling: false,
  );
  return [
    for (final rival in market.rivals)
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
              selling: true,
            )
          : none,
    for (final software in world.software)
      software.status == SoftwareStatus.selling
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
              selling: true,
            )
          : none,
  ];
}

/// What the selling [products]' customers use draws on average, each
/// counted by its customers; one in a market without any.
Fx softwareUsualOf(
  SoftwareDef def,
  List<SoftwareProduct> products,
  Money reference,
) {
  final all = products.fold(
    0,
    (sum, product) => product.selling ? sum + product.customers : sum,
  );
  if (all <= 0) return Fx.one;
  var usual = 0;
  for (final product in products) {
    if (!product.selling) continue;
    final draw = softwareDraw(def, product.edge, product.price, reference);
    usual += partsOf(product.customers, all) * draw.raw;
  }
  final mean = Fx.raw(usual ~/ 100000);
  return mean > Fx.zero ? mean : Fx.one;
}

/// The customers [reach] people win a month for a product that [draw]s
/// against the market's [usual]. An advert carries how a product compares
/// less than its customers do: by the square root of its draw against the
/// usual.
int softwareWon(SoftwareDef def, int reach, Fx draw, Fx usual) {
  if (reach <= 0 || draw <= Fx.zero) return 0;
  final against = mulDivRound(draw.raw, Fx.scale, usual.raw);
  final carried = isqrt(against * Fx.scale);
  return mulDivRound(reach, carried, Fx.scale) ~/ def.reachPerCustomer;
}

/// What a customer pays a month on average, at today's prices.
Money softwareReferencePrice(WorldState world, SoftwareDef def) =>
    def.price.times(world.macro.priceIndex);

/// What the economy's demand stands at for the world market: the shared
/// cycle's regime, or the first country's.
Fx softwareDemand(WorldState world, ContentDb content) {
  final regime = world.cycle?.regime ?? world.macro.regime;
  return content.macro.regimes[regime.index].demand;
}

/// Wages in [country] against the first country's at the start.
Fx softwareWageLevel(WorldState world, ContentDb content, CountryId country) =>
    world.macroOf(country).wageIndex * content.countries[country.index].service;

/// What [person] asks a month as software people go, at [wageLevel].
Money softwareSalary(SoftwareDef def, KeyPerson person, Fx wageLevel) =>
    def.levels[person.repute].salary.times(wageLevel);

/// What [software]'s team costs a month.
Money softwarePayroll(
  WorldState world,
  ContentDb content,
  SoftwareDef def,
  Software software,
) {
  final level = softwareWageLevel(world, content, software.country);
  return softwarePeople(
    world,
    software.id,
  ).fold(Money.zero, (sum, person) => sum + softwareSalary(def, person, level));
}

/// What [software]'s offices cost a month, for its team.
/// What a month leaves [software] after its costs, as things stand: its
/// customers' payments less serving them, its marketing once selling, its
/// office and its team.
Money softwareMonthProfit(
  WorldState world,
  ContentDb content,
  SoftwareDef def,
  Software software,
) {
  final revenue = software.price.timesInt(software.customers);
  final marketing = software.status == SoftwareStatus.selling
      ? software.marketing
      : Money.zero;
  return revenue -
      revenue.times(def.serving) -
      marketing -
      softwareOffice(world, def, software) -
      softwarePayroll(world, content, def, software);
}

Money softwareOffice(WorldState world, SoftwareDef def, Software software) =>
    def.office
        .timesInt(softwarePeople(world, software.id).length)
        .times(world.macroOf(software.country).priceIndex);

/// The lead of the best rival selling, or zero if none is.
Fx bestRivalLead(SoftwareMarket market) {
  Fx? best;
  for (final rival in market.rivals) {
    if (!rival.selling || rival.rest) continue;
    final lead = rival.level - market.standard;
    if (best == null || lead > best) best = lead;
  }
  return best ?? Fx.zero;
}

/// The software market's yearly growth in customers in a normal year, with
/// [customers] already: [SoftwareDef.growth] slowing in proportion as they
/// fill the market's [SoftwareDef.ceiling], none at or past it.
Fx softwareTrend(SoftwareDef def, int customers) {
  if (customers >= def.ceiling) return Fx.zero;
  return def.growth *
      Fx.raw(mulDivRound(def.ceiling - customers, Fx.scale, def.ceiling));
}

/// [software]'s yearly growth in customers, from its record: against a
/// year before, or, younger, against its first month with customers,
/// scaled to a year. Zero with too little to go on.
Fx softwareGrowth(Software software) {
  final history = software.history;
  if (history.isEmpty || software.customers <= 0) return Fx.zero;
  final now = software.customers;
  final back = history.length >= 13 ? history.length - 13 : 0;
  var from = back;
  while (from < history.length && history[from].customers <= 0) {
    from++;
  }
  if (from >= history.length) return Fx.zero;
  final then = history[from].customers;
  final months = history.length - from;
  if (months <= 0) return Fx.zero;
  final ratio = Fx.raw(mulDivRound(now, Fx.scale, then)) - Fx.one;
  return months >= 12 ? ratio : Fx.raw(mulDivRound(ratio.raw, 12, months));
}

/// What [software]'s company is worth, and what that rests on.
typedef SoftwareWorth = ({
  /// The whole company: its business plus its cash, less what it owes.
  Money worth,

  /// Its business alone: a year's revenue at its multiple, or its team.
  Money business,

  /// A year of what its customers pay now.
  Money yearRevenue,
  Fx growth,
  Fx multiple,

  /// What investors pay for its team, before it sells much.
  Money team,
});

/// What [software]'s company is worth today: a year's revenue times a
/// multiple that grows with its growth and falls with the economy, or, if
/// more, [SoftwareDef.teamMonths] of its team's pay; plus what its company
/// owns, less what it owes.
SoftwareWorth softwareWorth(
  WorldState world,
  ContentDb content,
  SoftwareDef def,
  Software software,
) {
  final company = world.companies[software.company.index];
  final yearRevenue = software.price.timesInt(software.customers * 12);
  final growth = softwareGrowth(software);
  var multiple =
      def.baseMultiple +
      def.growthMultiple * (growth > Fx.zero ? growth : Fx.zero);
  if (multiple > def.maxMultiple) multiple = def.maxMultiple;
  final economy =
      Fx.one + def.valuationCycle * (softwareDemand(world, content) - Fx.one);
  multiple = multiple * (economy > Fx.zero ? economy : Fx.zero);
  if (multiple < def.minMultiple) multiple = def.minMultiple;
  // Investors judge the team by its record: how much faster than the
  // standard it builds.
  final market = world.softwareMarket!;
  final pace = softwareProgress(
    def,
    softwareBuildPower(world, def, software.id, shown: true),
    software.level - market.standard,
  );
  var faster = pace <= def.rise ? Fx.zero : (pace - def.rise).div(def.rise);
  if (faster > def.teamPaceCap) faster = def.teamPaceCap;
  final team = software.running && faster > Fx.zero
      ? softwarePayroll(
          world,
          content,
          def,
          software,
        ).timesInt(def.teamMonths).times(faster)
      : Money.zero;
  final business = yearRevenue.times(multiple);
  final worth =
      (business > team ? business : team) + company.accounts.netAssets;
  return (
    worth: worth > Money.zero ? worth : Money.zero,
    business: business > team ? business : team,
    yearRevenue: yearRevenue,
    growth: growth,
    multiple: multiple,
    team: team,
  );
}

/// What investors put in for [share] of [software]'s company after the
/// round, which is worth [worth] before it.
Money roundMoney(Money worth, Fx share) {
  if (share <= Fx.zero || share >= Fx.one) return Money.zero;
  return Money(mulDivRound(worth.cents, share.raw, (Fx.one - share).raw));
}

/// The months a company's cash lasts at its last month's loss, or null if
/// it isn't losing money.
int? runwayMonths(Money cash, Money monthlyLoss) {
  if (monthlyLoss <= Money.zero) return null;
  if (cash <= Money.zero) return 0;
  return cash.cents ~/ monthlyLoss.cents;
}

/// The software product in [company], if it holds one.
Software? softwareOf(WorldState world, CompanyId company) {
  for (final software in world.software) {
    if (software.company == company) return software;
  }
  return null;
}

/// The share of [company]'s payouts its owner gets: all of it, but for a
/// software company with outside investors.
Fx ownerShare(WorldState world, CompanyId company) {
  // Listed, the player's part is what their holding keeps.
  final market = world.stocks;
  if (market != null) {
    for (final (i, stock) in market.stocks.indexed) {
      if (stock.own?.company != company.index || !stock.running) continue;
      final units = market.unitsOf(i, holdingOwner);
      return Fx.raw(mulDivRound(units, Fx.scale, stock.shares));
    }
  }
  return softwareOf(world, company)?.stake ?? Fx.one;
}

/// Splits [amount] paid out by [company] between its owner and outside
/// investors, who are beyond the simulation: returns the owner's part,
/// having paid the investors theirs with [reason] from [account].
Money payInvestors(
  WorldState world,
  Ledger ledger,
  CompanyId company,
  Money amount,
  AccountKind account,
  EntryReason reason,
) {
  final stake = ownerShare(world, company);
  if (stake >= Fx.one || amount <= Money.zero) return amount;
  final owners = amount.times(stake);
  final investors = amount - owners;
  if (investors > Money.zero) {
    ledger.pay(
      payer: world.companies[company.index],
      payerAccount: account,
      payee: world.elsewhere,
      payeeAccount: AccountKind.revenue,
      amount: investors,
      reason: reason,
    );
  }
  return owners;
}

/// Whether [company] holds a software product, and so may hold nothing
/// else.
bool holdsSoftware(WorldState world, CompanyId company) =>
    softwareOf(world, company) != null;

/// Whether [company] holds its software and nothing else beside it: no
/// shop of any scale, no plant, no subsidiary and no shares. Only such a
/// company is bought whole by a rival, and priced by its software alone.
bool holdsSoftwareAlone(WorldState world, CompanyId company) {
  if (!holdsSoftware(world, company)) return false;
  for (final store in world.stores) {
    if (store.company == company && store.status != StoreStatus.closed) {
      return false;
    }
  }
  for (final factory in world.factories) {
    if (factory.company == company && factory.status != FactoryStatus.closed) {
      return false;
    }
  }
  for (final district in world.sleepers) {
    if (district.shops.any((shop) => shop.company == company)) return false;
  }
  if (world.national case final national?) {
    for (final country in national.countries) {
      if (country.blocks.any((block) => block.company == company)) {
        return false;
      }
    }
  }
  for (final other in world.companies) {
    if (other.parent == company && other.isActive) return false;
  }
  return world.stocks?.holdings.every(
        (holding) => holding.owner != company.index,
      ) ??
      true;
}

/// [amount] shared out by [weights], each share rounded down. Worked in
/// big integers, exact on every platform, since a market's weights run to
/// trillions and the smallest product must still get its share.
List<int> shareOut(int amount, List<int> weights) {
  final total = weights.fold(
    BigInt.zero,
    (sum, weight) => weight > 0 ? sum + BigInt.from(weight) : sum,
  );
  if (amount <= 0 || total == BigInt.zero) {
    return List.filled(weights.length, 0);
  }
  final whole = BigInt.from(amount);
  return [
    for (final weight in weights)
      weight > 0 ? (whole * BigInt.from(weight) ~/ total).toInt() : 0,
  ];
}

/// [part] of [whole] in hundred-thousandths, for comparing shares of a
/// market of billions.
int partsOf(int part, int whole) =>
    whole <= 0 ? 0 : mulDivRound(part, 100000, whole);
