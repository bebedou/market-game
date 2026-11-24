import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../business.dart';
import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../widgets.dart';

/// Restructuring, the owner's layout A (2026-11-18): the levers sit where
/// things are, each opening a sheet with the price, the tax and both
/// companies' worth before and after. Inside the group at book value: down
/// the tree as capital, sideways for cash, up as a dividend in kind at the
/// dividend rate. Outside, sold on the spot.

/// How something moves between two companies of the player's.
enum _Way { down, sideways, up }

/// Whether [ancestor] holds [company], directly or through others.
bool _holds(SimulationController game, CompanyId ancestor, CompanyId company) {
  var parent = _company(game, company)?.parent;
  while (parent != null) {
    if (parent == ancestor) return true;
    parent = _company(game, parent)?.parent;
  }
  return false;
}

CompanyView? _company(SimulationController game, CompanyId id) =>
    game.view.companies.where((each) => each.id == id).firstOrNull;

_Way _way(SimulationController game, CompanyId from, CompanyId to) =>
    _holds(game, from, to)
    ? _Way.down
    : _holds(game, to, from)
    ? _Way.up
    : _Way.sideways;

/// The dividend rate where the player lives.
Fx _rate(SimulationController game) =>
    game.content.taxesOf(game.residence)?.dividendRate ?? Fx.zero;

/// [before] → [after], in short.
String _change(Money before, Money after) => tr('restructure.change', {
  'before': compactMoney(before),
  'after': compactMoney(after),
});

/// Moving, making a company of its own, or selling [business] of
/// [company].
class MoveOrSellSection extends StatelessWidget {
  const MoveOrSellSection({
    super.key,
    required this.company,
    required this.business,
  });

  final CompanyView company;
  final Business business;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final key = briefKey(game.content, business);
    final deal = company.deals[key];
    if (company.status != CompanyStatus.active || deal == null) {
      return const SizedBox.shrink();
    }
    final others = [
      for (final other in game.activeCompanies)
        if (other.id != company.id) other,
    ];
    void sheet(Widget child) => showGameSheet(context, game, child);
    return Section(
      title: tr('restructure.moveOrSell'),
      children: [
        if (others.isNotEmpty)
          IndexRow(
            icon: Icons.swap_horiz,
            title: tr('restructure.moveTo'),
            subtitle: tr('restructure.moveToPitch'),
            onTap: () => sheet(
              _MoveBusinessSheet(
                company: company,
                business: business,
                businessKey: key,
                deal: deal,
              ),
            ),
          ),
        IndexRow(
          icon: Icons.domain_add_outlined,
          title: tr('restructure.ownCompany'),
          subtitle: tr('restructure.ownCompanyPitch', {
            'company': game.companyName(company.id),
          }),
          onTap: () => sheet(
            _OwnCompanySheet(
              company: company,
              business: business,
              businessKey: key,
              deal: deal,
            ),
          ),
        ),
        IndexRow(
          icon: Icons.sell_outlined,
          title: tr('restructure.sell'),
          subtitle: tr('restructure.buyers.${business.kind.name}'),
          value: tr('restructure.about', {'amount': compactMoney(deal.worth)}),
          onTap: () => sheet(
            _SellBusinessSheet(
              company: company,
              business: business,
              businessKey: key,
              deal: deal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Merging, moving under another company, or selling [company] whole.
List<Widget> companyRestructureRows(BuildContext context, CompanyView company) {
  final game = context.game;
  if (company.status != CompanyStatus.active) return const [];
  void sheet(Widget child) => showGameSheet(context, game, child);
  final into = _mergeTargets(game, company);
  final under = _homes(game, company);
  return [
    if (into.isNotEmpty)
      IndexRow(
        icon: Icons.merge,
        title: tr('restructure.merge'),
        subtitle: tr('restructure.mergePitch'),
        onTap: () => sheet(_MergeSheet(company: company)),
      ),
    if (under.isNotEmpty)
      IndexRow(
        icon: Icons.account_tree_outlined,
        title: tr('restructure.moveUnder'),
        subtitle: tr('restructure.moveUnderPitch'),
        onTap: () => sheet(_MoveCompanySheet(company: company)),
      ),
    IndexRow(
      icon: Icons.sell_outlined,
      title: tr('restructure.sellCompany'),
      subtitle: tr('restructure.sellCompanyPitch'),
      value: switch (company.sale) {
        (:final price, refusal: null) => compactMoney(price),
        _ => null,
      },
      onTap: () => sheet(_SellCompanySheet(company: company)),
    ),
  ];
}

/// Where [company] may merge: into its parent, or a company beside it.
List<CompanyView> _mergeTargets(
  SimulationController game,
  CompanyView company,
) => [
  for (final other in game.activeCompanies)
    if (other.id != company.id &&
        (other.id == company.parent || other.parent == company.parent))
      other,
];

/// Where [company] may move: under any company of the player's but itself
/// and its own, or the holding (null) when another holds it.
List<CompanyId?> _homes(SimulationController game, CompanyView company) => [
  if (company.parent != null) null,
  for (final other in game.activeCompanies)
    if (other.id != company.id &&
        other.id != company.parent &&
        !_holds(game, company.id, other.id))
      other.id,
];

/// A sheet's title and its companies to pick from, the one picked ticked.
List<Widget> _picker(
  BuildContext context, {
  required String title,
  required String question,
  required List<CompanyId?> options,
  required CompanyId? picked,
  required bool chosen,
  required ValueChanged<CompanyId?> onPick,
}) {
  final game = context.game;
  final theme = Theme.of(context);
  return [
    Text(title, style: theme.textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(question, style: theme.textTheme.titleSmall),
    for (final option in options)
      ChoiceTile(
        selected: chosen && option == picked,
        title: option == null
            ? tr('restructure.theHolding')
            : game.companyName(option),
        subtitle: switch (option) {
          final id? => compactMoney(
            SimulationController.worthOf(_company(game, id)!),
          ),
          null => null,
        },
        onTap: () => onPick(option),
      ),
  ];
}

/// The submit button of a sheet: [label], doing [command] then closing.
Widget _go(BuildContext context, String label, Command? command) =>
    FilledButton(
      onPressed: command == null
          ? null
          : () {
              context.game.submit(command);
              Navigator.pop(context);
            },
      child: Text(label),
    );

class _MoveBusinessSheet extends StatefulWidget {
  const _MoveBusinessSheet({
    required this.company,
    required this.business,
    required this.businessKey,
    required this.deal,
  });

  final CompanyView company;
  final Business business;
  final String businessKey;
  final BusinessDeal deal;

  @override
  State<_MoveBusinessSheet> createState() => _MoveBusinessSheetState();
}

class _MoveBusinessSheetState extends State<_MoveBusinessSheet> {
  CompanyId? _to;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final from = widget.company;
    final options = [
      for (final other in game.activeCompanies)
        if (other.id != from.id) other.id,
    ];
    final to = _to == null ? null : _company(game, _to!);
    final deal = widget.deal;
    return SheetFrame(
      footer: _go(
        context,
        tr('restructure.moveIt'),
        to == null
            ? null
            : MoveBusiness(
                game.player,
                company: from.id,
                business: widget.businessKey,
                to: to.id,
              ),
      ),
      children: [
        ..._picker(
          context,
          title: tr('restructure.moveTitle', {
            'business': widget.business.name,
          }),
          question: tr('restructure.intoWhich'),
          options: options,
          picked: _to,
          chosen: _to != null,
          onPick: (id) => setState(() => _to = id),
        ),
        if (to != null) ...[
          const SizedBox(height: 12),
          ..._moveLines(game, from, to, deal),
        ],
        Hint(tr('restructure.moveHint')),
      ],
    );
  }
}

/// What moving a business worth [deal] from [from] to [to] does: how it is
/// paid, the tax, and both companies' worth before and after.
List<Widget> _moveLines(
  SimulationController game,
  CompanyView from,
  CompanyView to,
  BusinessDeal deal,
) {
  final way = _way(game, from.id, to.id);
  final tax = way == _Way.up ? deal.book.times(_rate(game)) : Money.zero;
  final fromWorth = SimulationController.worthOf(from);
  final toWorth = SimulationController.worthOf(to);
  final (fromAfter, toAfter) = switch (way) {
    _Way.down => (fromWorth, toWorth + deal.worth),
    _Way.up => (fromWorth - deal.worth, toWorth - tax),
    _Way.sideways => (
      fromWorth - deal.worth + deal.book,
      toWorth + deal.worth - deal.book,
    ),
  };
  final names = {
    'from': game.companyName(from.id),
    'to': game.companyName(to.id),
    'amount': money(deal.book, cents: false),
    'rate': percent(_rate(game), decimals: 0),
  };
  return [
    Line(tr('restructure.paid'), tr('restructure.way.${way.name}', names)),
    Line(
      tr('restructure.tax'),
      tax > Money.zero ? money(tax, cents: false) : tr('restructure.noTax'),
    ),
    Line(
      tr('restructure.worthOf', {'company': names['from']}),
      _change(fromWorth, fromAfter),
    ),
    Line(
      tr('restructure.worthOf', {'company': names['to']}),
      _change(toWorth, toAfter),
    ),
  ];
}

class _OwnCompanySheet extends StatefulWidget {
  const _OwnCompanySheet({
    required this.company,
    required this.business,
    required this.businessKey,
    required this.deal,
  });

  final CompanyView company;
  final Business business;
  final String businessKey;
  final BusinessDeal deal;

  @override
  State<_OwnCompanySheet> createState() => _OwnCompanySheetState();
}

class _OwnCompanySheetState extends State<_OwnCompanySheet> {
  late final _name = TextEditingController(text: widget.business.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final name = _name.text.trim();
    final from = game.companyName(widget.company.id);
    return SheetFrame(
      footer: _go(
        context,
        tr('restructure.makeIt'),
        name.isEmpty
            ? null
            : MoveBusiness(
                game.player,
                company: widget.company.id,
                business: widget.businessKey,
                name: name,
              ),
      ),
      children: [
        Text(
          tr('restructure.ownTitle', {'business': widget.business.name}),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          maxLength: maxNameLength,
          decoration: InputDecoration(labelText: tr('restructure.newName')),
          onChanged: (_) => setState(() {}),
        ),
        Line(
          tr('restructure.paid'),
          tr('restructure.way.down', {
            'from': from,
            'to': name.isEmpty ? tr('restructure.newCompany') : name,
            'amount': money(widget.deal.book, cents: false),
          }),
        ),
        Line(tr('restructure.tax'), tr('restructure.noTax')),
        Hint(tr('restructure.ownHint', {'company': from})),
      ],
    );
  }
}

class _SellBusinessSheet extends StatelessWidget {
  const _SellBusinessSheet({
    required this.company,
    required this.business,
    required this.businessKey,
    required this.deal,
  });

  final CompanyView company;
  final Business business;
  final String businessKey;
  final BusinessDeal deal;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final name = game.companyName(company.id);
    return SheetFrame(
      footer: _go(
        context,
        tr('restructure.sellFor', {'amount': compactMoney(deal.worth)}),
        deal.buyer
            ? SellBusiness(
                game.player,
                company: company.id,
                business: businessKey,
              )
            : null,
      ),
      children: [
        Text(
          tr('restructure.sellTitle', {'business': business.name}),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Line(tr('restructure.price'), money(deal.worth, cents: false)),
        Line(tr('restructure.book'), money(deal.book, cents: false)),
        Hint(tr('restructure.buyers.${business.kind.name}')),
        Hint(
          deal.buyer
              ? tr('restructure.moneyTo', {'company': name})
              : tr('refusals.noBuyer'),
        ),
      ],
    );
  }
}

class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.company});

  final CompanyView company;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  CompanyId? _into;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = widget.company;
    final into = _into == null ? null : _company(game, _into!);
    final up = into != null && into.id == company.parent;
    final kept = company.retainedEarnings;
    final tax = up && kept > Money.zero ? kept.times(_rate(game)) : Money.zero;
    final worth = SimulationController.worthOf(company);
    return SheetFrame(
      footer: _go(
        context,
        tr('restructure.mergeIt'),
        into == null
            ? null
            : MergeCompany(game.player, company: company.id, into: into.id),
      ),
      children: [
        ..._picker(
          context,
          title: tr('restructure.mergeTitle', {
            'company': game.companyName(company.id),
          }),
          question: tr('restructure.intoWhich'),
          options: [for (final other in _mergeTargets(game, company)) other.id],
          picked: _into,
          chosen: _into != null,
          onPick: (id) => setState(() => _into = id),
        ),
        if (into != null) ...[
          const SizedBox(height: 12),
          Line(
            tr('restructure.tax'),
            tax > Money.zero
                ? money(tax, cents: false)
                : tr('restructure.noTax'),
          ),
          Line(
            tr('restructure.worthOf', {'company': game.companyName(into.id)}),
            _change(
              SimulationController.worthOf(into),
              SimulationController.worthOf(into) + (up ? -tax : worth),
            ),
          ),
          Hint(
            up
                ? tr('restructure.mergeUpHint', {
                    'rate': percent(_rate(game), decimals: 0),
                  })
                : tr('restructure.mergeBesideHint', {
                    'into': game.companyName(into.id),
                  }),
          ),
        ],
        Hint(tr('restructure.mergeHint')),
      ],
    );
  }
}

class _MoveCompanySheet extends StatefulWidget {
  const _MoveCompanySheet({required this.company});

  final CompanyView company;

  @override
  State<_MoveCompanySheet> createState() => _MoveCompanySheetState();
}

class _MoveCompanySheetState extends State<_MoveCompanySheet> {
  /// The new parent; the holding if null, once [_picked].
  CompanyId? _under;
  bool _picked = false;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final company = widget.company;
    final value = company.injected;
    final from = company.parent;
    final under = _under;
    // The levels it climbs, each paying the rate, when it moves up.
    var levels = 0;
    var way = _Way.sideways;
    if (_picked) {
      if (from == null) {
        way = _Way.down;
      } else if (under == null || _holds(game, under, from)) {
        way = _Way.up;
        var at = from;
        while (at != under) {
          levels++;
          final parent = _company(game, at)?.parent;
          if (parent == null) break;
          at = parent;
        }
      } else if (_holds(game, from, under)) {
        way = _Way.down;
      }
    }
    final tax = value.times(_rate(game)).timesInt(levels);
    final names = {
      'from': from == null
          ? tr('restructure.theHolding')
          : game.companyName(from),
      'to': under == null
          ? tr('restructure.theHolding')
          : game.companyName(under),
      'amount': money(value, cents: false),
      'rate': percent(_rate(game), decimals: 0),
    };
    return SheetFrame(
      footer: _go(
        context,
        tr('restructure.moveIt'),
        _picked
            ? MoveCompany(game.player, company: company.id, under: under)
            : null,
      ),
      children: [
        ..._picker(
          context,
          title: tr('restructure.moveUnderTitle', {
            'company': game.companyName(company.id),
          }),
          question: tr('restructure.underWhich'),
          options: _homes(game, company),
          picked: under,
          chosen: _picked,
          onPick: (id) => setState(() {
            _under = id;
            _picked = true;
          }),
        ),
        if (_picked) ...[
          const SizedBox(height: 12),
          Line(
            tr('restructure.paid'),
            tr('restructure.companyWay.${way.name}', names),
          ),
          Line(
            tr('restructure.tax'),
            tax > Money.zero
                ? money(tax, cents: false)
                : tr('restructure.noTax'),
          ),
        ],
        Hint(tr('restructure.moveUnderHint')),
      ],
    );
  }
}

class _SellCompanySheet extends StatelessWidget {
  const _SellCompanySheet({required this.company});

  final CompanyView company;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final sale = company.sale;
    final ready = sale != null && sale.refusal == null;
    return SheetFrame(
      footer: _go(
        context,
        ready
            ? tr('restructure.sellFor', {'amount': compactMoney(sale.price)})
            : tr('restructure.sellCompany'),
        ready ? SellCompany(game.player, company: company.id) : null,
      ),
      children: [
        Text(
          tr('restructure.sellCompanyTitle', {
            'company': game.companyName(company.id),
          }),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (sale != null && sale.price > Money.zero)
          Line(tr('restructure.price'), money(sale.price, cents: false)),
        Hint(
          ready
              ? company.parent == null
                    ? tr('restructure.moneyToHolding')
                    : tr('restructure.moneyTo', {
                        'company': game.companyName(company.parent!),
                      })
              : tr('refusals.${sale?.refusal ?? 'nothingForSale'}'),
        ),
        Hint(tr('restructure.sellCompanyHint')),
      ],
    );
  }
}
