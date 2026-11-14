import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:market_game/src/l10n.dart';
import 'package:market_game/src/outlines.dart';

/// Reads the language [code] from the content package.
Strings stringsFromFiles(String code, {Strings? fallback}) {
  Map<String, Object?> read(String path) =>
      jsonDecode(File('../content/$path').readAsStringSync())
          as Map<String, Object?>;
  return Strings(
    code,
    interface: read('locales/$code.json'),
    scenario: read('scenarios/prototype.$code.json'),
    fallback: fallback,
  );
}

/// Every test file plays in English unless it says otherwise.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  useStrings(stringsFromFiles('en'));
  useOutlines(
    parseOutlines(
      File('../content/countries/outlines.json').readAsStringSync(),
    ),
  );
  await testMain();
}
