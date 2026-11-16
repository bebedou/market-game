import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../state/factories.dart';
import '../state/factory.dart';
import '../state/labs.dart';
import '../state/orders.dart';
import '../state/talent.dart';
import '../state/world_state.dart';
import 'events.dart';
import 'settlement.dart';
import 'tick_system.dart';

/// Runs factories' labs and the market for key people.
///
/// Every day, each key person's pay is billed to their factory's company.
/// On the first of the month the market closes part of every line's lead,
/// candidates nobody hired are taken by other companies and new ones come,
/// and each lab with a line to develop spends its budget: the work adds up,
/// multiplied by its engineers, until the line's next generation is ready
/// and launches, with the quality its designers give it. Runs before
/// settlement, which pays the bills.
final class LabSystem implements TickSystem {
  const LabSystem();

  @override
  void run(WorldState world, TickContext context) {
    final labs = context.content.factories?.labs;
    if (labs == null) return;
    final first = context.day.isFirstOfMonth;
    if (first || world.keyPeople.isEmpty) _market(world, context, labs);
    for (final factory in world.factories) {
      // The market catches up with every design, a closed factory's too.
      if (first) {
        for (final line in factory.lines) {
          line.lead -= line.lead * labs.catchUp;
        }
      }
      final company = world.companies[factory.company.index];
      final people = labPeople(world, factory.id);
      if (factory.status == FactoryStatus.closed || !company.isActive) {
        // Its people don't wait for a factory that is gone.
        for (final person in people) {
          person
            ..status = KeyStatus.gone
            ..factory = null;
        }
        continue;
      }
      final level = labWageLevel(world, context.content, factory);
      for (final person in people) {
        final pay = dailyPay(keySalary(labs, person, level));
        if (pay <= Money.zero) continue;
        bill(
          context.ledger,
          company,
          AccountKind.salaries,
          Payable(
            creditor: world.elsewhere.partyRef,
            creditorAccount: AccountKind.revenue,
            reason: EntryReason.salary,
            amount: pay,
            due: context.day,
            factory: factory.id,
          ),
        );
      }
      if (!first) continue;
      for (final person in people) {
        person.monthsWorked++;
      }
      if (factory.runsOn(context.day)) {
        _develop(world, context, labs, factory);
      }
    }
    if (!first) return;
    // Each line's month, as its owner's factories make it, once every lab
    // has worked.
    for (final factory in world.factories) {
      if (factory.status == FactoryStatus.closed) continue;
      for (final line in factory.lines) {
        line.record(factoryLead(world, factory, line.product));
      }
    }
  }

  /// A month of [factory]'s lab on its project: the budget is billed, by
  /// the services everyone buys from, and the line's next generation
  /// launches once the work is done.
  void _develop(
    WorldState world,
    TickContext context,
    LabsDef labs,
    Factory factory,
  ) {
    final project = factory.project;
    if (project == null || factory.labBudget <= Money.zero) return;
    bill(
      context.ledger,
      world.companies[factory.company.index],
      AccountKind.research,
      Payable(
        creditor: world.services.partyRef,
        creditorAccount: AccountKind.revenue,
        reason: EntryReason.development,
        amount: factory.labBudget,
        due: context.day,
        factory: factory.id,
      ),
    );
    final engineers = labPower(world, labs, factory.id, KeyRole.engineer);
    factory.labWork += labMonthlyWork(factory.labBudget, engineers);
    // It builds on the best its owner's factories of the kind make.
    final lead = factoryLead(world, factory, project);
    final saving = factorySaving(world, factory, project);
    final needed = generationWork(
      labs,
      lead,
      world.macroOf(factory.country).priceIndex,
    );
    if (factory.labWork < needed) return;
    factory.labWork -= needed;
    final designers = labPower(world, labs, factory.id, KeyRole.designer);
    final expected = generationGain(labs, designers);
    // Anywhere within the spread either side of what was expected.
    final rng = context.rng(RngStream.labs, factory.id.index);
    final luck =
        Fx.one - labs.gainSpread + (labs.gainSpread * rng.nextFx()).timesInt(2);
    final gain = expected * luck;
    final line = factory.lineFor(project)
      ..generation += 1
      ..lead = lead + gain
      ..saving = saving + generationSaving(labs, saving, engineers)
      ..launchedOn = context.day;
    context.events.add(
      GenerationLaunched(
        factory: factory.id,
        company: factory.company,
        product: project,
        generation: line.generation,
        gain: gain,
        lead: line.lead,
        saving: line.saving,
      ),
    );
  }

  /// The market for key people: candidates there too long are taken by
  /// other companies, and new ones come until it is full again.
  void _market(WorldState world, TickContext context, LabsDef labs) {
    var waiting = 0;
    for (final person in world.keyPeople) {
      if (person.status != KeyStatus.candidate || person.forSoftware) continue;
      if (context.day.number - person.since.number >= labs.candidateDays) {
        person.status = KeyStatus.gone;
      } else {
        waiting++;
      }
    }
    for (; waiting < labs.candidates; waiting++) {
      world.keyPeople.add(
        newCandidate(
          labs,
          KeyPersonId(world.keyPeople.length),
          context.day,
          context.rng(RngStream.talent, world.keyPeople.length),
        ),
      );
    }
  }
}
