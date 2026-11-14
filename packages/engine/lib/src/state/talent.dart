import '../core/calendar.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';

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

  /// Taken by another company, let go, or left with a factory that closed.
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
      monthsWorked = reader.readInt();

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
      ..writeInt(monthsWorked);
  }
}
