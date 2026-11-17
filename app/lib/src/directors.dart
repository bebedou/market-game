import 'package:engine/engine.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';

/// Who [director] of [company] is: their person, or, for one hired before
/// directors were people, the one the shortlist of their month would have
/// shown, applying the brief as it is.
DirectorPerson? directorPerson(
  SimulationController game,
  CompanyView company,
  Director director,
) => personOf(
  game.content,
  game.view,
  company,
  game.countryOfCompany(company),
  director,
);

/// "Seasoned director", "Directrice chevronnée": [grade] as [person]'s title.
String directorTitle(DirectorGradeDef grade, DirectorPerson? person) =>
    trMaybe('directors.titles.${grade.key}.${_form(person)}') ?? grade.name;

/// "bold", "audacieuse": [person]'s character, in the agreement of their
/// sex; null if the scenario has none for them.
String? characterName(ContentDb content, DirectorPerson? person) {
  final character = _character(content, person);
  if (character == null) return null;
  return trMaybe('directors.characters.${character.key}.${_form(person)}') ??
      character.name.toLowerCase();
}

/// "Seasoned director · bold": [person]'s title and character.
String directorLine(
  ContentDb content,
  DirectorGradeDef grade,
  DirectorPerson? person,
) =>
    [directorTitle(grade, person), ?characterName(content, person)].join(' · ');

/// One of [person]'s sayings, the same one always.
String? motto(ContentDb content, DirectorPerson? person) {
  final character = _character(content, person);
  if (person == null || character == null) return null;
  final sayings = trList('directors.mottos.${character.key}');
  if (sayings.isEmpty) return null;
  return sayings[person.looks % sayings.length];
}

/// Where [person] worked before, for how long, as their grade has it.
String? pastLine(DirectorGradeDef grade, DirectorPerson? person) {
  if (person == null || person.years <= 0) return null;
  return person.employer.isEmpty
      ? tr('directors.pastNowhere.${grade.key}', {'count': person.years})
      : tr('directors.past.${grade.key}', {
          'count': person.years,
          'employer': person.employer,
        });
}

/// What [person]'s character changes in how they apply a brief of
/// [strategy], with its figures: one sentence; null without a character.
String? characterPitch(
  ContentDb content,
  DirectorPerson? person,
  StrategyDef strategy,
) {
  final character = _character(content, person);
  if (character == null) return null;
  final one = Fx.one;
  final clauses = [
    if (character.payback != one)
      tr('directors.does.payback', {
        'months': scaledMonths(
          strategy.expansionPaybackMonths,
          character.payback,
        ),
        'usual': strategy.expansionPaybackMonths,
      }),
    if (character.reserve > one) tr('directors.does.thickCushion'),
    if (character.reserve < one) tr('directors.does.thinCushion'),
    if (character.credit < one)
      tr('directors.does.credit', {
        'share': percent(character.credit, decimals: 0),
      }),
    if (character.pace > one) tr('directors.does.fastPace'),
    if (character.pace < one) tr('directors.does.slowPace'),
    if (character.coaching < one) tr('directors.does.lessCoaching'),
    if (character.coaching > one) tr('directors.does.moreCoaching'),
    if (character.salary > one)
      tr('directors.does.dearer', {
        'change': percent(character.salary - one, decimals: 0),
      }),
    if (character.salary < one)
      tr('directors.does.cheaper', {
        'change': percent(one - character.salary, decimals: 0),
      }),
  ];
  return capitalized(
    tr('directors.pitch', {
      'character': characterName(content, person),
      'what': clauses.isEmpty ? tr('directors.does.asItIs') : listText(clauses),
    }),
  );
}

/// A line a director of [person]'s character adds to the letter of [month],
/// after a month that [earned] or lost money.
String? voiceLine(
  ContentDb content,
  DirectorPerson? person,
  Day month, {
  required bool earned,
}) {
  final character = _character(content, person);
  if (person == null || character == null) return null;
  final lines = trList(
    'directors.voices.${character.key}.${earned ? 'earned' : 'lost'}',
  );
  if (lines.isEmpty) return null;
  final pick =
      (month.date.month + month.date.year * 12 + person.looks) % lines.length;
  return lines[pick];
}

/// [company]'s shops of every scale, as [view] shows them: run in full,
/// asleep in districts run by formula, and across countries.
int shopsOf(Observation view, CompanyView company) {
  var shops = 0;
  for (final store in company.stores) {
    if (store.status != StoreStatus.closed) shops++;
  }
  for (final district in view.districts) {
    for (final shop in district.shops) {
      if (shop.company == company.id) shops++;
    }
  }
  for (final country in view.national) {
    for (final block in country.blocks) {
      if (block.company == company.id) shops += block.stores;
    }
  }
  return shops;
}

/// [company]'s sales in the last full month before [director] came, or the
/// first after if it had none, and in the last full month since.
({Money then, Money now})? salesSince(
  SimulationController game,
  CompanyView company,
  Director director,
) {
  final months = game.reports(ReportPeriod.month, company: company.id);
  final current = ReportPeriod.month.startOf(game.today);
  final full = [
    for (final month in months)
      if (month.start != current) month,
  ];
  if (full.length < 2) return null;
  final hired = ReportPeriod.month.startOf(director.hiredOn);
  PeriodReport? before;
  for (final month in full) {
    if (month.start.number < hired.number) before = month;
  }
  before ??= full.where((m) => m.start.number >= hired.number).firstOrNull;
  final latest = full.last;
  if (before == null || identical(before, latest)) return null;
  return (
    then: -before.flow(AccountKind.revenue),
    now: -latest.flow(AccountKind.revenue),
  );
}

DirectorCharacterDef? _character(ContentDb content, DirectorPerson? person) {
  final characters = content.directors?.characters ?? const [];
  final index = person?.character ?? -1;
  return index >= 0 && index < characters.length ? characters[index] : null;
}

String _form(DirectorPerson? person) =>
    person?.female ?? false ? 'woman' : 'man';
