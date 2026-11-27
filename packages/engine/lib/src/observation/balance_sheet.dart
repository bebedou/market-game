import '../accounting/ledger.dart';
import '../core/money.dart';

/// A company's balance sheet at book value, from its accounts: what it
/// holds and what it owes, each as a positive amount. Public, as filed
/// accounts are.
final class BalanceSheet {
  const BalanceSheet({
    required this.cash,
    required this.inventories,
    required this.receivables,
    required this.fixedAssets,
    required this.goodwill,
    required this.shareholdings,
    required this.payables,
    required this.loans,
  });

  BalanceSheet.of(Accounts accounts)
    : cash = accounts[AccountKind.cash],
      inventories = accounts[AccountKind.inventory],
      receivables = accounts[AccountKind.receivables],
      fixedAssets = accounts[AccountKind.fixedAssets],
      goodwill = accounts[AccountKind.businessAssets],
      shareholdings = accounts[AccountKind.investments],
      payables = -accounts[AccountKind.payables],
      loans = -accounts[AccountKind.loans];

  final Money cash;

  /// Stock at cost.
  final Money inventories;

  /// What buyers owe it.
  final Money receivables;

  /// Shop fittings and plants at cost less depreciation.
  final Money fixedAssets;

  /// What it paid for shops and chains bought beyond their stock and
  /// fittings.
  final Money goodwill;

  /// Its stakes in other companies, at cost.
  final Money shareholdings;

  /// Bills it owes, and what it has borrowed.
  final Money payables;
  final Money loans;

  Money get assets =>
      cash + inventories + receivables + fixedAssets + goodwill + shareholdings;

  Money get liabilities => payables + loans;

  /// Its book value: what it holds less what it owes.
  Money get equity => assets - liabilities;

  /// Its loans less its cash; below zero for net cash.
  Money get netDebt => loans - cash;
}
