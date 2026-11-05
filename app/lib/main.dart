import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';

void main() {
  // The fonts' licences, for the about box.
  LicenseRegistry.addLicense(() async* {
    for (final (fonts, file) in const [
      (['Fraunces'], 'OFL-Fraunces.txt'),
      (['IBM Plex Sans', 'IBM Plex Mono'], 'OFL-IBMPlex.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks(
        fonts,
        await rootBundle.loadString('assets/fonts/$file'),
      );
    }
  });
  runApp(const MarketGameApp());
}
