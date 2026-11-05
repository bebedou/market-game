import '../core/ids.dart';
import '../core/money.dart';

/// Why a command was refused: which message, and what goes in it. The engine
/// has no words of its own; the interface words [key] in the player's language.
final class Refusal {
  const Refusal(
    this.key, {
    this.amount,
    this.count,
    this.product,
    this.supplier,
    this.format,
    this.toFormat,
  });

  final String key;
  final Money? amount;
  final int? count;
  final ProductId? product;
  final SupplierId? supplier;

  /// The format it is about; [toFormat] the one a store would become.
  final FormatId? format;
  final FormatId? toFormat;

  @override
  String toString() => [
    key,
    if (amount != null) 'amount: ${amount!.toDecimalString()}',
    if (count != null) 'count: $count',
    if (product != null) 'product: ${product!.index}',
    if (supplier != null) 'supplier: ${supplier!.index}',
    if (format != null) 'format: ${format!.index}',
    if (toFormat != null) 'toFormat: ${toFormat!.index}',
  ].join(' ');
}
