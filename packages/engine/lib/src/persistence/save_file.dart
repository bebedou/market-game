import 'dart:typed_data';

import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../neighbourhoods/neighbourhood_generator.dart';
import '../state/game_start.dart';
import '../state/growth.dart';
import '../state/sleepers.dart';
import '../state/world_state.dart';
import 'state_io.dart';

/// The bytes of a saved game.
extension type const SaveFile(Uint8List bytes) {}

/// The format saves are written in: the state layout version. A command log
/// only replays correctly under the rules that recorded it, but snapshots
/// from [oldestReadableVersion] on load and carry on under today's rules.
const int saveFormatVersion = currentStateVersion;

/// The oldest save format this engine still loads.
const int oldestReadableVersion = 6;

/// The first format whose header holds the content's structure itself, so a
/// save can check how the content grew.
const int _structureVersion = 9;

/// The first format whose header says which neighbourhoods woke, so the
/// content can be grown to match before anything else is read.
const int _wokenVersion = 24;

/// The first format that tells which cities slept from the start.
const int _asleepVersion = 26;

/// The first format that keeps each country's economy.
const int _countriesVersion = 27;

const String _magic = 'market-game-save';

/// What a save holds: a snapshot of the world, the full command log since the
/// start (for replays), and commands queued for the next step.
/// A game whose cities but the player's run by formula from the start, and
/// the start the player chose: see [withCitiesAsleep].
typedef CitiesAsleep = ({GameStart? start});

final class SaveData {
  SaveData({
    required this.content,
    required this.world,
    required this.log,
    required this.pending,
    this.woken = const [],
    this.asleep,
  });

  /// Reads [file], from any format since [oldestReadableVersion], and grows
  /// its world into [content] if the scenario gained markets, sites, people
  /// or suppliers since. Throws a [FormatException] if it isn't a save, comes
  /// from a format this engine doesn't read, was made with content whose
  /// lists changed other than by growing, or is damaged. Changed numbers are
  /// fine: that is how balance tweaks keep saves.
  factory SaveData.decode(ContentDb scenario, SaveFile file) {
    final reader = StateReader(file.bytes);
    String magic;
    try {
      magic = reader.readString();
    } on FormatException {
      magic = '';
    }
    if (magic != _magic) {
      throw const FormatException('Not a Market Game save');
    }
    final version = reader.readInt();
    if (version < oldestReadableVersion || version > saveFormatVersion) {
      throw FormatException(
        'Save format $version is not supported (this engine reads formats '
        '$oldestReadableVersion to $saveFormatVersion)',
      );
    }
    reader.version = version;
    final scenarioId = reader.readString();
    final woken = <WokenNeighbourhood>[];
    var content = scenario;
    CitiesAsleep? asleep;
    if (version >= _wokenVersion) {
      final seed = reader.readInt();
      if (version >= _asleepVersion && reader.readBool()) {
        asleep = (start: reader.readBool() ? GameStart.read(reader) : null);
        (content, _) = withCitiesAsleep(content, start: asleep.start);
      }
      for (var i = 0, n = reader.readInt(); i < n; i++) {
        woken.add((
          row: reader.readInt(),
          day: Day(reader.readInt()),
          priceIndex: Fx.raw(reader.readInt()),
          households: [
            for (var h = 0, m = reader.readInt(); h < m; h++) reader.readInt(),
          ],
          shops: [
            for (var s = 0, m = reader.readInt(); s < m; s++)
              SleepingShop.read(reader),
          ],
        ));
      }
      if (woken.isNotEmpty) {
        if (woken.any((w) => w.row >= content.neighbourhoods.length)) {
          throw const FormatException(
            'The save was made with different content (neighbourhoods)',
          );
        }
        for (final wake in woken) {
          content = withNeighbourhoods(content, [wake], seed: seed);
        }
      }
    }
    String? problem;
    if (version >= _structureVersion) {
      problem = _structureProblem(_readStructure(reader), content.structure);
    } else {
      // A fingerprint of all the content or of its structure, which growth
      // changes; the world itself is checked once read.
      reader.readInt();
    }
    if (scenarioId != content.scenarioId) {
      problem = 'scenario "$scenarioId"';
    }
    if (problem != null) {
      throw FormatException(
        'The save was made with different content ($problem)',
      );
    }
    final world = WorldState.read(reader);
    final log = [
      for (var i = 0, n = reader.readInt(); i < n; i++)
        (day: Day(reader.readInt()), command: Command.read(reader)),
    ];
    final pending = [
      for (var i = 0, n = reader.readInt(); i < n; i++) Command.read(reader),
    ];
    if (version >= _wokenVersion) {
      for (var i = 0, n = reader.readInt(); i < n; i++) {
        world.sleepers.add(SleepingNeighbourhood.read(reader));
      }
    }
    if (version >= _countriesVersion) world.readEconomies(reader);
    reader.expectEnd();
    if (version < _structureVersion) {
      if (growthProblem(world, content) case final problem?) {
        throw FormatException(
          'The save was made with different content ($problem)',
        );
      }
    }
    growWorld(world, content);
    return SaveData(
      content: content,
      world: world,
      log: log,
      pending: pending,
      woken: woken,
      asleep: asleep,
    );
  }

  /// Whether the game's cities but the player's run by formula from the
  /// start, and how it started.
  final CitiesAsleep? asleep;

  /// The content the world goes with: the scenario's, plus what woke.
  final ContentDb content;

  /// The neighbourhoods woken, in order.
  final List<WokenNeighbourhood> woken;
  final WorldState world;
  final List<LoggedCommand> log;
  final List<Command> pending;

  SaveFile encode() {
    final writer = StateWriter()
      ..writeString(_magic)
      ..writeInt(saveFormatVersion)
      ..writeString(content.scenarioId)
      ..writeInt(world.seed)
      ..writeBool(asleep != null);
    if (asleep case (:final start)) {
      writer.writeBool(start != null);
      start?.write(writer);
    }
    writer.writeInt(woken.length);
    for (final (:row, :day, :priceIndex, :households, :shops) in woken) {
      writer
        ..writeInt(row)
        ..writeInt(day.number)
        ..writeInt(priceIndex.raw)
        ..writeInt(households.length);
      households.forEach(writer.writeInt);
      writer.writeInt(shops.length);
      for (final shop in shops) {
        shop.write(writer);
      }
    }
    writer.writeInt(content.structure.length);
    for (final (:name, :keys) in content.structure) {
      writer
        ..writeString(name)
        ..writeInt(keys.length);
      keys.forEach(writer.writeString);
    }
    world.write(writer);
    writer.writeInt(log.length);
    for (final (:day, :command) in log) {
      writer.writeInt(day.number);
      command.write(writer);
    }
    writer.writeInt(pending.length);
    for (final command in pending) {
      command.write(writer);
    }
    writer.writeInt(world.sleepers.length);
    for (final sleeper in world.sleepers) {
      sleeper.write(writer);
    }
    world.writeEconomies(writer);
    return SaveFile(writer.toBytes());
  }
}

List<ContentList> _readStructure(StateReader reader) => [
  for (var i = 0, n = reader.readInt(); i < n; i++)
    (
      name: reader.readString(),
      keys: [
        for (var k = 0, m = reader.readInt(); k < m; k++) reader.readString(),
      ],
    ),
];

/// Why a world built on [saved] can't load into [current], or null if it
/// can: the lists the world mirrors may only have grown at the end.
String? _structureProblem(List<ContentList> saved, List<ContentList> current) {
  for (final (:name, :keys) in saved) {
    final growth = ListGrowth.of(name);
    if (growth == ListGrowth.free) continue;
    final now =
        current.where((list) => list.name == name).firstOrNull?.keys ??
        const <String>[];
    if (now.length < keys.length) return '$name changed';
    for (var i = 0; i < keys.length; i++) {
      if (now[i] != keys[i]) return '$name changed';
    }
  }
  return null;
}
