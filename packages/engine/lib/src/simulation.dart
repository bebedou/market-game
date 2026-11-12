import 'accounting/ledger.dart';
import 'commands/apply_command.dart';
import 'commands/command.dart';
import 'commands/refusal.dart';
import 'content/content_db.dart';
import 'core/calendar.dart';
import 'core/fx.dart';
import 'core/money.dart';
import 'core/rng.dart';
import 'core/hash32.dart';
import 'core/ids.dart';
import 'countries/country_economy.dart';
import 'observation/observation.dart' as observation show observe, PublicView;
import 'neighbourhoods/neighbourhood_generator.dart';
import 'observation/observation.dart' show Observation;
import 'persistence/save_file.dart';
import 'persistence/state_io.dart';
import 'policies/director.dart' show Directive;
import 'policies/manager.dart';
import 'policies/policy.dart';
import 'reports/attribution.dart';
import 'reports/period_report.dart';
import 'state/game_start.dart';
import 'state/growth.dart';
import 'state/invariants.dart';
import 'systems/national.dart' show currentNational;
import 'state/sleepers.dart';
import 'state/world_state.dart';
import 'systems/events.dart';
import 'systems/tick_system.dart';

/// A command that failed validation, and why.
final class CommandRejection {
  const CommandRejection(this.command, this.reason);

  final Command command;
  final Refusal reason;
}

/// The outcome of one [Simulation.step].
final class TickResult {
  const TickResult({
    required this.day,
    required this.rejections,
    required this.entries,
    required this.events,
    required this.attribution,
  });

  /// The day that was simulated.
  final Day day;
  final List<CommandRejection> rejections;

  /// Every journal entry posted during the day.
  final List<JournalEntry> entries;
  final List<TickEvent> events;

  /// Why shoppers went where they did.
  final Attribution attribution;
}

/// The engine's entry point: commands go in, one day passes per [step], and
/// saves come out.
///
/// Every constructor takes [systems], the tick pipeline, defaulting to the
/// standard one, and [policies], the actors run by AI, defaulting to the
/// scenario's strategies. Tests and the headless runner may pass others; a
/// save only continues identically under the setup that produced it.
final class Simulation {
  Simulation._(
    this._content,
    this.systems,
    Map<PersonId, Policy>? policies,
    this.world,
    this._log,
    this._pending, [
    List<WokenNeighbourhood>? woken,
    this._asleep,
  ]) : policies = Map.unmodifiable(policies ?? standardPolicies(_content)),
       _woken = woken ?? [];

  /// Whether the cities but the player's have run by formula from the start,
  /// and how the game started then.
  final CitiesAsleep? _asleep;

  /// A new game, starting from [content]'s initial world, with the
  /// player's first store as [start] chose if given: see [startTerms].
  ///
  /// If [citiesAsleep], every city but the player's runs by formula until
  /// the player trades there, its businesses trading in their books: see
  /// [withCitiesAsleep].
  factory Simulation.newGame(
    ContentDb content, {
    required int seed,
    GameStart? start,
    List<TickSystem> systems = standardSystems,
    Map<PersonId, Policy>? policies,
    bool citiesAsleep = false,
  }) {
    var game = content;
    var begin = start;
    if (citiesAsleep) (game, begin) = withCitiesAsleep(content, start: start);
    return Simulation._(
      game,
      systems,
      policies,
      WorldState.initial(game, seed: seed, start: begin)
        ..sleepers.addAll([
          for (var row = 0; row < game.neighbourhoods.length; row++)
            newSleeper(game, row, seed: seed),
        ]),
      [],
      [],
      [],
      citiesAsleep ? (start: start) : null,
    );
  }

  /// Resumes the game saved in [file] from its snapshot.
  factory Simulation.load(
    ContentDb content,
    SaveFile file, {
    List<TickSystem> systems = standardSystems,
    Map<PersonId, Policy>? policies,
  }) {
    final save = SaveData.decode(content, file);
    final simulation = Simulation._(
      save.content,
      systems,
      policies,
      save.world,
      save.log,
      save.pending,
      List.of(save.woken),
      save.asleep,
    );
    // A row the save doesn't know of starts its formula now.
    final known = {
      for (final sleeper in save.world.sleepers) sleeper.row,
      for (final wake in save.woken) wake.row,
    };
    for (var row = 0; row < save.content.neighbourhoods.length; row++) {
      if (!known.contains(row)) {
        save.world.sleepers.add(
          newSleeper(save.content, row, seed: save.world.seed),
        );
      }
    }
    return simulation;
  }

  /// Rebuilds the game saved in [file] from its seed and command log alone,
  /// replaying every day up to the save. With a deterministic engine the
  /// result is identical to [Simulation.load]; this is how bug reports get
  /// reproduced.
  factory Simulation.replay(
    ContentDb content,
    SaveFile file, {
    List<TickSystem> systems = standardSystems,
    Map<PersonId, Policy>? policies,
  }) {
    final save = SaveData.decode(content, file);
    final simulation = Simulation.newGame(
      content,
      seed: save.world.seed,
      start: switch (save.asleep) {
        (:final start) => start,
        null => save.world.start,
      },
      systems: systems,
      policies: policies,
      citiesAsleep: save.asleep != null,
    );
    var next = 0;
    while (simulation.today < save.world.today) {
      while (next < save.log.length && save.log[next].day == simulation.today) {
        simulation.submit(save.log[next++].command);
      }
      simulation.step();
    }
    save.pending.forEach(simulation.submit);
    return simulation;
  }

  ContentDb _content;

  /// The scenario, and the neighbourhoods woken since the start.
  ContentDb get content => _content;
  final List<TickSystem> systems;

  /// The AI policy acting for each actor it controls.
  Map<PersonId, Policy> policies;

  final List<WokenNeighbourhood> _woken;

  /// The neighbourhoods woken so far, in order.
  List<WokenNeighbourhood> get woken => List.unmodifiable(_woken);

  /// The rows of [ContentDb.neighbourhoods] still asleep.
  List<int> get sleeping => [for (final sleeper in world.sleepers) sleeper.row];

  ContentDb? _plan;
  int _planMonth = -1;

  WokenNeighbourhood _standing(SleepingNeighbourhood sleeper) => (
    row: sleeper.row,
    day: today,
    priceIndex: world
        .macroOf(content.neighbourhoods[sleeper.row].country)
        .priceIndex,
    households: sleeper.households,
    shops: sleeper.shops,
  );

  /// The neighbourhoods still asleep, as they stand and would wake today:
  /// [content] with them all added, to look at and not to play. Null if none
  /// sleep. It's redone each month, when the formula has moved them.
  ContentDb? get plan {
    if (world.sleepers.isEmpty) return null;
    final date = today.date;
    final month = date.year * 12 + date.month;
    if (_plan == null || _planMonth != month) {
      _planMonth = month;
      _plan = withNeighbourhoods(
        content,
        [for (final sleeper in world.sleepers) _standing(sleeper)],
        seed: world.seed,
        withChains: true,
      );
    }
    return _plan;
  }

  /// Every country of the national table by formula, region by region, from
  /// the game's start up to this month, each country in the phase of the
  /// cycle the game had it in, with companies' shops run there: the national
  /// view. Null without a national table, or with one country. Kept with the
  /// world and saved; a game saved before it was kept rebuilds it.
  CountryEconomy? get national => currentNational(world, content);

  /// The full world state, for engine internals and tests. The app will read
  /// observations instead.
  final WorldState world;

  final List<LoggedCommand> _log;
  final List<Command> _pending;

  /// The day the next [step] will simulate.
  Day get today => world.today;

  /// Every submitted command applied so far, in order. Commands from
  /// [policies] aren't logged: they regenerate on replay.
  List<LoggedCommand> get commandLog => List.unmodifiable(_log);

  /// Queues [command] to be applied at the start of the next [step], or does
  /// it at once if it wakes a neighbourhood, as what's queued after it may
  /// refer to its sites.
  void submit(Command command) {
    if (command is WakeNeighbourhood) {
      _wake(command);
    } else if (command is CreateBrand) {
      // A brand is a name until shops trade under it: it's there at once,
      // for a shop to open under it the same day.
      if (applyCommand(world, content, Ledger(today), command) == null) {
        _log.add((day: today, command: command));
      }
    } else {
      _pending.add(command);
    }
  }

  /// Adds the neighbourhood of [command] to the world: its sites, households,
  /// shops and owners, on today's date. The shops have traded here for years.
  /// Nothing happens if it is awake already or there's no such row.
  void _wake(WakeNeighbourhood command) {
    final sleeper = world.sleepers
        .where((sleeper) => sleeper.row == command.row)
        .firstOrNull;
    if (sleeper == null) return;
    final wake = _standing(sleeper);
    final chains = <(SleepingShop, String, List<Money?>, List<int>)>[];
    final grown = withNeighbourhoods(
      content,
      [wake],
      seed: world.seed,
      onChain: (shop, site, prices, staff) =>
          chains.add((shop, site, prices, staff)),
    );
    final stores = world.stores.length;
    final persons = content.persons.length;
    growWorld(world, grown);
    world.sleepers.remove(sleeper);
    // Each shop is as well known as its history made it.
    final months = _monthsSinceStart();
    Fx known(SleepingShop shop) => months - shop.openedMonth >= 24
        ? grown.demand.establishedReputation
        : grown.demand.openingReputation;
    final own = [
      for (final shop in sleeper.shops)
        if (shop.company == null) shop,
    ];
    for (final (i, shop) in own.indexed) {
      world.stores[stores + i].reputation = known(shop);
    }
    // A chain's shops become stores of its company, under its brand.
    for (final (shop, siteKey, prices, staff) in chains) {
      final store = world.addStore(
        grown,
        name: shop.name,
        company: shop.company!,
        site: grown.sites.firstWhere((site) => site.key == siteKey),
        prices: prices,
        staff: staff,
        opensOn: today,
        format: shop.format,
        area: shop.area,
      );
      store
        ..brand = shop.brand
        ..reputation = known(shop);
    }
    final standard = standardPolicies(grown);
    policies = Map.unmodifiable({
      ...policies,
      for (final MapEntry(:key, :value) in standard.entries)
        if (key.index >= persons) key: value,
    });
    _content = grown;
    _plan = null;
    _woken.add(wake);
    _log.add((day: today, command: command));
  }

  /// What [actor] can see now, before the next [step].
  Observation observe(PersonId actor) =>
      observation.observe(world, content, actor);

  int _monthsSinceStart() {
    final start = content.startDay.date;
    final now = today.date;
    return (now.year - start.year) * 12 + now.month - start.month;
  }

  /// Simulates one day: the policies decide from what their actors see,
  /// their commands and the queued ones are applied, then the tick systems
  /// run. In debug builds, also checks the accounting and stock invariants.
  TickResult step() {
    final day = world.today;
    final ledger = Ledger(day);
    final events = <TickEvent>[];
    final rejections = <CommandRejection>[];
    final decided = <Command>[];
    // Everyone decides on the same moment, so what is public is built once.
    final public = observation.PublicView(world, content);
    for (final MapEntry(key: actor, value: policy) in policies.entries) {
      final view = observation.observe(world, content, actor, public: public);
      for (final command in policy.decide(view, content)) {
        assert(command.actor == actor, 'A policy acted for someone else');
        decided.add(command);
      }
    }
    final directives = <Directive>[];
    decided.addAll(_managerCommands(day, public, directives));
    final logged = _pending.length;
    final commands = [..._pending, ...decided];
    final done = Set<Command>.identity();
    for (final i in _inApplicationOrder(commands)) {
      final command = commands[i];
      if (i < logged) _log.add((day: day, command: command));
      final reason = applyCommand(world, content, ledger, command);
      if (reason != null) {
        rejections.add(CommandRejection(command, reason));
      } else {
        done.add(command);
      }
    }
    _pending.clear();
    for (final (:company, :command, :memo) in directives) {
      if (command == null || done.contains(command)) {
        world.companies[company.index].remember(memo);
      }
    }
    final attribution = Attribution(world.stores.length);
    final context = TickContext(
      content: content,
      day: day,
      seed: world.seed,
      ledger: ledger,
      events: events,
      attribution: attribution,
    );
    for (final system in systems) {
      system.run(world, context);
    }
    world.today = day + 1;
    assert(_checkInvariants(day));
    return TickResult(
      day: day,
      rejections: rejections,
      entries: ledger.entries,
      events: events,
      attribution: attribution,
    );
  }

  /// What store managers and directors decide for their owners on [day],
  /// the directors' memos added to [directives]. Managers' judgment is
  /// redrawn each week, directors' each month.
  List<Command> _managerCommands(
    Day day,
    observation.PublicView public,
    List<Directive> directives,
  ) {
    final owners = <PersonId>[];
    void add(PersonId owner) {
      if (!owners.contains(owner)) owners.add(owner);
    }

    for (final store in world.stores) {
      if (store.manager == null || !store.isTrading) continue;
      add(world.companies[store.company.index].owner);
    }
    for (final company in world.companies) {
      if (company.director != null && company.isActive) add(company.owner);
    }
    final week = ReportPeriod.week.startOf(day).number;
    final month = ReportPeriod.month.startOf(day).number;
    return [
      for (final owner in owners)
        ...manage(
          observation.observe(world, content, owner, public: public),
          content,
          (entity) => Rng.keyed(world.seed, RngStream.manager, week, entity),
          foresight: (entity) =>
              Rng.keyed(world.seed, RngStream.director, month, entity),
          directives: directives,
        ),
    ];
  }

  bool _checkInvariants(Day day) {
    final violations = invariantViolations(world);
    if (violations.isNotEmpty) {
      throw StateError(
        'Invariants broken on ${day.toIsoString()}:\n${violations.join('\n')}',
      );
    }
    return true;
  }

  /// [company]'s week or month reports, oldest first; the latest is still
  /// running. They are copies, unaffected by later steps, for the company's
  /// owner.
  List<PeriodReport> reports(CompanyId company, ReportPeriod period) =>
      companyReports(world, company, period);

  SaveFile save() => SaveData(
    content: content,
    world: world,
    log: _log,
    pending: _pending,
    woken: _woken,
    asleep: _asleep,
  ).encode();

  /// A hash of the canonical encoding of the world, with its neighbourhoods
  /// run by formula if there are any.
  int stateHash() {
    final writer = StateWriter();
    world.write(writer);
    for (final sleeper in world.sleepers) {
      sleeper.write(writer);
    }
    if (world.cycle != null) world.writeEconomies(writer);
    if (world.national != null) writeNational(writer, world);
    return (Hash32()..addBytes(writer.toBytes())).finish();
  }
}

/// Indexes into [commands] ordered by actor, then by position. `List.sort`
/// isn't stable, so the position is part of the key.
List<int> _inApplicationOrder(List<Command> commands) =>
    [for (var i = 0; i < commands.length; i++) i]..sort((a, b) {
      final byActor = commands[a].actor.index.compareTo(
        commands[b].actor.index,
      );
      return byActor != 0 ? byActor : a.compareTo(b);
    });
