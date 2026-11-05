import 'package:engine/engine.dart';

import 'saves_io.dart'
    if (dart.library.js_interop) 'saves_web.dart'
    as platform;

/// What the main menu shows of a saved game, kept beside it so the menu
/// needn't load the game.
typedef SlotSummary = ({
  String company,
  Day day,
  Money netWorth,

  /// When it was saved, by the device's clock.
  DateTime saved,
});

/// Where one game is kept between sessions.
abstract interface class SaveStore {
  /// The saved game, or null if there is none.
  Future<SaveFile?> read();

  /// Saves [file], with what the menu shows of it.
  Future<void> write(SaveFile file, {SlotSummary? summary});

  /// Keeps [file], a save that couldn't be loaded, out of the way of the
  /// slot, so an update that fails to read it doesn't lose it.
  Future<void> setAside(SaveFile file);

  /// Deletes the saved game for good; the slot is empty after.
  Future<void> delete();
}

/// A saved game in a slot: its summary, null for a game saved before slots
/// kept one.
typedef SavedSlot = ({SlotSummary? summary});

/// The games kept side by side, and the language they are played in.
abstract interface class SaveSlots {
  /// How many games fit.
  static const count = 3;

  /// The language the player chose, null if they haven't.
  Future<String?> language();

  /// Remembers the language the player chose.
  Future<void> setLanguage(String code);

  /// What each slot holds, null for an empty one.
  Future<List<SavedSlot?>> list();

  /// Slot [index]'s game.
  SaveStore slot(int index);
}

/// Files in the app's own storage on phones and desktops; memory only on
/// the web.
SaveSlots defaultSaveSlots() => platform.defaultSaveSlots();

/// Keeps a game in memory, for the web and for tests.
final class MemorySaveStore implements SaveStore {
  SaveFile? file;
  SlotSummary? summary;

  /// Saves set aside, oldest first.
  final List<SaveFile> setAsideFiles = [];

  @override
  Future<SaveFile?> read() async => file;

  @override
  Future<void> write(SaveFile file, {SlotSummary? summary}) async {
    this.file = file;
    this.summary = summary;
  }

  @override
  Future<void> setAside(SaveFile file) async {
    setAsideFiles.add(file);
    if (identical(this.file, file)) {
      this.file = null;
      summary = null;
    }
  }

  @override
  Future<void> delete() async {
    file = null;
    summary = null;
  }
}

/// Every slot in memory.
final class MemorySaveSlots implements SaveSlots {
  final stores = [for (var i = 0; i < SaveSlots.count; i++) MemorySaveStore()];
  String? _language;

  @override
  Future<String?> language() async => _language;

  @override
  Future<void> setLanguage(String code) async => _language = code;

  @override
  Future<List<SavedSlot?>> list() async => [
    for (final store in stores)
      store.file == null ? null : (summary: store.summary),
  ];

  @override
  SaveStore slot(int index) => stores[index];
}

/// The slot whose game was saved last, by the device's clock; a game saved
/// without a summary counts as the oldest. Null if every slot is empty.
int? latestSlot(List<SavedSlot?> slots) {
  int? latest;
  DateTime? when;
  for (final (i, slot) in slots.indexed) {
    if (slot == null) continue;
    final saved = slot.summary?.saved;
    if (latest == null ||
        (saved != null && (when == null || saved.isAfter(when)))) {
      latest = i;
      when = saved;
    }
  }
  return latest;
}
