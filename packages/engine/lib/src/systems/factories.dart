import '../accounting/ledger.dart';
import '../core/money.dart';
import '../state/orders.dart';
import '../state/world_state.dart';
import 'settlement.dart';
import 'tick_system.dart';

/// Bills what running factories cost whatever they make: each shift's staff
/// every day, at the wages of the factory's country, and on the first of the
/// month the site's rent and running costs. Everyone beyond the districts
/// played in full is paid the wages, and the landlords the site. Runs
/// before settlement, which pays the bills.
final class FactorySystem implements TickSystem {
  const FactorySystem();

  @override
  void run(WorldState world, TickContext context) {
    final factories = context.content.factories;
    if (factories == null || world.factories.isEmpty) return;
    for (final factory in world.factories) {
      final company = world.companies[factory.company.index];
      if (!factory.runsOn(context.day) || !company.isActive) continue;
      final kind = factories.kinds[factory.kind.index];
      final economy = world.macroOf(factory.country);
      final wages = kind.shiftWage
          .times(economy.wageIndex)
          .times(context.content.countries[factory.country.index].service)
          .timesInt(factory.shifts);
      if (wages > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.wages,
          Payable(
            creditor: world.elsewhere.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.wages,
            amount: wages,
            due: context.day,
            factory: factory.id,
          ),
        );
      }
      if (!context.day.isFirstOfMonth) continue;
      final site = kind.site.times(economy.priceIndex);
      if (site > Money.zero) {
        bill(
          context.ledger,
          company,
          AccountKind.rent,
          Payable(
            creditor: world.landlords.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.rent,
            amount: site,
            due: context.day,
            factory: factory.id,
          ),
        );
      }
    }
  }
}
