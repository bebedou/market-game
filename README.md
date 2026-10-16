# Market Game

A Flutter foundation for an Android-first convenience-store simulator. This PR
sets up development tooling and a responsive starter screen. **The retail
simulation, dashboard, and local saves are not implemented yet.**

## Start in Codespaces (including from a phone)

1. On GitHub, select the `setup/flutter-codespaces` branch while this setup PR is
   open (use `main` after merging).
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

Codespaces installs Git, curl, unzip, xz, zip, Python, OpenGL support, and Java 17.
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
The workflow uploads the web build, debug APK, generated Android launcher, and
dependency lockfile as a seven-day artifact. Artifacts are downloads, not a hosted
website. Workflow failures are visible in the repository's Actions tab.

## Architecture

```text
lib/
  main.dart       Flutter entry point and native orientation
  domain/         Future pure Dart models; no Flutter imports
  simulation/     Future pure Dart systems; no Flutter imports
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

- Define eight products, aggregated segments totaling 1,000 households, three
  stores, and two suppliers.
- Implement seeded daily demand, budget constraints, inventory purchases, sales,
  operating expenses, and bounded competitor pricing.
- Document demand formulas and accounting assumptions before balancing them.
- Test money transfers, inventory limits, demand responses, save/resume
  reproducibility, and a headless 10,000-day run.
- Build cash/profit, revenue, inventory, pricing, market-share, notification, and
  pause/speed controls (15 seconds per day at 1×; also 3× and 10×).
- Add local saves and validate the complete flow on Android.

Stock markets, manufacturing, patents, R&D, acquisitions, and macroeconomics are
outside the first retail prototype.
