import '../content/content_db.dart' show TalentDef;
import '../core/calendar.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../persistence/state_io.dart';
import 'software.dart' show softwareVersion;

/// What a key person does in a lab. Append only.
enum KeyRole {
  /// Multiplies what a lab's budget gets done, and what a generation saves
  /// in materials.
  engineer,

  /// Multiplies the quality a generation gains.
  designer,
}

/// Append only.
enum KeyStatus {
  /// On the market, for any company to hire.
  candidate,
  employed,

  /// Taken by another company, let go, or left with a factory or a
  /// software company that closed.
  gone,
}

/// A key person: one of the few named people whose talent changes what a
/// company can do. They are known by their track record, [repute], which
/// sets what they ask; their true [level] shows only after months of work.
final class KeyPerson {
  KeyPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.level,
    required this.repute,
    required this.since,
    this.status = KeyStatus.candidate,
    this.factory,
    this.monthsWorked = 0,
    this.forSoftware = false,
    this.software,
  });

  KeyPerson.read(this.id, StateReader reader)
    : name = reader.readString(),
      role = KeyRole.values[reader.readInt()],
      level = reader.readInt(),
      repute = reader.readInt(),
      since = Day(reader.readInt()),
      status = KeyStatus.values[reader.readInt()],
      factory = switch (reader.readNullableInt()) {
        final index? => FactoryId(index),
        null => null,
      },
      monthsWorked = reader.readInt(),
      forSoftware = reader.version >= softwareVersion && reader.readBool(),
      software = reader.version >= softwareVersion
          ? switch (reader.readNullableInt()) {
              final index? => SoftwareId(index),
              null => null,
            }
          : null;

  final KeyPersonId id;
  final String name;
  final KeyRole role;

  /// How good they are, as a place in the scenario's levels: hidden from
  /// their employer until they have worked long enough.
  final int level;

  /// The level their track record suggests, which sets their pay.
  final int repute;

  /// The day they came onto the market, or the day they were hired.
  Day since;
  KeyStatus status;

  /// Where they work, if employed.
  FactoryId? factory;

  /// Whole months worked for their employer.
  int monthsWorked;

  /// Whether they are on the market for software people, on software pay,
  /// rather than for labs.
  final bool forSoftware;

  /// The software company's product they build, if employed there.
  SoftwareId? software;

  /// Whether their employer has seen enough to know their [level].
  bool knownAfter(int revealMonths) =>
      status == KeyStatus.employed && monthsWorked >= revealMonths;

  /// The level their employer takes them for.
  int shownLevel(int revealMonths) => knownAfter(revealMonths) ? level : repute;

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(role.index)
      ..writeInt(level)
      ..writeInt(repute)
      ..writeInt(since.number)
      ..writeInt(status.index)
      ..writeNullableInt(factory?.index)
      ..writeInt(monthsWorked)
      ..writeBool(forSoftware)
      ..writeNullableInt(software?.index);
  }
}

/// A level drawn from [rng], as common as [def] has them.
int drawLevel(TalentDef def, Rng rng) {
  var draw = rng.nextFx();
  var level = 0;
  while (level < def.levels.length - 1 && draw >= def.levels[level].share) {
    draw -= def.levels[level++].share;
  }
  return level;
}

/// A candidate drawn from [rng] for a lab, or for software work if
/// [forSoftware]: a role, a level as common as [def] has it, and a repute
/// that is right half the time, a level short a quarter and a level over a
/// quarter.
KeyPerson newCandidate(
  TalentDef def,
  KeyPersonId id,
  Day day,
  Rng rng, {
  bool forSoftware = false,
}) {
  final role = KeyRole.values[rng.nextInt(KeyRole.values.length)];
  final level = drawLevel(def, rng);
  var repute = level + const [-1, 0, 0, 1][rng.nextInt(4)];
  if (repute < 0) repute = 0;
  if (repute >= def.levels.length) repute = def.levels.length - 1;
  final first = def.firstNames[rng.nextInt(def.firstNames.length)];
  final last = def.lastNames[rng.nextInt(def.lastNames.length)];
  return KeyPerson(
    id: id,
    name: '$first $last',
    role: role,
    level: level,
    repute: repute,
    since: day,
    forSoftware: forSoftware,
  );
}
