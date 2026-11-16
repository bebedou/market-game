# State and saves

Everything that changes during a game is in `WorldState`; everything that
doesn't is in `ContentDb` ([content-and-scenarios.md](content-and-scenarios.md)).
Design detail: *World state* and *Persistence* in
[Engine Architecture.md](<../Engine Architecture.md>).

## `WorldState`

[state/world_state.dart](../packages/engine/lib/src/state/world_state.dart),
class `WorldState`. Made by `WorldState.initial(content, seed:, start:)` or
`WorldState.read(reader)`.

It has two parts, and the split matters for saves and the state hash:

- **The core**, written by `world.write` and read by `WorldState.read`:
  seed, today, the player, money supply, the first country's `macro`,
  persons, companies, stores, suppliers, households, bank, landlords,
  services, cohorts, orders, loans, research reports, period reports,
  markets, government, filings, economic history, the `GameStart`, brands,
  `elsewhere`, factories, key people.
- **Kept beside the world**, each written separately and only when present:
  - `sleepers` (neighbourhoods run by formula), from format 24;
  - `otherEconomies`, `cycle`, `districtYears`, `countryLosses`,
    `regimeLog`, via `writeEconomies` / `readEconomies`, from format 27;
  - `national` and `nationalPosted`, via `writeNational` / `readNational` in
    [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart),
    from format 29;
  - `stocks` (the stock market), via `writeStocks` / `readStocks` in the
    same file, from format 38.

Helpers on the world: `macroOf(country)`, `macroAt(content, market)`,
`historyOf`, `economies`, `residence(content, person)`, `growEconomies`,
`addStore`, `parties` (every ledger party).

Ids are positions in these lists, and nothing is ever removed: a liquidated
company or closed store stays with its status.

## The entities

All in [state/](../packages/engine/lib/src/state):

| File | Types | Notes |
|---|---|---|
| [entities.dart](../packages/engine/lib/src/state/entities.dart) | `Person`, `Company`, `CompanyStatus`, `Supplier`, `Households`, `Bank`, `Services`, `Landlords`, `Government`, `Elsewhere` | `CompanyStatus` is append-only: `active`, `liquidated`, `dormant` (a holding start's unused scenario company) |
| [store.dart](../packages/engine/lib/src/state/store.dart) | `Store`, `Stock`, `Lot`, `Works`, `Manager`, `ManagerDuty`, `StoreStatus` | Stock is FIFO lots with expiry |
| [cohort.dart](../packages/engine/lib/src/state/cohort.dart) | `HouseholdCohort` | A cohort stands for `weight` identical households |
| [orders.dart](../packages/engine/lib/src/state/orders.dart) | `PurchaseOrder`, `OrderLine`, `Payable`, `Loan` | Bills of every kind are `Payable`s |
| [macro.dart](../packages/engine/lib/src/state/macro.dart) | `MacroState`, `Economy`, `SharedCycle` | One `MacroState` per country |
| [market.dart](../packages/engine/lib/src/state/market.dart) | `MarketState`, `Census` | |
| [director.dart](../packages/engine/lib/src/state/director.dart) | `Director`, `Growth`, the sealed `Memo` family | A director's brief and the memos the letters are written from |
| [factory.dart](../packages/engine/lib/src/state/factory.dart), [factories.dart](../packages/engine/lib/src/state/factories.dart) | `Factory`, `FactoryStatus`; `factoryFor`, `marketQuote`, `factoryPrice` | See [national-economy.md](national-economy.md) |
| [labs.dart](../packages/engine/lib/src/state/labs.dart), [talent.dart](../packages/engine/lib/src/state/talent.dart) | `KeyPerson`, `KeyRole`, `KeyStatus`; `labPower`, `generationWork`, `generationGain`, `keySalary`, `labYearCost` | See [national-economy.md](national-economy.md) |
| [brands.dart](../packages/engine/lib/src/state/brands.dart) | `Brand`, `BrandView`; `brandStore`, `aiBrand`, `takeOverName` | |
| [sleepers.dart](../packages/engine/lib/src/state/sleepers.dart), [districts.dart](../packages/engine/lib/src/state/districts.dart) | `SleepingNeighbourhood`, `SleepingShop`, `DistrictView` | Neighbourhoods asleep |
| [game_start.dart](../packages/engine/lib/src/state/game_start.dart) | `GameStart`, `StartTerms`, `startTerms`, `startingSites` | `GameStart.holding(name)` writes site and format as −1 |
| [credit.dart](../packages/engine/lib/src/state/credit.dart) | `companyEarnings`, `earningsRoom`, `guaranteeRoom`, `lendingRate`, `splitLoan` | What the bank lends |
| [valuation.dart](../packages/engine/lib/src/state/valuation.dart) | `valueStore`, `storeEarnings`, `companyPrice`, `bestBuyer`, `valueFactory` | Asking prices |
| [taxation.dart](../packages/engine/lib/src/state/taxation.dart) | `companyTaxes`, `DistrictYear`, `CountryLoss` | Splitting a year's tax by country |
| [buying_terms.dart](../packages/engine/lib/src/state/buying_terms.dart) | `buyingDiscount`, `goodsBoughtInYear` | |
| [national_value.dart](../packages/engine/lib/src/state/national_value.dart) | `NationalValue` | Prices of chains and blocks |
| [history.dart](../packages/engine/lib/src/state/history.dart), [public_record.dart](../packages/engine/lib/src/state/public_record.dart), [research.dart](../packages/engine/lib/src/state/research.dart) | `SalesHistory`, `Filing`, `EconomicMonth`, `ResearchReport` | |
| [growth.dart](../packages/engine/lib/src/state/growth.dart) | `growWorld`, `growthProblem` | Bringing a world up to grown content |
| [invariants.dart](../packages/engine/lib/src/state/invariants.dart) | `invariantViolations` | Checked after every step in debug builds |

## The canonical encoding

[persistence/state_io.dart](../packages/engine/lib/src/persistence/state_io.dart):
`StateWriter` and `StateReader`. Integers are variable length (a sign bit and
6 bits in the first byte, 7 bits after), using only `%` and `~/`, so the
bytes match on every platform. Strings are UTF-8 with a length. Every entity
has a hand-written `write(StateWriter)` and a `read(StateReader)`; there is
no code generation.

The same bytes feed both the save and `Simulation.stateHash()`, so the two
can't disagree. `stateHash` hashes `world.write`, then the sleepers, then the
economies if there is a shared cycle, then the national economy if it
exists, then the stock market if it exists. A world without a stock market
hashes as it did before one existed.

## The save file

[persistence/save_file.dart](../packages/engine/lib/src/persistence/save_file.dart):
`SaveFile` (the bytes) and `SaveData` (`encode`, `SaveData.decode`). Layout,
in order:

1. magic `market-game-save`, format version, scenario id, seed;
2. whether cities slept from the start, and the `GameStart` chosen;
3. the neighbourhoods woken, each with its row, day, price index,
   households and shops at that moment;
4. the content's structure: every mirrored list's keys, in order;
5. `world.write`;
6. the command log (day and command) and the pending commands;
7. the sleepers, the economies, the national economy.

`decode` rebuilds the content first (cities asleep, then each woken
neighbourhood through `withNeighbourhoods`), checks the structure
(`_structureProblem`, using `ListGrowth` from
[content_db.dart](../packages/engine/lib/src/content/content_db.dart)), reads
the world, then calls `growWorld` so the world gains anything the content
added since. Any problem is a `FormatException`.

## Version gating

- `currentStateVersion` (39) in
  [state_io.dart](../packages/engine/lib/src/persistence/state_io.dart) is
  the layout written. Bump it whenever the layout or the rules change.
- `oldestReadableVersion` (6) in
  [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart) is
  the oldest that loads.
- Readers check `reader.version` and fill defaults for fields added later,
  for example `reader.version >= 21 ? Money(reader.readInt()) : Money.zero`
  in `Command.read`.
- Milestones named in `save_file.dart`: 9 (structure in the header), 24
  (woken neighbourhoods), 26 (cities asleep), 27 (countries' economies), 29
  (the national economy), 33 (the national table's shape, `tableShape` in
  [country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart),
  checked before the economy is read), 34 (each lot's arrival day for goods
  that go out of fashion, the national trades and chains a save knew, so a
  table that gained some still reads it, and each woken district's
  edition), 35 (`softwareVersion` in
  [software.dart](../packages/engine/lib/src/state/software.dart): the
  software market and software companies' products, written at the end of
  the world, and key people's market and software employer; an older save
  opens the market as the scenario sets it out, in `growWorld`), 36
  (`factorySalesVersion` in
  [factory_sales.dart](../packages/engine/lib/src/state/factory_sales.dart):
  factories' size, works, reliability and share of independents, rival
  producers, tenders and contracts, factory reports' penalties, and
  `BuildFactory`'s size), 37 (`contractsVersion`: producers' aim, capacity
  and commitments, chains' plants, contracts' price index and request), 38
  (`stocksVersion` in
  [stocks.dart](../packages/engine/lib/src/state/stocks.dart): the stock
  market beside the world; an older save opens it on its next day, from
  the table, in `currentStocks`), 39 (`controlVersion`: shares' owners,
  bids, raiders, the holding's share loans, control and levers, and the
  player's own listings).
  The full history of what each version added is in
  *Persistence* in [Engine Architecture.md](<../Engine Architecture.md>).

Rule of thumb when adding state: write it in `write`, read it in `read`
behind `reader.version >= N`, bump `currentStateVersion` to N, give older
saves a sensible default, and add a test that reads an older layout. For a
new format, the commit before it can write a whole-save fixture: see
[old_saves_test.dart](../packages/engine/test/old_saves_test.dart).

A save that fails to load for any reason, not only a `FormatException`, is
set aside by the app's `openGame` and its slot freed.

## Growing worlds

[state/growth.dart](../packages/engine/lib/src/state/growth.dart),
`growWorld(world, content)`. When the scenario gains entries at the end of
its lists, a loaded world gains them too: new products get prices, stock and
history; new categories get needs; new markets get cohorts and a census; new
people and suppliers join with their opening cash; the scenario's stores on
new sites open that day. Content that hasn't grown changes nothing, so a
grown save writes back the same bytes. The same function wakes a
neighbourhood.

## Replays

`Simulation.replay` rebuilds a game from its seed, start and command log
alone, and must reach the same `stateHash` as `Simulation.load`. Only the
player's commands are logged, plus `WakeNeighbourhood` and `CreateBrand`,
which apply when submitted. AI and manager commands regenerate. A replay is
valid only under the rules that recorded it; snapshots, not replays, survive
engine updates.

## Saves in the app

[app/lib/src/saves.dart](../app/lib/src/saves.dart) defines `SaveStore` (one
game) and `SaveSlots` (three games and the language), picked per platform:

- [saves_io.dart](../app/lib/src/saves_io.dart): `FileSaveSlots` and
  `FileSaveStore`, files `slot1.mgsave` … in the app support directory, each
  with a `slotN.json` summary. Writes go to `.tmp` then rename. An
  unreadable save is moved aside as `unreadable-<time>.mgsave`. The old
  single `autosave.mgsave` moves into slot 1.
- [saves_web.dart](../app/lib/src/saves_web.dart): `MemorySaveSlots`, so web
  saves are lost on reload.

`SimulationController.save` runs on the first of each month and when the app
goes to the background; `openGame` in [app.dart](../app/lib/src/app.dart)
loads one and sets it aside on a `FormatException`.
