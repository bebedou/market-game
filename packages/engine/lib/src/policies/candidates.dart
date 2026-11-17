import '../content/content_db.dart';
import '../core/hash32.dart';
import '../core/ids.dart';
import '../observation/observation.dart';
import '../reports/period_report.dart';
import '../state/director.dart';
import '../state/store.dart';

/// A director the owner may hire: their grade and who they are.
typedef DirectorCandidate = ({DirectorGradeId grade, DirectorPerson person});

/// Mixed into every candidate's hash, so no other hash in the game draws
/// the same numbers.
const _salt = 0x64697263;

/// The directors [company] may hire this month, one of each grade, from
/// [country]: their names from its pool, each with a character no other on
/// the list has while there are enough, and a past at one of its chains of
/// the company's trades. The list is the same all month and changes on the
/// first; empty without persons in the scenario.
List<DirectorCandidate> directorShortlist(
  ContentDb content,
  Observation view,
  CompanyView company,
  CountryId country,
) {
  final directors = content.directors;
  final names = directors?.namesIn(country);
  if (directors == null || names == null || directors.characters.isEmpty) {
    return const [];
  }
  final month = ReportPeriod.month.startOf(view.today).number;
  int draw(int slot, int what) =>
      (Hash32(_salt)
            ..addInt(company.id.index)
            ..addInt(month)
            ..addInt(slot)
            ..addInt(what))
          .finish();

  // The characters in an order of the month's own, so each grade has a
  // different one while there are enough.
  final order = [for (var i = 0; i < directors.characters.length; i++) i];
  for (var i = order.length - 1; i > 0; i--) {
    final j = draw(-1, i) % (i + 1);
    final swapped = order[i];
    order[i] = order[j];
    order[j] = swapped;
  }
  final employers = _employers(content, view, company, country);
  final taken = <String>{};
  return [
    for (final (g, grade) in directors.grades.indexed)
      (
        grade: grade.id,
        person: _person(
          names,
          g,
          order[g % order.length],
          employers,
          taken,
          (what) => draw(g, what),
        ),
      ),
  ];
}

/// Who [director] is: their person, or, for one hired before directors
/// were people, the one of their grade on [company]'s shortlist of the
/// month they came, applying the brief as it is.
DirectorPerson? personOf(
  ContentDb content,
  Observation view,
  CompanyView company,
  CountryId country,
  Director director,
) {
  if (director.person case final person?) return person;
  final directors = content.directors;
  final names = directors?.namesIn(country);
  if (directors == null || names == null) return null;
  int draw(int what) =>
      (Hash32(_salt)
            ..addInt(company.id.index)
            ..addInt(ReportPeriod.month.startOf(director.hiredOn).number)
            ..addInt(director.grade.index)
            ..addInt(what))
          .finish();
  final plain = directors.characters.indexWhere((c) => c.isPlain);
  return _person(
    names,
    director.grade.index,
    plain < 0 ? -1 : plain,
    _employers(content, view, company, country),
    {},
    draw,
  );
}

DirectorPerson _person(
  DirectorNames names,
  int grade,
  int character,
  List<String> employers,
  Set<String> taken,
  int Function(int what) draw,
) {
  final female = draw(0) & 1 == 1;
  final firsts = female ? names.women : names.men;
  // Two candidates of one month never share a first name while there are
  // others.
  var f = draw(1) % firsts.length;
  for (var tries = 1; tries < firsts.length && taken.contains(firsts[f]);) {
    f = (f + 1) % firsts.length;
    tries++;
  }
  final first = firsts[f];
  taken.add(first);
  var surname = draw(2) % names.surnames.length;
  var name = '$first ${names.surnames[surname]}';
  // Two candidates of one month never share a name.
  for (var tries = 0; taken.contains(name) && tries < names.surnames.length;) {
    surname = (surname + 1) % names.surnames.length;
    name = '$first ${names.surnames[surname]}';
    tries++;
  }
  taken.add(name);
  // Higher grades have been at it longer.
  final years = 3 + 5 * grade + draw(3) % (4 + 3 * grade);
  return DirectorPerson(
    name: name,
    female: female,
    character: character,
    looks: draw(4),
    employer: employers.isEmpty ? '' : employers[draw(5) % employers.length],
    years: years,
  );
}

/// The chains of [country] in the trades of [company]'s shops, or any of
/// its chains if it has no shops of a trade there.
List<String> _employers(
  ContentDb content,
  Observation view,
  CompanyView company,
  CountryId country,
) {
  for (final national in view.national) {
    if (national.country != country) continue;
    final trades = {
      for (final store in company.stores)
        if (store.status != StoreStatus.closed)
          ?national.tradeOf(content, store.format),
    };
    final chains = [
      for (final chain in national.def.chains)
        if (!chain.independent) chain,
    ];
    final fitting = [
      for (final chain in chains)
        if (trades.contains(chain.trade)) chain.name,
    ];
    return fitting.isNotEmpty ? fitting : [for (final c in chains) c.name];
  }
  return const [];
}
