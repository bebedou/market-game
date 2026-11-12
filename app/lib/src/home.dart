import 'package:flutter/material.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';
import 'screens/dashboard.dart';
import 'screens/finance.dart';
import 'screens/guide.dart';
import 'screens/market.dart';
import 'screens/reports.dart';
import 'screens/store.dart';
import 'theme.dart';
import 'visuals.dart';
import 'widgets.dart';

/// The tabs, in order: the holding at a glance, the store picked, money
/// and deals, the world outside, and the books.
enum HomeTab { holding, shop, finance, world, books }

/// Switches to [tab], at [part] of the shop if given.
typedef OpenTab = void Function(HomeTab tab, {ShopPart? part});

/// The game: a tab per area, the clock at the bottom, and the changes
/// waiting for the next day above it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.notice});

  final SimulationController controller;

  /// Shown once on opening.
  final String? notice;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.holding;
  ShopPart _shopPart = ShopPart.shelves;

  /// The pages opened in each tab, the latest last.
  final _pages = {for (final tab in HomeTab.values) tab: <SubPage>[]};
  late final AppLifecycleListener _lifecycle;
  GameAlert? _latestAlert;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  SimulationController get _game => widget.controller;

  @override
  void initState() {
    super.initState();
    _latestAlert = _game.alerts.firstOrNull;
    _game.addListener(_onChange);
    // Leaving the app pauses the clock and saves.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _game.pause();
        _game.save();
      },
    );
    if (widget.notice case final notice?) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _messenger.currentState?.showSnackBar(
          SnackBar(content: Text(notice)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _game.removeListener(_onChange);
    super.dispose();
  }

  /// Shows the news that paused the clock, wherever the player is.
  void _onChange() {
    final alerts = _game.alerts;
    final latest = alerts.firstOrNull;
    if (identical(latest, _latestAlert)) return;
    final fresh = alerts.takeWhile((alert) => !identical(alert, _latestAlert));
    _latestAlert = latest;
    final pausing = fresh.where((alert) => _game.pauseOn.contains(alert.kind));
    if (pausing.isEmpty) return;
    final more = pausing.length - 1;
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            more > 0
                ? tr('home.andMore', {
                    'message': pausing.first.message,
                    'more': more,
                  })
                : pausing.first.message,
          ),
          action: SnackBarAction(
            label: tr('home.allNews'),
            onPressed: () => showAlerts(context, _game),
          ),
        ),
      );
  }

  void _open(HomeTab tab, {ShopPart? part}) => setState(() {
    _tab = tab;
    _pages[tab]!.clear();
    if (part != null) _shopPart = part;
  });

  /// From the tabs: the tab as it was left, or back to its start if it is
  /// the one shown.
  void _pick(HomeTab tab) => setState(() {
    if (tab == _tab) _pages[tab]!.clear();
    _tab = tab;
  });

  void _push(SubPage page) => setState(() => _pages[_tab]!.add(page));

  void _pop() => setState(() => _pages[_tab]!.removeLast());

  static String _tabName(HomeTab tab) => switch (tab) {
    HomeTab.holding => tr('home.tabs.holding'),
    HomeTab.shop => tr('home.tabs.shop'),
    HomeTab.finance => tr('home.tabs.finance'),
    HomeTab.world => tr('home.tabs.world'),
    HomeTab.books => tr('home.tabs.books'),
  };

  @override
  Widget build(BuildContext context) => GameScope(
    controller: _game,
    child: SubPages(
      open: _push,
      child: PopScope(
        // Back closes the page opened in the tab before leaving the game.
        canPop: _pages[_tab]!.isEmpty,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _pop();
        },
        child: ScaffoldMessenger(
          key: _messenger,
          child: Builder(
            builder: (context) {
              final game = context.game;
              final company = game.company;
              final store = game.store;
              final theme = Theme.of(context);
              final ledger = Ledger.of(context);
              // The holding and the world are the player's whole affairs; the
              // shop and the books are the store picked, which the title
              // switches.
              final picked = _tab == HomeTab.shop || _tab == HomeTab.books;
              final switchable = picked && game.myStores.length > 1;
              final small = theme.textTheme.bodySmall;
              final title = switch (_tab) {
                HomeTab.holding => tr('home.yourHolding'),
                HomeTab.finance => tr('home.tabs.finance'),
                HomeTab.world => tr('home.theWorld'),
                HomeTab.shop || HomeTab.books =>
                  store != null
                      ? game.storeName(store.id)
                      : company != null
                      ? game.companyName(company.id)
                      : tr('common.noCompany'),
              };
              return Scaffold(
                appBar: AppBar(
                  titleSpacing: 16,
                  title: InkWell(
                    onTap: switchable
                        ? () => showStorePicker(context, game)
                        : null,
                    child: Row(
                      children: [
                        if (picked && store != null) ...[
                          TradeMark(
                            ledger.trade(
                              game.content.formats[store.format.index],
                            ),
                            size: 12,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, overflow: TextOverflow.ellipsis),
                              if (!picked)
                                AnimatedMoney(
                                  game.netWorth,
                                  prefix: tr('home.netWorthPrefix'),
                                  style: small,
                                )
                              else if (company != null)
                                AnimatedMoney(
                                  company.cash,
                                  prefix: game.myStores.length > 1
                                      ? tr('home.companyCashPrefix', {
                                          'company': game.companyName(
                                            company.id,
                                          ),
                                        })
                                      : tr('home.cashPrefix'),
                                  style: small,
                                ),
                            ],
                          ),
                        ),
                        if (switchable) const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Badge(
                        isLabelVisible: game.alerts.isNotEmpty,
                        smallSize: 8,
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      tooltip: tr('common.news'),
                      onPressed: () => showAlerts(context, game),
                    ),
                    _Menu(game: game),
                  ],
                ),
                body: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.03, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey('${_tab.name} ${_pages[_tab]!.length}'),
                    child: switch (_pages[_tab]!) {
                      [] => switch (_tab) {
                        HomeTab.holding => DashboardScreen(onOpen: _open),
                        HomeTab.shop => StoreScreen(
                          part: _shopPart,
                          onPart: (part) => setState(() => _shopPart = part),
                        ),
                        HomeTab.finance => const FinanceScreen(),
                        HomeTab.world => const MarketScreen(),
                        HomeTab.books => const ReportsScreen(),
                      },
                      [..., final under, final page] => _PageFrame(
                        back: under.title,
                        page: page,
                        onBack: _pop,
                      ),
                      [final page] => _PageFrame(
                        back: _tabName(_tab),
                        page: page,
                        onBack: _pop,
                      ),
                    },
                  ),
                ),
                bottomNavigationBar: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: game.pending.isNotEmpty
                          ? const _PendingBar()
                          : const SizedBox(width: double.infinity),
                    ),
                    const _ClockBar(),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: ledger.ink, width: 2),
                        ),
                      ),
                      child: NavigationBar(
                        selectedIndex: _tab.index,
                        onDestinationSelected: (i) => _pick(HomeTab.values[i]),
                        destinations: [
                          NavigationDestination(
                            icon: Icon(Icons.account_balance_outlined),
                            label: tr('home.tabs.holding'),
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.storefront_outlined),
                            label: tr('home.tabs.shop'),
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.payments_outlined),
                            label: tr('home.tabs.finance'),
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.public_outlined),
                            label: tr('home.tabs.world'),
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.menu_book_outlined),
                            label: tr('home.tabs.books'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// A page opened within a tab: a way back, then its sections.
class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.back,
    required this.page,
    required this.onBack,
  });

  /// What going back returns to.
  final String back;
  final SubPage page;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, size: 18),
                const SizedBox(width: 6),
                Text(back, style: theme.textTheme.labelLarge),
              ],
            ),
          ),
        ),
        // Laid out whole rather than lazily: pages are short, and a lazy
        // list trips the framework's semantics when a dialog over it closes.
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey('page ${page.title}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: page.build(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// The date, the economy, and the clock's controls. While the clock runs, a
/// line fills as each day passes.
class _ClockBar extends StatelessWidget {
  const _ClockBar();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final regime = game
        .content
        .macro
        .regimes[game.view.economy(game.homeCountry).regime.index];
    final running = game.speed != Speed.paused;
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 3,
            child: running
                ? TweenAnimationBuilder<double>(
                    key: ValueKey(game.today),
                    tween: Tween(begin: 0, end: 1),
                    duration: game.speed.interval,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.4),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [?current],
                        ),
                        // Shrunk rather than wrapped, where the words are long.
                        child: FittedBox(
                          key: ValueKey(game.today),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            longDate(game.today),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          TradeMark(regimeColor(regime), size: 7),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              regime.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: running ? tr('home.pause') : tr('home.play'),
                  onPressed: () =>
                      game.setSpeed(running ? Speed.paused : Speed.normal),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      running ? Icons.pause : Icons.play_arrow,
                      key: ValueKey(running),
                    ),
                  ),
                ),
                PopupMenuButton<Speed>(
                  tooltip: tr('home.speed'),
                  initialValue: game.speed,
                  onSelected: game.setSpeed,
                  itemBuilder: (context) => [
                    for (final speed in Speed.values.skip(1))
                      PopupMenuItem(
                        value: speed,
                        child: Text(_speedName(speed)),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _speedBadge(game.speed),
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: const Icon(Icons.skip_next),
                  label: Text(tr('home.week')),
                  onPressed: game.advanceWeek,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _speedName(Speed speed) => switch (speed) {
    Speed.paused => tr('home.speeds.paused'),
    Speed.slow => tr('home.speeds.slow'),
    Speed.normal => tr('home.speeds.normal'),
    Speed.fast => tr('home.speeds.fast'),
  };

  static String _speedBadge(Speed speed) => switch (speed) {
    Speed.paused => '1×',
    Speed.slow => '½×',
    Speed.normal => '1×',
    Speed.fast => '4×',
  };
}

/// How many changes wait for tomorrow, and a way to review them.
class _PendingBar extends StatelessWidget {
  const _PendingBar();

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final count = game.pending.length;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      shape: Border(top: BorderSide(color: theme.colorScheme.onSurface)),
      child: InkWell(
        onTap: () => showPending(context, game),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('home.pending', {'count': count}))),
              Text(tr('home.review'), style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists the pending changes, each with a way to cancel it.
void showPending(BuildContext context, SimulationController game) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: game,
        builder: (context, _) => ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(tr('home.changesTomorrow'))),
            if (game.pending.isEmpty)
              ListTile(title: Text(tr('home.nothingWaiting'))),
            for (final command in game.pending)
              ListTile(
                title: Text(game.describe(command)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: tr('common.cancel'),
                  onPressed: () => game.cancel(command),
                ),
              ),
          ],
        ),
      ),
    );

/// Lists the news, newest first.
void showAlerts(BuildContext context, SimulationController game) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              tr('common.news'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            if (game.alerts.isEmpty) Hint(tr('home.nothingYet')),
            for (final alert in game.alerts) AlertTile(alert),
          ],
        ),
      ),
    );

/// One piece of news as a ledger entry: its date in the margin, trouble in
/// red ink.
class AlertTile extends StatelessWidget {
  const AlertTile(this.alert, {super.key});

  final GameAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trouble = switch (alert.kind) {
      AlertKind.refused ||
      AlertKind.overdue ||
      AlertKind.bankruptcy ||
      AlertKind.stockout ||
      AlertKind.deliveryRefused => true,
      _ => false,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              shortDate(alert.day),
              style: figures(theme.textTheme.bodySmall),
            ),
          ),
          Expanded(
            child: Text(
              alert.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: trouble ? Ledger.of(context).loss : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.game});

  final SimulationController game;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void Function()>(
    onSelected: (action) => action(),
    itemBuilder: (context) => [
      PopupMenuItem(
        value: () => _choosePauses(context),
        child: Text(tr('home.whenToPause')),
      ),
      PopupMenuItem(
        value: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()),
        ),
        child: Text(tr('common.howToPlay')),
      ),
      PopupMenuItem(
        value: () => Navigator.of(context).maybePop(),
        child: Text(tr('home.mainMenu')),
      ),
    ],
  );

  void _choosePauses(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(tr('home.pauseOn'))),
          for (final kind in AlertKind.values)
            SwitchListTile(
              title: Text(kind.label),
              value: game.pauseOn.contains(kind),
              onChanged: (on) => setState(
                () => on ? game.pauseOn.add(kind) : game.pauseOn.remove(kind),
              ),
            ),
        ],
      ),
    ),
  );
}
