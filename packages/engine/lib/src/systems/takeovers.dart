import '../accounting/ledger.dart';
import '../commands/apply_command.dart' show lendForTakeover;
import '../commands/stock_trades.dart' show orderImpact, orderValue;
import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';
import '../commands/transfers.dart' show transferCompany;
import '../state/credit.dart';
import '../state/entities.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'national.dart' show ownerShops, tableCountry;
import 'stocks.dart';
import 'tick_system.dart';

/// What the bank lends the player's holding for a takeover, secured on the
/// shares it buys: the target's earnings for the share bought times the
/// bank's multiple, then what the player can guarantee; null if it won't
/// lend [amount].
Money? holdingCredit(
  WorldState world,
  ContentDb content,
  Money amount,
  Money earnings,
) {
  final loan = splitLoan(
    amount,
    credit: earnings.times(content.finance.earningsMultiple),
    guarantee: guaranteeRoom(world, content, world.persons[world.player.index]),
  );
  return loan == null ? null : amount;
}

/// A year of company [i]'s profit, for the share of it in [units].
Money earningsOf(StockMarket market, int i, int units) {
  final stock = market.stocks[i];
  final profit = stock.yearProfit;
  if (profit <= Money.zero) return Money.zero;
  return Money(mulDivRound(profit.cents ~/ 100, units, stock.shares) * 100);
}

/// What a share of company [i] is worth to its holders before any bid: the
/// higher of its price and what analysts think it worth.
Money holdersPrice(StocksDef def, StockMarket market, int i) {
  final stock = market.stocks[i];
  final analysts = analystPrice(def, market, i);
  return stock.price > analysts ? stock.price : analysts;
}

/// The share of a free float that accepts a bid of [price]: as its premium
/// over [reference], what a share was worth to its holders, rises past
/// [StockRulesDef.acceptFrom], over [StockRulesDef.acceptSpan], up to
/// [StockRulesDef.acceptMost].
Fx freeFloatAccepting(StocksDef def, Money reference, Money price) {
  final rules = def.rules;
  if (reference <= Money.zero) return rules.acceptMost;
  final premium = moneyRatio(price, reference) - Fx.one;
  final part = (premium - rules.acceptFrom).div(rules.acceptSpan);
  if (part <= Fx.zero) return Fx.zero;
  return part > rules.acceptMost ? rules.acceptMost : part;
}

/// Whether raider [r] tenders its shares of company [i] into a bid of
/// [price]: once it pays [StockRulesDef.raiderSell] over what the company
/// is worth a share.
bool raiderAccepts(StocksDef def, StockMarket market, int i, Money price) {
  final stock = market.stocks[i];
  final worth = Money(stock.worth.cents ~/ stock.shares);
  return price >= worth + worth.times(def.rules.raiderSell);
}

/// The shares of company [i] that would accept [bid] today, the bidder's
/// own included.
int acceptingUnits(StocksDef def, StockMarket market, Bid bid) {
  final i = bid.stock;
  final stock = market.stocks[i];
  var accepted = 0;
  var held = 0;
  for (final holding in market.holdings) {
    if (holding.index || holding.of != i) continue;
    held += holding.units;
    final owner = holding.owner;
    final bidderSide =
        owner == bid.bidder || (isPlayers(owner) && isPlayers(bid.bidder));
    if (bidderSide ||
        (isPlayers(owner) && bid.tender) ||
        (isRaider(owner) && raiderAccepts(def, market, i, bid.price))) {
      accepted += holding.units;
    }
  }
  final free = stock.shares - held;
  if (free > 0) {
    final part = freeFloatAccepting(def, bid.reference, bid.price);
    accepted += mulDivRound(free, part.raw, Fx.scale);
  }
  return accepted;
}

/// What the bidder's side already holds of company [i]: theirs, and for the
/// player, everything the player and their companies hold.
int bidderUnits(StockMarket market, Bid bid) => isPlayers(bid.bidder)
    ? market.playersUnits(bid.stock)
    : market.unitsOf(bid.stock, bid.bidder);

/// Closes every bid whose month is up: won if more than half accept and the
/// bidder can pay, else lost or lapsed.
void closeBids(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
  CountryEconomy? economy,
) {
  for (final bid in market.bids) {
    if (bid.status != BidStatus.open || context.day < bid.closes) continue;
    final stock = market.stocks[bid.stock];
    if (!stock.listed) {
      bid.status = BidStatus.lapsed;
      context.events.add(BidClosed(number: bid.number, won: false));
      continue;
    }
    final accepted = acceptingUnits(def, market, bid);
    bid.accepted = accepted;
    if (accepted * 2 <= stock.shares) {
      bid.status = BidStatus.lost;
      context.events.add(BidClosed(number: bid.number, won: false));
      continue;
    }
    final won = _settle(world, context, def, market, economy, bid);
    bid.status = won ? BidStatus.won : BidStatus.lapsed;
    context.events.add(BidClosed(number: bid.number, won: won));
  }
  // Keep a year of closed bids.
  market.bids.removeWhere(
    (bid) =>
        bid.status != BidStatus.open &&
        context.day.number - bid.closes.number > 365,
  );
}

/// Settles [bid], which more than half accepted: the bidder pays for the
/// shares it gets, borrowing what it asked to; a chain joins the bidding
/// company whole, and a company by formula comes under the bidder's
/// control, leaving its exchange once nearly all of it is held. The
/// player's other holdings count towards the player's control but stay
/// theirs, unless everyone is bought out. False if the bidder can't pay.
bool _settle(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
  CountryEconomy? economy,
  Bid bid,
) {
  final content = context.content;
  final ledger = context.ledger;
  final rules = def.rules;
  final i = bid.stock;
  final stock = market.stocks[i];
  final listing = listingOf(def, market, i);
  final bidder = bid.bidder;
  final whole =
      listing.kind == ListingKind.chain ||
      listing.kind == ListingKind.company ||
      bid.accepted * Fx.scale >= stock.shares * rules.squeezeOut.raw;
  final own = market.unitsOf(i, bidder);
  final buying = whole
      ? stock.shares - own
      : bid.accepted - bidderUnits(market, bid);
  final cost = bid.price.timesInt(buying > 0 ? buying : 0);
  // The competition authority judges a chain as it joins the bidder, by
  // what its owner holds then.
  if (listing.kind == ListingKind.chain && economy != null && bidder >= 0) {
    final chain = chainOf(content, economy, listing)!;
    final index = economy.countries.indexWhere((c) => c.chains.contains(chain));
    final held = ownerShops(
      world,
      content,
      economy,
      index,
      world.companies[bidder].owner,
      chain.def.trade,
    );
    if (!economy.mayBuy(
      economy.countries[index],
      chain.def.trade,
      held,
      chain.stores,
    )) {
      return false;
    }
  }
  if (bid.via < 0) {
    if (isChain(bidder)) {
      final chain = _bidderChain(world, bidder);
      if (chain == null || chain.cash < cost) return false;
    } else if (isRaider(bidder)) {
      final cash = market.raiders[raiderOf(bidder)].cash;
      if (cash.times(rules.raiderLeverage) < cost) return false;
    } else {
      if (ownerCash(world, market, bidder) + bid.borrow < cost) return false;
      if (bid.borrow > Money.zero) {
        final earnings = earningsOf(market, i, own + buying);
        if (bidder == holdingOwner) {
          if (holdingCredit(world, content, bid.borrow, earnings) == null) {
            return false;
          }
          _lendHolding(world, content, ledger, market, bid);
        } else if (!lendForTakeover(
          world,
          content,
          ledger,
          world.companies[bidder],
          bid.borrow,
          bid.termMonths,
          earnings,
        )) {
          return false;
        }
      }
    }
  }
  // Sellers: everyone else if all are bought out, else the raiders that
  // accept and the player if they tender; the free float makes up the rest.
  var left = buying;
  for (final holding in [...market.holdings]) {
    if (left <= 0) break;
    if (holding.index || holding.of != i || holding.owner == bidder) continue;
    final sells =
        whole ||
        (!isPlayers(bidder) &&
            ((isRaider(holding.owner) &&
                    raiderAccepts(def, market, i, bid.price)) ||
                (isPlayers(holding.owner) && bid.tender))) ||
        (isPlayers(bidder) &&
            isRaider(holding.owner) &&
            raiderAccepts(def, market, i, bid.price));
    if (!sells) continue;
    final units = holding.units < left ? holding.units : left;
    sellHolding(
      world,
      content,
      ledger,
      market,
      holding,
      units,
      bid.price.timesInt(units),
      fee: Money.zero,
    );
    left -= units;
  }
  if (buying > 0) {
    _pay(world, ledger, market, bid, cost);
    _give(market, bid, buying, cost);
  }
  if (bid.via >= 0) {
    _merge(world, def, market, bid);
    return true;
  }
  if (listing.kind == ListingKind.chain && economy != null && bidder >= 0) {
    _chainJoins(world, content, ledger, def, market, economy, bid, listing);
    return true;
  }
  if (listing.kind == ListingKind.company) {
    _companyTakenOver(world, content, ledger, def, market, bid, listing);
    return true;
  }
  stock.controller = bidder;
  if (isRaider(bidder)) {
    // A raider puts in a good director, to sell it back better run.
    final grades = content.directors?.grades.length ?? 0;
    if (grades >= 2) stock.director = grades - 2;
  }
  if (whole) leaveExchange(def, market, i);
  return true;
}

/// Ends control of every company whose controller's side holds half of it
/// or less: its levers go with it.
void loseControl(StockMarket market) {
  for (final (i, stock) in market.stocks.indexed) {
    final controller = stock.controller;
    if (controller == null) continue;
    final units = isPlayers(controller)
        ? market.playersUnits(i)
        : market.unitsOf(i, controller);
    if (units * 2 > stock.shares) continue;
    stock
      ..controller = null
      ..payoutLever = null
      ..growthLever = 0
      ..debtLever = null
      ..director = null;
  }
}

/// The bidder pays [value] for shares: through its own books, a raider from
/// its cash, a company merging another in by its debt.
void _pay(
  WorldState world,
  Ledger ledger,
  StockMarket market,
  Bid bid,
  Money value,
) {
  if (bid.via >= 0) {
    market.stocks[bid.via].debt += value;
    return;
  }
  if (isChain(bid.bidder)) {
    _bidderChain(world, bid.bidder)!.cash -= value;
    return;
  }
  if (isRaider(bid.bidder)) {
    market.raiders[raiderOf(bid.bidder)].cash -= value;
    return;
  }
  ledger.pay(
    payer: bid.bidder == holdingOwner
        ? world.persons[world.player.index]
        : world.companies[bid.bidder],
    payerAccount: AccountKind.investments,
    payee: world.elsewhere,
    payeeAccount: AccountKind.investments,
    amount: value,
    reason: EntryReason.sharesBought,
  );
}

/// The chain [bidder] stands for.
Chain? _bidderChain(WorldState world, int bidder) {
  final (:country, :chain) = chainOfBidder(bidder);
  final countries = world.national?.countries;
  if (countries == null || country >= countries.length) return null;
  final chains = countries[country].chains;
  return chain < chains.length ? chains[chain] : null;
}

/// A company of the player's taken over: everyone was paid the bid, and the
/// company passes to the richest of the game's other owners, as its new
/// owners' choice to run it; it leaves the exchange.
void _companyTakenOver(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  StocksDef def,
  StockMarket market,
  Bid bid,
  ListingDef listing,
) {
  final company = world.companies[listing.link];
  market.holdings.removeWhere((h) => !h.index && h.of == bid.stock);
  leaveExchange(def, market, bid.stock);
  market.stocks[bid.stock].controller = null;
  Person? heir;
  for (final (p, setup) in content.persons.indexed) {
    if (setup.isPlayer || setup.strategy == null || setup.local) continue;
    final person = world.persons[p];
    if (heir == null ||
        person.accounts[AccountKind.cash] > heir.accounts[AccountKind.cash]) {
      heir = person;
    }
  }
  if (heir == null) return;
  company.injected = Money.zero;
  transferCompany(world, content, ledger, company, heir, Money.zero);
  company.director = null;
}

/// The player's listed companies of which they hold half or less are bid
/// for now and then: by a raider that can pay, or the richest chain of
/// their trade in their country.
void bidForPlayers(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
) {
  final rules = def.rules;
  for (final (i, stock) in market.stocks.indexed) {
    if (stock.own == null || !stock.listed || market.openBid(i) != null) {
      continue;
    }
    if (market.playersUnits(i) * 2 > stock.shares) continue;
    final rng = context.rng(RngStream.stocks, 6000 + i);
    // About once a year.
    if (!rng.chance(const Fx.raw(833))) continue;
    final worth = Money(stock.worth.cents ~/ stock.shares);
    if (stock.price > worth + worth.times(const Fx.raw(1000))) continue;
    final price = stock.price + stock.price.times(rules.raiderPremium);
    final cost = price.timesInt(stock.shares);
    var bidder = -1;
    var funds = Money.zero;
    for (final (r, raider) in market.raiders.indexed) {
      final can = raider.cash.times(rules.raiderLeverage);
      if (can >= cost && can > funds) {
        bidder = raiderOwner(r);
        funds = can;
      }
    }
    final listing = listingOf(def, market, i);
    final trade = def.sectors[listing.sector].trade;
    final key = context.content.countries[listing.country.index].national;
    for (final (c, country)
        in (world.national?.countries ?? const <CountryState>[]).indexed) {
      if (trade == null || country.def.key != key) continue;
      for (final (n, chain) in country.chains.indexed) {
        if (chain.def.independent ||
            !chain.isTrading ||
            world.national!.table.trades[chain.def.trade].key != trade) {
          continue;
        }
        if (chain.cash >= cost && chain.cash > funds) {
          bidder = chainBidder(c, n);
          funds = chain.cash;
        }
      }
    }
    if (bidder == -1) continue;
    openBid(world, context, def, market, i, bidder, price);
  }
}

/// The bidder's holding gains [units], which cost [value].
void _give(StockMarket market, Bid bid, int units, Money value) {
  var held = market.holding(bid.stock, owner: bid.bidder);
  if (held == null) {
    held = Holding(index: false, of: bid.stock, owner: bid.bidder);
    market.holdings.add(held);
  }
  held
    ..units += units
    ..cost += value;
}

/// The company bid for through [bid.via] merges into it: its share of the
/// sector and its debt, and it trades no more.
void _merge(WorldState world, StocksDef def, StockMarket market, Bid bid) {
  final into = market.stocks[bid.via];
  final gone = market.stocks[bid.stock];
  into
    ..share += gone.share
    ..debt += gone.debt;
  if (into.share > 1000000) into.share = 1000000;
  leaveExchange(def, market, bid.stock);
  gone.controller = null;
  market.holdings.removeWhere((h) => !h.index && h.of == bid.stock);
}

/// A chain bid for whole joins the bidding company as its shops by
/// formula, as buying it whole does; what the company paid for its shares
/// becomes what it paid for the business.
void _chainJoins(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  StocksDef def,
  StockMarket market,
  CountryEconomy economy,
  Bid bid,
  ListingDef listing,
) {
  final company = world.companies[bid.bidder];
  final holding = market.holding(bid.stock, owner: bid.bidder)!;
  ledger.post(
    company,
    debit: AccountKind.businessAssets,
    credit: AccountKind.investments,
    amount: holding.cost,
    reason: EntryReason.storeSale,
  );
  market.holdings.remove(holding);
  leaveExchange(def, market, bid.stock);
  final index = tableCountry(content, listing.country)!;
  final chain = chainOf(content, economy, listing)!;
  economy.buyChain(
    index,
    chain,
    company: company.id.index,
    format: bid.format,
    strategy: bid.strategy,
    cost: holding.cost,
  );
}

/// The bank lends the player's holding what [bid] borrows, against the
/// shares it buys.
void _lendHolding(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  StockMarket market,
  Bid bid,
) {
  final rate = lendingRate(
    content,
    world.macro.policyRate,
    world.today,
    guaranteed: false,
    lastBankruptcy: world.persons[world.player.index].lastBankruptcy,
  );
  market.loans.add(
    ShareLoan(
      number: market.nextLoan++,
      stock: bid.stock,
      outstanding: bid.borrow,
      rate: rate,
      installmentsLeft: bid.termMonths,
    ),
  );
  ledger.pay(
    payer: world.bank,
    payerAccount: AccountKind.loans,
    payee: world.persons[world.player.index],
    payeeAccount: AccountKind.loans,
    amount: bid.borrow,
    reason: EntryReason.loan,
  );
}

/// The holding pays each loan's monthly instalment, interest and an equal
/// part of what is left; short of cash, the bank sells the shares it holds
/// as security to repay it all.
void payShareLoans(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
) {
  final ledger = context.ledger;
  final player = world.persons[world.player.index];
  for (final loan in [...market.loans]) {
    final interest = Money(
      mulDivRound(loan.outstanding.cents, loan.rate.raw, 12 * Fx.scale),
    );
    final principal = loan.installmentsLeft <= 1
        ? loan.outstanding
        : Money(loan.outstanding.cents ~/ loan.installmentsLeft);
    if (player.accounts[AccountKind.cash] < interest + principal) {
      _foreclose(world, context, def, market, loan, interest);
      continue;
    }
    _repay(world, ledger, loan, interest, principal);
    loan.installmentsLeft--;
    if (loan.outstanding <= Money.zero) market.loans.remove(loan);
  }
}

void _repay(
  WorldState world,
  Ledger ledger,
  ShareLoan loan,
  Money interest,
  Money principal,
) {
  final player = world.persons[world.player.index];
  if (interest > Money.zero) {
    ledger.pay(
      payer: player,
      payerAccount: AccountKind.interest,
      payee: world.bank,
      payeeAccount: AccountKind.revenue,
      amount: interest,
      reason: EntryReason.interest,
    );
  }
  if (principal > Money.zero) {
    ledger.pay(
      payer: player,
      payerAccount: AccountKind.loans,
      payee: world.bank,
      payeeAccount: AccountKind.loans,
      amount: principal,
      reason: EntryReason.loanRepayment,
    );
  }
  loan.outstanding -= principal;
}

/// The bank sells the holding's shares that secure [loan] at the market and
/// repays it all, with [interest]; the rest of the money is the player's.
void _foreclose(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
  ShareLoan loan,
  Money interest,
) {
  final holding = market.holding(loan.stock);
  if (holding != null) {
    final stock = market.stocks[loan.stock];
    final value = stock.price.timesInt(holding.units);
    sellHolding(
      world,
      context.content,
      context.ledger,
      market,
      holding,
      holding.units,
      value,
      fee: Money.zero,
    );
    if (stock.controller == holdingOwner) stock.controller = null;
  }
  final player = world.persons[world.player.index];
  final cash = player.accounts[AccountKind.cash];
  final due = interest + loan.outstanding;
  final paid = cash < due ? cash : due;
  final paidInterest = paid < interest ? paid : interest;
  _repay(world, context.ledger, loan, paidInterest, paid - paidInterest);
  market.loans.remove(loan);
  context.events.add(ShareLoanCalled(stock: loan.stock));
}

/// Opens a bid by [bidder] for company [i] at [price], replacing any lower
/// one still open; the price moves most of the way to it, as the market
/// expects it to win.
Bid openBid(
  WorldState world,
  TickContext? context,
  StocksDef def,
  StockMarket market,
  int i,
  int bidder,
  Money price, {
  int via = -1,
  Money borrow = Money.zero,
  int termMonths = 0,
  int format = -1,
  int strategy = -1,
  bool tender = false,
}) {
  final stock = market.stocks[i];
  final open = market.openBid(i);
  final reference = open?.reference ?? holdersPrice(def, market, i);
  if (open != null) open.status = BidStatus.lapsed;
  final bid = Bid(
    number: market.nextBid++,
    stock: i,
    bidder: bidder,
    via: via,
    price: price,
    opened: world.today,
    closes: Day(world.today.number + def.rules.offerDays),
    reference: reference,
    borrow: borrow,
    termMonths: termMonths,
    format: format,
    strategy: strategy,
  )..tender = tender;
  market.bids.add(bid);
  // Most of the way to the bid: the market doubts a little.
  final aim = price - price.times(const Fx.raw(500));
  if (aim > stock.price) stock.mood += moodRatio(aim, stock.price);
  context?.events.add(BidOpened(number: bid.number));
  return bid;
}

/// Each raider's month: it sells what has become dear, adds to its stakes
/// in what its style finds cheapest, and a raider bids for a company it
/// holds enough of while it is still cheap.
void moveRaiders(
  WorldState world,
  TickContext context,
  StocksDef def,
  StockMarket market,
) {
  final rules = def.rules;
  for (final (r, raiderDef) in def.raiders.indexed) {
    final owner = raiderOwner(r);
    final raider = market.raiders[r];
    final rng = context.rng(RngStream.stocks, 5000 + r);
    // Sell out of a company it controls, a part a month, once it is run
    // well or has run past its worth: back on its exchange if it was held
    // whole.
    for (final holding in [...market.holdings]) {
      if (holding.owner != owner || holding.index) continue;
      final i = holding.of;
      final stock = market.stocks[i];
      if (stock.controller != owner) continue;
      final worth = Money(stock.worth.cents ~/ stock.shares);
      final proven =
          stock.management > averageManagement &&
          world.today.number - stock.managementSince.number >=
              30 * rules.unprovenMonths;
      if (!proven && stock.price < worth + worth.times(rules.raiderSell)) {
        continue;
      }
      if (!stock.listed) joinExchange(def, market, i);
      var units = mulDivRound(
        stock.shares,
        rules.raiderSell.raw ~/ 5,
        Fx.scale,
      );
      if (units > holding.units) units = holding.units;
      if (units <= 0) continue;
      final value = orderValue(
        rules,
        stock.price,
        stock.shares,
        units,
        buy: false,
      );
      stock.mood -= orderImpact(rules, units, stock.shares);
      sellHolding(
        world,
        context.content,
        context.ledger,
        market,
        holding,
        units,
        value,
        fee: Money.zero,
      );
    }
    // Sell what has run well past its worth, or no longer fits its style,
    // unless it controls it or bids for it.
    for (final holding in [...market.holdings]) {
      if (holding.owner != owner || holding.index) continue;
      final i = holding.of;
      final stock = market.stocks[i];
      if (!stock.listed || stock.controller == owner) continue;
      if (market.openBid(i)?.bidder == owner) continue;
      final worth = Money(stock.worth.cents ~/ stock.shares);
      final dear = stock.price >= worth + worth.times(rules.raiderSell);
      if (!dear && _stillFits(stock, raiderDef.style)) continue;
      final value = orderValue(
        rules,
        stock.price,
        stock.shares,
        holding.units,
        buy: false,
      );
      stock.mood -= orderImpact(rules, holding.units, stock.shares);
      sellHolding(
        world,
        context.content,
        context.ledger,
        market,
        holding,
        holding.units,
        value,
        fee: Money.zero,
      );
    }
    // Add to the stakes it holds, then start new ones, the cheapest by its
    // style first.
    final held = <int>[];
    for (final holding in market.holdings) {
      if (holding.owner == owner && !holding.index) held.add(holding.of);
    }
    var stakes = held.length;
    final ranked = [
      ...held,
      for (final i in _candidates(def, market, raiderDef.style, rng))
        if (!held.contains(i)) i,
    ];
    for (final i in ranked) {
      if (raider.cash <= Money.zero) break;
      final stock = market.stocks[i];
      if (!stock.listed || stock.controller != null) continue;
      final units0 = market.unitsOf(i, owner);
      if (units0 == 0 && stakes >= rules.raiderStakes) continue;
      final most = mulDivRound(
        stock.shares,
        rules.raiderMaxStake.raw,
        Fx.scale,
      );
      var units = mulDivRound(stock.shares, rules.raiderBuy.raw, Fx.scale);
      if (units0 + units > most) units = most - units0;
      final afford = raider.cash.cents ~/ (stock.price.cents + 1);
      if (units > afford) units = afford;
      if (units <= 0) continue;
      final value = orderValue(
        rules,
        stock.price,
        stock.shares,
        units,
        buy: true,
      );
      stock.mood += orderImpact(rules, units, stock.shares);
      buyHolding(world, context.ledger, market, owner, i, units, value);
      if (units0 == 0) stakes++;
    }
    if (raiderDef.style != RaiderStyle.raider) continue;
    // Bid for a company it holds enough of, while it is cheap.
    if (market.bids.any(
      (b) => b.bidder == owner && b.status == BidStatus.open,
    )) {
      continue;
    }
    for (final holding in market.holdings) {
      if (holding.owner != owner || holding.index) continue;
      final i = holding.of;
      final stock = market.stocks[i];
      if (!stock.listed ||
          stock.controller != null ||
          market.openBid(i) != null ||
          holding.units * Fx.scale < stock.shares * rules.raiderBidStake.raw) {
        continue;
      }
      final listing = listingOf(def, market, i);
      if (listing.kind != ListingKind.formula) continue;
      // Not once its price has run well past what it is worth.
      final worth = Money(stock.worth.cents ~/ stock.shares);
      if (stock.price > worth + worth.times(const Fx.raw(1000))) continue;
      // A premium of a few points either side of its usual.
      final premium = rules.raiderPremium + Fx.raw(rng.nextInt(1001) - 500);
      final price = stock.price + stock.price.times(premium);
      final cost = price.timesInt(stock.shares - holding.units);
      if (raider.cash.times(rules.raiderLeverage) < cost) continue;
      openBid(world, context, def, market, i, owner, price);
      break;
    }
  }
}

/// The listed companies a raider of [style] would buy, best first: for
/// value, the cheapest against their usual price to earnings and run at
/// least averagely; for growth, those whose profit grew most; for a raider,
/// the cheapest against their worth, run averagely or worse.
List<int> _candidates(
  StocksDef def,
  StockMarket market,
  RaiderStyle style,
  Rng rng,
) {
  final scored = <(int, int)>[];
  for (final (i, stock) in market.stocks.indexed) {
    if (!stock.listed || stock.controller != null) continue;
    final kind = listingOf(def, market, i).kind;
    if (kind != ListingKind.formula && kind != ListingKind.chain) continue;
    final multiple = stock.multiple;
    switch (style) {
      case RaiderStyle.value:
        final usual = _usual(stock.multiples);
        if (multiple <= Fx.zero ||
            usual <= Fx.zero ||
            stock.management < averageManagement) {
          continue;
        }
        scored.add((i, multiple.raw * 1000 ~/ usual.raw));
      case RaiderStyle.growth:
        if (stock.results.length < 8) continue;
        var before = Money.zero;
        for (var q = 0; q < 4; q++) {
          before += stock.results[q].profit;
        }
        if (before <= Money.zero) continue;
        final growth = moneyRatio(stock.yearProfit, before);
        scored.add((i, -growth.raw));
      case RaiderStyle.raider:
        if (stock.management > averageManagement) continue;
        final worth = stock.worth.cents ~/ stock.shares;
        if (worth <= 0) continue;
        scored.add((i, stock.price.cents * 1000 ~/ worth));
    }
  }
  // Each raider weighs them a little its own way.
  final weighed = [
    for (final (i, score) in scored)
      (i, score + mulDivRound(score.abs(), rng.nextInt(301) - 150, 1000)),
  ];
  weighed.sort(
    (a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
  );
  return [for (final (i, _) in weighed.take(3)) i];
}

/// Whether [stock] still fits [style]: a value raider holds while it is no
/// dearer than its usual price to earnings, a growth raider while its
/// profit still grows, a raider while it is run averagely or worse.
bool _stillFits(Listing stock, RaiderStyle style) {
  switch (style) {
    case RaiderStyle.value:
      final usual = _usual(stock.multiples);
      final multiple = stock.multiple;
      return multiple > Fx.zero &&
          usual > Fx.zero &&
          multiple.raw * 10 <= usual.raw * 11;
    case RaiderStyle.growth:
      if (stock.results.length < 8) return true;
      var before = Money.zero;
      for (var q = 0; q < 4; q++) {
        before += stock.results[q].profit;
      }
      return before > Money.zero &&
          moneyRatio(stock.yearProfit, before) > const Fx.raw(10500);
    case RaiderStyle.raider:
      return stock.management <= averageManagement;
  }
}

/// The average of [multiples] that were positive, or zero.
Fx _usual(List<Fx> multiples) {
  var sum = 0;
  var n = 0;
  for (final multiple in multiples) {
    if (multiple <= Fx.zero) continue;
    sum += multiple.raw;
    n++;
  }
  return n == 0 ? Fx.zero : Fx.raw(sum ~/ n);
}
