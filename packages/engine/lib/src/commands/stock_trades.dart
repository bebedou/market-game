import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../content/stocks_def.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../state/stocks.dart';
import '../state/world_state.dart';
import '../systems/stocks.dart' show sellHolding;
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
    return const Refusal('notEnoughPersonalCash');
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
