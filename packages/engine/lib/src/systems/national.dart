import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../countries/country_economy.dart';
import '../state/taxation.dart';
import '../state/world_state.dart';
import 'sleepers.dart' show formulaGoodsExtra;
import 'tick_system.dart';

/// [world]'s countries by formula, made the first time they are needed and
/// run up to this month, each country in the phase of the cycle the game had
/// it in (see [WorldState.regimeLog]). Null without a national table, or
/// with one country. A saved game from before they were kept rebuilds them
/// this way.
CountryEconomy? currentNational(WorldState world, ContentDb content) {
  final table = content.national;
  if (table == null || world.cycle == null) return null;
  final regimes = content.macro.regimes;
  // The table's phase for each of the game's regimes, by key.
  final phase = [
    for (final regime in regimes)
      switch (table.regimes.indexWhere((r) => r.key == regime.key)) {
        -1 => 0,
        final i => i,
      },
  ];
  // Each country of the table: its column in the log, or the shared cycle's.
  final columns = [
    for (final country in table.countries)
      switch (content.countries.indexWhere((c) => c.national == country.key)) {
        -1 => content.countries.length,
        final i => i,
      },
  ];
  final economy = world.national ??= CountryEconomy(
    table,
    seed: world.seed,
    start: content.startDay,
  );
  final months = 1 + world.regimeLog.length;
  while (economy.monthsRun < months) {
    final run = economy.monthsRun;
    final logged = run == 0 ? null : world.regimeLog[run - 1];
    economy.advanceMonth(
      regimes: [
        for (final column in columns)
          phase[logged == null
              ? content.macro.startRegime.index
              : logged[column]],
      ],
    );
  }
  return economy;
}

/// The game's country for the table's country at [index], if it plays it.
CountryId? gameCountry(ContentDb content, int index) {
  final key = content.national!.countries[index].key;
  final found = content.countries.indexWhere((c) => c.national == key);
  return found < 0 ? null : CountryId(found);
}

/// What shops of [format] run by formula in [country] spend, as shares of
/// sales, priced and stocked as [strategy] has it: goods at its markup with
/// what the formula's shops pay beyond the list, its marketing, and the
/// format's staff and premises as settled shops there have them.
ShopCosts nationalCosts(
  FormatDef format,
  StrategyDef strategy,
  CountryId country,
) {
  final national = format.national!;
  return (
    goods:
        Fx.one.div(Fx.one + strategy.markup) *
        (Fx.one + formulaGoodsExtra(format)),
    marketing: strategy.marketingShare,
    staff: national.staffIn(country),
    premises: national.premisesIn(country),
  );
}

/// What fitting out one shop of a format whose national figures are
/// [national] costs in [region] of [country], for [trade]: its national
/// fitting out at the country's prices and the region's cost level.
Money nationalFitOut(
  FormatNational national,
  CountryState country,
  int trade,
  int region,
) => national.fitOut
    .times(country.priceIndex)
    .times(country.costLevels[trade][region]);

/// The table's country for the game's [country], if the table has it.
int? tableCountry(ContentDb content, CountryId country) {
  final table = content.national;
  if (table == null) return null;
  final key = content.countries[country.index].national;
  final found = table.countries.indexWhere((c) => c.key == key);
  return found < 0 ? null : found;
}

/// Runs the countries by formula each month, on its first, and books each
/// month of companies' shops run by formula there in their accounts,
/// against everyone beyond the districts played in full: their sales, and
/// their goods, marketing, staff and premises. Each country taxes what they
/// made there.
final class NationalSystem implements TickSystem {
  const NationalSystem();

  @override
  void run(WorldState world, TickContext context) {
    if (!context.day.isFirstOfMonth) return;
    final economy = currentNational(world, context.content);
    if (economy == null) return;
    final posted = world.nationalPosted;
    for (final (i, country) in economy.countries.indexed) {
      final home = gameCountry(context.content, i);
      for (final block in country.blocks) {
        final company = world.companies[block.company];
        if (!company.isActive) continue;
        for (final month in block.months) {
          if (posted != null && month.start.number <= posted.number) continue;
          _book(world, context.ledger, block, month);
          if (home != null) {
            recordDistrictMonth(
              world,
              company.id,
              home,
              month.start.date.year,
              sales: month.sales,
              profit: month.profit,
            );
          }
        }
      }
    }
    // Everything up to this month is in the books.
    world.nationalPosted = context.day;
  }

  void _book(
    WorldState world,
    Ledger ledger,
    CompanyBlock block,
    BlockMonth month,
  ) {
    final company = world.companies[block.company];
    if (month.sales > Money.zero) {
      ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.revenue,
        amount: month.sales,
        reason: EntryReason.sale,
      );
    }
    for (final (amount, account, reason) in [
      (month.goods, AccountKind.costOfGoods, EntryReason.costOfSale),
      (month.marketing, AccountKind.marketing, EntryReason.marketing),
      (month.staff, AccountKind.wages, EntryReason.wages),
      (month.premises, AccountKind.rent, EntryReason.rent),
    ]) {
      if (amount <= Money.zero) continue;
      ledger.pay(
        payer: company,
        payerAccount: account,
        payee: world.elsewhere,
        payeeAccount: AccountKind.revenue,
        amount: amount,
        reason: reason,
      );
    }
  }
}
