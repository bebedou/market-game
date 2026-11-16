# Engine core

The engine lives in [packages/engine/lib/src](../packages/engine/lib/src). Its
public face is [engine.dart](../packages/engine/lib/engine.dart), a list of
exports: if the app needs a symbol, it must be exported there. Design detail
is in [Engine Architecture.md](<../Engine Architecture.md>) under *Core
primitives*, *The daily tick*, *Commands and policies* and *Observations and
information*.

## Integer maths and determinism

Everything in [core/](../packages/engine/lib/src/core) exists so that the VM
and JavaScript give identical results.

| Symbol | File | Notes |
|---|---|---|
| `Money` | [money.dart](../packages/engine/lib/src/core/money.dart) | Extension type over `int` cents. `+`, `-`, compare; multiply only by an `Fx` (`times`) or an int (`timesInt`) |
| `Fx` | [fx.dart](../packages/engine/lib/src/core/fx.dart) | Fixed point, scale 10,000 (`Fx.raw(400)` is 4%). `Fx.parse('0.15')` reads a decimal string |
| `mulDivRound`, `isSafeInt`, `isqrt` | [safe_int.dart](../packages/engine/lib/src/core/safe_int.dart) | `a·b/d` without any intermediate above 2^53, rounding half away from zero |
| `imul32`, `rotl32`, `mask32` | [bits32.dart](../packages/engine/lib/src/core/bits32.dart) | 32-bit operations that behave the same on the web |
| `Rng.keyed`, `RngStream` | [rng.dart](../packages/engine/lib/src/core/rng.dart) | xoshiro128** seeded by hashing `(seed, stream, day, entity)`. Draws don't depend on iteration order. Streams 1 to 18 are listed in `RngStream`; add a new one rather than reuse one |
| `Hash32` | [hash32.dart](../packages/engine/lib/src/core/hash32.dart) | The state hash and content fingerprints |
| `expNeg` | [exp_neg.dart](../packages/engine/lib/src/core/exp_neg.dart) over [exp_table.g.dart](../packages/engine/lib/src/core/exp_table.g.dart) | `exp(-x)` from a committed integer table, made by [tool/gen_exp_table.dart](../packages/engine/tool/gen_exp_table.dart) |
| `Day`, `CivilDate` | [calendar.dart](../packages/engine/lib/src/core/calendar.dart) | Days since 1970-01-01, civil dates by integer maths |
| `parseDecimal` | [decimal.dart](../packages/engine/lib/src/core/decimal.dart) | Decimal strings straight to integers, never through `double` |
| `MarketId`, `StoreId`, … | [ids.dart](../packages/engine/lib/src/core/ids.dart) | One extension type per kind of id; an id is a position in a list |

Ordering rules: collections are lists by dense id or insertion-ordered maps;
every sort comparator ends with an id tie-break, since `List.sort` is not
stable; `hashCode` never touches state.

[test/forbidden_api_test.dart](../packages/engine/test/forbidden_api_test.dart)
scans `lib/` and fails on `double`, `num`, float literals, `/`, `dart:math`,
`DateTime.now`, `HashMap`/`HashSet`, `hashCode`, `Object.hash` and `Random`.
The app may use doubles for display; the engine may not.

## The `Simulation` facade

[simulation.dart](../packages/engine/lib/src/simulation.dart), class
`Simulation`:

- `Simulation.newGame(content, seed:, start:, citiesAsleep:)` builds
  `WorldState.initial` and one sleeper per neighbourhood row. The app always
  passes `citiesAsleep: true` and a `GameStart.holding`.
- `Simulation.load(content, file)` decodes a save (`SaveData.decode`).
- `Simulation.replay(content, file)` starts a new game from the save's seed
  and start, and re-submits the command log day by day.
- `submit(command)` queues a command for the next step. Two kinds apply at
  once: `WakeNeighbourhood` (handled by `_wake`, which grows the content and
  the world) and `CreateBrand`.
- `step()` runs one day and returns a `TickResult` (rejections, journal
  entries, `TickEvent`s, attribution).
- `observe(actor)`, `reports(company, period)`, `save()`, `stateHash()`.
- `plan`: the content with every sleeping neighbourhood generated as it
  stands, rebuilt once a month, for screens only.
- `national`: the countries by formula (`currentNational`).
- `world`: the raw `WorldState`, meant for engine internals and tests.

### Inside `step()`

1. One `PublicView` is built for the day, then every AI policy in
   `policies` decides from its actor's `Observation`.
2. `_managerCommands` runs store managers and directors (`manage` in
   [policies/manager.dart](../packages/engine/lib/src/policies/manager.dart))
   for every owner who has any. Directors' memos come back as `Directive`s.
3. Queued player commands, then AI commands, are applied in (actor,
   position) order by `_inApplicationOrder`. Only the player's queued ones
   are logged; AI commands regenerate on replay.
4. A director's memo is kept only if its command was carried out.
5. Each `TickSystem` in `standardSystems` runs, with a `TickContext`.
6. `world.today` moves on; in debug builds `invariantViolations` is checked
   and throws on any.

## The daily tick

[systems/tick_system.dart](../packages/engine/lib/src/systems/tick_system.dart)
defines `TickSystem`, `TickContext` (content, day, ledger, events,
attribution, `rng(stream, entity)`, `boughtIn`) and `standardSystems`, the
order that runs:

| # | System | File | When |
|---|---|---|---|
| 1 | `MacroSystem` | [macro.dart](../packages/engine/lib/src/systems/macro.dart) | 1st of month: cycle, inflation, wages, labour, the one central-bank rate, per country |
| 2 | `BuyingTermsSystem` | [buying_terms.dart](../packages/engine/lib/src/systems/buying_terms.dart) | 1st of month: counts each company's goods bought, for its buying discount |
| 3 | `FactorySalesSystem` | [factory_sales.dart](../packages/engine/lib/src/systems/factory_sales.dart) | 1st of month: contracts delivered, tenders closed and opened; month's last day: independents buy |
| 4 | `NationalSystem` | [national.dart](../packages/engine/lib/src/systems/national.dart) | 1st of month: advances the countries by formula and books companies' blocks |
| 5 | `PopulationSystem` | [population.dart](../packages/engine/lib/src/systems/population.dart) | 1st of month; census on 1 January |
| 6 | `TaxSystem` | [taxes.dart](../packages/engine/lib/src/systems/taxes.dart) | 1 January: corporate tax, filings |
| 7 | `LogisticsSystem` | [logistics.dart](../packages/engine/lib/src/systems/logistics.dart) | Daily: deliveries become stock lots and bills |
| 8 | `SpoilageSystem` | [spoilage.dart](../packages/engine/lib/src/systems/spoilage.dart) | Daily: expired lots written off |
| 9 | `OperationsSystem` | [operations.dart](../packages/engine/lib/src/systems/operations.dart) | Daily: openings, finished works, service levels |
| 10 | `DemandSystem` | [demand.dart](../packages/engine/lib/src/systems/demand.dart) (with [sales.dart](../packages/engine/lib/src/systems/sales.dart)) | Daily: households shop; about 60% of a day's time |
| 11 | `FactorySystem` | [factories.dart](../packages/engine/lib/src/systems/factories.dart) | Daily wages, monthly site |
| 12 | `LabSystem` | [labs.dart](../packages/engine/lib/src/systems/labs.dart) | Daily key people's pay; 1st of month: leads fade, the market for people turns, labs develop |
| 13 | `SoftwareSystem` | [software.dart](../packages/engine/lib/src/systems/software.dart) | Daily: subscriptions paid, team, offices, marketing and serving billed; 1st of month: the software market turns (standard, products, rivals, startups, customers, offers) |
| 14 | `StockMarketSystem` | [stocks.dart](../packages/engine/lib/src/systems/stocks.dart) | 1st of month: listed companies' books, worth, analysts and managements; quarters: results and dividends; daily: moods and prices, indices |
| 15 | `SettlementSystem` | [settlement.dart](../packages/engine/lib/src/systems/settlement.dart) | Daily wages and salaries; monthly rent, overheads, loans; pays bills due |
| 16 | `SleeperSystem` | [sleepers.dart](../packages/engine/lib/src/systems/sleepers.dart) | 1st of month: neighbourhoods asleep, by formula |
| 17 | `SolvencySystem` | [solvency.dart](../packages/engine/lib/src/systems/solvency.dart) | Daily: liquidates companies overdue past the grace period |
| 18 | `CloseSystem` | [close.dart](../packages/engine/lib/src/systems/close.dart) | Daily: sales history, reputation |
| 19 | `ReportSystem` | [report.dart](../packages/engine/lib/src/systems/report.dart) | Daily: folds the day into week and month reports |

[closure.dart](../packages/engine/lib/src/systems/closure.dart) (`closeStore`)
is shared by commands and solvency. [events.dart](../packages/engine/lib/src/systems/events.dart)
holds the sealed `TickEvent` family: `DeliveryRefused`, `PaymentOverdue`,
`CensusTaken`, `CompanyLiquidated`, `StoreSold`, `GenerationLaunched`,
`SoftwareLaunched`, `SoftwareOfferMade`, `RivalLaunched`, `RivalFolded`,
`TenderOpened`, `TenderClosed`, `ChainPlantBuilt`, `ContractCutAsked`,
`ContractRetendered`, `ManagementChanged`, `StockDelisted`,
`DividendsReceived`, `StakeCrossed`.

Order matters: `BuyingTermsSystem` before `NationalSystem` (blocks need the
month's discount), `SleeperSystem` before `SolvencySystem` and
`ReportSystem` (chains' district shops book into company accounts),
`StockMarketSystem` after `NationalSystem` and `SoftwareSystem` (it lists
their chains and rivals).

## Commands and refusals

- [commands/command.dart](../packages/engine/lib/src/commands/command.dart):
  the sealed `Command` class and 58 subclasses (`SetPrice`, `PlaceOrder`,
  `OpenStore`, `HireDirector`, `BuildFactory`, `OpenNational`,
  `BuyNationalChain`, …). Each has a `static const tag` and a `write`;
  `Command.read` switches on the tag and gates fields on `reader.version`.
  Never renumber a tag: saved command logs depend on it.
- [commands/apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart):
  `applyCommand(world, content, ledger, command)` validates and applies,
  returning `null` or a `Refusal`. One private function per command
  (`_setPrice`, `_openStore`, `_buildFactory`, …). Also exports limits such as `maxNameLength`, `maxMarketingShare`,
  `maxNationalRate`, `maxRivalDiscount`.
- [commands/refusal.dart](../packages/engine/lib/src/commands/refusal.dart):
  `Refusal(key, amount:, count:, product:, supplier:, format:, toFormat:)`.
  The app words it from `refusals.<key>` in the locale files
  (`refusalText` in [app/lib/src/format.dart](../app/lib/src/format.dart)).
- [commands/transfers.dart](../packages/engine/lib/src/commands/transfers.dart):
  `injectCapital`, `transferStore`, `sellToBestBuyer`, `transferCompany`,
  shared by commands and liquidation.

To add a command: subclass `Command` with a new tag, add it to
`Command.read`, to `applyCommand`, to the exports in `engine.dart`, to
`describeCommand` in [app/lib/src/commands.dart](../app/lib/src/commands.dart),
and add each new refusal key to [content/locales/en.json](../content/locales/en.json)
(the l10n test checks every refusal the engine can make). Bump
`currentStateVersion` if the layout or rules change.

## Policies: who decides for AI actors

[policies/](../packages/engine/lib/src/policies) turns an `Observation` into
commands. Policies are stateless; what they remember is in the world.

| File | Symbols | Role |
|---|---|---|
| [policy.dart](../packages/engine/lib/src/policies/policy.dart) | `Policy`, `standardPolicies`, `ownerPolicy`, `CombinedPolicy` | The interface, and a policy for every person the scenario gives a strategy |
| [retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart) | `RetailPolicy`, `StorePlan`, `closingLoss` | Running a store: forecast, supplier, orders, prices, assortment, staff, enlarging, dividends |
| [entrepreneur_policy.dart](../packages/engine/lib/src/policies/entrepreneur_policy.dart) | `EntrepreneurPolicy` | Monthly: where to open or buy, including districts asleep |
| [manager.dart](../packages/engine/lib/src/policies/manager.dart) | `manage` | Store managers and directors acting for an owner, within their duties |
| [director.dart](../packages/engine/lib/src/policies/director.dart) | `Directive`, `nationalBudget`, `nationalChainShops`, `nationalPaybackMonths` | A company's director: hiring managers, closing, growing, borrowing, national openings |
| [cushion.dart](../packages/engine/lib/src/policies/cushion.dart) | `cashCushion`, `storeCushion`, `cashForEssentials` | The cash a company keeps aside before ordering in full |

Skill shows only as misjudgment, drawn from `RngStream.manager` (weekly) and
`RngStream.director` (monthly).

## Observations: what an actor may see

[observation/observation.dart](../packages/engine/lib/src/observation/observation.dart):
`observe(world, content, actor, public:)` builds an `Observation` with the
actor's own companies in full (`CompanyView`, `StoreView`, `FactoryView`,
`LoanView`, `BillView`), public shelves (`ShelfView`), censuses, filings,
valuations, credit and offers. `PublicView` holds what is the same for
everyone, built once a day. Two fields are lazy closures over the live world:
`districts` and `national` (see [tech-debt.md](tech-debt.md)).

Other views and estimates, all read-only:

- [outlook.dart](../packages/engine/lib/src/observation/outlook.dart):
  `shopOutlook` (a settled year for a new shop on a site), `channelSpending`,
  `tradeSpending`.
- [factory_outlook.dart](../packages/engine/lib/src/observation/factory_outlook.dart):
  `factoryOutlook`, `outlookServes`.
- [research.dart](../packages/engine/lib/src/observation/research.dart):
  market studies with their errors.
- [national_view.dart](../packages/engine/lib/src/observation/national_view.dart):
  `nationalViews`, `NationalCountryView`, `CompanyBlockView`.

## Money and explanations

- [accounting/ledger.dart](../packages/engine/lib/src/accounting/ledger.dart):
  the double-entry `Ledger` for a day, `JournalEntry`, `AccountKind`,
  `EntryReason`, `PartyRef`. Balances live only in the ledger. Cash never
  appears from nothing after the opening balances; `world.elsewhere` stands
  for everyone beyond the districts played in full.
- [reports/attribution.dart](../packages/engine/lib/src/reports/attribution.dart):
  `Attribution`, `StoreSwitch`, `SwitchCause`, `ItemMiss`: why shoppers went
  where they did.
- [reports/period_report.dart](../packages/engine/lib/src/reports/period_report.dart):
  `PeriodReport`, `StoreReport`, `FactoryReport`, `companyReports`. 13 weeks
  and 24 months per company. `tradingProfit` is what the app shows as profit.
- [state/invariants.dart](../packages/engine/lib/src/state/invariants.dart):
  `invariantViolations`: ledger balances, cash matches, no negative stock,
  values within 2^53.
