# Testing

Two suites: the engine's (`dart test`) and the app's (`flutter test`), plus
a screenshot tour on a real device. The table *Testing and the headless
runner* in [Engine Architecture.md](<../Engine Architecture.md>) lists what
each area's tests check.

## Engine tests

In [packages/engine/test](../packages/engine/test): 51 files, about 400
tests. Run from `packages/engine`:

```bash
dart test
```

[dart_test.yaml](../packages/engine/dart_test.yaml) sets `platforms: [vm,
node]`, so by default every test runs twice: on the Dart VM (as on Android)
and compiled to JavaScript under Node (as on the web). The two must agree.
To run one platform or one file:

```bash
dart test -p vm test/simulation_test.dart
```

**VM-only tests.** Anything that reads files with `dart:io` is marked
`@TestOn('vm')` or `testOn: 'vm'`: the prototype scenario, the national
table, every test under [test/countries](../packages/engine/test/countries)
and [test/neighbourhoods](../packages/engine/test/neighbourhoods), brands,
markets, the save fixture, the forbidden-API scan, and the runner. So the
Node run covers the core and the small test scenario only.

**Fixtures and helpers.**

- [test/support/fixtures.dart](../packages/engine/test/support/fixtures.dart):
  `testScenarioJson` (a two-store town), ids such as `player`, `rival`,
  `playerStore`, `milkBudget`, `ScriptedDemandSystem`, `quietSystems`,
  `testSystems`, `scriptedCommands`, `runScripted`.
- [test/fixtures/save_v6.bin](../packages/engine/test/fixtures/save_v6.bin):
  a format-6 save on the test scenario.
- `save_v31.bin.gz` and `save_v32.bin.gz` in the same folder: 150 days of the
  prototype (seed 11, other cities asleep, three grocers across France, a
  drinks plant, and in 32 a lab with one person), each written by the commit
  before the next format; and `save_v33_woken.bin.gz`, 120 days with a
  district and a city woken before clothing (seed 12); and
  `save_v42_holding.bin.gz`, a holding start on the test town written by
  151811b, from before format 43 added mergers, a start's cash and the
  holding's own name; and `save_v42_between.bin.gz`, the same in format
  43's layout under the number 42, as the builds after 151811b wrote it
  until 781c14b (`SaveData.decode` reads a format-42 save that fails as
  the first as the second).
  [old_saves_test.dart](../packages/engine/test/old_saves_test.dart)
  loads them, plays on and round-trips them. Formats in between are tested
  field by field, by writing a snippet and reading it with
  `StateReader(bytes, version: N)` (in `borrowing_test`, `cushion_test`,
  `director_test`).

**Determinism checks.**

- [core/cross_platform_golden_test.dart](../packages/engine/test/core/cross_platform_golden_test.dart):
  every core primitive over many inputs, hashed to a committed digest that
  must match on VM and Node.
- [simulation_test.dart](../packages/engine/test/simulation_test.dart):
  same seed gives the same hash, save/load continuity, replay, corrupt
  saves refused, and a scripted year's committed `stateHash`
  (`0x370e5ef2`). If a rule change moves it on purpose, update it in the
  same commit and say why.
- [forbidden_api_test.dart](../packages/engine/test/forbidden_api_test.dart):
  the source scan for non-deterministic APIs.

**Invariants** run after every step in debug builds, which tests are, so any
test that steps a game also checks the ledger, cash and stock.

Test files by area: [core/](../packages/engine/test/core),
[content/](../packages/engine/test/content),
[persistence/](../packages/engine/test/persistence),
[state/](../packages/engine/test/state),
[countries/](../packages/engine/test/countries),
[neighbourhoods/](../packages/engine/test/neighbourhoods),
[tool/sim_test.dart](../packages/engine/test/tool/sim_test.dart), and one
file per feature at the top level (`acquisitions_test`, `borrowing_test`,
`director_test`, `director_persons_test`, `factories_test`, `growth_test`, `manager_test`,
`software_test`, `factory_sales_test`, …). `factory_sales_test` plays the
prototype with the national figures: sizes, enlarging, tenders opening,
bids won and lost, a shortfall's penalty, independents, rivals' capacity
and development, chains' own plants, breaking, answering and repricing
contracts, indexation, and a save.
`stocks_test` plays the prototype with the national figures and the
stock market: the table and its errors, a company added later, opening at
the table's caps, buying with its fee and impact, refusals, a stake made
public at each 5% either way, a gain taxed
after a carried loss, an index, dividends, a chain bought whole leaving its
exchange, a recession's gloom, ratings and managements, saves, replays and
an older save gaining the market.
`takeovers_test` plays the prototype with a rich player: a bid that wins
control, one that loses, a chain joining a company, levers and a director,
a merger, a sale to a raider, the holding's loan, listing a company, being
taken over, and a save.
`software_test` runs the software market on the test
town with a million customers and round figures: a team's pace, launching,
customers conserved, rounds, investors' dividends, a sale and a save.

## App tests

In [app/test](../app/test). Run from `app`:

```bash
flutter test
```

- [flutter_test_config.dart](../app/test/flutter_test_config.dart) runs
  before every test file: English words from the content folder and the
  outlines.
- [support.dart](../app/test/support.dart): `prototype` and
  `nationalPrototype` content, lookups by key (`grade`, `strategy`,
  `product`, `supplier`, `format`), `newController`, `usePhone`, `pumpMenu`,
  `pumpGame`, `openIndex`, `goBack`, `scrollTo`.
- [controller_test.dart](../app/test/controller_test.dart): net worth,
  pending changes, news and pausing, the clock, saves, starts.
- [screens_test.dart](../app/test/screens_test.dart): 57 widget tests on a
  phone-sized screen, from the menu to the ink map.
- [factory_test.dart](../app/test/factory_test.dart): the factory pages.
- [sales_desk_test.dart](../app/test/sales_desk_test.dart): a factory's
  size and enlarging, its sales desk, a bid and a contract's page.
- [languages_test.dart](../app/test/languages_test.dart) also walks the
  Market tab in each language: the exchanges, the portfolio, every sector,
  a bank's page and an order; and the takeover pages: a company the
  holding took over, its levers, a rival's bid, and Finance's listing.
- [software_test.dart](../app/test/software_test.dart): the software pages,
  net worth on paper, and money shortened to millions and billions.
- [saves_test.dart](../app/test/saves_test.dart): file slots.
- [l10n_test.dart](../app/test/l10n_test.dart): every language has
  English's keys, placeholders and list shapes; every key the code asks for
  exists; every refusal the engine can make has words; nothing is still
  written out in the screens; each `tr` call gives what its text needs;
  scenario words name only what the scenario has.
- [languages_test.dart](../app/test/languages_test.dart): walks the screens
  in each language on a narrow phone, so a word too long for its row, a
  bare key or an unfilled placeholder fails.

## The device tour

[integration_test/tour_test.dart](../app/integration_test/tour_test.dart)
with [test_driver/integration_test.dart](../app/test_driver/integration_test.dart)
takes screenshots of every screen on a real phone, after two months played
by the balanced AI. Run from `app` with a device attached:

```bash
flutter drive --profile -d <device> --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/tour_test.dart
```

Without `--keep-app-running`, `flutter drive` uninstalls the app and the
phone's saves with it. Screenshots go to `$UX_OUT` or `screenshots/`.

## When to run what

- Touched `core/` or anything with arithmetic: the full `dart test` (both
  platforms).
- Touched a tick system, a policy or a command: `dart test`, then a short
  `tool/sim.dart` run to see the economy still behaves
  ([tools-and-scripts.md](tools-and-scripts.md)).
- Touched the national formula or the calibration: `test/countries`, and
  `tool/calibrate_countries.dart` if the test says the formula and the full
  simulation drifted apart.
- Touched words or screens: `flutter test` (the l10n and languages tests
  catch most mistakes).
