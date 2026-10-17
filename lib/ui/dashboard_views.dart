import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/economy.dart';
import 'format.dart';
import 'revenue_chart.dart';

const _ink = Color(0xFF18352C);
const _muted = Color(0xFF66776D);
const _amber = Color(0xFF92630F);
const _red = Color(0xFFB33D32);
const _storeColors = [Color(0xFF226C52), Color(0xFF4D73B4), Color(0xFFAA7834)];

class OverviewView extends StatelessWidget {
  const OverviewView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final sim = game.simulation;
    final report = game.playerReport;
    final totalUnits = report?.unitsSold.values.fold<int>(0, (a, b) => a + b);
    return _Page(
      children: [
        const _Heading(
          'Your business, at a glance',
          'Performance from your latest trading day.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF173F32),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Color(0xFFBDE8D0),
                    size: 20,
                  ),
                  Text(
                    'AVAILABLE CASH',
                    style: TextStyle(
                      color: Color(0xFFCAE5D4),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(sim.ledger.balance(sim.player.id)),
                  key: const Key('cash-value'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                report == null
                    ? 'Opening capital · ready for your first day'
                    : '${money(report.cashChange, signed: true)} cash movement on day ${sim.day}',
                style: const TextStyle(color: Color(0xFFD2E7D9)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final width = stacked
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: _Metric(
                    'Daily profit',
                    report == null ? '—' : money(report.profit, signed: true),
                    report == null
                        ? 'After your first close'
                        : 'Revenue less costs & expenses',
                    icon: Icons.trending_up,
                    color: (report?.profit ?? 0) < 0 ? _red : _storeColors[0],
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _Metric(
                    'Daily revenue',
                    report == null ? '—' : money(report.revenue),
                    report == null
                        ? 'After your first close'
                        : '${count(totalUnits!)} units sold',
                    icon: Icons.receipt_long_outlined,
                    color: _storeColors[1],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(
                'Revenue history',
                game.reports.isEmpty
                    ? 'No completed days yet'
                    : 'Last ${game.reports.length} completed days',
                compact: true,
              ),
              RevenueChart(reports: game.reports, storeId: sim.player.id),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (report != null) ...[
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(
                  'Day ${sim.day} · the numbers',
                  'How sales become profit',
                  compact: true,
                ),
                _Detail('Revenue', money(report.revenue)),
                _Detail(
                  'Cost of goods sold',
                  '−${money(report.costOfGoodsSold)}',
                ),
                _Detail(
                  'Operating expenses',
                  '−${money(report.operatingExpenses)}',
                ),
                const Divider(height: 24),
                _Detail('Net profit', money(report.profit), strong: true),
                const SizedBox(height: 12),
                Text(
                  'Restocking: ${money(report.inventoryPurchases)} moved from cash into inventory. '
                  'It becomes a cost when those goods sell.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Heading(
                'Store essentials',
                'Your current position',
                compact: true,
              ),
              _Detail(
                'Inventory on hand',
                '${count(sim.player.inventory.values.fold<int>(0, (a, b) => a + b.quantity))} units',
              ),
              _Detail(
                'Inventory value',
                money(inventoryValue(sim.player.inventory)),
              ),
              _Detail('Daily operating cost', money(sim.player.operatingCost)),
              _Detail(
                'Status',
                sim.player.isOpen ? 'Open for business' : 'Store closed',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SessionNote(),
      ],
    );
  }
}

class StockView extends StatelessWidget {
  const StockView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final store = game.simulation.player;
    return _Page(
      children: [
        const _Heading(
          'Stockroom',
          'Current stock, prices, and supplier quotes.',
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                money(inventoryValue(store.inventory)),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Inventory value at purchase cost',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              Text(
                store.autoRestock
                    ? 'Automatic restocking · at the daily open'
                    : 'Automatic restocking is off',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Prices and restock targets are read-only in this preview.',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < products.length; i++) ...[
          _ProductCard(
            game: game,
            product: products[i],
            icon: _productIcons[i],
          ),
          const SizedBox(height: 12),
        ],
        const _SessionNote(),
      ],
    );
  }
}

const _productIcons = [
  Icons.water_drop_outlined,
  Icons.local_drink_outlined,
  Icons.bakery_dining_outlined,
  Icons.sports_bar_outlined,
  Icons.cookie_outlined,
  Icons.coffee_outlined,
  Icons.soap_outlined,
  Icons.eco_outlined,
];

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.game,
    required this.product,
    required this.icon,
  });
  final GameController game;
  final Product product;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final store = game.simulation.player;
    final stock = store.inventory[product.id]!;
    final coverage = game.stockCoverage(product.id);
    final warning = stock.quantity == 0 || (coverage != null && coverage < 2);
    final coverageText = stock.quantity == 0
        ? 'Out of stock'
        : coverage == null
        ? (game.reports.isEmpty
              ? 'Coverage: awaiting first close'
              : 'Coverage: no recent sales')
        : '${coverage.toStringAsFixed(1)} days of stock';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: _storeColors[0], size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                money(store.prices[product.id]!),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                '${count(stock.quantity)} on hand',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Target ${count(store.restockTargets[product.id]!)}',
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            coverageText,
            style: TextStyle(
              color: warning ? _amber : _muted,
              fontWeight: warning ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const Divider(height: 28),
          for (final supplier in game.simulation.suppliers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _Detail(
                supplier.name,
                money(supplier.prices[product.id]!),
              ),
            ),
        ],
      ),
    );
  }
}

class MarketView extends StatelessWidget {
  const MarketView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final sim = game.simulation;
    final shares = sim.lastReport?.marketShares;
    return _Page(
      children: [
        const _Heading(
          'The neighborhood',
          '1,000 households. Three stores. One shared market.',
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(
                'Market share',
                sim.day == 0
                    ? 'Available after the first trading day'
                    : 'Revenue share · day ${sim.day}',
                compact: true,
              ),
              for (var i = 0; i < sim.stores.length; i++) ...[
                _ShareRow(
                  store: sim.stores[i],
                  share: shares?[sim.stores[i].id],
                  color: _storeColors[i],
                ),
                if (i < sim.stores.length - 1) const SizedBox(height: 24),
              ],
              const SizedBox(height: 20),
              const Text(
                'Shares measure local retail revenue, not units sold. Some households choose not to buy.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(
                'Consumer segments',
                'Income sets a budget; price affects where it goes.',
                compact: true,
              ),
              for (final segment in consumerSegments) ...[
                _Detail(
                  '${segment.id[0].toUpperCase()}${segment.id.substring(1)}',
                  '${segment.households} households',
                  strong: true,
                ),
                Text(
                  '${money(segment.monthlyIncome)} / month per household',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(
                'Wholesale supply',
                'Quotes and stock refresh at the daily open.',
                compact: true,
              ),
              for (final supplier in sim.suppliers) ...[
                _Detail(
                  supplier.name,
                  '${count(supplier.inventory.values.fold<int>(0, (n, s) => n + s.quantity))} units',
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SessionNote(),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.store,
    required this.share,
    required this.color,
  });
  final Store store;
  final double? share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '${store.name}${store.playerControlled ? ' · You' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              share == null ? '—' : '${(share! * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: '${store.name} revenue share',
          value: share == null
              ? 'No sales yet'
              : '${(share! * 100).toStringAsFixed(1)} percent',
          child: ExcludeSemantics(
            child: LinearProgressIndicator(
              value: share ?? 0,
              minHeight: 7,
              color: color,
              backgroundColor: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${store.isOpen ? 'Open' : 'Closed'} · 8-item basket ${money(store.prices.values.fold<int>(0, (a, b) => a + b))}',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    );
  }
}

class ActivityView extends StatelessWidget {
  const ActivityView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) => _Page(
    children: [
      const _Heading(
        'Business activity',
        'Daily closes and the events worth your attention.',
      ),
      if (game.activity.isEmpty)
        const _Panel(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.notifications_none, size: 36, color: _muted),
                SizedBox(height: 16),
                Text(
                  'A fresh start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Complete your first day to see sales, profit, and business events here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      for (final event in game.activity) ...[
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    event.warning
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: event.warning ? _amber : _storeColors[0],
                    size: 20,
                  ),
                  Text(
                    'DAY ${event.day}',
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                event.message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (event.revenue != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Revenue ${money(event.revenue!)} · Profit ${money(event.profit!)}',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 16),
      const _SessionNote(),
    ],
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE3E9E1)),
    ),
    child: child,
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle, {this.compact = false});
  final String title;
  final String subtitle;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: compact ? 20 : 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 19 : 25,
            fontWeight: FontWeight.w700,
            color: _ink,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: _muted, height: 1.4)),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(
    this.label,
    this.value,
    this.detail, {
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: _muted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: LayoutBuilder(
      builder: (context, c) {
        final style = TextStyle(
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: _ink,
        );
        if (c.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: strong ? _ink : _muted,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 3),
              Text(value, style: style),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: strong ? _ink : _muted),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(value, style: style, textAlign: TextAlign.right),
            ),
          ],
        );
      },
    ),
  );
}

class _SessionNote extends StatelessWidget {
  const _SessionNote();
  @override
  Widget build(BuildContext context) => const Text(
    'Session only · Refreshing starts a new game.',
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
  );
}
