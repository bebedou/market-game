import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final content = loadScenario(testScenarioJson);

  test('owners rename their stores and companies, for everyone to see', () {
    final simulation = Simulation.newGame(
      content,
      seed: 1,
      systems: quietSystems,
    );
    final invalid = {
      RenameStore(player, store: playerStore, name: ''):
          'nameRule',
      RenameStore(player, store: playerStore, name: ' Shop'):
          'nameRule',
      RenameStore(player, store: playerStore, name: 'x' * 33):
          'nameRule',
      RenameStore(player, store: rivalStore, name: 'Mine'):
          'notYourStore',
      RenameCompany(player, company: CompanyId(1), name: 'Mine'):
          'notYourCompany',
    };
    invalid.keys.forEach(simulation.submit);
    simulation
      ..submit(RenameStore(player, store: playerStore, name: 'Chez Rayan'))
      ..submit(
        RenameCompany(player, company: playerCompany, name: 'Rayan & Co'),
      );
    final result = simulation.step();
    expect({
      for (final rejection in result.rejections)
        rejection.command: rejection.reason.key,
    }, invalid);
    final seen = simulation.observe(rival);
    expect(seen.shelves[playerStore.index].name, 'Chez Rayan');
    expect(seen.companyNames[playerCompany.index], 'Rayan & Co');

    final save = simulation.save();
    final replayed = Simulation.replay(content, save, systems: quietSystems);
    expect(replayed.stateHash(), simulation.stateHash());
    expect(
      replayed.observe(player).shelves[playerStore.index].name,
      'Chez Rayan',
    );
  });

  test('recent sales give daily visits and units sold', () {
    final simulation = Simulation.newGame(content, seed: 1);
    runScripted(simulation, 20);
    final sales = simulation
        .observe(player)
        .companies
        .single
        .stores
        .single
        .sales;
    expect(sales.dailyVisits, hasLength(sales.days));
    expect(
      sales.dailyVisits.fold(0, (a, b) => a + b),
      DaySlot.values.fold(0, (sum, slot) => sum + sales.visits(slot, 28)),
    );
    expect(
      sales.dailySold.fold(0, (a, b) => a + b),
      sales.total(SalesCount.sold, milkBudget, 28) +
          sales.total(SalesCount.sold, milkPremium, 28),
    );
    expect(sales.dailySold.any((units) => units > 0), isTrue);
  });
}
