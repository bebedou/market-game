import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../widgets.dart';

/// Sets up a new game: only the holding's name, the player starting their
/// first business from the dashboard. Returns the [GameStart] chosen, or
/// null if the player goes back.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, required this.content});

  final ContentDb content;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GameStart get _start => GameStart.holding(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final (terms, _) = startTerms(widget.content, _start);
    // What the player starts with, whatever the name.
    final (cash, _) = startTerms(widget.content, const GameStart.holding('-'));
    return Scaffold(
      appBar: AppBar(title: Text(tr('common.newGame'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          Section(
            title: tr('newGame.yourHolding'),
            icon: Icons.account_balance_outlined,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: maxNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('newGame.holdingLabel'),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (terms != null) Navigator.of(context).pop(_start);
                },
              ),
              if (cash != null)
                Hint(
                  tr('newGame.holdingHint', {
                    'cash': money(cash.personalCash, cents: false),
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: terms == null
                  ? null
                  : () => Navigator.of(context).pop(_start),
              label: Text(tr('newGame.start')),
            ),
          ),
        ],
      ),
    );
  }
}
