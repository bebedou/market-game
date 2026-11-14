import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import 'factory.dart';
import 'talent.dart';
import 'world_state.dart';

/// The key people working in [factory]'s lab, in the order hired.
List<KeyPerson> labPeople(WorldState world, FactoryId factory) => [
  for (final person in world.keyPeople)
    if (person.status == KeyStatus.employed && person.factory == factory)
      person,
];

/// What [factory]'s people of [role] add to its lab's multiplier: the sum
/// of their levels' powers. With [shown], as their employer takes them to
/// be, those not yet known counted at their repute.
Fx labPower(
  WorldState world,
  LabsDef labs,
  FactoryId factory,
  KeyRole role, {
  bool shown = false,
}) {
  var power = Fx.zero;
  for (final person in world.keyPeople) {
    if (person.status != KeyStatus.employed ||
        person.factory != factory ||
        person.role != role) {
      continue;
    }
    final level = shown ? person.shownLevel(labs.revealMonths) : person.level;
    power += labs.levels[level].power;
  }
  return power;
}

/// The work a line's next generation takes when it is [lead] ahead of the
/// market's standard, at [priceIndex]: more the further ahead.
Money generationWork(LabsDef labs, Fx lead, Fx priceIndex) => labs
    .generationWork
    .times(priceIndex)
    .times(Fx.one + labs.leadHardness * lead);

/// The work a month of [budget] gets done with engineers adding
/// [engineers] to the lab's multiplier.
Money labMonthlyWork(Money budget, Fx engineers) =>
    budget.times(Fx.one + engineers);

/// The lead a generation is expected to add with designers adding
/// [designers] to the lab's multiplier.
Fx generationGain(LabsDef labs, Fx designers) =>
    labs.gain * (Fx.one + designers);

/// The share of its materials a generation saves a line that already
/// saves [saving], with engineers adding [engineers]: less as the line
/// nears the most it can save.
Fx generationSaving(LabsDef labs, Fx saving, Fx engineers) {
  final room = labs.maxSaving - saving;
  if (room <= Fx.zero || labs.maxSaving <= Fx.zero) return Fx.zero;
  final added = labs.saving * (Fx.one + engineers) * room.div(labs.maxSaving);
  return added < room ? added : room;
}

/// What [person] is paid a month where wages stand at [wageLevel]: what
/// someone of their repute asks.
Money keySalary(LabsDef labs, KeyPerson person, Fx wageLevel) =>
    labs.levels[person.repute].salary.times(wageLevel);

/// A day's share of a [monthly] salary.
Money dailyPay(Money monthly) => Money(mulDivRound(monthly.cents, 12, 365));

/// Wages in [factory]'s country against the first country's at the start.
Fx labWageLevel(WorldState world, ContentDb content, Factory factory) =>
    world.macroOf(factory.country).wageIndex *
    content.countries[factory.country.index].service;

/// The most [factory]'s lab may spend a month, at its country's prices.
Money labBudgetLimit(WorldState world, LabsDef labs, Factory factory) =>
    labs.maxBudget.times(world.macroOf(factory.country).priceIndex);

/// What [factory]'s lab costs a year as it stands: its key people's pay,
/// and its budget while it has a line to develop.
Money labYearCost(WorldState world, ContentDb content, Factory factory) {
  final labs = content.factories?.labs;
  if (labs == null) return Money.zero;
  final level = labWageLevel(world, content, factory);
  var year = factory.project == null
      ? Money.zero
      : factory.labBudget.timesInt(12);
  for (final person in labPeople(world, factory.id)) {
    year += keySalary(labs, person, level).timesInt(12);
  }
  return year;
}
