import '../accounting/ledger.dart';
import '../commands/apply_command.dart'
    show maxNationalOpenings, maxNationalRate;
import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../observation/factory_sales_view.dart' show TenderView;
import '../observation/national_view.dart';
import '../observation/observation.dart';
import '../state/director.dart';
import '../state/businesses.dart' show plantsKey, softwareBusiness, tradeKey;
import '../state/districts.dart';
import '../observation/software_view.dart' show SoftwareView;
import '../state/factory.dart' show FactoryStatus;
import '../state/factory_sales.dart' show TenderStatus;
import '../state/store.dart';
import 'entrepreneur_policy.dart';
import 'manager.dart';
import 'retail_policy.dart';

/// A memo a director writes for [company], kept once [command], if any, is
/// carried out.
typedef Directive = ({CompanyId company, Command? command, Memo memo});

/// The most months a director allowed to borrow lets a rival's profitable
/// store take to repay its asking price, at its present earnings.
const buyoutPaybackMonths = 48;

/// What a boss keeping a plant full takes off the producer price to sell
/// its spare goods to rivals, when it sold only to its own shops.
const plantRivalDiscount = Fx.raw(500);

/// What a boss bids under a tender's producer price before any tender for
/// those goods there has been won, how far under the latest winning share
/// they bid once one has, and the least over its own cost a unit they bid
/// at.
const tenderUnder = Fx.raw(400);
const tenderStep = Fx.raw(100);
const tenderMargin = Fx.raw(1000);

/// The size a boss builds a new plant at beside one full at the largest
/// size: a plant, not a workshop.
const newPlantSize = 1;

/// How many months of cash, at its loss with them, a software company must
/// have for its boss to hire someone: growing it, and growing it fast.

/// How full a plant runs, in hundredths of what its shifts can make, before
/// a boss growing it enlarges it, and growing it fast.
const growPlantFull = 90;
const growFastPlantFull = 75;

/// The share of its revenue a boss growing software spends on marketing at
/// least, and growing it fast; and the months of cash below which growing
/// it fast they raise a round, of half the most a round may sell.
const growSoftwareMarketing = Fx.raw(1000);
const growFastSoftwareMarketing = Fx.raw(2500);
const roundBelowMonths = 6;
const hireCashMonths = 12;
const hireFastCashMonths = 6;

/// The duties of the managers a director hires: all but investing, which is
/// the director's.
final directorManagerDuties = List<bool>.unmodifiable([
  for (final duty in ManagerDuty.values) duty != ManagerDuty.investing,
]);

/// The stores of [company] its director closes today: see [losingStore].
Set<StoreId> closingStores(Observation view, CompanyView company) => {
  if (company.director != null)
    for (final store in company.stores)
      if (store.status != StoreStatus.closed && losingStore(view, store))
        store.id,
};

/// What [company]'s director does today for its owner, `view.actor`, from
/// [budget], the company's uncommitted cash its managers left. Each command
/// comes with a memo in [directives].
///
/// Every day, they hire a manager for any store without one. On the first
/// of the month, they close the stores in [closing], and invest and grow as
/// far as the brief allows, as an AI owner would, from cash beyond the
/// strategy's reserve and the year's tax, once the company has made a
/// profit overall: works first, then a rival's store or a new one, at most
/// one a month and none within the strategy's interval of the last. If the
/// brief lets them borrow, the company borrows what it lacks for the works
/// or the store on its earnings, in whole thousands, over the longest term
/// the bank offers. What they would grow but can't pay for, they save for;
/// otherwise, if the brief says so, they pay the owner what is left. Their
/// estimate of a site is off by up to their grade's share of the scenario's
/// error, drawn from [judgment] for each site; null judges exactly. Their
/// character scales the reserve they keep, how much of the bank's credit
/// they use and how long a shop may take to pay back.
List<Command> direct(
  Observation view,
  ContentDb content,
  CompanyView company,
  Money budget,
  Set<StoreId> closing,
  List<Directive> directives, {
  Rng Function(int entity)? judgment,
}) {
  final director = company.director!;
  final today = view.today;
  final commands = <Command>[];
  void give(Command? command, Memo memo) {
    if (command != null) commands.add(command);
    directives.add((company: company.id, command: command, memo: memo));
  }

  final strategy = content.strategies[director.strategy.index];
  for (final store in company.stores) {
    if (store.status == StoreStatus.closed ||
        store.manager != null ||
        closing.contains(store.id)) {
      continue;
    }
    give(
      HireManager(
        view.actor,
        store: store.id,
        grade: director.managerGrade,
        strategy: _strategyFor(content, strategy, store),
        duties: directorManagerDuties,
      ),
      ManagerHired(today, store: store.id, grade: director.managerGrade),
    );
  }
  if (director.goals.isNotEmpty) {
    _bidTenders(view, content, company, director, commands);
  }
  if (!today.isFirstOfMonth) return commands;

  for (final store in company.stores) {
    if (!closing.contains(store.id)) continue;
    final (:revenue, :profit, days: _) = store.recentMonths;
    give(
      CloseStore(view.actor, store: store.id),
      StoreClosed(today, store: store.id, sales: revenue, loss: -profit),
    );
  }

  final character = content.directors!.characterOf(director);
  final reserve = operatingReserve(
    view,
    company,
    scaledMonths(strategy.reserveDays, character.reserve),
  );
  if (reserve == null) return commands;
  var spare = budget - reserve - company.taxAccrued;
  // What the bank still lends on the company's earnings, if they may ask,
  // as far as they will go.
  var credit = director.borrows
      ? (view.companyCredits[company.id.index] ?? Money.zero).times(
          character.credit,
        )
      : Money.zero;
  final term = content.finance.maxTermMonths;
  bool canPay(Money cost) =>
      cost <= spare || (director.borrows && _thousands(cost - spare) <= credit);
  // Pays for works, borrowing what there isn't to spare; returns the loan.
  Money pay(Money cost) {
    if (cost <= spare) {
      spare -= cost;
      return Money.zero;
    }
    final loan = _thousands(cost - spare);
    commands.add(
      TakeLoan(
        view.actor,
        company: company.id,
        amount: loan,
        termMonths: term,
        guarantee: false,
      ),
    );
    credit -= loan;
    spare = Money.zero;
    return loan;
  }

  final profit =
      company.retainedEarnings + company.balance(AccountKind.dividends);
  // Works and fitting out are spent, out of the profit kept.
  var retained = company.retainedEarnings;
  ProfitKept? saving;
  if (profit > Money.zero) {
    for (final store in company.stores) {
      if (store.status == StoreStatus.closed ||
          closing.contains(store.id) ||
          !director.allowsIn(
            tradeKey(content.formats[store.format.index]),
            Growth.invest,
          )) {
        continue;
      }
      final plan = StorePlan(
        switch (store.manager) {
          final manager? => content.strategies[manager.strategy.index],
          null => strategy,
        },
        content,
        view,
        company,
        store,
      );
      if (plan.conversion() case (
        :final format,
        :final cost,
      ) when canPay(cost)) {
        final borrowed = pay(cost);
        give(
          ConvertStore(view.actor, store: store.id, format: format),
          StoreConverted(
            today,
            store: store.id,
            format: format,
            cost: cost,
            borrowed: borrowed,
          ),
        );
        retained -= cost;
      } else if (plan.enlargementCost() case final cost?) {
        if (canPay(cost)) {
          final borrowed = pay(cost);
          give(
            ExpandStore(view.actor, store: store.id),
            StoreEnlarged(
              today,
              store: store.id,
              cost: cost,
              borrowed: borrowed,
            ),
          );
          retained -= cost;
        } else {
          saving ??= ProfitKept(today, store: store.id, needed: cost);
        }
      }
    }
  }

  // The trades the brief grows, each with the strategy its shops follow,
  // the director's own first; a brief from before goals grows only that.
  final growing = <(String, StrategyDef)>[
    if (director.goals.isEmpty)
      if (director.allows(Growth.open))
        (tradeKey(content.formats[strategy.format.index]), strategy)
      else
        ...[]
    else
      for (final trade in _tradesOf(content, view, company, strategy))
        if (director.allowsIn(trade, Growth.open))
          if (_strategyOfTrade(content, view, company, strategy, trade)
              case final own?)
            (trade, own),
  ];
  if (growing.isNotEmpty && profit > Money.zero) {
    // At most a shop a month in full or in a district for each trade it
    // grows, where one pays, never two in one spot; what each borrows
    // leaves the next less credit.
    final taken = <String>{};
    for (final (trade, own) in growing) {
      final growth = _growth(
        view,
        content,
        company,
        own,
        judgment,
        spare,
        credit,
        buys: director.allowsIn(trade, Growth.buy),
        taken: taken,
      );
      if (growth == null) continue;
      final (:command, :memo, :cost, :borrowed) = growth;
      if (!taken.add(_spot(command))) continue;
      if (cost > spare + borrowed) {
        saving ??= ProfitKept(
          today,
          site: command is OpenStore ? command.site : null,
          store: command is BuyStore ? command.store : null,
          needed: cost,
        );
        continue;
      }
      // Opening and buying in districts run by formula take no loan of
      // their own: the company borrows first.
      if (borrowed > Money.zero &&
          (command is OpenInDistrict || command is BuyInDistrict)) {
        commands.add(
          TakeLoan(
            view.actor,
            company: company.id,
            amount: borrowed,
            termMonths: term,
            guarantee: false,
          ),
        );
      }
      give(command, memo);
      // A loan takes all there was to spare, and leaves nothing to pay out.
      spare = borrowed > Money.zero ? Money.zero : spare - cost;
      credit -= borrowed;
      if (memo is StoreOpened) retained -= memo.cost;
      if (memo is DistrictOpened) retained -= memo.cost;
    }
  }

  // Shops run by formula grow out of a business that earns: what the company
  // made overall before what it spent fitting out shops, which serve for
  // years, so a chain growing fast doesn't wait for each year's fitting out
  // to be earned back before the next.
  final earned = profit + company.balance(AccountKind.openingCosts);
  national:
  for (final (trade, own) in growing) {
    if (earned <= Money.zero ||
        nationalGrowthRate(content, director, trade: trade) <= Fx.zero) {
      continue;
    }
    for (final (:command, :memo) in _nationalGrowth(
      view,
      content,
      company,
      own,
      judgment,
    )) {
      if (!canPay(memo.cost)) {
        saving ??= ProfitKept(today, needed: memo.cost);
        break national;
      }
      final borrowed = pay(memo.cost);
      give(
        command,
        NationalOpened(
          today,
          country: memo.country,
          region: memo.region,
          format: memo.format,
          count: memo.count,
          cost: memo.cost,
          earns: memo.earns,
          paybackMonths: memo.paybackMonths,
          borrowed: borrowed,
        ),
      );
      retained -= memo.cost;
    }
  }

  if (director.goals.isNotEmpty) {
    spare = _directPlants(
      view,
      content,
      company,
      director,
      commands,
      spare: spare,
      credit: director.borrows ? credit : Money.zero,
    );
    _directSoftware(view, content, company, director, commands);
  }

  if (director.payout) {
    if (saving != null) {
      give(null, saving);
    } else {
      final amount = spare < retained ? spare : retained;
      if (amount > Money.zero) {
        give(
          PayDividend(view.actor, company: company.id, amount: amount),
          ProfitPaid(today, amount: amount),
        );
      }
    }
  }
  return commands;
}

/// [count] days or months times [factor], rounded.
int scaledMonths(int count, Fx factor) =>
    mulDivRound(count, factor.raw, Fx.scale);

/// [amount] rounded up to a whole thousand.
Money _thousands(Money amount) {
  const thousand = 100000;
  return Money((amount.cents + thousand - 1) ~/ thousand * thousand);
}

/// The strategy a manager hired for [store] follows: the director's, if it
/// runs that kind of business, or else the one that runs it at the
/// market's prices.
StrategyId _strategyFor(
  ContentDb content,
  StrategyDef strategy,
  StoreView store,
) => _strategyForFormat(content, strategy, store.format);

/// The strategy a shop of [format] follows under a director of [strategy]:
/// theirs, if of that format, or else the one that runs it at the market's
/// prices.
StrategyId _strategyForFormat(
  ContentDb content,
  StrategyDef strategy,
  FormatId format,
) {
  if (strategy.format == format) return strategy.id;
  final fitting = [
    for (final option in content.strategies)
      if (option.format == format) option,
  ];
  return fitting
          .where((option) => option.marketPosition == Fx.zero)
          .firstOrNull
          ?.id ??
      fitting.firstOrNull?.id ??
      strategy.id;
}

/// The store [company]'s director would buy or open this month, if any, as
/// an AI owner judges them (see [EntrepreneurPolicy]), with what it costs
/// and what the company would borrow towards it beyond the cash it has to
/// [spare], as far as the bank's [credit] goes: a rival's struggling store of
/// the strategy's format, at its
/// asking price and the buyer's reserve, if the brief allows buying, or else
/// the vacant site that would repay a new store soonest, with its opening
/// cost and starting months. Either must repay within the strategy's payback
/// period, as their character stretches it, and come the strategy's
/// interval after the company's latest store. If the brief lets them borrow
/// and no struggling store will do, they also buy the profitable rival's
/// store that repays soonest, within [buyoutPaybackMonths] stretched the
/// same way, if the bank lends what that takes.
({Command command, Memo memo, Money cost, Money borrowed})? _growth(
  Observation view,
  ContentDb content,
  CompanyView company,
  StrategyDef strategy,
  Rng Function(int entity)? judgment,
  Money spare,
  Money credit, {
  required bool buys,
  Set<String> taken = const {},
}) {
  final director = company.director!;
  final owner = EntrepreneurPolicy(strategy);
  final grade = content.directors!.grades[director.grade.index];
  final error = content.directors!.judgmentError * (Fx.one - grade.skill);
  final character = content.directors!.characterOf(director);
  // The longest a new shop, or a profitable rival's, may take to repay.
  final paybackLimit = scaledMonths(
    strategy.expansionPaybackMonths,
    character.payback,
  );
  final buyoutLimit = scaledMonths(buyoutPaybackMonths, character.payback);
  Fx judged(SiteId site) => switch (judgment) {
    final judgment? => judgmentFactor(
      judgment(company.id.index * content.sites.length + site.index),
      error,
    ),
    null => Fx.one,
  };
  // A site of a district run by formula, by its row and number.
  Fx judgedAt(int row, int site) => switch (judgment) {
    final judgment? => judgmentFactor(
      judgment(company.id.index * 100000 + 60000 + row * 100 + site),
      error,
    ),
    null => Fx.one,
  };
  // The company's latest shop of the strategy's trade, each trade waiting
  // the interval after its own.
  final trade = tradeKey(content.formats[strategy.format.index]);
  bool ofTrade(FormatId format) =>
      tradeKey(content.formats[format.index]) == trade;
  var latest = company.founded.number;
  for (final store in company.stores) {
    if (!ofTrade(store.format)) continue;
    final since = (store.acquiredOn ?? store.opensOn).number;
    if (since > latest) latest = since;
  }
  // Its shops in districts run by formula count too.
  for (final district in view.districts) {
    for (final shop in district.shops) {
      if (shop.company == company.id &&
          ofTrade(shop.format) &&
          shop.since.number > latest) {
        latest = shop.since.number;
      }
    }
  }
  final waited = view.today.number - latest;
  final term = content.finance.maxTermMonths;
  // A shop of a kind the countries run by formula, run in full, joins its
  // company's shops by formula the day it opens (see `absorbDirected`): the
  // director buys and opens only in districts run by formula, and across
  // countries.
  final byFormula =
      view.national.isNotEmpty &&
      content.formats[strategy.format.index].national != null;

  // What the company borrows towards [cost], with [earnings] of a store it
  // buys counted: zero if it has the cash, may not borrow or the bank won't
  // lend that much. Rounded up to a thousand.
  Money borrowing(Money cost, {Money earnings = Money.zero}) {
    if (!director.borrows || cost <= spare) return Money.zero;
    final wanted = _thousands(cost - spare);
    final room = credit + earnings.times(content.finance.earningsMultiple);
    return wanted <= room ? wanted : Money.zero;
  }

  if (content.acquisitions case final terms?
      when buys && waited >= terms.intervalDays) {
    Money withReserve(Money price) => price + price.times(terms.buyerReserve);
    // A struggling shop, run in full or in a district run by formula.
    var struggling = owner.strugglingShop(
      view,
      content,
      passOver: (owner) => owner == view.actor,
      judged: judged,
      judgedAt: judgedAt,
    );
    // Another trade of the company's took it this month.
    if (struggling != null &&
        taken.contains(switch (struggling.district) {
          (final district, final shop) =>
            'district ${district.row} ${shop.site}',
          null => 'store ${struggling.shelf?.id.index}',
        })) {
      struggling = null;
    }
    var best = byFormula ? null : struggling?.shelf;
    var bestPayback = struggling?.paybackMonths ?? 0;
    var price = struggling?.price ?? Money.zero;
    // Else, borrowing, the profitable shop that repays soonest.
    ShelfView? profitable;
    var profitablePayback = buyoutLimit + 1;
    for (final shelf in view.shelves) {
      if (!director.borrows || byFormula) break;
      if (shelf.status == StoreStatus.closed ||
          shelf.format != strategy.format ||
          view.companyOwners[shelf.company.index] == view.actor ||
          taken.contains('store ${shelf.id.index}')) {
        continue;
      }
      final value = view.valuations[shelf.id.index];
      if (value == null || value.earnings.isNegative) continue;
      final since = shelf.acquiredOn ?? shelf.opensOn;
      if (view.today.number - since.number < 365) continue;
      final expected = value.earnings.times(judged(shelf.site));
      if (expected <= Money.zero) continue;
      final payback = mulDivRound(value.price.cents, 12, expected.cents);
      final cost = withReserve(value.price);
      if (payback < profitablePayback &&
          cost <= spare + borrowing(cost, earnings: value.earnings)) {
        profitable = shelf;
        profitablePayback = payback;
      }
    }
    if (struggling?.district case (final district, final shop)) {
      final cost = withReserve(price);
      final borrowed = borrowing(cost);
      return (
        command: BuyInDistrict(
          view.actor,
          row: district.row,
          site: shop.site,
          company: company.id,
        ),
        memo: DistrictBought(
          view.today,
          row: district.row,
          site: shop.site,
          price: price,
          paybackMonths: bestPayback,
          borrowed: borrowed,
        ),
        cost: cost,
        borrowed: borrowed,
      );
    }
    if (best == null && profitable != null) {
      best = profitable;
      bestPayback = profitablePayback;
      price = view.valuations[profitable.id.index]!.price;
    }
    if (best != null) {
      final cost = withReserve(price);
      final borrowed = borrowing(
        cost,
        earnings: view.valuations[best.id.index]!.earnings,
      );
      return (
        command: BuyStore(
          view.actor,
          store: best.id,
          company: company.id,
          borrow: borrowed,
          termMonths: borrowed > Money.zero ? term : 0,
        ),
        memo: StoreBought(
          view.today,
          store: best.id,
          price: price,
          paybackMonths: bestPayback,
          borrowed: borrowed,
        ),
        cost: cost,
        borrowed: borrowed,
      );
    }
  }

  if (waited < strategy.expansionIntervalDays) return null;
  final format = content.formats[strategy.format.index];
  SiteDef? best;
  var bestPayback = 0;
  for (final id in view.vacantSites) {
    if (byFormula) break;
    final site = content.sites[id.index];
    if (site.area < format.minArea || taken.contains('site ${id.index}')) {
      continue;
    }
    final payback = owner.paybackMonths(
      view,
      content,
      site,
      judged: judged(id),
    );
    if (payback == null || payback > paybackLimit) continue;
    if (best == null || payback < bestPayback) {
      best = site;
      bestPayback = payback;
    }
  }
  // Free sites in districts run by formula, weighed the same way.
  (DistrictView, DistrictSite)? there;
  for (final district in view.districts) {
    for (final site in district.free) {
      if (site.area < format.minArea ||
          taken.contains('district ${district.row} ${site.number}')) {
        continue;
      }
      final payback = owner.districtPaybackMonths(view, content, district, (
        location: site.location,
        area: site.area,
        rent: site.rent,
        openingCost: site.openingCost,
      ), judged: judgedAt(district.row, site.number));
      if (payback == null ||
          payback > paybackLimit ||
          (best != null || there != null) && payback >= bestPayback) {
        continue;
      }
      best = null;
      there = (district, site);
      bestPayback = payback;
    }
  }
  if (there case (final district, final site)) {
    final cost = owner.districtCapital(view, content, district, site);
    final borrowed = borrowing(cost);
    return (
      command: OpenInDistrict(
        view.actor,
        row: district.row,
        site: site.number,
        company: company.id,
        format: strategy.format,
      ),
      memo: DistrictOpened(
        view.today,
        row: district.row,
        site: site.number,
        format: strategy.format,
        cost: site.openingCost
            .times(format.fitOut)
            .times(view.economy(district.country).priceIndex),
        paybackMonths: bestPayback,
        borrowed: borrowed,
      ),
      cost: cost,
      borrowed: borrowed,
    );
  }
  if (best == null) return null;
  final cost = owner.startingCapital(view, content, best);
  final borrowed = borrowing(cost);
  return (
    command: OpenStore(
      view.actor,
      site: best.id,
      name: best.name,
      company: company.id,
      format: strategy.format,
      borrow: borrowed,
      termMonths: borrowed > Money.zero ? term : 0,
    ),
    memo: StoreOpened(
      view.today,
      site: best.id,
      format: strategy.format,
      cost: best.openingCost
          .times(format.fitOut)
          .times(view.economyAt(content, best.market).priceIndex),
      paybackMonths: bestPayback,
      borrowed: borrowed,
    ),
    cost: cost,
    borrowed: borrowed,
  );
}

/// How soon a shop run by formula across a country must pay back its
/// fitting out for a director to open it, in months, unless the strategy
/// allows longer. Longer than a district shop's: its sales and costs are its
/// trade's across a region, known rather than guessed for one site.
const nationalPaybackMonths = 36;

/// The rate [director] grows their company's shops run by formula of
/// [trade], their own strategy's if null, at. With a brief of goals: what
/// their grade runs well at their character's pace, growing it; twice
/// that, as far as a brief may go, growing it fast; none otherwise. Before
/// goals, their brief's rate, or that pace left to judge.
Fx nationalGrowthRate(ContentDb content, Director director, {String? trade}) {
  final directors = content.directors!;
  if (director.goals.isEmpty) return directors.growthRateOf(director);
  final key =
      trade ??
      tradeKey(
        content.formats[content
            .strategies[director.strategy.index]
            .format
            .index],
      );
  final judged =
      directors.grades[director.grade.index].growth *
      directors.characterOf(director).pace;
  return switch (director.goalOf(key)) {
    Goal.grow => judged,
    Goal.growFast =>
      judged.timesInt(2) > maxNationalRate
          ? maxNationalRate
          : judged.timesInt(2),
    Goal.harvest || Goal.hold => Fx.zero,
  };
}

/// [company]'s trades: [own]'s first, then those of its shops in full, in
/// districts run by formula and across countries, in that order.
List<String> _tradesOf(
  ContentDb content,
  Observation view,
  CompanyView company,
  StrategyDef own,
) {
  final trades = <String>{tradeKey(content.formats[own.format.index])};
  for (final store in company.stores) {
    if (store.status != StoreStatus.closed) {
      trades.add(tradeKey(content.formats[store.format.index]));
    }
  }
  for (final district in view.districts) {
    for (final shop in district.shops) {
      if (shop.company == company.id) {
        trades.add(tradeKey(content.formats[shop.format.index]));
      }
    }
  }
  for (final country in view.national) {
    for (final block in country.blocks) {
      if (block.company == company.id) {
        trades.add(tradeKey(content.formats[block.format.index]));
      }
    }
  }
  return [...trades];
}

/// The strategy [company]'s shops of [trade] follow: [own], if of it; else
/// that of its first shop of it in full, in a district or across a
/// country; null if it has none.
StrategyDef? _strategyOfTrade(
  ContentDb content,
  Observation view,
  CompanyView company,
  StrategyDef own,
  String trade,
) {
  bool ofTrade(FormatId format) =>
      tradeKey(content.formats[format.index]) == trade;
  if (ofTrade(own.format)) return own;
  for (final store in company.stores) {
    if (store.status != StoreStatus.closed && ofTrade(store.format)) {
      return content.strategies[(store.manager?.strategy ??
              _strategyFor(content, own, store))
          .index];
    }
  }
  for (final country in view.national) {
    for (final block in country.blocks) {
      if (block.company == company.id && ofTrade(block.format)) {
        return content.strategies[block.strategy.index];
      }
    }
  }
  for (final district in view.districts) {
    for (final shop in district.shops) {
      if (shop.company == company.id && ofTrade(shop.format)) {
        return content.strategies[_strategyForFormat(
          content,
          own,
          shop.format,
        ).index];
      }
    }
  }
  return null;
}

/// The tenders [director] bids for today, for [company]'s plants whose goal
/// is to hold or grow: those still open past today that a plant can fill
/// from what its shifts leave a month, beyond its own shops and its
/// contracts and the tenders it has bid for, of goods good enough, just
/// under the producer price and never near its cost. Tenders open and close
/// within the month, so they look every day.
void _bidTenders(
  Observation view,
  ContentDb content,
  CompanyView company,
  Director director,
  List<Command> commands,
) {
  final kinds = content.factories?.kinds;
  if (kinds == null) return;
  for (final factory in company.factories) {
    final sales = factory.sales;
    if (!factory.making ||
        sales == null ||
        director.goalOf(plantsKey(kinds[factory.kind.index])) == Goal.harvest) {
      continue;
    }
    var free = factory.monthCapacity - factory.recentOwnUnits - sales.committed;
    for (final tender in view.tenders) {
      if (tender.status == TenderStatus.open &&
          tender.bidFactory == factory.id) {
        free -= tender.units;
      }
    }
    for (final tender in view.tenders) {
      if (free <= 0) break;
      if (tender.status != TenderStatus.open ||
          tender.bidFactory != null ||
          tender.closes.number <= view.today.number ||
          tender.units > free ||
          !factory.serves[tender.country.index]) {
        continue;
      }
      final line = sales.lines
          .where((line) => line.product == tender.product)
          .firstOrNull;
      if (line == null || line.lead < tender.floor) continue;
      final price = tenderBid(view.tenders, tender, line.unitCost);
      if (price == null) continue;
      commands.add(
        BidTender(
          view.actor,
          tender: tender.number,
          factory: factory.id,
          price: price,
        ),
      );
      free -= tender.units;
    }
  }
}

/// What [director] does with [company]'s plants on the first of the month,
/// by the goal for each kind, out of the cash [spare] and, if they may
/// borrow, the bank's [credit]; returns what is left to spare. Harvesting,
/// they stop its research. From holding on, they sell its spare goods to
/// rivals (and bid for tenders, see [_bidTenders]). Growing, they enlarge
/// it once it runs nine tenths full, three quarters growing fast.
Money _directPlants(
  Observation view,
  ContentDb content,
  CompanyView company,
  Director director,
  List<Command> commands, {
  required Money spare,
  required Money credit,
}) {
  final kinds = content.factories?.kinds;
  if (kinds == null) return spare;
  final term = content.finance.maxTermMonths;
  // The kinds and countries a new plant was ordered for this month.
  final built = <(FactoryKindId, CountryId)>{};
  for (final factory in company.factories) {
    if (!factory.making) continue;
    final goal = director.goalOf(plantsKey(kinds[factory.kind.index]));
    if (goal == Goal.harvest) {
      if (factory.lab case final lab? when lab.budget > Money.zero) {
        commands.add(
          SetLab(view.actor, factory: factory.id, budget: Money.zero),
        );
      }
      continue;
    }
    if (factory.rivalDiscount == null) {
      commands.add(
        SetFactoryTerms(
          view.actor,
          factory: factory.id,
          serves: factory.serves,
          rivalDiscount: plantRivalDiscount,
        ),
      );
    }
    final sales = factory.sales;
    if (sales == null) continue;
    final full = switch (goal) {
      Goal.grow => growPlantFull,
      Goal.growFast => growFastPlantFull,
      Goal.harvest || Goal.hold => null,
    };
    if (full == null || sales.enlargedOn != null) continue;
    final used =
        factory.recentOwnUnits + factory.recentRivalUnits + sales.committed;
    if (used * 100 < factory.monthCapacity * full) continue;
    final cost = sales.enlargeCost;
    if (cost == null) {
      // The largest there is: another plant of its kind beside it, unless
      // one is being built or enlarged there already.
      final kind = kinds[factory.kind.index];
      final mates = [
        for (final other in company.factories)
          if (other.kind == factory.kind &&
              other.country == factory.country &&
              other.status == FactoryStatus.running)
            other,
      ];
      if (built.contains((factory.kind, factory.country)) ||
          mates.any(
            (other) => !other.making || other.sales?.enlargedOn != null,
          )) {
        continue;
      }
      final size = newPlantSize < content.factories!.sizes.length
          ? newPlantSize
          : content.factories!.sizes.length - 1;
      final price = content.factories!
          .sized(kind.id, size)
          .buildCost
          .times(view.economy(factory.country).priceIndex);
      final command = BuildFactory(
        view.actor,
        kind: kind.id,
        country: factory.country,
        name: '${factory.name} ${mates.length + 1}',
        company: company.id,
        shifts: factory.shifts,
        serves: factory.serves,
        size: size,
      );
      if (price <= spare) {
        commands.add(command);
        spare -= price;
      } else if (_thousands(price - spare) case final loan
          when loan <= credit) {
        commands.add(
          BuildFactory(
            view.actor,
            kind: kind.id,
            country: factory.country,
            name: command.name,
            company: company.id,
            borrow: loan,
            termMonths: term,
            shifts: factory.shifts,
            serves: factory.serves,
            size: size,
          ),
        );
        credit -= loan;
        spare = Money.zero;
      } else {
        continue;
      }
      built.add((factory.kind, factory.country));
      continue;
    }
    if (cost <= spare) {
      commands.add(EnlargeFactory(view.actor, factory: factory.id));
      spare -= cost;
    } else if (_thousands(cost - spare) case final loan when loan <= credit) {
      commands.add(
        EnlargeFactory(
          view.actor,
          factory: factory.id,
          borrow: loan,
          termMonths: term,
        ),
      );
      credit -= loan;
      spare = Money.zero;
    }
  }
  return spare;
}

/// A boss's bid for [tender], among [tenders] open and lately closed: a
/// point under what won the latest for its goods in its country, as a share
/// of that one's producer price, or [tenderUnder] below the producer price
/// if none has been won yet; null unless that is [tenderMargin] over
/// [unitCost].
Money? tenderBid(List<TenderView> tenders, TenderView tender, Money unitCost) {
  var under = tenderUnder;
  TenderView? latest;
  for (final other in tenders) {
    if (other.product != tender.product ||
        other.country != tender.country ||
        other.winningPrice == null ||
        other.reference <= Money.zero) {
      continue;
    }
    if (latest == null || other.closes.number > latest.closes.number) {
      latest = other;
    }
  }
  if (latest != null) {
    final won = Fx.raw(
      mulDivRound(latest.winningPrice!.cents, Fx.scale, latest.reference.cents),
    );
    under = Fx.one - won + tenderStep;
    if (under < Fx.zero) under = Fx.zero;
  }
  final price = tender.reference - tender.reference.times(under);
  final least = unitCost + unitCost.times(tenderMargin);
  return price >= least && price > Money.zero ? price : null;
}

/// The spot [command] opens or buys a shop in, so no two openings of a
/// month take the same one.
String _spot(Command command) => switch (command) {
  OpenStore(:final site) => 'site ${site.index}',
  OpenInDistrict(:final row, :final site) => 'district $row $site',
  BuyInDistrict(:final row, :final site) => 'district $row $site',
  BuyStore(:final store) => 'store ${store.index}',
  _ => '$command',
};

/// What [director] does with [company]'s software on the first of the
/// month, by its goal: harvesting, they stop its marketing; growing, they
/// spend at least [growSoftwareMarketing] of its revenue on it, and growing
/// fast [growFastSoftwareMarketing], raising a round when it has less than
/// [roundBelowMonths] of cash at its loss. Who joins its team stays the
/// owner's choice.
void _directSoftware(
  Observation view,
  ContentDb content,
  CompanyView company,
  Director director,
  List<Command> commands,
) {
  final software = company.software;
  if (software == null || !software.running) return;
  final goal = director.goalOf(softwareBusiness);
  final least = switch (goal) {
    Goal.harvest => Money.zero,
    Goal.hold => software.marketing,
    Goal.grow => software.revenue.times(growSoftwareMarketing),
    Goal.growFast => software.revenue.times(growFastSoftwareMarketing),
  };
  final budget = goal == Goal.harvest
      ? Money.zero
      : (least > software.marketing ? least : software.marketing);
  if (budget != software.marketing) {
    commands.add(
      SetSoftwareMarketing(view.actor, software: software.id, budget: budget),
    );
  }
  if (goal == Goal.grow || goal == Goal.growFast) {
    _hireForSoftware(
      view,
      content,
      company,
      software,
      commands,
      fast: goal == Goal.growFast,
    );
  }
  if (goal != Goal.growFast ||
      software.monthProfit >= Money.zero ||
      view.today.number < software.nextRound.number) {
    return;
  }
  final cash = company.cash;
  final loss = -software.monthProfit;
  if (cash.cents >= loss.cents * roundBelowMonths) return;
  final share = Fx.raw(software.maxRoundShare.raw ~/ 2);
  if (share > Fx.zero) {
    commands.add(RaiseRound(view.actor, software: software.id, share: share));
  }
}

/// Hires the candidate who builds most for their pay into [software], if
/// its team has room and [company]'s cash covers [hireCashMonths] of its
/// loss with them ([hireFastCashMonths] growing [fast]), or it still makes
/// money with them; growing fast, the strongest it can so afford rather
/// than the best value. One a month.
void _hireForSoftware(
  Observation view,
  ContentDb content,
  CompanyView company,
  SoftwareView software,
  List<Command> commands, {
  required bool fast,
}) {
  final def = content.software;
  if (def == null || software.team.length >= software.maxPeople) return;
  final months = fast ? hireFastCashMonths : hireCashMonths;
  KeyPersonView? best;
  var bestScore = 0;
  for (final candidate in view.softwareCandidates) {
    final pay = candidate.salary.times(software.wageLevel);
    if (pay <= Money.zero) continue;
    final after = software.monthProfit - pay;
    final affordable =
        after >= Money.zero || company.cash.cents >= -after.cents * months;
    if (!affordable) continue;
    final power = def.levels[candidate.level].power;
    // Power per thousand of pay, or growing fast, power alone.
    final score = fast ? power.raw : mulDivRound(power.raw, 100000, pay.cents);
    if (best == null || score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  if (best != null) {
    commands.add(
      HireSoftwarePerson(view.actor, software: software.id, person: best.id),
    );
  }
}

/// [company]'s shops of [trade] in [country]: run by hand, in districts run
/// by formula, and across the country, its chains bought among them.
int nationalChainShops(
  Observation view,
  ContentDb content,
  CompanyView company,
  NationalCountryView country,
  int trade,
) {
  final game = country.country;
  var shops = 0;
  for (final block in country.blocks) {
    if (block.company == company.id && block.trade == trade) {
      shops += block.stores;
    }
  }
  for (final store in company.stores) {
    if (store.status != StoreStatus.closed &&
        content.countryOf(store.market) == game &&
        country.tradeOf(content, store.format) == trade) {
      shops++;
    }
  }
  for (final district in view.districts) {
    if (district.country != game) continue;
    for (final shop in district.shops) {
      if (shop.company == company.id &&
          country.tradeOf(content, shop.format) == trade) {
        shops++;
      }
    }
  }
  return shops;
}

/// [sales] as a share of [market]: in euros, and in coarser units still
/// once a market passes 400 billion a year, as a country's does in a long
/// game, to stay safe in the division.
Fx shareOfMarket(Money sales, Money market) {
  var sold = sales.cents ~/ 100;
  var whole = market.cents ~/ 100;
  while (whole > 400000000000) {
    sold ~/= 10;
    whole ~/= 10;
  }
  return whole <= 0 ? Fx.zero : Fx.raw(mulDivRound(sold, Fx.scale, whole));
}

/// How many shops of [trade] a director growing [company] at [rate] opens
/// in [country] this month: that share of its shops of the trade there, run
/// by hand, in districts run by formula and across the country, slowed as
/// it nears critical mass there (at [DirectorsDef.criticalShare] of the
/// trade at its sales' yearly pace, half as fast), and at least one. A part
/// of a shop is one more with that chance by [rng], so growth compounds on
/// average however small; without [rng], it rounds. None at no rate.
int nationalBudget(
  Observation view,
  ContentDb content,
  CompanyView company,
  NationalCountryView country,
  int trade,
  Fx rate, {
  Rng? rng,
}) {
  if (rate <= Fx.zero) return 0;
  final shops = nationalChainShops(view, content, company, country, trade);
  var sales = Money.zero;
  for (final block in country.blocks) {
    if (block.company != company.id || block.trade != trade) continue;
    // A year at its latest months' pace.
    final months = block.months.length > 12
        ? block.months.sublist(block.months.length - 12)
        : block.months;
    if (months.isEmpty) continue;
    var sold = Money.zero;
    for (final month in months) {
      sold += month.sales;
    }
    sales += Money(mulDivRound(sold.cents, 12, months.length));
  }
  final market = country.markets[trade].fold(Money.zero, (sum, m) => sum + m);
  final critical = content.directors!.criticalShare;
  var slowed = rate;
  if (market.cents >= 100 && critical > Fx.zero) {
    slowed = rate * critical.div(critical + shareOfMarket(sales, market));
  }
  final whole = shops * slowed.raw;
  var count = whole ~/ Fx.scale;
  final part = Fx.raw(whole % Fx.scale);
  if (rng == null ? part.raw * 2 >= Fx.scale : rng.chance(part)) count++;
  return count < 1 ? 1 : count;
}

/// The shops run by formula [company]'s director would open this month, the
/// soonest paid back first: in each country, as many as [nationalBudget]
/// allows at the rate they grow it, each in the region allowed where one
/// more would pay back soonest as they judge it, counting those placed
/// before it this month, within [nationalPaybackMonths] or the strategy's
/// payback period if longer, as their character stretches it. Growing
/// faster than their grade runs well, they misjudge in proportion.
List<({OpenNational command, NationalOpened memo})> _nationalGrowth(
  Observation view,
  ContentDb content,
  CompanyView company,
  StrategyDef strategy,
  Rng Function(int entity)? judgment,
) {
  final director = company.director!;
  final format = content.formats[strategy.format.index];
  final national = format.national;
  if (national == null) return const [];
  final grade = content.directors!.grades[director.grade.index];
  final rate = nationalGrowthRate(content, director, trade: tradeKey(format));
  if (rate <= Fx.zero) return const [];
  var error = content.directors!.judgmentError * (Fx.one - grade.skill);
  if (grade.growth > Fx.zero && rate > grade.growth) {
    error = error * rate.div(grade.growth);
  }
  final home = {
    for (final store in company.stores)
      if (store.status != StoreStatus.closed)
        content.countryOf(store.market).index,
    for (final district in view.districts)
      if (district.shops.any((shop) => shop.company == company.id))
        district.country.index,
  };
  final limit = scaledMonths(
    strategy.expansionPaybackMonths > nationalPaybackMonths
        ? strategy.expansionPaybackMonths
        : nationalPaybackMonths,
    content.directors!.characterOf(director).payback,
  );
  final picks = <({OpenNational command, NationalOpened memo})>[];
  for (final country in view.national) {
    final game = country.country;
    if (game == null || country.def.regions.isEmpty) continue;
    final trade = country.tradeOf(content, format.id);
    if (trade == null) continue;
    final ours = country.blocks.any((block) => block.company == company.id);
    final regions = [
      for (final (r, region) in country.def.regions.indexed)
        if (director.nationalRegions.isEmpty
            ? home.contains(game.index) || ours
            : director.nationalRegions.contains(region.key))
          r,
    ];
    if (regions.isEmpty) continue;
    // How far off they are about each region, this month.
    final judged = {
      for (final r in regions)
        r: judgment == null
            ? Fx.one
            : judgmentFactor(
                judgment(
                  company.id.index * 100000 + 90000 + country.index * 100 + r,
                ),
                error,
              ),
    };
    final placed = List.filled(country.def.regions.length, 0);
    final first = <int, ({Money earns, int payback})>{};
    var budget = nationalBudget(
      view,
      content,
      company,
      country,
      trade,
      rate,
      rng: judgment?.call(company.id.index * 100000 + 95000 + country.index),
    );
    while (budget-- > 0) {
      var best = -1;
      var bestPayback = 0;
      var bestProfit = Money.zero;
      for (final r in regions) {
        final profit = country
            .newShop(
              content,
              company: company.id,
              format: format.id,
              strategy: strategy.id,
              region: r,
              extra: placed[r] * 1000,
            )
            .profit
            .times(judged[r]!);
        if (profit <= Money.zero) continue;
        final cost = country.fitOut(content, format.id, r);
        final payback = (cost.cents * 12 + profit.cents - 1) ~/ profit.cents;
        if (payback > limit) continue;
        if (best < 0 || payback < bestPayback) {
          best = r;
          bestPayback = payback;
          bestProfit = profit;
        }
      }
      if (best < 0) break;
      placed[best]++;
      first[best] ??= (earns: bestProfit, payback: bestPayback);
    }
    for (final r in regions) {
      var left = placed[r];
      final cost = country.fitOut(content, format.id, r);
      while (left > 0) {
        final count = left < maxNationalOpenings ? left : maxNationalOpenings;
        left -= count;
        picks.add((
          command: OpenNational(
            view.actor,
            company: company.id,
            country: game,
            region: r,
            format: format.id,
            strategy: strategy.id,
            count: count,
          ),
          memo: NationalOpened(
            view.today,
            country: game,
            region: country.def.regions[r].key,
            format: format.id,
            count: count,
            cost: cost.timesInt(count),
            earns: first[r]!.earns,
            paybackMonths: first[r]!.payback,
          ),
        ));
      }
    }
  }
  // Soonest paid back first, so what the cash runs short of is the least
  // good.
  picks.sort((a, b) => a.memo.paybackMonths.compareTo(b.memo.paybackMonths));
  return picks;
}
