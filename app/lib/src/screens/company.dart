import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../business.dart';
import '../controller.dart';
import '../directors.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'business_page.dart';
import 'finance.dart' show DirectorSection, openCompanyPage, showDirectorSheet;
import 'holding.dart' show toDoItems;
import 'businesses.dart' show companySummary, holdsLine;
import 'start.dart' show openStartBusiness;

/// Opens [company]'s page within the current tab.
void openCompanyDashboard(
  BuildContext context,
  CompanyView company,
  OpenTab onOpen,
) => context.openPage(
  context.game.companyName(company.id),
  (_) => [CompanyDashboard(id: company.id, onOpen: onOpen)],
);

/// Its months' profits, oldest first, the running month left out, up to
/// twelve.
List<Money> monthlyProfits(SimulationController game, {CompanyId? company}) {
  final current = ReportPeriod.month.startOf(game.today);
  final months = [
    for (final month in game.holdingProfits(
      ReportPeriod.month,
      company: company,
    ))
      if (month.start != current) month.profit,
  ];
  return months.length > 12 ? months.sublist(months.length - 12) : months;
}

/// What [company] owes the bank.
Money debtOf(CompanyView company) =>
    company.loans.fold(Money.zero, (sum, loan) => sum + loan.outstanding);

/// A company, the owner's layout B (2026-11-17): a verdict, in its boss's
/// words if it has one, four key figures, what needs doing there, its
/// businesses with their own figures, its boss, and the owner's levers.
class CompanyDashboard extends StatelessWidget {
  const CompanyDashboard({super.key, required this.id, required this.onOpen});

  final CompanyId id;

  /// Switches to another tab.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = game.view.companies
        .where((company) => company.id == id)
        .firstOrNull;
    if (company == null) return Hint(tr('finance.noCompany'));
    final active = company.status == CompanyStatus.active;
    final businesses = businessesOf(game, company, game.view.national);
    final profits = monthlyProfits(game, company: id);
    final director = game.directorOf(company);
    final directors = game.content.directors;
    final boss = director == null || directors == null
        ? null
        : directorPerson(game, company, director)?.name ??
              aDirector(directors.grades[director.grade.index]);
    final verdict = active
        ? companyVerdict(profits, businesses, boss: boss)
        : (tone: Tone.trouble, text: tr('common.liquidated'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VerdictBox(verdict.text, color: toneColor(context, verdict.tone)),
        FigureGrid([
          (
            label: tr('dashboard.worth'),
            value: compactMoney(SimulationController.worthOf(company)),
            values: null,
          ),
          (
            label: tr('businesses.figures.profit'),
            value: profits.isEmpty
                ? '–'
                : signedMoney(profits.last, cents: false),
            values: [for (final profit in profits) profit.cents],
          ),
          (
            label: tr('common.companyCash'),
            value: compactMoney(company.cash),
            values: null,
          ),
          (
            label: tr('businesses.figures.debt'),
            value: compactMoney(debtOf(company)),
            values: null,
          ),
        ]),
        ...toDoItems(context, game, onOpen, only: id),
        Section(
          title: tr('businesses.title'),
          children: [
            if (businesses.isEmpty) Hint(tr('businesses.noneHere')),
            for (final business in businesses)
              _BusinessLine(business: business),
            if (active)
              IndexRow(
                icon: Icons.add,
                title: businesses.isEmpty
                    ? tr('common.startBusiness')
                    : tr('businesses.addBusiness'),
                subtitle: tr('businesses.addBusinessPitch', {
                  'company': game.companyName(company.id),
                }),
                onTap: () => openStartBusiness(context, company: company.id),
              ),
          ],
        ),
        _Subsidiaries(company: company, onOpen: onOpen),
        if (directors != null && active)
          Section(
            title: tr('businesses.boss'),
            children: [
              if (director != null)
                IndexRow(
                  icon: Icons.badge_outlined,
                  title: boss!,
                  subtitle: directorLine(
                    game.content,
                    directors.grades[director.grade.index],
                    directorPerson(game, company, director),
                  ),
                  onTap: () => context.openPage(
                    boss,
                    (_) => [DirectorSection(company: company)],
                  ),
                )
              else
                IndexRow(
                  icon: Icons.badge_outlined,
                  title: tr('common.hireDirector'),
                  subtitle: tr('businesses.hireBossPitch'),
                  onTap: () => showDirectorSheet(context, company),
                ),
            ],
          ),
        Section(
          title: tr('businesses.levers'),
          children: [
            IndexRow(
              title: tr('dashboard.companyMoneyLine'),
              subtitle: tr('dashboard.inFinance'),
              value: money(company.cash, cents: false),
              onTap: () => openCompanyPage(context, company),
            ),
            if (active)
              IndexRow(
                icon: Icons.edit_outlined,
                title: tr('businesses.rename'),
                subtitle: game.companyName(company.id),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => GameScope(
                    controller: game,
                    child: _RenameCompanyDialog(company: company.id),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// [company]'s subsidiaries, a line each with its worth and whether its
/// profit rose last month, opening its page; then the way to found one.
class _Subsidiaries extends StatelessWidget {
  const _Subsidiaries({required this.company, required this.onOpen});

  final CompanyView company;
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final subsidiaries = game.subsidiariesOf(company.id);
    if (company.status != CompanyStatus.active) return const SizedBox.shrink();
    return Section(
      title: tr('businesses.subsidiaries'),
      children: [
        for (final subsidiary in subsidiaries)
          () {
            final profits = monthlyProfits(game, company: subsidiary.id);
            final last = profits.lastOrNull ?? Money.zero;
            final before = profits.length > 1
                ? profits[profits.length - 2]
                : Money.zero;
            return IndexRow(
              title: game.companyName(subsidiary.id),
              subtitle: holdsLine(
                subsidiary,
                companySummary(game, subsidiary, game.view.national),
              ),
              value:
                  '${compactMoney(SimulationController.worthOf(subsidiary))}'
                  '${arrow(last, before)}',
              onTap: () => openCompanyDashboard(context, subsidiary, onOpen),
            );
          }(),
        IndexRow(
          icon: Icons.account_tree_outlined,
          title: tr('businesses.foundSubsidiary'),
          subtitle: tr('businesses.foundSubsidiaryPitch'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => GameScope(
              controller: game,
              child: _FoundDialog(parent: company),
            ),
          ),
        ),
      ],
    );
  }
}

/// A subsidiary's name and its capital, from its parent's cash.
class _FoundDialog extends StatefulWidget {
  const _FoundDialog({required this.parent});

  final CompanyView parent;

  @override
  State<_FoundDialog> createState() => _FoundDialogState();
}

class _FoundDialogState extends State<_FoundDialog> {
  final _name = TextEditingController();
  final _capital = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final name = _name.text.trim();
    final capital = parseMoney(_capital.text);
    final cash = widget.parent.cash;
    final ok =
        name.isNotEmpty &&
        capital != null &&
        capital > Money.zero &&
        capital <= cash;
    return AlertDialog(
      title: Text(tr('businesses.foundSubsidiary')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('businesses.name')),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _capital,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('businesses.capitalFrom', {
                'company': game.companyName(widget.parent.id),
              }),
              helperText: tr('businesses.hasCash', {
                'cash': money(cash, cents: false),
              }),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: ok
              ? () {
                  game.submit(
                    FoundCompany(
                      game.player,
                      name: name,
                      capital: capital,
                      parent: widget.parent.id,
                    ),
                  );
                  Navigator.pop(context);
                }
              : null,
          child: Text(tr('businesses.found')),
        ),
      ],
    );
  }
}

/// A business on its company's page: what it is, its size, and last
/// month's sales against the month before.
class _BusinessLine extends StatelessWidget {
  const _BusinessLine({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final months = business.months;
    final last = months.lastOrNull;
    final before = months.length > 1 ? months[months.length - 2] : null;
    return IndexRow(
      mark: businessMark(context, business),
      title: business.name,
      subtitle: switch (business.kind) {
        BusinessKind.trade => [
          tr('common.stores', {'count': business.units}),
          tr('businesses.countries', {
            'count': business.countries(game.content).length,
          }),
        ].join(' · '),
        BusinessKind.works => tr('businesses.factories', {
          'count': business.units,
        }),
        BusinessKind.software => tr('businesses.customers', {
          'count': compactCount(business.software?.customers ?? 0),
        }),
      },
      value: last == null
          ? null
          : '${compactMoney(last.sales)}'
                '${arrow(last.sales, before?.sales ?? Money.zero)}',
      onTap: () => openBusinessPage(context, business),
    );
  }
}

/// A company's new name.
class _RenameCompanyDialog extends StatefulWidget {
  const _RenameCompanyDialog({required this.company});

  final CompanyId company;

  @override
  State<_RenameCompanyDialog> createState() => _RenameCompanyDialogState();
}

class _RenameCompanyDialogState extends State<_RenameCompanyDialog> {
  late final _name = TextEditingController(
    text: context.game.companyName(widget.company),
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final name = _name.text.trim();
    return AlertDialog(
      title: Text(tr('businesses.rename')),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 32,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: tr('businesses.name')),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: name.isEmpty
              ? null
              : () {
                  game.submit(
                    RenameCompany(
                      game.player,
                      company: widget.company,
                      name: name,
                    ),
                  );
                  Navigator.pop(context);
                },
          child: Text(tr('store.rename')),
        ),
      ],
    );
  }
}
