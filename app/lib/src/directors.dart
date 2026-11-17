import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';
import 'theme.dart';

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

/// A director's face in ink, drawn from their looks: hair, glasses, a beard
/// or moustache, and a collar, greyer the longer they have worked.
class DirectorPortrait extends StatelessWidget {
  const DirectorPortrait({super.key, required this.person, this.size = 44});

  final DirectorPerson? person;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: person?.name,
    child: CustomPaint(
      size: Size.square(size),
      painter: _PortraitPainter(person, Ledger.of(context)),
    ),
  );
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.person, this.ledger);

  final DirectorPerson? person;
  final Ledger ledger;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    final looks = person?.looks ?? 0;
    final female = person?.female ?? false;
    int bits(int shift, int count) => (looks >> shift) % count;
    final ink = ledger.ink;
    final hair = (person?.years ?? 0) >= 15 ? ledger.muted : ink;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final thin = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ink;
    final hairFill = Paint()..color = hair;
    final paper = Paint()..color = ledger.paper;

    // The frame: a disc of darker paper.
    canvas.drawCircle(
      const Offset(20, 20),
      19.5,
      Paint()..color = ledger.shade,
    );
    canvas.drawCircle(
      const Offset(20, 20),
      19.5,
      Paint()
        ..color = ledger.rule
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(20, 20), radius: 19.5)),
    );

    // Long hair falls behind the head.
    final style = bits(0, 4);
    if (female && style == 1) {
      canvas.drawPath(_path('M12 31 Q10 8 20 8 Q30 8 28 31 Z'), hairFill);
    }

    // Shoulders and collar.
    canvas.drawPath(_path('M7 41 Q8.5 30 20 29 Q31.5 30 33 41 Z'), paper);
    canvas.drawPath(_path('M7 41 Q8.5 30 20 29 Q31.5 30 33 41'), line);
    switch (bits(5, 4)) {
      case 0 when !female:
        canvas.drawPath(_path('M17.4 29.4 L20 32.6 L22.6 29.4'), thin);
        canvas.drawPath(_path('M20 32.6 L18.9 37 L20 40 L21.1 37 Z'), fill);
      case 0 || 1:
        canvas.drawPath(_path('M17 29.5 L20 34 L23 29.5'), thin);
      case 2:
        canvas.drawPath(_path('M15.5 30.6 Q20 34.2 24.5 30.6'), thin);
      default:
        canvas.drawPath(
          _path('M16.4 28.6 Q20 30.6 23.6 28.6 L23.8 31.2 Q20 33 16.2 31.2 Z'),
          thin,
        );
    }

    // The face, a little wider or narrower.
    final width = 6.6 + bits(7, 3) * 0.4;
    final face = Rect.fromCenter(
      center: const Offset(20, 18.5),
      width: width * 2,
      height: 17,
    );
    canvas.drawOval(face, paper);
    canvas.drawOval(face, line);

    // Hair on top.
    final top = switch ((female, style)) {
      (true, 0) =>
        'M12.5 22 Q11 8 20 8 Q29 8 27.5 22 Q27 13.5 20 12.5 '
            'Q14.5 13.5 12.5 22 Z',
      (true, 1) =>
        'M13 16 Q13 9 20 9 Q27 9 27 16 Q24 12.5 20 13 '
            'Q16 12.5 13 16 Z',
      (true, 2) =>
        'M13 16 Q13 9 20 9 Q27 9 27 16 Q24 12 20 12.5 '
            'Q16 12 13 16 Z',
      (true, _) =>
        'M13 17 Q13 9.5 20 9.5 Q27.5 9.5 27 17 Q25 12 21 12.5 '
            'Q16 13.5 13 17 Z',
      (false, 0) =>
        'M13 15 Q13 9 20 9 Q27 9 27 15 Q24 11.5 20 12 '
            'Q16 11.5 13 15 Z',
      (false, 1) =>
        'M13 16 Q12.5 9 19 9 Q27.5 8.5 27 16 Q26 12 22 12 '
            'Q18 11 15.5 13.5 Q14 14.5 13 16 Z',
      (false, 2) =>
        'M13 18 Q12.8 13 15 12 Q14.5 14 14.2 18 Z '
            'M27 18 Q27.2 13 25 12 Q25.5 14 25.8 18 Z',
      (false, _) => '',
    };
    if (top.isNotEmpty) canvas.drawPath(_path(top), hairFill);
    if (!female && style == 3) {
      for (final (x, y) in const [
        (14.6, 13.2),
        (17.0, 10.6),
        (20.0, 9.8),
        (23.0, 10.6),
        (25.4, 13.2),
      ]) {
        canvas.drawCircle(Offset(x, y), 2.5, hairFill);
      }
    }
    if (female && style == 2) {
      canvas.drawCircle(const Offset(20, 7.2), 3, hairFill);
    }

    // Eyes, or glasses.
    if (bits(2, 3) == 0) {
      canvas.drawCircle(const Offset(17, 18.8), 2.3, thin);
      canvas.drawCircle(const Offset(23, 18.8), 2.3, thin);
      canvas.drawLine(const Offset(19.3, 18.8), const Offset(20.7, 18.8), thin);
    }
    canvas.drawCircle(const Offset(17.2, 19), 0.75, fill);
    canvas.drawCircle(const Offset(22.8, 19), 0.75, fill);
    // Nose and mouth.
    canvas.drawPath(_path('M20 19.8 L19.3 22.4 L20.3 22.5'), thin);
    canvas.drawPath(
      _path(
        bits(9, 2) == 0
            ? 'M18.2 24.4 Q20 25.6 21.8 24.4'
            : 'M18.5 24.7 L21.5 24.7',
      ),
      thin,
    );
    if (!female) {
      switch (bits(3, 4)) {
        case 2:
          canvas.drawPath(
            _path('M17.6 23.6 Q20 22.5 22.4 23.6 Q20 24.3 17.6 23.6 Z'),
            hairFill,
          );
        case 3:
          canvas.drawPath(
            _path(
              'M13.5 20 Q14 28.6 20 28.9 Q26 28.6 26.5 20 '
              'Q25 25.6 20 25.8 Q15 25.6 13.5 20 Z',
            ),
            hairFill,
          );
        default:
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PortraitPainter old) =>
      old.person != person || old.ledger != ledger;
}

/// [data], a path in the few SVG commands the portraits use: M, L, Q and Z,
/// with absolute figures.
Path _path(String data) {
  final path = Path();
  final tokens = RegExp(r'[MLQZ]|-?\d+(?:\.\d+)?').allMatches(data).toList();
  var i = 0;
  double next() => double.parse(tokens[i++].group(0)!);
  while (i < tokens.length) {
    switch (tokens[i++].group(0)) {
      case 'M':
        path.moveTo(next(), next());
      case 'L':
        path.lineTo(next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
      case 'Z':
        path.close();
    }
  }
  return path;
}
