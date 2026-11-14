# Overview and repo map

Market Game is a business simulation for phones. The player runs shops, then
chains, factories and companies across four euro countries, against AI owners
who play by the same rules. Money is the score
([Game Design.md](<../Game Design.md>)).

The code is a pure Dart engine with a Flutter app on top. The engine is
deterministic: integer maths only, so the same seed and commands give the
same bytes on the Dart VM (Android) and in JavaScript (web), and saves replay
exactly.

## The three packages

One Dart pub workspace, declared in the root [pubspec.yaml](../pubspec.yaml),
with one shared lockfile ([pubspec.lock](../pubspec.lock)). Dart 3.8 or later.

| Package | Folder | What it is |
|---|---|---|
| `engine` | [packages/engine](../packages/engine) | The simulation. No Flutter imports. Public API in [engine.dart](../packages/engine/lib/engine.dart); two side libraries for tools: [countries.dart](../packages/engine/lib/countries.dart) and [neighbourhoods.dart](../packages/engine/lib/neighbourhoods.dart) |
| `market_game` | [app](../app) | The Flutter app, Android first, web for development |
| `market_content` | [content](../content) | Scenario JSON, interface words, country data. Declares them as Flutter assets in [content/pubspec.yaml](../content/pubspec.yaml), so the root JSON stays the only copy |

Because the engine and app share a lockfile, the engine's test dependencies
must be versions Flutter's pinned `test_api` accepts.

## Repo map

```
Engine Architecture.md   design detail and balancing history (long; read the section you need)
Game Design.md           what the game is for
packages/engine/
  lib/engine.dart        public API (exports)
  lib/src/core/          Money, Fx, Day, ids, rng, hashing, exp table
  lib/src/content/       ContentDb and the scenario loader
  lib/src/state/         WorldState and every entity
  lib/src/commands/      Command types, applyCommand, Refusal, transfers
  lib/src/systems/       one TickSystem per daily phase
  lib/src/policies/      AI owners, entrepreneurs, managers, directors, the cash cushion
  lib/src/observation/   what an actor may see; outlooks; national views
  lib/src/accounting/    the double-entry ledger
  lib/src/reports/       attribution and week/month reports
  lib/src/persistence/   StateWriter/StateReader and the save file
  lib/src/countries/     the national table and the countries by formula
  lib/src/neighbourhoods/ the generator: rows of figures to cities
  test/                  engine tests (VM and Node)
  tool/                  headless runner, balance and calibration tools
app/
  lib/src/controller.dart SimulationController: clock, pending changes, news, saves
  lib/src/screens/       one file per tab or page
  test/                  widget and controller tests, l10n checks
  integration_test/      a screenshot tour on a real device
content/
  scenarios/             prototype.json and its words per language
  locales/               interface words per language
  countries/             euro.json, calibration.json, outlines.json and the Python that builds them
```

## Rules that hold everywhere

These come from *Architecture at a glance* in
[Engine Architecture.md](<../Engine Architecture.md>):

1. Only commands and tick systems change the world.
2. Nothing outside the engine reads `WorldState`; the UI and AI see an
   `Observation`. (The app breaks this in three places: see
   [tech-debt.md](tech-debt.md).)
3. Definitions (`ContentDb`, immutable) are separate from state (`WorldState`).
4. The player and AI actors issue the same commands under the same rules.
5. The engine has no words. Refusals are keys; the app words them.
6. Whatever could differ in someone else's world is data, not code.

## How data flows

```
player taps ──► SimulationController.submit (pending, shown as "takes effect tomorrow")
                    │ step()
                    ▼
Simulation.step: policies decide from observations ─► managers and directors
                 ─► applyCommand for each command, by actor ─► tick systems in order
                    │
                    ▼
TickResult (journal entries, events, attribution, rejections)
                    │
SimulationController: new Observation, news (_news), autosave on the 1st
                    │
                    ▼
widgets read controller.view, controller.reports(...)
```

## Running things

Shell commands in this repo are prefixed with `rtk` on the owner's machine
(see the owner's global instructions).

From `packages/engine`:

```bash
dart test
```

```bash
dart run tool/sim.dart --scenario prototype --seeds 1-20 --days 1825 --player idle,balanced --out runs
```

From `app`:

```bash
flutter test
```

```bash
flutter build web
```

`.claude/launch.json` serves `app/build/web` on port 8642 for the in-app
browser preview.

House rules for sessions: run `dart format` only on files you changed,
commit only when asked, and pushes go as `bebedou` through the local git
config.
