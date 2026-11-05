import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

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
