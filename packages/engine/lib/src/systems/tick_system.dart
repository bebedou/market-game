import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../reports/attribution.dart';
import '../state/world_state.dart';
import 'buying_terms.dart';
import 'close.dart';
import 'demand.dart';
import 'events.dart';
import 'factories.dart';
import 'logistics.dart';
import 'macro.dart';
import 'national.dart';
import 'operations.dart';
import 'population.dart';
import 'report.dart';
import 'settlement.dart';
import 'sleepers.dart';
import 'solvency.dart';
import 'spoilage.dart';
import 'taxes.dart';

/// One phase of the daily tick.
abstract interface class TickSystem {
  void run(WorldState world, TickContext context);
}

/// What a tick system needs besides the world: content, the day being
/// simulated, keyed randomness, and where to record money, events and
/// attribution.
final class TickContext {
  TickContext({
    required this.content,
    required this.day,
    required int seed,
    required this.ledger,
    required this.events,
    required this.attribution,
  }) : _seed = seed;

  final ContentDb content;
  final Day day;
  final int _seed;
  final Ledger ledger;
  final List<TickEvent> events;
  final Attribution attribution;

  /// Units the owner's shops had from their wholesalers on a factory's
  /// order today, as it was making all it could.
  final boughtIn = <({FactoryId factory, ProductId product, int units})>[];

  /// The random generator for [entity] on this day, in subsystem [stream].
  Rng rng(int stream, int entity) =>
      Rng.keyed(_seed, stream, day.number, entity);
}

/// The production tick phases, in order. Commands are applied before these
/// run.
const List<TickSystem> standardSystems = [
  MacroSystem(),
  // Before the countries by formula, whose shops' buying terms it sets.
  BuyingTermsSystem(),
  NationalSystem(),
  PopulationSystem(),
  TaxSystem(),
  LogisticsSystem(),
  SpoilageSystem(),
  OperationsSystem(),
  DemandSystem(),
  FactorySystem(),
  SettlementSystem(),
  // Before solvency and reports: chains' shops in districts book there.
  SleeperSystem(),
  SolvencySystem(),
  CloseSystem(),
  ReportSystem(),
];
