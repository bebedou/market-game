import '../accounting/ledger.dart';
import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/safe_int.dart';
import '../core/money.dart';
import '../observation/observation.dart';
import '../state/entities.dart';
import '../state/store.dart';
import 'policy.dart';

/// An AI owner's expansion. Once a month, on a day of its own, it estimates
/// for each vacant site how soon a new store there would repay its opening
/// cost, and opens one at the best site if that is within the strategy's
/// payback period and it can fund the store from personal cash. An owner who
/// already trades must be in profit, and its latest store must have been
/// open for the strategy's expansion interval.
///
/// Where businesses change hands, an owner who trades first looks for a
/// struggling store of its format, owned by anyone but the player: one
/// losing money after a year of trading and a year with its owner. It buys
/// the one that would repay its price soonest, within the payback period,
/// if its latest store opened or was bought long enough ago and its company
/// and personal cash cover the price and a reserve.
///
/// It sees no more than anyone else: its estimate splits an assumed margin
/// per household, at the latest census and scaled by the market's price and
/// income levels, among the stores of its channel trading in the market, by
/// location and size, and
/// counts rent, overheads and one member of staff per slot it would open.
final class EntrepreneurPolicy implements Policy {
  const EntrepreneurPolicy(this.strategy);

  final StrategyDef strategy;

  /// Months of rent and wages a new store starts with, on top of its opening
  /// cost.
  static const startingMonths = 3;

  /// Days of stock a new store starts with, at the strategy's opening
  /// forecast for every shelf slot.
  static const startingStockDays = 14;

  @override
  List<Command> decide(Observation view, ContentDb content) {
    if (strategy.expansionPaybackMonths == 0 ||
        view.today.date.day != 1 + view.actor.index * 9 % 28) {
      return const [];
    }
    if (content.acquisitions case final terms?) {
      final purchase = _purchase(view, content, terms);
      if (purchase.isNotEmpty) return purchase;
    }
    if (!_readyToGrow(view, strategy.expansionIntervalDays)) return const [];

    SiteDef? best;
    var bestPayback = 0;
    for (final id in view.vacantSites) {
      final site = content.sites[id.index];
      final payback = paybackMonths(view, content, site);
      if (payback == null || payback > strategy.expansionPaybackMonths) {
        continue;
      }
      if (best == null || payback < bestPayback) {
        best = site;
        bestPayback = payback;
      }
    }
    if (best == null) return const [];
    final capital = startingCapital(view, content, best);
    if (view.cash < capital) return const [];
    final company = view.companies
        .where((company) => company.status == CompanyStatus.active)
        .firstOrNull;
    return [
      OpenStore(
        view.actor,
        site: best.id,
        name: best.name,
        company: company?.id,
        capital: capital,
        format: strategy.format,
      ),
    ];
  }

  /// The opening cost, [startingMonths] of rent and wages, and
  /// [startingStockDays] of stock at the base cost of the average product
  /// its format sells.
  Money startingCapital(Observation view, ContentDb content, SiteDef site) {
    final level = view.macro.priceIndex;
    // The average cost of what the strategy's format sells.
    final format = content.formats[strategy.format.index];
    final sold = [
      for (final product in content.products)
        if (format.sells[product.category.index]) product,
    ];
    final averageCost = Money(
      sold.fold(0, (sum, p) => sum + p.baseCost.cents) ~/ sold.length,
    );
    final stockUnits = strategy.openingForecast
        .timesInt(site.shelfSlots * startingStockDays)
        .roundToInt();
    final monthly =
        _monthlyCosts(content, site).times(level) +
        _dailyWages(view, content, site).timesInt(30);
    return _fitOut(content, site).times(level) +
        monthly.timesInt(startingMonths) +
        averageCost.times(level).timesInt(stockUnits);
  }

  /// [site]'s rent and the strategy's format's overheads there, a month at
  /// a price index of 1.
  Money _monthlyCosts(ContentDb content, SiteDef site) =>
      site.rent +
      content.formats[strategy.format.index].overheadsFor(site.area);

  /// What fitting out [site] costs for the strategy's format.
  Money _fitOut(ContentDb content, SiteDef site) =>
      site.openingCost.times(content.formats[strategy.format.index].fitOut);

  /// One member of staff in each slot the strategy opens, at [site]'s wages
  /// for the strategy's format.
  Money _dailyWages(Observation view, ContentDb content, SiteDef site) =>
      content.operations.slotWage
          .times(
            view.macro.wageIndex * content.markets[site.market.index].wageLevel,
          )
          .times(content.formats[strategy.format.index].wageFactor)
          .timesInt(strategy.hours.where((open) => open).length);

  /// Commands buying the struggling store [EntrepreneurPolicy] looks for,
  /// the owner first putting in personal cash; none if there is no such
  /// store or the owner isn't ready.
  List<Command> _purchase(
    Observation view,
    ContentDb content,
    AcquisitionDef terms,
  ) {
    final company = view.companies
        .where((company) => company.status == CompanyStatus.active)
        .firstOrNull;
    if (company == null || company.stores.isEmpty) return const [];
    if (!_readyToGrow(view, terms.intervalDays)) return const [];
    ShelfView? best;
    var bestPayback = 0;
    var price = Money.zero;
    for (final shelf in view.shelves) {
      if (shelf.status == StoreStatus.closed ||
          shelf.format != strategy.format) {
        continue;
      }
      final value = view.valuations[shelf.id.index];
      final owner = view.companyOwners[shelf.company.index];
      if (value == null ||
          !value.earnings.isNegative ||
          owner == view.actor ||
          owner == content.player) {
        continue;
      }
      final since = shelf.acquiredOn ?? shelf.opensOn;
      if (view.today.number - since.number < 365) continue;
      final payback = paybackMonths(
        view,
        content,
        content.sites[shelf.site.index],
        cost: value.price,
        existing: true,
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
    if (best == null) return const [];
    final needed = price + price.times(terms.buyerReserve);
    if (company.cash + view.cash < needed) return const [];
    // What the company lacks; on the first, when its owner may take a
    // dividend first, all of it.
    var capital = view.today.isFirstOfMonth ? needed : needed - company.cash;
    if (capital > view.cash) capital = view.cash;
    return [
      if (capital > Money.zero)
        InjectCapital(view.actor, company: company.id, amount: capital),
      BuyStore(view.actor, store: best.id, company: company.id),
    ];
  }

  /// True for a newcomer; for an owner who trades, true if its companies are
  /// in profit overall and its latest store opened or was bought at least
  /// [interval] days ago. Either way, a bankruptcy must be at least as far
  /// in the past.
  bool _readyToGrow(Observation view, int interval) {
    if (view.lastBankruptcy case final day?
        when view.today.number - day.number < interval) {
      return false;
    }
    var profit = Money.zero;
    var latest = -1;
    for (final company in view.companies) {
      if (company.status != CompanyStatus.active) continue;
      profit +=
          company.retainedEarnings + company.balance(AccountKind.dividends);
      for (final store in company.stores) {
        final since = store.acquiredOn ?? store.opensOn;
        if (since.number > latest) latest = since.number;
      }
    }
    if (latest < 0) return true;
    return profit > Money.zero && view.today.number - latest >= interval;
  }

  /// Months for a store at [site] to earn back [cost], its opening cost by
  /// default, or null if it wouldn't make a profit at all. For an
  /// [existing] store, the site is among those trading already. Its margin
  /// is taken as [judged] times the estimate: one for an owner, who judges
  /// only from what everyone sees.
  int? paybackMonths(
    Observation view,
    ContentDb content,
    SiteDef site, {
    Money? cost,
    bool existing = false,
    Fx judged = Fx.one,
  }) {
    // The latest census: the market as everyone can see it.
    final households = view.households[site.market.index];
    // Each store of the channel draws by its location and its size, as
    // shoppers weigh size (see DemandDef.halfSizeArea).
    final half = content.demand.halfSizeArea;
    Fx pull(Fx location, int area) =>
        location * Fx.raw(mulDivRound(area, Fx.scale, area + half));
    final mine = pull(site.location, site.area);
    var total = existing ? Fx.zero : mine;
    for (final shelf in view.shelves) {
      if (shelf.market == site.market &&
          content.formatChannels[shelf.format.index] ==
              content.formatChannels[strategy.format.index] &&
          shelf.status != StoreStatus.closed) {
        total += pull(shelf.location, shelf.area);
      }
    }
    if (total <= Fx.zero) return null;
    final share = mine.div(total);
    final level = view.macro.priceIndex;
    final market = content.markets[site.market.index];
    // Margins follow what households here think normal, and how well off
    // they are.
    final daily = strategy.marginPerHousehold
        .times(level * market.priceLevel * market.incomeLevel)
        .timesInt(households)
        .times(share * judged);
    final monthly =
        (daily - _dailyWages(view, content, site)).timesInt(30) -
        _monthlyCosts(content, site).times(level);
    if (monthly <= Money.zero) return null;
    final opening = cost ?? _fitOut(content, site).times(level);
    return (opening.cents + monthly.cents - 1) ~/ monthly.cents;
  }
}
