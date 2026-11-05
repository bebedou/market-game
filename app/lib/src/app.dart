import 'dart:async';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'l10n.dart';
import 'saves.dart';
import 'screens/menu.dart';
import 'theme.dart';

const scenarioAsset = 'packages/market_content/scenarios/prototype.json';

/// A seed for a new world.
int newSeed() => DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

/// The bundled scenario, in the words of the language in use.
Future<ContentDb> loadContent() async => loadScenario(
  localizedScenario(
    await rootBundle.loadString(scenarioAsset),
    currentStrings?.scenario ?? const {},
  ),
);

/// The game saved in [store], or null if there is none. A save that can't
/// be loaded is set aside, emptying the slot, and the notice says why.
Future<(SimulationController?, String?)> openGame(
  ContentDb content,
  SaveStore store,
) async {
  final file = await store.read();
  if (file == null) return (null, null);
  try {
    return (
      SimulationController(
        content,
        Simulation.load(content, file),
        saves: store,
      ),
      null,
    );
  } on FormatException catch (error) {
    await store.setAside(file);
    return (null, tr('app.loadFailed', {'error': error.message}));
  }
}

class MarketGameApp extends StatefulWidget {
  const MarketGameApp({super.key, this.saves, this.language});

  /// Where to keep the games; the platform's default if null.
  final SaveSlots? saves;

  /// The language to play in, whatever the player last chose or the phone's
  /// setting; for tests.
  final String? language;

  @override
  State<MarketGameApp> createState() => _MarketGameAppState();
}

class _MarketGameAppState extends State<MarketGameApp> {
  late final SaveSlots _saves = widget.saves ?? defaultSaveSlots();
  late Future<ContentDb> _content = _load();
  List<Language> _languages = const [];
  String? _language;

  /// Loads [choice], or the language last chosen, or the phone's if the game
  /// speaks it, or English; then the scenario in its words.
  Future<ContentDb> _load([String? choice]) async {
    _languages = await loadLanguages();
    final phone =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final code =
        choice ??
        widget.language ??
        await _saves.language() ??
        (_languages.any((language) => language.code == phone) ? phone : 'en');
    await useLanguage(code);
    final content = await loadContent();
    if (mounted) setState(() => _language = code);
    return content;
  }

  void _pickLanguage(String code) {
    if (code == _language) return;
    unawaited(_saves.setLanguage(code));
    setState(() {
      _content = _load(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_) => currentStrings == null ? '' : tr('app.title'),
      debugShowCheckedModeBanner: false,
      theme: gameTheme(Brightness.light),
      darkTheme: gameTheme(Brightness.dark),
      locale: _language == null ? null : Locale(_language!),
      supportedLocales: [
        for (final language in _languages) Locale(language.code),
        if (_languages.isEmpty) const Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => ScreenMargins(child: child!),
      home: FutureBuilder(
        future: _content,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(data: final content?) => MainMenu(
            key: ValueKey(_language),
            content: content,
            saves: _saves,
            languages: _languages,
            language: _language,
            onLanguage: _pickLanguage,
          ),
          AsyncSnapshot(:final error?) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                // Without a language there are no words to say it in.
                child: Text(
                  currentStrings == null
                      ? '$error'
                      : tr('app.startFailed', {'error': error}),
                ),
              ),
            ),
          ),
          _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}

/// Keeps the game [margin] of the screen's height clear of its top and bottom
/// edges, beyond the system bars, for easier reading.
class ScreenMargins extends StatelessWidget {
  const ScreenMargins({super.key, required this.child});

  static const margin = 0.05;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final gap = media.size.height * margin;
    final top = media.padding.top + gap;
    final bottom = media.padding.bottom + gap;
    final keyboard = media.viewInsets.bottom - bottom;
    final theme = Theme.of(context);
    final icons = theme.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The phone's own bars on the same paper as the game.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: theme.brightness,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarDividerColor: theme.scaffoldBackgroundColor,
      ),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          // The system bars are outside the game now, and the keyboard covers
          // less of it.
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(top: 0, bottom: 0),
              viewPadding: media.viewPadding.copyWith(top: 0, bottom: 0),
              viewInsets: media.viewInsets.copyWith(
                bottom: keyboard > 0 ? keyboard : 0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
