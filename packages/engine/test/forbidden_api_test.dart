@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Constructs that break cross-platform determinism if used in engine code.
/// Checked against code with comments and string literals removed.
final _forbidden = <String, RegExp>{
  'double/num types': RegExp(r'\b(double|num)\b'),
  'floating-point literal': RegExp(r'\b\d+\.\d+\b|\b\d+[eE][+-]?\d+\b'),
  '`/` (it produces a double; use ~/ or mulDivRound)': RegExp(
    r'(?<![~/*])/(?![/*])',
  ),
  'wall-clock time': RegExp(r'\bDateTime\.now\b'),
  'unordered collections': RegExp(r'\bHash(Map|Set)\b'),
  'run-dependent hashes': RegExp(
    r'\b(hashCode|identityHashCode)\b|Object\.hash',
  ),
  'dart:math Random': RegExp(r'\bRandom\b'),
};

void main() {
  test('engine code avoids non-deterministic APIs', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(RegExp(r'//.*'), '');
        if (code.contains('dart:math')) {
          violations.add('${file.path}:${i + 1}: dart:math');
        }
        final bare = code.replaceAll(
          RegExp(
            r"'[^']*'|"
            r'"[^"]*"',
          ),
          "''",
        );
        for (final MapEntry(key: name, value: pattern) in _forbidden.entries) {
          if (pattern.hasMatch(bare)) {
            violations.add(
              '${file.path}:${i + 1}: $name\n    ${lines[i].trim()}',
            );
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
