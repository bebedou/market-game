import '../accounting/ledger.dart';
import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../observation/observation.dart';
import '../state/director.dart';
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
/// error, drawn from [judgment] for each site; null judges exactly.
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
  if (!today.isFirstOfMonth) return commands;

  for (final store in company.stores) {
    if (!closing.contains(store.id)) continue;
    final (:revenue, :profit, days: _) = store.recentMonths;
    give(
      CloseStore(view.actor, store: store.id),
      StoreClosed(today, store: store.id, sales: revenue, loss: -profit),
    );
  }

  final reserve = operatingReserve(view, company, strategy.reserveDays);
  if (reserve == null) return commands;
  var spare = budget - reserve - company.taxAccrued;
  // What the bank still lends on the company's earnings, if they may ask.
  var credit = director.borrows
      ? view.companyCredits[company.id.index] ?? Money.zero
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
  if (director.allows(Growth.invest) && profit > Money.zero) {
    for (final store in company.stores) {
      if (store.status == StoreStatus.closed || closing.contains(store.id)) {
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

  if (director.allows(Growth.open) && profit > Money.zero) {
    final growth = _growth(
      view,
      content,
      company,
      strategy,
      judgment,
      spare,
      credit,
    );
    switch (growth) {
      case (:final command, :final memo, :final cost, :final borrowed)
          when cost <= spare + borrowed:
        give(command, memo);
        // A loan takes all there was to spare, and leaves nothing to pay out.
        spare = borrowed > Money.zero ? Money.zero : spare - cost;
        if (memo is StoreOpened) retained -= memo.cost;
      case (:final command, :final cost, memo: _, borrowed: _):
        saving ??= ProfitKept(
          today,
          site: command is OpenStore ? command.site : null,
          store: command is BuyStore ? command.store : null,
          needed: cost,
        );
      case null:
    }
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
) {
  if (strategy.format == store.format) return strategy.id;
  final fitting = [
    for (final option in content.strategies)
      if (option.format == store.format) option,
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
/// period, and come the strategy's interval after the company's latest
/// store. If the brief lets them borrow and no struggling store will do,
/// they also buy the profitable rival's store that repays soonest, within
/// [buyoutPaybackMonths], if the bank lends what that takes.
({Command command, Memo memo, Money cost, Money borrowed})? _growth(
  Observation view,
  ContentDb content,
  CompanyView company,
  StrategyDef strategy,
  Rng Function(int entity)? judgment,
  Money spare,
  Money credit,
) {
  final director = company.director!;
  final owner = EntrepreneurPolicy(strategy);
  final grade = content.directors!.grades[director.grade.index];
  final error = content.directors!.judgmentError * (Fx.one - grade.skill);
  Fx judged(SiteId site) => switch (judgment) {
    final judgment? => judgmentFactor(
      judgment(company.id.index * content.sites.length + site.index),
      error,
    ),
    null => Fx.one,
  };
  var latest = company.founded.number;
  for (final store in company.stores) {
    final since = (store.acquiredOn ?? store.opensOn).number;
    if (since > latest) latest = since;
  }
  final waited = view.today.number - latest;
  final term = content.finance.maxTermMonths;

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
      when director.allows(Growth.buy) && waited >= terms.intervalDays) {
    Money withReserve(Money price) => price + price.times(terms.buyerReserve);
    ShelfView? best;
    var bestPayback = 0;
    var price = Money.zero;
    ShelfView? profitable;
    var profitablePayback = buyoutPaybackMonths + 1;
    for (final shelf in view.shelves) {
      if (shelf.status == StoreStatus.closed ||
          shelf.format != strategy.format ||
          view.companyOwners[shelf.company.index] == view.actor) {
        continue;
      }
      final value = view.valuations[shelf.id.index];
      if (value == null) continue;
      final since = shelf.acquiredOn ?? shelf.opensOn;
      if (view.today.number - since.number < 365) continue;
      if (!value.earnings.isNegative) {
        if (!director.borrows) continue;
        final expected = value.earnings.times(judged(shelf.site));
        if (expected <= Money.zero) continue;
        final payback = mulDivRound(value.price.cents, 12, expected.cents);
        final cost = withReserve(value.price);
        if (payback < profitablePayback &&
            cost <= spare + borrowing(cost, earnings: value.earnings)) {
          profitable = shelf;
          profitablePayback = payback;
        }
        continue;
      }
      final payback = owner.paybackMonths(
        view,
        content,
        content.sites[shelf.site.index],
        cost: value.price,
        existing: true,
        judged: judged(shelf.site),
      );
      if (payback == null || payback > strategy.expansionPaybackMonths) {
        continue;
      }
      if (best == null || payback < bestPayback) {
        best = shelf;
        bestPayback = payback;
        price = value.price;
      }
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
    final site = content.sites[id.index];
    if (site.area < format.minArea) continue;
    final payback = owner.paybackMonths(
      view,
      content,
      site,
      judged: judged(id),
    );
    if (payback == null || payback > strategy.expansionPaybackMonths) {
      continue;
    }
    if (best == null || payback < bestPayback) {
      best = site;
      bestPayback = payback;
    }
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
      cost: best.openingCost.times(format.fitOut).times(view.macro.priceIndex),
      paybackMonths: bestPayback,
      borrowed: borrowed,
    ),
    cost: cost,
    borrowed: borrowed,
  );
}
