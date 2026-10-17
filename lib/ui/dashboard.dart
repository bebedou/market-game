import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import 'dashboard_views.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.controller});
  final GameController? controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late GameController _game;
  late bool _ownsController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _attach();
    WidgetsBinding.instance.addObserver(this);
  }

  void _attach() {
    _ownsController = widget.controller == null;
    _game = widget.controller ?? GameController();
    final state = WidgetsBinding.instance.lifecycleState;
    _game.setForeground(state == null || state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _game.pause();
      if (_ownsController) {
        _game.dispose();
      }
      _attach();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _game.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.pause();
    if (_ownsController) {
      _game.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _game,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DashboardHeader(game: _game),
            if (_game.error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFBE9E6),
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${_game.error} Refresh to start a new session.',
                  style: const TextStyle(color: Color(0xFF92372D)),
                ),
              ),
            Expanded(
              child: switch (_page) {
                0 => OverviewView(game: _game),
                1 => StockView(game: _game),
                2 => MarketView(game: _game),
                _ => ActivityView(game: _game),
              },
            ),
            _PlaybackControls(game: _game),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE0EBDF),
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Market',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Activity',
          ),
        ],
      ),
    ),
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFE0EBDF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.storefront_outlined, color: Color(0xFF226C52)),
    );
    const title = Text(
      'Corner & Co.',
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: Color(0xFF18352C),
        letterSpacing: -0.5,
      ),
    );
    final status = Text(
      game.isPlaying ? 'Trading · not saved' : 'Paused · not saved',
      style: const TextStyle(fontSize: 12, color: Color(0xFF66776D)),
    );
    final day = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E9E1)),
      ),
      child: Text(
        'Day ${game.simulation.day}',
        key: const Key('trading-day'),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF18352C),
        ),
      ),
    );
    return Padding(
      key: const Key('dashboard-header'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 350 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        const Expanded(child: title),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [status, day],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, status],
                    ),
                  ),
                  const SizedBox(width: 12),
                  day,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final enabled = game.isForeground && game.error == null;
    final seconds = 15 / game.speed;
    final speed = Tooltip(
      message:
          'One game day takes ${seconds % 1 == 0 ? seconds.toInt() : seconds} seconds',
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(48, 48),
        ),
        segments: const [
          ButtonSegment(
            value: 1,
            label: Text('1×'),
            tooltip: '15 seconds per day',
          ),
          ButtonSegment(
            value: 3,
            label: Text('3×'),
            tooltip: '5 seconds per day',
          ),
          ButtonSegment(
            value: 10,
            label: Text('10×'),
            tooltip: '1.5 seconds per day',
          ),
        ],
        selected: {game.speed},
        onSelectionChanged: enabled
            ? (value) => game.setSpeed(value.single)
            : null,
      ),
    );
    final play = FilledButton.icon(
      key: const Key('play-pause'),
      onPressed: enabled ? (game.isPlaying ? game.pause : game.play) : null,
      icon: Icon(
        game.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      ),
      label: Text(game.isPlaying ? 'Pause' : 'Play'),
      style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
    );
    final next = Tooltip(
      message: game.isPlaying
          ? 'Pause before advancing a day'
          : 'Advance one complete day',
      child: IconButton.filledTonal(
        key: const Key('next-day'),
        onPressed: enabled && !game.isPlaying ? game.nextDay : null,
        icon: const Icon(Icons.skip_next_rounded),
        tooltip: 'Next day',
      ),
    );
    return Container(
      key: const Key('playback-bar'),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3E9E1))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 335 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: play),
                        const SizedBox(width: 12),
                        next,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Speed',
                          style: TextStyle(color: Color(0xFF66776D)),
                        ),
                        speed,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: play),
                  const SizedBox(width: 8),
                  next,
                  const SizedBox(width: 8),
                  speed,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
