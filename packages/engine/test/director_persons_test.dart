import 'package:engine/engine.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/policies/director.dart';
import 'package:engine/src/policies/retail_policy.dart' show operatingReserve;
import 'package:test/test.dart';

import 'director_test.dart' show clerk, hire, novice, star, withDirectors;
import 'support/fixtures.dart';

/// [json] with directors who are people: four characters, the last two
/// made to show their levers plainly, and names to give them.
String withPersons(String json) => withDirectors(json).replaceFirst(
  '"salary": "3.00" }\n  ] },',
  '"salary": "3.00" }\n  ],\n'
      '  "characters": [\n'
      '    { "id": "steady", "name": "Steady" },\n'
      '    { "id": "thrifty", "name": "Thrifty", "coaching": "0.6", "salary": "0.8" },\n'
      '    { "id": "timid", "name": "Timid", "payback": "0.01", "reserve": "3", "credit": "0" },\n'
      '    { "id": "rash", "name": "Rash", "pace": "1.5" }\n'
      '  ],\n'
      '  "people": [\n'
      '    { "women": ["Ada", "Bea"], "men": ["Cyril", "Dov"], "surnames": ["Eyre", "Frey", "Gale"] }\n'
      '  ] },',
);

const _thrifty = 1;
const _timid = 2;
const _rash = 3;

DirectorPerson _person(int character, {String name = 'Ada Eyre'}) =>
    DirectorPerson(
      name: name,
      female: true,
      character: character,
      looks: 1234,
      employer: 'Rival Mart',
      years: 9,
    );

void main() {
  final content = loadScenario(withPersons(testScenarioJson));
  final start = content.startDay;
  final opening = loadScenario(
    withPersons(testScenarioJson)
        .replaceFirst(
          '"expansionPaybackMonths": 0,\n      "expansionIntervalDays": 365',
          '"expansionPaybackMonths": 60,\n      "expansionIntervalDays": 30',
        )
        .replaceFirst('"cash": "500.00" }', '"cash": "5000.00" }'),
  );

  Director? director(Simulation simulation) =>
      simulation.observe(player).companies.first.director;

  test('load the characters and names on offer, or none', () {
    final directors = content.directors!;
    expect(directors.characters.map((c) => c.key), [
      'steady',
      'thrifty',
      'timid',
      'rash',
    ]);
    expect(directors.characters.first.isPlain, isTrue);
    expect(directors.characters[_thrifty].salary, Fx.parse('0.8'));
    expect(directors.characters[_timid].credit, Fx.zero);
    expect(directors.namesIn(const CountryId(0))!.surnames, [
      'Eyre',
      'Frey',
      'Gale',
    ]);
    final plain = loadScenario(withDirectors(testScenarioJson)).directors!;
    expect(plain.characters, isEmpty);
    expect(plain.namesIn(const CountryId(0)), isNull);
    expect(
      () => loadScenario(
        withPersons(
          testScenarioJson,
        ).replaceFirst('"id": "thrifty"', '"id": "steady"'),
      ),
      throwsA(isA<ContentException>()),
    );
    expect(
      () => loadScenario(
        withPersons(
          testScenarioJson,
        ).replaceFirst('"women": ["Ada", "Bea"]', '"women": []'),
      ),
      throwsA(isA<ContentException>()),
    );
  });

  group('the shortlist', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final view = simulation.observe(player);
    final company = view.companies.first;
    List<DirectorCandidate> list(Observation view) => directorShortlist(
      content,
      view,
      view.companies.first,
      const CountryId(0),
    );

    test('holds one of each grade, named from the pool, each a character '
        'of their own', () {
      final shortlist = list(view);
      expect(shortlist.map((c) => c.grade), [novice, star]);
      final names = content.directors!.namesIn(const CountryId(0))!;
      for (final (:grade, :person) in shortlist) {
        final [first, surname] = person.name.split(' ');
        expect(
          (person.female ? names.women : names.men).contains(first),
          isTrue,
        );
        expect(names.surnames.contains(surname), isTrue);
        expect(person.years, greaterThanOrEqualTo(3 + 5 * grade.index));
      }
      expect(shortlist.map((c) => c.person.character).toSet().length, 2);
      expect(shortlist.map((c) => c.person.name).toSet().length, 2);
    });

    test('stays the same all month, and changes on the first', () {
      final first = list(view);
      for (var i = 0; i < 20; i++) {
        simulation.step();
      }
      List<(String, int)> who(List<DirectorCandidate> list) => [
        for (final (grade: _, :person) in list) (person.name, person.looks),
      ];
      expect(who(list(simulation.observe(player))), who(first));
      while (!simulation.today.isFirstOfMonth) {
        simulation.step();
      }
      expect(who(list(simulation.observe(player))), isNot(who(first)));
    });

    test('is empty without persons in the scenario', () {
      final plain = loadScenario(withDirectors(testScenarioJson));
      final view = Simulation.newGame(plain, seed: 1).observe(player);
      expect(
        directorShortlist(
          plain,
          view,
          view.companies.first,
          const CountryId(0),
        ),
        isEmpty,
      );
    });

    test('gives a director hired before persons the one of their grade '
        'from their month, applying the brief as it is', () {
      final old = Director(
        grade: star,
        strategy: steady,
        managerGrade: clerk,
        growth: Growth.none,
        payout: false,
        hiredOn: start,
      );
      final person = personOf(content, view, company, const CountryId(0), old)!;
      expect(person.character, 0, reason: 'steady, who changes nothing');
      expect(
        samePerson(
          personOf(content, view, company, const CountryId(0), old),
          person,
        ),
        isTrue,
      );
      expect(content.directors!.characterOf(old).isPlain, isTrue);
    });
  });

  test('are hired as people, keep their record when rebriefed, and a new '
      'person replaces them', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final ada = _person(_thrifty);
    simulation.submit(
      HireDirector(
        player,
        company: playerCompany,
        grade: novice,
        strategy: steady,
        managerGrade: clerk,
        growth: Growth.none,
        payout: false,
        person: _person(9),
      ),
    );
    expect(simulation.step().rejections.single.reason.key, 'unknownCharacter');
    simulation
      ..submit(hire(grade: novice).withPerson(ada))
      ..step();
    expect(samePerson(director(simulation)?.person, ada), isTrue);
    expect(director(simulation)?.record.shopsAtHire, 1);
    final hired = director(simulation)!.hiredOn;
    simulation
      ..submit(hire(grade: novice, payout: true).withPerson(ada))
      ..step();
    expect(director(simulation)?.hiredOn, hired, reason: 'rebriefed');
    expect(director(simulation)?.payout, isTrue);
    simulation
      ..submit(
        hire(grade: novice).withPerson(_person(_thrifty, name: 'Bea Frey')),
      )
      ..step();
    expect(director(simulation)?.person?.name, 'Bea Frey');
    expect(director(simulation)?.hiredOn, isNot(hired), reason: 'replaced');
  });

  test('ask the pay their character does', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    )..submit(hire(grade: novice).withPerson(_person(_thrifty)));
    final paid = [
      for (final entry in simulation.step().entries)
        if (entry.reason == EntryReason.salary &&
            entry.debit == AccountKind.salaries)
          entry.amount,
    ];
    expect(paid, [Money.parse('1.60')]);
    final view = simulation.observe(player);
    expect(
      directorSalary(
        view,
        content,
        view.companies.first,
        view.companies.first.director!,
      ),
      Money.parse('1.60'),
    );
  });

  test('coach managers and grow as their character does', () {
    final directors = content.directors!;
    Director of(int character, {bool auto = true}) => Director(
      grade: star,
      strategy: steady,
      managerGrade: clerk,
      growth: Growth.open,
      payout: false,
      hiredOn: start,
      nationalAuto: auto,
      person: _person(character),
    );
    expect(directors.keptBy(of(0)), directors.kept(star));
    // Full skill and half coaching, done at 0.6: 30% taken away.
    expect(directors.keptBy(of(_thrifty)), Fx.parse('0.70'));
    final grade = directors.grades[star.index].growth;
    expect(directors.growthRateOf(of(0)), grade);
    expect(directors.growthRateOf(of(_rash)), grade * Fx.parse('1.5'));
    expect(
      directors.growthRateOf(of(_rash, auto: false)),
      Fx.zero,
      reason: "the brief's own rate",
    );
  });

  group('on the first of the month', () {
    (Simulation, Observation) firstOfFebruary(
      DirectorPerson? person, {
      Growth growth = Growth.open,
    }) {
      final simulation = Simulation.newGame(opening, seed: 1)
        ..submit(hire(growth: growth, payout: true).withPerson(person));
      for (var i = 0; i < 31; i++) {
        simulation.step();
      }
      return (simulation, simulation.observe(player));
    }

    Money reserve(Observation view) => operatingReserve(
      view,
      view.companies.first,
      opening.strategies.single.reserveDays,
    )!;

    test('a director who takes no shop that pays back slowly opens none, '
        'where one who applies the brief opens one', () {
      for (final (person, opens) in [
        (_person(0), true),
        (_person(_timid), false),
      ]) {
        final (_, view) = firstOfFebruary(person);
        final commands = direct(
          view,
          opening,
          view.companies.first,
          reserve(view).timesInt(4) + Money.parse('2000.00'),
          const {},
          [],
        );
        expect(
          commands.any((command) => command is OpenStore),
          opens,
          reason: person.name,
        );
      }
    });

    test('a director keeping a thicker cushion pays out less', () {
      Money paid(DirectorPerson person) {
        final (_, view) = firstOfFebruary(person, growth: Growth.invest);
        final directives = <Directive>[];
        // Beyond three times the usual reserve, a cent.
        direct(
          view,
          opening,
          view.companies.first,
          reserve(view).timesInt(3) + Money.parse('0.01'),
          const {},
          directives,
        );
        return [
          for (final d in directives)
            if (d.memo case ProfitPaid(:final amount)) amount,
        ].fold(Money.zero, (sum, amount) => sum + amount);
      }

      expect(paid(_person(_timid)) < paid(_person(0)), isTrue);
    });

    test('count what they did in their record', () {
      final (simulation, _) = firstOfFebruary(_person(0));
      simulation.step();
      final record = director(simulation)!.record;
      expect(record.opened, 1);
      expect(record.bought, 0);
      expect(record.closed, 0);
    });
  });

  test('a record counts each kind of memo once', () {
    var record = const DirectorRecord(shopsAtHire: 2);
    for (final memo in <Memo>[
      StoreOpened(
        start,
        site: lane,
        format: const FormatId(0),
        cost: Money.zero,
        paybackMonths: 1,
      ),
      NationalOpened(
        start,
        country: const CountryId(0),
        region: 'r',
        format: const FormatId(0),
        count: 4,
        cost: Money.zero,
        earns: Money.zero,
        paybackMonths: 1,
      ),
      StoreBought(
        start,
        store: const StoreId(1),
        price: Money.zero,
        paybackMonths: 1,
      ),
      StoreClosed(
        start,
        store: const StoreId(1),
        sales: Money.zero,
        loss: Money.zero,
      ),
      ProfitPaid(start, amount: Money.parse('12.00')),
      ProfitPaid(start, amount: Money.parse('3.00')),
    ]) {
      record = record.noting(memo);
    }
    expect(
      (record.shopsAtHire, record.opened, record.bought, record.closed),
      (2, 5, 1, 1),
    );
    expect(record.paid, Money.parse('15.00'));
    final hired = ManagerHired(start, store: const StoreId(0), grade: clerk);
    expect(identical(record.noting(hired), record), isTrue);
  });

  test('a person and record survive a save; older briefs and commands read '
      'with none', () {
    final brief = Director(
      grade: star,
      strategy: steady,
      managerGrade: clerk,
      growth: Growth.open,
      payout: true,
      hiredOn: start,
      person: _person(_thrifty),
      record: DirectorRecord(
        shopsAtHire: 3,
        opened: 2,
        bought: 1,
        closed: 1,
        paid: Money.parse('40.00'),
      ),
    );
    final writer = StateWriter();
    brief.write(writer);
    final read = Director.read(StateReader(writer.toBytes()));
    expect(samePerson(read.person, brief.person), isTrue);
    expect(read.record.paid, Money.parse('40.00'));
    expect(read.record.shopsAtHire, 3);

    // A format-39 brief stops before the person.
    final older = StateWriter()
      ..writeInt(star.index)
      ..writeInt(steady.index)
      ..writeInt(clerk.index)
      ..writeInt(Growth.open.index)
      ..writeBool(true)
      ..writeInt(start.number)
      ..writeBool(false)
      ..writeBool(false)
      ..writeInt(0)
      ..writeInt(0);
    final old = Director.read(StateReader(older.toBytes(), version: 39));
    expect(old.person, isNull);
    expect(old.record.shopsAtHire, -1);

    final command = hire().withPerson(_person(_rash));
    final out = StateWriter();
    command.write(out);
    expect(
      samePerson(
        (Command.read(StateReader(out.toBytes())) as HireDirector).person,
        _person(_rash),
      ),
      isTrue,
    );
  });

  test(
    'memos, persons and records survive a save, and play on identically',
    () {
      final simulation = Simulation.newGame(
        opening,
        seed: 1,
      )..submit(hire(growth: Growth.open, payout: true).withPerson(_person(0)));
      for (var i = 0; i < 40; i++) {
        simulation.step();
      }
      final loaded = Simulation.load(opening, simulation.save());
      expect(loaded.stateHash(), simulation.stateHash());
      expect(
        director(loaded)?.record.opened,
        director(simulation)?.record.opened,
      );
      for (var i = 0; i < 40; i++) {
        simulation.step();
        loaded.step();
      }
      expect(loaded.stateHash(), simulation.stateHash());
    },
  );
}

extension on HireDirector {
  HireDirector withPerson(DirectorPerson? person) => HireDirector(
    actor,
    company: company,
    grade: grade,
    strategy: strategy,
    managerGrade: managerGrade,
    growth: growth,
    payout: payout,
    borrows: borrows,
    nationalRate: nationalRate,
    nationalAuto: nationalAuto,
    nationalRegions: nationalRegions,
    person: person,
  );
}
