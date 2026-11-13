import '../state/buying_terms.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// Counts each company's goods bought in the month just ended, on the first
/// of the month, for its buying terms; nothing without the scenario's.
final class BuyingTermsSystem implements TickSystem {
  const BuyingTermsSystem();

  @override
  void run(WorldState world, TickContext context) {
    if (!context.day.isFirstOfMonth || context.content.buyingTerms == null) {
      return;
    }
    for (final company in world.companies) {
      if (company.isActive) countGoodsMonth(company);
    }
  }
}
