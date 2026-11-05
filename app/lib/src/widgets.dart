import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';
import 'theme.dart';
import 'visuals.dart';

/// Gives the widgets below it the game, and rebuilds them when it changes.
class GameScope extends InheritedNotifier<SimulationController> {
  const GameScope({
    super.key,
    required SimulationController controller,
    required super.child,
  }) : super(notifier: controller);

  static SimulationController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameScope>()!.notifier!;

  /// The game, without rebuilding on its changes: for `initState`.
  static SimulationController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GameScope>()!.notifier!;
}

extension GameContext on BuildContext {
  SimulationController get game => GameScope.of(this);
}

/// A section of the ledger: a serif title over an ink rule, then its
/// figures and actions. No card: the rules do the separating.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.mark,
    required this.children,
  });

  final String title;

  /// What the section is about, for those who read the screen aloud; the
  /// ledger shows no icons by its titles.
  final IconData? icon;
  final Widget? trailing;

  /// A colour marking whose section it is, such as a store's trade, shown
  /// before the title and as its rule.
  final Color? mark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = mark ?? theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (mark != null) ...[TradeMark(mark!), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 5),
          Container(height: 1.2, color: ink),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// A page opened within a tab: its title, for the way back from pages
/// opened on it, and the sections it shows.
typedef SubPage = ({String title, List<Widget> Function(BuildContext) build});

/// Opens pages within the current tab, keeping the clock and the tabs.
class SubPages extends InheritedWidget {
  const SubPages({super.key, required this.open, required super.child});

  final void Function(SubPage page) open;

  @override
  bool updateShouldNotify(SubPages old) => false;
}

extension PageContext on BuildContext {
  /// Opens a page of [build]'s sections, named [title], within the current
  /// tab.
  void openPage(String title, List<Widget> Function(BuildContext) build) =>
      getInheritedWidgetOfExactType<SubPages>()!.open((
        title: title,
        build: build,
      ));
}

/// A line of a ledger's contents: a title, a line on what it holds, a
/// figure, and a way in.
class IndexRow extends StatelessWidget {
  const IndexRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.mark,
    this.stamp,
    this.icon,
    required this.onTap,
  });

  final String title;
  final String? subtitle;

  /// A figure on the right, such as a total.
  final String? value;
  final Color? valueColor;

  /// A trade's colour, for a store.
  final Color? mark;

  /// Trouble to stamp on it, in red.
  final String? stamp;

  /// An icon before the title, for an action rather than a page.
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            if (mark != null) ...[
              TradeMark(mark!, size: 10),
              const SizedBox(width: 10),
            ],
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if (subtitle case final subtitle?)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (stamp case final stamp?) ...[
              const SizedBox(width: 8),
              Stamp(stamp),
            ],
            if (value case final value?) ...[
              const SizedBox(width: 10),
              Text(
                value,
                style: figures(
                  theme.textTheme.bodyLarge,
                ).copyWith(color: valueColor),
              ),
            ],
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// A small square in a trade's colour, marking a store or company.
class TradeMark extends StatelessWidget {
  const TradeMark(this.color, {super.key, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ColoredBox(color: color),
  );
}

/// A label and its value on one line.
class Line extends StatelessWidget {
  const Line(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.color,
    this.hint,
  });

  final String label;
  final String value;
  final bool strong;
  final Color? color;

  /// Smaller text under the label.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (hint case final hint?)
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // A long value, in words, wraps rather than pushing the row wide.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.45,
            ),
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: figures(style).copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muted explanatory text.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Green for gains and red for losses; null for no change.
Color? gainColor(BuildContext context, int sign) =>
    sign == 0 ? null : gainTone(context, sign);

/// Asks for an amount of money. Null if cancelled.
Future<Money?> askAmount(
  BuildContext context, {
  required String title,
  String? message,
  Money? initial,
  String? action,
}) => showDialog<Money>(
  context: context,
  builder: (context) => _AmountDialog(
    title: title,
    message: message,
    initial: initial,
    action: action ?? tr('common.ok'),
  ),
);

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.message,
    required this.initial,
    required this.action,
  });

  final String title;
  final String? message;
  final Money? initial;
  final String action;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _text = TextEditingController(
    text: switch (widget.initial) {
      final amount? => moneyInput(amount),
      null => '',
    },
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseMoney(_text.text);
    if (amount == null || amount <= Money.zero) {
      setState(() => _error = tr('widgets.enterAmount'));
      return;
    }
    Navigator.pop(context, amount);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message case final message?) ...[
          Text(message),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('common.cancel')),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// A small −/+ stepper around a number.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    required this.max,
    this.label,
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool enabled;

  /// Shown instead of the value.
  final String? label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        tooltip: tr('widgets.fewer'),
        onPressed: enabled && value > min ? () => onChanged(value - 1) : null,
      ),
      SizedBox(
        width: 48,
        child: Text(label ?? '$value', textAlign: TextAlign.center),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        tooltip: tr('widgets.more'),
        onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
      ),
    ],
  );
}

/// Lets the player pick which of their stores to look at, across every
/// company and city.
Future<void> showStorePicker(BuildContext context, SimulationController game) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final content = game.content;
        final selected = game.store?.id;
        final stores = game.myStores;
        final companies = [
          for (final company in game.view.companies)
            if (company.stores.isNotEmpty) company,
        ];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  tr('common.yourStores'),
                  style: theme.textTheme.titleLarge,
                ),
                for (final company in companies) ...[
                  if (companies.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 2),
                      child: Text(
                        game.companyName(company.id),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  for (final (owner, store) in stores)
                    if (owner.id == company.id)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          store.status == StoreStatus.closed
                              ? Icons.store_mall_directory_outlined
                              : Icons.storefront,
                        ),
                        title: Text(game.storeName(store.id)),
                        subtitle: Text(
                          [
                            content.sites[store.site.index].name,
                            if (content.markets.length > 1)
                              content.markets[store.market.index].name,
                            if (store.status == StoreStatus.closed)
                              tr('common.closedLower'),
                          ].join(' · '),
                        ),
                        trailing: store.id == selected
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          game.selectStore(store.id);
                          Navigator.pop(context);
                        },
                      ),
                ],
              ],
            ),
          ),
        );
      },
    );
