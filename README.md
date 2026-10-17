# Market Game

A mobile-first **economy observation dashboard** for tuning a small, pure Dart
retail simulation: 1,000 households, three competing shops, two wholesale
suppliers, and eight products. Every shop uses automatic pricing and restocking.
There is no player management interface in this milestone.

State lives in memory. Refreshing starts a fresh deterministic run with seed 42.
Player decisions, local saves, and additional industries are deferred while we
observe and calibrate the retail economy. See [ROADMAP.md](ROADMAP.md).

## GitHub Pages preview

The `Deploy Flutter to GitHub Pages` workflow publishes the web dashboard on pushes
to `main`. It builds with the Pages subdirectory as
Flutter's base path, so JavaScript and assets resolve correctly under
`/market-game/`. The expected default URL is https://bebedou.github.io/market-game/;
the successful deployment's environment URL is authoritative.

The workflow attempts to enable Pages automatically. If GitHub denies initial
site creation, an administrator must open **Settings → Pages**, select **GitHub
Actions** as the source, and rerun the deployment. Pages is enabled for this public repository. The deployment does not
change repository visibility. The hosted dashboard advances the real economy. The current priority is monitoring
and engine calibration; gameplay and saves are deferred.

## Using the dashboard

- **Economy:** total retail revenue, profit, cash, and sales; equal comparison
  cards for all three shops; a shared 30-day chart switching between revenue,
  profit (including losses), and revenue share. Cards show empty product lines,
  net margin, and inventory value. Shares are revenue-based, not unit-based.
- **Shops:** choose any shop to inspect FIFO accounts, cash movement, inventory
  purchases, prices, stock targets, sales, supplier quotes, and stock coverage.
  Coverage uses up to seven completed days of actual sales and is unavailable
  when there are no sales. Selection survives ticks while that view stays open.
- **Supply:** household budgets and actual spending, local demand fulfillment,
  and both suppliers' cash, profit, procurement, stock, and quotes. Unfilled
  intentions include the outside option and price/budget rejection; they must
  not be interpreted as lost sales caused only by stockouts.
- **Activity:** neighborhood daily closes plus warnings from every shop. The feed
  retains at most 80 entries and repeats warnings at most once every three days.

No data is fabricated before day one. All daily financials describe the latest
completed day; prices and stock show the current closing position. Daily profit
is revenue minus FIFO cost of goods sold and operating expenses. Restocking
reduces cash and increases inventory, so cash movement differs from profit.

New and restored controllers start **paused**. Press **Play**, or use the **Next
day** button (skip-next icon) while paused to complete one day immediately. Speeds
are 1× (15 seconds/day), 3× (5 seconds/day), and 10× (1.5 seconds/day). Changing
speed preserves the completed fraction of the current day. A manual next-day
step resets that partial-day clock.

Backgrounding the app or hiding the browser tab pauses it. Returning does not
resume automatically or simulate offline time. There is one active tick timer;
a delayed callback advances at most one day rather than catching up missed days.
The engine still advances only when `advanceDay()` is called.

## Start in Codespaces (including from a phone)

1. On GitHub, select the `main` branch for the integrated project.
2. Choose **Code → Codespaces → Create codespace on this branch**. On a phone,
   use the browser's desktop-site option if the Code menu is hidden. Creating a
   Codespace uses your GitHub account's Codespaces quota.
3. Wait for the container's post-create task to finish. It installs the pinned
   Flutter SDK, creates Android launcher files, and downloads Dart dependencies.
   Retry a failed setup with `bash tool/setup.sh`.
4. In the Codespaces terminal, run:

   ```bash
   bash tool/preview.sh
   ```

5. Open the **Ports** panel and open the forwarded URL for **8080**. The URL looks
   like `https://<codespace-name>-8080.app.github.dev`. Open that URL in your phone
   browser, signed into the same GitHub account. Keep port visibility **Private**.
   `localhost:8080` on your phone is not the Codespace.
6. Keep the terminal running. After editing code, use the terminal reload command
   printed by Flutter (`r`/`R`, depending on SDK support), then refresh the phone
   page if needed. Stop the server with Ctrl+C and stop your Codespace when done.

No backend, app account, database, or paid API is required. The preview is a Flutter
web app; it is not an Android emulator. The app requests portrait orientation on
native devices; web browsers control their own orientation.

## SDK and local setup

Flutter **3.47.7** is pinned in `.flutter-version`, with its commit recorded in
`.flutter-revision`: `abaf9c523780a608bd46686fd5e53740a07077f8`. This was resolved
from Flutter's official `stable` branch and verified against release tag `3.47.7`
on 2026-10-16. Dart is bundled with Flutter. Codespaces and CI use the same release.
`tool/setup.sh` verifies the tag's commit and installs it into ignored
`.tools/flutter`, preserving any system Flutter installation. Review and update
the version and revision deliberately as stable releases change.

Codespaces installs Git, curl, unzip, xz, zip, Python, Node.js, OpenGL support,
and Java 17. Node.js runs the JavaScript compatibility check; the game has no
Node.js backend.
To work locally on Linux or macOS, install these dependencies and run:

```bash
bash tool/setup.sh
export PATH="$PWD/.tools/flutter/bin:$PATH"
flutter doctor -v
bash tool/preview.sh
```

The default Codespace is configured for web development. Android builds require an
Android SDK (not bundled in this container). For native development, install the
Android SDK using Android Studio on your computer, accept its licenses with
`flutter doctor --android-licenses`, and connect an Android phone with USB
debugging enabled. Run `flutter doctor -v`, `flutter devices`, then
`flutter run -d <device-id>`.

The setup script generates `android/` from the pinned SDK instead of hand-writing
Gradle files. It is ignored at this foundation stage. Before customizing native
Android behavior, remove `android/` from `.gitignore` and commit the generated
launcher. The script will then leave it alone. The temporary application ID is
`com.bebedou.market_game`; choose the final ID before publishing.

`pubspec.lock` is committed for reproducible application dependencies. Use
`flutter pub get` for setup and review intentional dependency upgrades separately.

## Checks

```bash
bash tool/check.sh
```

This checks committed Dart formatting, runs `flutter analyze --fatal-infos`, runs widget tests at phone
and wider sizes, and builds release web output. GitHub Actions uses the same
script and also builds an Android debug APK using the runner's Android SDK.
The checks also advance the pure Dart economy for 10,000 days and print its
financial results. A 365-day replay is also compiled to JavaScript and compared
byte for byte with its Dart VM snapshot. To inspect a shorter run:

```bash
dart tool/simulate.dart --days 30 --seed 42
```

Read [the economic model](docs/economy.md) for formulas, opening endowments,
consumer budgets, supplier policies, FIFO accounting, and snapshot limitations.

The workflow uploads the web build, debug APK, generated Android launcher, and
dependency lockfile as a seven-day artifact. Artifacts are downloads, not a hosted
website. Workflow failures are visible in the repository's Actions tab.

## Architecture

```text
lib/
  main.dart       Flutter entry point and native orientation
  application/    Controller, monotonic playback clock, bounded history/activity
  domain/         Pure Dart entities, FIFO stock, reports, and cash ledger
  simulation/     Seeded daily demand, restocking, pricing AI, and state snapshots
  ui/             Flutter screens and presentation
test/             Automated tests
tool/             SDK installation, verification, and preview scripts
web/              Flutter Web entry point
```

Keep the engine independent of wall-clock time, widgets, and storage. UI timers
will request daily ticks; persistence will serialize game state and the random
generator state outside the engine. Use integer cents for money and explicit
inventory quantities.

## Engine calibration workflow

1. Start paused and advance individual days to inspect accounts and stock.
2. Run at 10× to compare shops over the latest 30 days. Inspect supplier supply,
   unfilled intentions, and segment spending alongside profit and share.
3. Change one assumption in code, rerun with the same seed, and compare results.
   Product demand/prices/costs and segment incomes/sensitivity live in
   `lib/domain/economy.dart`; choice formulas in `lib/simulation/demand.dart`;
   opening capital, daily costs, restocking, and AI in
   `lib/simulation/simulation.dart`. Formulas are documented in
   [docs/economy.md](docs/economy.md).
4. Run `bash tool/check.sh`. The headless CLI and VM/JavaScript replay use the same
   all-automated policy as the dashboard. The long run audits 10,000 days.

The default low-level `Simulation.neighborhood()` retains the original mixed
policy for engine regression experiments. Pass `automateAllStores: true` for
observer runs; the controller and CLI already do. Snapshots preserve this flag;
older snapshots without it retain their original fixed Corner & Co. prices.

The UI is read-only apart from playback and view selection. Engine parameters
are edited in code in this step. Profits are provisional; this is a diagnostic
tool, not a balanced playable game. Next work is evidence-driven calibration and
additional diagnostics where a concrete experiment needs them. Player decisions,
saves, stock markets, manufacturing, patents, R&D, and acquisitions remain deferred.
