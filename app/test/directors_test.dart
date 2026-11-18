import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/directors.dart';
import 'package:market_game/src/l10n.dart';
import 'package:market_game/src/letters.dart';
import 'package:market_game/src/screens/finance.dart';
import 'package:market_game/src/widgets.dart';

import 'flutter_test_config.dart';
import 'support.dart';

/// Opens the hiring sheet of the player's company from Finance.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Finance'));
  await tester.pumpAndSettle();
  await openIndex(tester, 'Corner Shop');
  await scrollTo(tester, find.text('Hire a director'));
  await tester.tap(find.text('Hire a director'));
  await tester.pumpAndSettle();
}

void main() {
  test('every character and grade has its words in every language', () {
    final directors = prototype.directors!;
    for (final code in ['en', 'fr', 'es']) {
      useStrings(stringsFromFiles(code, fallback: stringsFromFiles('en')));
      for (final form in ['man', 'woman']) {
        for (final grade in directors.grades) {
          expect(
            trMaybe('directors.titles.${grade.key}.$form'),
            isNotNull,
            reason: '$code ${grade.key}',
          );
          expect(trMaybe('directors.past.${grade.key}'), isNotNull);
          expect(trMaybe('directors.pastNowhere.${grade.key}'), isNotNull);
        }
        for (final character in directors.characters) {
          expect(
            trMaybe('directors.characters.${character.key}.$form'),
            isNotNull,
            reason: '$code ${character.key}',
          );
        }
      }
      for (final character in directors.characters) {
        expect(trList('directors.mottos.${character.key}'), isNotEmpty);
        for (final month in ['earned', 'lost']) {
          expect(
            trList('directors.voices.${character.key}.$month'),
            isNotEmpty,
            reason: '$code ${character.key} $month',
          );
        }
      }
    }
    useStrings(stringsFromFiles('en'));
  });

  test('a person is titled, characterised and given a past in their words', () {
    final game = newController();
    final company = game.view.companies.first;
    final shortlist = directorShortlist(
      prototype,
      game.view,
      company,
      game.countryOfCompany(company),
    );
    expect(shortlist, hasLength(prototype.directors!.grades.length));
    for (final (:grade, :person) in shortlist) {
      final def = prototype.directors!.grades[grade.index];
      final line = directorLine(prototype, def, person);
      expect(line, startsWith(def.name));
      expect(line, contains(' · '));
      expect(motto(prototype, person), isNotNull);
      expect(pastLine(def, person), contains('${person.years} years'));
      final pitch = characterPitch(
        prototype,
        person,
        prototype.strategies.first,
      )!;
      expect(pitch, endsWith('.'));
      expect(pitch[0], pitch[0].toUpperCase());
    }
    final bold = prototype.directors!.characters.indexWhere(
      (c) => c.key == 'bold',
    );
    final person = DirectorPerson(
      name: 'Hélène Varenne',
      female: true,
      character: bold,
      looks: 0,
      years: 9,
    );
    final months = prototype.strategies.first.expansionPaybackMonths;
    expect(
      characterPitch(prototype, person, prototype.strategies.first),
      'Bold: takes shops that pay back in up to '
      '${scaledMonths(months, Fx.parse('1.25'))} months, against your '
      'strategy’s $months, keeps a thinner cushion of cash, left to judge, '
      'grows faster than their grade runs well and asks 10% more pay.',
    );
    useStrings(stringsFromFiles('fr', fallback: stringsFromFiles('en')));
    expect(
      directorLine(prototype, prototype.directors!.grades[1], person),
      'Directrice chevronnée · audacieuse',
    );
    useStrings(stringsFromFiles('en'));
  });

  testWidgets('the hiring sheet offers this month’s shortlist, and hires the '
      'person picked', (tester) async {
    final game = newController();
    final company = game.view.companies.first;
    final shortlist = directorShortlist(
      prototype,
      game.view,
      company,
      game.countryOfCompany(company),
    );
    await pumpGame(tester, game);
    await _openSheet(tester);
    expect(find.text('This month’s shortlist'), findsOneWidget);
    final sheet = find.byType(Scrollable).last;
    for (final (grade: _, :person) in shortlist) {
      await tester.scrollUntilVisible(
        find.text(person.name),
        100,
        scrollable: sheet,
      );
      expect(find.text(person.name), findsOneWidget);
    }
    // The star, the last on the list.
    final star = shortlist.last;
    await tester.ensureVisible(find.text(star.person.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(star.person.name));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('The company’s money'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.textContaining('Hire for'));
    await tester.pumpAndSettle();
    final hire = game.pending.single as HireDirector;
    expect(samePerson(hire.person, star.person), isTrue);
    expect(hire.grade, star.grade);
  });

  testWidgets('a director’s file shows who they are, their record and what '
      'their character does; their letters are signed and in their voice', (
    tester,
  ) async {
    final game = newController();
    final company = game.view.companies.first;
    final candidate = directorShortlist(
      prototype,
      game.view,
      company,
      game.countryOfCompany(company),
    )[1];
    game.submit(
      HireDirector(
        prototype.player,
        company: company.id,
        grade: candidate.grade,
        strategy: strategy('balanced'),
        managerGrade: grade('experienced'),
        growth: Growth.invest,
        payout: true,
        person: candidate.person,
      ),
    );
    for (var i = 0; i < 40; i++) {
      game.step();
    }
    final director = game.view.companies.first.director!;
    expect(samePerson(director.person, candidate.person), isTrue);
    expect(director.record.shopsAtHire, 1);

    final letters = directorLetters(
      game.view.companies.first,
      game.reports(ReportPeriod.month, company: company.id),
      prototype,
      game.view,
      by: candidate.person,
      since: director.hiredOn,
    );
    expect(letters, isNotEmpty);
    expect(samePerson(letters.first.by, candidate.person), isTrue);
    final character =
        prototype.directors!.characters[candidate.person.character];
    final voices = [
      ...trList('directors.voices.${character.key}.earned'),
      ...trList('directors.voices.${character.key}.lost'),
    ];
    expect(voices.contains(letters.first.paragraphs.last), isTrue);

    await pumpGame(tester, game);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    await openIndex(tester, 'Corner Shop');
    expect(find.byType(PersonHeader), findsOneWidget);
    expect(find.text(candidate.person.name), findsOneWidget);
    final def = prototype.directors!.grades[candidate.grade.index];
    expect(
      find.text(directorLine(prototype, def, candidate.person)),
      findsOneWidget,
    );
    expect(
      find.text('“${motto(prototype, candidate.person)}”'),
      findsOneWidget,
    );
    expect(find.widgetWithText(Line, 'Shops'), findsOneWidget);
    expect(find.text('Opened · bought · closed'), findsOneWidget);
    expect(find.textContaining('record here, since'), findsOneWidget);
    await scrollTo(tester, find.text('Letters'));
    expect(
      find.text(candidate.person.name.split(' ').first),
      findsWidgets,
      reason: 'signed with their first name',
    );
  });
}
