import '../core/fx.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../state/cohort.dart';
import '../state/market.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'tick_system.dart';

/// The population phase, on the first of each month after the macro phase.
/// Each segment of each market grows or shrinks by its trend plus the
/// business cycle's migration: a twelfth of the annual rate on its current
/// households, with fractions of a household carried over. Households join
/// or leave cohorts of the segment drawn at random. On the first of January
/// a census counts every market.
final class PopulationSystem implements TickSystem {
  const PopulationSystem();

  @override
  void run(WorldState world, TickContext context) {
    final day = context.day;
    if (!day.isFirstOfMonth || day <= context.content.startDay) return;
    final content = context.content;
    final segments = content.segments.length;
    final members = [
      for (final _ in content.markets)
        [for (final _ in content.segments) <HouseholdCohort>[]],
    ];
    for (final cohort in world.cohorts) {
      members[cohort.market.index][cohort.segment.index].add(cohort);
    }
    for (final market in content.markets) {
      final migration = content
          .macro
          .regimes[world.macroOf(market.country).regime.index]
          .migration;
      final state = world.markets[market.id.index];
      while (state.pending.length < segments) {
        state.pending.add(Fx.zero);
      }
      for (final segment in content.segments) {
        final cohorts = members[market.id.index][segment.id.index];
        if (cohorts.isEmpty) continue;
        final households = _households(cohorts);
        final rate = market.growth[segment.id.index] + migration;
        final owed =
            state.pending[segment.id.index] +
            Fx.raw(mulDivRound(households * rate.raw, 1, 12));
        // Whole households, toward zero; the rest waits for next month.
        final whole = owed.raw ~/ Fx.scale;
        state.pending[segment.id.index] = owed - Fx.fromInt(whole);
        final rng = context.rng(
          RngStream.population,
          market.id.index * segments + segment.id.index,
        );
        for (var i = 0; i < whole; i++) {
          cohorts[rng.nextInt(cohorts.length)].weight++;
        }
        for (var i = 0; i < -whole; i++) {
          final occupied = [
            for (final cohort in cohorts)
              if (cohort.weight > 0) cohort,
          ];
          if (occupied.isEmpty) break;
          occupied[rng.nextInt(occupied.length)].weight--;
        }
      }
      if (day.date.month == 1) {
        final households = _households([
          for (final cohorts in members[market.id.index]) ...cohorts,
        ]);
        final previous = state.censuses.last.households;
        state.censuses.add((day: day, households: households));
        if (state.censuses.length > MarketState.censusesKept) {
          state.censuses.removeAt(0);
        }
        context.events.add(
          CensusTaken(
            market: market.id,
            households: households,
            previous: previous,
          ),
        );
      }
    }
  }

  static int _households(List<HouseholdCohort> cohorts) =>
      cohorts.fold(0, (sum, cohort) => sum + cohort.weight);
}
