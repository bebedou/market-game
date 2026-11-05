import 'dart:io';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/saves_io.dart';

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('market_game_saves');
  });

  tearDown(() async {
    await folder.delete(recursive: true);
  });

  List<String> files() =>
      [for (final entity in folder.listSync()) entity.uri.pathSegments.last]
        ..sort();

  test('deleting a saved game removes its files and only its files', () async {
    final first = FileSaveStore(0, folder: folder);
    final second = FileSaveStore(1, folder: folder);
    final save = SaveFile(Uint8List.fromList([1, 2, 3]));
    final summary = (
      company: 'Corner Shop',
      day: const Day(1000),
      netWorth: Money.parse('35000.00'),
      saved: DateTime(2026, 11, 4),
    );
    await first.write(save, summary: summary);
    await second.write(save, summary: summary);
    expect(files(), [
      'slot1.json',
      'slot1.mgsave',
      'slot2.json',
      'slot2.mgsave',
    ]);

    await first.delete();
    expect(await first.read(), isNull);
    expect(files(), ['slot2.json', 'slot2.mgsave']);
    expect((await second.read())?.bytes, save.bytes);

    // Deleting an empty slot does nothing.
    await first.delete();
    expect(files(), ['slot2.json', 'slot2.mgsave']);
  });
}
