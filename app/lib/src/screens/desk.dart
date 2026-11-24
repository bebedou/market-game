import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../home.dart';
import '../l10n.dart';
import '../mail.dart';
import '../theme.dart';
import '../widgets.dart';
import 'books.dart' show explainChange, periodName;
import 'finance.dart' show LettersSection;

/// The desk on the Holding page, the owner's layout A of 2026-11-18: mail
/// first, what waits on the player, each ruled in red like a to-do, then
/// the month's reports in a line or two; then the news.

/// Opens the mail keyed [key] within the current tab.
void openMail(BuildContext context, String key) =>
    context.openPage(tr('mail.title'), (_) => [MailPage(mailKey: key)]);

/// Whether the player has answered [mail]: one of its answers is pending.
MailAnswer? answeredWith(SimulationController game, Mail mail) {
  for (final answer in mail.answers) {
    final command = answer.command;
    if (command == null) continue;
    if (game.pending.any((pending) => '$pending' == '$command')) return answer;
  }
  return null;
}

/// The desk's mail: what waits on the player, then what needs doing at the
/// shops they run, then the reports.
class DeskMail extends StatelessWidget {
  const DeskMail({super.key, required this.onOpen, required this.toDo});

  final OpenTab onOpen;

  /// The shops' to-dos, ruled the same way.
  final List<Widget> toDo;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final mail = mailOf(game);
    final waiting = [
      for (final each in mail)
        if (answeredWith(game, each) == null) each,
    ];
    final count = waiting.length + toDo.length;
    final directed = [
      for (final company in game.activeCompanies)
        if (company.director != null || company.memos.isNotEmpty) company,
    ];
    final weeks = game.reports(ReportPeriod.week);
    final story = weeks.length > 1
        ? explainChange(
            game,
            weeks[weeks.length - 2],
            weeks.length > 2 ? weeks[weeks.length - 3] : null,
          )
        : null;
    return Section(
      title: tr('mail.title'),
      trailing: count == 0
          ? null
          : Text(
              tr('mail.toAnswer', {'count': count}),
              style: theme.textTheme.bodySmall,
            ),
      children: [
        for (final each in mail) _MailLine(mail: each),
        ...toDo,
        if (mail.isEmpty && toDo.isEmpty) Hint(tr('mail.nothing')),
        if (directed.isNotEmpty)
          IndexRow(
            icon: Icons.description_outlined,
            title: tr('mail.reports'),
            subtitle: tr('mail.reportsFrom', {'count': directed.length}),
            onTap: () => context.openPage(
              tr('mail.reports'),
              (context) => [
                for (final company in context.game.activeCompanies)
                  if (company.director != null || company.memos.isNotEmpty)
                    LettersSection(company: company, titled: true),
              ],
            ),
          ),
        if (story != null)
          IndexRow(
            icon: Icons.insights_outlined,
            title: periodName(weeks[weeks.length - 2]),
            subtitle: story.first,
            onTap: () => context.openPage(
              tr('dashboard.lastWeek'),
              (_) => [
                _LastWeek(
                  lines: story,
                  title: periodName(weeks[weeks.length - 2]),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A mail on the desk: ruled in red until answered, its subject, who wrote
/// it and how long it stands; opening it.
class _MailLine extends StatelessWidget {
  const _MailLine({required this.mail});

  final Mail mail;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final answered = answeredWith(game, mail);
    return InkWell(
      onTap: () => openMail(context, mail.key),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: answered == null ? ledger.loss : ledger.rule,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mail.subject, style: theme.textTheme.titleSmall),
                  Text(
                    [
                      mail.from,
                      if (answered != null)
                        tr('mail.answered', {'answer': answered.label})
                      else if (mail.until case final until?)
                        tr('mail.until', {'date': shortDate(until)}),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// How last week went, in a few sentences.
class _LastWeek extends StatelessWidget {
  const _LastWeek({required this.lines, required this.title});

  final List<String> lines;
  final String title;

  @override
  Widget build(BuildContext context) => Section(
    title: title,
    children: [
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(line),
        ),
    ],
  );
}

/// One mail, opened: who wrote it, the letter, its numbers, how long it
/// stands and what happens without an answer, then the answers.
class MailPage extends StatelessWidget {
  const MailPage({super.key, required this.mailKey});

  final String mailKey;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final mail = mailOf(game).where((each) => each.key == mailKey).firstOrNull;
    if (mail == null) return Hint(tr('mail.gone'));
    final answered = answeredWith(game, mail);
    return Section(
      title: mail.from,
      children: [
        if (mail.fromLine case final line?)
          Text(
            line,
            style: theme.textTheme.bodySmall?.copyWith(color: ledger.muted),
          ),
        const SizedBox(height: 10),
        Text(mail.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final paragraph in mail.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(paragraph, style: theme.textTheme.bodyLarge),
          ),
        if (mail.signature case final name?)
          Text(
            tr('mail.signed', {'name': name}),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: titleFont,
              fontStyle: FontStyle.italic,
            ),
          ),
        const SizedBox(height: 8),
        for (final (label, value) in mail.lines) Line(label, value),
        if (mail.until case final until?)
          Hint(
            [
              tr('mail.standsUntil', {'date': shortDate(until)}),
              ?mail.fallback,
            ].join(' '),
          ),
        const SizedBox(height: 8),
        if (answered != null)
          Hint(tr('mail.answeredHint', {'answer': answered.label})),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, answer) in mail.answers.indexed)
              if (i == 0 && answered == null)
                FilledButton(
                  onPressed: () => _answer(context, answer),
                  child: Text(answer.label),
                )
              else
                OutlinedButton(
                  onPressed: answer == answered
                      ? null
                      : () => _answer(context, answer),
                  child: Text(answer.label),
                ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _answer(BuildContext context, MailAnswer answer) {
    if (answer.command case final command?) {
      context.game.submit(command);
    } else {
      answer.open?.call(context);
    }
  }
}

/// The latest news on the desk, and the way to all of it.
class DeskNews extends StatelessWidget {
  const DeskNews({super.key, required this.allNews});

  /// Opens every piece of news.
  final VoidCallback allNews;

  /// How many pieces the desk shows.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final latest = game.alerts.take(_shown).toList();
    return Section(
      title: tr('common.news'),
      children: [
        if (latest.isEmpty) Hint(tr('dashboard.pressPlay')),
        for (final alert in latest) AlertTile(alert),
        if (game.alerts.length > latest.length)
          IndexRow(
            title: tr('mail.allNews'),
            value: '${game.alerts.length}',
            onTap: allNews,
          ),
      ],
    );
  }
}
