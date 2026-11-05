import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../controller.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../saves.dart';
import '../theme.dart';
import 'guide.dart';
import 'new_game.dart';

/// The first screen: carry on with the latest game, start a new one, pick
/// one of the saved games, or read how to play.
class MainMenu extends StatefulWidget {
  const MainMenu({
    super.key,
    required this.content,
    required this.saves,
    this.languages = const [],
    this.language,
    this.onLanguage,
  });

  final ContentDb content;
  final SaveSlots saves;

  /// The languages to choose from, the one in use, and what choosing does.
  final List<Language> languages;
  final String? language;
  final ValueChanged<String>? onLanguage;

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  late Future<List<SavedSlot?>> _slots = widget.saves.list();
  bool _busy = false;

  void _refresh() => setState(() {
    _slots = widget.saves.list();
  });

  void _tell(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _play(int slot) async {
    if (_busy) return;
    _busy = true;
    final (game, notice) = await openGame(
      widget.content,
      widget.saves.slot(slot),
    );
    _busy = false;
    if (!mounted) return;
    if (game == null) {
      if (notice != null) _tell(notice);
      _refresh();
      return;
    }
    await _enter(game);
  }

  /// Plays [game] until the player leaves it, then saves it.
  Future<void> _enter(SimulationController game) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(controller: game)),
    );
    game.pause();
    await game.save();
    game.dispose();
    if (mounted) _refresh();
  }

  Future<void> _newGame(List<SavedSlot?> slots) async {
    var slot = slots.indexWhere((saved) => saved == null);
    if (slot < 0) {
      final replaced = await _replace(slots);
      if (replaced == null || !mounted) return;
      slot = replaced;
    }
    final start = await Navigator.of(context).push<GameStart>(
      MaterialPageRoute(builder: (_) => NewGameScreen(content: widget.content)),
    );
    if (start == null || !mounted) return;
    final game = SimulationController.newGame(
      widget.content,
      seed: newSeed(),
      start: start,
      saves: widget.saves.slot(slot),
    );
    await game.save();
    if (!mounted) return;
    await _enter(game);
  }

  /// Asks, then deletes the game in [slot] for good.
  Future<void> _delete(int slot, SlotSummary? summary) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(
            tr('menu.deleteTitle', {
              'game': summary?.company ?? tr('menu.thisGame'),
            }),
          ),
          content: Text(
            summary == null
                ? tr('menu.goneForGood')
                : tr('menu.gameGoneForGood', {
                    'date': longDate(summary.day),
                    'worth': money(summary.netWorth, cents: false),
                  }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('common.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('common.delete')),
            ),
          ],
        );
      },
    );
    if (yes != true) return;
    await widget.saves.slot(slot).delete();
    if (mounted) _refresh();
  }

  /// Which full slot the new game replaces; null if the player changes
  /// their mind.
  Future<int?> _replace(List<SavedSlot?> slots) => showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('menu.replaceWhich')),
      children: [
        for (final (i, slot) in slots.indexed)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, i),
            child: Text(_describe(slot!.summary, i)),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 16, top: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('common.cancel')),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _chooseLanguage() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('menu.language')),
        children: [
          for (final language in widget.languages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, language.code),
              child: Text(language.name),
            ),
        ],
      ),
    );
    if (code != null) widget.onLanguage?.call(code);
  }

  static String _describe(SlotSummary? summary, int slot) => summary == null
      ? tr('menu.gameNumber', {'number': slot + 1})
      : tr('menu.gameSummary', {
          'company': summary.company,
          'date': longDate(summary.day),
        });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: FutureBuilder(
        future: _slots,
        builder: (context, snapshot) {
          final slots = snapshot.data;
          final latest = slots == null ? null : latestSlot(slots);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                children: [
                  Text(
                    tr('app.title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Container(height: 2, color: theme.colorScheme.onSurface),
                  const SizedBox(height: 8),
                  Text(
                    tr('scenario.tagline'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (slots == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (latest != null)
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _play(latest),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        label: Text(
                          tr('menu.continue', {
                            'game': _describe(slots[latest]!.summary, latest),
                          }),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (latest == null)
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        onPressed: () => _newGame(slots),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        label: Text(tr('common.newGame')),
                      )
                    else
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        onPressed: () => _newGame(slots),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        label: Text(tr('common.newGame')),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      tr('menu.yourGames'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final (i, slot) in slots.indexed)
                      _SlotCard(
                        index: i,
                        slot: slot,
                        onTap: slot == null ? null : () => _play(i),
                        onDelete: slot == null
                            ? null
                            : () => _delete(i, slot.summary),
                      ),
                  ],
                  const SizedBox(height: 20),
                  TextButton.icon(
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HowToPlayScreen(),
                      ),
                    ),
                    label: Text(tr('common.howToPlay')),
                  ),
                  if (widget.onLanguage != null && widget.languages.length > 1)
                    TextButton.icon(
                      icon: const Icon(Icons.language),
                      onPressed: _chooseLanguage,
                      label: Text(
                        widget.languages
                            .firstWhere(
                              (language) => language.code == widget.language,
                              orElse: () => widget.languages.first,
                            )
                            .name,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.index,
    required this.slot,
    this.onTap,
    this.onDelete,
  });

  final int index;
  final SavedSlot? slot;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = slot?.summary;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        leading: Text(
          '${index + 1}',
          style: figures(theme.textTheme.titleMedium).copyWith(
            color: slot == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
        title: Text(
          slot == null
              ? tr('menu.empty')
              : summary?.company ?? tr('menu.savedGame'),
          style: slot == null
              ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
        subtitle: summary == null
            ? (slot == null ? null : Text(tr('menu.earlierVersion')))
            : Text(
                tr('menu.slotDetails', {
                  'date': longDate(summary.day),
                  'worth': money(summary.netWorth, cents: false),
                  'played': calendarDate(summary.saved),
                }),
              ),
        trailing: slot == null
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: tr('menu.deleteThis'),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: onDelete,
              ),
      ),
    );
  }
}
