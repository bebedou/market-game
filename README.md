# Market Game

An Android-first convenience-store simulator with a pure Dart retail economy.
The headless engine models 1,000 households, three stores, two suppliers, and eight
products with seeded daily demand and auditable accounting. The Flutter screen
is still the environment starter; the playable dashboard and local-save adapter
are the next milestones.

See [ROADMAP.md](ROADMAP.md) for detailed implementation steps, dependencies,
and acceptance criteria for the first playable release.

## GitHub Pages preview

The `Deploy Flutter to GitHub Pages` workflow publishes the web starter on pushes
to `main` or `setup/flutter-codespaces`. It builds with the Pages subdirectory as
Flutter's base path, so JavaScript and assets resolve correctly under
`/market-game/`. The expected default URL is https://bebedou.github.io/market-game/;
the successful deployment's environment URL is authoritative.

The workflow attempts to enable Pages automatically. If GitHub denies initial
site creation, an administrator must open **Settings → Pages**, select **GitHub
Actions** as the source, and rerun the deployment. Pages is enabled for this public repository. The deployment does not
change repository visibility. The hosted screen is still a status screen; the headless engine is implemented,
and the playable dashboard is the next milestone.

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

`flutter pub get` generates `pubspec.lock`. Commit it after the first verified
setup so dependency versions are locked for the application; it is not ignored.

## Checks

```bash
bash tool/check.sh
```

This formats Dart, runs `flutter analyze --fatal-infos`, runs widget tests at phone
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

## Next development milestone

The engine and its accounting, demand, inventory, determinism, snapshot-resume,
and 10,000-day tests are implemented. Next:
- Build cash/profit, revenue, inventory, pricing, market-share, notification, and
  pause/speed controls (15 seconds per day at 1×; also 3× and 10×).
- Add local saves and validate the complete flow on Android.

Stock markets, manufacturing, patents, R&D, acquisitions, and macroeconomics are
outside the first retail prototype.
