# Content and scenarios

Content is everything a scenario defines and a game never changes: places,
products, formats, segments, suppliers, strategies, grades, tuning, the
opening world, and the countries' statistics. The aim is moddability:
whatever could differ in someone else's world is data. Design detail:
*Content and scenarios* and *Neighbourhoods from figures* in
[Engine Architecture.md](<../Engine Architecture.md>).

## The files

| File | What it holds | Read by |
|---|---|---|
| [content/scenarios/prototype.json](../content/scenarios/prototype.json) | The scenario: start date, 4 countries, 13 markets, 126 sites, 12 categories, 6 formats, 24 products, 6 segments, 16 suppliers, 7 strategies, 77 persons, 73 companies and stores, 30 neighbourhood rows, and every tuning block (`finance`, `taxes`, `macro`, `demand`, `managers`, `directors`, `factories`, …) | `loadScenario` |
| [prototype.fr.json](../content/scenarios/prototype.fr.json), [prototype.es.json](../content/scenarios/prototype.es.json), [prototype.en.json](../content/scenarios/prototype.en.json) | The scenario's names and wordings per language, by id | `localizedScenario` in the app |
| [content/countries/euro.json](../content/countries/euro.json) | The national table: countries, regions, income classes, trades, chains, regimes, brand and regional tuning | `loadCountryTable` |
| [content/countries/calibration.json](../content/countries/calibration.json) | Numbers the formula borrows from the full simulation: `capture`, `staffFixed`, `riseResponse`, `cutResponse` | `loadCountryTable` |
| [content/countries/outlines.json](../content/countries/outlines.json) | Region outlines for the ink maps | the app only (`loadOutlines`) |
| [content/stocks/companies.json](../content/stocks/companies.json) | The stock market: its rules, the four exchanges, 23 sectors (each formula sector's output by country, from Eurostat), and 822 listed companies with their ticker, name, country, sector, share, cap, shares, margin, debt, growth, payout and management, or the game's own chain, software rival or producer they are. Edit freely; a mod can ship its own | `loadScenario(stocks:)`, giving `ContentDb.stocks` (`StocksDef`) |
| [content/countries/places.json](../content/countries/places.json), [places_built.json](../content/countries/places_built.json) | Intermediate files of the places pipeline, not bundled | the build scripts ([tools-and-scripts.md](tools-and-scripts.md)) |
| [content/locales/](../content/locales) | Interface words; see [app.md](app.md) | the app |

## Loading: `loadScenario`

[content/scenario_loader.dart](../packages/engine/lib/src/content/scenario_loader.dart),
`loadScenario(jsonText, national:, stocks:)`, returns a `ContentDb` or throws a
`ContentException` with the JSON path at fault.

- Strict: a `JsonNode` ([json_node.dart](../packages/engine/lib/src/content/json_node.dart))
  wraps each object, every read is checked, and `finish()` fails on any
  field left unread, so typos are caught. The national table and its
  calibration are read with it too.
- Decimals are JSON strings (`"0.15"`) parsed straight to `Fx` or `Money`.
  JSON numbers with a fraction are refused, since they would be doubles.
- String ids become dense integer ids in file order (`_Keys`). An id is a
  position in its list.
- Countries are read first, since places and suppliers name theirs.
- Places are sized from what households spend (`placeSize` in
  [household_demand.dart](../packages/engine/lib/src/content/household_demand.dart)):
  a market's yearly spending per trade and its mix of segments become
  households and a scale per channel.

## `ContentDb`

[content/content_db.dart](../packages/engine/lib/src/content/content_db.dart),
class `ContentDb`, plus every definition type (`MarketDef`, `SiteDef`,
`FormatDef`, `ProductDef`, `SegmentDef`, `StrategyDef`, `CountryDef`,
`NeighbourhoodRow`, `DirectorsDef`, `FactoryKindDef`, …). Useful members:

- `player`: the person marked as the player.
- `countryOf(market)`, `taxesOf(country)`, `residenceOf(person)`.
- `costLevels` and `references`: what wholesalers charge per country and
  what households there think each product should cost (late, computed
  once).
- `structure`: every mirrored list's keys in order, written into saves.
- `source`: the JSON text the content came from, used to grow it.
- `national`: the `CountryTable`, or null.

`ContentDb` never changes. A grown game (a woken neighbourhood, a scenario
update) gets a new `ContentDb`, and `Simulation` swaps its `_content`.
Products found later through research go in `WorldState`, not here.

## Ids are list positions: what may change under a saved game

Because ids are positions, a save depends on the order of the scenario's
lists. `ListGrowth` in `content_db.dart` says how each list may change:

- `append` (every list but two): entries may only be added at the end. On
  load, `growWorld` adds them to the world. Removing, renaming or moving an
  entry makes old saves refuse to load.
- `free` (`companies`, `stores`): only a new game reads them.

Numbers may change freely; that is how balance tweaks keep saves. The
mirrored lists are markets, sites, categories, formats, products, segments,
regimes, research grades, manager and director grades, suppliers,
strategies, persons, companies, stores, countries and factory kinds.
Neighbourhood rows and the national table are not in this list (see
[tech-debt.md](tech-debt.md)).

[content/countries/insert_places.py](../content/countries/insert_places.py)
and [add_clothing.py](../content/countries/add_clothing.py) follow this
rule: they append new entries at the end of each list.

Entries the scenario appends land before those of districts a save woke
since. On load, if a save's lists don't line up, `_inSavedOrder` in
[save_file.dart](../packages/engine/lib/src/persistence/save_file.dart)
puts the entries it knew first, in its order, and the new ones after.

## Editions: a trade added to places already described

A format's `edition` (0 by default; clothing is 1) marks a trade added
after places were described. Its market figure doesn't count in how many
households a place has (`placeSize`), so every place keeps its households
and every district the sites and shops they make: the figure only scales
what households buy of it. Each woken district keeps the edition it woke in
(`WokenNeighbourhood.edition`, saved from format 34), and is rebuilt
without the sites and shops of later editions, so saves with districts
woken before stay valid. The generator adds a later edition's sites last.
`ContentDb.edition` is the latest.

## The scenario's words

The engine has no languages. The app swaps names in before loading:
`localizedScenario(json, words)` in [app/lib/src/l10n.dart](../app/lib/src/l10n.dart)
walks `prototype.<lang>.json`, which mirrors the scenario by id, and replaces
each `name` (and extra forms such as `a`: "une supérette"). Store and company
names are saved with the game, so a game keeps the names it began with.
Rivals' brand names stay the same in every language.

## Neighbourhoods and cities asleep

A neighbourhood row (`NeighbourhoodRow` in `content_db.dart`) is a district
described by figures: households and growth by segment, spending scale per
channel, price, wage and income levels, rents, shop sizes. Rows run by
formula until the player trades there.

The generator is [neighbourhoods/neighbourhood_generator.dart](../packages/engine/lib/src/neighbourhoods/neighbourhood_generator.dart):

| Symbol | What it does |
|---|---|
| `generateScenario(json, rows, seed:)` | Replaces a scenario's cities with generated ones (for `tool/generate_neighbourhoods.dart`) |
| `rowsFromScenario(content)` | Reads today's cities as rows |
| `withCitiesAsleep(content, start:)` | Turns every city but the player's into a row whose `layout` keeps its sites and stores; returns the new content and start. Used by every new game in the app |
| `newSleeper(content, row, seed:)` | The `SleepingNeighbourhood` a row starts as |
| `withNeighbourhoods(content, woken, seed:, onChain:)` | Generates woken rows and appends their markets, sites, persons, companies and stores to the content's lists |
| `WokenNeighbourhood` | Row, day, price index, households and shops at the moment it woke; saved in the header |

`SleeperSystem` ([systems/sleepers.dart](../packages/engine/lib/src/systems/sleepers.dart))
runs the rows each month: households, spending shared among shops, closings,
enlargements, newcomers. Chains' shops in districts book into their
companies' accounts against `world.elsewhere`.

Waking (`WakeNeighbourhood`, applied at once by `Simulation._wake`):
generate the row as it stands, append it to the content, `growWorld`, remove
the sleeper, set reputations by shop age, and turn chains' shops into stores
of their companies. The app wakes a city when the player opens a business
there (`SimulationController.wake`).

`Simulation.plan` is the content with every sleeper generated as it stands,
rebuilt once a month, so screens can show sites and shops of districts still
asleep. It is never played.

## The holding start

`GameStart.holding(name)` ([state/game_start.dart](../packages/engine/lib/src/state/game_start.dart))
gives the player money and no business. The scenario's company for the
player stays in the world as `CompanyStatus.dormant`, since content and world
must have the same companies; observations hide it. The first business is
opened from the dashboard (`NewBusiness` in
[app/lib/src/screens/world.dart](../app/lib/src/screens/world.dart)), and
opening on a site asleep wakes its city first.

## The national table

[countries/country_table.dart](../packages/engine/lib/src/countries/country_table.dart):
`loadCountryTable(tableJson, calibrationJson)` returns a `CountryTable`
(`NationalCountry`, `NationalRegion`, `ChainDef`, `RegionalTuning`,
`BrandTuning`). A scenario country links to it through its `national` key.
Tests and tools may load a scenario without it; the app always passes it.
See [national-economy.md](national-economy.md).
