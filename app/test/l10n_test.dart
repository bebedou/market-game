import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/src/controller.dart';
import 'package:market_game/src/format.dart';
import 'package:market_game/src/l10n.dart';

import 'flutter_test_config.dart';
import 'support.dart';

Map<String, Object?> _read(String path) =>
    jsonDecode(File('../content/$path').readAsStringSync())
        as Map<String, Object?>;

bool _isForms(Map<String, Object?> node) =>
    node['other'] is String &&
    node.keys.every(
      (key) => key == 'other' || key == 'one' || int.tryParse(key) != null,
    );

/// Every leaf under [node] by dotted key: a string, a list or plural forms.
Map<String, Object?> _leaves(Map<String, Object?> node, [String prefix = '']) {
  final leaves = <String, Object?>{};
  node.forEach((key, value) {
    if (value is Map<String, Object?> && !_isForms(value)) {
      leaves.addAll(_leaves(value, '$prefix$key.'));
    } else {
      leaves['$prefix$key'] = value;
    }
  });
  return leaves;
}

final _placeholder = RegExp(r'\{(\w+)\}');

Set<String> _names(String text) => {
  for (final match in _placeholder.allMatches(text)) match.group(1)!,
};

/// The placeholders [value] fills, whichever of its forms is used.
Set<String> _placeholders(Object? value) => switch (value) {
  final String text => _names(text),
  final Map<String, Object?> forms => {
    for (final form in forms.values) ..._names('$form'),
  },
  _ => const {},
};

Iterable<File> _dartFiles(String folder) => Directory(folder)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The keys a tr( call may use and the names its map gives, from just inside
/// its open bracket at [start] in [source].
({Set<String> keys, Set<String> given}) _callAt(String source, int start) {
  final keys = <String>{};
  final given = <String>{};
  var depth = 0;
  var inMap = false;
  var i = start;
  final string = RegExp(r"'((?:[^'\\]|\\.)*)'");
  while (i < source.length) {
    final c = source[i];
    if (c == "'") {
      final match = string.matchAsPrefix(source, i);
      if (match == null) break;
      final text = match.group(1)!;
      final after = source.substring(match.end).trimLeft();
      if (!inMap && depth == 0 && RegExp(r'^\w+(\.\w+)+$').hasMatch(text)) {
        keys.add(text);
      } else if (inMap && depth == 1 && after.startsWith(':')) {
        given.add(text);
      }
      i = match.end;
      continue;
    }
    if (c == '(' || c == '[') depth++;
    if (c == '{') {
      if (depth == 0) inMap = true;
      depth++;
    }
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
    }
    i++;
  }
  return (keys: keys, given: given);
}

void main() {
  final english = _leaves(_read('locales/en.json'));

  /// Keys the code builds from an enum's names, with what makes them up.
  final built = {
    'alerts.kinds': [for (final kind in AlertKind.values) kind.name],
    'terms.slots': [for (final slot in DaySlot.values) slot.name],
    'terms.causes': [for (final cause in SwitchCause.values) cause.name],
    'terms.growth': [for (final growth in Growth.values) growth.name],
    'terms.duties': [for (final duty in ManagerDuty.values) duty.name],
    'terms.misses': [for (final miss in MissReason.values) miss.name],
  };

  tearDown(() => useStrings(stringsFromFiles('en')));

  group('every language', () {
    for (final code in ['fr', 'es']) {
      final language = _leaves(_read('locales/$code.json'));

      test('$code has every key English has, and no others', () {
        expect(language.keys.toSet().difference(english.keys.toSet()), isEmpty);
        expect(english.keys.toSet().difference(language.keys.toSet()), isEmpty);
      });

      test('$code fills the same placeholders as English', () {
        for (final MapEntry(:key, :value) in english.entries) {
          // A form of one needn't say its count.
          final theirs = _placeholders(language[key]);
          final ours = _placeholders(value);
          expect(
            theirs.difference(ours),
            isEmpty,
            reason: '$key names placeholders English does not fill',
          );
          expect(
            ours.difference(theirs).difference({'count'}),
            isEmpty,
            reason: '$key drops what English says',
          );
        }
      });

      test('$code gives forms and lists the shape English does', () {
        for (final MapEntry(:key, :value) in english.entries) {
          expect(language[key].runtimeType, value.runtimeType, reason: key);
          if (value is List && key != 'format.singular') {
            expect(
              (language[key]! as List),
              hasLength(value.length),
              reason: key,
            );
          }
        }
      });
    }

    test('the languages listed each have their words', () {
      final languages =
          jsonDecode(
                File('../content/locales/languages.json').readAsStringSync(),
              )
              as List<Object?>;
      expect(languages, hasLength(3));
      for (final language in languages) {
        final code = (language! as Map)['code'];
        expect(File('../content/locales/$code.json').existsSync(), isTrue);
        expect(
          File('../content/scenarios/prototype.$code.json').existsSync(),
          isTrue,
        );
      }
    });
  });

  group('the code asks for', () {
    test('only keys English has', () {
      final call = RegExp(r"""\btr(?:Maybe|List)?\(\s*'([^'$]+)'""");
      final keys = <String>{};
      for (final file in _dartFiles('lib')) {
        for (final match in call.allMatches(file.readAsStringSync())) {
          keys.add(match.group(1)!);
        }
      }
      expect(keys.length, greaterThan(700));
      final overlay = _leaves(
        _read('scenarios/prototype.en.json'),
        'scenario.',
      );
      for (final key in keys) {
        // Formats and the few statement lines are looked up by table.
        expect(
          english.containsKey(key) || overlay.containsKey(key),
          isTrue,
          reason: key,
        );
      }
    });

    test('keys it builds from names', () {
      for (final MapEntry(key: group, value: names) in built.entries) {
        for (final name in names) {
          expect(
            english.containsKey('$group.$name'),
            isTrue,
            reason: '$group.$name',
          );
        }
      }
    });

    test('every refusal the engine can make', () {
      final call = RegExp(r"""Refusal\(\s*'(\w+)'""");
      final keys = <String>{};
      for (final file in _dartFiles('../packages/engine/lib')) {
        for (final match in call.allMatches(file.readAsStringSync())) {
          keys.add(match.group(1)!);
        }
      }
      expect(keys.length, greaterThan(60));
      for (final key in keys) {
        expect(english.containsKey('refusals.$key'), isTrue, reason: key);
      }
    });

    test('nothing still written out in the screens', () {
      // Text handed straight to a widget, the commonest way to slip back.
      final literal = RegExp(r"""\b(Text|Hint|Pill)\(\s*'[^'$]*[A-Za-z]""");
      for (final file in _dartFiles('lib')) {
        expect(
          literal.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('and gives each text what it says', () {
      // Each tr( call's key or keys, then the names in its map.
      for (final file in _dartFiles('lib')) {
        final source = file.readAsStringSync();
        for (final call in RegExp(r'\btr\(').allMatches(source)) {
          final (:keys, :given) = _callAt(source, call.end);
          for (final key in keys) {
            final text = english[key];
            if (text == null) continue; // A table's key; checked above.
            final missing = _placeholders(text).difference(given);
            expect(missing, isEmpty, reason: '$key in ${file.path}');
          }
        }
      }
    });
  });

  group('the scenario words', () {
    final scenario = _read('scenarios/prototype.json');

    Set<String> idsOf(Object? list) => {
      for (final item in list! as List<Object?>) (item! as Map)['id'] as String,
    };

    for (final code in ['en', 'fr', 'es']) {
      test('$code names only what the scenario has', () {
        final words = _read('scenarios/prototype.$code.json');
        void check(String section, Object? ours, Object? theirs) {
          if (theirs is! Map<String, Object?>) return;
          expect(
            theirs.keys.toSet().difference(idsOf(ours)),
            isEmpty,
            reason: section,
          );
        }

        for (final section in [
          'categories', 'formats', 'products', 'segments', 'research', //
          'strategies', 'sites', 'companies', 'stores',
        ]) {
          check(section, scenario[section], words[section]);
        }
        check(
          'managers',
          (scenario['managers']! as Map)['grades'],
          (words['managers']! as Map)['grades'],
        );
        check(
          'directors',
          (scenario['directors']! as Map)['grades'],
          (words['directors']! as Map)['grades'],
        );
        check(
          'regimes',
          (scenario['macro']! as Map)['regimes'],
          (words['macro']! as Map)['regimes'],
        );
      });

      test('$code says how to name each kind of thing', () {
        useStrings(stringsFromFiles(code, fallback: stringsFromFiles('en')));
        final content = loadScenario(
          localizedScenario(
            File('../content/scenarios/prototype.json').readAsStringSync(),
            currentStrings!.scenario,
          ),
        );
        for (final format in content.formats) {
          expect(
            trMaybe('scenario.formats.${format.key}.a'),
            isNotNull,
            reason: format.key,
          );
          expect(
            trMaybe('scenario.formats.${format.key}.blurb'),
            isNotNull,
            reason: format.key,
          );
        }
        for (final grade in content.managers.grades) {
          for (final form in ['one', 'a', 'many']) {
            expect(
              trMaybe('scenario.managers.grades.${grade.key}.$form'),
              isNotNull,
              reason: '${grade.key} $form',
            );
          }
        }
        for (final grade in content.directors!.grades) {
          expect(
            trMaybe('scenario.directors.grades.${grade.key}.a'),
            isNotNull,
          );
        }
        for (final regime in content.macro.regimes) {
          expect(trMaybe('scenario.macro.regimes.${regime.key}.a'), isNotNull);
        }
        for (final tier in content.researchTiers) {
          expect(trMaybe('scenario.research.${tier.key}.a'), isNotNull);
        }
        expect(trMaybe('scenario.country'), isNotNull);
        expect(trMaybe('scenario.tagline'), isNotNull);
      });
    }

    test('names change with the language and nothing else does', () {
      final source = File(
        '../content/scenarios/prototype.json',
      ).readAsStringSync();
      final english = loadScenario(source);
      final french = loadScenario(
        localizedScenario(source, _read('scenarios/prototype.fr.json')),
      );
      expect(french.formats.first.name, 'Supérette');
      expect(french.products.first.name, 'Lait économique 1 L');
      expect(french.structure.length, english.structure.length);
      for (final (i, list) in english.structure.indexed) {
        expect(french.structure[i].keys, list.keys);
      }
      // A rival keeps its brand, and a place not translated its name.
      expect(
        french.companies.map((company) => company.name),
        contains('QuickStop Market'),
      );
      expect(french.sites.map((site) => site.name), contains('Rue de Cuire'));
    });

    test('a scenario with no words of its own still plays', () {
      final source = File(
        '../content/scenarios/prototype.json',
      ).readAsStringSync();
      expect(
        loadScenario(localizedScenario(source, const {})).formats.first.name,
        loadScenario(source).formats.first.name,
      );
    });

    test(
      'a save made in one language loads in another, and plays the same',
      () {
        final source = File(
          '../content/scenarios/prototype.json',
        ).readAsStringSync();
        final english = loadScenario(source);
        final french = loadScenario(
          localizedScenario(source, _read('scenarios/prototype.fr.json')),
        );
        final inEnglish = Simulation.newGame(english, seed: 3);
        for (var i = 0; i < 40; i++) {
          inEnglish.step();
        }
        final resumed = Simulation.load(french, inEnglish.save());
        for (var i = 0; i < 40; i++) {
          inEnglish.step();
          resumed.step();
        }
        expect(resumed.stateHash(), inEnglish.stateHash());
      },
    );
  });

  group('words', () {
    test('a count picks its form, the exact one first', () {
      expect(tr('common.stores', {'count': 1}), '1 store');
      expect(tr('common.stores', {'count': 0}), '0 stores');
      expect(tr('common.stores', {'count': 3}), '3 stores');
      expect(tr('dashboard.lastWeeks', {'count': 1}), 'Last week');
      expect(tr('dashboard.lastWeeks', {'count': 4}), 'Last 4 weeks');
      useStrings(stringsFromFiles('fr', fallback: stringsFromFiles('en')));
      // French treats nought as singular.
      expect(tr('common.stores', {'count': 0}), '0 magasin');
      expect(tr('common.stores', {'count': 2}), '2 magasins');
      useStrings(stringsFromFiles('es', fallback: stringsFromFiles('en')));
      expect(tr('common.stores', {'count': 0}), '0 tiendas');
    });

    test('a key a language lacks falls back on English, then shows itself', () {
      final partial = Strings(
        'xx',
        interface: const {
          'common': {'cancel': 'Nope'},
        },
        fallback: stringsFromFiles('en'),
      );
      useStrings(partial);
      expect(tr('common.cancel'), 'Nope');
      expect(tr('common.delete'), 'Delete');
      expect(tr('no.such.key'), 'no.such.key');
      expect(trMaybe('no.such.key'), isNull);
    });

    test('a placeholder not given stays as it is', () {
      expect(tr('common.perDay'), '{amount} a day');
    });
  });

  group('figures and dates follow the language', () {
    final day = Day.parse('2026-03-05');

    test('English', () {
      expect(money(Money.parse('1234.5')), '1,235');
      expect(money(Money.parse('12.5')), '12.50');
      expect(percent(Fx.parse('0.125')), '12.5%');
      expect(share(1, 4), '25%');
      expect(shortDate(day), '5 Mar');
      expect(longDate(day), 'Thu 5 Mar 2026');
      expect(monthName(day), 'March 2026');
      expect(termName(36), '3 years');
      expect(termName(12), '1 year');
      expect(termName(18), '18 months');
      expect(cushionLength(14), '2 weeks');
      expect(cushionLength(7), '1 week');
      expect(cushionLength(10), '10 days');
      expect(listText(['a', 'b', 'c']), 'a, b and c');
    });

    test('French', () {
      useStrings(stringsFromFiles('fr', fallback: stringsFromFiles('en')));
      expect(money(Money.parse('1234.5')), '1\u00a0235');
      expect(money(Money.parse('12.5')), '12,50');
      expect(percent(Fx.parse('0.125')), '12,5\u00a0%');
      expect(share(1, 4), '25\u00a0%');
      expect(shortDate(day), '5 mars');
      expect(longDate(day), 'jeu. 5 mars 2026');
      expect(monthName(day), 'Mars 2026');
      expect(monthName(day, capital: false), 'mars 2026');
      expect(termName(36), '3 ans');
      expect(termName(12), '1 an');
      expect(cushionLength(14), '2 semaines');
      expect(listText(['a', 'b', 'c']), 'a, b et c');
    });

    test('Spanish', () {
      useStrings(stringsFromFiles('es', fallback: stringsFromFiles('en')));
      expect(money(Money.parse('1234.5')), '1.235');
      expect(money(Money.parse('12.5')), '12,50');
      expect(percent(Fx.parse('0.125')), '12,5\u00a0%');
      expect(shortDate(day), '5 mar');
      expect(longDate(day), 'jue 5 mar 2026');
      expect(monthName(day), 'Marzo de 2026');
      expect(termName(36), '3 años');
      expect(listText(['a', 'b', 'c']), 'a, b y c');
    });
  });

  group('amounts typed', () {
    Money? cents(String text) => parseMoney(text);

    test('in English', () {
      expect(cents('12.5'), Money.parse('12.50'));
      expect(cents('12,5'), Money.parse('12.50'));
      expect(cents('1,234.50'), Money.parse('1234.50'));
      expect(cents('1,234'), Money.parse('1234'));
      expect(cents('1 234'), Money.parse('1234'));
      expect(cents('abc'), isNull);
    });

    test('in French', () {
      useStrings(stringsFromFiles('fr', fallback: stringsFromFiles('en')));
      expect(cents('12,5'), Money.parse('12.50'));
      expect(cents('12.5'), Money.parse('12.50'));
      expect(cents('1 234,50'), Money.parse('1234.50'));
      expect(cents('1\u00a0234,50'), Money.parse('1234.50'));
      expect(moneyInput(Money.parse('12.5')), '12,50');
      expect(cents(moneyInput(Money.parse('12.5'))), Money.parse('12.50'));
    });

    test('in Spanish', () {
      useStrings(stringsFromFiles('es', fallback: stringsFromFiles('en')));
      expect(cents('12,5'), Money.parse('12.50'));
      expect(cents('12.5'), Money.parse('12.50'));
      expect(cents('1.234'), Money.parse('1234'));
      expect(cents('1.234,50'), Money.parse('1234.50'));
      expect(cents('1.234.567'), Money.parse('1234567'));
      expect(cents(moneyInput(Money.parse('1234.5'))), Money.parse('1234.50'));
    });
  });

  group('refusals', () {
    test('word what the engine sends', () {
      final content = prototype;
      expect(
        refusalText(const Refusal('bankWantsGuarantee'), content),
        'the bank wants a personal guarantee',
      );
      expect(
        refusalText(
          Refusal('cannotPayWorks', amount: Money.parse('200')),
          content,
        ),
        'the company cannot pay the 200.00 of works',
      );
      expect(
        refusalText(
          Refusal(
            'formatDoesNotSell',
            format: format('grocery'),
            product: product('fastfood_budget'),
          ),
          content,
        ),
        'a convenience store does not sell Burger menu',
      );
      useStrings(stringsFromFiles('fr', fallback: stringsFromFiles('en')));
      expect(
        refusalText(
          Refusal('cannotPayWorks', amount: Money.parse('200')),
          content,
        ),
        'la société ne peut pas payer les 200,00 de travaux',
      );
      expect(
        refusalText(
          Refusal('siteTooSmall', format: format('supermarket')),
          content,
        ),
        "l’emplacement est trop petit pour un supermarché",
      );
    });
  });
}
