# Market Game app

The Flutter app over the engine in `../packages/engine`. It bundles the
scenario from `../content` and saves the game in the app's own storage.

## Run it on an Android phone

1. On the phone, turn on Developer options (tap *Build number* seven times in
   *Settings > About phone*), then turn on *USB debugging*.
2. Plug the phone in and accept the debugging prompt on it.
3. From this folder:

   ```bash
   flutter devices
   flutter run
   ```

   Or in Android Studio with the Flutter plugin (SDK path set to your Flutter
   folder), pick the phone and the *Market Game* run configuration.

`flutter build apk --debug` makes `build/app/outputs/flutter-apk/app-debug.apk`
to copy onto a phone instead.

## Run it in a browser

`flutter run -d chrome` works for development. Saves stay in memory there.

## Tests

```bash
flutter test
```
