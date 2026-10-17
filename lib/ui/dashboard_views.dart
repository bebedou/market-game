import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/economy.dart';
import 'format.dart';
import 'competition_chart.dart';

const _ink = Color(0xFF18352C);
const _muted = Color(0xFF66776D);
const _amber = Color(0xFF92630F);

int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
String _margin(BusinessReport? report) => report == null || report.revenue == 0
    ? '—'
    : '${(100 * report.profit / report.revenue).toStringAsFixed(1)}%';
String _amount(int? value, {bool signed = false}) =>
    value == null ? '—' : money(value, signed: signed);

class OverviewView extends StatelessWidget {
  const OverviewView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final sim = game.simulation;
    final report = sim.lastReport;
    return _Page(
      children: [
        const _Heading(
          'Neighborhood overview',
          '1,000 households · 3 shops · 2 suppliers',
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
              const Text(
                'TOTAL RETAIL REVENUE',
                style: TextStyle(
                  color: Color(0xFFCAE5D4),
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _amount(report?.retailRevenue),
                  key: const Key('retail-revenue'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                report == null
                    ? 'Advance one day to collect results.'
                    : 'Latest completed day · Day ${report.day}',
                style: const TextStyle(color: Color(0xFFD2E7D9)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            children: [
              _Detail(
                'Combined daily profit',
                report == null ? '—' : money(game.retailProfit, signed: true),
                strong: true,
              ),
              _Detail('Retail cash', money(game.retailCash)),
              _Detail(
                'Units sold',
                report == null ? '—' : count(report.soldUnits),
              ),
              _Detail(
                'Open shops',
                '${sim.stores.where((s) => s.isOpen).length} / ${sim.stores.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _Heading(
          'Shop comparison',
          'Same day, same measures. Share is based on retail revenue.',
          compact: true,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < sim.stores.length; i++)
                  SizedBox(
                    width: width,
                    child: _StoreSummary(
                      game: game,
                      store: sim.stores[i],
                      index: i,
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
              const _Heading(
                'Competition over time',
                'Latest 30 completed days. Solid 1 · dashed 2 · dotted 3.',
                compact: true,
              ),
              CompetitionChart(reports: game.reports, stores: sim.stores),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(
                'Run assumptions',
                'A small economy for observing and tuning the engine.',
                compact: true,
              ),
              Text(
                sim.automateAllStores
                    ? 'All three shops use automatic pricing and restocking.'
                    : 'Mixed policy run: Corner & Co. prices are fixed; the other shops adapt.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Profits and demand are provisional. Unfilled intentions include outside purchases, price rejection, budget limits, and stock shortages.',
                style: TextStyle(color: _muted, height: 1.5),
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

class _StoreSummary extends StatelessWidget {
  const _StoreSummary({
    required this.game,
    required this.store,
    required this.index,
  });
  final GameController game;
  final Store store;
  final int index;

  @override
  Widget build(BuildContext context) {
    final report = game.reportFor(store.id);
    final share = game.simulation.lastReport?.marketShares[store.id];
    final empty = store.inventory.values.where((s) => s.quantity == 0).length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                '${index + 1}. ${store.name}',
                style: TextStyle(
                  color: storeColors[index],
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Text(
                store.isOpen ? 'Open' : 'Closed',
                style: TextStyle(color: store.isOpen ? _muted : _amber),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Detail(
            'Revenue share',
            share == null ? '—' : '${(share * 100).toStringAsFixed(1)}%',
            strong: true,
          ),
          Semantics(
            label: '${store.name} revenue share',
            value: share == null
                ? 'No completed days'
                : '${(share * 100).toStringAsFixed(1)} percent',
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: share ?? 0,
                color: storeColors[index],
                backgroundColor: storeColors[index].withValues(alpha: 0.1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Detail('Revenue', _amount(report?.revenue)),
          _Detail('Net profit', _amount(report?.profit, signed: true)),
          _Detail('Net margin', _margin(report)),
          _Detail('Cash', money(game.simulation.ledger.balance(store.id))),
          _Detail('Inventory value', money(inventoryValue(store.inventory))),
          _Detail('Empty product lines', '$empty / ${products.length}'),
        ],
      ),
    );
  }
}

class ShopsView extends StatefulWidget {
  const ShopsView({super.key, required this.game});
  final GameController game;

  @override
  State<ShopsView> createState() => _ShopsViewState();
}

class _ShopsViewState extends State<ShopsView> {
  String? _storeId;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final sim = game.simulation;
    final store = sim.stores.firstWhere(
      (s) => s.id == (_storeId ?? sim.stores.first.id),
    );
    final report = game.reportFor(store.id);
    return _Page(
      children: [
        const _Heading(
          'Shop inspector',
          'Inspect the same financial and inventory measures for every shop.',
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Shop', style: TextStyle(color: _muted)),
              DropdownButton<String>(
                key: const Key('shop-selector'),
                value: store.id,
                isExpanded: true,
                itemHeight: null,
                selectedItemBuilder: (context) => [
                  for (final s in sim.stores)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                items: [
                  for (final s in sim.stores)
                    DropdownMenuItem(
                      value: s.id,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(s.name),
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _storeId = id),
              ),
              const SizedBox(height: 8),
              Text(
                '${store.isOpen ? 'Open' : 'Closed'} · ${sim.automateAllStores || !store.playerControlled ? 'Adaptive pricing' : 'Fixed prices'} · ${store.autoRestock ? 'Auto restock' : 'Restocking off'}',
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(
                'Daily accounts',
                'Latest completed day · FIFO cost of goods',
                compact: true,
              ),
              _Detail('Cash', money(sim.ledger.balance(store.id))),
              _Detail('Revenue', _amount(report?.revenue)),
              _Detail('Cost of goods sold', _amount(report?.costOfGoodsSold)),
              _Detail('Operating expenses', _amount(report?.operatingExpenses)),
              _Detail(
                'Net profit',
                _amount(report?.profit, signed: true),
                strong: true,
              ),
              _Detail('Net margin', _margin(report)),
              const Divider(height: 24),
              _Detail(
                'Inventory purchases',
                _amount(report?.inventoryPurchases),
              ),
              _Detail(
                'Cash movement',
                _amount(report?.cashChange, signed: true),
              ),
              _Detail(
                'Inventory value',
                money(inventoryValue(store.inventory)),
              ),
              _Detail('Scheduled daily costs', money(store.operatingCost)),
              const SizedBox(height: 10),
              const Text(
                'Restocking moves cash into inventory. Profit deducts the cost of sold goods, not all purchases.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _Heading(
          'Products',
          'Read-only observations. Coverage uses up to seven days of actual sales.',
          compact: true,
        ),
        for (final p in products) ...[
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                _Detail('Retail price', money(store.prices[p.id]!)),
                _Detail(
                  'Units sold today',
                  report == null ? '—' : count(report.unitsSold[p.id]!),
                ),
                _Detail('On hand', count(store.inventory[p.id]!.quantity)),
                _Detail('Restock target', count(store.restockTargets[p.id]!)),
                _Detail(
                  'Stock coverage',
                  game.stockCoverage(p.id, storeId: store.id) == null
                      ? '— (no recent sales)'
                      : '${game.stockCoverage(p.id, storeId: store.id)!.toStringAsFixed(1)} days',
                ),
                const Divider(height: 24),
                for (final supplier in sim.suppliers)
                  _Detail(
                    supplier.name,
                    '${money(supplier.prices[p.id]!)} · ${count(supplier.inventory[p.id]!.quantity)} units',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const _SessionNote(),
      ],
    );
  }
}

class SupplyView extends StatelessWidget {
  const SupplyView({super.key, required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final sim = game.simulation;
    final report = sim.lastReport;
    final budget = _sum(consumerSegments.map((s) => s.dailyBudget));
    final spending = report == null ? null : _sum(report.spending.values);
    return _Page(
      children: [
        const _Heading(
          'Demand & supply',
          'Trace household spending and the two wholesalers behind the shops.',
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(
                'Consumer demand',
                'Latest completed day',
                compact: true,
              ),
              _Detail('Daily shopping budget', money(budget)),
              _Detail('Spent in local shops', _amount(spending)),
              _Detail(
                'Unspent budget',
                spending == null ? '—' : money(budget - spending),
              ),
              _Detail(
                'Purchase intentions',
                report == null ? '—' : count(report.requestedUnits),
              ),
              _Detail(
                'Units sold locally',
                report == null ? '—' : count(report.soldUnits),
              ),
              _Detail(
                'Unfilled intentions',
                report == null ? '—' : count(report.unfulfilledUnits),
              ),
              _Detail(
                'Local fulfillment',
                report == null || report.requestedUnits == 0
                    ? '—'
                    : '${(100 * report.soldUnits / report.requestedUnits).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 10),
              const Text(
                'Unfilled intentions are not a stockout measure. Households can reject prices, reach their budget, or choose the outside option. Unsold budgets are not spent automatically.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _Heading(
          'Households',
          'Income is monthly per household; budgets are daily segment totals.',
          compact: true,
        ),
        for (final segment in consumerSegments) ...[
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${segment.id[0].toUpperCase()}${segment.id.substring(1)} · ${count(segment.households)} households',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                _Detail(
                  'Monthly household income',
                  money(segment.monthlyIncome),
                ),
                _Detail('Daily shopping budget', money(segment.dailyBudget)),
                _Detail(
                  'Local spending today',
                  report == null ? '—' : money(report.spending[segment.id]!),
                ),
                _Detail('Price sensitivity', '${segment.priceSensitivity} / 5'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        const _Heading(
          'Wholesale suppliers',
          'Quotes and available units are the end-of-day position.',
          compact: true,
        ),
        for (final supplier in sim.suppliers) ...[
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  supplier.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                _Detail('Cash', money(sim.ledger.balance(supplier.id))),
                _Detail(
                  'Wholesale revenue',
                  _amount(game.reportFor(supplier.id)?.revenue),
                ),
                _Detail(
                  'Profit',
                  _amount(game.reportFor(supplier.id)?.profit, signed: true),
                ),
                _Detail(
                  'Procurement spending',
                  _amount(game.reportFor(supplier.id)?.inventoryPurchases),
                ),
                _Detail(
                  'Inventory value',
                  money(inventoryValue(supplier.inventory)),
                ),
                const Divider(height: 24),
                for (final p in products)
                  _Detail(
                    p.name,
                    '${money(supplier.prices[p.id]!)} · ${count(supplier.inventory[p.id]!.quantity)} units',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const _SessionNote(),
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
        'Economy activity',
        'Neighborhood daily totals and warnings from every shop.',
      ),
      if (game.activity.isEmpty)
        const _Panel(
          child: Text(
            'Complete one day to see neighborhood results and business events.',
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
                children: [
                  Icon(
                    event.warning
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: event.warning ? _amber : storeColors.first,
                    size: 20,
                  ),
                  Text(
                    'DAY ${event.day}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
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
                  'Total retail revenue ${money(event.revenue!)} · Profit ${money(event.profit!)}',
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
    'Session only · Refreshing starts a new observation run.',
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
  );
}
