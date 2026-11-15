# Tools and scripts

Two kinds: Dart tools in [packages/engine/tool](../packages/engine/tool),
run with `dart run` from `packages/engine`, and Python scripts in
[content/countries](../content/countries) that build the content's data from
Eurostat. Each file's header comment gives its options.

## Dart tools

| Tool | What it does | Writes |
|---|---|---|
| [sim.dart](../packages/engine/tool/sim.dart) | The headless runner: plays a scenario for many seeds with a bot in the player's seat, one isolate per run, and scores stability and profitability. Bots: a strategy name, `idle`, `<strategy>@<grade>` (a manager), `<strategy>#<grade>-<growth>` (a director, `+borrow` to let them borrow), `<strategy>+credit`, `<strategy>+cash` | `runs/<bot>/seed-<n>.csv`, `runs/companies.csv`, `runs/stores.csv` (ignored by git) |
| [profile.dart](../packages/engine/tool/profile.dart) | Times each tick system, each AI's decision and the rest | console |
| [gen_exp_table.dart](../packages/engine/tool/gen_exp_table.dart) | Regenerates the `exp(-x)` table with `dart:math` on the developer's machine; the engine only reads the committed integers | `lib/src/core/exp_table.g.dart` |
| [calibrate_countries.dart](../packages/engine/tool/calibrate_countries.dart) | Fits capture, staff that goes with being open, and price responses from controlled full-simulation runs; `--write` to save | `content/countries/calibration.json` |
| [countries_report.dart](../packages/engine/tool/countries_report.dart) | The countries by formula against reported market figures, and over the years | console |
| [countries_balance.dart](../packages/engine/tool/countries_balance.dart) | Business by country: margins played in full and by formula, closings, recessions | console |
| [national_shops.dart](../packages/engine/tool/national_shops.dart) | What a settled district shop of each kind sells and keeps, by country: the source of the formats' `national` figures | console |
| [national_balance.dart](../packages/engine/tool/national_balance.dart) | A rich player's director growing a chain by formula, year by year (`--rate auto` or a share, `--grade`, `--strategy`) | console |
| [factories_balance.dart](../packages/engine/tool/factories_balance.dart) | A chain with and without its own plant | console |
| [generate_neighbourhoods.dart](../packages/engine/tool/generate_neighbourhoods.dart) | Rebuilds today's cities from their figures, to compare with the hand-made ones | a scenario JSON |
| [add_places.dart](../packages/engine/tool/add_places.dart) | Lays out the districts from `places.json` with the generator | `content/countries/places_built.json` |

Typical runs:

```bash
dart run tool/sim.dart --scenario prototype --seeds 1-20 --days 1825 --player idle,discount,balanced,premium,discount@expert --out runs
```

```bash
dart run tool/profile.dart prototype 2000
```

The runner is tested by [test/tool/sim_test.dart](../packages/engine/test/tool/sim_test.dart),
which imports `tool/sim.dart` directly (`runJob`, `Job`).

Balancing results from these tools are recorded under *Testing and the
headless runner* in [Engine Architecture.md](<../Engine Architecture.md>),
pass by pass.

## Python build scripts

All fetch Eurostat's public API (or GISCO for outlines) and write JSON next
to themselves. Run from `content/countries`.

| Script | Reads | Writes |
|---|---|---|
| [build_euro.py](../content/countries/build_euro.py) | Eurostat: households, incomes, spending per class and trade, business statistics; chains written by hand in the script | `euro.json` |
| [build_regions.py](../content/countries/build_regions.py) | Eurostat `demo_r_pjanaggr3` and `nama_10r_2hhinc` (2022) | adds regions and chains' home regions to `euro.json`; run after `build_euro.py` |
| [build_places.py](../content/countries/build_places.py) | Eurostat; district figures written by hand | `places.json`: countries' taxes, cycles, suppliers, names, districts |
| [insert_places.py](../content/countries/insert_places.py) | `places_built.json` | appends to `prototype.json`, keeping saved games valid; stops if the scenario already has countries |
| [add_clothing.py](../content/countries/add_clothing.py) | `euro.json` (clothing against electronics per household) | appends clothing to `prototype.json` and its translations: categories with their fashion, goods, habits, the format (edition 1) with its national figures, strategies, suppliers, each place's clothing market, two rival shops a city; stops if clothing is there |
| [build_outlines.py](../content/countries/build_outlines.py) | GISCO NUTS 2021 1:20M GeoJSON | `outlines.json` |

## The data pipelines

```
Eurostat ─► build_euro.py ─► euro.json ◄─ build_regions.py
                                  │
                                  ├─► (app bundles it) ─► loadCountryTable
                                  └─► calibrate_countries.dart ─► calibration.json

Eurostat ─► build_places.py ─► places.json
            ─► dart run tool/add_places.dart ─► places_built.json
            ─► insert_places.py ─► prototype.json (appended at the end of each list)

GISCO ─► build_outlines.py ─► outlines.json ─► (app) loadOutlines ─► ink maps
```

When `euro.json` changes shape (countries, regions, trades, chains), saved
games' national state no longer matches it: see
[tech-debt.md](tech-debt.md). When outlines change, check that every region
key in `euro.json` still has an outline.

## Previewing the web build

[.claude/launch.json](../.claude/launch.json) defines `app-web`, a Python
static server on port 8642 over `app/build/web`. Build first with `flutter
build web` in `app`. Web saves stay in memory.
