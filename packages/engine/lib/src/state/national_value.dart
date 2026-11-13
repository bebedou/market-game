import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../countries/country_economy.dart';

/// What a chain or a company's shops run by formula are worth: a year of
/// their profit before tax at their latest months' pace, their fittings
/// worn down by half their life, and the price their [AcquisitionDef]'s
/// excess earnings method sets on that, as it does on a store.
typedef NationalValue = ({Money earnings, Money fittings, Money price});

/// What [chain] of [country] sells for whole; null if the scenario sells
/// nothing, or it is a trade's independents or trades no more.
NationalValue? valueChain(
  ContentDb content,
  CountryEconomy economy,
  CountryState country,
  Chain chain,
) {
  if (chain.def.independent || !chain.isTrading) return null;
  final months = chain.months.length > 12
      ? chain.months.sublist(chain.months.length - 12)
      : chain.months;
  var profit = 0;
  for (final month in months) {
    profit += (month.sales - month.goods - month.staff - month.premises).cents;
  }
  return _value(
    content,
    earnings: months.isEmpty
        ? Money.zero
        : Money(mulDivRound(profit, 12, months.length)),
    fittings: chain.perStore
        .times(economy.table.fitOut)
        .times(country.priceIndex)
        .timesInt(chain.stores),
  );
}

/// What [block] of [country] sells for whole; null if the scenario sells
/// nothing or it has no shops.
NationalValue? valueBlock(
  ContentDb content,
  CountryEconomy economy,
  CountryState country,
  CompanyBlock block,
) {
  if (block.stores == 0) return null;
  final months = block.months.length > 12
      ? block.months.sublist(block.months.length - 12)
      : block.months;
  var profit = 0;
  for (final month in months) {
    profit += month.profit.cents;
  }
  return _value(
    content,
    earnings: months.isEmpty
        ? Money.zero
        : Money(mulDivRound(profit, 12, months.length)),
    fittings: block.perStore
        .times(economy.table.fitOut)
        .times(country.priceIndex)
        .timesInt(block.stores),
  );
}

/// A year of [block]'s profit before tax at its latest months' pace, as
/// the bank counts it; nothing before its shops have traded three months.
Money blockEarnings(CompanyBlock block) {
  final months = block.months.length > 12
      ? block.months.sublist(block.months.length - 12)
      : block.months;
  if (months.length < 3) return Money.zero;
  var profit = 0;
  for (final month in months) {
    profit += month.profit.cents;
  }
  return Money(mulDivRound(profit, 12, months.length));
}

NationalValue? _value(
  ContentDb content, {
  required Money earnings,
  required Money fittings,
}) {
  final terms = content.acquisitions;
  if (terms == null) return null;
  // Halfway through their life, on average.
  final held = fittings.times(
    Fx.one - Fx.raw((Fx.one - terms.fittingsResidual).raw ~/ 2),
  );
  final excess = earnings - held.times(terms.tangibleReturn);
  final price =
      held +
      Money(mulDivRound(excess.cents, Fx.scale, terms.capitalization.raw));
  final floor = held.times(terms.distressFloor);
  return (
    earnings: earnings,
    fittings: held,
    price: price > floor ? price : floor,
  );
}

/// The chain of [trade] in [country] with the most cash, that can pay
/// [price]: none of a trade's independents, nor one that has failed or been
/// bought.
Chain? nationalBuyer(CountryState country, int trade, Money price) {
  Chain? best;
  for (final chain in country.chains) {
    if (chain.def.trade != trade ||
        chain.def.independent ||
        !chain.isTrading ||
        chain.cash < price) {
      continue;
    }
    if (best == null || chain.cash > best.cash) best = chain;
  }
  return best;
}
