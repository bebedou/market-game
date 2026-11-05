import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _package = 'packages/market_content';

/// A language the game can be played in, as `locales/languages.json` lists it.
typedef Language = ({String code, String name});

/// The languages on offer.
Future<List<Language>> loadLanguages() async {
  final list = jsonDecode(
    await rootBundle.loadString('$_package/locales/languages.json'),
  );
  return [
    for (final entry in list as List<Object?>)
      if (entry case {'code': final String code, 'name': final String name})
        (code: code, name: name),
  ];
}

/// The words of one language, flattened to dotted keys: every string the
/// player reads comes from `locales/<code>.json` and the words a scenario
/// brings in `<scenario>.<code>.json`, under `scenario.`. A key this language
/// lacks falls back on [_fallback], so a translation can be partial.
final class Strings {
  Strings(
    this.code, {
    required Map<String, Object?> interface,
    this.scenario = const {},
    Strings? fallback,
  }) : _fallback = fallback {
    _flatten(interface, '', _entries);
    _flatten(scenario, 'scenario.', _entries);
    final singular = _entries['format.singular'];
    if (singular is List<String>) _singular = singular.map(int.parse).toSet();
  }

  final String code;

  /// The words the scenario brings, as written: see [localizedScenario].
  final Map<String, Object?> scenario;
  final Strings? _fallback;
  final _entries = <String, Object>{};

  /// The counts that take a plural entry's `one` form.
  Set<int>? _singular;

  Object? _entry(String key) => _entries[key] ?? _fallback?._entry(key);

  Set<int> get _singularForms =>
      _singular ?? _fallback?._singularForms ?? const {1};

  /// Whether [node] gives a form per count: `other`, and only `one` or exact
  /// counts beside it.
  static bool _isForms(Map<String, Object?> node) =>
      node['other'] is String &&
      node.keys.every(
        (key) => key == 'other' || key == 'one' || int.tryParse(key) != null,
      );

  /// Nests objects into dotted keys. An object of forms per count is one entry,
  /// and so is a list, of strings.
  static void _flatten(
    Map<String, Object?> node,
    String prefix,
    Map<String, Object> into,
  ) {
    node.forEach((key, value) {
      final path = '$prefix$key';
      switch (value) {
        case final String text:
          into[path] = text;
        case final List<Object?> list:
          into[path] = [for (final item in list) '$item'];
        case final Map<String, Object?> forms when _isForms(forms):
          into[path] = forms.map((form, text) => MapEntry(form, '$text'));
        case final Map<String, Object?> inner:
          _flatten(inner, '$path.', into);
      }
    });
  }

  /// The text under [key] with [args] filled in; the form for `args['count']`
  /// if it has forms. Null if neither this language nor its fallback has it.
  String? maybe(String key, [Map<String, Object?> args = const {}]) {
    final String text;
    switch (_entry(key)) {
      case final String plain:
        text = plain;
      case final Map<String, String> forms:
        final count = args['count'];
        text =
            forms['$count'] ??
            (count is int && _singularForms.contains(count)
                ? forms['one']
                : null) ??
            forms['other']!;
      default:
        return null;
    }
    if (args.isEmpty || !text.contains('{')) return text;
    return text.replaceAllMapped(_placeholder, (match) {
      final name = match.group(1)!;
      return args.containsKey(name) ? '${args[name]}' : match.group(0)!;
    });
  }

  /// The list under [key], empty if there is none.
  List<String> list(String key) => switch (_entry(key)) {
    final List<String> items => items,
    _ => const [],
  };

  static final _placeholder = RegExp(r'\{(\w+)\}');
}

Strings? _current;

/// The language in use, once one has loaded.
Strings? get currentStrings => _current;

/// Makes [strings] the language in use.
void useStrings(Strings strings) => _current = strings;

/// Loads the language [code] and makes it the one in use. English backs it up
/// for anything it lacks.
Future<void> useLanguage(String code) async {
  Future<Strings> load(String code, {Strings? fallback}) async => Strings(
    code,
    interface: await _readObject('$_package/locales/$code.json'),
    scenario: await _readObject('$_package/scenarios/prototype.$code.json'),
    fallback: fallback,
  );
  final english = await load('en');
  useStrings(code == 'en' ? english : await load(code, fallback: english));
}

/// The object in the asset at [path], empty if there is none: a language
/// needn't translate the scenario.
Future<Map<String, Object?>> _readObject(String path) async {
  final String text;
  try {
    text = await rootBundle.loadString(path);
  } on FlutterError {
    return const {};
  }
  return jsonDecode(text) as Map<String, Object?>;
}

/// The text the current language has for [key], with [args] filled in where
/// the text says `{name}`. With a `count`, picks the form for that number. The
/// key itself if there is none, so a gap shows rather than breaks.
String tr(String key, [Map<String, Object?> args = const {}]) =>
    _current?.maybe(key, args) ?? key;

/// Like [tr], or null if the current language has nothing for [key].
String? trMaybe(String key, [Map<String, Object?> args = const {}]) =>
    _current?.maybe(key, args);

/// The list of strings the current language has for [key].
List<String> trList(String key) => _current?.list(key) ?? const [];

/// [scenario], a scenario's JSON, with the names [words] gives in place of its
/// own. [words] mirrors the scenario: under a list of things with ids, each id
/// maps to its name, or to an object with its `name` and other forms the
/// interface uses. Whatever it doesn't mention keeps its name, so a scenario
/// without a translation still plays.
String localizedScenario(String scenario, Map<String, Object?> words) {
  final root = jsonDecode(scenario);
  _applyNames(root, words);
  return jsonEncode(root);
}

void _applyNames(Object? node, Object? words) {
  if (words is! Map<String, Object?>) return;
  if (node is List<Object?>) {
    for (final item in node) {
      if (item is! Map<String, Object?>) continue;
      switch (words[item['id']]) {
        case final String name:
          item['name'] = name;
        case {'name': final String name}:
          item['name'] = name;
      }
    }
  } else if (node is Map<String, Object?>) {
    words.forEach((key, value) => _applyNames(node[key], value));
  }
}
