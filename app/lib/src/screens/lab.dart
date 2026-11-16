import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

/// How many steps a lab's budget moves through, from nothing to its most.
const _budgetSteps = 8;

/// Opens [factory]'s lab within the current tab.
void openLabPage(BuildContext context, FactoryView factory) =>
    context.openPage(tr('lab.title'), (_) => [LabPage(id: factory.id)]);

/// [lead] in whole points over the standard, signed.
String points(Fx lead) {
  final value = (lead.raw + (lead.isNegative ? -50 : 50)) ~/ 100;
  return value > 0 ? '+$value' : '$value';
}

/// What [factory]'s lab costs a month once pending changes apply: its
/// people's pay, and its budget while a line is on the bench.
Money _monthlyCost(SimulationController game, FactoryView factory) {
  final lab = factory.lab!;
  final pending = game.labOf(factory);
  final budget = pending.project == null ? Money.zero : pending.budget;
  return lab.monthlyPay + budget;
}

/// How [factory]'s lab stands once pending changes apply: the work its
/// project takes, a month's work at its budget, and the months left.
({Money needed, Money monthly, int? months}) _pace(
  SimulationController game,
  FactoryView factory,
) {
  final labs = game.content.factories!.labs!;
  final lab = factory.lab!;
  final (:budget, :project) = game.labOf(factory);
  if (project == null) {
    return (needed: Money.zero, monthly: Money.zero, months: null);
  }
  final lead = lab.lines.firstWhere((line) => line.product == project).lead;
  final needed = generationWork(
    labs,
    lead,
    game.view.economy(factory.country).priceIndex,
  );
  final monthly = labMonthlyWork(budget, lab.engineers);
  if (monthly <= Money.zero) {
    return (needed: needed, monthly: monthly, months: null);
  }
  final left = needed - lab.work;
  final months = left <= Money.zero
      ? 1
      : (left.cents + monthly.cents - 1) ~/ monthly.cents;
  return (needed: needed, monthly: monthly, months: months);
}

/// The line the chart follows: the one on the bench, else the furthest
/// ahead, else the first.
LineView _charted(LabView lab, ProductId? project) {
  for (final line in lab.lines) {
    if (line.product == project) return line;
  }
  return lab.lines.reduce((a, b) => b.lead > a.lead ? b : a);
}

/// A factory's lab: how its lines stand against the market's standard,
/// what is on the bench, and its team.
class LabPage extends StatelessWidget {
  const LabPage({super.key, required this.id});

  final FactoryId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final factory = game.factory(id);
    final lab = factory?.lab;
    if (factory == null || lab == null) return Hint(tr('factory.gone'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Overview(factory: factory, lab: lab),
        if (factory.status != FactoryStatus.closed) ...[
          _Bench(factory: factory, lab: lab),
          _Team(factory: factory, lab: lab),
        ],
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.factory, required this.lab});

  final FactoryView factory;
  final LabView lab;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final theme = Theme.of(context);
    final charted = _charted(lab, game.labOf(factory).project);
    final history = [...charted.history, charted.lead];
    return Section(
      title: tr('lab.title'),
      mark: Ledger.of(context).works,
      children: [
        Hint(
          tr('lab.costs', {
            'factory': factory.name,
            'amount': money(_monthlyCost(game, factory), cents: false),
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('lab.chartOf', {
                  'product': content.products[charted.product.index].name,
                }),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              points(charted.lead),
              style: figures(theme.textTheme.titleMedium),
            ),
          ],
        ),
        if (charted.history.isEmpty)
          Hint(tr('lab.chartEmpty'))
        else ...[
          LeadChart(history),
          Hint(tr('lab.chartHint')),
        ],
        const SizedBox(height: 6),
        for (final line in lab.lines)
          Line(
            content.products[line.product.index].name,
            points(line.lead),
            hint: line.generation == 0
                ? tr('lab.asBought')
                : [
                    tr('lab.generation', {
                      'generation': line.generation,
                      'date': shortDate(line.launchedOn!),
                    }),
                    if (line.saving > Fx.zero)
                      tr('lab.saved', {
                        'saving': percent(line.saving, decimals: 0),
                      }),
                  ].join(' · '),
            color: gainColor(context, line.lead.raw.sign),
          ),
      ],
    );
  }
}

/// A line's lead over the market's standard month by month: a rule for
/// the standard, and the lead in ink above it, stepping up at each
/// generation and sinking as the market catches up.
class LeadChart extends StatelessWidget {
  const LeadChart(this.leads, {super.key, this.height = 84});

  final List<Fx> leads;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ledger = Ledger.of(context);
    final theme = Theme.of(context);
    return Semantics(
      label: tr('lab.chartHint'),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LeadPainter(
                  [for (final lead in leads) lead.raw / Fx.scale],
                  ink: ledger.ink,
                  rule: ledger.muted,
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 2,
              child: Text(
                tr('lab.standard'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ledger.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadPainter extends CustomPainter {
  _LeadPainter(this.leads, {required this.ink, required this.rule});

  final List<double> leads;
  final Color ink;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    // Room under the standard's rule for its name.
    final base = size.height - 16;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 0.8,
    );
    if (leads.length < 2) return;
    final high = math.max(leads.reduce(math.max), 0.05);
    final low = math.min(leads.reduce(math.min), 0.0);
    final span = high - low;
    double y(double lead) => base - (base - 4) * (lead - low) / span;
    final points = [
      for (var i = 0; i < leads.length; i++)
        Offset(size.width * i / (leads.length - 1), y(leads[i])),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = ink
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawCircle(points.last, 2.6, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_LeadPainter old) =>
      old.leads != leads || old.ink != ink || old.rule != rule;
}

class _Bench extends StatelessWidget {
  const _Bench({required this.factory, required this.lab});

  final FactoryView factory;
  final LabView lab;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final labs = content.factories!.labs!;
    final theme = Theme.of(context);
    final (:budget, :project) = game.labOf(factory);
    // Round steps, in tens, below the most a lab may spend.
    final step = Money(lab.budgetLimit.cents ~/ _budgetSteps ~/ 1000 * 1000);
    final steps = step <= Money.zero ? 0 : budget.cents ~/ step.cents;
    final pace = _pace(game, factory);
    void change({Money? budget, ProductId? project, bool idle = false}) =>
        game.submit(
          SetLab(
            game.player,
            factory: factory.id,
            budget: budget ?? game.labOf(factory).budget,
            project: idle ? null : (project ?? game.labOf(factory).project),
          ),
        );
    final line = project == null
        ? null
        : lab.lines.firstWhere((line) => line.product == project);
    final low = generationGain(labs, lab.designers) * (Fx.one - lab.gainSpread);
    final high =
        generationGain(labs, lab.designers) * (Fx.one + lab.gainSpread);
    final saving = line == null
        ? Fx.zero
        : generationSaving(labs, line.saving, lab.engineers);
    return Section(
      title: tr('lab.bench'),
      children: [
        if (line == null || budget <= Money.zero)
          Hint(tr('lab.idle'))
        else ...[
          Line(
            tr('lab.developing', {
              'product': content.products[line.product.index].name,
              'generation': line.generation + 1,
            }),
            switch (pace.months) {
              final months? => tr('lab.monthsLeft', {'count': months}),
              null => tr('lab.noPace'),
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LevelBar(
              pace.needed <= Money.zero
                  ? 0
                  : lab.work.cents / pace.needed.cents,
              color: Ledger.of(context).ink,
              height: 7,
            ),
          ),
          Hint(
            tr('lab.workDone', {
              'done': money(lab.work, cents: false),
              'needed': money(pace.needed, cents: false),
            }),
          ),
          Line(
            tr('lab.expected'),
            tr('lab.expectedValue', {
              'low': points(low).replaceFirst('+', ''),
              'high': points(high).replaceFirst('+', ''),
            }),
            hint: saving > Fx.zero
                ? tr('lab.expectedSaving', {
                    'saving': percent(saving, decimals: 0),
                  })
                : null,
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(tr('lab.budget'), style: theme.textTheme.labelLarge),
            ),
            CountStepper(
              value: steps,
              max: _budgetSteps,
              label: money(budget, cents: false),
              onChanged: (next) => change(
                budget: step.timesInt(next),
                project: project ?? lab.lines.first.product,
              ),
            ),
          ],
        ),
        Hint(
          tr('lab.budgetHint', {
            'amount': money(lab.budgetLimit, cents: false),
          }),
        ),
        const SizedBox(height: 4),
        Text(tr('lab.line'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final option in lab.lines)
              ChoiceChip(
                label: Text(content.products[option.product.index].name),
                selected: option.product == project,
                onSelected: (_) => change(
                  project: option.product,
                  // A line taken up with no budget gets half the most.
                  budget: budget > Money.zero
                      ? budget
                      : step.timesInt(_budgetSteps ~/ 2),
                ),
              ),
          ],
        ),
        if (project != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => change(budget: Money.zero, idle: true),
              child: Text(tr('lab.pause')),
            ),
          ),
      ],
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({required this.factory, required this.lab});

  final FactoryView factory;
  final LabView lab;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final joining = [
      for (final person in game.view.candidates)
        if (game.hiring(person.id) &&
            game.pending.any(
              (command) =>
                  command is HireKeyPerson &&
                  command.person == person.id &&
                  command.factory == factory.id,
            ))
          person,
    ];
    return Section(
      title: tr('lab.team', {
        'count': game.peopleOf(factory),
        'most': lab.maxPeople,
      }),
      children: [
        if (lab.people.isEmpty && joining.isEmpty) Hint(tr('lab.noTeam')),
        for (final person in lab.people)
          PersonRow(
            person: person,
            status: game.dismissing(person.id)
                ? tr('lab.leaving')
                : person.known
                ? tr('lab.shown')
                : tr('lab.reputed', {
                    'count': math.max(
                      1,
                      game.content.factories!.labs!.revealMonths -
                          person.monthsWorked,
                    ),
                  }),
            pay: person.salary,
            action: game.dismissing(person.id)
                ? TextButton(
                    onPressed: () => game.cancel(
                      game.pending.firstWhere(
                        (command) =>
                            command is DismissKeyPerson &&
                            command.person == person.id,
                      ),
                    ),
                    child: Text(tr('common.cancel')),
                  )
                : TextButton(
                    onPressed: () => _letGo(context, game, person),
                    child: Text(tr('lab.letGo')),
                  ),
          ),
        for (final person in joining)
          PersonRow(
            person: person,
            status: tr('lab.joins'),
            pay: person.salary.times(lab.wageLevel),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => context.openPage(
              tr('lab.market'),
              (_) => [PeopleMarketPage(id: factory.id)],
            ),
            child: Text(tr('lab.market')),
          ),
        ),
      ],
    );
  }

  Future<void> _letGo(
    BuildContext context,
    SimulationController game,
    KeyPersonView person,
  ) async {
    final confirmed = await confirm(
      context,
      title: tr('lab.letGo'),
      body: tr('lab.letGoConfirm', {'person': person.name}),
      action: tr('lab.letGo'),
    );
    if (confirmed) {
      game.submit(DismissKeyPerson(game.player, person: person.id));
    }
  }
}

/// A key person on a line: their name, role and what it does, in a lab or
/// a [software] company, how they stand, their level as filled dots, their
/// pay, and an action.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.status,
    required this.pay,
    this.action,
    this.software = false,
  });

  final KeyPersonView person;
  final String status;

  /// What they are paid a month where they work.
  final Money pay;
  final Widget? action;

  /// Whether they work for a software company, not a lab.
  final bool software;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = context.game.content;
    final levels = software
        ? content.software!.levels.length
        : content.factories!.labs!.levels.length;
    final role = switch (person.role) {
      KeyRole.engineer => tr('lab.engineer'),
      KeyRole.designer => tr('lab.designer'),
    };
    final does = switch ((person.role, software)) {
      (KeyRole.engineer, false) => tr('lab.engineerDoes'),
      (KeyRole.designer, false) => tr('lab.designerDoes'),
      (KeyRole.engineer, true) => tr('software.engineerDoes'),
      (KeyRole.designer, true) => tr('software.designerDoes'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name, style: theme.textTheme.titleSmall),
                Text(
                  [role, does].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  [
                    status,
                    tr('lab.pay', {'amount': money(pay, cents: false)}),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          LevelDots(level: person.level, of: levels),
          ?action,
        ],
      ),
    );
  }
}

/// A level of [of] as that many dots, the first [level] + 1 filled.
class LevelDots extends StatelessWidget {
  const LevelDots({super.key, required this.level, required this.of});

  final int level;
  final int of;

  @override
  Widget build(BuildContext context) {
    final ink = Ledger.of(context).ink;
    return Semantics(
      label: tr('lab.level', {'level': level + 1, 'of': of}),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < of; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= level ? ink : null,
                border: Border.all(color: ink, width: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}

/// The key people on the market, for [id]'s lab to hire.
class PeopleMarketPage extends StatelessWidget {
  const PeopleMarketPage({super.key, required this.id});

  final FactoryId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final factory = game.factory(id);
    final lab = factory?.lab;
    if (factory == null || lab == null) return Hint(tr('factory.gone'));
    final labs = game.content.factories!.labs!;
    final full = game.peopleOf(factory) >= lab.maxPeople;
    final candidates = game.view.candidates;
    return Section(
      title: tr('lab.market'),
      children: [
        Hint(tr('lab.marketHint', {'months': labs.revealMonths})),
        if (candidates.isEmpty) Hint(tr('lab.noCandidates')),
        if (full) Hint(tr('lab.full')),
        for (final person in candidates)
          PersonRow(
            person: person,
            status: game.hiring(person.id)
                ? tr('lab.joins')
                : tr('lab.leaves', {'date': shortDate(person.leaves!)}),
            pay: person.salary.times(lab.wageLevel),
            action: game.hiring(person.id)
                ? TextButton(
                    onPressed: () => game.cancel(
                      game.pending.firstWhere(
                        (command) =>
                            command is HireKeyPerson &&
                            command.person == person.id,
                      ),
                    ),
                    child: Text(tr('common.cancel')),
                  )
                : full
                ? null
                : TextButton(
                    onPressed: () => game.submit(
                      HireKeyPerson(
                        game.player,
                        person: person.id,
                        factory: factory.id,
                      ),
                    ),
                    child: Text(tr('lab.hire')),
                  ),
          ),
      ],
    );
  }
}
