import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:path_provider/path_provider.dart';

import 'saves.dart';

SaveSlots defaultSaveSlots() => FileSaveSlots();

Future<Directory> _supportFolder() async => getApplicationSupportDirectory();

/// Each slot's game in a file of the app's support directory, its summary
/// in a JSON file beside it. The single autosave of earlier versions moves
/// into the first slot.
final class FileSaveSlots implements SaveSlots {
  FileSaveSlots();

  Future<void>? _migrated;

  Future<void> _migrate() => _migrated ??= () async {
    final folder = await _supportFolder();
    final old = File('${folder.path}/autosave.mgsave');
    final first = File('${folder.path}/${FileSaveStore.fileName(0)}');
    if (await old.exists() && !await first.exists()) {
      await old.rename(first.path);
    }
  }();

  @override
  Future<List<SavedSlot?>> list() async {
    await _migrate();
    final folder = await _supportFolder();
    return [
      for (var i = 0; i < SaveSlots.count; i++)
        await File('${folder.path}/${FileSaveStore.fileName(i)}').exists()
            ? (summary: await FileSaveStore._readSummary(folder, i))
            : null,
    ];
  }

  @override
  SaveStore slot(int index) => FileSaveStore(index, ready: _migrate);

  Future<File> _languageFile() async =>
      File('${(await _supportFolder()).path}/language.txt');

  @override
  Future<String?> language() async {
    final file = await _languageFile();
    return await file.exists() ? (await file.readAsString()).trim() : null;
  }

  @override
  Future<void> setLanguage(String code) async {
    await (await _languageFile()).writeAsString(code);
  }
}

/// One slot's game.
final class FileSaveStore implements SaveStore {
  const FileSaveStore(this.index, {this.ready, this.folder});

  final int index;

  /// Done before touching the files.
  final Future<void> Function()? ready;

  /// Where the files are, if not in the app's support directory.
  final Directory? folder;

  static String fileName(int index) => 'slot${index + 1}.mgsave';

  Future<File> _file() async {
    await ready?.call();
    return File(
      '${(folder ?? await _supportFolder()).path}/${fileName(index)}',
    );
  }

  static File _summaryFile(Directory folder, int index) =>
      File('${folder.path}/slot${index + 1}.json');

  static Future<SlotSummary?> _readSummary(Directory folder, int index) async {
    final file = _summaryFile(folder, index);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return (
        company: json['company']! as String,
        day: Day(json['day']! as int),
        netWorth: Money(json['netWorth']! as int),
        saved: DateTime.parse(json['saved']! as String),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<SaveFile?> read() async {
    final file = await _file();
    return await file.exists() ? SaveFile(await file.readAsBytes()) : null;
  }

  @override
  Future<void> write(SaveFile save, {SlotSummary? summary}) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Written aside first, so a crash mid-write keeps the previous save.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(save.bytes, flush: true);
    await temporary.rename(file.path);
    final side = _summaryFile(file.parent, index);
    if (summary == null) {
      if (await side.exists()) await side.delete();
      return;
    }
    await side.writeAsString(
      jsonEncode({
        'company': summary.company,
        'day': summary.day.number,
        'netWorth': summary.netWorth.cents,
        'saved': summary.saved.toIso8601String(),
      }),
    );
  }

  /// Next to the slot, named for when it was set aside; the slot is empty
  /// after.
  @override
  Future<void> setAside(SaveFile save) async {
    final file = await _file();
    await File(
      '${file.parent.path}/unreadable-${DateTime.now().millisecondsSinceEpoch}.mgsave',
    ).writeAsBytes(save.bytes, flush: true);
    if (await file.exists()) await file.delete();
    final side = _summaryFile(file.parent, index);
    if (await side.exists()) await side.delete();
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    for (final doomed in [
      file,
      File('${file.path}.tmp'),
      _summaryFile(file.parent, index),
    ]) {
      if (await doomed.exists()) await doomed.delete();
    }
  }
}
