# National economy, growth and factories

Two levels of economy run side by side:

- **The shop level**: districts played in full, day by day, household by
  household ([engine-core.md](engine-core.md)), plus districts asleep run
  by formula each month ([content-and-scenarios.md](content-and-scenarios.md)).
- **The national level**: whole countries run by formula each month, region
  by region, with chains as blocks of shops and no households. This is where
  a player's chain grows past a few districts.

Design detail: *Countries by formula*, *Countries in the game*, *Growing
nationally*, *What compounds* and *Factories* in
[Engine Architecture.md](<../Engine Architecture.md>), with balancing tables
under *Growing nationally*, *What compounds* and *Compounding growth*.

## Countries in the game (shop level)

A scenario's `countries` (France first) give each place its taxes, cycle,
wages (`service`) and wholesalers. In the world:

- `WorldState.macro` is the first country's economy; `otherEconomies` hold
  the rest; `cycle` is the shared cycle (`SharedCycle` in
  [state/macro.dart](../packages/engine/lib/src/state/macro.dart)).
  `MacroSystem` turns each country with its own chance of following.
- One central bank rate for all, weighted by each country's `weight`.
- `regimeLog` records each month's regime per country, which the national
  level replays.
- Taxes: `companyTaxes` in [state/taxation.dart](../packages/engine/lib/src/state/taxation.dart)
  splits a company's year by where its shops traded; `districtYears` and
  `countryLosses` hold what that needs.
- A store buys only from its country's suppliers (`supplierElsewhere`
  refusal).

## The national table

[countries/country_table.dart](../packages/engine/lib/src/countries/country_table.dart)
loads [euro.json](../content/countries/euro.json) and
[calibration.json](../content/countries/calibration.json) into a
`CountryTable`: per country its households, five income classes, three
trades (grocery, restaurants, electronics) with cost shares and shop counts,
NUTS regions with population and income, fictional chains with home regions,
corporate tax, and tuning (`RegionalTuning`, `BrandTuning`).

[countries/shop_bridge.dart](../packages/engine/lib/src/countries/shop_bridge.dart)
links the two levels: `formatTrades` maps scenario format keys to national
trades, and `shopCapture` reads the calibration.

## `CountryEconomy`

[countries/country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart),
the largest engine file. Main types:

| Type | What it is |
|---|---|
| `CountryEconomy` | Every country of the table; `advanceMonth(regimes:)`, `open`, `buyChain`, `sellBlock`, `closeCompany`, `bestMarketing`, `brandFactor`, `pullFor`, `regionMarket`, `yearOnYear` |
| `CountryState` | One country: households, spending indices, price and wage indices, trade months, region spending, `costLevels`, chains, blocks, offers |
| `Chain`, `ChainMonth` | An AI chain: shops by region (`regional`), price, pull, cash, monthly books; `boughtBy` once a company buys it |
| `CompanyBlock`, `BlockRegion`, `BlockMonth` | A company's shops of one format in one country, region by region: settled, young (`youngMonths`, 24) and being fitted out; discount, goodwill, marketing, strain |
| `NationalOffer` | A chain's offer for a block, open 30 days |
| `ShopCosts` | A block's cost shape as shares of sales |

It runs without dice in demand. Sales add up exactly to spending; chains'
openings and closings follow the gap between their margin and the trade's
normal one.

## How the national level runs in a game

- **Made lazily.** `currentNational(world, content)` in
  [systems/national.dart](../packages/engine/lib/src/systems/national.dart)
  creates `world.national` the first time it is needed and advances it to
  `1 + regimeLog.length` months, replaying each country's logged regime.
  Before each month, `_brief` sets each block's buying discount, strain and
  marketing. Null with one country or no table.
- **Booked monthly.** `NationalSystem` (1st of the month) books every block
  month not yet posted (`world.nationalPosted`) in the company's accounts
  against `elsewhere`, records it for the country's tax, supplies blocks from
  the owner's factories (`_supply`, `formatGoodsMix`), then makes chains'
  offers (`_offers`, `offerChance` 4% a month, at least
  `offerMinimumShops`).
- **Commands.** `OpenNational`, `BuyNationalChain`, `SellNational`,
  `AcceptNationalOffer`, `DeclineNationalOffer` in
  [apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart).
  Fitting out costs `nationalFitOut`.
- **Prices.** `valueChain`, `valueBlock` and `nationalBuyer` in
  [state/national_value.dart](../packages/engine/lib/src/state/national_value.dart).
  `companyEarnings` and `companyPrice` count blocks, so the bank lends on
  them.
- **Views.** `nationalViews` in
  [observation/national_view.dart](../packages/engine/lib/src/observation/national_view.dart)
  builds `NationalCountryView` per country (regions, trades, chains, the
  actor's blocks, `newShop`), reached through `Observation.national`.

## Directors and compounding growth

In [policies/director.dart](../packages/engine/lib/src/policies/director.dart):

- A director's brief (`Director` in [state/director.dart](../packages/engine/lib/src/state/director.dart))
  carries `nationalRate` (0 to `maxNationalRate`, 10% a month) or
  `nationalAuto` (the grade's own pace, `DirectorGradeDef.growth`: 1.5%,
  3.5%, 6%), and `nationalRegions`.
- `nationalChainShops` counts the company's shops of the trade in a
  country, played in full, asleep and by formula.
- `nationalBudget` is the month's openings: the rate times those shops,
  slowed by `criticalShare / (criticalShare + share)` as the chain nears
  critical mass, with a fractional shop opened by chance. At least one a
  month.
- Each opening goes to the allowed region that pays back soonest, within
  `nationalPaybackMonths` (36), as far as cash and loans go; a
  `NationalOpened` memo per region.
- **Strain.** A brief faster than the grade runs well gives the block a
  `strain`; `strainFactor` divides its pull by `1 + strainCost × strain`
  (0.6). Set in `_strain` in `systems/national.dart`.

Directors also open and buy in districts asleep for the player's company
(`OpenInDistrict`, `BuyInDistrict`, `DistrictOpened` and `DistrictBought`
memos).

**People and characters.** A director is a `DirectorPerson` with a
character (`DirectorCharacterDef` in
[content_db.dart](../packages/engine/lib/src/content/content_db.dart)),
which multiplies the payback limits, the reserve days, the credit used, the
pace when left to judge (`DirectorsDef.growthRateOf`, which `_strain` also
reads), the coaching (`keptBy`) and the pay (`salaryOf`). The month's
shortlist is `directorShortlist` in
[policies/candidates.dart](../packages/engine/lib/src/policies/candidates.dart);
`personOf` gives one hired before people their month's. `DirectorRecord`
counts what they did, noted by `Company.remember`.

## What size buys

- **Buying terms**: `buyingDiscount` in
  [state/buying_terms.dart](../packages/engine/lib/src/state/buying_terms.dart),
  from the last twelve months of goods (`Company.goodsMonths`, counted by
  `BuyingTermsSystem`). Applied to supplier orders, factory transfer prices,
  district shops and blocks.
- **National marketing and brands**: a block's goodwill raises its pull by
  `brandFactor`; with a director it spends what `bestMarketing` finds pays
  best, capped by `maxNationalMarketing` (8%).
- **Buying and selling chains whole**, and chains' offers (above).

## Factories

The first rung of owning the supply chain. One category per factory, made to
order for its owner's shops and, if the owner says, for rivals at a discount.

| Part | Where |
|---|---|
| Kinds and shared terms (`FactoryKindDef`, `FactoriesDef`) | the scenario's `factories` block, loaded in [content_db.dart](../packages/engine/lib/src/content/content_db.dart) |
| `Factory`, `FactoryStatus`, `spareFor`, `recordMade` | [state/factory.dart](../packages/engine/lib/src/state/factory.dart) |
| `factoryFor`, `marketQuote`, `factoryPrice`, `materialsCost`, `factoryLeadTime` | [state/factories.dart](../packages/engine/lib/src/state/factories.dart) |
| Daily wages, monthly site | `FactorySystem` in [systems/factories.dart](../packages/engine/lib/src/systems/factories.dart) |
| Delivery, invoicing between companies | `LogisticsSystem` in [systems/logistics.dart](../packages/engine/lib/src/systems/logistics.dart) |
| What a factory owes for what it made: `billMaking` (materials, and freight abroad), `billFactory` (any bill from beyond the simulation); used by deliveries, shops by formula and sales to other companies | [systems/factory_sales.dart](../packages/engine/lib/src/systems/factory_sales.dart) |
| `BuildFactory`, `SetFactoryShifts`, `SetFactoryTerms`, `CloseFactory`, `OrderFromFactory`; `PlaceOrder` refuses what a factory makes (`madeInHouse`) | [apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart) |
| `factoryOutlook` (what a new plant would do) | [observation/factory_outlook.dart](../packages/engine/lib/src/observation/factory_outlook.dart) |
| `FactoryReport` in period reports | [reports/period_report.dart](../packages/engine/lib/src/reports/period_report.dart) |
| `valueFactory`, `factoryEarnings` | [state/valuation.dart](../packages/engine/lib/src/state/valuation.dart) |
| Screens | [app/lib/src/screens/factory.dart](../app/lib/src/screens/factory.dart) |

Policies buy from a `Source` (`FactorySource` for the owner's plant) in
`StorePlan`. AI owners don't build factories yet.

## Labs, quality and key people

A factory's lab develops its products a generation at a time; its goods are
then better than the market's standard, which catches up month by month.
Design detail: *Labs, quality and key people* in
[Engine Architecture.md](<../Engine Architecture.md>).

| Part | Where |
|---|---|
| Numbers (`LabsDef`, `TalentLevelDef`), `SegmentDef.qualityWeight`, `worthWith` | the scenario's `factories.labs` block, [content_db.dart](../packages/engine/lib/src/content/content_db.dart) |
| `FactoryLine`, `Factory.labBudget`, `project`, `labWork`, `lines` | [state/factory.dart](../packages/engine/lib/src/state/factory.dart) |
| `factoryLead`, `factorySaving` (the owner's best of the kind) | [state/factories.dart](../packages/engine/lib/src/state/factories.dart) |
| `KeyPerson`, `WorldState.keyPeople` | [state/talent.dart](../packages/engine/lib/src/state/talent.dart) |
| Formulas: `labPower`, `generationWork`, `generationGain`, `generationSaving`, `keySalary` | [state/labs.dart](../packages/engine/lib/src/state/labs.dart) |
| `LabSystem` | [systems/labs.dart](../packages/engine/lib/src/systems/labs.dart) |
| Drawing a candidate, a lab's or software's: `newCandidate`, `drawLevel` over `TalentDef` (`LabsDef` and `SoftwareDef`) | [state/talent.dart](../packages/engine/lib/src/state/talent.dart) |
| `Stock.quality`, blended on delivery | [state/store.dart](../packages/engine/lib/src/state/store.dart), `LogisticsSystem._take` |
| Shoppers: the price index and `_accepts` take quality | [systems/demand.dart](../packages/engine/lib/src/systems/demand.dart) |
| Policy pricing (`qualityInPrice`, `_forQuality`) | [policies/retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart) |
| `CompanyBlock.quality`, set by `_quality` in `_brief` | [systems/national.dart](../packages/engine/lib/src/systems/national.dart) |
| `SetLab`, `HireKeyPerson`, `DismissKeyPerson` | [apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart) |
| `LabView`, `KeyPersonView`, `Observation.candidates` (by `candidateViews`, which software's market uses too), `quality` on shelves | [observation/observation.dart](../packages/engine/lib/src/observation/observation.dart) |
| Balance tool | [tool/labs_balance.dart](../packages/engine/tool/labs_balance.dart) |

In the app, [screens/lab.dart](../app/lib/src/screens/lab.dart) holds
`LabPage` (the lead chart `LeadChart` over `FactoryLine.history`, the lines,
the bench, the team) and `PeopleMarketPage`, opened from the factory page's
"The lab" row; the controller's `labOf`, `hiring`, `dismissing` and
`peopleOf` read pending changes. Layout B of the 2026-11-14 mockups. A shop's shelf line says how far its goods are over the standard (`store.better` in [screens/shop.dart](../app/lib/src/screens/shop.dart)), and a rival's shop in the World tab how many of its goods are (`market.betterGoods`).

## Not built yet

From the design doc: regions' own price levels, rivals who borrow, AI
factories and labs, poaching of key people, chains that set their own prices, entry of new chains, and
generating a neighbourhood from a national row. Events (an oil crisis, a
war, choices between two outcomes) are described under *Events* in
[Game Design.md](<../Game Design.md>) and not in code yet.
