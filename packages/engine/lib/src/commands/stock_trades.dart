import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import '../countries/shop_bridge.dart' show formatTrades;
import '../systems/stocks.dart'
    show
        chainOf,
        joinExchange,
        listOwnCompany,
        listingOf,
        listingPlace,
        ownListing,
        ownerCash,
        sellHolding;
import '../state/credit.dart' show companyEarnings;
import '../state/software_rules.dart' show softwareOf;
import '../systems/takeovers.dart' show earningsOf, holdingCredit, openBid;
import 'apply_command.dart' show wouldLendForTakeover;
import 'command.dart';
import 'refusal.dart';

/// What an order for [units] of a company of [shares] moves its price by,
/// as a log in millionths: [StockRulesDef.impact] for all of it, in
/// proportion.
int orderImpact(StockRulesDef rules, int units, int shares) {
  final part = mulDivRound(units, 1000000, shares);
  return mulDivRound(part, rules.impact.raw, 10000);
}

/// What [units] of a company of [shares] at [price] cost to buy, or bring
/// in sold, before the broker's fee: the price, moved half way by the
/// order's own impact.
Money orderValue(
  StockRulesDef rules,
  Money price,
  int shares,
  int units, {
  required bool buy,
}) {
  final gross = price.timesInt(units);
  final half = orderImpact(rules, units, shares) ~/ 2;
  final moved = Money(mulDivRound(gross.cents, half, 1000000));
  return buy ? gross + moved : gross - moved;
}

/// The broker's fee on an order worth [value].
Money orderFee(StockRulesDef rules, Money value, {required bool index}) =>
    value.times(index ? rules.indexFee : rules.fee);

(StockMarket?, Refusal?) _market(
  WorldState world,
  ContentDb content,
  Command command,
  int of,
  int units, {
  required bool index,
}) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) {
    return (null, const Refusal('noStockMarket'));
  }
  if (command.actor != world.player) {
    return (null, const Refusal('onlyThePlayerTrades'));
  }
  if (units <= 0) return (null, const Refusal('unitsNotPositive'));
  if (index) {
    if (of < 0 || of >= market.exchanges.length) {
      return (null, const Refusal('unknownExchange'));
    }
  } else {
    if (of < 0 || of >= market.stocks.length) {
      return (null, const Refusal('unknownStock'));
    }
    if (!market.stocks[of].listed) {
      return (null, const Refusal('stockNotListed'));
    }
  }
  return (market, null);
}

/// Buys shares of a listed company, or units of an exchange's index, with
/// the player's own money: a company's price moves against a big order.
Refusal? buyShares(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  BuyShares command,
) {
  final (market, refusal) = _market(
    world,
    content,
    command,
    command.of,
    command.units,
    index: command.index,
  );
  if (market == null) return refusal;
  final player = world.persons[world.player.index];
  final holding = market.holding(command.of, index: command.index);
  final Money value;
  if (command.index) {
    value = market.exchanges[command.of].level.timesInt(command.units);
  } else {
    final stock = market.stocks[command.of];
    if ((holding?.units ?? 0) + command.units > stock.shares) {
      return const Refusal('moreThanItsShares');
    }
    value = orderValue(
      content.stocks!.rules,
      stock.price,
      stock.shares,
      command.units,
      buy: true,
    );
  }
  final fee = orderFee(content.stocks!.rules, value, index: command.index);
  if (player.accounts[AccountKind.cash] < value + fee) {
    return const Refusal('notEnoughHoldingCash');
  }
  ledger.pay(
    payer: player,
    payerAccount: AccountKind.investments,
    payee: world.elsewhere,
    payeeAccount: AccountKind.investments,
    amount: value,
    reason: EntryReason.sharesBought,
  );
  if (fee > Money.zero) {
    ledger.pay(
      payer: player,
      payerAccount: AccountKind.investments,
      payee: world.services,
      payeeAccount: AccountKind.revenue,
      amount: fee,
      reason: EntryReason.brokerage,
    );
  }
  var held = holding;
  if (held == null) {
    held = Holding(index: command.index, of: command.of);
    market.holdings.add(held);
  }
  held
    ..units += command.units
    ..cost += value + fee;
  if (!command.index) {
    final stock = market.stocks[command.of];
    stock.mood += orderImpact(
      content.stocks!.rules,
      command.units,
      stock.shares,
    );
  }
  return null;
}

/// Sells shares or index units the player holds: the gain over what they
/// cost is taxed, once past losses are set against it.
Refusal? sellShares(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  SellShares command,
) {
  final (market, refusal) = _market(
    world,
    content,
    command,
    command.of,
    command.units,
    index: command.index,
  );
  if (market == null) return refusal;
  final holding = market.holding(command.of, index: command.index);
  if (holding == null || holding.units < command.units) {
    return const Refusal('notEnoughShares');
  }
  final rules = content.stocks!.rules;
  final Money value;
  if (command.index) {
    value = market.exchanges[command.of].level.timesInt(command.units);
  } else {
    final stock = market.stocks[command.of];
    value = orderValue(
      rules,
      stock.price,
      stock.shares,
      command.units,
      buy: false,
    );
    stock.mood -= orderImpact(rules, command.units, stock.shares);
  }
  final fee = orderFee(rules, value, index: command.index);
  sellHolding(
    world,
    content,
    ledger,
    market,
    holding,
    command.units,
    value,
    fee: fee,
  );
  return null;
}

/// The most a bid may offer over the price.
const maxBidPremium = Fx.raw(10000);

/// The most a controlled company by formula may aim to owe, in years of
/// profit.
const maxDebtLever = Fx.raw(60000);

/// Bids for a listed company: a company by formula, or a chain for one of
/// the player's companies of its trade; at a premium over its price, more
/// than any bid open for it, with what the bidder has and can borrow.
Refusal? bidForCompany(
  WorldState world,
  ContentDb content,
  BidForCompany command,
) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) return const Refusal('noStockMarket');
  if (command.actor != world.player) {
    return const Refusal('onlyThePlayerTrades');
  }
  final i = command.stock;
  if (i < 0 || i >= market.stocks.length) {
    return const Refusal('unknownStock');
  }
  final stock = market.stocks[i];
  if (!stock.listed) return const Refusal('stockNotListed');
  final listing = listingOf(def, market, i);
  if (listing.kind != ListingKind.formula &&
      listing.kind != ListingKind.chain) {
    return const Refusal('notForBids');
  }
  if (stock.controller case final controller? when isPlayers(controller)) {
    return const Refusal('alreadyYours');
  }
  if (command.premium <= Fx.zero || command.premium > maxBidPremium) {
    return const Refusal('premiumRange');
  }
  final bidder = command.bidder;
  if (bidder != holdingOwner) {
    if (bidder < 0 || bidder >= world.companies.length) {
      return const Refusal('unknownCompany');
    }
    final company = world.companies[bidder];
    if (company.owner != world.player || !company.isActive) {
      return const Refusal('notYourCompany');
    }
  }
  if (listing.kind == ListingKind.chain) {
    // Shops need a company: one with a national format of the chain's trade.
    if (bidder == holdingOwner) return const Refusal('chainNeedsCompany');
    if (command.format < 0 || command.format >= content.formats.length) {
      return const Refusal('unknownFormat');
    }
    final format = content.formats[command.format];
    final chain = chainOf(content, world.national, listing);
    final national = world.national;
    if (chain == null ||
        national == null ||
        format.national == null ||
        national.table.trades[chain.def.trade].key !=
            formatTrades[format.key]) {
      return Refusal('formatNotNational', format: format.id);
    }
    if (command.strategy < 0 || command.strategy >= content.strategies.length) {
      return const Refusal('unknownStrategy');
    }
  }
  final price = stock.price + stock.price.times(command.premium);
  if (market.openBid(i) case final open? when open.price >= price) {
    return Refusal('bidTooLow', amount: open.price);
  }
  if (command.borrow < Money.zero) return const Refusal('amountNotPositive');
  if (command.borrow > Money.zero &&
      (command.termMonths < 1 ||
          command.termMonths > content.finance.maxTermMonths)) {
    return Refusal('termRange', count: content.finance.maxTermMonths);
  }
  // Enough to buy everything it lacks: what a bid that wins whole costs.
  final own = market.unitsOf(i, bidder);
  final cost = price.timesInt(stock.shares - own);
  final cash = ownerCash(world, market, bidder);
  if (cash + command.borrow < cost) {
    return Refusal('cannotPayPrice', amount: cost);
  }
  if (command.borrow > Money.zero) {
    final earnings = earningsOf(market, i, stock.shares);
    final lends = bidder == holdingOwner
        ? holdingCredit(world, content, command.borrow, earnings) != null
        : wouldLendForTakeover(
            world,
            content,
            world.companies[bidder],
            command.borrow,
            command.termMonths,
            earnings,
          );
    if (!lends) return const Refusal('bankWillNotLend');
  }
  openBid(
    world,
    null,
    def,
    market,
    i,
    bidder,
    price,
    borrow: command.borrow,
    termMonths: command.termMonths,
    format: command.format,
    strategy: command.strategy,
  );
  return null;
}

/// The player offers their shares into someone else's open bid, or not.
Refusal? answerBid(WorldState world, AnswerBid command) {
  final market = world.stocks;
  if (market == null) return const Refusal('noStockMarket');
  if (command.actor != world.player) {
    return const Refusal('onlyThePlayerTrades');
  }
  final bid = market.bids
      .where((b) => b.number == command.bid && b.status == BidStatus.open)
      .firstOrNull;
  if (bid == null) return const Refusal('noSuchBid');
  if (isPlayers(bid.bidder)) return const Refusal('yourOwnBid');
  bid.tender = command.tender;
  return null;
}

/// The listed company [stock] by formula, if the player controls it.
(Listing?, Refusal?) _controlled(
  WorldState world,
  ContentDb content,
  Command command,
  int stock,
) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) {
    return (null, const Refusal('noStockMarket'));
  }
  if (command.actor != world.player) {
    return (null, const Refusal('onlyThePlayerTrades'));
  }
  if (stock < 0 || stock >= market.stocks.length) {
    return (null, const Refusal('unknownStock'));
  }
  final listing = market.stocks[stock];
  final controller = listing.controller;
  if (controller == null || !isPlayers(controller) || !listing.running) {
    return (null, const Refusal('notControlled'));
  }
  if (listingOf(def, market, stock).kind != ListingKind.formula) {
    return (null, const Refusal('notControlled'));
  }
  return (listing, null);
}

/// Sets a controlled company's levers and director.
Refusal? runListed(WorldState world, ContentDb content, RunListed command) {
  final (stock, refusal) = _controlled(world, content, command, command.stock);
  if (stock == null) return refusal;
  if (command.payout case final payout?
      when payout.isNegative || payout > Fx.one) {
    return const Refusal('payoutRange');
  }
  if (command.growth < -1 || command.growth > 1) {
    return const Refusal('growthRange');
  }
  if (command.debt case final debt?
      when debt.isNegative || debt > maxDebtLever) {
    return const Refusal('debtRange');
  }
  final grades = content.directors?.grades.length ?? 0;
  if (command.director case final grade? when grade < 0 || grade >= grades) {
    return const Refusal('unknownGrade');
  }
  stock
    ..payoutLever = command.payout
    ..growthLever = command.growth
    ..debtLever = command.debt
    ..director = command.director;
  return null;
}

/// A controlled company bids, with debt, for a smaller listed company of
/// its sector and country, to merge it in.
Refusal? buyRival(WorldState world, ContentDb content, BuyRival command) {
  final (via, refusal) = _controlled(world, content, command, command.via);
  if (via == null) return refusal;
  final def = content.stocks!;
  final market = world.stocks!;
  final i = command.stock;
  if (i < 0 || i >= market.stocks.length || i == command.via) {
    return const Refusal('unknownStock');
  }
  final target = market.stocks[i];
  if (!target.listed) return const Refusal('stockNotListed');
  final mine = listingOf(def, market, command.via);
  final theirs = listingOf(def, market, i);
  if (theirs.kind != ListingKind.formula ||
      theirs.sector != mine.sector ||
      theirs.country != mine.country ||
      target.cap >= via.cap) {
    return const Refusal('notARival');
  }
  if (target.controller != null) return const Refusal('notForBids');
  if (command.premium <= Fx.zero || command.premium > maxBidPremium) {
    return const Refusal('premiumRange');
  }
  final price = target.price + target.price.times(command.premium);
  if (market.openBid(i) case final open? when open.price >= price) {
    return Refusal('bidTooLow', amount: open.price);
  }
  openBid(
    world,
    null,
    def,
    market,
    i,
    via.controller!,
    price,
    via: command.via,
  );
  return null;
}

/// Puts a controlled company up for sale: the richest raider that can pay
/// for it all bids at a premium, and the player's shares are tendered.
Refusal? sellControlled(
  WorldState world,
  ContentDb content,
  SellControlled command,
) {
  final (stock, refusal) = _controlled(world, content, command, command.stock);
  if (stock == null) return refusal;
  final def = content.stocks!;
  final market = world.stocks!;
  if (market.openBid(command.stock) != null) {
    return const Refusal('bidAlreadyOpen');
  }
  final rules = def.rules;
  final price = stock.price + stock.price.times(rules.raiderPremium);
  final cost = price.timesInt(stock.shares);
  var best = -1;
  for (final (r, raider) in market.raiders.indexed) {
    if (raider.cash.times(rules.raiderLeverage) < cost) continue;
    if (best < 0 || raider.cash > market.raiders[best].cash) best = r;
  }
  if (best < 0) return const Refusal('noRaiderBuyer');
  // A company held whole goes back on its exchange to be bid for.
  joinExchange(def, market, command.stock);
  openBid(
    world,
    null,
    def,
    market,
    command.stock,
    raiderOwner(best),
    price,
    tender: true,
  );
  return null;
}

/// The least share of a company listed, and the most.
const minListedShare = Fx.raw(500);
const maxListedShare = Fx.raw(10000);

/// Lists a company of the player's: one that earns, or a software company
/// that sells; never the holding, which isn't a company.
Refusal? listCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  ListCompany command,
) {
  final def = content.stocks;
  final market = world.stocks;
  if (def == null || market == null) return const Refusal('noStockMarket');
  if (command.actor != world.player) {
    return const Refusal('onlyThePlayerTrades');
  }
  final index = command.company.index;
  if (index < 0 || index >= world.companies.length) {
    return const Refusal('unknownCompany');
  }
  final company = world.companies[index];
  if (company.owner != world.player || !company.isActive) {
    return const Refusal('notYourCompany');
  }
  if (ownListing(market, company.id) != null) {
    return const Refusal('companyListed');
  }
  if (command.share < minListedShare || command.share > maxListedShare) {
    return const Refusal('listedShareRange');
  }
  if (command.newShares && command.share >= Fx.one) {
    return const Refusal('listedShareRange');
  }
  final software = softwareOf(world, company.id);
  final earns = software != null
      ? software.customers > 0
      : companyEarnings(world, content, company.id) > Money.zero;
  if (!earns) return const Refusal('earnsTooLittle');
  final place = listingPlace(world, content, def, company);
  if (place == null) return const Refusal('noSector');
  listOwnCompany(
    world,
    content,
    ledger,
    def,
    market,
    company,
    place,
    command.share,
    newShares: command.newShares,
  );
  return null;
}
