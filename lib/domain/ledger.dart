const outsideAccount = 'outside';

enum TransferKind { income, retailSale, wholesaleSale, procurement, operatingCost }

class CashTransfer {
  const CashTransfer(this.from, this.to, this.amount, this.kind);
  final String from;
  final String to;
  final int amount;
  final TransferKind kind;

  Map<String, Object> toJson() => {
        'from': from, 'to': to, 'amount': amount, 'kind': kind.name,
      };

  static CashTransfer fromJson(Map<String, dynamic> j) => CashTransfer(
        j['from'] as String, j['to'] as String, j['amount'] as int,
        TransferKind.values.byName(j['kind'] as String),
      );
}

/// Every cash change passes through here. Only the outside account may be negative.
class Ledger {
  Ledger(Map<String, int> balances)
      : _balances = Map.of(balances),
        _opening = Map.of(balances),
        _entries = [],
        conservedCash = balances.values.fold(0, (a, b) => a + b) {
    validate();
  }

  Ledger._(this._balances, this._opening, this.conservedCash, this._entries) {
    validate();
  }

  final Map<String, int> _balances;
  Map<String, int> _opening;
  final int conservedCash;
  List<CashTransfer> _entries;
  Map<String, int> get balances => Map.unmodifiable(_balances);
  List<CashTransfer> get entries => List.unmodifiable(_entries);
  int get totalCash => _balances.values.fold(0, (a, b) => a + b);
  int balance(String id) => _balances[id] ?? (throw ArgumentError('Unknown account: $id'));

  void beginDay() {
    _opening = Map.of(_balances);
    _entries = [];
  }

  void transfer(String from, String to, int amount, TransferKind kind) {
    if (amount <= 0 || from == to) {
      throw ArgumentError('Invalid transfer.');
    }
    final available = balance(from);
    final destination = balance(to);
    if (from != outsideAccount && available < amount) {
      throw StateError('Insufficient cash in $from.');
    }
    _balances[from] = available - amount;
    _balances[to] = destination + amount;
    _entries.add(CashTransfer(from, to, amount, kind));
  }

  void validate() {
    if (!_balances.containsKey(outsideAccount) || totalCash != conservedCash ||
        _balances.entries.any((e) => e.key != outsideAccount && e.value < 0)) {
      throw StateError('Cash conservation or solvency violated.');
    }
    final reconstructed = Map<String, int>.of(_opening);
    for (final t in _entries) {
      if (t.amount <= 0 || t.from == t.to ||
          !reconstructed.containsKey(t.from) || !reconstructed.containsKey(t.to)) {
        throw StateError('Invalid journal entry.');
      }
      reconstructed[t.from] = reconstructed[t.from]! - t.amount;
      reconstructed[t.to] = reconstructed[t.to]! + t.amount;
    }
    if (reconstructed.length != _balances.length ||
        _balances.entries.any((e) => reconstructed[e.key] != e.value)) {
      throw StateError('Cash journal does not reconcile with balances.');
    }
  }

  Map<String, Object> toJson() => {
        'balances': Map<String, int>.of(_balances),
        'opening': Map<String, int>.of(_opening),
        'conservedCash': conservedCash,
        'entries': [for (final e in _entries) e.toJson()],
      };

  static Ledger fromJson(Map<String, dynamic> j) => Ledger._(
        Map<String, int>.from(j['balances'] as Map),
        Map<String, int>.from(j['opening'] as Map),
        j['conservedCash'] as int,
        [for (final e in j['entries'] as List)
          CashTransfer.fromJson(e as Map<String, dynamic>)],
      );
}
