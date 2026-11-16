# Technical debt register

Known problems in the code, found by reading it at commit `5a03209`
(2026-11-14), and since. None of them is fixed here. Each row says where it is and why
it matters. "Read, not run" means the problem follows from the code but no
test or run has shown it yet; confirm it before fixing.

Ids are stable: refer to them as D1, D2… When you fix one, delete its row
and say so in the commit message. When you find one, add a row.

## Suggested order

Fixed 2026-11-15: D1 (the chain-offer news, now told by the offer's
expiry), D4 (format 33 checks the national table's shape), D6 (any load
failure sets the save aside) and D28 (fixtures of formats 31 and 32).

Fixed 2026-11-16, in a pass over duplicated and misnamed code: D25 (the tab
files now carry the tabs' names) and two of D23's misplaced comments
(`Command`'s and `SaveData`'s). The same pass merged copies that had no row:
factory billing (`billMaking`), purchase borrowing (`_borrowing`), the excess
earnings price (`AcquisitionDef.askingPrice`), the tax on a sale's gain
(`taxGain`), first-of-month dates (`Day.firstOfNextMonth`, `firstOfMonth`),
and in the app every yes-or-no dialog (`confirm`), the bottom sheets
(`showGameSheet`, `SheetFrame`, `ChoiceTile`), a new business's funding
(`newBusinessFunding`, `CapitalField`, `BorrowSwitch`), the person rows
(`PersonRow`), `ownerName` and `balancedStrategy`. Two pages that were both
called `BidPage` are now `TakeoverBidPage` and `TenderBidPage`. What it left
is in *Duplication* below.

1. **D2, D5**: the observation's live closures, and neighbourhood rows
   matched by index.
2. **D3**: the known `_fitOut` mistake in company financials.
3. **D18, D19**: test coverage of the web build and of older saves, which
   guard everything else.
5. The rest as the code around them is touched.

## Correctness

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D2 | `Observation` says it is "a copy, unaffected by later steps", but `districts`, `national` and `stocks` are closures over the live world (`observe` passes `() => shared.districts`, `() => nationalViews(world, …)` and the stock market's view, worked out on first reading). Anything that keeps an observation across a step and reads them gets today's state, not that day's. | [observation.dart](../packages/engine/lib/src/observation/observation.dart) `observe`, `Observation` | It caused D1 (fixed 2026-11-15), and is a trap for any before/after comparison or for moving the engine to an isolate. |
| D3 | `_fitOut` assumes world store *i* is scenario store *i* for the stores a game began with (`index >= content.stores.length` skips the rest). Waking a district appends scenario stores to `content.stores`, so a store the player opened later can fall below that length and gain the fit-out of an unrelated scenario store. Holding starts return early and are safe; older saves and chosen or classic starts are not. | [app/lib/src/financials.dart](../app/lib/src/financials.dart) `_fitOut` | Inflates money tied up, so ROIC and the company page read wrong after a wake. |
| D5 | Neighbourhood rows are not in the content structure either. Sleepers and woken districts are matched to rows by index; the only check is `row >= length`. | [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart) `SaveData.decode`; [simulation.dart](../packages/engine/lib/src/simulation.dart) `Simulation.load` | Reordering or removing a row in `prototype.json` attaches saved districts to the wrong rows without an error. |
| D7 | Reading the national economy can create and advance it: `currentNational` makes `world.national` on first use, and is called from `Simulation.national`, `nationalViews` and commands, not only from `NationalSystem`. `stateHash` and saves include it only once it exists. Read, not run; the window is small (until the first 1st of the month, or an old save's first read). | [systems/national.dart](../packages/engine/lib/src/systems/national.dart) `currentNational`; [simulation.dart](../packages/engine/lib/src/simulation.dart) `stateHash` | A getter that changes state means the hash can depend on whether a screen looked. |
| D8 | Two saves can run at once: `step()` starts an unawaited `save()` on the 1st of the month, and the app also saves when it goes to the background. Both write the same `slotN.mgsave.tmp` before renaming. Read, not run. | [controller.dart](../app/lib/src/controller.dart) `step`, `save`; [saves_io.dart](../app/lib/src/saves_io.dart) `FileSaveStore.write` | Rare, but it can leave a torn save in the slot. |
| D9 | The ink map force-unwraps `outline.regions[key]!` for every region of the national table, and no test checks that `outlines.json` has every region `euro.json` has. | [screens/national.dart](../app/lib/src/screens/national.dart) `_InkMap` | Adding a region to the table without redrawing the outlines breaks the country page. |

## Architecture

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D10 | The app reads `WorldState` directly in three places, against the rule that only observations leave the engine: `residence`, `sleeper(row)` and `start` go through `Simulation.world`, whose own comment says the app will read observations instead. | [controller.dart](../app/lib/src/controller.dart); [simulation.dart](../packages/engine/lib/src/simulation.dart) `world` | Blocks moving the engine to a background isolate, and lets the UI see what the player shouldn't. |
| D11 | Lower layers import higher ones: `state/game_start.dart` imports `commands/apply_command.dart` (for `maxNameLength`) and `commands/refusal.dart`; `state/districts.dart` imports the neighbourhood generator; `reports/period_report.dart` imports `systems/tick_system.dart`; `systems/sleepers.dart` imports `observation/outlook.dart` and `policies/retail_policy.dart` (`closingLoss`); `observation/national_view.dart` imports `systems/national.dart`. | those files | The folders no longer form layers, so a change in a policy or command can ripple into state and saves. Moving shared limits and helpers into `state/` or a rules file would untangle it. |
| D12 | State is saved in four pieces, each with its own presence rule: `world.write`, then sleepers, economies (`writeEconomies`) and the national economy (`writeNational`). `SaveData.encode`, `SaveData.decode` and `Simulation.stateHash` each list them by hand, and the hash skips economies with one country and national when null. | [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart); [simulation.dart](../packages/engine/lib/src/simulation.dart) `stateHash`; [world_state.dart](../packages/engine/lib/src/state/world_state.dart) | New state has three places to forget; one function used by both save and hash would keep them in step. |

## Moddability

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D13 | Scenario keys are written into code. The engine maps format keys to national trades in `formatTrades`; the generator uses `'grocery'`, `'supermarket'`, `'balanced'`, opening hours per strategy key, a rule per kind of shop (clothing's two shops, `'fastfashion'` and `'boutique'` among them), and French shop words as a fallback; the district formula (`_settled` in sleepers.dart) and the opening outlook (`habitsOf` in outlook.dart) keep fitted figures per format key. The app picks colours and icons by key in `Ledger.trade`, `formatIcon`, `categoryIcon`, `regimeIcon`. | [shop_bridge.dart](../packages/engine/lib/src/countries/shop_bridge.dart); [neighbourhood_generator.dart](../packages/engine/lib/src/neighbourhoods/neighbourhood_generator.dart); [app/lib/src/theme.dart](../app/lib/src/theme.dart) | Goal 6 says what differs between worlds is data. A mod's formats get no national trade, a default colour, and generated districts that assume the prototype's formats. |
| D14 | Balance numbers live in code, not content: `offerChance`, `offerMinimumShops`, `offerDays` ([national.dart](../packages/engine/lib/src/systems/national.dart)); `strainCost`, `maxNationalMarketing`, `youngMonths` ([country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart)); `nationalPaybackMonths`, `buyoutPaybackMonths` ([director.dart](../packages/engine/lib/src/policies/director.dart)); `closingLoss`, `maxManagedMarketing` ([retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart)); `maxNationalRate`, `maxRivalDiscount` ([apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart)); `_shakyMargin`, `_shakyChance` ([sleepers.dart](../packages/engine/lib/src/systems/sleepers.dart)). | those files | The headless runner can't sweep them, and a mod can't change them. |
| D27 | A block's quality counts a plant's whole month of capacity for every block and product it could supply, though hand-run shops, other blocks and rivals share it; and shops run by policy pick a source on price alone, blind to a factory's better goods. Read, not run. | `_quality` in [national.dart](../packages/engine/lib/src/systems/national.dart), `StorePlan` in [retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart) | A chain much larger than its plants gets more pull from quality than its shelves could hold; rivals never choose a factory for its quality. |
| D30 | Software is balanced at its own pay scale: software people ask 2,400 to 16,000 a month against labs' 200 to 1,600, because its market is the world's spending in real euros. The two markets for people never meet, so a lab engineer and a software engineer of the same level are paid tenfold apart. | `software.levels` and `factories.labs.levels` in [prototype.json](../content/scenarios/prototype.json) | Fine while they never compare; a shared market for people, or poaching across them, would need one scale. |
| D31 | Software's rivals are simple: they never hire, poach, buy startups or raise rounds; the biggest is always the one to offer for a player's company; AI owners never start software companies; and the market follows the shared cycle, or the first country's. A star team can still run far ahead of them for years. | [systems/software.dart](../packages/engine/lib/src/systems/software.dart) | The race lacks the incumbents' fight back and the talent war that make a lead hard to hold. |
| D32 | Factory sales leave out other industries as buyers (restaurants, hotels, offices), set aside by the owner for a restaurants rework; rivals' discounts only drift back when they beat the player, so a long price war leaves them keen for good; chains' own plants never close or grow beyond their need; tenders open only for products the player's running factories make; and the engine lets a player win more than their factory can make (the bid page warns). | [systems/factory_sales.dart](../packages/engine/lib/src/systems/factory_sales.dart) | Markets lack a big share of buyers, and a price war is one-way. |
| D33 | The stock market has its first two phases: no short selling or bonds yet, and companies by formula never fail; a company of the player's taken over passes to one of the game's other owners, not into the bidding chain's or raider's books; shares a company of the player's holds count at what they cost in its net assets, not at their price; the player trades index units and single shares only in person; chains' management is read off their margin; the six software rivals, valued like the world's tech giants, sit on the four countries' exchanges and are held back only by the 15% index cap; and its table must be rebuilt by hand (`build_companies.py`, then `stock_caps.dart`) when the scenario's chains, rivals or producers change. | [systems/stocks.dart](../packages/engine/lib/src/systems/stocks.dart), [content/stocks/companies.json](../content/stocks/companies.json) | The rest of the owner's plan (phases 2 and 3) is still to build. |
| D29 | Clothing's figures for the district formula and the opening outlook (`_settled`, `habitsOf`: capture, draw, goods extra, peak staff) are electronics' with 3% of goods lost to clearance, not fitted. The districts' clothing shops come out close to the cities' (14% of sales in France against 10 to 15%), but the outlook a player reads before opening one is unchecked. | `_settled` in [sleepers.dart](../packages/engine/lib/src/systems/sleepers.dart), `habitsOf` in [outlook.dart](../packages/engine/lib/src/observation/outlook.dart) | "Where to open next" may misjudge a clothing shop's profit. |

## Performance and scale

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D15 | Growing content goes through JSON: `withNeighbourhoods` and `withCitiesAsleep` decode `content.source`, edit it and call `loadScenario` again. `Simulation.plan` does this each month; `SaveData.decode` does it once per district ever woken. Each load also hashes the canonical JSON for `fingerprint`. | [neighbourhood_generator.dart](../packages/engine/lib/src/neighbourhoods/neighbourhood_generator.dart); [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart) `SaveData.decode` | Loading a game slows with every city woken, on a phone, on the main isolate. |
| D16 | A save holds every command the player ever gave, and saves are not compressed (compression was deferred). | [save_file.dart](../packages/engine/lib/src/persistence/save_file.dart) `SaveData.encode` | 40-year games grow without bound, and each save rewrites it all on the main isolate. |
| D17 | The engine runs on the main isolate, stepped by `Timer.periodic`; the first of each month adds the national economy, the sleepers and a rebuild of `plan` to the day. Accepted in the design; worth watching as the national level grows. | [controller.dart](../app/lib/src/controller.dart) `_run`, `step` | Frames can drop on month ends at fast speed. |

## Tests

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D18 | The Node (web) run covers only the core and the small test scenario. Every test that uses the prototype, the national table or neighbourhoods reads files with `dart:io` and is VM-only. | [packages/engine/test](../packages/engine/test), e.g. [test/countries](../packages/engine/test/countries), [test/neighbourhoods](../packages/engine/test/neighbourhoods) | Web determinism of the largest and newest code (formula layer, sleepers, generator) is unchecked. Embedding the content as Dart constants for tests would let them run on both. |
| D19 | Whole-save fixtures exist for formats 6, 31 and 32 only. Formats 7 to 30 are tested one entity at a time with `StateReader(bytes, version: N)`; no full save of, say, format 28 or 30 is ever loaded. | [test/fixtures](../packages/engine/test/fixtures) | The save layout is the riskiest thing to break; a fixture per earlier milestone (27, 29, 30) would catch sidecar mistakes (D12). |
| D20 | No test for outlines covering every region (D9). | [app/test](../app/test) | It would catch a broken country page before players do. |

## Dead code and drift

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D21 | Region tiles are dead but required: `loadCountryTable` fails without each region's `tile`, `NationalRegion.col` and `row` are read, and nothing uses them since the ink map replaced the tiles. `build_regions.py` still writes them. | [country_table.dart](../packages/engine/lib/src/countries/country_table.dart); [build_regions.py](../content/countries/build_regions.py) | Data and code kept alive for nothing; misleading for anyone editing regions. |
| D22 | `ContentDb.fingerprint` is computed on every load and read only by a test; its comment says a save loads only with the content it was made with, which stopped being true at format 9. | [content_db.dart](../packages/engine/lib/src/content/content_db.dart); [scenario_loader.dart](../packages/engine/lib/src/content/scenario_loader.dart) | Wasted work (D15) and a wrong explanation of how saves match content. |
| D23 | Stale or misplaced doc comments: [neighbourhoods.dart](../packages/engine/lib/neighbourhoods.dart) says the game doesn't use the generator yet; `SleeperSystem` says districts touch no account, but chains' shops there book against `elsewhere`. | those files | Comments are how this codebase explains itself; wrong ones mislead the next change. |
| D24 | [Engine Architecture.md](<../Engine Architecture.md>) has drifted: its header still says version 0.1, October 2026; the daily tick table lists 11 phases while `standardSystems` runs 15 (no buying terms, national, tax, factory or sleeper phases); the repository layout lists four screens and three country scripts; the testing table says the goldens compare daily state hashes on VM and Node, while the code checks one hash after a year; *Decisions to confirm* still says taxes are stubbed and that unguaranteed credit needs a net-asset threshold. | that file | It is the main design reference; sessions trust it. |

## Duplication

Left by the 2026-11-16 pass, because merging them would change behaviour or
an error message, or needs a shared shape the code doesn't have yet.

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D34 | Two JSON readers do the same job: `_Node` for the scenario and `_Reader` for the national table, each with its own `flag`, `fx`, `money`, `strings`, `object`, `objects` and `finish`, and slightly different error messages. | `_Node` in [scenario_loader.dart](../packages/engine/lib/src/content/scenario_loader.dart), `_Reader` in [country_table.dart](../packages/engine/lib/src/countries/country_table.dart) | A rule added to one (a range check, a clearer message) misses the other; one reader in `content/` would serve both. |
| D35 | AI owners and directors look for a rival's struggling shop to buy with near-copies of one search, by hand and in the districts by formula: the director's weighs what it judges each place would earn and skips only its own owner, the entrepreneur's skips the player too. | `EntrepreneurPolicy._purchase` in [entrepreneur_policy.dart](../packages/engine/lib/src/policies/entrepreneur_policy.dart), `_growth` in [director.dart](../packages/engine/lib/src/policies/director.dart) | A change to how buyers weigh a shop has to be made twice, and the two already differ in ways nobody chose on purpose. |
| D36 | Key people are built twice, for labs and for software: candidates (`_candidates` against `softwareCandidatesOf`) and new hires (`KeyPerson(` in the two systems) differ only in which levels and days they read. | [observation.dart](../packages/engine/lib/src/observation/observation.dart), [software_view.dart](../packages/engine/lib/src/observation/software_view.dart), [systems/labs.dart](../packages/engine/lib/src/systems/labs.dart), [systems/software.dart](../packages/engine/lib/src/systems/software.dart) | A shared market for people (see D30) would have to change both. |
| D37 | The "as a new company" switch is written twice, in opening a shop and building a factory; the shop's names the company without its pending rename, the factory's with it. | `_OpenStoreDialog` in [screens/world.dart](../app/lib/src/screens/world.dart), `BuildFactoryPage` in [screens/factory.dart](../app/lib/src/screens/factory.dart) | Small; merging it means picking one of the two names. |

## Size

| Id | Issue | Where | Why it matters |
|---|---|---|---|
| D26 | Very large files (lines on 2026-11-16): [screens/world.dart](../app/lib/src/screens/world.dart) (2,688: the World tab, starting a business, buying dialogs), [apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart) (2,596), [command.dart](../packages/engine/lib/src/commands/command.dart) (2,476), [country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart) (2,046), [content_db.dart](../packages/engine/lib/src/content/content_db.dart) (2,009), [screens/shop.dart](../app/lib/src/screens/shop.dart) (1,579), [screens/finance.dart](../app/lib/src/screens/finance.dart) (1,506). In [controller.dart](../app/lib/src/controller.dart), `_news` alone is about 430 lines. | those files | Hard to review and easy to conflict on; splitting by feature (national commands, factory commands, the new-business flow, news per kind) would help. |

## To check

Not confirmed as problems; look before acting.

- Only `observe` filters out `CompanyStatus.dormant`, for the owner's own
  companies. Check that public lists (company names, filings, valuations,
  rivals on the World tab) never show the player's dormant scenario company.
  [observation.dart](../packages/engine/lib/src/observation/observation.dart),
  [systems/taxes.dart](../packages/engine/lib/src/systems/taxes.dart).
- Web saves live in memory and vanish on reload
  ([saves_web.dart](../app/lib/src/saves_web.dart)). Fine for development;
  a limitation if the web build is ever shown to players.
