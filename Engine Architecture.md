# Simulation Engine — Architecture
**Version 0.1 | October 2026** · Companion to [Game Design.md](<Game Design.md>) v0.3

## Goals

The engine is a pure Dart package that:

1. advances the world one day at a time, deterministically, on the Dart VM and on the web;
2. runs headless for thousands of days in seconds, for testing and balancing;
3. treats the player and AI firms identically: the same commands, the same rules, the same information limits;
4. explains its outcomes (attribution counters, ledger) so the UI can always answer "why";
5. grows into new industries by adding data, entity kinds, and systems, without rewriting retail;
6. is extremely moddable: whatever could differ in someone else's world (company names, countries, products, balance, words) is data, not code (see Modding in the design brief).

**Not goals for the prototype:** scaling beyond about 1,000 households, multithreading, and replay compatibility across engine versions (snapshots migrate; command-log replays don't).

## Architecture at a glance

```
┌──────────────────────── Flutter app ────────────────────────┐
│  widgets  ←  SimulationController (clock, speed, auto-pause) │
└───────────────┬─────────────────────────────▲────────────────┘
            commands                observations, reports, alerts
┌───────────────▼─────────────────────────────┴────────────────┐
│                     Simulation (facade)                       │
│      command queue  →  daily tick pipeline  →  views          │
│                                                               │
│  ContentDb (immutable definitions)   WorldState (all truth)   │
│  Tick systems (ordered phases)       Policies (AI decisions)  │
│  Ledger · Attribution · Persistence                           │
└───────────────────────────────────────────────────────────────┘
        ▲
headless runner (CLI): seeds × days × strategy bots → metrics
```

Three rules hold everywhere:

- **Only commands and tick systems change the world.** Commands come from the player, AI policies, and later managers.
- **Nothing outside the engine reads `WorldState`.** The UI, AI policies, and strategy bots see the world only through an `Observation`, which enforces the information rules.
- **Definitions are separate from state.** `ContentDb` holds immutable data from the scenario (products, segments, suppliers, tuning). `WorldState` holds everything that changes.

## Repository layout

A Dart pub workspace (Dart 3.8 or later, for workspaces, extension types, sealed classes, and `// dart format off` in generated tables):

```
market_game/
  pubspec.yaml               # workspace root
  packages/engine/           # pure Dart, no Flutter imports
    lib/engine.dart          # public API
    lib/countries.dart       # countries run by formula, which the game doesn't use yet
    lib/neighbourhoods.dart  # the neighbourhood generator, for tools
    lib/src/
      core/                  # Money, Fx, ids, calendar, rng, hashing
      content/               # definitions, scenario loader
      state/                 # WorldState and entities
      commands/              # command types, validation, application
      systems/               # one file per tick phase
      policies/              # AI retail, entrepreneur (later: managers)
      observation/           # visibility rules, market research
      accounting/            # ledger, statements
      reports/               # attribution counters, period rollups
      persistence/           # canonical writer/reader, save format
      countries/             # country tables, the monthly formula model, its link to the shop level
      neighbourhoods/        # the generator: a row of figures and a seed to a scenario's cities
    test/
    tool/                    # headless runner, exp-table generator
  content/                   # scenario data, a tiny package the app bundles
    pubspec.yaml             # `market_content`: declares the JSON as Flutter assets
    scenarios/prototype.json
    scenarios/prototype.<lang>.json  # the scenario's names and wordings in each language
    locales/<lang>.json      # every string of the interface, per language
    locales/languages.json   # the languages on offer
    countries/               # euro.json, calibration.json, build_euro.py; not bundled
  app/                       # Flutter, Android first (and web for development)
    lib/src/controller.dart  # SimulationController: clock, pending changes, news, saves
    lib/src/l10n.dart        # loads the words, tr(), scenario names in the language in use
    lib/src/screens/         # dashboard, store, orders, reports
    test/
```

The engine and the app share one workspace lockfile, so the engine's test dependencies must be ones Flutter's pinned `test_api` allows.

## Core primitives (`core/`)

Everything that touches state uses these types. The determinism rules from the design doc are enforced here.

| Type | Representation | Notes |
|---|---|---|
| `Money` | `int` cents | `+`, `-`, comparison; multiplication only by an `Fx` |
| `Fx` | `int`, scale 10,000 | fixed-point for rates, shares, loyalty, elasticities |
| `Qty` | `int` units | inventory is whole units; fractional needs use `Fx` |
| `Day` | `int` days since 1970-01-01 | calendar dates derived with integer civil-date math |
| IDs | `int` | `FirmId`, `StoreId`, `ProductId`, … as distinct types |

All of these are zero-cost extension types:

```dart
extension type const Money(int cents) {
  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money times(Fx f) => Money(mulDivRound(cents, f.raw, Fx.scale));
}
```

**Overflow-safe arithmetic.** On the web, integers above 2^53 silently lose precision. All values stay within ±2^53 (asserted in debug builds). Multiplications go through `mulDivRound(a, b, d)`, which splits `a` into `q·d + r` so no intermediate exceeds 2^53. Rounding is half away from zero everywhere.

**Bitwise operations are 32-bit on the web.** RNG and hashing use only 32-bit operations masked with `0xFFFFFFFF` and a 32-bit multiply built from 16-bit halves (`imul32`). They never shift a value of 2^32 or more; they use `~/` instead.

**No transcendental functions.** The store-choice model needs `exp`. `tool/gen_exp_table.dart` computes `exp(-x)` once on the developer's machine and writes it out as a `const` list literal, which the engine interpolates linearly. Because the table is source code, platform differences in `dart:math` never reach the simulation.

**Random numbers are keyed, not sequential.** Each draw is derived from `(worldSeed, stream, day, entityId)`:

```dart
final r = Rng.keyed(seed, RngStream.shopping, day, cohort.id); // xoshiro128**, seeded by hashing the key
final u = r.nextFx();
```

Results then don't depend on iteration order. Adding a household doesn't reshuffle every other household's luck, and adding a system doesn't shift the draws of the others.

**Ordering.**
- Collections are `List`s indexed by dense IDs, or insertion-ordered maps and sets (Dart's default `{}` literals). Never `HashMap` or `HashSet`.
- `List.sort` is not stable, so every comparator must be a total order that ends with an ID tie-break.
- `hashCode` and `Object.hash` vary between runs and platforms. They are never used for anything that affects state or the state hash.

**Enforcement.** A test scans `packages/engine/lib` for whole-word matches of `dart:math`, `double`, `num`, `DateTime.now`, `HashMap`, `HashSet`, `Random(`, and `.hashCode`, and fails if it finds any. Number formatting for display happens in the app.

## Content and scenarios (`content/`)

The game must be extremely moddable (see Modding in the design brief), and content is where that is won or lost. Whatever could differ in someone else's world belongs here rather than in code. Logic and saves go by ids, so names are free to change: a save records the content's structure as its keys, not its names, and can be opened in any language.

A scenario is a JSON file with the start date, markets, segments, products, suppliers, firms, persons, macro parameters, and every tuning constant. Decimal values are written as strings (`"0.15"`) and parsed straight into `Fx` or `Money` by an integer decimal parser, never through `double.parse`.

The scenario loads into an immutable `ContentDb`. All balance numbers live there, not in code, so the headless runner can sweep them.

Each product has a category, a tier, a shelf life, a base cost, a reference price (the shelf price households consider normal), and later an attribute map. Each segment has its consumption and premium share per category, trip interval, price sensitivity and tolerance, convenience and loyalty weights, word-of-mouth rate, odds for responding to a missing item, the share of households preferring each slot of the day, and a service weight; each market has its household count per segment, and three levels against the usual (1 by default, from 0.3 to 3): `priceLevel` scales the reference prices households there consider normal, `wageLevel` what staff and managers there are paid, and `incomeLevel` how well off its households are, on top of their relative income and purchasing power. Supplier prices are the same in every market. AI owners and managers scale their markup by the market's price level, since the same cost can fetch more in a dear city. Sites are the places in a market where a store can trade: location quality, monthly rent, shelf slots, storage, opening cost and build days. The scenario's stores each occupy one; the rest are vacant. **Formats** are the kinds of business a site can host (a convenience store, a supermarket, a fast food, a steakhouse, fine dining, an electronics shop): each sells a set of categories; formats that sell any category in common form a **channel** and compete for the same trips, as a convenience store and a supermarket do for groceries; a format costs `fitOut` times the site's opening cost to fit out; serves `visitsPerStaff` customers per member of staff in a slot; and pays its staff `wageFactor` times a shop assistant's wage (a restaurant's crew costs more). A format may need a `minArea` and add `slotBonus` shelf slots and `storageBonus` storage: a supermarket needs 220 m² and adds six slots. Its `overheads` are what a store of it pays each month per square metre for energy, insurance, upkeep and card fees, however much it sells (6.00 for groceries, 3.00 for electronics, 7.00 to 13.00 for restaurants, whose kitchens and dining rooms cost more to run). `ConvertStore` turns a store into a dearer format of its channel, a convenience store into a supermarket, paid at once (the difference in fitting out, never negative, plus works up to the format's least area) and finished after the site's build days, the store trading throughout; AI owners convert when the extra slots' margin, less the extra rent and overheads, repays the works within their payback, as they judge enlargements. A category still spreading among households has a `diffusion` (see Models from the literature). A scenario without formats has one that sells everything. Any site takes any format, chosen on opening; the scenario's stores and each strategy name theirs, and an AI owner opens its strategy's format. Restaurants are stores selling meals: their dishes are products bought as ingredients from a food wholesaler and sold by the cover, perishable, without a seat limit. `demand` holds the pull of marketing (`marketingWeight` at most, half of it at `halfGoodwill` of goodwill, which wears off by `goodwillDecay` a day) and households' `lossAversion`. A store spends a share of its recent sales on marketing, so its budget scales with the business; a strategy's `marketingShare` is the one its AI owners set. A person with a strategy runs their stores by it; one marked `local` is a shopkeeper who never opens more, while the others (chains and entrepreneurs) look for sites. `acquisitions` holds how stores and companies are priced when they change hands (see Buying and selling businesses); without it, nothing is ever sold. `finance` holds the bank's reserves and terms and the grace period before liquidation; `macro` the business-cycle regimes and the central bank's rule; `operations` the wage per staffed slot and how many shoppers one member of staff serves; `research` the grades of market study. Each scenario store says how many staff it starts with in each slot. Products discovered later through R&D are added at runtime to `WorldState.tech`, since `ContentDb` itself never changes.

## World state (`state/`)

Prototype entities:

| Entity | Key fields |
|---|---|
| `Person` | ledger accounts, bankruptcies and the latest one's day. The player and AI owners are both `Person`s; companies point to their owner. |
| `Company` | owner (who may sell it), ledger accounts, unpaid bills, founding day, capital injected (for an owner who bought it, the price paid), status (active, liquidated), the days of wages its cash cushion holds (14 unless the owner says otherwise), its director if any (grade, the strategy for the managers they hire and the stores they open, those managers' grade, how far they may grow it, whether they pay out, day hired), and its directors' memos, up to 240 |
| `Store` (a `BusinessUnit`) | site, market, location quality, listed products (shelf slots), inventory lots, prices, storage, staff per slot, service per slot, today's visits per slot, daily sales and visit history (28 days), status (building, open, closed), first trading day, selling area, enlargement under way and when it last grew, its manager if any (grade, strategy, duties, day hired), if its owner bought it, when and what they paid beyond its stock, and its reputation |
| `HouseholdCohort` | market, segment, weight (the households it stands for), preferred slot of the day, need per household per category, proximity per site, and per store: loyalty and perceived price index |
| `Supplier` | price list with volume tiers, minimum order quantity, lead time, payment terms (exogenous in the prototype) |
| `PurchaseOrder` | buyer store, supplier, lines, ordered day, arrival day, status |
| `Payable` | a company's unpaid bill: creditor, amount, due day, reason (supplier invoice, rent, interest, loan principal) |
| `Loan` | number, borrower, principal, amount still to bill, annual rate, installments left, guarantor, interest billed up to |
| `Bank`, `Landlords`, `Services` | books only: the bank lends from its reserves; landlords collect rent and opening costs; services sell market research |
| `ResearchReport` | number, buyer, market, grade, as-of day, and estimates with error: per segment its households, daily units and premium share per category, price sensitivity and tolerance, and slot preferences; per store its share of units sold |
| `GameStart` | the site, format and name the player chose for their first store, if they did; replays start from it |
| `MacroState` | regime and months in it, price index, wage index, latest inflation, policy rate, last measured shelf-price level |
| `MarketState` | growth owed to each segment in fractions of a household, and the censuses taken (households counted each first of January, the latest 40) |
| `PeriodReport` | a company's week (from Monday) or calendar month: days recorded, the net amount posted to each of its accounts, and per store visits, units sold, revenue, cost of goods and spoilage per product, units missed per reason and product, and trips gained from and lost to each other store by cause. Each company keeps its latest 13 weeks and 24 months. |

Design notes:

- **Households are agents grouped into cohorts.** Each cohort stands for `weight` identical households that shop together. A market's `agents` sets how many cohorts simulate it (by default one per household, as in the prototype's 1,000); raising the weight much beyond today's four households or so breaks the economy, though, as a cohort empties shelves in one trip (see Countries by formula). Population change moves households in and out of cohorts, so the agent count stays fixed as a market grows.
- **Inventory is lot-based (FIFO).** Each delivery becomes a lot with a quantity, a unit cost, and an expiry day. That gives exact spoilage and cost of goods sold.
- **`BusinessUnit` is the extension point.** `Store` is the only kind for now. `Factory`, `Farm`, and `Office` come later and share ownership, staffing, and accounting.
- **Opening hours are day slots** (morning, midday, evening, night), set by staffing: a store sets its staff per slot, and a slot without staff is closed. Each cohort prefers one slot. A store closed then costs the cohort `offHoursPenalty` of utility, since it must shop at another time, rather than ruling the store out; otherwise households whose slot no store opens would never shop.
- **Suppliers are exogenous in the prototype.** They sell from price lists that follow the macro price index, and they become real firms when production arrives.
- **AI owners are provisional.** This tentatively answers open question 1. AI companies are owned by AI `Person`s whose personal wealth comes from the scenario and grows with the dividends they pay themselves. Entrepreneurs are AI persons with no company yet, whose policy opens a store with their own capital. That keeps "same rules for everyone" literal.
- **Stores and companies are never removed.** IDs are dense, so a liquidated company and a closed store stay in the world with their status; a closed store frees its site for a new store.

## The daily tick (`systems/`)

`Simulation.step()` runs these phases in a fixed order. Decisions and commands run in the facade; every later phase is a `TickSystem`:

```dart
abstract interface class TickSystem {
  void run(WorldState world, TickContext ctx); // ctx: content, day, rng, ledger, attribution, alerts
}
```

| # | Phase | What happens | Cadence |
|---|---|---|---|
| 0 | Decisions | AI retail and entrepreneur policies decide from what their actors see | per policy |
| 1 | Commands | Apply queued and AI commands in (actor, sequence) order; reject invalid ones with a reason | daily |
| 2 | Macro | Move the business cycle on, compound inflation into the price and wage indices, reset the policy rate | monthly |
| 3 | Population | Each segment of each market grows or shrinks by its trend plus the regime's migration; on the first of January, a census | monthly / yearly |
| 4 | Logistics | Deliveries arrive as lots; payables are created | daily |
| 5 | Spoilage | Expired lots are written off | daily |
| 6 | Operations | Stores whose fit-out is finished open; finished enlargements add their area, shelf slots and storage; each slot's service level is set from today's staff and yesterday's visits | daily |
| 7 | Demand | Needs accrue; cohorts shop; purchases, substitution, loyalty, and perceived prices update; attribution is recorded | daily |
| 8 | Settlement | Bill the day's wages and manager salaries, and on the first of the month rent, overheads (to the services) and loan installments; pay the bills that are due, oldest first, as far as cash allows | daily / monthly |
| 9 | Solvency | Liquidate companies with a bill overdue past the grace period: pay creditors, call guarantees | daily |
| 10 | Close | Record each store's sales, misses and visits per slot, and move each open store's reputation toward how well it served | daily |
| 11 | Reports | Fold the day's journal entries and attribution into each company's running week and month reports, opening new ones as periods turn | daily |

Invariants are checked after the close in debug builds.

**Fair timing.** AI policies decide at the start of a step, from the same end-of-day world the player saw after the previous step, and their commands apply alongside the player's. A player who checks the dashboard tonight and acts gets exactly the same timing. Neither side reacts within the same day. Deciding at the start rather than the end of a step also means no AI commands are pending when the game is saved.

## Demand model (`systems/demand.dart`)

Each cohort goes through these steps every day:

1. **Needs accrue.** `need[category]` grows by the segment's daily units for that category times the regime's demand factor, times the share of households that have adopted it if it is still spreading, capped at `maxNeedDays` of consumption but never below one unit, so what is bought less than weekly (household goods, a meal out) still gets bought. Such rare purchases start each household part of the way to a unit, so a city's households don't all run out together.
2. **Hear prices.** The cohort's perceived price index for each store drifts toward the true index at the segment's word-of-mouth rate. A store's price index for a segment is its basket cost over the same basket at reference prices, weighting each listed product by the segment's daily units and tier share.
3. **Shop or not.** A cohort shops every `tripIntervalDays`, phase-shifted by cohort ID so traffic spreads across the week, if at least one need has reached a whole unit. The day's shoppers reach the stores in a shuffled order, since the first ones get scarce stock. A shopping day is a trip to a store of each channel the cohort needs something from: groceries at a convenience store or a supermarket, a meal at a restaurant of the format that serves it, a gadget at an electronics shop, each chosen, visited and learned from on its own.
4. **Choose a store.** Every open store of the channel in the market with something listed and at least one staffed slot gets a utility:

   `U = −β_price·λ·(perceived − 1) + β_conv·(location + proximity) + β_loyal·loyalty + β_service·(service − 1) + β_size·area/(area + halfSizeArea) + marketingWeight·G/(G + halfGoodwill) + reputationWeight·reputation − offHours`

   where `λ` is the loss aversion when the store is believed dearer than expected and 1 when it is believed cheaper, and `G` is the store's goodwill: advertising draws shoppers from rivals with less of it, with diminishing returns, and a trip it decided is attributed to it.

   Location is the quality of the store's site, the same for everyone. Proximity, from 0 to 1, is how close the cohort lives to the site, drawn once at the start. Without it every household agrees which store is most convenient, and loyalty turns small advantages into near-monopolies. Service is the store's level in the slot the cohort would shop: its preferred slot if the store is open then, or else the nearest one it is, in which case `offHours` is the off-hours penalty. Size is the store's selling area: bigger stores draw more shoppers, with diminishing returns, and each segment weighs it differently (families and retirees most).

   The probability of choosing a store is proportional to `exp(U − U_max)`, taken from the table. Each cohort's loyalty carries its own experience of stockouts and gaps, and service is seen directly; a store's reputation is what everyone has come to think of it. From 0 to 1, it moves each day `1/reputationDays` of the way toward how well the store served that day: the units it sold over those wanted of what it lists, sold or missed for want of stock, times its service level over the day's visits. A corner shop isn't blamed for its range: counting the products it doesn't list kept a well-run small store below the 85% its rivals started at. A store a city has known for years starts at `establishedReputation` (0.85), the player's new business and every store opened later at `openingReputation` (0.65), so a new store that serves well builds its name, and its custom, over its first years.
5. **Fill the basket.** For each category with a need of at least one unit, the cohort draws a tier from its premium share (the segment's, scaled by the households' affluence) plus the regime's premium shift, and tries to buy the whole units it needs:
   - if the item is listed, in stock and acceptably priced, it buys as much as there is, and revenue and cost of goods are booked;
   - an item is acceptable within the households' tolerance (the segment's, scaled by their affluence) above its **reference price**, the shelf price households consider normal: content data times the macro price index. Beyond the tolerance, the chance of buying falls off as `exp(−β_price·excess)`. Because the reference doesn't follow shelf prices, stores can't drift prices upward together;
   - for units not bought, an outcome is drawn from the segment's odds: **substitute** the other tier in the same store, go **elsewhere** (a follow-up visit to the best other store listing the item), **delay** (the need carries over), or **skip** (the need is dropped). A substitute or follow-up that fails turns into a delay; there are no further chains;
   - a price too dear is no easier to pay in a few days, and nobody answers it by paying more. So for an overpriced item a substitute must be cheaper, and what would have been a delay is a skip: the household goes without. The exception is a follow-up store that is sold out, or an overpriced item met on a follow-up from a store that was sold out, which can still be waited for.
6. **Learn.** Perceived prices for the stores visited become exact. Loyalty to each visited store moves `loyaltyRate` of the way toward the visit's fill score, where a unit bought as wanted counts 1, a substituted unit counts `substituteCredit`, and anything else counts 0. Loyalty to stores skipped on the trip moves `loyaltyDecay` of the way back to `neutralLoyalty`, where every cohort starts. A store that disappoints falls below neutral, below one never tried, so stockouts, gaps in the assortment, and overpricing all erode future visits; a good store rises above it and becomes a habit.

Because shoppers act on perceived prices, a price change takes time to show up in sales, and loyalty prevents price wars over a single cent.

A cohort's whole trip is its households': they go to the same store, each buys the whole units it needs, and visits, traffic per slot and switches count every household. In the prototype each cohort starts as one household; as the population grows, households join existing cohorts, so a few shop in twos.

## Legibility

Two mechanisms record *why* things happen as the simulation runs.

**Attribution counters.** Each cohort has a habitual store, the one it is most loyal to beyond neutral. When it shops somewhere else, the engine records a switch from the habitual store to the chosen one. The cause is the utility component with the largest gap in the chosen store's favor: price, convenience, hours (open when the household likes to shop), service or size, or "closed" if the habitual store isn't open for business. If no component favored the chosen store, the cause is "variety", meaning chance decided. Item misses are recorded directly as units per store, product, reason (not listed, out of stock, overpriced) and response (substituted, went elsewhere and to which store, delayed, skipped). Each step returns the day's counters, with visits per store, in its `TickResult.attribution`, and the Reports phase folds them into the owners' period reports.

This is what lets the UI say "lost 40 visits to Store B: price (milk +12%)".

**News.** The app turns each day's changes into news (`SimulationController._news`), and only what needs the player stops the clock: a change the game refused, a bill left unpaid, a bankruptcy. Everything else can be set to pause it. A product that sells out is news only when nothing is on order and the player orders for that store; a store a manager restocks makes no sold-out or delivery news, since a delivery that doesn't fit costs nothing (it goes back unbilled) and a manager orders to keep the stockroom full. Good news is told too: a record month for the holding, net worth passing 50,000, 100,000, 250,000 and on, and a store's reputation reaching 80% and 90%. In two years of a hands-off game the clock had stopped on 429 days of 730, for sold-out products with more on order and deliveries that didn't fit; it now runs through, with a news line or two a month.

**Double-entry ledger.** Every money movement is a journal entry in one party's books: day, debit account, credit account, amount, reason, and what it was for (store, product, units). Balances live only in the ledger; entities have no cash fields of their own. Cash changes hands only through a payment, which posts a matching entry on each side, so the total cash in the world never changes after the opening balances. External parties (households, suppliers, the bank, landlords, later government) have books too; the bank's opening reserves are part of the money supply, so lending moves money rather than creating it. Each step returns its journal entries. A period report's account flows are that period's income statement; the observation's balances are the balance sheet.

**Period reports.** `Simulation.reports(company, period)` returns a company's week or month reports, oldest first, the latest still running. They are copies, for the company's owner: policies never see them, only each store's profit over its owner's last twelve complete months, which an owner's observation carries (`StoreView.recentMonths`). A store's part of a report holds its visits, sales, goods sold and spoiled per product, and its running costs (staff, manager, rent, overheads and marketing), so its profit before interest and tax. A report's `tradingProfit` is its profit before fitting out and works, which serve for years, the corporate tax, gains on stores sold and debts forgiven, and with rent and overheads counted day by day: what the app shows as the period's profit, so investing, January's tax and the first of the month don't read as a bad week. Rent and overheads are paid on the first for the month; each store's report also records its daily share of them (`StoreReport.occupancy`, the month's at today's area and prices over the month's days), and `rentPaidAhead` is what the period paid beyond its share: ahead in a week with the first in it, drawn on, below zero, in the others, and about nothing over a whole month. Every company has them, so the headless runner could use them too, and a liquidated company's last report includes the liquidation. Weeks run from Monday and months are calendar months, so the first of each is partial; a report says how many days it recorded and whether it is complete.

## Finance and insolvency

- **Owner money.** `InjectCapital` moves personal cash into a company, booked as an investment by the person and equity by the company. `PayDividend` pays the owner from the company's retained earnings (net assets beyond the capital put in), never more. There is no other way for money to move between a person and their companies. Taxes wait for launch scope.
- **Loans.** One bank lends from its reserves. A loan is repaid in monthly installments of equal principal plus the interest accrued, billed on the first of each month; `RepayLoan` repays principal early with interest to date. The rate is fixed when the loan is taken: the policy rate plus the bank's margin plus a spread, smaller for loans the owner guarantees, larger for unguaranteed ones, and higher for five years after an owner's bankruptcy.
- **Credit.** This provisionally answers open question 2. The bank lends on earnings: without a guarantee, a company may owe up to `earningsMultiple` (a year and a half in the prototype) years of its stores' earnings, each counted as a buyer would (`storeEarnings`, the same year's profit the asking prices rest on), less what is left of its unguaranteed loans (`earningsRoom`). Stores open fewer than 28 days count nothing and losing ones count their losses, so a new company borrows only on a guarantee. On top of that, an owner can guarantee loans up to `guaranteeMultiple` times their personal cash, less what is left of the loans they already guarantee (`guaranteeRoom`). The old rule, unguaranteed debt up to the company's net assets once those passed 100,000, almost never let a chain borrow on its own: fitting out is spent, so a profitable chain's books hold little more than cash and stock.
- **Borrowing where you spend.** `OpenStore`, `BuyStore` and `BuyCompany` can carry a loan (`borrow` over `termMonths`), checked with the purchase: if the bank won't lend, nothing happens, and a purchase that fails takes no loan. For a store, the bank lends on the buyer's earnings, the bought store's own included, and then on the owner's guarantee for the rest (`splitLoan`), each part a loan of its own; the capital an owner puts in with a new store no longer backs a guarantee. For a company, the company itself borrows on its own earnings and pays that much of the price to the seller out of the loan, handing back that much of its capital; the buyer pays only the rest and puts in only that (`transferCompany`'s `financed`), and the seller is taxed on the whole price. Every observation carries what the bank still lends each company on its earnings (`companyCredits`, below zero when its loans already exceed it) and what the actor can still guarantee (`guaranteeRoom`), so the app offers what the bank will accept.
- **Bills.** Supplier invoices, rent and loan installments are all `Payable`s, paid oldest first when due, as far as cash allows. A bill that can't be paid raises `PaymentOverdue` and is retried daily.
- **Liquidation.** A company with a bill overdue for more than `graceDays` is wound up:
  - each store is sold at its asking price to the AI owner of its format best able to pay (see below), or else closes, with stock written off and undelivered orders cancelled;
  - its loans fall due at once;
  - creditors share its cash in proportion to what they're owed;
  - guarantors pay what is left of guaranteed loans, as far as their personal cash goes;
  - everything else is written off by the creditors;
  - the owner loses the capital put in and keeps the rest of their personal wealth, and the bankruptcy is on record.

  Sites are freed for anyone, the player included, and the player can start again with a new company.
- **Buying and selling businesses.** With `acquisitions`, every trading store has an asking price by the excess earnings method (see Models from the literature): its stock at cost and its fittings (the site's opening cost times the format's fit-out factor, at today's prices, worn down in a straight line over `fittingsLifeDays` to `fittingsResidual` of it), plus what a year's earnings beat `tangibleReturn` on those by, divided by `capitalization` (0.40 in the prototype: two and a half years of them), and never less than `distressFloor` (half) of its stock and fittings. A year's earnings are the last 28 days' units sold at today's prices, less their cost (the average cost of the stock on hand, or the base cost at today's prices), scaled to a year, less a year of today's wages, salary, marketing, rent and overheads. A store open fewer than 28 days asks what it holds. A company asks its trading stores' prices plus its cash, less its bills and loans, and never less than a symbolic euro. Every observation carries every store's and company's price and owner.
  - `BuyStore` buys another owner's store at its price, paid from one of the actor's companies; the store keeps its stock, staff, prices, manager, goodwill and shoppers, and orders on their way go with it. The seller books the price less the stock and what it had paid for the store as a gain (the `disposals` account, part of profit and so taxed in January); the buyer carries the price beyond the stock as `businessAssets`, until it sells, or books a gain if it paid less than the stock. The player's stores are never bought from them, and a store sold today can't be sold again the same day.
  - `SellStore` sells one of the actor's stores to the best buyer: a company of an AI owner who expands with the store's format, not the seller, whose company and personal cash cover the price and `buyerReserve` more, the best funded first. The owner puts in what the company lacks. Each of the player's stores shows who that would be.
  - `BuyCompany` buys a whole company from its owner out of the actor's personal cash, with its stores, cash, bills and loans; the buyer takes over the seller's guarantees of its loans, and the seller pays the 30% flat tax on the price beyond the capital they had in it. The player's companies are never bought from them.
  - An expanding AI owner who trades looks first, on its monthly day, for a struggling store of its format owned by anyone but the player: one losing money, a year after it opened and a year after it last changed hands. It buys the one whose price its usual estimate of a site's profit repays soonest, within its payback period, if its latest store opened or was bought at least `intervalDays` ago and its company and personal cash cover the price and the reserve.
- **Choosing the start.** `Simulation.newGame` takes an optional `GameStart`: the site, format and name of the player's first store, in place of the scenario's. Any site no other scenario store holds will do, if the format fits its area. The player starts as well off as with the scenario's store: what fitting out the chosen store costs beyond it comes out of the company's cash, topped up from the player's own to keep at least `minStartingCash` (10,000) in the company, and a cheaper store leaves the company the difference; a start the player can't afford is refused. The first store takes its prices and staff from the scenario's first store of its format, at the city's price level. The start is saved with the world, so replays begin the same way.
- **Entry.** `OpenStore` takes a vacant site, pays its opening cost, and the store trades after the site's build days; without a company given, it founds one with capital from the actor's personal cash. Rent is billed from the first of the month after the site is taken, or at once if that is the first. `CloseStore` closes a store for good.
- **Enlargement.** Each site has a selling area and a maximum. `ExpandStore` adds one step of floor area (the scenario's `expansion`), paid at once to the landlords as a fit-out cost; after its build days the store has the extra area, shelf slots and storage, and it keeps trading meanwhile. Rent is the site's rent in proportion to the store's area. One enlargement at a time, up to the site's maximum.

## The economy, staffing and research

- **Business cycle.** The regimes (expansion, slowdown, recession, recovery in the prototype) follow each other in order. On the first of each month the cycle moves on with a chance of one in the current regime's mean duration, drawn from the keyed RNG. Each regime has an annual inflation rate, real wage growth, an output gap, a demand factor on what households consume, and a shift in premium share: households trade down in a recession.
- **Hybrid inflation.** Each month, inflation is the regime's, moved `retailFeedback` of the way toward the shelf-price inflation actually measured in the markets (capped at ±20% a year). It compounds monthly into the price index; inflation plus real wage growth compounds into the wage index. Supplier prices, reference prices, rents, opening costs and research fees scale with the price index; wages with the wage index.
- **Policy rate.** A Taylor rule: neutral rate + inflation target + `inflationResponse` × (inflation − target) + `gapResponse` × output gap, floored at `minRate`. New loans are priced from it.
- **Labour market.** With `macro.labour`, unemployment drifts each month a quarter of the way toward the natural rate less the regime's output gap over Okun's coefficient (7.5% and 2 in the prototype: a recession's −3% gap takes it toward 9%). Wage growth falls by the Phillips slope times unemployment above natural, and households buy `confidence` times less for each point of it, so a slump deepens and lingers after the regime turns.
- **Taxes.** With `taxes`, each company's profit for the calendar year is taxed on the first of January, due within the month, at the reduced rate on the first part and the full rate on the rest (15% up to 42,500 and 25% in the prototype, as for French small companies), after setting off losses carried from earlier years; tax goes to the government, a party of its own. Dividends pay a flat 30% (the French single flat tax), taken from the owner, so keeping profit in the company and investing it is taxed once, paying it out twice.
- **Public records.** Every first of January each company's accounts for the year just ended become public, as French companies' filings are: sales, profit and stores at the year's end, kept ten years. The economy is recorded month by month (the regime, price and wage indices, inflation, the policy rate and unemployment), kept twenty years. Observations give both to everyone.
- **Staffing.** `SetStaffing` sets a store's staff for each of the four slots; it is both the opening hours and the headcount. Each staffed slot costs `slotWage` × the wage index a day, billed daily and paid to the market's households, their first income. One member of staff serves `visitsPerStaff` shoppers in a slot; each day a slot's service is today's capacity over yesterday's visits, at most 1.
- **Market research.** `BuyResearch` buys a study of a market at one of the scenario's grades. It is taken from the true state that day, and each estimate is the truth off by up to the grade's error, either way. A study covers each segment's households, consumption and premium share per category (as the current regime shapes them), price sensitivity and tolerance, and slot preferences, plus each open store's share of the units sold over the last 28 days. Only the buyer sees it.

## Population

- **Trends and migration.** Each market gives each segment a yearly growth rate, and each regime a yearly migration added to every segment: people arrive in good times and leave in recessions. On the first of each month after the macro phase, a segment's change is a twelfth of its rate on its current households, plus what was owed from earlier months; whole households join cohorts of the segment drawn at random (`population` RNG stream) or leave them, and the fraction waits for next month. Segments growing at different rates change a market's mix over the years.
- **Household incomes.** Within a segment, incomes spread evenly within `incomeSpread` of the segment's average, by each cohort's income rank. The rank follows from the seed and the cohort's ID (the `income` RNG stream), so it isn't saved, older saves get ranks on load, and changing the spread applies to existing games. A household's price sensitivity is the segment's times (2 − relative income), so the segment's average stays put while the hard-pressed chase discounts and the better-off care less; its premium share and price tolerance scale with its affluence, relative income times purchasing power. **Purchasing power** is one plus `incomeEffect` times the change in real wages (the wage index over the price index): when wages outpace prices households trade up and mind price less, and recessions undo some of it. The sensitivity used in store choice is the households' own, so a premium store keeps the better-off even at a price gap.
- **Cities.** Each market is a city with its own households, sites, levels and rivals; households only shop in their own city, so cities compete only for the owners' money and attention. Research covers one city per study. Entrepreneurs weigh every vacant site in every city, so a promising city attracts newcomers and established owners alike.
- **Growing cities.** The prototype's segments grow 1 to 3% a year (the capital's families shrink), about 2.2% a year for a city as a whole: a town where nobody opens a store sees its stores' sales rise year after year, beyond inflation.
- **Census.** Every first of January each market is counted, and the census is public: observations give the latest one and the history, and the app reports it as news. Entrepreneurs estimate demand from the census, so a growing town attracts new stores, with a lag. True households by segment, as of today, only come from market research.

## Commands and policies (`commands/`, `policies/`)

```dart
sealed class Command { ActorId get actor; }

final class SetPrice extends Command { final StoreId store; final ProductId product; final Money price; /* … */ }
final class PlaceOrder extends Command { final StoreId store; final SupplierId supplier; final List<OrderLine> lines; /* … */ }
// Also ListProduct, DelistProduct, InjectCapital, PayDividend, TakeLoan, RepayLoan,
// OpenStore, CloseStore, SetStaffing (staff per slot, which sets opening hours too),
// BuyResearch, HireManager (grade, strategy, duties; also rebriefs), FireManager,
// ExpandStore (one step of floor area), RenameStore, RenameCompany (1 to 32 characters),
// SetMarketing, ConvertStore, BuyStore, SellStore, BuyCompany,
// SetCushion (0 to 90 days of wages), HireDirector (grade, strategy, managers'
// grade, growth, payout; also rebriefs), FireDirector
```

Validation enforces the same rules for every actor: cash, minimum order quantities, shelf slots, staffing caps, and ownership. A rejected command comes back with a reason the UI can show.

A **policy** turns observations into commands:

```dart
abstract interface class Policy {
  List<Command> decide(Observation view, ContentDb content);
}
```

Policies are stateless: everything they remember is in the world, such as each store's sales history. So saves, loads and replays need nothing extra. `Simulation` takes a map from actor to policy, by default a `RetailPolicy` for every person the scenario gives a strategy.

- **`RetailPolicy`** is an AI store strategy, parameterized by a content `StrategyDef`:
  - **Forecast:** daily demand per product is units sold plus units missed for lack of stock or listing, averaged over `forecastDays`; days without history count as `openingForecast`.
  - **Supplier:** the cheapest at a typical order size, among those whose minimum order sells before it spoils.
  - **Ordering:** when stock plus orders fall to lead-time demand plus safety stock, it orders up to that plus `orderCycleDays` of demand. Goods in transit don't use storage, so only safety and cycle stock must fit; when they don't, batches shrink first. Safety and cycle stock are capped by shelf life, and orders stay within uncommitted cash, most profitable lines first.
  - **Cash cushion** (`policies/cushion.dart`): a company keeps aside what it must pay soon: its `cushionDays` of every store's wages and manager's salary, a month of each store's rent, each loan's next payment, and the corporate tax on this year's profit so far (`CompanyView.taxAccrued`, counted the way January's bill will be; on the first of January, before the bill, the year just ended). Orders are placed in full only from uncommitted cash beyond the cushion. A line that doesn't fit is topped up only to its reorder point, enough to keep selling until the next order, from the cash left once bills already due and orders on their way are paid; the least profitable lines go without. Bills due later, a tax bill or a supplier's terms, don't stop those few days of stock, since a store with empty shelves can't pay them either.
  - **Pricing:** every `priceReviewDays`, each price moves at most `maxPriceStep` toward cost × (1 + `markup`), pulled by `marketWeight` toward competitors' average × (1 + `marketPosition`). It is cut when more than `maxOverpricedShare` of would-be buyers refuse it, and never set below cost × (1 + `minMarkup`). The cost-plus anchor keeps prices from spiraling.
  - **Assortment:** every `assortmentReviewDays`, it scores products by expected daily margin, weighted by `premiumBias` for premium products. It lists the best unlisted product in a free slot, or in place of the weakest listed one if it scores `assortmentHysteresis` better.
  - **Staffing:** weekly, and on a new store's first day, it staffs the strategy's `hours`. Each open slot gets enough staff to serve its average visits over the forecast window times `serviceTarget`, with `openingTraffic` assumed for days without history.
  - **Costs:** supplier prices come from the published price index, so its cost-plus prices follow inflation.
  - **Owner money:** on the first of the month, it pays the owner the retained earnings beyond `reserveDays` of average spending on stock, staff, rent and interest, and beyond the year's tax so far, which enlargements and conversions leave alone too. When uncommitted cash falls below half that reserve, and the company has made a profit overall or is in its first two years, the owner puts personal cash in to restore it. An older company that has only lost money is left to fail.
  - **Closing:** on the first of the month, a store two years after it opened (the time a new store takes to win its custom), and a year after its owner bought it if they did, is closed if it lost more than 3% of its sales over its last twelve months (`closingLoss`), so a store that about breaks even stays open. Twelve months rather than the 28 days of sales the asking price uses: an electronics shop selling a few phones a day has months of 6,000 and months of 24,000, and a one-month test closed shops that made money.
- **Enlarging** is part of `RetailPolicy`: on the first of the month it enlarges a store whose shelves are full and which has products left to stock, if the company has made a profit overall, cash beyond its reserve covers the works, and what the new slots would earn less the extra rent and overheads pays the works back within `expansionPaybackMonths`, at most once per `expansionIntervalDays`. The new slots earn what the products off the shelves that shoppers ask for most would make: the units asked for (its misses for want of a listing), at the product's target margin. Counting each new slot at the average listed product's margin, as it first did, flattered enlargements: owners made about 300 in ten years that barely paid, and profit dipped after each. Owners don't count the pull of a bigger store, so they grow cautiously; managers enlarge only when trusted with investing (see Managers). When an enlargement pays but the cash isn't there yet, the owner holds its dividends until it is: the stores' needs, orders and works, come before the owner's monthly dividend.
- **`EntrepreneurPolicy`** runs once a month, on a day that depends on the actor so owners don't all look at once. For each vacant site, it estimates the monthly profit of a store there: `marginPerHousehold` × the market's households × the site's share among the stores of its channel trading there, each weighted by its location and by its size as shoppers weigh it (area / (area + `halfSizeArea`)), so a supermarket next door counts for more than a corner shop, less rent, the format's overheads for the site's area and one member of staff in each slot it would open, all at today's price and wage levels. It opens a store at the site with the quickest payback of the opening cost, if that is within `expansionPaybackMonths` and the person can fund the opening cost, three months of rent, overheads and wages, and two weeks of stock. An owner who already trades expands only while in profit overall and `expansionIntervalDays` after its latest store opened, and nobody expands within that interval of their own bankruptcy. The estimate uses only public information, so entrants can be wrong.
- `ownerPolicy(strategy)` combines the two for a person the scenario gives a strategy.
- **Managers** run a store for its owner. `HireManager` puts a manager of one of the scenario's grades in charge, following one of its strategies (the price stances: discount, balanced, premium), with any of five duties: reordering stock, pricing and marketing, choosing products, staffing, and investing. Investing is off for briefs recorded before it existed, in saves and command logs. Hiring again with the same grade changes the brief; another grade replaces the manager, and `FireManager` lets them go, as does closing the store.
  - Each day, after the policies, the facade runs every manager from the owner's observation (`policies/manager.dart`). A manager plans its store with the same `StorePlan` as a `RetailPolicy` by its strategy, and gives only the commands within its duties; orders share the company's uncommitted cash store by store, under the same cash cushion as AI owners. With pricing it also sets marketing, reviewed with the prices: a store that never advertised lost its goodwill, and its shoppers, to rivals that did. It spends the share that pays best (`StorePlan.bestMarketingShare`): spending a share s of daily sales R settles goodwill at G = s·R/δ, pulling w·G/(G + H); at m, what a euro of sales leaves after the goods (at the strategy's markup) and the store's staff, one more euro pays back a euro at G = √(m·w·H·R/δ) − H. In half percents, never below the strategy's share nor above 8%: about 5% for a balanced corner shop, 2% for a discount one, whose thin margin makes heavy marketing a loss. AI owners keep their strategy's share. With investing it converts or enlarges the store by the owner's rules, once the company has made a profit overall and from cash beyond the strategy's reserve and the year's tax, after the day's orders: without it a managed store stayed as it was while rivals grew around it. Its commands are the owner's, unlogged like AI commands, so replays regenerate them.
  - Skill shows only as misjudgment: each week, keyed by store, each product's demand forecast and target price and the store's traffic are off by a uniform factor of up to (1 − skill) × the scenario's `forecastError` or `priceError`, drawn from the manager RNG stream. A manager of skill 1 decides exactly as the owner's policy would. Mistakes come from misjudging the market, never from blunders.
  - A grade's salary × the wage index is billed daily to the `salaries` account and paid to the market's households, like wages.
  - AI owners don't hire managers yet; they run their stores themselves.
- **Directors** run a whole company for its owner, above its store managers (`policies/director.dart`). `HireDirector` puts a director of one of the scenario's grades in charge with a brief: a strategy, the grade of the managers they hire, how far they may grow the company (`Growth`: keep the stores as they are, enlarge and convert them, also open new stores, also buy struggling rivals), whether they may borrow to grow, and whether they pay the owner what is left each month. Hiring again with the same grade changes the brief; another grade replaces the director, and `FireDirector` lets them go, leaving the managers. A scenario without `directors` offers none.
  - Each day, `manage` runs a company's director after its managers, from the cash they left. A director hires a manager of the brief's grade for any store without one, with every duty but investing, which is theirs, following the brief's strategy if it runs that kind of store, or else the store's own strategy at the market's prices.
  - On the first of the month they close the stores an AI owner would (`losingStore`), which the managers then leave alone, and then, once the company has made a profit overall and from cash beyond the strategy's reserve and the year's tax: enlarge and convert as an owner would; buy a rival's struggling store or open one at the vacant site that would pay back soonest, judged as `EntrepreneurPolicy` judges, at most one a month and none within the strategy's interval of the company's latest store. New stores are paid from the company's cash, never the owner's. What they would grow but can't pay for yet, they save for, keeping the month's profit; otherwise, if the brief says so, they pay the owner the profit kept, up to the cash beyond the reserve, less what works and fitting out spent.
  - Skill shows in two ways. The margin they expect of each site is off by a uniform factor of up to (1 − skill) × the scenario's `judgmentError`, drawn each month, keyed by company and site, from the director RNG stream, so a weaker director opens more stores that later close. And they check their managers' forecasts and prices: every manager of the company keeps only 1 − skill × `coaching` of the misjudgment its grade allows (`DirectorsDef.kept`), the same draws scaled down.
  - A grade's salary × the national wage index is billed daily to `salaries` and paid to the households of the market of the company's first store still trading. The cash cushion holds as many days of it as of wages.
  - Each decision carried out leaves a `Memo` on the company (a manager hired, a store closed, enlarged, converted, opened or bought, the profit paid or kept, with its figures); a command refused leaves none. The app writes the monthly letter from them.
- **Strategy bots** for headless testing are `RetailPolicy`s acting for the player, one per scenario strategy, plus an idle player who never acts.

## Observations and information (`observation/`)

`Simulation.observe(actor)` builds a read-only copy containing:

- the actor's personal cash and latest bankruptcy, and the market studies it bought;
- public data: the macro regime, price and wage indices, inflation and policy rate, the households in each market at the latest census and every census so far, and every company's name;
- everything about the actor's own companies and units: status, account balances, money committed to unpaid bills and undelivered orders, loans, orders on their way (supplier, arrival, lines), unpaid bills (creditor, reason, amount, due day), and per store the status, first trading day, prices, stock, units on order, staff and service per slot, and the days since opening (up to 28) of units sold and missed (out of stock, not listed, overpriced) and visits per slot, also summed per day for charts;
- public information about every store: name, owner, site, status (including stores being fitted out), market, location, shelf prices and opening slots, and which sites are vacant.

AI policies get exactly this view, so they too have to infer demand from their own sales. A debug "god view" exists only in development builds.

**What a new shop might do.** `shopOutlook` (`observation/outlook.dart`) estimates a settled year for a new shop of a format on a site, from what anyone can see: households at the latest census by the scenario's mix, what they buy at normal prices, the rivals of its own channel by location, size and shelf prices, and what the site and staff cost. For a neighbourhood still asleep these come from `Simulation.plan`, where each shop is at the size the formula has reached and charges its strategy's markup on what it pays: the best any supplier gives for its usual order. It reads and changes nothing in the state, so no hash depends on it. A store's rivals are only those of its channel, and so is any share: restaurants take nothing from grocers. A market study's shares (`ResearchReport.unitShares`) and the `share` column in `tool/sim.dart` count the same way. The World tab shows the player's own shops with their share of their trade, then ranks every neighbourhood with room, for the trade the player picks, by that estimate.

## Persistence (`persistence/`)

- **One canonical serializer.** Each entity has a hand-written `write(StateWriter)` and `read(StateReader)`. The same code produces both save files and the state hash, so the two can't disagree.
- **Save file.** A header (format version, engine version, scenario ID, seed), the latest snapshot, and the log of submitted commands. AI commands aren't logged, because they regenerate deterministically; a save continues identically only under the same policies.
- **Versioning.** Snapshots carry a format version (`currentStateVersion`, now 22: a director's brief says whether they may borrow, and their memos what they borrowed, with none in older saves; 21: opening and buying commands carry their loans, and older ones read with none; 20: each store's report keeps its daily share of rent and overheads; 19 billed rent and overheads on the first of the month again, and a store's reputation no longer counts what it doesn't list; 18, with no new fields, billed them daily and changed the policies with the growth pass; 17 added each store's reputation, 16 added each company's director and memos, 15 added each store's running costs to its period reports, 14 each company's cushion, 13 what each store's owner paid for it and when, the two new accounts and the game's start; 12 added unemployment, companies' losses carried for tax, the government's books, public filings and the economic history; 11 added marketing shares, goodwill and format-changing works, and format 10's daily budget is dropped on load), and the engine loads every format since `oldestReadableVersion` (6): each reader checks `StateReader.version` and fills in defaults for fields added later, so updates keep players' games. A format 6 save loads with every cohort at a weight of one and its first census on the save's day. Replays are valid only under the rules that recorded them.
- **Content check.** IDs are positions in the scenario's lists, so the header carries the content's structure: every list's IDs, in order. Content whose numbers changed still loads, which is how balance tweaks keep saves. Every list the world mirrors may also grow at the end (markets, sites, categories, products, segments, people, suppliers, regimes, research grades, manager grades, strategies); the scenario's companies and stores only matter to a new game. Anything else, an entry removed, renamed or moved, is refused. Older headers (formats 6 to 8) hold only a fingerprint, so for them the world itself is checked: no list it mirrors may be longer than the content's.
- **Growing worlds.** After loading, `growWorld` brings the world up to the content: stores gain a price (unlisted), stock and sales history for new products, and running reports widen with them; households gain a need for new categories; markets gain cohorts for segments they lacked, counted in a census of the day; new people and suppliers join with their opening cash (the money supply grows by it), every household learns how far it lives from new sites (the `sites` RNG stream, keyed by site and cohort), new markets get their households, a census on the day and neutral loyalty to every store, and the scenario's stores on new sites open that day under their companies, founded with their opening cash. A labour market added since starts at its natural rate rather than at zero. That is how a game started before the cities existed gains them on update. Content that hasn't grown changes nothing, so a grown save loads back to the same bytes.
- **Compression** is deferred until saves get large; `package:archive` is pure Dart and works on the web.

## Public API

```dart
final class Simulation {
  // Each also takes optional `systems` and `policies`, for tests and the runner.
  factory Simulation.newGame(ContentDb content, {required int seed});
  factory Simulation.load(ContentDb content, SaveFile file);   // from the snapshot
  factory Simulation.replay(ContentDb content, SaveFile file); // from seed + command log

  Day get today;
  void submit(Command command);            // applied at the start of the next step
  TickResult step();                       // one day; returns alerts and command rejections
  Observation observe(PersonId actor);
  List<PeriodReport> reports(CompanyId company, ReportPeriod period);
  SaveFile save();
  int stateHash();
}
```

The API is message-shaped: commands go in and immutable views come out. That lets the engine move into a background isolate on Android later without changing the UI. Flutter Web has no isolates, so there the engine runs on the main thread, which is fine for development.

## Flutter integration

The app (`app/`) runs the engine on the main isolate. It loads the scenario from the `market_content` asset package, so the root JSON stays the only copy.

- **Text and languages.** No string the player reads is in the code. `locales/<lang>.json` holds the interface, nested by screen and flattened to dotted keys when loaded; `tr('store.sell', {'store': name})` looks one up and fills its `{placeholders}`. It is loaded at run time rather than generated by Flutter's `gen-l10n`, so a mod can bring a language without a build. An entry given as an object holds a form per count: `one` for the counts `format.singular` lists (1 in English and Spanish, 0 and 1 in French), an exact number, or `other`; `args['count']` picks one. `format` also holds what makes figures and dates read right: separators, the percent sign, month and weekday names, and how they combine, so `money()`, `percent()` and the dates follow the language, and `parseMoney` accepts what the language writes (`1.234,50` in Spanish). Anything a language lacks falls back on English, and anything English lacks shows as its key.
  - *The scenario's words.* `<scenario>.<lang>.json` mirrors the scenario by id: under `formats`, each id maps to its name, or to an object with its `name` and the other forms sentences need (`a`: "a supermarket", "un supermarché"), since articles and plurals can't be worked out from a name. `localizedScenario` swaps the names into the scenario's JSON before the engine loads it, so the engine stays unaware of languages; a scenario with no words in that language keeps its own names. Rivals' brands stay as they are in every language, and store and company names live in the save, so a game keeps the names it began with. A language is chosen on the main menu, not during a game, and remembered beside the saves; before any choice it is the phone's, if the game speaks it, or English. Flutter's own strings follow through `flutter_localizations`.
  - *The engine has no words.* A refused command returns a `Refusal`: a key, with the amount, count, product, supplier or formats that go in it. The app words it from `refusals.<key>`. The engine's other text, such as the `FormatException` of an unreadable save, is for developers and stays in English.
  - *Checks.* `l10n_test.dart` holds every language to English's keys, placeholders and list lengths, every key the code asks for and every refusal the engine makes to `en.json`, and each `tr` call to what its text says. `languages_test.dart` walks the screens in each language on a narrow phone, so a word too long for its row fails the test, as does a bare key or an unfilled placeholder.
- **`SimulationController`** (a `ChangeNotifier`, given to widgets by an `InheritedNotifier`) owns the `Simulation` and the player's latest observation. Widgets read observations and reports from it, never the world.
- **Clock.** Paused, slow (a day every 2 s), normal (1 s) or fast (4 days a second), plus "Week", which runs seven days fast and pauses. At normal speed a year passes in about six minutes of play, so a 30-minute session with pauses for decisions covers the design's one to two years.
- **Pending changes.** The player's commands wait in the controller until the next step, shown as "N changes take effect tomorrow" with a list to cancel from. A change to the same price, listing or staffing replaces the earlier one, and one that restores the current state just cancels it. Screens show prices and staff as they will be.
- **News and auto-pause.** After each step the controller turns the result and the change in observations into alerts: the player's refused commands with the engine's reason, overdue bills (once each), bankruptcies, products selling out, deliveries turned away, stores opening, closing and changing hands (bought, sold, or sold off as their company was wound up), companies the player bought, regime changes, and each month's profit. The player chooses which kinds pause the clock; by default, all but regime changes and monthly results. A pausing alert shows as a snackbar on any tab.
- **Main menu and saves.** The app opens on a main menu: continue the game saved last, start a new one, pick one of three saved games (each showing its company, date, net worth and the day it was last played, from a small summary kept beside the save), delete one after asking, or read how to play. A new game takes the first empty slot, or asks which game to replace, then a setup screen: the company's name, the city (with its households and levels), the site (area, rent, location and what fitting it out costs for the business picked, in red beyond the budget), the kind of business (with a word on each and how many compete there at the start), and what the start comes to (fitting out, the company's cash and the player's own). Leaving a game, from the menu or the back button, saves it and returns to the main menu. The game also saves itself when the app goes to the background and on the first of each month, to its slot's file in the app's support directory, written aside and renamed; the single autosave of earlier versions moves into the first slot. On the web saves stay in memory. A save the engine can't load is set aside, never overwritten, and its slot freed, with a note on the menu.
- **Screen margins.** The whole app sits 5% of the screen's height in from the top and bottom, beyond the system bars, for easier reading.
- **Look: an account book.** One design system (`theme.dart`): paper and ink, with green ink for gains and red ink for losses and trouble, a night edition (pale ink on dark paper) for the phone's dark mode, and the phone's own bars on the same paper. Three fonts, bundled with their OFL licences: Fraunces for titles and names, IBM Plex Sans for text, IBM Plex Mono for every figure, so amounts line up. Sections are a serif title over an ink rule, not cards; entries are separated by hairlines; tags are thin ruled labels and warnings red rubber stamps. Each kind of business has its colour (convenience store vermilion, supermarket green, fast food ochre, steakhouse oxblood, fine dining navy, electronics cobalt), shown as a small square mark wherever its stores appear and as the rule under a shop's name. Amounts show cents only below a thousand. Charts are inked: thin lines, square bars in plain ink with losses in red. Tabs fade into each other, the date slides as days pass, and amounts count to their new value.
- **Holding and stores.** The Holding, Finance and World tabs are about the player's whole affairs, with net worth in the title; the Shop and Books tabs are about one store, picked from the title bar across every company and city, with its trade's mark and its company's cash.
- **Contents and pages.** Each tab keeps a short summary on top, then index lines (a title, a line on what it holds, a key figure) that open pages within the tab, under a way back and above the clock and the tabs; the phone's back gesture closes them, and tapping the tab again returns to its start. The World tab leads with the country's economy (the phase of the cycle, inflation, the central bank's rate, unemployment, and prices, wages and buying power since the start), with competitors, cities and the economy's history as pages; Holding lists the stores, one line each, with the way to start a new business on any vacant site, then last week's story, the news and profit as pages; the shop's running and supplies, Finance's accounts, taxes and deals, and the books' parts of a period are pages too. Pages are laid out whole rather than lazily: a lazy list under a closing dialog trips Flutter's semantics.
- **Net worth** is the player's cash plus each company's net assets at book value (cash, stock at cost and stakes, less unpaid bills and loans; fitting out and works are spent). Moving money between the player and their companies leaves it unchanged, so only profit moves it: its history is worked back from today by the combined profit of each later week or month, from the reports already kept, with nothing saved.
- **Screens**, on five tabs (Holding, Shop, Finance, World, Books), with the date, the cycle's phase and the clock in a bar above them:
  - *Holding:* a masthead (how many companies, stores and cities, net worth, this and last week's profit, net worth over the past weeks or months); what needs doing, as notes with a red margin that open the right part of the shop; how last week went, in a few sentences (profit against the week before, the lines that moved it, trips won from or lost to each rival on balance and why, the biggest missed sales); key figures under rules; the player's companies, each with its stores, who runs it and its cash, opening its page, with the offer of a director for a company without one and of a subsidiary (a separate company, its first store opened from the vacant sites); a ruled entry per store with its trade's mark, status, warnings stamped in red, shoppers, sales and margin this week and a line of shoppers; the news, products sold out and deliveries turned away grouped into one line a day per store; and profit by week or month as bars with the best and worst.
  - *How to play:* a short guide to the aim, time, each tab, buying and selling businesses, and tips, from the main menu or the game's menu.
  - *World:* every company trading, the player's own first, then rivals in the player's cities, then the rest, with their public accounts, formats and cities, each store's site, size, products and prices against what shoppers there expect, each rival store's asking price with a button to buy it, and each rival company's price with a button to buy it whole (opening a store and both purchases offer to borrow what the company lacks beyond its cushion, rounded up to a hundred, for one to seven years, with the bank's rates, any part guaranteed by the player and about what the first month costs; on by default when the cash falls short, and an option when it would only eat the cushion); the cities, with their levels, households, stores and vacant sites to open on; and the economy and its history at the bottom.
  - *Shop:* in three parts. *Shelves*, first: per product the format sells its price (tap to change), cost from the cheapest supplier, margin, rivals' prices, a bar of how many days of sales the stock and what is coming cover, sales and misses over 7 days, and a switch to stock it or stop. *Supplies*: below. *Running*: the store's header (name, renamed from a dialog that can rename the company too, status, format, site and location, shelf slots and storage used, the floor area with a button to enlarge it), staff per slot with shoppers, service and wages, the manager (hire, change the brief or let go), the marketing slider with its daily cost, and becoming a supermarket. Whatever the manager looks after is locked, with a note saying so; the supplies say when the manager reorders, and the holding stops asking for what the manager does. It asks instead when a company whose managers reorder has less free cash than its cash cushion, since they then buy only the essentials. A manager's commands that the engine refuses become news of their own, which doesn't pause the clock by default.
  - *Supplies* (in the shop): the terms of the suppliers of what the store's format sells, an order sheet per supplier with a suggestion (a week's sales after delivery, or the shelf life if shorter, less what will be left by then, in whole minimum orders, scaled to the free storage; without history, the scenario strategies' opening forecast), orders on their way, and unpaid bills.
  - *Finance:* with several companies, a line opening all of them added up; each company's page, also opened from the Holding: its director first (hire, change the brief or let go), then its financials (see Company financials), then its accounts (cash, money spoken for, free cash, its cash cushion with a sheet that sets it to one, two or four weeks of wages and shows each store's share, the loans' next payments and the year's tax, profit kept, what the bank lends on the stores' earnings and on the player's guarantee, loans) with buttons to add capital, pay a dividend (saying what the state takes), borrow (a sheet that keeps to what the bank lends, with loan lengths of one to seven years and the first month's payment) and repay, and its director's letters; the taxes; rival stores going cheap (losing money, cheapest first) with a button to buy each; and, for each of the player's stores, what it would sell for and the buyer named.
  - *Books:* week or month, with profit per period as bars (tap one to read it), a "what happened" summary against the period before (profit change, the three lines that moved it most, where regulars went and why, the biggest missed sales), the profit and loss with a bar of where the sales went (goods, wages, rent, other costs, profit), shoppers gained and lost per store and cause, results per product, and market research to buy and read.
- **Company financials.** Worked out in the app, in `financials.dart`, from month reports, filings and balances, with no change to the engine; rivals only publish sales, profit and stores, so World keeps to their net margin. A company's page leads with four key figures against the year before (sales, operating margin, net margin, ROIC), net profit each year as bars, and lines opening the profit and loss, the balance sheet and the years.
  - *Spans.* The last twelve complete months; a company with fewer shows everything since founding, the running month included; a liquidated one its last twelve, with no comparison, as its last month is cut short and debts forgiven count as income. Reports are kept for 24 months with the running one, so the year before usually holds 11 months: amounts are scaled to twelve and it says so, and under six months there is no comparison. Older years have only what was filed (sales, net profit, stores), so margins and ROIC stop where reports do.
  - *Margins.* Gross is sales less goods sold and spoiled. Operating also takes off staff, rent, overheads, marketing and research, and so comes before interest, fit-out and works, tax and one-offs. Net is the report's profit, and the statement adds up to it exactly.
  - *ROIC* is operating profit less the tax billed in the months, at a year's rate, over the money tied up averaged across the month-ends. Money tied up is fit-out and works at cost, plus what was paid for bought stores beyond their stock, plus stock, less unpaid bills, rolled back month by month through what each report posted. Equity plus loans less cash would not do: fitting out is an expense here, so a shop's books show almost nothing invested. The store the game began with never went through the books, so its fit-out is added as it began (`GameStart`, read by the controller from the world, or the scenario), since a later conversion is among the works. No wear is taken off, and fit-out stays in after a store closes or sells, so an old or shrunk company reads a little low. A corner shop's ROIC comes out around 100%, since 30,000 of fit-out earns 30,000 to 60,000 a year; a bought store's is far lower. No ROIC before 90 days, with nothing tied up, or for a liquidated company.

## Countries by formula (`countries/`)

A second, far cheaper level of the economy, in its own library (`package:engine/countries.dart`), so that the game doesn't touch it yet: nothing in `engine.dart` exports or calls it, and it changes no state hash. Where the shop level simulates households and shops day by day, this level runs whole countries month by month from their statistics, with no shoppers, no shops of their own and no dice in the demand. Four countries take 60 to 80 µs a game month on a desktop VM, against 1.3 to 2.2 ms a game day for one simulated neighbourhood.

- **The table** (`content/countries/euro.json`, built by `build_euro.py` from Eurostat's API) gives each country its households, five income classes with what each earns and spends per trade, each trade's cost structure and shop count, its growth and how it takes the cycle, its corporate tax and its chains. Chains are fictional; their shares follow the real market's structure. The currency is the euro throughout, as the engine has no currencies yet.
- **Spending** per class and trade is households × the table's spending × real spending since × the price index × the cycle, a twelfth each month. Real spending follows real income by each trade's income elasticity, fitted across the classes. The cycle is the shop level's regimes, shared, cut to the size real ones have (`amplitude`) and scaled by how the country and the trade move with consumption.
- **Chains** are blocks: stores, a price against the trade's average, a pull fitted so that the table's shares come out, cash, and real monthly books. A class divides its spending in proportion to stores × pull × a price term, with rises punished more than cuts reward, more so for poorer classes. Sales add up exactly to spending. A failed chain's stores pass to the independents.
- **Costs** come from the structural business statistics: goods, staff and everything else as shares of sales. Part of the staff and all the premises go with the stores, whatever they sell; the rest with sales. Every business starts at the trade's real margin.
- **Openings and closings** follow the gap between a chain's margin and what's normal in the trade, so margins come back to normal over time. A rate makes them due; chance only decides when a fraction falls, so one event is never multiplied.
- **Why sales moved.** `yearOnYear` splits a chain's change into population, income, prices, the cycle and share, adding up exactly.
- **Calibration.** `tool/calibrate_countries.dart` runs the full simulation and writes `content/countries/calibration.json`: what shops capture of what households want, how much of staff goes with being open, and the price response, from controlled runs (below). A test fails if the formula and the full simulation drift apart, which is the signal to run it again after a balance change.

Not there yet: saves, chains that decide anything (prices are set from outside), entry of new chains, the player, and zooming in: generating a neighbourhood from its row, with its households taken out of the row so totals still add up.

## Neighbourhoods from figures (`neighbourhoods/`)

The way to bigger cities and to zooming in from a country: a neighbourhood built from a row of figures and a seed, rather than by hand, and simulated only once the player trades there. `generateScenario` takes a scenario and rows, and returns the scenario with its cities replaced, so everything that plays a scenario can play the result (`tool/generate_neighbourhoods.dart`, then `tool/sim.dart --scenario`).

**Asleep and awake.** A scenario's `neighbourhoods` start a game as rows, with no market, site, store or person, and run by formula until the player trades there. `WorldState.sleepers` holds each one's households and its shops (`state/sleepers.dart`): who they are, how big, what the shop and its owner hold, and twelve months of sales and profit. Its sites come from the row and the seed, so they aren't kept.

`SleeperSystem` (`systems/sleepers.dart`) runs last, on the first of each month:

- Households grow by the row's rates and the regime's migration, as `PopulationSystem` would have them.
- What they spend on each channel (`tradeDemand`), at the regime and confidence of the day, buying dearer as real wages rise and trading down by the regime's `premiumShift`, is shared among that channel's shops only, by location, size and price (`shopPull`, `priceDraw`), a shop in its first two years drawing 0.8 of what an established one does.
- Each shop books its sales, goods, staff, premises and marketing. Tax comes off a profit; what's beyond a working reserve goes to its owner, and a loss falls on the company, then on the owner. How settled shops turn demand into sales and what their goods and busiest hours cost are fitted by trade (`_settled`), and they aren't the same as `ShopHabits`, which describe a new shop for `shopOutlook`.
- A shop closes as `losingStore` would have it: two years old, and more than 3% of a year's sales lost. It also closes when its owner's money runs out. And real shops scatter around what the formula gives them, so one earning under 3% of its sales may close anyway: a 3% chance a month at no profit, scaling with its margin.
- A grocer short of shelves enlarges when a year's profit, beyond what the extra room would cost, is twice the works' cost, and then 8 and 18 times, as each round of shelves holds what sells less. Restaurants and electronics shops have the shelves they need.
- With a chance of 3% a month for every 2,000 households, someone takes the free site that would pay back soonest by the entrepreneur's rule, if it would within the strategy's limit.

There are no purchases, chains or conversions to supermarkets in the formula: each shop stays its own company, and no bot or owner decides anything. The sleepers touch nothing else. They stay out of `world.write`, so a game plays the same with rows as without; `stateHash` adds them only if there are any, and a save writes them after the pending commands.

`Simulation.plan` is the content with every sleeper generated as it stands, remade each month, for screens and estimates and for nothing else. `WakeNeighbourhood` adds one for real: its row is generated with the formula's households and shops in place of the ones it started with, appended at the end of the content's lists, and `growWorld` brings the world up to that content, as it does when a saved game meets a scenario that has grown. A store's optional `area` in a scenario takes it beyond its site's, with the shelves and storage each round of works adds, which is how shops take back their size; those over two years old are as well known as any established shop. Waking shops charge settled prices, as `plan` shows them, where a world just begun charges around normal ones. It takes effect as it is submitted, not with the day's commands, as those may refer to its sites. A save's header lists what woke, with its households and shops at that moment, so the content can be grown to match before the rest is read; a replay wakes them from the command log.

A row (`NeighbourhoodRow`) holds households and growth by segment, the price, wage and income levels, a month's rent per m², a grocer's usual and largest area, and how far a site can grow. `rowsFromScenario` reads today's cities that way, and nothing else of them gets through. From a row:

- **Cohorts** are 250 plus 11% of the households, to the nearest 50, which is what the seven cities have. Fewer break the economy.
- **Grocers** number 2 plus one per 400,000 of the neighbourhood's yearly margin on groceries, with 2 plus one per 1,500 households of sites left vacant. Sites form a ladder of locations from 0.60 to 0.40, a quarter of them a step off. A better location is bigger, with shelves by area, 15 units of stock per m², and rent and fitting out that rise with both. Grocers take the best sites and follow premium, balanced and discount in a seeded order. If the largest site has room for a supermarket, it is one, at discount.
- **Other shops** open where they would pay: what a shop alone would keep of its sales, from households' spending at the strategy's own markup, less waste, the staff such a shop settles at, rent and overheads, must reach 8%. One restaurant site stays vacant.
- **The player** keeps their store, prices and cash, on a site of usual size at a location of 0.50 with a tighter stockroom (12.5 units per m²). Their rivals spread along the ladder instead of holding its top, and none starts at discount. Their old city was built that way.
- **Starting shelves** are the staples, which the scenario lists first, two slots short of full, for the owner to choose the rest. A strategy favouring premium goods takes them first; a discounter takes every category's cheaper line first.
- **Owners** each have one company, with cash in proportion to its site's fitting out.

Names are drawn from short lists, the same in every language. Rows don't yet come from a country's table: the country level has five income classes and the shop level six segments, and nothing maps one to the other.

## Testing and the headless runner

| Test | What it checks |
|---|---|
| Core math goldens | `Money`, `Fx`, `mulDivRound`, RNG, and hashing produce committed values under both `dart test -p vm` and `dart test -p node` |
| Determinism goldens | A scenario, seed, and scripted command list run for 365 days match committed daily state hashes on both VM and Node |
| Save/load continuity | 365 days straight gives the same hash as 180 days, then save, load, and 185 more days |
| Replay | Seed plus command log reproduces the original run's hash |
| Invariants (every tick in debug) | The ledger balances; company cash matches ledger cash; no inventory is negative; all values are within ±2^53; household count is constant |
| Forbidden APIs | The source scan described under Core primitives |
| Period reports | Weeks and months start on the right days; their flows add up to the company's balances; visits, sales, switches and misses match the daily attribution and ledger; they survive a save and keep 13 weeks |
| Enlargement | Paid at once, the space comes in use when the works finish; refused beyond the site, during works or without the cash; rent follows the area; closing ends the works; bigger stores draw more trips and switches are attributed to size; AI owners enlarge full stores on the first of the month up to the site's limit |
| Managers | Hiring, rebriefing and firing are validated; salaries are paid daily; a manager of full skill decides exactly as the owner's `RetailPolicy`; managers stick to their duties; they enlarge a full store only when trusted with investing; briefs from before investing read with it off; the cash cushion adds each store's wages, salary and rent, the loans' next payments and the year's tax, which the January bill matches; it is set by the owner, kept in saves and two weeks in older ones; managers order in full only beyond it, and below it a few days of each line from cash not owed yet; misjudgment stays within skill's share of the error; a managed game replays and loads to the same state hash; closing a store lets its manager go; with pricing they market at the strategy share unless the owner chose one |
| Directors | Grades load, or none; hiring, rebriefing and letting go are validated, and refused without directors; salaries are paid daily and held in the cushion; their managers keep 1 − skill × coaching of their misjudgment, so full skill and full coaching leave a clerk deciding exactly as the owner's policy; a director hires a manager, with every duty but investing, for each store without one; closes a store that lost money over its last year two years after it opened; enlarges only if the brief allows; on the first of the month opens a store at the best vacant site from the company's cash, saves for one it can't pay for yet, pays the owner the profit kept as far as cash allows, and does neither unless the brief says so; memos are kept only once their commands are carried out, survive a save with the brief, and read back as written; allowed to borrow, they borrow what a store or works lack in whole thousands, on the earnings and over the longest term, nothing while the company has the cash, and save if the bank won't lend; they buy a profitable rival the bank will lend for, leave one alone without saving for it if it won't, and never otherwise; briefs and memos from before loans read with none |
| App controller (`flutter test` in `app/`) | Net worth adds the player's cash to every company's net assets, combined profit adds up each company's reports, opening a second company leaves net worth to profit alone, and its history steps by each period's profit; pending changes replace and cancel each other; the next step applies them; refusals, month ends and pausing news; the clock's speeds and week runs; saves load back with their summary; a new game starts where the player chose; buying and selling stores make the news; a pending manager shows as it will be; a hired manager keeps the store stocked and priced; only what needs the player pauses the clock, a store a manager restocks makes no sold-out or delivery news, and a record month is told |
| Incomes | Spread and effect load, with validation; incomes spread evenly and purchasing power follows real wages; ranks follow from the seed and survive a save without being in it; better-off households stick with a dearer store; rising real wages raise the premium share and lower the price sensitivity research reports; owners hold dividends while saving for works |
| Population | Growth and migration rates load, with validation; fewer cohorts can stand for the same households; a cohort shops for all its households and an empty one not at all; 12% a year takes 60 households to 67 by the January census; emigration takes one household a month at 2%; studies count the households cohorts stand for; a format 6 save loads and plays on |
| Growing saves | A saved game loaded into content with a new category, its products and a new segment gains them (stores price, stock and count the products, households need the category, the town gains the segment's households and a census), then lists, sells and reports the new products; one loaded into content with a new city, site, person, company and store gains them on its day, with the money supply and invariants intact, a census for the city, and households who know every site; the newcomer's AI runs its store and villagers shop there; the grown save loads back unchanged; renamed sites, products or segments, and shrunk lists, are refused; a format 8 save grows like a current one; a format 6 save grows too and is refused content with a site fewer |
| Market levels | Levels load, from 0.3 to 3 and 1 by default; a price far over the reference sells in a dear market and not in a usual one; wages follow the wage level; richer markets mind price less in research |
| Local shopkeepers | A person marked local runs their store but never opens another, whatever the payback |
| Reputation | Its settings load, and are off by default; rivals' stores start known and the player's and any opened later new, as their owners see; it builds with stocked shelves and wears away with empty ones; a store with a better name draws more shoppers |
| Formats and marketing | Formats load, each category sold by exactly one, and stores list only their format's products; a diner costs its fit-out factor; households eat out at diners and shop for groceries at grocery stores; staff serve as many customers as the format says; an entrepreneur opens its strategy's format; marketing is a share of sales set within limits, paid daily, builds goodwill that wears off at the decay rate, survives a save, draws shoppers from a store that does none, and is the strategy's share for an AI owner |
| Overheads and closing | A format's overheads are billed with the rent once a month for the floor area, to the services, and go into the store's running costs and profit; an owner closes a store that lost more than 3% of its sales over its last twelve months two years after it opened, on the first of the month, and keeps one that about broke even, is younger or until the first; a new company is backed for two years, then only one that has made money; though paid on the first, they're counted day by day in the reports, a week with the first in it bearing only its share |
| Borrowing | Without a guarantee the bank lends `earningsMultiple` years of the stores' earnings less what they owe, and says how much; a guarantee adds twice the owner's cash and the two don't draw on each other; a store bought on credit borrows on earnings first, its own included, then on the guarantee; a loan refused buys nothing; a new company borrows only on a guarantee; a company bought on credit borrows on its own earnings, the buyer pays the rest and the seller is taxed on the whole price; purchases with loans replay and older commands read with none |
| Acquisitions | A new store asks what it holds and a trading one adds capitalised excess earnings; one losing money asks half what it holds; a company asks its stores plus cash less debts, a symbolic euro when it owes more; nothing is priced without `acquisitions`; buying a rival store moves its stock, orders and books, and the rival can't take it back; only the player sells the player's stores; selling finds the best funded AI owner of the format, who tops its company up; no buyer, no sale; buying a whole company pays the seller, taxes the gain and moves the guarantees; a company wound up sells its stores; an expanding owner buys a struggling rival after a year, never the player's |
| Game start | Free sites include the player's own; the classic start's terms are the scenario's; a cheaper store leaves more cash, a dearer one takes the player's, and one beyond both, a taken site, a site too small or a bad name is refused; a chosen start opens there with the format's usual prices and staff and saves, loads and replays the same |
| Economy | Unemployment heads for Okun's target in a slump and the Phillips curve holds wages back; confidence cuts spending; the economy is recorded month by month for everyone; a year's profit is taxed in January at the reduced and full rates, losses carried forward; every company files its accounts; dividends pay the flat tax to the government |
| Models | Bass diffusion follows its closed form; loss aversion makes a dear store lose more shoppers; a convenience store becomes a supermarket through works, paying the fit-out difference and the area, gaining the format's slots and storage; conversion is refused on a small site or to the same format; a supermarket competes for the same grocery trips |
| Renaming | Owners rename their stores and companies within the name rules, everyone sees the names, and replays keep them; daily visits and sales add up to the recent totals |
| App screens | On a phone-sized screen with the margins: the main menu setting up a new game on a chosen city, site and business, saving it in a slot, returning to the menu and continuing it; a game that can't be loaded set aside and its slot freed; the guide; buying a rival store from the Market tab and selling a store from its screen; the Market tab's economy, history, taxes, competitors and cities, opening a restaurant with its format picked, the marketing slider, becoming a supermarket once affordable, a restaurant listing only dishes, the holding's header, a card per store that opens it and the title bar's store picker, the dashboard's to-dos and cities, setting a price, staffing, ordering with a suggestion, play and pause, reports and research for a city picked, hiring a manager who then locks the prices, hiring a director from the company page who then writes a letter, the dashboard leading with the last four weeks' trading profit and its change and the last weeks as bars, enlarging the store, renaming the store and its company; loading the bundled scenario |

The **headless runner** (`tool/sim.dart`, run from `packages/engine`) plays each strategy bot in the player's seat for many seeds, one isolate per run. A bot named `<strategy>@<grade>` leaves the player's store to a manager of that grade, and `<strategy>#<grade>-<growth>` hires a director of that grade who grows the company as far as `<growth>` allows, hires experienced managers and pays the profit out:

```bash
dart run tool/sim.dart --scenario prototype --seeds 1-100 --days 5000 --player idle,discount,balanced,premium --out runs
```

It writes `runs/<bot>/seed-<n>.csv` with daily metrics for every store that has existed: the regime, company, status, listed products, staff, price index (against reference prices at today's price level), visits, units sold, revenue, cost of goods, write-offs, wages, rent, units missed by reason, stock, and cash. `runs/companies.csv` has one row per run and company (founding and liquidation days, revenue, gross and net profit, dividends, cash), and `runs/stores.csv` one per run and store. The console summary reports, per player bot, how the scenario's companies fared, how many stores opened and companies failed, how much of the time the economy spent in each regime and how far prices rose, and scores prototype success criteria 1 and 2:
- **Stability:** a store is flagged if its price index leaves 0.7–1.4 after its first 60 days, or it goes 30 open days without a sale (unless its company is being wound up: that is how a failing store dies). A run is flagged if one company takes over 70% of a city's visits in the final year, or a city has fewer than two stores left trading. The summary also gives each city's households, stores trading and stores opened by the end. Stores that lose out and fail are competition, not instability: they show up as liquidations.
- **Profitability:** the strategies whose company made a net profit and never went bankrupt in every seed.

**Performance targets:** 5,000 days for one seed in under 10 seconds on a desktop VM, and one tick in under 5 ms on a mid-range Android phone. The single-city prototype ran 5,000 days in about 9 seconds; the seven-city prototype, with about 12,000 households in 3,100 cohorts, 42 stores and 25 AI owners, takes 5.0 ms a day on a desktop VM (25 seconds for 5,000 days), over target but well within the app's fastest speed of four days a second. `tool/profile.dart` times each tick system, the AI decisions and the rest:

```bash
dart run tool/profile.dart prototype 2000
```

Demand is about 60% of a day. What made it cheaper without changing a single result (the determinism goldens hold): each day's shopping precomputes what every household of a segment accrues, each store's pull of size and the slot it serves for each preferred slot, the stores each segment can shop at, and each market's reference prices; trips share their scratch lists; a keyed RNG hashes its key once rather than four times; and choosing why a household switched needs no map. Every AI's and manager's observation shares one view of what is public, built once a day (vacant sites in one pass rather than a search per site). Together they cut a day by a fifth; more households cost cohorts, not households, so cities use the `agents` setting.

### First balancing pass (build step 5)

Ten seeds of 5,000 days per player bot, on the prototype scenario as committed. Profit is gross profit per year; share is the share of visits in the final year.

| Player bot | Player profit, share | QuickStop (balanced AI) | Daily Basket (premium AI) |
|---|---|---|---|
| discount | 75k, 59% | 56k, 29% | 28k, 13% |
| balanced | 70k, 36% | 99k, 46% | 43k, 18% |
| premium | 53k, 23% | 133k, 58% | 46k, 20% |
| idle | 0 | 149k, 58% | 62k, 23% |

- No store was flagged. Prices settle within the first year and then hold steady, stockouts stay at about 1%, and spoilage at 0–5%. Seeds differ by only a few percent.
- Every strategy is profitable. Premium earns about 70% of discount: the premium half of "premium/convenience" works, but the convenience half (opening hours and service) arrives with staffing in build step 7.
- What the pass changed: AI stock targets keep goods in transit out of the storage budget; households have a proximity to each store; loyalty starts at a neutral level and fades back to it. Retuned values: the loyalty weights, QuickStop's markup (0.75) and its location (0.60).

### Second balancing pass (build step 6)

Rent now stands in for all overheads until wages arrive: 1,800 a month at the player's corner, 2,500 at QuickStop's prime site, 1,300 at Daily Basket's. Two sites are vacant, and Samir Haddad, an entrepreneur with 80,000 and the discount strategy, looks for one. Ten seeds of 5,000 days per player bot; profit is net profit per year, after rent and opening costs.

| Player bot | Player profit, share | QuickStop (balanced AI) | Daily Basket (premium AI) | Entrant |
|---|---|---|---|---|
| discount | 29k, 41% | 7.6k, 18% | 2.7k, 9% | 21k |
| balanced | 11k, 19% | 23k, 26% | 11k, 12% | 40k |
| premium | 9.6k, 13% | 28k, 29% | 9.5k, 11% | 45k |
| idle | bankrupt after about 7 months | 36k, 27% | 9.5k, 11% | 41k |

- Nothing was flagged, and every player strategy made a net profit in every seed. Discount earns about three times what balanced or premium do.
- In every seed the entrepreneur opens at Mill Lane, the cheap back street, within the first month and earns more than any incumbent. After that, the estimate rules out the dearer Station Road, so the market settles at four stores. The idle player's company is liquidated on unpaid rent, and an AI reopens its site.
- What the pass changed: AI owners expand only while in profit and a year after their latest opening, each on its own day of the month; rents came down about 30%; entrants assume 0.45 of margin per household a day.
- Open for step 7: the market is static once entry settles. Business cycles and wages should bring the failures and re-entries that "a living economy" needs.

### Third balancing pass (build step 7)

Wages now carry most of the overheads: 10.00 per staffed slot a day at the start, rising with the wage index. Rents fell to about a third (600 a month at the player's corner, 850 at QuickStop's, 450 at Daily Basket's). The economy cycles through four regimes; recessions cut consumption 12% and push households toward budget products. Ten seeds of 5,000 days per player bot; profit is net profit per year after wages, rent and opening costs.

| Player bot | Player profit, share | QuickStop (balanced AI) | Daily Basket (premium AI) | Entrant |
|---|---|---|---|---|
| discount | 16k, 39% | 5.6k, 17% | 1.6k, 13%, failed in 1 of 10 seeds | 8.3k |
| balanced | 7.4k, 18% | 18k, 23% | 10k, 18% | 21k |
| premium | 6.7k, 17% | 20k, 25% | 6.0k, 15% | 25k |
| idle | bankrupt after about 7 months | 26k, 24% | 8.3k, 16% | 19k |

- Nothing was flagged, and every player strategy made a net profit in every seed. Over 13.7 years the economy spent about 53% of the time in expansion, 14% in slowdown, 18% in recession and 15% in recovery, and prices rose about 30%. Shelf prices track the price index: balanced stores sit at about 0.99 of inflation-adjusted reference prices, discount at about 0.83.
- Entry settles at four stores: the entrepreneur opens at Mill Lane in the first month. Against the discount bot, Daily Basket lost money over its life in one seed and was liquidated; rescues keep profitable companies alive through recessions.
- What the pass changed:
  - entrants budget for wages and two weeks of stock, and wait out the expansion interval after a bankruptcy;
  - the dividend reserve counts wages;
  - owners rescue companies that have made money;
  - entrants assume 0.40 of margin per household a day;
  - recessions last about a year, with demand at 0.88 and a 10-point shift to budget products.
- Discount remains about twice as profitable as balanced or premium for the player. Premium's night hours cost wages and win few shoppers; whether convenience can pay is a question for playtests and the UI's legibility.
### Incomes and the fourth balancing pass

The diagnosis: store choice was decided almost entirely by price. Discount stores got two and a half times the shopping trips of premium ones, a 41% gross margin couldn't make up for it, and every household of a segment chased the same cheapest basket. The pass changed three things:

- **Price sensitivity cut by 40%** (families 6, professionals 2.4, students 4.8, retirees 3.6), so location, hours, service and size weigh against price.
- **Household incomes** spread within each segment (families ±40%, professionals and retirees ±50%, students ±30%), with half the change in real wages reaching purchasing power. The 40% cut alone already gave most of the balance; the spread keeps premium stores' better-off shoppers and makes discount win the hard-pressed.
- **AI owners save for works**: they paid every spare cent in dividends before checking whether an enlargement paid, so a profitable discount or premium store never had the cash to grow, while rivals on cheaper sites did. Owners now hold dividends until worthwhile works are paid for.

Strategy bots in the managed runs now make the owner's calls (enlarging, dividends) and leave the rest to the manager, as a player would. Since managers can invest, those bots leave enlarging to the manager too.

| Player bot | 15 years, 8 seeds | 40 years, 6 seeds | Entrant, 40 years |
|---|---|---|---|
| discount | 22.7k | 30.0k | fails against the discount bot (5 liquidations in 6 seeds) |
| premium | 19.9k | 25.5k | 32k |
| balanced | 17.1k | 20.3k | 28k |
| discount, experienced manager | 18.2k | 22.8k | |
| premium, experienced manager | 15.5k | 19.2k | |
| discount with a trainee / expert | 12.6k / 19.3k | | |

Net profit per year. Nothing was flagged and every bot made a profit in every seed. The three strategies now sit within 1.5 times of each other, against 5 times before; the premium AI earns 15 to 20k instead of struggling, and QuickStop, with two stores from about year 15, 40 to 55k.

### Living population (40-year games)

The prototype town grows by segment (families 0.6% a year, professionals 1.2%, students 0.4%, retirees 1.0%), plus migration of 0.4% in expansions, 0.2% in recoveries, none in slowdowns and −1.2% in recessions: about 0.8% a year in all. Six seeds of 40 years per player bot:

| Player bot | Year 1 | Year 10 | Year 20 | Year 30 | Year 40 | Stores | Failures |
|---|---|---|---|---|---|---|---|
| discount | 19.3k | 13.0k | 14.1k | 15.2k | 16.4k | 4 → 5 | Daily Basket in 3 of 6 |
| balanced | 11.5k | 9.2k | 8.8k | 10.6k | 15.0k | 4 → 5 | none |
| premium | 10.8k | 0.8k | 2.2k | 0.7k | 8.4k | 4 → 5 | none |
| discount, experienced manager | 15.9k | 5.8k | 5.0k | 5.7k | 6.3k | 4 → 5 | the player in 1 of 6 |

Player net profit per year, in money of the day (prices rise about 2.2 times over 40 years).

- Without growth, the same games showed the long-run problem: real wages rise about 0.6% a year while demand per household is flat, so every store's real profit shrank, the discount bot went from 19k a year to a loss by year 40, and the market froze at four stores. With growth, nothing was flagged and all three strategies made a profit in every seed.
- Households reach 1,360 to 1,460 after 40 years, depending on the recessions. The mix drifts toward professionals (25% to 29%) and away from families (35% to 31%) and students (20% to 17%), which slowly favours convenience over price.
- The pass found that entrepreneurs estimated demand from the scenario's opening households, so the town never looked bigger to them; with the census, QuickStop's owner opens a second store at Station Road between years 13 and 25.
- These games left the entrant's discount store dominant and premium weak; the next pass fixed both.
- A 5,000-day run takes 9 seconds, against 7 before: more households and a fifth store mean more trips and sales.

### Store size (build step 8)

Sites now have a selling area (Corner 120 m², Market Square 160, The Parade 110, Station Road 130, Mill Lane 90) and room to grow (to 170–280 m²) in steps of 40 m² that cost 150.00 a square metre, take 14 days, and add 2 shelf slots and 500 units of storage. Families weigh size at 2.5, retirees 2.0, professionals and students 1.0, with half the pull at 150 m². Ten seeds of 5,000 days per player bot:

| Player bot | Player profit, share | QuickStop | Daily Basket | Entrant |
|---|---|---|---|---|
| discount | 12.8k, 30% | 8.1k | 0.4k, failed in 3 of 10 | 13.9k |
| balanced | 7.8k, 17% | 17k | 5.0k | 32k |
| premium | 1.9k, 16% | 21k | 3.0k | 37k |

- Nothing was flagged and every player strategy still made a net profit. AI stores each grow once, until their shelves hold the whole range of 8 products; the entrant grows Mill Lane twice, to 170 m² and all 8 products, and earns far more than before.
- Size shifts the market toward stores that grow: the premium and discount bots, which rarely fill their shelves and so don't enlarge, earn less than in the third pass, and a manager-run store that never grows ends a balanced game near break-even (discount: 8.7k with an experienced manager, 10.9k with an expert).

### Managers (build step 8)

`<strategy>@<grade>` bots leave the player's store to a manager with every duty from the first day; the player never adds capital or takes dividends. Eight seeds of 3,650 days; net profit per year after the salary, against the owner-run bot of the third pass.

| Strategy | Owner-run | Trainee (skill 0.30, 3.00 a day) | Experienced (0.65, 5.00) | Expert (0.90, 7.00) |
|---|---|---|---|---|
| discount | 15.7k | 7.3k, 7% stockouts | 12.1k | 13.3k |
| balanced | 7.6k | 4.3k, 6% stockouts | 6.0k | 4.7k |

- Nothing was flagged and no managed store failed. Misjudgment is up to 80% of demand and 25% of price for a manager of no skill, redrawn weekly.
- The first try, with salaries of 8, 15 and 25 a day and smaller errors, made the expert the worst choice: its salary exceeded what better judgment saved, and balanced stores run by experts failed in 8 of 10 seeds.
- On a single store a trainee is cheap but sloppy (stockouts, spoilage), and experienced and expert managers come close to the owner's own results. Whether experts should pay off more clearly, for example across several stores, is for playtests.

### Cities

The prototype became four cities. Lyon, Croix-Rousse is the original neighborhood at the usual levels, with the player and three rivals. The others each have two founding rivals and fictional owners:

| City | Households | Levels (prices, wages, incomes) | Character | Sites |
|---|---|---|---|---|
| Lyon, Croix-Rousse | 1,000, mixed | 1, 1, 1 | the original market | 5, 2 vacant |
| Montpellier, Boutonnet | 950, mostly students | 0.95, 0.90, 0.85 | cheap rents, thin margins, night shopping | 4, 2 vacant |
| Bordeaux, Chartrons | 850, mostly professionals | 1.12, 1.10, 1.25 | dear rents, premium pays | 5, 3 vacant |
| Nantes, Rezé | 1,200, mostly families | 0.97, 0.95, 0.92 | big cheap sites, price-sensitive | 5, 3 vacant |

New cities use 300 to 360 cohorts; a second entrepreneur, with a premium strategy, joins the discount one. Eight seeds of 15 years, net profit per year:

| Player bot | Player | Lyon rivals | Montpellier | Bordeaux | Rezé |
|---|---|---|---|---|---|
| discount (expands) | 42k | 32k, 16k | 11k, 10k | 63k, 41k | 57k, 17k |
| premium (expands) | 41k | 72k, 24k | 11k, 13k | 63k, 40k | 75k, 29k |
| discount, experienced manager | 25k | 33k, 17k | 6k, 13k | 63k, 50k | 70k, 26k |
| premium, experienced manager | 27k | 71k, 24k | 6k, 11k | 62k, 50k | 74k, 28k |

- Nothing was flagged and every player bot made a profit in every seed. Expanding bots open their second store in Rezé after a year; a single managed store earns 25 to 27k, up from 15 to 18k with one city, because the entrepreneurs now open elsewhere first.
- Entry is fast: within 13 months most vacant sites outside Lyon are taken, by the two entrepreneurs (first days) and by established owners (once a year, if in profit). Bordeaux keeps room longest: its rents put entrepreneurs off, though its rich households make it the most profitable city, which research reveals. Two to six companies fail per eight seeds.
- AI owners and managers scale their markup by the city's price level. Before that, Bordeaux's stores priced 10% under what its households expected and earned half as much.
- Three changes during the pass: Rezé's retail park went from 260 to 220 m², since Le Goff took half the city and 90k a year; Montpellier's Arceaux corner became a five-slot, 95 m² site, since the discount entrepreneur failed there in every seed; and a fifth Montpellier site was dropped, since five stores left everyone there earning almost nothing.
- Montpellier stays the thin city: its founders earn 5 to 13k a year and occasionally fail.
- Four cities double the work per day: 5,000 days take about 22 seconds on a desktop VM (4.4 ms a day), against 9 with one city. Fewer cohorts for Lyon only gained 3 seconds; the ten AI owners each observing the world daily are the likelier cost.

### Seven cities and twelve products

The prototype grew to seven cities, twelve products and six household types:

- **Products.** Fruit and veg (bananas, organic apples, which spoil within days) and household goods (washing-up liquid, eco laundry pods, which keep and sell rarely but dear). Every site has two more shelf slots, so a store still chooses about two thirds of the range.
- **Households.** Working singles, the commonest household in French city centres (small baskets, evening and night trips, convenience first), and comfortable dual-income families (big baskets, premium-leaning, loyal, drawn to big stores) join the four segments. The old cities gain them; the new ones have their own mixes. Cities run 1,300 to 2,300 households in 400 to 500 cohorts.
- **Cities.** Lille, Wazemmes (a working-class market district: low incomes and rents), Marseille, Cours Julien (young and mixed) and Paris, Batignolles (rich and dense, with fit-outs over 60,000 and rents of 4,500 to 6,300 a month) join, three rivals and three vacant sites each. Every older city gains a rival and a site; Lyon two sites.
- **Rents** were raised where margins are fat, since supplier prices are national and a dear city's markup is pure margin: Paris three times its first figures, Bordeaux 1.8, Rezé 1.6, Marseille 1.25, Lille 1.2, Lyon 1.1. Paris and Bordeaux price and income levels came down a notch.
- **Entry.** Most rivals are local shopkeepers (`local`); five chains and three entrepreneurs expand. Entrepreneurs estimate 0.55 of margin per household (0.40 before, with half the categories), scaled by the market's income level as well as its price level, and established owners wait two years between openings and between enlargements. The entrepreneurs open three stores in the first month; chains start expanding in the third year; the cities fill by the fifth.

Eight seeds of 15 years, net profit per year:

| Player bot | Player | Typical rival store | Paris rival stores | Liquidations |
|---|---|---|---|---|
| discount (expands) | 50k | 20 to 60k | 80 to 130k | 0 |
| premium (expands) | 80k | 20 to 60k | 75 to 115k | 0 |
| discount, experienced manager | 38k | 20 to 60k | 80 to 135k | 0 |

- Nothing was flagged and every bot made a profit in every seed. Expanding bots wait two years like the chains, open their second store at the start of the third year, and earn 70 to 110k a year by the fifteenth; a player who doesn't wait has two years of vacant sites to choose from.
- Montpellier and Lille's premium night shop stay the thin end (12 to 30k); Paris, behind its fit-outs and rents, is the prize, its best premium site earning over 130k.
- Before the rent and entry changes, every site in every city was taken by the second year and Paris stores made up to 280k: the richer baskets had outgrown the old rents.

### Restaurants and marketing

Three restaurant formats join the grocery store, each a channel of its own: households eat out by type and income (students and singles at fast food every week or two, professionals and comfortable families at a steakhouse a few times a month, fine dining for the better-off now and then), apart from their grocery runs.

| Format | Dishes (ingredients / reference price) | Fit-out | Customers per staff | Crew cost |
|---|---|---|---|---|
| Fast food | burger menu 2.60 / 8.90, gourmet burger 4.20 / 13.90 | ×1.6 | 25 | ×5 |
| Steakhouse | bavette 6.50 / 18.90, rib steak 13.00 / 32.00 | ×2.0 | 12 | ×5 |
| Fine dining | lunch menu 11.00 / 39.00, tasting menu 28.00 / 95.00 | ×2.8 | 6 | ×5 |

Every city opens with two or three restaurants on sites of their own, and keeps one vacant; two restaurant chains and a fine-dining entrepreneur expand. ChefSupply Wholesale sells the ingredients, a day away, in fours. Every strategy markets: groceries 1 to 2% of expected sales, restaurants 3 to 4%.

What the pass found:

- **Rare purchases were never made.** Need was capped at seven days' worth, so anything bought less than weekly never reached a whole unit: household goods, milk and bread for singles, snacks for retirees, and every meal out. The cap is now at least one unit, which roughly doubled grocery profits and needed nothing else: the earlier balance had been made without those sales.
- **Households ran out together.** Starting with no need, every household of a segment reached its first meal out on the same day, so restaurants sat empty for weeks, then turned crowds away while stock spoiled. Rare purchases now start part-way.
- **Labour was too cheap for restaurants.** At a shop assistant's wage a fast food made 300,000 a year; crews now cost five times as much, about a third of a restaurant's sales, and eating out was halved to realistic rates.
- **Fine dining wasted half its stock** on ten-cover minimum orders with two-day shelf lives; orders come in fours and keep four days. Its crews then came down from seven times a shop assistant's wage to five, and the better-off eat it a little more often, since Lyon's and Marseille's failed in every seed.
- Paris's price and income levels came down to 1.12 and 1.15: its best grocery store made 220,000 a year.

Eight seeds of 15 years, net profit per year:

| | Lyon | Montpellier | Bordeaux | Paris |
|---|---|---|---|---|
| Fast food | 80k (a chain) | 39k | | |
| Steakhouse | 54k (a chain) | 11k | 60k | 83k |
| Fine dining | 48k | | 89k | 136k |
| Best grocery store | | | | 164k |

- Nothing was flagged and every player bot made a profit in every seed: 46k for a managed single store, 100k (discount) to 142k (premium) for a player who expands, 150 to 200k a year by the fifteenth. One to four companies fail per eight seeds.
- Cities fill by the tenth year: 64 businesses on 64 sites, from 37.
- A day takes about 6 ms on a desktop VM with 40 AI owners and up to 64 businesses.

### Models from the literature

The engine's behavioural rules follow published models, adapted to integer arithmetic:

| Rule | Model | Source |
|---|---|---|
| Store choice | Multinomial logit: the chance of a store is `exp(U)` over the sum | D. McFadden, "Conditional logit analysis of qualitative choice behavior", in *Frontiers in Econometrics*, 1974 |
| Price perception | Reference prices and loss aversion: a price above what households expect hurts 1.5 times more than one as far below helps | D. Kahneman and A. Tversky, "Prospect theory: an analysis of decision under risk", *Econometrica* 47(2), 1979; A. Tversky and D. Kahneman, "Loss aversion in riskless choice", *QJE* 106(4), 1991 (λ ≈ 2.25); G. Kalyanaram and R. Winer, "Empirical generalizations from reference price research", *Marketing Science* 14(3), 1995 |
| Advertising | A goodwill stock: `G' = (1 − δ)·G + spend`, its pull concave in `G` | M. Nerlove and K. J. Arrow, "Optimal advertising policy under dynamic conditions", *Economica* 29, 1962 |
| Advertising's decay | δ = 2% a day, a half-life of about a month, inside the three to nine months in which 90% of an effect wears off | D. G. Clarke, "Econometric measurement of the duration of advertising effect on sales", *Journal of Marketing Research* 13(4), 1976 |
| Advertising budgets | A steady advertising-to-sales ratio per strategy (1 to 4%), the policy shown optimal for a firm | R. Dorfman and P. O. Steiner, "Optimal advertising and optimal quality", *American Economic Review* 44(5), 1954 |
| New products | Bass diffusion: `F(t) = (1 − e^{−(p+q)t}) / (1 + (q/p)·e^{−(p+q)t})`, with p = 0.03 and q = 0.38 a year, close to the averages found across durables | F. M. Bass, "A new product growth for model consumer durables", *Management Science* 15(5), 1969; V. Mahajan, E. Muller and F. M. Bass, "New product diffusion models in marketing", *Journal of Marketing* 54(1), 1990 |
| Interest rates | Taylor rule | J. B. Taylor, "Discretion versus policy rules in practice", *Carnegie-Rochester Conference Series on Public Policy* 39, 1993 |
| Unemployment | Okun's law: unemployment above natural is the output gap over a coefficient of about 2 | A. M. Okun, "Potential GNP: its measurement and significance", *Proceedings of the Business and Economic Statistics Section*, American Statistical Association, 1962 |
| Wages | The wage Phillips curve: slack holds wage growth back | A. W. Phillips, "The relation between unemployment and the rate of change of money wage rates in the United Kingdom, 1861–1957", *Economica* 25(100), 1958; O. Blanchard and L. Katz, "What we know and do not know about the natural rate of unemployment", *Journal of Economic Perspectives* 11(1), 1997 |
| Business valuation | The excess earnings method: tangible assets plus earnings beyond a fair return on them, capitalised; a loss-making business sells below its assets | US Treasury, Revenue Ruling 68-609, 1968 (the "formula approach"), still the standard way of valuing small businesses' goodwill |
| Taxes | French rates: corporate tax 15% up to 42,500 for small companies and 25% above; a 30% flat tax on dividends and on gains from selling a company | Code général des impôts, articles 219 (corporate tax) and 200 A (the *prélèvement forfaitaire unique*) |

### Supermarkets, electronics and goodwill

- **Supermarkets** need 220 m², cost 1.8 times a convenience store to fit out, add six shelf slots and 2,500 units of storage, and serve 45 shoppers per member of staff. Le Goff's retail park store opens as one in a new game; AI owners convert stores whose shelves are full when the extra slots pay, and by the fifteenth year most big grocery stores stock the whole range. The player's corner shop costs 39,000 to convert at the start (24,000 of fitting out and 15,000 of works to reach 220 m²).
- **Electronics shops** (Lyon's Pixel, a chain; Bordeaux, Lille and Paris locals) sell accessories every year or two, a smartphone every three to four years, and smart-home devices that spread from 23% of households in 2026 to over 90% ten years on. Margins are thin (40% over wholesale) and their staff cost half as much again. A first try had wholesale prices so low that every shop sold at 64% of reference prices, flagged as runaway; at realistic costs they price at reference and earn 15,000 (Lille) to 78,000 (Paris) a year.
- **Marketing** as a share of sales made a store's advertising follow its size, and goodwill made it slow to build and slow to fade.

Eight seeds of 15 years: nothing flagged but one electronics branch that went a month without a sale in one seed; every player bot made a profit in every seed (a managed single store about 41,000 a year, a player who expands 116,000 discount to 139,000 premium, 170,000 to 205,000 a year by the fifteenth); three to nine companies fail per eight seeds; 67 businesses by the end.

### Taxes and the labour market

- The headless runner's net profit now subtracts marketing and taxes. It had left marketing out since marketing came in, so the two passes before overstated net profit by one to four percent of sales.
- Taxes take about a quarter of every profitable company's profit, and the dividend tax makes owners keep more in their companies. Expansion barely slowed: entry comes from owners' cash, and chains still fill the cities by the tenth year.
- The labour market deepens recessions a little: unemployment climbs about a point and a half over a recession and takes a year to come back, so the months after a recession now sell one or two percent less than before.
- The electronics chain expanded into weak sites, where a branch could go a month without a sale; electronics owners now want their money back within a year rather than two.

Eight seeds of 15 years, net profit per year after tax: a managed single store about 38,000; a player who expands 87,000 (discount) to 95,000 (premium), 125,000 to 130,000 by the fifteenth; grocery chains 70,000 to 175,000; restaurants 6,000 (a steakhouse in Montpellier's student quarter) to 96,000 (Paris fine dining); electronics shops 8,000 to 21,000. Every player bot made a profit in every seed.

### Acquisitions and the game start

- The asking prices follow the books: a store's estimated earnings are within a few percent of its company's monthly profit scaled to a year, before tax. At first, prices at three years of excess earnings (capitalisation 0.33) had healthy convenience stores asking 300,000 to 650,000 in the first year; at two and a half years (0.40), closer to what small businesses sell for, a store asks two and a half years of its earnings plus four fifths of its fittings and stock (2.7 times a year's earnings for QuickStop in its first year), and a struggling one half its fittings and stock, often less than fitting out a new store.
- AI owners first bought any store earning less than 8% on its fittings and stock: 157 stores changed hands per 15-year run, marginal stores passed from owner to owner. Buying only stores losing money, a year after they opened and a year after they last changed hands, brought that to 21 to 24 a run, one or two a year, mostly weak groceries in Lille and Montpellier and the weakest restaurants and electronics shops, bought by chains of their format. Some still change hands more than once.
- Liquidation sales seldom happen in balanced runs, since no AI company went bankrupt; an idle player's store is bought by a chain when the player's company is wound up.

Eight seeds of 15 years with acquisitions, net profit per year after tax: a player who expands 92,000 (balanced) to 93,000 (premium), 123,000 to 139,000 by the fifteenth; grocery chains 42,000 to 156,000; restaurants 3,000 (a steakhouse in Montpellier's student quarter) to 96,000 (Paris fine dining); electronics shops 5,000 to 53,000. Nothing was flagged, and every player bot made a profit in every seed.

### Managers who advertise and invest

- A fully managed store declined over the years: its manager never advertised, so its goodwill wore away while rivals spent 1.5 to 2% of sales, and it couldn't enlarge or convert while rivals did. Staff were cut to match the shoppers who were left. An expert-run store's monthly sales fell from about 18,600 to 7,900 over six years.
- With marketing under pricing and the investing duty, the same store becomes a supermarket in its first year. Its sales peak at about 48,000 a month in the second year and ease to about 20,000 by the sixth, as rivals grow and two grocers open. It makes a profit every month. A player who takes all the profit out each month leaves the manager nothing to invest, and their store still earns 2,500 to 4,000 a month.

Eight seeds of 10 years, the player's store left to a manager with every duty, net profit per year after tax. Managed bots never open another store; owner-run bots do from the third year, so only their first two years compare.

| Player bot | Year 1 | Year 2 | Year 5 | Year 10 | 10-year average | Failed |
|---|---|---|---|---|---|---|
| balanced, owner-run | 67k | 55k | | | | 0 |
| balanced, expert | 65k | 52k | 42k | 34k | 43k | 0 |
| balanced, trainee | 49k | 40k | 30k | 23k | 31k | 0 |
| discount, owner-run | 55k | 45k | | | | 0 |
| discount, experienced | 46k | 38k | 43k | 44k | 44k | 0 |

- Nothing was flagged, and no managed store failed in any seed.
- A managed store still loses share as the cities fill, from 44 stores to 67 over ten years. A balanced store run by an expert ends the decade earning about half its first year, while a discount one holds up. Growing beyond one store remains the player's job.
- An owner tops up a company short of cash from personal money; a manager can't, so a player whose company runs dry sees their managers stop ordering. The holding now says so before the shelves empty.

### Cash cushion

- What sank managed companies was January. A player who paid out the year's profit, or whose managers spent it on works, met a corporate tax bill they couldn't pay. A bill counts as money spoken for as soon as it arrives, so every manager stopped ordering for the month it was due. Paying it left the company with no cash and empty shelves, and nothing to restock with. In a test game with two managed stores, a loan and the profit paid out every month, the company was wound up in March of its third year.
- With the cushion, which holds the year's tax among the rest, and with a few days of stock still bought from cash not yet owed, the same game runs six years without an overdue bill and pays out 383,000 rather than 178,000. Its managers buy only the essentials on about one day in thirteen, mostly late in the year, when cash falls short of the tax to come. A company that keeps its profit never does.

Eight seeds of 10 years against the run before the cushion, net profit per year after tax over the decade:

| Player bot | Before | With the cushion |
|---|---|---|
| balanced, owner-run (expands) | 78k | 68k |
| balanced, expert | 43k | 45k |
| balanced, trainee | 31k | 31k |
| discount, owner-run (expands) | 62k | 56k |
| discount, experienced | 44k | 42k |

- Nothing was flagged, no company of anyone's failed, and every player bot made a profit in every seed. AI owners opened as many stores and made as many enlargements as before.
- Owners who expand earn 9 to 13% less over the decade. They now keep the year's tax in the company instead of paying it out and putting money back in January, so they have less personal cash for new stores and open them later.
- The year's tax adds 1% to a run's time.

### Real margins and failure

In eight seeds of ten years, none of 352 AI companies failed and no store closed: the median company made 14% of its sales after tax, and the weakest tenth 8%. Food retailers make about 1.7% (FMI, 2024) and single convenience stores 2 to 5%; about half of France's new retail firms survive five years (INSEE: 48% for the 2002 cohort). Groceries bought at 53 to 60% of their reference price, against 70 to 75% in real stores; nothing paid for energy, insurance or upkeep; and no owner ever closed a store.

- Grocery products now cost 20% more and grocery markups are scaled to match, so shelf prices barely move but gross margins at the reference price fall to about 30%. Every format pays overheads per square metre each month. Owners close a store that lost money over its last twelve months, two years after opening it; they back a new company for two years; and owners looking at a new site or a struggling rival assume a margin per household about a third lower.
- Eight rounds of four seeds got there. Costs 25% higher bankrupted the discounters in their first year, since a 16% markup left them no gross margin. Losing stores sold to the best funded rival dragged the buyer down with them, 113 sales a run; owners now close them instead. Judged on 28 days of sales, and then on six months with staff priced from one day's rota, owners closed shops that made money. Judged after one year, new stores closed while still winning their custom.

Eight seeds of ten years, net profit per year after tax for the player's company:

| Player bot | Before | Now |
|---|---|---|
| balanced, owner-run (expands) | 68k | 32k |
| balanced, expert | 45k | 25k |
| balanced, trainee | 31k | 11k |
| discount, owner-run (expands) | 56k | 6k, wound up in 1 seed of 8 |
| discount, experienced | 42k | 10k |

- Over the decade about a fifth of the founding stores close: 5% of groceries and no supermarkets, but 43% of fast food places, 48% of steakhouses, 25% of fine dining and 34% of electronics shops. Closures come in the third year, when the weakest founders have had their two years, and in recessions.
- The median company now makes about 7.5% after tax, the weakest tenth less than 1%; a company that is still trading has outlived its weaker rivals.
- 74 to 85% of the stores entrants open in the first five years are gone within five, more than the half of real life: entrants open where incumbents hold the shoppers, and every steakhouse an entrant opened closed. Fewer open, so the cities go from 44 stores to about 37 over the decade.
- Companies close stores rather than fail: one was wound up in 40 runs, a discount player who bought a losing rival. Owners don't borrow yet, so debt can't sink them.
- One entrant's store, opened in the eighth year of a run, never sold anything.

### Fewer failures

That pass closed too much: a fifth of the founding stores in a decade, and most of them were about breaking even. Over their last year before closing, 63 of 96 had made 0 to 3% of their sales or more before marketing, which restaurants and electronics shops spend 3 to 4% of sales on.

- Owners now close a store only if it lost more than 3% of its sales over its last twelve months. Overheads came down for restaurants (fast food 12.00, steakhouses 7.00, fine dining 13.00) and electronics (3.00).
- Entrants weigh the stores of their channel by size as well as location, as shoppers do. On location alone, a new corner shop expected the share of the supermarket next door. Weighing size first stopped new groceries opening at all, so their margin per household went back from 0.27 to 0.33; steakhouse and fast food chains assume less (0.11 and 0.21).

Eight seeds of ten years, against the pass before:

| | Before | Now |
|---|---|---|
| Founding stores closed in ten years | 18 to 22% | 7 to 11% |
| of groceries and supermarkets | 5% and none | none |
| of fast food, steakhouses, fine dining, electronics | 43, 48, 25, 34% | 15, 25, 6, 19% |
| Entrants' stores gone within five years | 74 to 85% | 58% overall (38 to 80% by bot) |
| Stores in the cities, first year to tenth | 43 to 37 | 42 to 40 |
| Player, balanced owner-run (expands) | 32k | 53k |
| Player, balanced, expert / trainee manager | 25k / 11k | 25k / 11k |
| Player, discount owner-run (expands) | 6k, wound up in 1 seed of 8 | 6k, wound up in 4 |
| Player, discount, experienced manager | 10k | 10k |

- Closures come in the third year, when the weakest founders have had their two years, and in recessions.
- The discount player who runs its own company keeps buying struggling rivals with the cash its corner shop barely earns, and half the time runs dry. A broke company buys no stock, so its stores sell nothing for the weeks before it is wound up; the runner flags those.
- No company of an AI owner failed: owners close stores before they run out of cash, and don't borrow yet.

### Directors

A director runs a whole company above its managers (see Commands and policies). The scenario offers three grades: a promoted manager (skill 0.40, 8.00 a day), a seasoned director (0.70, 14.00) and a star (0.95, 22.00), about 2,900, 5,100 and 8,000 a year at the start's wages, against 1,100 to 2,600 for a store manager. A director of no skill misjudges a site's margin by up to 30% (`judgmentError`), and one of full skill takes half their managers' misjudgment away (`coaching`): a promoted manager 20%, a seasoned director 35%, a star 48%.

`<strategy>#<grade>-<growth>` bots hire a director on the first day, who hires an experienced manager for the player's store and pays the profit out; the owner only tops the company up. Eight seeds of 3,650 days, the player's net profit per year, balanced:

| Player | Net profit per year | What the director did |
|---|---|---|
| Owner-run | 53k | |
| Expert manager, investing | 25k | |
| Seasoned director, keep the stores as they are | 1k (an earlier pricing at 20.00 a day) | The store never grows; rivals that do take its shoppers, and it loses money from the third year |
| Seasoned director, enlarge and convert | 16k | Enlarges as an owner would |
| Seasoned director, also open | 16k | No site repays within 24 months by its judgment |
| Seasoned director, also buy | 15k | Bought a struggling rival in 7 seeds: 2 turned round (the company made 21k and 23k a year), 5 closed a year later |
| Promoted manager, also open | 16k | Opened 4 stores in the 8 seeds; 3 closed two years later |
| Star director, also open | 13k | Opened nothing; costs more |

- Over one store a director costs more than they bring: they are for companies with several, where one salary covers them all.
- At the first pricing (12.00, 20.00 and 32.00 a day, a 50% error) a promoted manager opened 11 stores and 10 closed, picking the sites it overrated most among dozens, and a star cost 11,500 a year to open nothing. Hence the lower error and salaries.
- Without coaching, skill only showed when a director was allowed to grow, and the estimate rarely finds a site worth opening, so a star did no better than a seasoned director for 2,900 more a year. With coaching, the same runs (enlarge and convert) give the player 20k a year under a promoted manager, 19k under a seasoned director and 16k under a star: before their salaries, 23.1k, 23.8k and 24.4k. Over one store the cheapest director still wins, but the gain comes from every store's manager while the salary is paid once: a seasoned director pays for the difference from about three stores, a star from about four.
- Closing works the same as for AI owners: a bought store still losing 3% of its sales a year after the purchase goes.

### Marketing and reputation

A store with a good location, an expert manager and 10% of its sales on marketing earned little: 9,000 a year in its first years, falling to 7,000. Marketing then saturated early (`marketingWeight` 0.6, `halfGoodwill` 1,500): 10% drew about 30% more shoppers than 1.5%, whose margin covered barely half the spend, so it earned less than the strategy's 1.5% (25,000). And a well-run store's profit only kept pace with inflation.

- **Marketing** pulls up to twice as much and saturates later (`marketingWeight` 1.2, `halfGoodwill` 3,000), so the best share for a corner shop moved from about 1.5% to about 5%, and 10% no longer ruins it. At a strategy's 1 to 4%, AI owners get about the same pull as before. Managers with pricing keep a share the owner chose; the store screen prices out 1 to 12% of sales: the monthly cost, and the pull each builds up to.
- **Reputation** (see the demand model) weighs up to 0.5. Established stores start at 0.85, a new one at 0.65, moving toward their service over about ten months; well-run stores settle around 0.9. The gap is what a new store wins over its first years.

Eight seeds of 3,650 days, the player's net profit per year (the old balance in brackets, where it was measured):

| Player | Average | Year 1 | Year 3 | Year 5 | Year 10 |
|---|---|---|---|---|---|
| Owner-run, balanced | 59k (53k) | 26k | 33k | 22k | 95k |
| Expert manager, 1.5% marketing | 23k (25k) | 23k | 19k | 17k | 26k |
| Expert manager, 5% | 36k (26k) | 22k | 28k | 30k | 46k |
| Expert manager, 10% | 24k (14k) | 15k | 12k | 17k | 31k |

- The dips around years 3 to 5 are the store's enlargements: the works are spent at once, and the extra rent and overheads come before the extra sales. The enlargement estimate counts new slots at the average listed product's margin and no extra staff, which flatters it; making it stricter is left for a balancing pass of its own.
- AI owners: no company liquidated; 7% of founding stores closed in ten years (7 to 11% before). New stores have a harder start: 71 to 78% of those opened in the first five years were gone within five (58% before), most of them groceries opened into towns where established stores already have the better name.
- The discount player who runs its own company still buys struggling rivals and was wound up in 5 seeds of 8 (4 before); its broke stores are the runner's only flags.

### Growth you can feel

The aim: sensible play grows. A store left to an expert manager on default settings earned 23k in its first year and 26k in its tenth, less in real terms; profit dipped in the years a store enlarged; a January read as a loss.

- Rent and overheads were billed daily during this pass, to even out the weeks; they are billed on the first of the month again, as a lease is, and the results below were measured with daily billing.
- **Reports and the dashboard lead with trading profit** (`PeriodReport.tradingProfit`): before fitting out and works, which serve for years, the corporate tax and one-offs. The net profit follows on the profit and loss page.
- **Enlargements are judged on what the missing products would sell** (see Enlarging), so they pay when they're made.
- **Managers spend the marketing that pays** on their store's margin after staff (see Managers), about 5% for a balanced corner shop and 2% for a discount one; AI owners keep their strategies' 1 to 4%.
- **Cities grow** about 2.2% a year (they grew 0.9%).
- **Owners grow more selectively**: every payback period is two thirds of what it was (16 months, 8 for electronics), for new stores, purchases, enlargements and conversions. With growing cities and the old 24 months, owners opened three times as many stores, most of which failed and crowded everyone else.
- **A new store's name** starts at 0.75 against 0.85 for an established one (0.65 before), and AI owners buy a struggling store at most once a year (every 180 days before).

Eight seeds of 3,650 days, the player's net profit per year (after works and tax, which the app shows apart):

| Player | Average | Year 1 | Year 2 | Year 3 | Year 5 | Year 10 |
|---|---|---|---|---|---|---|
| Owner-run, balanced | 62k (59k) | 27k | 35k | 46k | 66k | 89k |
| Expert manager, balanced | 48k (23k) | 24k | 23k | 25k | 41k | 73k |
| Seasoned director, opening stores | 38k (16k) | 17k | 17k | 15k | 28k | 63k |
| Owner-run, discount | 7k (2k) | 10k | 3k | 5k | 8k | 10k |
| Experienced manager, discount | 3k (9k) | 5k | 3k | 2k | 2k | 7k |

- The managed store's profit before marketing grows every year (39k, 44k, 50k, 68k by year 5, 110k by year 10, in a run of six seeds); its net stays level the first three years as marketing grows with sales and the first enlargements are paid for, then climbs.
- AI owners: no company liquidated; 5 to 7% of founding stores closed in ten years; 24 to 35 new stores opened across the eight seeds, a third to a half of them gone within five years (58 to 78% before).
- A discount corner shop is still the hard path: its thin margin leaves little for a manager's misjudgment. Under an experienced manager it made from a 1,400 loss to a 10,000 profit a year depending on the seed, and was wound up in one of eight.

### Calm and steady

A two-year audit through the app's controller, of a hands-off player (an expert manager with every duty) and of one played by the owner's policy, looked at what playing feels like rather than what it earns.

- **The clock stopped on 429 days of 730**, mostly the next day, for products sold out with more already on order (261) and deliveries that didn't fit in storage (242), and for rivals' stores opening, growing or changing hands. Pausing now waits for what needs the player (see News): the same games run through.
- **Deliveries that don't fit cost nothing.** A manager orders up to its targets for each product without counting what the others bring the same days, so deliveries often bounce off a full stockroom. Capping orders to the room left on arrival ended the bounces but left the shelves thinner, and sales fell: a full stockroom is worth more than the bounced units, which go back unbilled. The orders stay as they were; the bounces are no longer news where a manager orders.
- **A small store's reputation** counted the products it can't fit; it now counts only stockouts and service. A hands-off corner shop's reputation climbed from 73% to 78% in two years; it now reaches 89% in a year and 93% in two.
- **Rent and overheads** went back to the first of the month.

Six seeds, the hands-off store's trading profit a month, on average: 1,380 in its first month, 1,940 in its fifth, 2,560 in its twelfth, 2,300 to 2,670 in its second year.

Eight seeds of 3,650 days, the player's net profit per year:

| Player | Average | Year 1 | Year 2 | Year 3 | Year 5 | Year 10 |
|---|---|---|---|---|---|---|
| Owner-run, balanced | 54k | 28k | 33k | 32k | 47k | 83k |
| Expert manager, balanced | 44k | 24k | 23k | 26k | 39k | 64k |
| Seasoned director, opening stores | 37k | 16k | 16k | 21k | 34k | 56k |
| Owner-run, discount | 7k | 11k | 6k | 7k | 8k | 8k |
| Experienced manager, discount | 12k (3k) | 4k | 2k | 1k | 8k | 19k |

AI owners: no company liquidated; 4 to 6% of founding stores closed in ten years; 16 to 28 new stores opened across the eight seeds, a quarter gone within five years. The discount player who runs its own company still buys struggling rivals beyond its means and was wound up in 2 seeds of 8.

### Borrowing to grow

The headless runner gained a player keen to grow (`CreditOwner`): it runs its stores as the owner's policy does, keeps the profit in the company, and every four months makes the move that repays soonest, a vacant site within the strategy's payback or a rival's store whose present earnings repay its price within four years. With `+credit` it borrows what the company lacks beyond its cushion as far as the bank lends, over seven years; with `+cash` it waits until it has the money. It is reckless on purpose: it borrows the bank's limit whenever it can.

- **Money was not what held a player back.** A player keeping its profit has 60,000 of spare cash after a year and a half, and a corner shop rarely finds a site that repays within its payback. What loans change is buying: a profitable rival asks about four years of its earnings, out of reach of savings for years.
- **Lending two years of earnings was a trap.** Counting the store bought, it let the keen player buy its first rival in year one and owe 600,000 by year five; recessions then drained the cash of the most indebted, whose shelves emptied, and half of them were wound up, mostly after year five. Cheaper credit didn't save them (5 of 8 wound up).
- **A year and a half, at three points over the central bank's rate** (`unsecuredSpread` 0.02 on top of `bankMargin`; a guaranteed loan two points), let every keen player through ten years.

Eight seeds of 3,650 days, the keen player:

| Bank | Wound up | Stores, year 5 | Stores, year 10 | Net worth, year 10 |
|---|---|---|---|---|
| No loans (`+cash`) | 0 | 1.0 | 2.2 | 428k |
| Two years, five points over | 4 | 5.8 | 8.8 | 1,510k |
| Two years, three points over | 5 | 7.0 | 7.5 | 1,596k |
| A year and a half, five points over | 1 | 3.0 | 8.0 | 1,184k |
| A year and a half, three points over | 0 | 3.0 | 10.0 | 1,572k |

The worst seed of the last still grew from one store to four and from 63,000 to 508,000 of net worth. AI owners don't borrow, and players who don't borrow are unaffected.

**Directors who borrow.** The brief can let a director borrow what the company lacks for works or a store, on its earnings and never on the owner's guarantee, in whole thousands over the longest term. Allowed to buy as well, they also go for profitable rivals whose present earnings repay the asking price within four years (`buyoutPaybackMonths`), if the bank lends what that takes; they don't save for those, or the profit would never reach the owner.

- **Works come first.** At first they borrowed only for stores. In one seed in eight, a rival bought in the second year and a recession left the company with nothing to spare beyond its reserve, so its stores were never enlarged, cheap as that is and the best investment going: 120 m² instead of 200, a sixth of the profit, and 42,000 of net worth at year ten against 292,000 for the same director without loans. Borrowing for works too took that seed to seven stores and 508,000.
- **A discount director is weak either way.** 2 of 8 companies wound up without loans and 3 of 8 with: the strategy barely earns once a director's and a manager's salaries are paid, whatever the bank does. See When discounting pays.

Eight seeds of 3,650 days, a director who may buy and pays the profit out:

| Director | May borrow | Wound up | Net profit a year | Stores, year 10 | Net worth, year 10 |
|---|---|---|---|---|---|
| Seasoned, balanced | No | 0 | 37k (25k to 43k) | 1.0 | 305k |
| Seasoned, balanced | Yes | 0 | 100k (53k to 184k) | 7.7 | 887k |
| Promoted manager, balanced | Yes | 0 | 83k (21k to 114k) | 7.0 | 731k |
| Seasoned, discount | No | 2 | 3k | 0.7 | 57k |
| Seasoned, discount | Yes | 3 | 1k | 0.7 | 41k |

### When discounting pays

Discounting should pay only in two cases: for client acquisition, and on a supermarket's volume. Measured with no change to the rules or numbers: a discount store sits about 9.5% below its rivals, steady for ten years, for 7.6 points less gross margin than a balanced one, and in a small shop the extra shoppers don't pay for that. Without enough profit overall a director can't enlarge, so 4 seeds of 8 stay at 120 m², and after two years the owner stops topping up a company that has never made money. Those are the wound-up companies.

Eight seeds of 3,650 days, an experienced manager, the store converted when the company and the owner can pay for it (year 4 or 5 for discount, one seed never; year 1 or 2 for balanced):

| Store | Net a year | Year 10 | Units a day, year 10 |
|---|---|---|---|
| Discount, corner shop | 11.5k | 19k | 912 |
| Discount, supermarket | 32.4k | 62k | 1,240 |
| Balanced, corner shop | 39.3k | 56k | 980 |
| Balanced, supermarket | 79.0k | 102k | 1,220 |

A discount supermarket earns about what a balanced corner shop does, three times a discount corner shop, though a balanced supermarket still earns more on about the same units. What didn't close that gap:

- Supplier tiers at 360 and 600 units, more supermarket storage and bigger discount batches: a discount store's prices follow the cheaper orders it expects but can't store, down to 1k a year with 4 of 8 wound up, while a balanced supermarket reached 87k.
- Staffing discount at `serviceTarget` 1.2: 17k.
- A separate stance from the day of converting: at markup 0.38, 35k and 65k in year 10; at 0.42, 40k and 72k.

**Client acquisition.** A year at discount on an established corner shop brings 11% more shoppers for a third less gross profit, and they are gone within two months of the prices rising (36k a year over the decade against 39k). The second store opened in year 4 has few shoppers to lose margin on:

| Opening offer | Shoppers, first six months | Shoppers, the next three and a half years | Holding's net profit over seven years |
|---|---|---|---|
| None | 82 | | 198k |
| Three months at discount | 96 | about 1% more | 197k |
| Six months | 103 | 1 to 6% more | 192k |
| Discount for good | 103 | 5 to 23% more | 142k |

So a short opening offer wins custom about free, and a long one doesn't pay. Habits that form and fade four times more slowly (`loyaltyRate` 0.05, `loyaltyDecay` 0.025) kept no more of them. The manager's and director's menus and the guide now say all this; strategies list by channel, so a supermarket takes a convenience store's stances (hiring its manager used to crash, with none to choose from).

### Prices too dear

A shop alone in its city, as nearly every restaurant and electronics shop is, could raise its prices almost freely. A household that refused a price kept its need, came back a few days later and rolled again, which costs nothing for something bought every few years. It could also answer a price by buying the dearer tier: too dear at 12.90, so the one at 79. At 50% over normal, an electronics shop had 74% of attempts refused yet sold only 32% fewer units. Groceries escaped this because rivals take the shoppers, and a second restaurant or electronics shop in a city mostly loses money, so being alone is the normal case.

Now a household takes a cheaper tier, tries another store, or goes without (see Demand model). The retries were the bigger cause: with trading up stopped and retries kept, electronics still earned most at +50%, 68k a year.

A shop's profit a year, alone in its city, three seeds, years 2 and 3, one shop per format and city pinned at its reference prices times the factor:

| | Normal | +10% | +20% | +30% | +50% |
|---|---|---|---|---|---|
| Electronics, before | 14.4k | 36.7k | 59.2k | 76.5k | 86.5k |
| Electronics, now | 14.8k | 33.8k | 36.7k | 32.4k | 18.0k |
| Fine dining, before | 63.6k | 90.5k | 104.9k | 109.3k | 93.9k |
| Fine dining, now | 64.3k | 83.6k | 75.0k | 51.9k | 4.3k |
| Steakhouse, before | 37.8k | 58.5k | 60.4k | 52.8k | 29.4k |
| Steakhouse, now | 38.3k | 50.8k | 40.0k | 20.2k | -14.8k |
| Fast food, before | 65.9k | 86.8k | 68.9k | 36.7k | -28.4k |
| Fast food, now | 65.7k | 62.9k | 17.9k | -6.1k | -156.8k |

So having no rival still pays, within limits: about a third more in steakhouses and fine dining at +10%, nothing in fast food, and 2.5 times a thin profit in electronics at +20%.

The player's net a year, ten years:

| Bot | Before | Now |
|---|---|---|
| Experienced manager, balanced, seeds 1-8 | 39.3k | 39.1k |
| Experienced manager, premium, seeds 1-8 | 50.3k | 47.7k |
| Experienced manager, discount, seeds 1-8 | 11.5k | 9.6k |
| Owner-run balanced, seeds 1-8 | 53.9k | 42.0k |
| Owner-run balanced, seeds 9-16 | 39.0k | 41.2k |
| Seasoned director with loans, seeds 1-8 | 99.9k | 117.6k |
| Seasoned director with loans, seeds 9-16 | 65.8k | 64.5k |

The owner-run and director rows swing both ways with the stores they buy, from 18k to 228k a seed, so they say little. AI companies charge near normal prices, so each format stays within 5% on average in every run, and none was liquidated. Three weak shops that often closed already close more often, by about one game in five to ten: La Braise, Rezé Burger and Wazemmes Mobile. A few others close slightly less often, and the count of stores open in year 10 barely moves.

### Countries by formula

Why a formula rather than sampling: on copies of the prototype, four times fewer cohorts cut a median rival's profit from 26,500 to 15,300 a year and took stock-outs from 4% to 11%, ten times fewer took it to 1,000, with 3.9 companies failing per game against none, and the day only fell from 9 to 5.6 ms: most of what's left is per store and per owner. A store's day-to-day swing in visits grows with the square root, 19%, 39% and 55%. Sampling whole neighbourhoods holds up far better (one copy of a city lands within about 1% of the others on sales and 3% on profit), but costs 1.3 to 2.2 ms a day each. A formula from a city's table alone, fitted on six cities and predicting the seventh, came within 3% on sales, against 19% for equal spending per household. So simulated neighbourhoods became the calibration, offline.

The formula against the full simulation (`test/countries/shop_bridge_test.dart`, seed 1, seven cities, two years, a format counting only where it traded all year): sales are 3.3% off at the median and 6.7% at worst. Seed 3 gives 3.0% and 6.7%, and seed 2 gives 5.1% and 15.0%, with every city but one running high in its first year; it gave 4.3% and 13.4% before "Prices too dear". A shop closing partway through a year is further off, as the formula assumes the whole year: 12.7% for Montpellier when La Braise closes in seed 1. Fitted capture: groceries 0.95, restaurants 0.85, electronics 1.01.

The table against reality, 2022: what households report spending against what sellers report selling, before VAT.

| €bn | Groceries | Restaurants | Electronics |
|---|---|---|---|
| Germany | 273 / 278 | 72 / 75 | 34 / 30 |
| France | 228 / 285 | 79 / 88 | 16 / 11 |
| Italy | 218 / 148 | 75 / 70 | 18 / 7 |
| Spain | 134 / 121 | 92 / 61 | 7 / 9 |

The gaps have reasons. France's hypermarkets sell far more than food, fuel among it. Italian food also sells through markets and small shops outside these statistics. Spain's restaurant spending counts tourists and likely more cash than turnover reports. Electronics sells largely online and through general stores, which the sellers' side books elsewhere. The model takes the households' side.

Controlled price runs, four seeds: one shop per trade and city pinned at normal prices, 10% over and 10% under, with a rival added next door where it had none.

| Sales after | Groceries | Restaurants | Electronics |
|---|---|---|---|
| A 10% rise | −26.7% | −20.5% | −8.2% |
| A 10% cut | +7.2% | +6.6% | −10.5% |

A rise costs three to four times what a cut brings. In electronics even a cut loses sales: units rise only about 5%, and an AI rival follows half way, so the real gap is 5 to 6%. So electronics chains feel a rise but gain nothing from a cut. These rest on few shops: electronics' response to rises spans 2.45 between seeds. Before "Prices too dear", a rise in electronics gained 1.7% and a cut lost 5.6%.

Over 20 years and 8 seeds: real growth of 0.1 to 1.8% a year by trade and country, margins within half a point of normal, no chain failing, and shop counts moving by −0.04 to +1.26% a year.

Assumptions, not data: restaurants' goods at 30% of sales, how price-sensitive each class is against the average (1.4 to 0.6), how fast stores respond to margins, fit-out at 25% of a store's yearly sales, starting cash, restaurant and electronics shares, store counts per chain and all price positions. Every chain in a trade and country earns the same margin, as nothing yet separates a discounter's costs from anyone else's. The shop level's recession cuts demand 12%, about five times the size of real ones, so the two levels differ there, which zooming in will have to settle.

### What a new shop might do

`shopOutlook` against shops actually opened: one per format and city, three months into a game, held at normal prices and otherwise run by an AI owner, four seeds, their years 2 and 3. Across the 35 shops, half of the profit estimates come within about 4,000 a year, three quarters within 16,000, and the worst is 51,000 off. Half of the sales estimates come within 10%. The neighbourhood it ranks first is the one that did best for grocers, fast food and electronics, but only third for steakhouses and fifth for fine dining.

The largest miss is a steakhouse in Paris that took 82% of its trade against an estimated 53%, probably as its rival changed later on, which an estimate can't foresee, though none of the misses has been traced one by one. It takes a shop as run well at normal prices, with no manager. At those prices a new fast food next to a rival charging 13% less gets only a fifth to a third of the trade, so shelf prices count; they count only between 15% under and 5% over normal, as a new game's dear shops soon settle. Its numbers (`ShopHabits`) were fitted to these same shops, and refitted since: see "The estimate refitted".

### Neighbourhoods from figures

Today's seven cities generated from their figures alone, against the hand-made ones. Eight seeds of 3,650 days, with three generated worlds. Player's net a year:

| Bot | By hand | World 1 | World 2 | World 3 |
|---|---|---|---|---|
| Experienced manager, balanced | 39.1k | 43.8k | 40.0k | 39.5k |
| Experienced manager, premium | 47.7k | 42.7k | 47.7k | 48.1k |
| Experienced manager, discount | 9.6k | 20.3k | | |
| Owner-run balanced | 42.0k | 32.9k | | |
| Seasoned director with loans | 117.6k | 105.6k | | |

Under the balanced manager, grocers' sales over ten years stay within about 3% in every city and world, and within 1% overall. There are as many restaurants and electronics shops as by hand, 15 and 4, but not in the same cities: the rule drops La Braise and Wazemmes Mobile and Rezé Burger, which often closed, and opens a steakhouse and an electronics shop in Marseille and a fast food in Paris. So restaurants sell 11 to 14% more overall, and electronics 7 to 8%. Rivals earn about the same by format, fast food 21k against 20 to 26k, steakhouses 25k against 25 to 26k, fine dining 48k against 46 to 50k, electronics 26k against 26 to 27k, grocers 47k against 40 to 46k. Nobody is wound up, and a game day takes the same (8.2 ms against 7.7 ms).

What doesn't match:

- Stores change hands more than twice as often: 205 to 235 purchases over the eight games, against 87. They are mostly marginal restaurants and weak grocers passed between owners. So one company more often ends up with over 70% of a neighbourhood's grocery trade: 14 to 20 times across the eight games, against 2.
- A discount player earns about twice as much, in the one world tried, on a thin 9.6k. An owner-run player earns about a fifth less and a director with loans about a tenth less, also in one world, though those two swing widely with the seeds even by hand.
- In world 1, a premium rival on Lyon's best site becomes a supermarket within two months, and the player's first two years come in 24% and 44% lower, then higher from year 5.

What was found on the way, all from changing today's Lyon one detail at a time: rivals' starting shelves matter most. Listing what earns most, rather than the staples, took the player from 18k to 31k a year in the first three years, as rivals then didn't stock what the player does. The player's stockroom comes next: 1,800 units rather than 1,500 is worth 5k a year. Rivals' cash and the player's opening cost change nothing in three years, and one rival's site little.

The rules were fitted on these same seven cities, so this shows they reproduce them, not that they hold for a different kind of place: see the next section for that. `test/neighbourhoods/neighbourhood_generator_test.dart` compares groceries over two years, within 8% per city, and fails if the two drift apart after a balance change.

### Neighbourhoods asleep

The scenario holds 18 rows beside the seven cities: six more in Lyon, two more in each of the others. Their households, levels and rents are invented, and their names are real places. They first slept frozen, which isn't what the owner had approved; see "Neighbourhoods by formula" below, which replaced that.

Those 18 woken on day 90 of a game, two seeds, with a test shop per trade opened in each at normal prices, years 2 and 3. Places the rules and `shopOutlook` weren't fitted to:

- No company is wound up. 121 of 1,379 shops have closed by the end of the third year, with every place given one more rival than it was made for.
- The profit estimate is off by about 8,000 at the median, three quarters within 13,000, the worst 35,000, and sales by 14%. That's worse than on the seven cities, as expected, and it runs high: grocers 29k against 18k, fast food 29k against 12k, fine dining 16k against 6k.
- It ranks well: the place it puts first is the best in fact for four trades of five, and second for grocers.

All 18 awake takes a game day about 5.4 times as long, so about 2 ms each on a desktop against today's 7.8 ms in all (a contended measure, five games at once).

How little the cities depend on each other, from today's game with only Lyon awake and the other six as rows, ten years, eight seeds. A day falls from 7.81 to 1.67 ms, which is under the phone target of 5 ms, though the phone itself hasn't been timed:

| Bot | All seven awake | Only Lyon |
|---|---|---|
| Experienced manager, balanced | 39.1k | 37.9k |
| Experienced manager, premium | 47.7k | 46.9k |
| Experienced manager, discount | 9.6k | 11.9k |
| Owner-run balanced | 42.0k | 28.4k |

The manager's year-by-year figures barely move (20.2k to 19.3k in year 1, 55.0k to 55.5k in year 10), so what happens in another city hardly touches a shop. The owner-run bot earns less because it grows by buying and opening in the other cities, which it can't do when it can't wake them. The game doesn't work this way yet: today's seven cities are all awake from the start. These runs had the six other cities frozen. The formula wouldn't change Lyon's results, as it touches nothing simulated, but they haven't been repeated with the six running by formula.

### Neighbourhoods by formula

The same 18 places over ten years, by formula and simulated in full from day 0, with the same seeds. The figures by trade were fitted on seeds 1 and 2. These are seeds 3 and 4, which they weren't fitted on, so the shops differ, though the places are the same:

| Year 5 | Sales, formula | Sales, in full | Profit per shop, formula | Profit per shop, in full |
|---|---|---|---|---|
| Convenience stores | 29.1m | 30.0m | 52.9k | 58.0k |
| Supermarkets (2) | 1.59m | 1.54m | 92.5k | 98.8k |
| Fast food | 4.88m | 4.77m | 30.2k | 38.1k |
| Steakhouses | 4.97m | 4.95m | 38.8k | 42.2k |
| Fine dining | 4.23m | 4.23m | 68.8k | 73.9k |
| Electronics | 3.98m | 3.71m | 40.2k | 35.8k |

- One trade in one place, by sales: half within 4%, three quarters within 8%, nine in ten within 13% in years 2 to 5, and half within 3%, three quarters within 7%, nine in ten within 12% in years 6 to 10.
- By year 10 sales are within 2 to 7% in each trade but supermarkets, 12% over.
- Profit per shop by year 5 runs low by 6 to 21%, but for electronics, 12% high. By year 10 each trade is within 13%.
- New shops, nearly all fast food: 11 against 10.5 by year 5, and 16 against 12 by year 10. Closures: 3 against 4.5 by year 10.
- Grocers' area matches: 179 m² against 175 by year 5, 180 against 181 by year 10.
- Supermarkets match on sales by year 5, though there are only two to go on.

Waking all 18 after five years by formula, then three years in full, seeds 1 and 2. No wave of failures: one company in the whole world wound up by the end of each game. The first year in full counts only 11 months and looks low, 6 to 24% under the formula's last year, and supermarkets up to 32%. A game's own first year is also about 12% under its second. The next year is 7 to 23% above the formula's last, but for supermarkets on one seed, 6% under.

A month of the formula costs 39 µs a place, about 0.023 ms per game day for all 18, against 7.15 ms for the day as a whole on a desktop. So a place costs about 0.0013 ms a day by formula, and about 2 ms awake (the contended measure above).

What it isn't: no purchases or chains, so it says nothing of how trade concentrates; no bots, managers or shop-level price wars; the fit is on these 18 invented places, and "The formula on other kinds of place" tests it beyond them. The recession is the shop level's size, 12%, kept so that the two levels agree until that decision is made.

### The formula on other kinds of place

18 test places, in a scratch copy of the scenario, each pushed one way beyond the game's own 18 (1,100 to 3,400 households, incomes 0.75 to 1.45). By formula and in full, ten years, seeds 1 to 4, with nothing refitted to them but for the three fixes below:

| Place | Sales, formula against full: year 5 | Year 10 | Shops in year 10, formula / full | Profit per shop in year 5, formula / full |
|---|---|---|---|---|
| Very poor, incomes 0.40 | 1.04 | 1.08 | 2.8 / 3.5 | 31.1k / 6.2k |
| Poor, 0.55 | 1.01 | 1.07 | 5.2 / 5.8 | 27.1k / 22.0k |
| Rich, 1.70 | 0.98 | 0.98 | 9.0 / 9.0 | 112k / 134k |
| Very rich, 2.00 | 1.02 | 1.02 | 9.8 / 9.2 | 94k / 128k |
| Tiny, 500 households | 0.95 | 0.90 | 1.8 / 1.2 | 16.7k / 17.9k |
| Small, 800 | 0.93 | 0.94 | 3.0 / 2.8 | 16.4k / 19.7k |
| Large, 6,000 | 1.00 | 1.01 | 16.5 / 16.8 | 105k / 91k |
| Huge, 12,000 | 1.00 | 1.01 | 25.0 / 25.0 | 133k / 133k |
| Mostly students | 1.02 | 0.99 | 5.2 / 5.2 | 35.2k / 39.4k |
| Mostly retirees | 1.00 | 1.00 | 5.5 / 6.8 | 56.0k / 47.4k |
| Mostly families | 1.02 | 1.05 | 5.8 / 6.0 | 44.5k / 46.9k |
| Mostly comfortable | 0.99 | 1.03 | 8.0 / 7.8 | 86.4k / 94.9k |
| Shrinking 4% a year | 0.96 | 0.98 | 8.0 / 7.8 | 46.9k / 56.8k |
| Booming 6% a year | 1.00 | 1.02 | 8.2 / 8.2 | 51.9k / 50.9k |
| Rents of 60 a m² | 0.90 | 1.24 | 1.0 / 1.0 | 243k / 130k |
| Rents of 1.50 | 0.96 | 0.97 | 9.0 / 9.0 | 56.9k / 57.6k |
| Wages 0.60 | 0.98 | 0.97 | 8.0 / 8.0 | 75.8k / 80.1k |
| Wages 1.60 | 0.86 | 0.87 | 5.0 / 6.0 | 31.9k / 33.3k |

One trade in one place, by sales: half within 4%, three quarters within 9% in years 2 to 5, half within 3% and three quarters within 7% in years 6 to 10. Nine in ten are within 24%, then 31%, the tail being a trade where one side has a shop and the other hasn't. So sales hold across all of these, and the number of shops in nearly all.

It found three things, now fixed:

- Big places opened too few shops: 3 where the full simulation opened 11 in the huge one, as the chance of a new owner didn't grow with the place. It's now per 2,000 households, and both open 11.
- Enlarging ignored the extra rent, which the AI's rule counts. It now counts it, and asks twice the works' cost rather than three times, which keeps the game's 18 places at the size they reach in full.
- Staff grew without limit with shoppers, where a slot holds 6 at most. It now stops there. Profit per shop in the huge place went from 113k to 130k, against 133k in full. The estimate uses the same sum.

Where it's still off: the very poor place, whose grocers sell about 20% too much; dear rents, where the one grocer left sells up to 24% too much; supermarkets in big places, of which the full simulation has about twice as many. Profit runs low in most of them, by a fifth to a quarter in the rich places. Poor places lose too many shops, 2.5 against 0.8 and 1.8 against 0.2 by year 10, as so many there trade near the line that the chance of closing, added under "Downturns", bites too often.

`shopOutlook` in the same places, a test shop per trade, seeds 1 to 4: half the profit estimates within 8,000, three quarters within 14,300, nine in ten within 25,600, 400 too low on average; half the sales estimates within 9%; right about profit or loss 81% of the time; of those it says will make over 5,000, 87% make money. The first pick is the true best in 4 trades of 5, and the top third holds 5 or 6 of the true top 6. It reads too high in tiny and small places, grocers most (2k against -15k, 6k against -13k), and for restaurants where few eat out, as fast food among retirees (5k against -26k). It reads too low in the huge place (129k against 175k) and where rents are so dear that rivals close, which it can't foresee (grocers -42k against -2k). The worst single miss is 225k, in the huge place.

### Downturns

The formula took a recession's cut in spending and left out that households also trade down, by 10 points of premium share in a recession, and buy dearer as real wages rise. With both, what a shop sells in the first six months of a recession, against the year before:

| | Convenience | Supermarket | Fast food | Steakhouse | Fine dining | Electronics |
|---|---|---|---|---|---|---|
| Seeds 1 to 4, before | -3.7% | -3.2% | -5.8% | -3.1% | -2.9% | -1.8% |
| Seeds 1 to 4, after | -7.5% | -7.4% | -8.2% | -6.6% | -7.8% | -9.7% |
| Seeds 1 to 4, in full | -7.9% | -11.6% | -10.5% | -9.9% | -10.7% | -11.8% |
| Seeds 9 to 12, after | -15.3% | -15.8% | -14.6% | -14.3% | -15.9% | -19.4% |
| Seeds 9 to 12, in full | -13.3% | -18.9% | -16.2% | -15.4% | -16.0% | -19.7% |

Seeds 9 to 12 had no part in any of this. Their month's profit in all shops of a trade, in a recession, formula against full: convenience 151k / 169k, fast food 19k / 18k, steakhouses 28k / 25k, fine dining 38k / 36k, electronics 20k / 23k. In an expansion all of those are within 7%. It also took up most of the low profit: average margins by trade now match within about a point by year 5, as convenience 10.3% / 10.3%, steakhouses 12.7% / 13.3%, fine dining 19.3% / 19.4%, fast food 8.8% / 9.1%.

Closures needed more. Of 26 shops closing in full on three seeds, 15 did in a recession, but 16 had traded for years and 10 had recently opened, and most stood barely under the line. The formula gives a trade's shops what such shops do on average, so few fall under it: within one place its shops' margins differ by 1.5 points against 3 in full. A shop earning under 3% of its sales now has a 3% chance a month of closing at no profit, scaling with its margin, fitted on seeds 1 to 8.

| By year 10, of about 120 shops | Before | With trading down | With the chance of closing | In full |
|---|---|---|---|---|
| Seeds 1 to 4 | 0.8 | 1.5 | 3.2 | 3.5 |
| Seeds 5 to 8 | | 2.0 | 5.5 | 7.2 |
| Seeds 9 to 12 | | | 4.8 | 8.0 |

So it still closes too few, and it's a statistical stand-in rather than a reason: which shop closes is chance, and its rivals in a place stay more alike than real ones. The size of the recession itself, 12%, remains the open decision noted under the country layer.

### The estimate refitted

`shopOutlook` against shops actually opened in the 18 places: a test shop per trade in each at normal prices, on seeds 3 and 4, which nothing here was fitted to, in its years 2 and 3 of trading. Before is the estimate as it stood, after is as it stands:

| | Woken on day 90, before | After | Woken on day 1,100, before | After |
|---|---|---|---|---|
| Profit off by, half within | 9,000 | 5,100 | 10,800 | 5,300 |
| Three quarters within | 15,200 | 9,900 | 17,500 | 8,900 |
| Worst | 48,000 | 36,900 | 44,700 | 39,500 |
| Off on average | +8,800 | +1,400 | +10,300 | +1,400 |
| Sales off by, half within | 12% | 7% | 11% | 7% |
| Right about profit or loss | 78% | 81% | 77% | 86% |
| Said over +5,000, and it did make money | 82% | 93% | 80% | 90% |

Two errors about sleeping rivals came first, and took no tuning:

- Their prices. `plan` showed what shops of a world just begun charge, while shops soon settle on their markup over what they pay: fast food -5% against -13%, fine dining +5% against -4%, grocers 0% against -5%. It now works out that markup on the best price any supplier gives for the shop's usual order, which lands within about a point: grocers -4.2% against -5.3%, fast food -12.9% against -13.1%. Shops wake at these prices too.
- Their size, as the formula has left them. By the size rule alone, with all its rivals enlarged once, that's about a tenth of a new grocer's sales.

The rest is `ShopHabits`, fitted on seeds 1 and 2 here and four seeds in the seven cities: how a new shop draws against those already there, and the staff it keeps for its busiest hours. Goods and premises already matched. Restaurants keep more staff than the old figure assumed.

In the seven cities, same four seeds and so partly fitted, half the profit estimates fall from within 9,600 to within 7,900, nine in ten from 32,900 to 27,300, and the average from +1,500 to -900, right about profit or loss 72% of the time both ways. On four more seeds: half within 9,000, nine in ten within 30,500, worst 61,900, right 69% of the time.

Ranking barely moves. In the 18 places, the top third by estimate holds 5 or 6 of the true top 6 in every trade, as before, and the first pick is the true best in 2 or 3 trades of 5, against 3 or 4. It's still high for steakhouses and fine dining, by 3,000 to 6,000 in the 18 places, and for fine dining in the seven cities by 9,000, where shops alone in a place lose money the estimate says they'd make.

Measuring this found a flaw in the earlier test tools: a month after a test shop had closed counted as a month of no sales. So the figures under "What a new shop might do" and "Neighbourhoods asleep" overstate how far short of the estimate losing shops fell. One wrong turn followed from that: a new fast food looked to win far less against a rival than it does.

## Build order

Each step ends with something you can test headlessly.

1. **Core:** primitives, RNG, hashing, the exp table, the forbidden-API scan, and goldens on VM and Node.
2. **Skeleton:** content loader, `WorldState`, an empty tick pipeline, save/load, the state hash, and the continuity and replay tests.
3. **Supply side:** orders, lead times, deliveries, spoilage, shelf slots, payables, and the ledger, driven by a fixed scripted demand.
4. **Demand:** cohorts, store choice, baskets, substitution, loyalty, perceived prices, and attribution.
5. **Competitors:** `RetailPolicy`, strategy bots, the headless runner and its CSV output, and a first balancing pass.
6. **Finance and entry:** loans, guarantees, insolvency and liquidation, AI owners, and `EntrepreneurPolicy`.
7. **World:** macro regimes, staffing and opening slots, market research, and observations.
8. **UI:** Flutter dashboard, store, orders, and reports over the observation API, then playtests for criteria 3 and 4.

A throwaway debug screen after step 4 helps catch nonsense early.

## Decisions to confirm

- Text is looked up at run time from JSON, by dotted key, through one global language, rather than through `gen-l10n` and a `BuildContext`: mods can bring languages, and news, commands and letters are worded outside any widget. Changing language rebuilds the menu, and is offered only there.
- Households are agent cohorts rather than aggregate segment shares.
- Suppliers stay exogenous until production exists.
- AI owners are `Person`s (a provisional answer to open question 1).
- Serialization is hand-written, with no code generation in the engine.
- Opening hours are day slots set by staff per slot, with a soft penalty for shopping off-hours rather than a hard rule.
- Taxes are stubbed in the prototype: the ledger accounts exist, but tax logic waits for launch scope.
- A company may borrow without a guarantee once its net assets reach a scenario threshold (a provisional answer to open question 2).
- Wages are paid to the market's households, their first income; households still spend more than they earn until a fuller income model exists.
- Research is one kind of study, in grades of accuracy; AI owners don't buy it yet.
- A liquidated company's stores are sold to whoever can buy them, at their asking price; only the stock of stores no one buys is written off.
- Every business has a public asking price and sells at it: no negotiation. The player's stores and companies are sold only when the player says so, and only stores, not companies, can be sold by the player.
- The player's chosen start costs what the scenario's first store would have: no free fittings for a dearer site or business.
- Reports are calendar weeks from Monday and calendar months, kept for 13 weeks and 24 months, for every company.
- The app has five tabs: Holding (the player's affairs at a glance), Shop (the store picked: shelves, supplies, running), Finance (money and deals), World (rivals, cities, the economy) and Books (reports and research). The look is one account-book design throughout, with a colour per kind of business.
- Company accounts are public a year late, as in France; what a rival's store sells now stays hidden, short of research.
- Taxes are corporate and dividend taxes only: no VAT, payroll or property taxes.
- Net worth counts book value only: fitting out, works and a store's goodwill aren't assets, so opening a store first lowers it; what a company paid for a store beyond its stock is, until it sells it.
- Managers come in scenario grades with visible skill rather than from a pool of candidates (a provisional answer to open question 3), and AI owners don't hire them.
- A manager's skill only scales how far it misjudges demand and prices, redrawn weekly; it doesn't change how often it reviews.
- Size draws shoppers through a saturating area/(area + halfSizeArea) term weighted per segment; assortment breadth isn't a term of its own, since bigger stores show it through more slots and better fill.
- Enlarging is an owner's decision, delegated to a manager only with the investing duty: both count only the extra slots' margin.
- Population change moves whole households in and out of existing cohorts, so growing markets keep their agent count and new arrivals share an existing cohort's habits.
- Incomes vary within segments around fixed averages, and their effect over time comes only from real wages; households still spend more than they earn, since their money comes from outside the simulation.
- The census is yearly and public; only research tells the true count between censuses and the mix by segment.
- Cities differ through three levels (prices, wages, incomes), their mix of households and their sites; wholesale prices are national. The prototype's cities are real districts (Lyon's Croix-Rousse, Montpellier's Boutonnet, Bordeaux's Chartrons, Nantes' Rezé) with fictional companies and people.
- Every scenario list the world mirrors may grow at the end under saved games; nothing may be removed or reordered once released.
- Restaurants are stores of another format selling meals, with no seat limit or reputation of their own (a lighter first version); any site hosts any format.
- Marketing is a share of a store's sales that builds goodwill with diminishing returns, not campaigns; advertising agencies as a business can come later.
- A supermarket is a format of the grocery channel reached by converting a convenience store, or opened on a site of 220 m² or more; Paris has none, its sites being too small.
- Electronics shops sell accessories, smartphones and smart-home devices, the last still spreading; they compete with nothing online.
- Most rivals are local shopkeepers who never expand; only chains and entrepreneurs open stores, at most one every two years once established.
- Rents carry the difference between cities: supplier prices are national, so a dear city's higher shelf prices are margin that its rents take back.
- Purchasing power is shown in the app's economy card.
- The order suggestion assumes, without sales history, what the scenario's AI strategies expect a new store to sell.
