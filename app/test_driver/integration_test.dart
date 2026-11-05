import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves the tour's screenshots in `$UX_OUT`, or `screenshots/`.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final folder = Platform.environment['UX_OUT'] ?? 'screenshots';
    File('$folder/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return true;
  },
);
