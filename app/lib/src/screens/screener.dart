import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exchange.dart' show openStock, sectorName;

/// The figures a screen may limit, beside sectors and exchanges.
enum Criterion {
  pe,
  belowUsual,
  dividendYield,
  growth,
  debt,
  size,
  management,
  analysts,
  yearChange,
}

/// The limits each criterion offers, in its own units: a price to earnings
/// under; percent under its usual; percent of yield over; percent of sales
/// growth over (-1 for falling); years of profit of debt under (0 for
/// none); a size band; the least management grade; the least analysts'
/// rating (-1 for sell or worse); percent moved over a year, fallen (below
/// zero) or risen.
const criterionLimits = <Criterion, List<int>>{
  Criterion.pe: [8, 10, 12, 15, 20],
  Criterion.belowUsual: [10, 20, 30, 40],
  Criterion.dividendYield: [2, 3, 4, 5, 6],
  Criterion.growth: [-1, 0, 5, 10, 20],
  Criterion.debt: [0, 1, 2, 3, 4],
  Criterion.size: [0, 1, 2],
  Criterion.management: [2, 3, 4],
  Criterion.analysts: [3, 4, -1],
  Criterion.yearChange: [-30, -20, 20, 50],
};

/// What results are ordered by, each in its natural direction first.
enum ScreenSort {
  size,
  pe,
  belowUsual,
  dividendYield,
  growth,
  debt,
  yearChange,
  upside,
}

/// The three ways to see a screen, as the owner's three mockups had them.
enum ScreenerView { screens, criteria, table }

/// Ready-made screens: their limits and how they sort.
enum ReadyScreen {
  cheap({
    Criterion.pe: 20,
    Criterion.belowUsual: 20,
    Criterion.management: 2,
  }, ScreenSort.belowUsual),
  income({
    Criterion.dividendYield: 5,
    Criterion.debt: 3,
  }, ScreenSort.dividendYield),
  growing({Criterion.growth: 10}, ScreenSort.growth),
  fallen({
    Criterion.yearChange: -30,
    Criterion.management: 3,
  }, ScreenSort.yearChange),
  strongBuys({Criterion.analysts: 4}, ScreenSort.upside),
  smallDebtFree({Criterion.size: 0, Criterion.debt: 0}, ScreenSort.pe),
  everything({}, ScreenSort.size);

  const ReadyScreen(this.limits, this.sort);

  final Map<Criterion, int> limits;
  final ScreenSort sort;
}

/// What a screen asks: sectors and exchanges (any when empty) and a limit
/// per criterion.
typedef ScreenCriteria = ({
  Set<int> sectors,
  Set<CountryId> countries,
  Map<Criterion, int> limits,
});

/// The figures of one stock a screen reads, worked out once.
typedef StockFigures = ({
  StockView stock,

  /// Its price to earnings; null while it loses money.
  Fx? pe,

  /// How far its price to earnings stands from its usual: -0.2 a fifth
  /// under.
  Fx? againstUsual,
  Fx dividendYield,
  Fx? growth,

  /// Its debt in years of profit: zero without debt, null while it loses
  /// money.
  Fx? debt,

  /// How far its price moved over the last twelve months.
  Fx? yearChange,

  /// How far analysts' view of a share stands above its price.
  Fx? upside,
});

/// A billion, in the market's money.
const _billion = Money(100000000000);

/// [stock]'s figures, as a screen reads them.
StockFigures figuresOf(StockView stock) {
  Fx ratio(Money a, Money b) =>
      Fx.raw((a.cents - b.cents) * Fx.scale ~/ b.cents);
  final multiple = stock.multiple;
  final usual = stock.averageMultiple;
  final closes = stock.closes;
  final yearAgo = closes.length >= 13 ? closes[closes.length - 13] : null;
  return (
    stock: stock,
    pe: multiple,
    againstUsual: multiple != null && usual != null && usual > Fx.zero
        ? multiple.div(usual) - Fx.one
        : null,
    dividendYield: stock.cap <= Money.zero
        ? Fx.zero
        : Fx.raw(stock.yearDividends.cents * Fx.scale ~/ stock.cap.cents),
    growth: stock.salesGrowth,
    debt: stock.debtYears ?? (stock.yearProfit > Money.zero ? Fx.zero : null),
    yearChange: yearAgo != null && yearAgo > Money.zero
        ? ratio(stock.price, yearAgo)
        : null,
    upside: stock.price > Money.zero
        ? ratio(stock.analysts, stock.price)
        : null,
  );
}

/// Whether [f] meets every limit of [criteria].
bool meets(StockFigures f, ScreenCriteria criteria) {
  final stock = f.stock;
  if (criteria.sectors.isNotEmpty && !criteria.sectors.contains(stock.sector)) {
    return false;
  }
  if (criteria.countries.isNotEmpty &&
      !criteria.countries.contains(stock.country)) {
    return false;
  }
  Fx percents(int value) => Fx.raw(value * Fx.scale ~/ 100);
  for (final MapEntry(key: criterion, value: limit)
      in criteria.limits.entries) {
    final ok = switch (criterion) {
      Criterion.pe => f.pe != null && f.pe! < Fx.raw(limit * Fx.scale),
      Criterion.belowUsual =>
        f.againstUsual != null && f.againstUsual! <= -percents(limit),
      Criterion.dividendYield => f.dividendYield >= percents(limit),
      Criterion.growth => switch (f.growth) {
        null => false,
        final growth =>
          limit < 0 ? growth.isNegative : growth >= percents(limit),
      },
      Criterion.debt => switch (f.debt) {
        null => false,
        final debt =>
          limit == 0 ? debt == Fx.zero : debt < Fx.raw(limit * Fx.scale),
      },
      Criterion.size => switch (limit) {
        0 => stock.cap < _billion,
        1 => stock.cap >= _billion && stock.cap < _billion.timesInt(10),
        _ => stock.cap >= _billion.timesInt(10),
      },
      Criterion.management =>
        stock.management != null && stock.management! >= limit,
      Criterion.analysts =>
        limit < 0
            ? stock.rating.index <= AnalystRating.sell.index
            : stock.rating.index >= limit,
      Criterion.yearChange => switch (f.yearChange) {
        null => false,
        final moved =>
          limit < 0 ? moved <= percents(limit) : moved >= percents(limit),
      },
    };
    if (!ok) return false;
  }
  return true;
}

/// Whether [sort]'s natural order is biggest first.
bool biggestFirst(ScreenSort sort) => switch (sort) {
  ScreenSort.size ||
  ScreenSort.dividendYield ||
  ScreenSort.growth ||
  ScreenSort.upside => true,
  _ => false,
};

/// The figure [sort] orders by, null where [f] has none; and whether its
/// natural order is biggest first.
(Fx?, bool) sortFigure(StockFigures f, ScreenSort sort) =>
    (_sortValue(f, sort), biggestFirst(sort));

Fx? _sortValue(StockFigures f, ScreenSort sort) => switch (sort) {
  ScreenSort.size => Fx.raw(f.stock.cap.cents ~/ 100000),
  ScreenSort.pe => f.pe,
  ScreenSort.belowUsual => f.againstUsual,
  ScreenSort.dividendYield => f.dividendYield,
  ScreenSort.growth => f.growth,
  ScreenSort.debt => f.debt,
  ScreenSort.yearChange => f.yearChange,
  ScreenSort.upside => f.upside,
};

/// The listed companies of [stocks] that meet [criteria], ordered by [sort]
/// in its natural direction, or the other way if [reversed]; those without
/// the figure last, then by size.
List<StockFigures> screen(
  List<StockView> stocks,
  ScreenCriteria criteria,
  ScreenSort sort, {
  bool reversed = false,
}) {
  final found = [
    for (final stock in stocks)
      if (stock.listed)
        if (figuresOf(stock) case final f when meets(f, criteria)) f,
  ];
  found.sort((a, b) {
    final (x, down) = sortFigure(a, sort);
    final (y, _) = sortFigure(b, sort);
    if (x == null || y == null) {
      if (x != null) return -1;
      if (y != null) return 1;
      return b.stock.cap.cents.compareTo(a.stock.cap.cents);
    }
    final order = down != reversed
        ? y.raw.compareTo(x.raw)
        : x.raw.compareTo(y.raw);
    return order != 0 ? order : b.stock.cap.cents.compareTo(a.stock.cap.cents);
  });
  return found;
}

/// The screener on the Market tab, in the owner's three layouts as three
/// views of one screen: ready-made screens, the criteria and their results,
/// and a table sorted by column.
class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key});

  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage> {
  static const _page = 30;

  ScreenerView _view = ScreenerView.screens;
  ReadyScreen? _ready = ReadyScreen.cheap;
  ScreenCriteria _criteria = (
    sectors: const {},
    countries: const {},
    limits: ReadyScreen.cheap.limits,
  );
  ScreenSort _sort = ReadyScreen.cheap.sort;
  bool _reversed = false;
  int _shown = _page;

  void _pickScreen(ReadyScreen ready) => setState(() {
    _ready = ready;
    _criteria = (
      sectors: _criteria.sectors,
      countries: _criteria.countries,
      limits: ready.limits,
    );
    _sort = ready.sort;
    _reversed = false;
    _shown = _page;
  });

  void _change(ScreenCriteria criteria) => setState(() {
    _criteria = criteria;
    _ready = null;
    _shown = _page;
  });

  void _limit(Criterion criterion, int? limit) => _change((
    sectors: _criteria.sectors,
    countries: _criteria.countries,
    limits: {
      for (final entry in _criteria.limits.entries)
        if (entry.key != criterion) entry.key: entry.value,
      criterion: ?limit,
    },
  ));

  void _sortBy(ScreenSort sort) => setState(() {
    _reversed = _sort == sort && !_reversed;
    _sort = sort;
  });

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final stocks = game.view.stocks?.stocks ?? const <StockView>[];
    final results = screen(stocks, _criteria, _sort, reversed: _reversed);
    final listed = stocks.where((s) => s.listed).length;
    final views = Wrap(
      spacing: 6,
      children: [
        for (final view in ScreenerView.values)
          ChoiceChip(
            label: Text(tr('stocks.screener.views.${view.name}')),
            selected: _view == view,
            onSelected: (_) => setState(() => _view = view),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (_view) {
        ScreenerView.screens => [
          Section(
            title: tr('stocks.screener.title'),
            children: [
              views,
              for (final ready in ReadyScreen.values)
                IndexRow(
                  title: tr('stocks.screener.ready.${ready.name}.title'),
                  subtitle: _readyHint(ready),
                  value:
                      '${screen(stocks, (sectors: const {}, countries: const {}, limits: ready.limits), ready.sort).length}',
                  onTap: () => _pickScreen(ready),
                ),
              IndexRow(
                title: tr('stocks.screener.yourOwn'),
                subtitle: tr('stocks.screener.yourOwnHint'),
                onTap: () => setState(() => _view = ScreenerView.criteria),
              ),
            ],
          ),
          _Results(
            title: _ready == null
                ? tr('stocks.companies', {'count': results.length})
                : tr('stocks.screener.ready.${_ready!.name}.title'),
            subtitle: tr('stocks.screener.resultsLine', {
              'count': results.length,
              'sort': tr('stocks.screener.sorts.${_sort.name}'),
            }),
            results: results,
            sort: _sort,
            shown: _shown,
            more: () => setState(() => _shown += _page),
          ),
        ],
        ScreenerView.criteria => [
          Section(
            title: tr('stocks.screener.title'),
            children: [
              views,
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final ready in ReadyScreen.values)
                    ChoiceChip(
                      label: Text(
                        tr('stocks.screener.ready.${ready.name}.chip'),
                      ),
                      selected: _ready == ready,
                      onSelected: (_) => _pickScreen(ready),
                    ),
                ],
              ),
              _CriterionLine(
                label: tr('stocks.screener.criteria.sector'),
                value: _sectorsText(),
                onTap: () => _pickSectors(context),
              ),
              _CriterionLine(
                label: tr('stocks.screener.criteria.exchanges'),
                value: _countriesText(),
                onTap: () => _pickCountries(context),
              ),
              for (final criterion in Criterion.values)
                if (_criteria.limits[criterion] case final limit?)
                  _CriterionLine(
                    label: tr('stocks.screener.criteria.${criterion.name}'),
                    value: limitText(criterion, limit),
                    onTap: () => _pickLimit(context, criterion),
                  ),
              if (_criteria.limits.length < Criterion.values.length)
                IndexRow(
                  icon: Icons.add,
                  title: tr('stocks.screener.addCriterion'),
                  onTap: () => _addCriterion(context),
                ),
            ],
          ),
          _Results(
            title: tr('stocks.companies', {'count': results.length}),
            subtitle: tr('stocks.screener.byLine', {
              'sort': tr('stocks.screener.sorts.${_sort.name}'),
            }),
            onSubtitle: () => _pickSort(context),
            results: results,
            sort: _sort,
            shown: _shown,
            more: () => setState(() => _shown += _page),
          ),
        ],
        ScreenerView.table => [
          Section(
            title: tr('stocks.screener.title'),
            children: [
              views,
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  ActionChip(
                    label: Text(_sectorsText()),
                    onPressed: () => _pickSectors(context),
                  ),
                  ActionChip(
                    label: Text(_countriesText()),
                    onPressed: () => _pickCountries(context),
                  ),
                  for (final criterion in Criterion.values)
                    if (_criteria.limits[criterion] case final limit?)
                      InputChip(
                        label: Text(
                          tr('stocks.screener.chip', {
                            'criterion': tr(
                              'stocks.screener.short.${criterion.name}',
                            ),
                            'limit': limitText(criterion, limit),
                          }),
                        ),
                        onPressed: () => _pickLimit(context, criterion),
                        onDeleted: () => _limit(criterion, null),
                      ),
                  if (_criteria.limits.length < Criterion.values.length)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(tr('stocks.screener.filter')),
                      onPressed: () => _addCriterion(context),
                    ),
                ],
              ),
              _Table(
                results: results,
                total: listed,
                sort: _sort,
                reversed: _reversed,
                shown: _shown,
                onSort: _sortBy,
                more: () => setState(() => _shown += _page),
              ),
              Hint(tr('stocks.screener.tableHint')),
            ],
          ),
        ],
      },
    );
  }

  String _readyHint(ReadyScreen ready) => tr(
    'stocks.screener.ready.${ready.name}.hint',
    {'amount': compactMoney(_billion)},
  );

  String _sectorsText() {
    final content = context.game.content;
    final sectors = _criteria.sectors;
    if (sectors.isEmpty) return tr('stocks.screener.allSectors');
    if (sectors.length == 1) return sectorName(content, sectors.single);
    return tr('stocks.screener.someSectors', {'count': sectors.length});
  }

  String _countriesText() {
    final def = context.game.content.stocks!;
    final countries = _criteria.countries;
    if (countries.isEmpty) return tr('stocks.everywhere');
    return [
      for (final exchange in def.exchanges)
        if (countries.contains(exchange.country)) exchange.name,
    ].join(', ');
  }

  Future<void> _pickSectors(BuildContext context) async {
    final game = context.game;
    final content = game.content;
    final picked = await _pickMany<int>(
      context,
      tr('stocks.screener.criteria.sector'),
      [
        for (final (i, _) in content.stocks!.sectors.indexed)
          (i, sectorName(content, i)),
      ],
      _criteria.sectors,
    );
    if (picked == null) return;
    _change((
      sectors: picked,
      countries: _criteria.countries,
      limits: _criteria.limits,
    ));
  }

  Future<void> _pickCountries(BuildContext context) async {
    final def = context.game.content.stocks!;
    final picked = await _pickMany<CountryId>(
      context,
      tr('stocks.screener.criteria.exchanges'),
      [for (final exchange in def.exchanges) (exchange.country, exchange.name)],
      _criteria.countries,
    );
    if (picked == null) return;
    _change((
      sectors: _criteria.sectors,
      countries: picked,
      limits: _criteria.limits,
    ));
  }

  /// Asks which of [options] to keep, [now] ticked; null if dismissed.
  Future<Set<T>?> _pickMany<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
    Set<T> now,
  ) async {
    Set<T>? result;
    await showGameSheet(
      context,
      context.game,
      _ManySheet<T>(
        title: title,
        options: options,
        initial: now,
        onDone: (picked) => result = picked,
      ),
    );
    return result;
  }

  Future<void> _pickLimit(BuildContext context, Criterion criterion) async {
    final current = _criteria.limits[criterion];
    await showGameSheet(
      context,
      context.game,
      _OneSheet(
        title: tr('stocks.screener.criteria.${criterion.name}'),
        options: [
          (null, tr('stocks.screener.any')),
          for (final limit in criterionLimits[criterion]!)
            (limit, limitText(criterion, limit)),
        ],
        selected: current,
        onPick: (limit) => _limit(criterion, limit),
      ),
    );
  }

  Future<void> _addCriterion(BuildContext context) async {
    final game = context.game;
    Criterion? picked;
    await showGameSheet(
      context,
      game,
      _OneSheet<Criterion>(
        title: tr('stocks.screener.addCriterion'),
        options: [
          for (final criterion in Criterion.values)
            if (!_criteria.limits.containsKey(criterion))
              (criterion, tr('stocks.screener.criteria.${criterion.name}')),
        ],
        selected: null,
        onPick: (criterion) => picked = criterion,
      ),
    );
    if (picked case final criterion? when context.mounted) {
      await _pickLimit(context, criterion);
    }
  }

  Future<void> _pickSort(BuildContext context) => showGameSheet(
    context,
    context.game,
    _OneSheet<ScreenSort>(
      title: tr('stocks.screener.sortTitle'),
      options: [
        for (final sort in ScreenSort.values)
          (sort, tr('stocks.screener.sorts.${sort.name}')),
      ],
      selected: _sort,
      onPick: (sort) => setState(() {
        if (sort == null) return;
        _sort = sort;
        _reversed = false;
      }),
    ),
  );
}

/// [criterion]'s [limit] in words: "under 12", "20% under".
String limitText(Criterion criterion, int limit) => switch (criterion) {
  Criterion.pe => tr('stocks.screener.limits.under', {'value': limit}),
  Criterion.belowUsual => tr('stocks.screener.limits.percentUnder', {
    'value': percentOf(limit),
  }),
  Criterion.dividendYield => tr('stocks.screener.limits.over', {
    'value': percentOf(limit),
  }),
  Criterion.growth =>
    limit < 0
        ? tr('stocks.screener.limits.falling')
        : tr('stocks.screener.limits.over', {'value': percentOf(limit)}),
  Criterion.debt =>
    limit == 0
        ? tr('stocks.screener.limits.none')
        : tr('stocks.screener.limits.underYears', {'count': limit}),
  Criterion.size => tr(
    'stocks.screener.sizes.${['small', 'mid', 'large'][limit]}',
    {
      'amount': compactMoney(_billion),
      'more': compactMoney(_billion.timesInt(10)),
    },
  ),
  Criterion.management => tr(
    'stocks.screener.limits.management.${managementGrades[limit]}',
  ),
  Criterion.analysts => tr(
    'stocks.screener.limits.analysts.${switch (limit) {
      < 0 => 'sell',
      4 => 'strongBuy',
      _ => 'buy',
    }}',
  ),
  Criterion.yearChange =>
    limit < 0
        ? tr('stocks.screener.limits.fallen', {'value': percentOf(-limit)})
        : tr('stocks.screener.limits.risen', {'value': percentOf(limit)}),
};

/// [multiple] as a price-to-earnings figure, or a dash.
String _multiple(Fx? multiple) => multiple == null
    ? '—'
    : decimalText((multiple.raw ~/ 1000 / 10).toString());

/// [rate] signed, as a percentage: "+12%", "−3%"; unsigned when it rounds
/// to nothing.
String _signed(Fx rate, [int decimals = 0]) {
  final text = percent(rate, decimals: decimals);
  if (_roundsToNothing(rate, decimals)) return text.replaceFirst('-', '');
  return rate > Fx.zero ? '+$text' : text.replaceFirst('-', '−');
}

/// Whether [rate], as a percentage of [decimals], shows as zero.
bool _roundsToNothing(Fx rate, int decimals) {
  var half = Fx.scale ~/ 200;
  for (var i = 0; i < decimals; i++) {
    half ~/= 10;
  }
  return rate.raw.abs() < half;
}

/// The figure a result shows for [sort], with a word on it where one helps.
(String, String?) _shownFigure(StockFigures f, ScreenSort sort) =>
    switch (sort) {
      ScreenSort.size => (compactMoney(f.stock.cap), null),
      ScreenSort.pe => (_multiple(f.pe), null),
      ScreenSort.belowUsual => (
        _multiple(f.pe),
        f.stock.averageMultiple == null
            ? null
            : tr('stocks.usually', {
                'value': _multiple(f.stock.averageMultiple),
              }),
      ),
      ScreenSort.dividendYield => (percent(f.dividendYield), null),
      ScreenSort.growth => (
        f.growth == null ? '—' : _signed(f.growth!),
        tr('stocks.screener.sales'),
      ),
      ScreenSort.debt => (_debt(f.debt), null),
      ScreenSort.yearChange => (
        f.yearChange == null ? '—' : _signed(f.yearChange!),
        tr('stocks.screener.overYear'),
      ),
      ScreenSort.upside => (
        tr('stocks.ratings.${f.stock.rating.name}'),
        f.upside == null
            ? null
            : tr('stocks.screener.upside', {'change': _signed(f.upside!)}),
      ),
    };

String _debt(Fx? years) => switch (years) {
  null => '—',
  final years when years == Fx.zero => tr('stocks.noDebt'),
  final years => decimalText((years.raw ~/ 1000 / 10).toString()),
};

/// A screen's results as index lines, a page at a time.
class _Results extends StatelessWidget {
  const _Results({
    required this.title,
    required this.subtitle,
    required this.results,
    required this.sort,
    required this.shown,
    required this.more,
    this.onSubtitle,
  });

  final String title;
  final String subtitle;
  final List<StockFigures> results;
  final ScreenSort sort;
  final int shown;
  final VoidCallback more;
  final VoidCallback? onSubtitle;

  @override
  Widget build(BuildContext context) {
    final content = context.game.content;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final def = content.stocks!;
    return Section(
      title: title,
      children: [
        InkWell(
          onTap: onSubtitle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ledger.muted,
                    ),
                  ),
                ),
                if (onSubtitle != null)
                  Icon(Icons.arrow_drop_down, size: 18, color: ledger.muted),
              ],
            ),
          ),
        ),
        if (results.isEmpty) Hint(tr('stocks.screener.none')),
        for (final f in results.take(shown))
          Builder(
            builder: (context) {
              final (value, word) = _shownFigure(f, sort);
              final stock = f.stock;
              return IndexRow(
                title: stock.name,
                subtitle: [
                  stock.ticker,
                  def.exchanges[def.exchangeOf(stock.country)!].name,
                  sectorName(content, stock.sector),
                  ?word,
                ].join(' · '),
                value: value,
                stamp:
                    sort == ScreenSort.belowUsual &&
                        f.againstUsual != null &&
                        f.againstUsual! <= const Fx.raw(-2000)
                    ? tr('stocks.cheap')
                    : null,
                onTap: () => openStock(context, stock),
              );
            },
          ),
        if (results.length > shown)
          TextButton(
            onPressed: more,
            child: Text(
              tr('stocks.screener.more', {
                'count': results.length - shown < 30
                    ? results.length - shown
                    : 30,
              }),
            ),
          ),
      ],
    );
  }
}

/// The results as a ruled table: price to earnings, yield, sales growth and
/// debt in columns, sorted by the one tapped.
class _Table extends StatelessWidget {
  const _Table({
    required this.results,
    required this.total,
    required this.sort,
    required this.reversed,
    required this.shown,
    required this.onSort,
    required this.more,
  });

  final List<StockFigures> results;
  final int total;
  final ScreenSort sort;
  final bool reversed;
  final int shown;
  final ValueChanged<ScreenSort> onSort;
  final VoidCallback more;

  static const _columns = [
    ScreenSort.pe,
    ScreenSort.dividendYield,
    ScreenSort.growth,
    ScreenSort.debt,
  ];
  static const _width = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final small = theme.textTheme.bodySmall;
    final numbers = figures(small);
    Widget header(ScreenSort column) {
      final on = column == sort;
      final down = biggestFirst(column) != reversed;
      return InkWell(
        onTap: () => onSort(column),
        child: SizedBox(
          width: _width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    tr('stocks.screener.columns.${column.name}'),
                    textAlign: TextAlign.end,
                    style: small?.copyWith(
                      color: on ? ledger.ink : ledger.muted,
                      decoration: on ? TextDecoration.underline : null,
                    ),
                  ),
                ),
                if (on)
                  Icon(
                    down ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 12,
                    color: ledger.ink,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    String cell(StockFigures f, ScreenSort column) => switch (column) {
      ScreenSort.pe => _multiple(f.pe),
      ScreenSort.dividendYield => percent(f.dividendYield),
      ScreenSort.growth => f.growth == null ? '—' : _signed(f.growth!, 1),
      _ => _debt(f.debt),
    };
    Color? tint(StockFigures f, ScreenSort column) => switch (column) {
      ScreenSort.growth
          when f.growth != null && !_roundsToNothing(f.growth!, 1) =>
        f.growth!.isNegative ? ledger.loss : ledger.gain,
      ScreenSort.debt when f.debt != null && f.debt! >= Fx.raw(3 * Fx.scale) =>
        ledger.loss,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ledger.ink, width: 0.8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onSort(ScreenSort.size),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      tr('stocks.screener.of', {
                        'count': results.length,
                        'total': total,
                      }),
                      style: small?.copyWith(color: ledger.muted),
                    ),
                  ),
                ),
              ),
              for (final column in _columns) header(column),
            ],
          ),
        ),
        if (results.isEmpty) Hint(tr('stocks.screener.none')),
        for (final f in results.take(shown))
          InkWell(
            onTap: () => openStock(context, f.stock),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ledger.rule, width: 0.6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.stock.name, style: theme.textTheme.bodyMedium),
                        Text(
                          '${f.stock.ticker} · ${sectorName(context.game.content, f.stock.sector)}',
                          style: small?.copyWith(color: ledger.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  for (final column in _columns)
                    SizedBox(
                      width: _width,
                      child: Text(
                        cell(f, column),
                        textAlign: TextAlign.end,
                        style: numbers.copyWith(color: tint(f, column)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (results.length > shown)
          TextButton(
            onPressed: more,
            child: Text(
              tr('stocks.screener.more', {
                'count': results.length - shown < 30
                    ? results.length - shown
                    : 30,
              }),
            ),
          ),
      ],
    );
  }
}

/// A criterion and its limit, in words: tapped to change it.
class _CriterionLine extends StatelessWidget {
  const _CriterionLine({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ledger.rule, width: 0.6)),
        ),
        child: Row(
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ledger.muted,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: ledger.muted),
          ],
        ),
      ),
    );
  }
}

/// A sheet that picks one of [options], or none.
class _OneSheet<T> extends StatelessWidget {
  const _OneSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final String title;
  final List<(T?, String)> options;
  final T? selected;
  final ValueChanged<T?> onPick;

  @override
  Widget build(BuildContext context) => SheetFrame(
    footer: TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(tr('common.cancel')),
    ),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      for (final (value, label) in options)
        ChoiceTile(
          selected: value == selected,
          title: label,
          onTap: () {
            onPick(value);
            Navigator.pop(context);
          },
        ),
    ],
  );
}

/// A sheet that ticks any of [options]; none ticked means any.
class _ManySheet<T> extends StatefulWidget {
  const _ManySheet({
    super.key,
    required this.title,
    required this.options,
    required this.initial,
    required this.onDone,
  });

  final String title;
  final List<(T, String)> options;
  final Set<T> initial;
  final ValueChanged<Set<T>> onDone;

  @override
  State<_ManySheet<T>> createState() => _ManySheetState<T>();
}

class _ManySheetState<T> extends State<_ManySheet<T>> {
  late final Set<T> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) => SheetFrame(
    footer: FilledButton(
      onPressed: () {
        widget.onDone(Set.unmodifiable(_picked));
        Navigator.pop(context);
      },
      child: Text(tr('stocks.screener.done')),
    ),
    children: [
      Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
      Hint(tr('stocks.screener.anyHint')),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final (value, label) in widget.options)
            FilterChip(
              label: Text(label),
              selected: _picked.contains(value),
              onSelected: (on) => setState(
                () => on ? _picked.add(value) : _picked.remove(value),
              ),
            ),
        ],
      ),
    ],
  );
}
