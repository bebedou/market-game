import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/money.dart';

/// A problem in a scenario file or the national table, with the JSON path
/// where it was found.
final class ContentException implements Exception {
  ContentException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() {
    final where = path.isEmpty ? 'the root' : path;
    return 'Invalid scenario at $where: $message';
  }
}

/// A JSON object being read, which remembers its path for error messages and
/// which fields were read, so that [finish] can reject the rest: a scenario,
/// the national table and its calibration are all read with it.
final class JsonNode {
  JsonNode(this.path, Object? value)
    : _map = switch (value) {
        final Map<String, Object?> map => map,
        _ => throw ContentException(path, 'expected an object'),
      };

  final String path;
  final Map<String, Object?> _map;
  final _read = <String>{};

  Iterable<String> get keys => _map.keys;

  String pathOf(String key) => path.isEmpty ? key : '$path.$key';

  Object? _value(String key) {
    _read.add(key);
    return _map[key];
  }

  Never fail(String key, String message) =>
      throw ContentException(pathOf(key), message);

  String string(String key) => optionalString(key) ?? fail(key, 'missing');

  /// A string field, without counting it as read: for a key that must be
  /// looked up before the field is read in its turn.
  String peek(String key) => switch (_map[key]) {
    final String text => text,
    null => fail(key, 'missing'),
    _ => fail(key, 'expected a string'),
  };

  String? optionalString(String key) => switch (_value(key)) {
    final String text => text,
    null => null,
    _ => fail(key, 'expected a string'),
  };

  bool flag(String key) => switch (_value(key)) {
    null => false,
    final bool value => value,
    _ => fail(key, 'expected true or false'),
  };

  int? optionalPositiveInt(String key) => switch (_value(key)) {
    null => null,
    final int value when value > 0 => value,
    _ => fail(key, 'expected a positive whole number'),
  };

  int positiveInt(String key) =>
      optionalPositiveInt(key) ?? fail(key, 'missing');

  int nonNegativeInt(String key) => switch (_value(key)) {
    final int value when value >= 0 => value,
    null => fail(key, 'missing'),
    _ => fail(key, 'expected a whole number, 0 or more'),
  };

  Fx fx(String key) {
    final text = switch (_value(key)) {
      final String text => text,
      null => fail(key, 'missing'),
      _ => fail(key, 'expected a decimal string such as "0.05"'),
    };
    try {
      return Fx.parse(text);
    } on FormatException catch (e) {
      fail(key, e.message);
    }
  }

  Fx nonNegativeFx(String key) {
    final value = fx(key);
    if (value.isNegative) fail(key, 'must not be negative');
    return value;
  }

  /// A share, rate or probability: a decimal from 0 to 1.
  Fx fraction(String key) {
    final value = fx(key);
    if (value.isNegative || value > Fx.one) fail(key, 'must be from 0 to 1');
    return value;
  }

  /// A list of strings. When [optional], a missing list is empty.
  List<String> strings(String key, {bool optional = false}) =>
      switch (_value(key)) {
        final List<Object?> list => [
          for (var i = 0; i < list.length; i++)
            switch (list[i]) {
              final String text => text,
              _ => throw ContentException(
                '${pathOf(key)}[$i]',
                'expected a string',
              ),
            },
        ],
        null when optional => const [],
        null => fail(key, 'missing'),
        _ => fail(key, 'expected a list'),
      };

  /// A list of whole numbers, 0 or more.
  List<int> nonNegativeInts(String key) => switch (_value(key)) {
    final List<Object?> list => [
      for (var i = 0; i < list.length; i++)
        switch (list[i]) {
          final int value when value >= 0 => value,
          _ => throw ContentException(
            '${pathOf(key)}[$i]',
            'expected a whole number, 0 or more',
          ),
        },
    ],
    null => fail(key, 'missing'),
    _ => fail(key, 'expected a list'),
  };

  Money money(String key) {
    final text = switch (_value(key)) {
      final String text => text,
      null => fail(key, 'missing'),
      _ => fail(key, 'expected a decimal string such as "1.50"'),
    };
    try {
      return Money.parse(text);
    } on FormatException catch (e) {
      fail(key, e.message);
    }
  }

  Money positiveMoney(String key) {
    final value = money(key);
    if (value <= Money.zero) fail(key, 'must be positive');
    return value;
  }

  Day date(String key) {
    try {
      return Day.parse(string(key));
    } on FormatException catch (e) {
      fail(key, e.message);
    }
  }

  T choice<T extends Enum>(String key, List<T> values) {
    final text = string(key);
    for (final value in values) {
      if (value.name == text) return value;
    }
    final allowed = values.map((value) => value.name).join(', ');
    fail(key, 'expected one of: $allowed');
  }

  JsonNode object(String key) =>
      JsonNode(pathOf(key), _value(key) ?? fail(key, 'missing'));

  JsonNode? optionalObject(String key) => switch (_value(key)) {
    null => null,
    final value => JsonNode(pathOf(key), value),
  };

  /// An object kept as plain JSON, not read field by field; null if
  /// missing.
  Map<String, Object?>? optionalMap(String key) => switch (_value(key)) {
    null => null,
    final Map<String, Object?> map => map,
    _ => fail(key, 'expected an object'),
  };

  bool has(String key) => _map.containsKey(key);

  /// A multiplier on the usual, from 0.3 to 3; 1 if missing.
  Fx level(String key) {
    if (!has(key)) return Fx.one;
    final value = fx(key);
    if (value < Fx.parse('0.3') || value > Fx.fromInt(3)) {
      fail(key, 'must be from 0.3 to 3');
    }
    return value;
  }

  /// A yearly rate of change, either way: a decimal from -0.5 to 0.5.
  Fx yearlyRate(String key) {
    final value = fx(key);
    if (value < Fx.parse('-0.5') || value > Fx.parse('0.5')) {
      fail(key, 'must be from -0.5 to 0.5');
    }
    return value;
  }

  /// A list of objects. When [optional], a missing list is empty.
  List<JsonNode> objects(String key, {bool optional = false}) =>
      switch (_value(key)) {
        final List<Object?> list => [
          for (var i = 0; i < list.length; i++)
            JsonNode('${pathOf(key)}[$i]', list[i]),
        ],
        null when optional => const [],
        null => fail(key, 'missing'),
        _ => fail(key, 'expected a list'),
      };

  /// Fails on any field that wasn't read.
  void finish() {
    for (final key in _map.keys) {
      if (!_read.contains(key)) fail(key, 'unknown field');
    }
  }
}
