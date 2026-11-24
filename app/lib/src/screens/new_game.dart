import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../widgets.dart';

/// Sets up a new game: the holding's name and the money it starts with,
/// the player starting their first business from the dashboard. Returns the
/// [GameStart] chosen, or null if the player goes back.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, required this.content});

  final ContentDb content;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  final _name = TextEditingController();
  final _cash = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    super.dispose();
  }

  /// What the scenario starts a holding with.
  late final Money? _usual = startTerms(
    widget.content,
    const GameStart.holding('-'),
  ).$1?.personalCash;

  /// The money typed, or the scenario's if none; null if not an amount.
  Money? get _money =>
      _cash.text.trim().isEmpty ? _usual : parseMoney(_cash.text);

  GameStart get _start => GameStart.holding(
    _name.text.trim(),
    // The scenario's own amount stays the scenario's.
    cash: _money == _usual ? null : _money,
  );

  @override
  Widget build(BuildContext context) {
    final money_ = _money;
    final (terms, refusal) = money_ == null
        ? (null, null)
        : startTerms(widget.content, _start);
    if (_cash.text.isEmpty && _usual != null) {
      _cash.text = moneyInput(_usual);
    }
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
              TextField(
                controller: _cash,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: tr('newGame.cashLabel'),
                  errorText: money_ == null
                      ? tr('common.notAnAmount')
                      : refusal?.key == 'startCashRange'
                      ? tr('refusals.startCashRange')
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Hint(
                tr('newGame.holdingHint', {
                  'cash': money(money_ ?? Money.zero, cents: false),
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
