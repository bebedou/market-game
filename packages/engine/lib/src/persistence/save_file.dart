import 'dart:convert';
import 'dart:typed_data';

import '../commands/command.dart';
import '../content/content_db.dart';
import '../content/scenario_loader.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../countries/country_economy.dart';
import '../neighbourhoods/neighbourhood_generator.dart';
import '../state/game_start.dart';
import '../state/growth.dart';
import '../state/sleepers.dart';
import '../state/stocks.dart';
import '../state/store.dart' show shopSizesVersion;
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

/// The save version from which each woken neighbourhood keeps the edition
/// of the places it woke in.
const int _editionVersion = 34;

/// The first format that tells which cities slept from the start.
const int _asleepVersion = 26;

/// The first format that keeps each country's economy.
const int _countriesVersion = 27;

/// The first format that keeps the countries by formula, which older saves
/// rebuild from the phases of the cycle they went through.
const int _nationalVersion = 29;

const String _magic = 'market-game-save';

/// The format written in two layouts (see [SaveData.decode]).
const int _twoLayoutsVersion = 42;

/// The format [file] says it is in, or null if it isn't a save.
int? _formatOf(SaveFile file) {
  try {
    final reader = StateReader(file.bytes);
    return reader.readString() == _magic ? reader.readInt() : null;
  } on FormatException {
    return null;
  }
}

/// A game whose cities but the player's run by formula from the start, and
/// the start the player chose: see [withCitiesAsleep].
typedef CitiesAsleep = ({GameStart? start});

/// What a save holds: a snapshot of the world, the full command log since the
/// start (for replays), and commands queued for the next step.
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
    try {
      return SaveData._read(scenario, file);
    } catch (error, stack) {
      if (_formatOf(file) != _twoLayoutsVersion) rethrow;
      // Format 42 has two layouts: 151811b's, and that of the builds after
      // it until 781c14b, which wrote format 43's under the number 42. A save
      // that doesn't read as the first, to its last byte, reads as the
      // second.
      try {
        return SaveData._read(scenario, file, layout: 43);
      } catch (_) {
        Error.throwWithStackTrace(error, stack);
      }
    }
  }

  factory SaveData._read(ContentDb scenario, SaveFile file, {int? layout}) {
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
    reader.version = layout ?? version;
    // A save from before formats went numbers its shops' formats as they
    // were: its header says how, so it is read once for that, then for
    // good with their numbers mapped to today's.
    if (version >= _structureVersion && version < shopSizesVersion) {
      final probe = StateReader(file.bytes, version: layout ?? version)
        ..readString()
        ..readInt();
      reader.formatMap = _formatMap(
        _readHeader(probe, version).structure,
        scenario,
      );
    }
    final (:scenarioId, :seed, :asleep, :woken, :structure) = _readHeader(
      reader,
      version,
    );
    var content = scenario;
    if (asleep != null) {
      (content, _) = withCitiesAsleep(content, start: asleep.start);
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
    String? problem;
    if (structure != null) {
      // Formats that went are matched by the map, not by their places.
      final saved = [
        for (final list in structure)
          if (reader.formatMap == null || list.name != 'formats') list,
      ];
      problem = _structureProblem(saved, content.structure);
      if (problem != null) {
        // Entries the scenario gained since come before the districts woken
        // since: put them after, where the save expects what it knew.
        if (_inSavedOrder(content, saved) case final reordered?
            when _structureProblem(saved, reordered.structure) == null) {
          content = reordered;
          problem = null;
        }
      }
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
    // Commands the game no longer has drop out.
    final log = [
      for (var i = 0, n = reader.readInt(); i < n; i++)
        if ((Day(reader.readInt()), Command.readOrRetired(reader)) case (
          final day,
          final command?,
        ))
          (day: day, command: command),
    ];
    final pending = [
      for (var i = 0, n = reader.readInt(); i < n; i++)
        ?Command.readOrRetired(reader),
    ];
    if (version >= _wokenVersion) {
      for (var i = 0, n = reader.readInt(); i < n; i++) {
        world.sleepers.add(SleepingNeighbourhood.read(reader));
      }
    }
    if (version >= _countriesVersion) world.readEconomies(reader);
    if (version >= _nationalVersion) readNational(reader, world, content);
    if (version >= stocksVersion) readStocks(reader, world);
    reader.expectEnd();
    if (version < shopSizesVersion) _settleShopSizes(world, content);
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
    for (final (:row, :day, :priceIndex, :households, :shops, :edition)
        in woken) {
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
      writer.writeInt(edition);
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
    writeNational(writer, world);
    writeStocks(writer, world);
    return SaveFile(writer.toBytes());
  }
}

/// What a save holds before its world: its scenario, seed, how its cities
/// sleep, the neighbourhoods woken in it, and the content's lists as it
/// knew them (null before saves kept them).
typedef _Header = ({
  String scenarioId,
  int seed,
  CitiesAsleep? asleep,
  List<WokenNeighbourhood> woken,
  List<ContentList>? structure,
});

/// Reads a save's [_Header], [version] being its format.
_Header _readHeader(StateReader reader, int version) {
  final scenarioId = reader.readString();
  var seed = 0;
  CitiesAsleep? asleep;
  final woken = <WokenNeighbourhood>[];
  if (version >= _wokenVersion) {
    seed = reader.readInt();
    if (version >= _asleepVersion && reader.readBool()) {
      asleep = (start: reader.readBool() ? GameStart.read(reader) : null);
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
        // Saves before editions woke everything in the first.
        edition: version >= _editionVersion ? reader.readInt() : 0,
      ));
    }
  }
  List<ContentList>? structure;
  if (version >= _structureVersion) {
    structure = _readStructure(reader);
  } else {
    // A fingerprint of all the content or of its structure, which growth
    // changes; the world itself is checked once read.
    reader.readInt();
  }
  return (
    scenarioId: scenarioId,
    seed: seed,
    asleep: asleep,
    woken: woken,
    structure: structure,
  );
}

/// Formats that went, and the format whose shops they became: a
/// supermarket is a grocer's large size since [shopSizesVersion].
const _retiredFormats = {'supermarket': 'grocery'};

/// Today's number in [content] for each format a save's [saved] lists
/// knew, by its number there, when some of them went (see
/// [_retiredFormats]); null when none did, or one is unknown, which the
/// lists' check then refuses.
List<int>? _formatMap(List<ContentList>? saved, ContentDb content) {
  final keys = saved?.where((list) => list.name == 'formats').firstOrNull?.keys;
  if (keys == null || !keys.any(_retiredFormats.containsKey)) return null;
  final now = [for (final format in content.formats) format.key];
  final map = <int>[];
  for (final key in keys) {
    final at = now.indexOf(_retiredFormats[key] ?? key);
    if (at < 0) return null;
    map.add(at);
  }
  return map;
}

/// Brings a world read from before shops were sized as they open
/// ([shopSizesVersion]) up to date: works under way are done at once, as
/// they would have come to be, and a company's shops by formula of a format
/// that went join its others of the one they became.
void _settleShopSizes(WorldState world, ContentDb content) {
  final expansion = content.expansion;
  for (final store in world.stores) {
    final works = store.oldWorks;
    if (works == null) continue;
    final steps = (works.area - store.area) ~/ expansion.stepArea;
    store
      ..area = works.area
      ..shelfSlots += steps * expansion.shelfSlots
      ..storageUnits += steps * expansion.storageUnits
      ..oldWorks = null;
    if (works.format case final format?) {
      final next = content.formats[format.index];
      store
        ..format = format
        ..shelfSlots += next.slotBonusAt(store.area)
        ..storageUnits += next.storageBonusAt(store.area);
    }
  }
  final economy = world.national;
  if (economy == null) return;
  for (final country in economy.countries) {
    for (final block in [...country.blocks]) {
      if (block.name != null || !country.blocks.contains(block)) continue;
      final first = economy.blockOf(
        country,
        company: block.company,
        trade: block.trade,
        format: block.format,
      );
      if (first != null && !identical(first, block)) {
        economy.foldBlock(country, first, block);
      }
    }
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
/// [content] with the lists a save reads by position in the order [saved]
/// knew them, the entries it didn't know after them; null if it lacks some
/// of them, or nothing moves.
ContentDb? _inSavedOrder(ContentDb content, List<ContentList> saved) {
  final root = jsonDecode(content.source) as Map<String, dynamic>;
  var moved = false;
  for (final (:name, :keys) in saved) {
    if (ListGrowth.of(name) == ListGrowth.free) continue;
    if (root[name] case final List<dynamic> list) {
      final byKey = {
        for (final entry in list) (entry as Map<String, dynamic>)['id']: entry,
      };
      if (!keys.every(byKey.containsKey)) return null;
      final known = keys.toSet();
      final ordered = [
        for (final key in keys) byKey[key],
        for (final entry in list)
          if (!known.contains((entry as Map<String, dynamic>)['id'])) entry,
      ];
      for (var i = 0; i < ordered.length; i++) {
        if (!identical(ordered[i], list[i])) moved = true;
      }
      root[name] = ordered;
    }
  }
  if (!moved) return null;
  return loadScenario(
    jsonEncode(root),
    national: content.national,
    stocks: content.stocks?.source,
  );
}

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

/// Writes [world]'s countries by formula, if it keeps them.
void writeNational(StateWriter writer, WorldState world) {
  final national = world.national;
  writer.writeBool(national != null);
  if (national == null) return;
  national.write(writer);
  writer.writeNullableInt(world.nationalPosted?.number);
}

/// Writes [world]'s stock market, if it keeps one.
void writeStocks(StateWriter writer, WorldState world) {
  writer.writeBool(world.stocks != null);
  world.stocks?.write(writer);
}

/// Reads what [writeStocks] wrote into [world].
void readStocks(StateReader reader, WorldState world) {
  if (reader.readBool()) world.stocks = StockMarket.read(reader);
}

/// Reads what [writeNational] wrote into [world], made afresh from
/// [content]'s national table.
void readNational(StateReader reader, WorldState world, ContentDb content) {
  if (!reader.readBool()) return;
  final table = content.national;
  if (table == null) {
    throw const FormatException(
      'The save keeps countries by formula, and no national table was given',
    );
  }
  world.national = CountryEconomy(
    table,
    seed: world.seed,
    start: content.startDay,
  )..read(reader);
  world.nationalPosted = switch (reader.readNullableInt()) {
    final day? => Day(day),
    null => null,
  };
}
