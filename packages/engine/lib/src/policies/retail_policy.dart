import '../accounting/ledger.dart';
import '../commands/apply_command.dart' show conversionCost;
import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../observation/observation.dart';
import '../state/entities.dart';
import '../state/history.dart';
import '../state/store.dart';
import 'cushion.dart';
import 'policy.dart';

/// The most of its sales a manager spends on marketing.
final maxManagedMarketing = Fx.parse('0.08');

/// The share of its sales a store must have lost over its last twelve
/// months for its owner to close it.
final closingLoss = Fx.parse('0.03');

/// An AI way of running stores. Prices start from cost plus a markup and lean
/// toward a position against competitors' prices; stock is ordered up to a
/// forecast of demand, in full only from cash beyond the company's cushion
/// (see [cashCushion]); the assortment keeps the products with the best margin
/// times sales; full stores are enlarged when that pays, dividends held until
/// the works can be paid for; profit beyond a cash reserve and the stores'
/// needs goes to the owner each month,
/// and the owner tops the reserve back up from personal cash when a company
/// that has made money, or is in its first two years, runs short. A store
/// still losing money two years after it opened, and a year after its owner
/// bought it, is closed on the first of the month. Every other number comes
/// from a [StrategyDef].
final class RetailPolicy implements Policy {
  const RetailPolicy(this.strategy);

  final StrategyDef strategy;

  @override
  List<Command> decide(Observation view, ContentDb content) {
    final commands = <Command>[];
    for (final company in view.companies) {
      if (company.status != CompanyStatus.active) continue;
      var budget = company.cash - company.committed;
      final cushion = cashCushion(view, content, company);
      var essentials = cashForEssentials(view, company);
      final reserve = operatingReserve(view, company, strategy.reserveDays);
      final rescue = reserve == null
          ? Money.zero
          : _rescue(view, company, budget, reserve);
      // Whether a store worth enlarging waits for the cash to pay for it.
      var saving = false;
      if (rescue > Money.zero) {
        commands.add(
          InjectCapital(view.actor, company: company.id, amount: rescue),
        );
        budget += rescue;
        essentials += rescue;
      }
      for (final store in company.stores) {
        if (store.status == StoreStatus.closed) continue;
        if (losingStore(view, store)) {
          commands.add(CloseStore(view.actor, store: store.id));
          continue;
        }
        final plan = StorePlan(strategy, content, view, company, store);
        commands
          ..addAll(plan.assortment())
          ..addAll(plan.prices())
          ..addAll(plan.staffing())
          ..addAll(plan.marketing());
        final (orders, spent) = plan.orders(
          budget - cushion,
          essentials: essentials,
        );
        commands.addAll(orders);
        budget -= spent;
        essentials -= spent;
        final profit =
            company.retainedEarnings + company.balance(AccountKind.dividends);
        if (reserve != null && profit > Money.zero) {
          if (plan.conversion() case (
            :final format,
            :final cost,
          ) when cost <= budget - reserve - company.taxAccrued) {
            commands.add(
              ConvertStore(view.actor, store: store.id, format: format),
            );
            budget -= cost;
          } else if (plan.enlargementCost() case final cost?) {
            if (cost <= budget - reserve - company.taxAccrued) {
              commands.add(ExpandStore(view.actor, store: store.id));
              budget -= cost;
            } else {
              saving = true;
            }
          }
        }
      }
      // The stores' needs come first, works being saved for included; the
      // owner takes what is left.
      if (reserve != null && view.today.isFirstOfMonth && !saving) {
        final dividend = _dividend(
          company,
          budget - reserve - company.taxAccrued,
        );
        if (dividend > Money.zero) {
          commands.add(
            PayDividend(view.actor, company: company.id, amount: dividend),
          );
        }
      }
    }
    return commands;
  }

  /// Retained profit, up to the uncommitted cash beyond the reserve.
  Money _dividend(CompanyView company, Money surplus) {
    final retained = company.retainedEarnings;
    return surplus < retained ? surplus : retained;
  }

  /// When uncommitted cash [free] falls below half the reserve, personal
  /// cash to restore the reserve, if the company has made a profit overall
  /// or is in its first two years, while owners expect a new business to
  /// lose money.
  Money _rescue(
    Observation view,
    CompanyView company,
    Money free,
    Money reserve,
  ) {
    final profit =
        company.retainedEarnings + company.balance(AccountKind.dividends);
    final young = view.today.number - company.founded.number < 730;
    if (free.timesInt(2) >= reserve || (profit <= Money.zero && !young)) {
      return Money.zero;
    }
    final needed = reserve - free;
    return needed < view.cash ? needed : view.cash;
  }
}

/// How far whoever plans a store misjudges it: factors on each product's
/// demand forecast and right price, and on shoppers per slot. Owners judge
/// their own stores exactly; managers don't.
final class Judgment {
  const Judgment({
    required this.demand,
    required this.price,
    required this.traffic,
  });

  /// Indexed by [ProductId].
  final List<Fx> demand;

  /// Indexed by [ProductId].
  final List<Fx> price;
  final Fx traffic;
}

/// One store's decisions for the day.
final class StorePlan {
  StorePlan(
    this.strategy,
    this.content,
    this.view,
    this.company,
    this.store, {
    this.judgment,
  }) : _prices = List.of(store.prices);

  final StrategyDef strategy;
  final ContentDb content;
  final Observation view;
  final CompanyView company;
  final StoreView store;

  /// Null for exact judgment.
  final Judgment? judgment;

  /// Shelf prices as this plan leaves them, indexed by [ProductId].
  final List<Money?> _prices;

  /// The economy of the store's country, whose suppliers it buys from.
  late final MacroView _macro = view.economyAt(content, store.market);

  /// Indexed by [ProductId].
  late final List<Fx> _demand = [
    for (final product in content.products) _forecast(product.id),
  ];

  /// Indexed by [ProductId]; null if no supplier sells the product.
  late final List<SupplierDef?> _suppliers = [
    for (final product in content.products) _supplierFor(product),
  ];

  bool _reviewDay(int period) =>
      (view.today.number + store.id.index) % period == 0;

  /// Expected units wanted per day: recent sales plus units missed for lack
  /// of stock or listing, as judged. Days without history count as the
  /// opening forecast.
  Fx _forecast(ProductId product) {
    final window = strategy.forecastDays;
    final days = store.sales.days < window ? store.sales.days : window;
    var units = 0;
    for (final count in const [
      SalesCount.sold,
      SalesCount.outOfStock,
      SalesCount.notListed,
    ]) {
      units += store.sales.total(count, product, days);
    }
    final missing = strategy.openingForecast.raw * (window - days);
    final forecast = Fx.raw(mulDivRound(missing + units * Fx.scale, 1, window));
    return switch (judgment) {
      final judgment? => forecast * judgment.demand[product.index],
      null => forecast,
    };
  }

  /// The cheapest supplier of [product] whose minimum order sells before it
  /// spoils, or failing that the one with the smallest minimum order.
  SupplierDef? _supplierFor(ProductDef product) {
    // A store only ever stocks what its format sells.
    if (!content.formats[store.format.index].sells[product.category.index]) {
      return null;
    }
    final demand = _demand[product.id.index];
    final country = content.countryOf(store.market);
    final carriers = [
      for (final supplier in content.suppliers)
        if (supplier.carries[product.id.index] && supplier.country == country)
          supplier,
    ];
    if (carriers.isEmpty) return null;
    final life = product.shelfLifeDays;
    final sellable = [
      for (final supplier in carriers)
        if (life == null ||
            Fx.fromInt(supplier.minOrderUnits) <= demand.timesInt(life))
          supplier,
    ];
    if (sellable.isEmpty) {
      return carriers.reduce(
        (a, b) => b.minOrderUnits < a.minOrderUnits ? b : a,
      );
    }
    SupplierDef? best;
    var bestPrice = Money.zero;
    for (final supplier in sellable) {
      final price = supplier.unitPrice(
        product,
        _typicalOrder(supplier, demand),
        _macro.priceIndex,
      );
      if (best == null || price < bestPrice) {
        best = supplier;
        bestPrice = price;
      }
    }
    return best;
  }

  int _typicalOrder(SupplierDef supplier, Fx demand) {
    final cycle = _roundUp(demand.timesInt(strategy.orderCycleDays));
    return cycle > supplier.minOrderUnits ? cycle : supplier.minOrderUnits;
  }

  /// The unit cost of [product] from its supplier, at a typical order size.
  Money _cost(ProductDef product) {
    final supplier = _suppliers[product.id.index]!;
    return supplier.unitPrice(
      product,
      _typicalOrder(supplier, _demand[product.id.index]),
      _macro.priceIndex,
    );
  }

  /// Cost plus markup, pulled toward the strategy's position against the
  /// average price competitors in the market charge for [product], as
  /// judged.
  Money _targetPrice(ProductDef product, Money cost) {
    final target = _exactTargetPrice(product, cost);
    return switch (judgment) {
      final judgment? => target.times(judgment.price[product.id.index]),
      null => target,
    };
  }

  Money _exactTargetPrice(ProductDef product, Money cost) {
    // Wholesale prices follow the country; what shoppers accept follows the
    // place, against what goods cost in its country, and the country's
    // normal price for the product, whose margin is paid at its wages.
    final market = content.markets[store.market.index];
    final costLevel = content.costLevel(market.country);
    var base = cost
        .times(Fx.one + strategy.markup)
        .times(
          costLevel == Fx.one
              ? market.priceLevel
              : market.priceLevel.div(costLevel),
        );
    final normal = content.referenceIn(product, market.country);
    if (normal != product.referencePrice) {
      base = Money(
        mulDivRound(base.cents, normal.cents, product.referencePrice.cents),
      );
    }
    var sum = 0;
    var count = 0;
    for (final shelf in view.shelves) {
      final price = shelf.prices[product.id.index];
      if (price == null ||
          shelf.market != store.market ||
          shelf.company == company.id) {
        continue;
      }
      sum += price.cents;
      count++;
    }
    if (count == 0) return base;
    final rivals = Money(
      mulDivRound(sum, 1, count),
    ).times(Fx.one + strategy.marketPosition);
    return base + (rivals - base).times(strategy.marketWeight);
  }

  /// Expected daily gross margin, weighted by the taste for premium.
  Money _score(ProductDef product, Money price, Money cost) {
    final margin = (price - cost).times(_demand[product.id.index]);
    return product.tier == ProductTier.premium
        ? margin.times(strategy.premiumBias)
        : margin;
  }

  /// A new store's empty slots are filled at once with the best-scoring
  /// products. After that, on review days, the best unlisted product takes a
  /// free slot, or replaces the weakest listed one if it scores clearly
  /// better.
  List<Command> assortment() {
    final free = store.shelfSlots - store.listedProducts;
    if (store.sales.days < strategy.forecastDays) {
      return free > 0 ? _fill(free) : const [];
    }
    if (!_reviewDay(strategy.assortmentReviewDays)) return const [];
    ProductDef? weakest;
    var weakestScore = Money.zero;
    ProductDef? best;
    var bestScore = Money.zero;
    var bestPrice = Money.zero;
    for (final product in content.products) {
      if (_suppliers[product.id.index] == null) continue;
      final cost = _cost(product);
      final listed = _prices[product.id.index];
      final price = listed ?? _targetPrice(product, cost);
      final score = _score(product, price, cost);
      if (listed != null) {
        if (weakest == null || score < weakestScore) {
          weakest = product;
          weakestScore = score;
        }
      } else if (best == null || score > bestScore) {
        best = product;
        bestScore = score;
        bestPrice = price;
      }
    }
    if (best == null || bestScore <= Money.zero) return const [];
    final actor = view.actor;
    final commands = <Command>[];
    if (store.listedProducts >= store.shelfSlots) {
      final threshold = weakestScore.times(
        Fx.one + strategy.assortmentHysteresis,
      );
      if (weakest == null || bestScore <= threshold) return const [];
      commands.add(DelistProduct(actor, store: store.id, product: weakest.id));
      _prices[weakest.id.index] = null;
    }
    _prices[best.id.index] = bestPrice;
    commands.add(
      ListProduct(actor, store: store.id, product: best.id, price: bestPrice),
    );
    return commands;
  }

  /// Lists the [slots] best-scoring unlisted products at their target prices.
  List<Command> _fill(int slots) {
    final candidates = <({ProductDef product, Money score, Money price})>[];
    for (final product in content.products) {
      if (_prices[product.id.index] != null ||
          _suppliers[product.id.index] == null) {
        continue;
      }
      final cost = _cost(product);
      final price = _targetPrice(product, cost);
      candidates.add((
        product: product,
        score: _score(product, price, cost),
        price: price,
      ));
    }
    candidates.sort((a, b) {
      final byScore = b.score.cents.compareTo(a.score.cents);
      return byScore != 0 ? byScore : a.product.id.index - b.product.id.index;
    });
    final commands = <Command>[];
    for (final candidate in candidates.take(slots)) {
      if (candidate.score <= Money.zero) break;
      _prices[candidate.product.id.index] = candidate.price;
      commands.add(
        ListProduct(
          view.actor,
          store: store.id,
          product: candidate.product.id,
          price: candidate.price,
        ),
      );
    }
    return commands;
  }

  /// On review days, moves each price toward its target by at most the
  /// strategy's step, cutting it if too many buyers refuse it, and never
  /// below the minimum markup. Prices this plan just set are left alone.
  List<Command> prices() {
    if (!_reviewDay(strategy.priceReviewDays)) return const [];
    final step = strategy.maxPriceStep;
    final commands = <Command>[];
    for (final product in content.products) {
      final i = product.id.index;
      final current = store.prices[i];
      if (current == null || _prices[i] != current || _suppliers[i] == null) {
        continue;
      }
      final cost = _cost(product);
      var target = _targetPrice(product, cost);
      final cut = current.times(Fx.one - step);
      if (_overpriced(product.id) && cut < target) target = cut;
      final raise = current.times(Fx.one + step);
      var price = target < cut ? cut : (target > raise ? raise : target);
      final floor = cost.times(Fx.one + strategy.minMarkup);
      if (price < floor) price = floor;
      if (price == current) continue;
      _prices[i] = price;
      commands.add(
        SetPrice(
          view.actor,
          store: store.id,
          product: product.id,
          price: price,
        ),
      );
    }
    return commands;
  }

  /// On the first of the month, a bigger format of the store's channel the
  /// site can host and what converting to it costs, if the store's shelves
  /// are full, it has products left to stock, and what the new slots would
  /// earn (see [_newSlotsMargin]), less the extra rent and overheads, pays
  /// the works back within the strategy's payback; null otherwise. Like
  /// enlarging, owners count only the new slots.
  ({FormatId format, Money cost})? conversion() {
    if (strategy.expansionPaybackMonths == 0 ||
        !view.today.isFirstOfMonth ||
        store.status != StoreStatus.open ||
        store.works != null) {
      return null;
    }
    final site = content.sites[store.site.index];
    final current = content.formats[store.format.index];
    final channel = content.formatChannels[current.id.index];
    FormatDef? target;
    for (final format in content.formats) {
      if (content.formatChannels[format.id.index] == channel &&
          format.fitOut > current.fitOut &&
          format.minArea <= site.maxArea) {
        target = format;
        break;
      }
    }
    if (target == null) return null;
    var listed = 0;
    var unlisted = 0;
    for (final product in content.products) {
      final i = product.id.index;
      if (!target.sells[product.category.index]) continue;
      if (_prices[i] == null) {
        if (_suppliers[i] != null) unlisted++;
        continue;
      }
      listed++;
    }
    if (listed < store.shelfSlots || unlisted == 0) return null;
    final expansion = content.expansion;
    final area = target.minArea > store.area ? target.minArea : store.area;
    var slots =
        target.slotBonus +
        (area - store.area) ~/ expansion.stepArea * expansion.shelfSlots;
    if (slots > unlisted) slots = unlisted;
    final level = _macro.priceIndex;
    final extraRent =
        (site.rentFor(area) -
                site.rentFor(store.area) +
                target.overheadsFor(area) -
                current.overheadsFor(store.area))
            .times(level);
    final monthly =
        _newSlotsMargin(
          slots,
          (product) => target!.sells[product.category.index],
        ) -
        extraRent;
    final cost = conversionCost(
      content,
      site,
      store.format,
      store.area,
      target,
      level,
    );
    if (monthly <= Money.zero ||
        cost > monthly.timesInt(strategy.expansionPaybackMonths)) {
      return null;
    }
    return (format: target.id, cost: cost);
  }

  /// On the first of the month, what enlarging the store would cost, if its
  /// shelves are full, it has products left to stock, and what the new slots
  /// would earn (see [_newSlotsMargin]), less the extra rent and overheads,
  /// pays the works back within the strategy's payback; null otherwise.
  /// Owners count only the new slots, not the pull of a bigger store. At
  /// most once per expansion interval.
  Money? enlargementCost() {
    if (strategy.expansionPaybackMonths == 0 ||
        !view.today.isFirstOfMonth ||
        store.status != StoreStatus.open ||
        store.works != null) {
      return null;
    }
    final expansion = content.expansion;
    final site = content.sites[store.site.index];
    final area = store.area + expansion.stepArea;
    final since = store.enlargedOn ?? store.opensOn;
    if (area > site.maxArea ||
        view.today.number - since.number < strategy.expansionIntervalDays) {
      return null;
    }
    var listed = 0;
    var unlisted = 0;
    for (final product in content.products) {
      final i = product.id.index;
      if (_suppliers[i] == null) continue;
      if (_prices[i] == null) {
        unlisted++;
      } else {
        listed++;
      }
    }
    if (listed < store.shelfSlots || unlisted == 0) return null;
    final slots = unlisted < expansion.shelfSlots
        ? unlisted
        : expansion.shelfSlots;
    final level = _macro.priceIndex;
    final extraRent =
        (site.rentFor(area) -
                site.rentFor(store.area) +
                content.formats[store.format.index].overheadsFor(
                  area - store.area,
                ))
            .times(level);
    final monthly = _newSlotsMargin(slots, (_) => true) - extraRent;
    final cost = expansion.cost(level);
    if (monthly <= Money.zero ||
        cost > monthly.timesInt(strategy.expansionPaybackMonths)) {
      return null;
    }
    return cost;
  }

  /// What [slots] more shelf slots would earn in a month: the products off
  /// the shelves that shoppers ask for most, among those [sells] allows, at
  /// their target margin on the units asked for, as judged.
  Money _newSlotsMargin(int slots, bool Function(ProductDef product) sells) {
    final margins = <int>[];
    for (final product in content.products) {
      final i = product.id.index;
      if (!sells(product) || _prices[i] != null || _suppliers[i] == null) {
        continue;
      }
      final cost = _cost(product);
      margins.add((_targetPrice(product, cost) - cost).times(_demand[i]).cents);
    }
    margins.sort((a, b) => b - a);
    var total = 0;
    for (final margin in margins.take(slots)) {
      if (margin > 0) total += margin;
    }
    return Money(total * 30);
  }

  /// The share of sales a manager spends on marketing, rounded to half a
  /// percent: where one more euro would bring back about a euro of margin.
  /// Spending a share s of daily sales R settles goodwill at G = s·R/δ,
  /// pulling w·G/(G + H) (see [DemandTuning.marketingWeight]); the margin
  /// that brings is about m·R·w·G/(G + H), where m is what a euro of sales
  /// leaves after the goods, at the strategy's markup, and the store's
  /// staff, which pays best at G = √(m·w·H·R/δ) − H. A thin-margin store
  /// spends little, a rich one more; never below the strategy's share, nor
  /// above [maxManagedMarketing].
  Fx bestMarketingShare() {
    final days = store.sales.days < strategy.forecastDays
        ? store.sales.days
        : strategy.forecastDays;
    var revenue = 0;
    for (final product in content.products) {
      final price = store.prices[product.id.index];
      if (price == null || days == 0) continue;
      revenue += price
          .timesInt(store.sales.total(SalesCount.sold, product.id, days))
          .cents;
    }
    if (revenue == 0) return strategy.marketingShare;
    final daily = revenue ~/ days;
    final demand = content.demand;
    final gross = mulDivRound(
      strategy.markup.raw,
      Fx.scale,
      Fx.scale + strategy.markup.raw,
    );
    final staff = mulDivRound(
      dailyStaffCost(view, content, store).cents,
      Fx.scale,
      daily,
    );
    if (gross <= staff) return strategy.marketingShare;
    final margin = Fx.raw(gross - staff);
    final half = demand.halfGoodwill.times(_macro.priceIndex).cents;
    final scaled = mulDivRound(
      half,
      (margin * demand.marketingWeight).raw,
      demand.goodwillDecay.raw,
    );
    final goodwill = isqrt(mulDivRound(scaled, daily, 1)) - half;
    if (goodwill <= 0) return strategy.marketingShare;
    var share = mulDivRound(goodwill, demand.goodwillDecay.raw, daily);
    share = (share + 25) ~/ 50 * 50;
    if (share > maxManagedMarketing.raw) share = maxManagedMarketing.raw;
    return share < strategy.marketingShare.raw
        ? strategy.marketingShare
        : Fx.raw(share);
  }

  /// A manager's marketing: [bestMarketingShare], reviewed with the prices,
  /// and at once for a store that spends nothing.
  List<Command> managedMarketing() {
    if (store.marketingShare != Fx.zero &&
        !_reviewDay(strategy.priceReviewDays)) {
      return const [];
    }
    final share = bestMarketingShare();
    if (share == store.marketingShare) return const [];
    return [SetMarketing(view.actor, store: store.id, share: share)];
  }

  /// Spends the strategy's share of sales on marketing: owners set a
  /// steady advertising-to-sales ratio, as firms do (the ratio
  /// R. Dorfman and P. O. Steiner show to be optimal, "Optimal advertising
  /// and optimal quality", American Economic Review 44, 1954).
  List<Command> marketing() {
    if (store.marketingShare == strategy.marketingShare) return const [];
    return [
      SetMarketing(view.actor, store: store.id, share: strategy.marketingShare),
    ];
  }

  /// Staffs the strategy's hours to cover expected traffic in each slot
  /// times the service target, reviewed with prices. A store is first
  /// staffed the day it opens.
  List<Command> staffing() {
    if (store.opensOn > view.today) return const [];
    final unstaffed = store.staff.every((count) => count == 0);
    if (!unstaffed && !_reviewDay(strategy.priceReviewDays)) return const [];
    final perStaff = content.formats[store.format.index].visitsPerStaff;
    final most = content.operations.maxStaffPerSlot;
    final window = strategy.forecastDays;
    final days = store.sales.days < window ? store.sales.days : window;
    final misjudged = judgment?.traffic ?? Fx.one;
    final staff = [
      for (final slot in DaySlot.values)
        if (!strategy.hours[slot.index])
          0
        else
          _staffFor(
            Fx.raw(
                  mulDivRound(
                    (strategy.openingTraffic * (window - days) +
                            store.sales.visits(slot, days)) *
                        Fx.scale,
                    1,
                    window,
                  ),
                ) *
                misjudged,
            perStaff,
            most,
          ),
    ];
    for (var slot = 0; slot < staff.length; slot++) {
      if (staff[slot] != store.staff[slot]) {
        return [SetStaffing(view.actor, store: store.id, staff: staff)];
      }
    }
    return const [];
  }

  /// Staff to serve [traffic] visits a day with the strategy's headroom.
  int _staffFor(Fx traffic, int perStaff, int most) {
    final needed = _roundUp(
      Fx.raw((traffic * strategy.serviceTarget).raw ~/ perStaff),
    );
    return needed < 1 ? 1 : (needed > most ? most : needed);
  }

  /// Whether more than the tolerated share of would-be buyers refused
  /// [product]'s price over the forecast window.
  bool _overpriced(ProductId product) {
    final window = strategy.forecastDays;
    final refused = store.sales.total(SalesCount.overpriced, product, window);
    final bought = store.sales.total(SalesCount.sold, product, window);
    return refused * Fx.scale >
        (refused + bought) * strategy.maxOverpricedShare.raw;
  }

  /// Orders each listed product up to its target stock once it falls to its
  /// reorder point, within the store's storage and [budget]. The most
  /// profitable lines come first when cash runs short. A line [budget]
  /// can't pay for in full is topped up only to its reorder point, enough to
  /// keep selling until the next order, if [essentials] covers that; the
  /// least profitable lines go without. Returns the orders and what they
  /// will cost.
  (List<Command>, Money) orders(Money budget, {Money? essentials}) {
    essentials ??= budget;
    // Stock is ordered up to lead-time demand, which is on its way rather
    // than in storage, plus safety and cycle stock, which sit on the shelf.
    final count = content.products.length;
    final transit = List.filled(count, 0);
    final safety = List.filled(count, 0);
    final cycle = List.filled(count, 0);
    for (final product in content.products) {
      final i = product.id.index;
      final supplier = _suppliers[i];
      if (_prices[i] == null || supplier == null) continue;
      final demand = _demand[i];
      var safetyDays = strategy.safetyDays;
      var cycleDays = strategy.orderCycleDays;
      if (product.shelfLifeDays case final life?) {
        // Stock beyond this many days of demand spoils before it sells.
        if (safetyDays > life - 1) safetyDays = life - 1;
        if (cycleDays > life - safetyDays) cycleDays = life - safetyDays;
      }
      transit[i] = _roundUp(demand.timesInt(supplier.leadTimeDays));
      safety[i] = _roundUp(demand.timesInt(safetyDays));
      cycle[i] = _roundUp(demand.timesInt(cycleDays));
    }
    // When storage is short, order more often in smaller batches; only if
    // even the safety stock doesn't fit is it cut too.
    final storage = store.storageUnits;
    final safe = safety.fold(0, (sum, units) => sum + units);
    final cycles = cycle.fold(0, (sum, units) => sum + units);
    final reorderAt = List.filled(count, 0);
    final target = List.filled(count, 0);
    for (var i = 0; i < count; i++) {
      var shelf = safety[i];
      var batch = cycle[i];
      if (safe >= storage) {
        shelf = shelf * storage ~/ safe;
        batch = 0;
      } else if (safe + cycles > storage) {
        batch = batch * (storage - safe) ~/ cycles;
      }
      reorderAt[i] = transit[i] + shelf;
      target[i] = reorderAt[i] + batch;
    }

    final wanted =
        <({ProductDef product, int quantity, int lean, Money margin})>[];
    for (final product in content.products) {
      final i = product.id.index;
      final supplier = _suppliers[i];
      final price = _prices[i];
      if (price == null || supplier == null) continue;
      // A store being fitted out only takes stock that arrives as it opens.
      if (view.today.number + supplier.leadTimeDays < store.opensOn.number) {
        continue;
      }
      final position = store.stock[i] + store.onOrder[i];
      if (position > reorderAt[i] || position >= target[i]) continue;
      var quantity = target[i] - position;
      if (quantity < supplier.minOrderUnits) quantity = supplier.minOrderUnits;
      if (quantity > store.storageUnits) continue;
      var lean = reorderAt[i] - position;
      if (lean < supplier.minOrderUnits) lean = supplier.minOrderUnits;
      if (lean > quantity) lean = quantity;
      final unitPrice = supplier.unitPrice(
        product,
        quantity,
        _macro.priceIndex,
      );
      wanted.add((
        product: product,
        quantity: quantity,
        lean: lean,
        margin: (price - unitPrice).times(_demand[i]),
      ));
    }
    wanted.sort((a, b) {
      final byMargin = b.margin.cents.compareTo(a.margin.cents);
      return byMargin != 0 ? byMargin : a.product.id.index - b.product.id.index;
    });

    var spent = Money.zero;
    final bySupplier = [for (final _ in content.suppliers) <OrderQuantity>[]];
    for (final line in wanted) {
      final supplier = _suppliers[line.product.id.index]!;
      Money costOf(int quantity) => supplier
          .unitPrice(line.product, quantity, _macro.priceIndex)
          .timesInt(quantity);
      var quantity = line.quantity;
      var cost = costOf(quantity);
      if (spent + cost > budget) {
        quantity = line.lean;
        cost = costOf(quantity);
        if (spent + cost > essentials) continue;
      }
      spent += cost;
      bySupplier[supplier.id.index].add((
        product: line.product.id,
        quantity: quantity,
      ));
    }
    final commands = <Command>[
      for (final supplier in content.suppliers)
        if (bySupplier[supplier.id.index].isNotEmpty)
          PlaceOrder(
            view.actor,
            store: store.id,
            supplier: supplier.id,
            lines: bySupplier[supplier.id.index]
              ..sort((a, b) => a.product.index - b.product.index),
          ),
    ];
    return (commands, spent);
  }

  static int _roundUp(Fx units) => (units.raw + Fx.scale - 1) ~/ Fx.scale;
}

/// Whether [store] is to be closed today: on the first of the month, two
/// years after it opened, the time a new store takes to win its custom, and
/// a year after its owner bought it, if they did, if it lost more than
/// [closingLoss] of its sales over its last twelve months (see
/// [StoreView.recentMonths]). A slow month, or a short slump, closes
/// nothing, and an owner keeps a store that about breaks even.
bool losingStore(Observation view, StoreView store) {
  if (!view.today.isFirstOfMonth) return false;
  if (view.today.number - store.opensOn.number < 730) return false;
  if (store.acquiredOn case final bought?
      when view.today.number - bought.number < 365) {
    return false;
  }
  final (:revenue, :profit, :days) = store.recentMonths;
  return days > 0 && -profit > revenue.times(closingLoss);
}

/// [reserveDays] of [company]'s average daily spending on stock, staff, rent
/// and interest since it was founded: the cash an owner keeps aside. Null on
/// its first day, before there is any.
Money? operatingReserve(
  Observation view,
  CompanyView company,
  int reserveDays,
) {
  final days = view.today.number - company.founded.number;
  if (days <= 0) return null;
  final spent =
      company.balance(AccountKind.costOfGoods) +
      company.balance(AccountKind.wages) +
      company.balance(AccountKind.salaries) +
      company.balance(AccountKind.rent) +
      company.balance(AccountKind.overheads) +
      company.balance(AccountKind.interest);
  return Money(mulDivRound(spent.cents, reserveDays, days));
}
