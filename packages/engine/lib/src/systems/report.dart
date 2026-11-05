import '../reports/period_report.dart';
import '../state/world_state.dart';
import 'tick_system.dart';

/// The report phase, last in the day: folds the day's money, shoppers and
/// misses into each company's running week and month reports.
final class ReportSystem implements TickSystem {
  const ReportSystem();

  @override
  void run(WorldState world, TickContext context) =>
      recordPeriodReports(world, context);
}
