import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../directors.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'holding.dart' show openCompanyDashboard;
import 'start.dart';

/// What a company holds and how it did, as its line in the Businesses tab
/// and the summary on its page say it.
typedef CompanySummary = ({
  /// Its shops played in full, which its owner or its director runs.
  int byHand,

  /// Its shops by formula: in districts run so, and across countries.
  int byFormula,
  int factories,

  /// Who runs it, by name or grade; null without a director.
  String? director,

  /// Its sales and profit in the last full month; null before one.
  ({Money sales, Money profit})? month,
});

/// [company]'s summary, its shops by formula counted from [national], the
/// countries by formula as the player sees them.
CompanySummary companySummary(
  SimulationController game,
  CompanyView company,
  List<NationalCountryView> national,
) {
  var byFormula = 0;
  for (final district in game.view.districts) {
    for (final shop in district.shops) {
      if (shop.company == company.id) byFormula++;
    }
  }
  for (final country in national) {
    for (final block in country.blocks) {
      if (block.company == company.id) byFormula += block.stores;
    }
  }
  final directors = game.content.directors;
  final director = game.directorOf(company);
  final current = ReportPeriod.month.startOf(game.today);
  final full = game
      .reports(ReportPeriod.month, company: company.id)
      .where((month) => month.start != current)
      .lastOrNull;
  return (
    byHand: company.stores
        .where((store) => store.status != StoreStatus.closed)
        .length,
    byFormula: byFormula,
    factories: company.factories
        .where((f) => f.status != FactoryStatus.closed)
        .length,
    director: director == null || directors == null
        ? null
        : directorPerson(game, company, director)?.name ??
              aDirector(directors.grades[director.grade.index]),
    month: full == null
        ? null
        : (sales: -full.flow(AccountKind.revenue), profit: full.profit),
  );
}

/// What [company] holds, in a few words: its software and customers, or
/// its shops and factories.
String holdsLine(CompanyView company, CompanySummary summary) {
  if (company.software case final software?) {
    return '${tr('business.software')} · '
        '${tr('businesses.customers', {'count': compactCount(software.customers)})}';
  }
  final shops = summary.byHand + summary.byFormula;
  final parts = [
    if (shops > 0) tr('common.stores', {'count': shops}),
    if (summary.factories > 0)
      tr('businesses.factories', {'count': summary.factories}),
  ];
  return parts.isEmpty ? tr('businesses.nothingYet') : parts.join(' · ');
}

/// The Businesses tab, the owner's layout A (2026-11-17): the companies
/// still trading, a line each with what it holds, who runs it, last month's
/// sales and profit and its cash, each opening its page; then the way to
/// start another business.
class BusinessesScreen extends StatelessWidget {
  const BusinessesScreen({super.key, required this.onOpen});

  /// Switches to another tab, from a company's page.
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final companies = game.activeCompanies;
    // Worked out once: the countries by formula take a while.
    final national = game.view.national;
    return ListView(
      key: const PageStorageKey('businesses'),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Section(
          title: companies.length == 1
              ? tr('common.yourCompany')
              : tr('common.yourCompanies'),
          children: [
            if (companies.isEmpty) Hint(tr('businesses.none')),
            for (final company in companies)
              _CompanyLine(
                company: company,
                summary: companySummary(game, company, national),
                onOpen: onOpen,
              ),
            IndexRow(
              icon: Icons.add_business_outlined,
              title: tr('common.startBusiness'),
              subtitle: tr('dashboard.startBusinessPitch'),
              onTap: () => openStartBusiness(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// A company on its line: what it holds and who runs it, then last month's
/// sales and profit; its cash on the right.
class _CompanyLine extends StatelessWidget {
  const _CompanyLine({
    required this.company,
    required this.summary,
    required this.onOpen,
  });

  final CompanyView company;
  final CompanySummary summary;
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final ledger = Ledger.of(context);
    final first = company.stores.firstOrNull;
    final runBy = switch (summary.director) {
      final director? => tr('dashboard.runBy', {'director': director}),
      null when company.software == null => tr('businesses.byHand'),
      null => null,
    };
    return IndexRow(
      mark: company.software != null
          ? ledger.software
          : first != null
          ? ledger.trade(game.content.formats[first.format.index])
          : company.factories.isNotEmpty
          ? ledger.works
          : null,
      title: game.companyName(company.id),
      subtitle: [
        [holdsLine(company, summary), ?runBy].join(' · '),
        if (summary.month case (:final sales, :final profit))
          tr('businesses.lastMonth', {
            'sales': money(sales, cents: false),
            'profit': signedMoney(profit, cents: false),
          }),
      ].join('\n'),
      value: money(company.cash, cents: false),
      onTap: () => openCompanyDashboard(context, company, onOpen),
    );
  }
}
