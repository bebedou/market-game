import 'package:engine/engine.dart';
import 'package:engine/src/accounting/ledger.dart' show Accounts;
import 'package:engine/src/core/rng.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:engine/src/policies/manager.dart';
import 'package:engine/src/state/entities.dart' show Company;
import 'package:test/test.dart';

import 'support/fixtures.dart';

const clerk = ManagerGradeId(0);
const ordering = [true, false, false, false, false];

void main() {
  // Staff earn 1.00 a slot, and the corner's rent is 100.00 a month.
  final content = loadScenario(
    testScenarioJson
        .replaceFirst('"slotWage": "0.00"', '"slotWage": "1.00"')
        .replaceFirst(
          '"location": "0.50", "rent": "0.00"',
          '"location": "0.50", "rent": "100.00"',
        ),
  );

  test('holds days of wages and salaries, a month of rent and the next '
      'loan payments', () {
    final simulation =
        Simulation.newGame(content, seed: 1, systems: quietSystems)
          ..submit(
            HireManager(
              player,
              store: playerStore,
              grade: clerk,
              strategy: steady,
              duties: ordering,
            ),
          )
          ..step();
    final view = simulation.observe(player);
    final company = view.companies.single;
    expect(company.cushionDays, defaultCushionDays);
    // Four staffed slots at 1.00 and the clerk's 5.00 for 14 days, and the
    // rent.
    expect(cashCushion(view, content, company), Money.parse('226.00'));
    // A twelfth of the principal and a month's interest at 12%.
    expect(
      nextInstallment((
        number: 1,
        outstanding: Money.parse('1200.00'),
        rate: Fx.parse('0.12'),
        installmentsLeft: 12,
        guaranteed: false,
      )),
      Money.parse('112.00'),
    );
  });

  test('is set by the owner and kept in saves', () {
    final simulation = Simulation.newGame(content, seed: 1);
    final invalid = {
      SetCushion(player, company: playerCompany, days: -1):
          'cushionRange',
      SetCushion(player, company: playerCompany, days: 91):
          'cushionRange',
      SetCushion(rival, company: playerCompany, days: 7):
          'notYourCompany',
    };
    invalid.keys.forEach(simulation.submit);
    simulation.submit(SetCushion(player, company: playerCompany, days: 28));
    final result = simulation.step();
    expect({
      for (final rejection in result.rejections)
        rejection.command: rejection.reason.key,
    }, invalid);
    expect(simulation.observe(player).companies.single.cushionDays, 28);

    final save = simulation.save();
    expect(
      Simulation.load(content, save).observe(player).companies.single,
      isA<CompanyView>().having((c) => c.cushionDays, 'cushionDays', 28),
    );
    expect(
      Simulation.replay(content, save).stateHash(),
      simulation.stateHash(),
    );
  });

  test('is two weeks in saves from before it', () {
    final writer = StateWriter();
    Company(
      id: playerCompany,
      name: 'Old',
      owner: player,
      accounts: Accounts(),
      founded: content.startDay,
      cushionDays: 28,
    ).write(writer);
    final read = Company.read(
      playerCompany,
      StateReader(writer.toBytes(), version: 13),
    );
    expect(read.cushionDays, defaultCushionDays);
  });

  test('buys full orders beyond it and only the best sellers\' next few '
      'days within it', () {
    int ordered(int days) {
      final simulation =
          Simulation.newGame(content, seed: 1, systems: quietSystems)
            ..submit(SetCushion(player, company: playerCompany, days: days))
            ..submit(
              HireManager(
                player,
                store: playerStore,
                grade: const ManagerGradeId(1),
                strategy: steady,
                duties: ordering,
              ),
            )
            ..step();
      final view = simulation.observe(player);
      var units = 0;
      for (final command in manage(
        view,
        content,
        (entity) => Rng.keyed(1, RngStream.manager, 0, entity),
      )) {
        if (command is PlaceOrder) {
          for (final line in command.lines) {
            units += line.quantity;
          }
        }
      }
      return units;
    }

    // With no days of wages kept, the 500.00 in hand covers the rent and
    // full orders; 90 days of wages are more than the company has.
    final full = ordered(0);
    final lean = ordered(maxCushionDays);
    expect(lean, greaterThan(0), reason: 'the store keeps selling');
    expect(lean, lessThan(full));
  });
}
