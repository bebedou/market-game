@TestOn('vm')
library;

import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/state/invariants.dart';
import 'package:test/test.dart';

void main() {
  final content = loadScenario(
    File('../../content/scenarios/prototype.json').readAsStringSync(),
  );
  SiteId site(String key) => content.sites.firstWhere((s) => s.key == key).id;
  FormatId format(String key) =>
      content.formats.firstWhere((f) => f.key == key).id;
  ProductId product(String key) =>
      content.products.firstWhere((p) => p.key == key).id;
  final player = content.player;

  test("the player may start on any site the scenario's other stores leave "
      'free, their own first one included', () {
    final sites = startingSites(content);
    expect(sites, contains(site('corner')));
    expect(sites, contains(site('backstreet')));
    expect(sites, isNot(contains(site('prime'))));
    expect(sites.length, 28);
  });

  test("the classic start's terms are the scenario's", () {
    final (terms, problem) = startTerms(
      content,
      GameStart(
        site: site('corner'),
        format: format('grocery'),
        name: 'Corner Shop',
      ),
    );
    expect(problem, isNull);
    expect(terms, (
      fitOut: Money.parse('30000.00'),
      companyCash: Money.parse('15000.00'),
      personalCash: Money.parse('20000.00'),
      capital: Money.zero,
    ));
  });

  test('a cheaper store leaves the company the difference, a dearer one '
      "takes the player's own cash, and one beyond both is refused", () {
    StartTerms? terms(String siteKey, String formatKey) => startTerms(
      content,
      GameStart(site: site(siteKey), format: format(formatKey), name: 'Mine'),
    ).$1;
    // Rue du Mail costs 20,000 to fit out, 10,000 less than the corner.
    expect(
      terms('backstreet', 'grocery')!.companyCash,
      Money.parse('25000.00'),
    );
    // Fine dining at the Arceaux: 18,000 × 2.8 = 50,400. The company keeps
    // 10,000 and the player puts in 15,400 of their 20,000.
    expect(terms('mtp_arceaux', 'finedining'), (
      fitOut: Money.parse('50400.00'),
      companyCash: minStartingCash,
      personalCash: Money.parse('4600.00'),
      capital: Money.parse('15400.00'),
    ));
    String? problem(String siteKey, String formatKey, [String name = 'Mine']) =>
        startTerms(
          content,
          GameStart(site: site(siteKey), format: format(formatKey), name: name),
        ).$2?.key;
    expect(problem('par_clichy', 'grocery'), 'fitOutTooDear');
    expect(problem('prime', 'grocery'), 'siteTaken');
    expect(
      problem('backstreet', 'supermarket'),
      'siteTooSmall',
    );
    expect(problem('backstreet', 'grocery', ' Mine'), 'nameRule');
  });

  test('a chosen start opens there with the format’s usual prices and staff, '
      'and saves, loads and replays the same', () {
    final start = GameStart(
      site: site('mtp_arceaux'),
      format: format('fastfood'),
      name: 'Burger Lab',
    );
    final simulation = Simulation.newGame(content, seed: 7, start: start);
    final view = simulation.observe(player);
    final company = view.companies.single;
    expect(view.companyNames[company.id.index], 'Burger Lab');
    // 18,000 × 1.6 = 28,800 to fit out, 1,200 less than the corner.
    expect(company.cash, Money.parse('16200.00'));
    expect(view.cash, Money.parse('20000.00'));
    final store = company.stores.single;
    expect(store.site, site('mtp_arceaux'));
    expect(store.format, format('fastfood'));
    expect(view.shelves[store.id.index].name, 'Burger Lab');
    // Croc Burger's prices in Lyon, at Montpellier's 0.95.
    expect(store.prices[product('fastfood_budget').index], Money.parse('8.46'));
    expect(
      store.prices[product('fastfood_premium').index],
      Money.parse('13.21'),
    );
    expect(store.prices[product('milk_budget').index], isNull);
    expect(store.staff, [0, 2, 2, 1]);
    expect(view.vacantSites, contains(site('corner')));
    expect(invariantViolations(simulation.world), isEmpty);

    for (var i = 0; i < 20; i++) {
      simulation.step();
    }
    final file = simulation.save();
    expect(
      Simulation.load(content, file).world.start.toString(),
      start.toString(),
    );
    final replayed = Simulation.replay(content, file);
    expect(replayed.stateHash(), simulation.stateHash());
  });

  test('a start that is refused never makes a world', () {
    expect(
      () => Simulation.newGame(
        content,
        seed: 1,
        start: GameStart(
          site: site('prime'),
          format: format('grocery'),
          name: 'X',
        ),
      ),
      throwsArgumentError,
    );
  });
}
