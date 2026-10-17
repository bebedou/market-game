# Market Game implementation roadmap

Updated: 2026-10-17

## Goal and scope

Deliver a first playable, Android-first convenience-store simulator with a mobile
Flutter dashboard and a browser preview. The player should understand why profit
changed, adjust prices and stock targets, advance the economy, and resume a saved
game without changing its future.

The first release contains 1,000 households in aggregated consumer segments,
three convenience stores, two AI wholesale suppliers, and eight products. It
includes inventory, household spending budgets, operating expenses, profit,
competitor pricing, market shares, and notifications.

The engine stays pure Dart. There is no backend, authentication, external database,
or paid API. Financial markets, manufacturing, software businesses, R&D, patents,
and acquisitions are outside this release.

## Current status

| Milestone | Status | Evidence or dependency |
| --- | --- | --- |
| M0 — Development foundation | Complete and merged | Flutter 3.47.7, Codespaces, CI, web and Android builds |
| M1 — Daily retail engine | Implemented and tested; integrated by this release | [PR #2](https://github.com/bebedou/market-game/pull/2) |
| M2 — Game controller and simulation clock | Planned | Integrate M1 |
| M3 — Readable mobile dashboard | Planned | M2 and engine reports |
| M4 — Player decisions and feedback | Planned | M3 and validated engine commands |
| M5 — Local persistence | Planned | M2 state ownership; M3 history; M4 controls |
| M6 — Integrated validation and balance | Planned | M2–M5 |
| M7 — First playable release | Planned | M6 acceptance checks |

The [live GitHub Pages site](https://bebedou.github.io/market-game/) currently
shows the environment starter. A working engine in a PR is not yet a playable
mobile game. Completed checkboxes below describe implemented work; unchecked
items are remaining work, not functionality available in the current build.

## M0 — Development foundation

### Completed

- [x] Initialize the Flutter application and responsive starter screen.
- [x] Pin the stable Flutter release tag and verify its exact commit.
- [x] Enable Flutter Web and generate the Android launcher from the pinned SDK.
- [x] Configure Codespaces, Dart/Flutter editor extensions, and forwarded port 8080.
- [x] Add setup, preview, and verification scripts.
- [x] Run analysis, widget tests, release web compilation, and Android debug builds.
- [x] Deploy the starter through GitHub Actions to GitHub Pages.

### Foundation cleanup before the first playable release

- [ ] Commit a verified application `pubspec.lock` for reproducible dependencies.
- [ ] Commit the generated Android launcher before adding native customizations;
  stop ignoring `android/` at that point.
- [ ] Review the temporary application ID before any store publication.
- [ ] Limit production Pages deployments to the intended release branch, normally
  `main`; keep PR builds as validation rather than production deployments.
- [ ] Ensure formatting is checked consistently and commit formatted source;
  avoid depending on CI to silently rewrite files before analysis.

Acceptance: a fresh Codespace can install dependencies and start the web preview
using only the documented steps. A connected Android device can run the app using
an installed Android SDK. The published project-subdirectory URL loads its assets.

## M1 — Daily retail engine

### Implemented in PR #2

- [x] Define eight products with reference prices, wholesale/procurement costs,
  and distinct baseline demand rates.
- [x] Define four consumer segments totaling 1,000 households, with income,
  convenience-shopping budgets, and price sensitivity.
- [x] Add one player store, two competing stores, and two wholesale suppliers.
- [x] Represent money in integer cents and inventory in whole units.
- [x] Introduce an explicit cash ledger with an outside-economy counterparty.
- [x] Implement FIFO inventory costing and prevent negative stock.
- [x] Advance income, supplier quotes/procurement, operating costs, restocking,
  consumer purchases, and competitor price adjustments in a daily tick.
- [x] Bound purchases by household budgets, store cash, and supplier inventory.
- [x] Give consumers an outside option instead of forcing all budgets to be spent.
- [x] Produce daily business reports, revenue market shares, and event messages.
- [x] Preserve PRNG, FIFO, account, pricing, and prior-sales state in JSON snapshots.
- [x] Document formulas and limits in [docs/economy.md](docs/economy.md).
- [x] Add a standalone headless Dart runner and economic regression tests.

### Finish integration

1. [x] Review the successful CI results and integrate PR #2 in this release.
2. [ ] Run the documented 30-day scenario from the integrated revision.
3. [ ] Record any formula changes with their intended behavioral effect and update
   the model documentation and deterministic fixtures together.
4. [ ] Preserve the framework boundary: domain and simulation code import neither
   Flutter nor storage/UI services.

Verified baseline: 20 tests passed; 10,000 audited days completed; a 365-day full
snapshot matched byte for byte between the Dart VM and JavaScript. All stores
remained open after 10,000 days, with final revenue shares near 33.1%, 34.8%, and
32.1%. These results establish baseline viability, not final gameplay balance.

Acceptance: the same seed and action sequence produce the same reports and state;
all business statements reconcile; local cash and inventory never become negative.

## M2 — Game controller and simulation clock

1. [ ] Add one small Flutter-facing controller that owns the `Simulation` instance,
   playback state, selected speed, recent reports, and displayable errors. Start
   with Flutter's built-in notification/state tools; add a state package only if
   a concrete need appears.
2. [ ] Expose explicit commands for play/pause, speed, price changes, stock targets,
   and automatic restocking. Widgets must not edit ledger balances or inventory.
3. [ ] Introduce a controllable scheduler outside the engine. A tick remains one
   synchronous `advanceDay()` call; the economic engine never reads a wall clock.
4. [ ] Implement day durations: 1× = 15 seconds, 3× = 5 seconds, 10× = 1.5 seconds.
5. [ ] Define speed changes to preserve the fraction of the current day already
   elapsed. Ensure there is only one active scheduler and no overlapping ticks.
6. [ ] Start new and restored games paused. Pause when the app is backgrounded or
   the browser tab is hidden; require play on return. Do not add offline progress
   in the first release.
7. [ ] Keep the most recent 30 daily reports for charts and event summaries. Show
   an explicit pre-trading state on day 0 rather than fabricated history.
8. [ ] Dispose timers/listeners when the controller is replaced or the app closes.
9. [ ] Test the clock with fake time: each speed, pause/resume, speed changes,
   backgrounding, disposal, and rapid repeated control taps.

Acceptance: one day advances exactly once at the configured interval, pausing
stops advancement, and changing speed never creates a second timer or changes
randomness for the same completed-day/action sequence.

## M3 — Readable mobile dashboard

1. [ ] Replace the starter screen with a dashboard backed entirely by controller
   state and actual engine reports.
2. [ ] Show current day, playback state, cash, last completed day's revenue, and
   last completed day's profit. Label cash change and profit distinctly.
3. [ ] Add a revenue history chart for up to 30 completed days. Include readable
   values and an empty state before the first close; do not generate sample data.
4. [ ] Show each product's units on hand, inventory value, current retail price,
   supplier quotes, restock target, and estimated days of stock remaining.
5. [ ] Derive stock coverage from recent actual unit sales. For zero sales or no
   history, display an explicit unavailable/insufficient-history state.
6. [ ] Show all three competitors' revenue shares, including a zero-sales state
   and a clear indication of the player-controlled store.
7. [ ] Provide a daily explanation of revenue minus COGS minus operating expenses,
   so the player can connect a decision to its financial result.
8. [ ] Make important events visible without obscuring controls: stockouts,
   inability to restock, store closure, and save/load problems.
9. [ ] Use a small number of navigable sections if a single scrolling screen
   becomes difficult to scan. Keep primary business and playback controls easy
   to reach with one hand.
10. [ ] Check narrow phones, larger phones, browser widths, large text, contrast,
    screen-reader labels, and touch targets. Do not rely on color alone for profit
    and loss or stock warnings.

Acceptance: every visible number has an identifiable engine/report source; the
player can find cash, profit, inventory, and market share without horizontal
scrolling or clipped text on a narrow portrait phone.

## M4 — Player decisions and useful feedback

### Pricing

1. [ ] Add per-product price editors with clear currency formatting and useful
   increments. Support precise entry when step controls would take too many taps.
2. [ ] Validate through `setPlayerPrice` before updating the interface. Explain
   invalid entries and keep the previous valid value.
3. [ ] Make price changes apply to the next day's trading. Prevent mid-tick
   mutation; controls and daily settlement must have a clear execution order.
4. [ ] Show enough context to judge a price: wholesale quote, margin estimate,
   recent unit sales, and the relevant competitor price range.

### Stock and suppliers

5. [ ] Expose per-product restock targets and the automatic-restocking toggle.
   Explain that the current engine places restocking orders at the daily open.
6. [ ] Show estimated replenishment cost and affordability. State that actual
   purchases depend on next-open supplier quotes, supplier stock, and store cash.
7. [ ] Surface limited cash and partial fulfillment rather than reporting that a
   target guarantees delivery.
8. [ ] Keep immediate/manual purchases out of the first UI unless needed. If added,
   first introduce an engine command with defined timing, journal entries, and
   report reconciliation; never debit cash directly from a widget.

### Feedback and failure

9. [ ] Convert engine messages into bounded, readable activity entries with day
   and severity. Avoid repeated stock warnings flooding the feed.
10. [ ] Explain store closure and the current no-bailout policy, and provide a real
    new-game action. Confirm before discarding an existing game.
11. [ ] Make every visible action change real state, navigate somewhere useful, or
    explain why it is disabled. Remove unfinished placeholder buttons.

Acceptance: a player can lower a price, observe a change in later sales, change
stock targets, avoid an impending stockout, and explain why profit or cash changed.
A poor decision can lose money without violating accounting or inventory rules.

## M5 — Local persistence

1. [ ] Define a versioned save envelope containing the engine snapshot, recent
   reports/history, selected speed, and the minimum controller state needed to
   restore the dashboard. Keep engine serialization free of Flutter dependencies.
2. [ ] Add a small local-storage adapter for Android and Flutter Web. Prefer one
   maintained, free Flutter package with no server requirement.
3. [ ] Use a game-specific storage key. Document that browser saves belong to the
   current origin/browser and do not sync with Android or another device.
4. [ ] Load before creating a new game. A restored game must start paused and must
   not simulate time spent away from the app.
5. [ ] Save after completed ticks and accepted player decisions. Serialize or
   coalesce writes so an older save cannot overwrite a newer state.
6. [ ] Make saves atomic at the adapter's supported granularity. Never mark a save
   successful before the storage operation completes.
7. [ ] Validate schema and engine invariants before accepting a saved state. Handle
   malformed data, unsupported versions, unavailable browser storage, and failed
   writes with visible recovery options.
8. [ ] Preserve the prior save on a load failure; do not silently overwrite it
   with a fresh neighborhood. Make reset/new-game behavior explicit.
9. [ ] Test saving after price/target changes, after a stockout, and after a closure.
   Check history restoration, ordered writes, and failure recovery.
10. [ ] Compare an uninterrupted run with a persisted/reloaded run that receives
    the same subsequent actions; their economic futures must match exactly.

Acceptance: refreshing the phone browser or restarting Android restores the same
day, cash, inventories, prices, and history. Resuming does not reroll demand.
Local storage may be cleared by the user/browser, so promise local saves only.

## M6 — Integrated validation and gameplay balance

### Correctness and stability

1. [ ] Retain the existing FIFO, ledger, affordability, demand, AI, determinism,
   snapshot, and 10,000-day tests.
2. [ ] Add controller and widget tests for the user-facing behaviors introduced
   in M2–M5, including failure states and large text.
3. [ ] Exercise a fixed multi-seed set and explicit strategies: baseline prices,
   deep discounts, high prices, disabled restocking, and low working capital.
4. [ ] Check conservation, nonnegative local balances and stock, consumer budgets,
   FIFO valuation, and bounded memory across those scenarios. Do not require
   every intentionally bad strategy to survive.
5. [ ] Retain Dart VM/JavaScript replay equivalence after engine changes and add
   action/reload sequences to the comparison when controller integration requires it.
6. [ ] Profile sustained 10× play on a real Android phone and a phone browser.
   Measure tick duration, frame responsiveness, memory, and save-write overhead.
   Optimize a measured bottleneck before adding isolates or parallel processing.

### Balance and comprehension

7. [ ] Record revenue, profit, cash, stockouts, unfulfilled demand, and market shares
   over representative 30-day and longer scenarios.
8. [ ] Review operating costs, opening cash, margins, budget shares, demand rates,
   restock targets, and AI bounds. The current generous profitability is a starting
   assumption, not a target economy.
9. [ ] Confirm that lower prices can increase units while reducing margin, stockouts
   lose real revenue, and extra inventory ties up working capital.
10. [ ] Check that competitors retain a useful presence in the baseline without
    preventing the player from improving or failing through decisions.
11. [ ] Run a short player walkthrough: understand yesterday's result, make one
    pricing decision, make one stock decision, pause, and resume a saved game.
12. [ ] Update [the model documentation](docs/economy.md) when tuning formulas or
    parameters; update snapshot compatibility deliberately when behavior changes.

Acceptance: the first loop is understandable and responsive, accounting remains
correct under adverse play, and balance changes have recorded before/after results.

## M7 — First playable release

1. [ ] Run `bash tool/check.sh` from a clean setup. Require clean analysis, passing
   tests, headless runs, replay equivalence, and a successful release web build.
2. [ ] Build and smoke-test an Android APK on a physical portrait device. A successful
   CI build alone does not establish device usability.
3. [ ] Build the Pages version with the repository subdirectory as its base href.
   Deploy the tested revision from the release branch and verify the deployment.
4. [ ] Open the published URL on a phone; check initial load, assets, navigation,
   pricing, restocking, speeds, pause, refresh, and save restoration.
5. [ ] Keep Codespaces port-8080 instructions available for development previews.
6. [ ] Update README with controls, local-save limitations, model assumptions,
   testing commands, release links, and known unfinished items.
7. [ ] Provide a reviewable PR with the implemented behavior and verification
   results; merge and publish the accepted revision. Record the release commit/tag.

### Definition of the first playable prototype

- [ ] A player can run a store for at least 30 days without using a terminal.
- [ ] Cash, daily profit, revenue history, inventory, prices, market shares, and
  important notifications are visible and backed by real simulation data.
- [ ] Price and restock controls affect later economic outcomes.
- [ ] Pause and 1×/3×/10× playback work at 15/5/1.5 seconds per day.
- [ ] A local save survives app/browser restart and preserves deterministic state.
- [ ] No local balance or inventory becomes negative through supported actions;
  all transfers and business reports reconcile.
- [ ] The 10,000-day headless check and appropriate automated tests pass.
- [ ] Android and web builds succeed, and both phone experiences are smoke-tested.
- [ ] Every visible action works, or its disabled state explains the constraint.
- [ ] Remaining limitations are documented without claiming later systems exist.

## Suggested implementation batches

These are dependency-ordered PRs, not dates or delivery estimates:

1. **Engine integration:** finish M1 review/merge and foundation cleanup needed
   by the next code change.
2. **Read-only dashboard and clock:** M2 plus cash, profit, history, inventory,
   shares, and activity from M3. No nonfunctional business controls.
3. **Playable decisions:** M4 pricing and stock controls, with controller/widget
   tests and readable feedback.
4. **Saved games:** M5 storage adapter, recovery states, and exact resume checks.
5. **Validation and release:** M6 balance/device checks and M7 deployment.

Work directly in the existing project files; do not create worktrees. Keep each
batch compiling and reviewable, and keep the pure Dart engine independently runnable.

## Long-term direction — deferred, not committed scope

After the retail prototype is usable and validated, evaluate one expansion at a
time. Each needs its own brief, economic assumptions, save-schema plan, tests,
and player-facing reason to exist.

1. Deeper retail: delivery lead times, spoilage, staffing, store capacity, and
   additional locations. Choose mechanisms that improve decisions rather than
   merely adding repetitive tasks.
2. Broader supply chains: multiple retail categories, then manufacturing and
   production planning once inventory and cost accounting can support them.
3. Software, R&D, and intellectual property: define creation costs, uncertain
   outcomes, licensing, and competition before connecting them to the economy.
4. Corporate ownership and acquisitions: establish firm-level balance sheets,
   valuation, and ownership transactions before allowing takeovers.
5. Financial markets and portfolio decisions: design issuance, trading,
   counterparties, settlement, and safeguards against accounting exploits.
6. More complex macroeconomics only when a specific gameplay need justifies it.

Do not implement these systems while the first retail release still lacks its
core dashboard, reliable saves, or understandable economic feedback.
