import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';
import 'widgets.dart';

/// The loan lengths offered, in months.
const loanTerms = [12, 36, 60, 84];

/// The longest of [loanTerms] the bank allows: what a purchase starts with,
/// for the smallest payments.
int longestTerm(ContentDb content) => loanTerms.lastWhere(
  (months) => months <= content.finance.maxTermMonths,
  orElse: () => content.finance.maxTermMonths,
);

/// How many years of a company's earnings the bank lends without a
/// guarantee, such as "2 years".
String earningsYears(ContentDb content) {
  final years = content.finance.earningsMultiple;
  return tr(years == Fx.one ? 'loans.oneYear' : 'loans.years', {
    'years': fxText(years),
  });
}

/// [amount] rounded up to a hundred; zero if it is not above zero.
Money roundedUp(Money amount) {
  const hundred = 10000;
  return amount <= Money.zero
      ? Money.zero
      : Money((amount.cents + hundred - 1) ~/ hundred * hundred);
}

/// About what [amount] lent at [rate] over [months] costs its first month:
/// its share of the principal and a month's interest.
Money firstPayment(Money amount, Fx rate, int months) =>
    Money(amount.cents ~/ months) + Money(amount.times(rate).cents ~/ 12);

/// How a new business costing [cost] is paid for: from [company]'s cash
/// beyond its bills, orders and cushion (none for a new company), the
/// [capital] the player puts in, and the rest borrowed if [borrow] says
/// so, or, left unsaid, if those fall [short] of it. [amount] is the rest,
/// rounded up, and [terms] the bank's for it.
({Money short, Money amount, bool borrow, LoanTerms terms}) newBusinessFunding(
  SimulationController game, {
  required CompanyView? company,
  required Money cost,
  required Money capital,
  required bool? borrow,
  required int months,
  required ValueChanged<int> onMonths,
}) {
  final view = game.view;
  final spare =
      (company == null
          ? Money.zero
          : company.cash - company.committed - game.cushion(company)) +
      capital;
  final short = cost - (company?.cash ?? Money.zero) - capital;
  final amount = roundedUp(cost - spare);
  final room = company == null
      ? Money.zero
      : view.companyCredits[company.id.index] ?? Money.zero;
  // The capital put in no longer backs a guarantee.
  final guarantee =
      view.guaranteeRoom -
      capital.times(game.content.finance.guaranteeMultiple);
  return (
    short: short,
    amount: amount,
    borrow: amount > Money.zero && (borrow ?? short > Money.zero),
    terms: LoanTerms(
      view: view,
      content: game.content,
      amount: amount,
      credit: room.isNegative ? Money.zero : room,
      guarantee: guarantee.isNegative ? Money.zero : guarantee,
      months: months,
      onMonths: onMonths,
      note: company == null ? tr('market.newCompanyNote') : null,
    ),
  );
}

/// What the player puts into a new business from their own [cash]; marked
/// wrong unless [valid].
class CapitalField extends StatelessWidget {
  const CapitalField({
    super.key,
    required this.controller,
    required this.cash,
    required this.valid,
    required this.onChanged,
    this.from,
  });

  final TextEditingController controller;

  /// The cash it comes from: the holding's, or [from], the parent's.
  final Money cash;
  final String? from;
  final bool valid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: from == null
          ? tr('market.capitalFromCash')
          : tr('businesses.capitalFrom', {'company': from}),
      helperText: from == null
          ? tr('market.youHave', {'cash': money(cash)})
          : tr('businesses.hasCash', {'cash': money(cash)}),
      errorText: valid ? null : tr('common.notAnAmount'),
    ),
    onChanged: (_) => onChanged(),
  );
}

/// The player's company a new business goes in, when they have one still
/// trading and nothing picked: the one they last looked at.
CompanyId? currentCompany(SimulationController game) {
  final company = game.company;
  return company != null && company.status == CompanyStatus.active
      ? company.id
      : null;
}

/// Which company a new business goes in: one of the player's companies
/// still trading, or a company of its own; with what that means.
class CompanyPicker extends StatelessWidget {
  const CompanyPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The company picked; null for one of its own.
  final CompanyId? value;
  final ValueChanged<CompanyId?> onChanged;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return DropdownButtonFormField<CompanyId?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('business.inCompany'),
        helperText: value == null
            ? tr('market.ownBooks')
            : tr('market.ownedBy', {'company': game.companyName(value!)}),
        helperMaxLines: 2,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('business.ownCompany'))),
        for (final company in game.activeCompanies)
          DropdownMenuItem(
            value: company.id,
            child: Text(game.companyName(company.id)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Whether to borrow the rest of a purchase from the bank. Off, it says
/// how much the buyer is [short], or that borrowing keeps the cushion.
class BorrowSwitch extends StatelessWidget {
  const BorrowSwitch({
    super.key,
    required this.value,
    required this.short,
    required this.onChanged,
  });

  final bool value;
  final Money short;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(tr('market.borrowFromBank')),
    subtitle: value
        ? null
        : Text(
            short > Money.zero
                ? tr('market.needsMore', {'amount': money(short, cents: false)})
                : tr('market.keepCushion'),
          ),
    value: value,
    onChanged: onChanged,
  );
}

/// The bank's terms for borrowing [amount] towards a purchase: lent on the
/// buyer's earnings as far as [credit] goes, then on the player's guarantee
/// up to [guarantee]. The player picks how long to repay it over; the rates
/// and about what the first month costs follow.
class LoanTerms extends StatelessWidget {
  const LoanTerms({
    super.key,
    required this.view,
    required this.content,
    required this.amount,
    required this.credit,
    required this.guarantee,
    required this.months,
    required this.onMonths,
    this.label,
    this.note,
  });

  final Observation view;
  final ContentDb content;
  final Money amount;
  final Money credit;
  final Money guarantee;
  final int months;
  final ValueChanged<int> onMonths;

  /// What the borrowing is called, if not borrowing the rest.
  final String? label;

  /// Said under the payments, such as what the store bought earns.
  final String? note;

  /// How the bank lends [amount]; null if it won't lend that much.
  ({Money unsecured, Money guaranteed})? get split =>
      splitLoan(amount, credit: credit, guarantee: guarantee);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Fx rate({required bool guaranteed}) => lendingRate(
      content,
      view.macro.policyRate,
      view.today,
      guaranteed: guaranteed,
      lastBankruptcy: view.lastBankruptcy,
    );
    final split = this.split;
    String hint({bool guaranteed = false}) =>
        '${[if (guaranteed) tr('loans.guaranteedHint'), tr('loans.falling'), ?note].join('. ')}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Line(
          label ?? tr('loans.borrowRest'),
          money(amount, cents: false),
          strong: true,
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final option in loanTerms)
              if (option <= content.finance.maxTermMonths)
                ChoiceChip(
                  label: Text(termName(option)),
                  selected: option == months,
                  onSelected: (_) => onMonths(option),
                ),
          ],
        ),
        const SizedBox(height: 4),
        if (split == null)
          Text(
            tr(
              guarantee > Money.zero ? 'loans.limitGuaranteed' : 'loans.limit',
              {'amount': money(credit + guarantee, cents: false)},
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (split.unsecured == Money.zero ||
            split.guaranteed == Money.zero)
          Line(
            tr('common.perYear', {
              'amount': percent(
                rate(guaranteed: split.unsecured == Money.zero),
              ),
            }),
            tr('common.perMonth', {
              'amount': money(
                firstPayment(
                  amount,
                  rate(guaranteed: split.unsecured == Money.zero),
                  months,
                ),
                cents: false,
              ),
            }),
            hint: hint(guaranteed: split.unsecured == Money.zero),
          )
        else ...[
          Line(
            tr('loans.onEarnings', {'rate': percent(rate(guaranteed: false))}),
            money(split.unsecured, cents: false),
          ),
          Line(
            tr('loans.guaranteedRate', {
              'rate': percent(rate(guaranteed: true)),
            }),
            money(split.guaranteed, cents: false),
            hint: tr('loans.ifFails'),
          ),
          Line(
            tr('loans.firstPayment'),
            tr('common.perMonth', {
              'amount': money(
                firstPayment(split.unsecured, rate(guaranteed: false), months) +
                    firstPayment(
                      split.guaranteed,
                      rate(guaranteed: true),
                      months,
                    ),
                cents: false,
              ),
            }),
            hint: hint(),
          ),
        ],
      ],
    );
  }
}
