import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../loans.dart';
import '../theme.dart';
import '../widgets.dart';

/// The discounts a factory may offer rivals, as choices.
final _discounts = [
  for (final rate in ['0', '0.05', '0.10', '0.15', '0.20']) Fx.parse(rate),
];

/// The player's factories on the holding, each on a line, and the way to
/// build one. Nothing if the scenario has none.
class FactoriesSection extends StatelessWidget {
  const FactoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    if (game.content.factories == null) return const SizedBox.shrink();
    final mine = game.myFactories;
    return Section(
      title: mine.length == 1
          ? tr('factory.yourFactory')
          : mine.isEmpty
          ? tr('factory.factories')
          : tr('factory.yourFactories'),
      children: [
        for (final (company, factory) in mine)
          _FactoryEntry(company: company, factory: factory),
        IndexRow(
          icon: Icons.factory_outlined,
          title: tr('factory.build'),
          subtitle: tr('factory.buildPitch'),
          onTap: () => context.openPage(
            tr('factory.build'),
            (_) => [const BuildFactoryPage()],
          ),
        ),
      ],
    );
  }
}

/// Opens [factory]'s page within the current tab.
void openFactoryPage(BuildContext context, FactoryView factory) =>
    context.openPage(factory.name, (_) => [FactoryPage(id: factory.id)]);

/// [factory]'s part of its company's latest month report, and the month.
(PeriodReport, FactoryReport)? _thisMonth(
  SimulationController game,
  FactoryView factory,
) {
  final month = game
      .reports(ReportPeriod.month, company: factory.company)
      .lastOrNull;
  final part = month?.factory(factory.id);
  return month == null || part == null ? null : (month, part);
}

/// The month the page reads: this month once a week of it is recorded,
/// else the month before, else this one so far.
(PeriodReport, FactoryReport)? _shownMonth(
  SimulationController game,
  FactoryView factory,
) {
  final months = game.reports(ReportPeriod.month, company: factory.company);
  (PeriodReport, FactoryReport)? of(PeriodReport report) =>
      switch (report.factory(factory.id)) {
        final part? => (report, part),
        null => null,
      };
  final latest = months.lastOrNull;
  if (latest == null) return null;
  if (latest.days >= 7 || months.length < 2) return of(latest);
  return of(months[months.length - 2]) ?? of(latest);
}

/// The share of what [factory] could have made over [report]'s days that it
/// made.
Fx _use(ContentDb content, FactoryView factory, PeriodReport report, int made) {
  final kind = content.factories!.kinds[factory.kind.index];
  final capacity = kind.shiftUnits * factory.shifts * report.days;
  return capacity == 0 ? Fx.zero : Fx.raw(made * Fx.scale ~/ capacity);
}

/// [units] with the language's thousands separators.
String _count(int units) => money(Money(units * 100), cents: false);

/// What one shift of [kind] costs a day in [country], at today's wages.
Money _shiftCost(SimulationController game, FactoryKindDef kind, CountryId c) =>
    kind.shiftWage
        .times(game.view.economy(c).wageIndex)
        .times(game.content.countries[c.index].service);

class _FactoryEntry extends StatelessWidget {
  const _FactoryEntry({required this.company, required this.factory});

  final CompanyView company;
  final FactoryView factory;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final kind = content.factories!.kinds[factory.kind.index];
    final month = _thisMonth(game, factory);
    final shifts = game.shiftsOf(factory);
    return IndexRow(
      mark: Ledger.of(context).works,
      title: factory.name,
      subtitle: [
        kind.name,
        if (content.countries.length > 1)
          content.countries[factory.country.index].name,
        if (factory.status == FactoryStatus.closed)
          tr('common.closedLower')
        else if (factory.building)
          tr('common.opensOn', {'date': shortDate(factory.opensOn)})
        else ...[
          shifts == 0
              ? tr('factory.stopped')
              : tr('factory.shifts', {'count': shifts}),
          if (month case (final report, final part))
            tr('factory.usedLine', {
              'use': percent(
                _use(content, factory, report, part.made),
                decimals: 0,
              ),
            }),
        ],
      ].join(' · '),
      value: month == null ? null : money(month.$2.profit, cents: false),
      valueColor: month == null
          ? null
          : gainColor(context, month.$2.profit.cents.sign),
      onTap: () => openFactoryPage(context, factory),
    );
  }
}

/// A factory's page, statement first: the month against buying, its
/// capacity and shifts, its lines, and whom it sells to.
class FactoryPage extends StatelessWidget {
  const FactoryPage({super.key, required this.id});

  final FactoryId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final factory = game.factory(id);
    if (factory == null) return Hint(tr('factory.gone'));
    final content = game.content;
    final kind = content.factories!.kinds[factory.kind.index];
    final ledger = Ledger.of(context);
    final shown = _shownMonth(game, factory);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: factory.name,
          mark: ledger.works,
          children: [
            Hint(
              [
                kind.name,
                if (content.countries.length > 1)
                  content.countries[factory.country.index].name,
                if (factory.status == FactoryStatus.closed)
                  tr('common.closedLower')
                else if (factory.building)
                  tr('common.opensOn', {'date': shortDate(factory.opensOn)})
                else
                  tr('factory.since', {'date': shortDate(factory.opensOn)}),
                game.companyName(factory.company),
              ].join(' · '),
            ),
            Line(tr('factory.builtFor'), money(factory.builtFor, cents: false)),
            if (factory.earnings case final earnings?)
              Line(
                tr('factory.earnsYear'),
                money(earnings, cents: false),
                color: gainColor(context, earnings.cents.sign),
                hint: tr('factory.earnsHint'),
              ),
          ],
        ),
        _Statement(factory: factory, shown: shown),
        if (factory.status != FactoryStatus.closed) ...[
          _Capacity(factory: factory, kind: kind),
          _Lines(factory: factory, kind: kind, shown: shown),
          _SellsTo(factory: factory, kind: kind, shown: shown),
        ],
      ],
    );
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.factory, required this.shown});

  final FactoryView factory;
  final (PeriodReport, FactoryReport)? shown;

  @override
  Widget build(BuildContext context) {
    final shown = this.shown;
    if (shown == null) {
      return Section(
        title: tr('factory.againstBuying'),
        children: [
          Hint(
            factory.building
                ? tr('factory.notYet', {'date': shortDate(factory.opensOn)})
                : tr('factory.nothingYet'),
          ),
        ],
      );
    }
    final (report, part) = shown;
    final theme = Theme.of(context);
    Widget cost(String label, Money amount) =>
        Line(label, money(-amount, cents: false));
    return Section(
      title: report.complete
          ? tr('factory.monthAgainst', {'month': monthName(report.start)})
          : tr('factory.monthSoFar', {'month': monthName(report.start)}),
      children: [
        Line(
          tr('factory.wouldHavePaid'),
          money(part.totalOwnGoods, cents: false),
        ),
        if (part.totalRivalSales > Money.zero)
          Line(
            tr('factory.rivalsPaid'),
            money(part.totalRivalSales, cents: false),
          ),
        cost(tr('factory.materials'), part.totalMaterials),
        cost(tr('factory.staff'), part.wages),
        cost(tr('factory.site'), part.occupancy),
        if (part.freight > Money.zero)
          cost(tr('factory.freight'), part.freight),
        Container(height: 1, color: theme.colorScheme.onSurface),
        Line(
          tr('factory.earned'),
          money(part.profit, cents: false),
          strong: true,
          color: gainColor(context, part.profit.cents.sign),
        ),
        Hint(tr('factory.atMarket')),
        if (part.totalBoughtIn > 0)
          Hint(tr('factory.boughtIn', {'units': _count(part.totalBoughtIn)})),
      ],
    );
  }
}

class _Capacity extends StatelessWidget {
  const _Capacity({required this.factory, required this.kind});

  final FactoryView factory;
  final FactoryKindDef kind;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final most = content.factories!.maxShifts;
    final shifts = game.shiftsOf(factory);
    final outlook = factoryOutlook(
      game.view,
      content,
      factory.kind,
      factory.country,
      serves: factory.serves,
    );
    final plan = shifts == 0 ? null : outlook.plans[shifts - 1];
    final capacity = factory.monthCapacity;
    final use = capacity == 0
        ? 0.0
        : (factory.madeThisMonth / capacity).clamp(0.0, 1.0);
    return Section(
      title: tr('factory.capacity'),
      children: [
        if (factory.making)
          _CapacityBar(
            use: use,
            breakEven: plan == null ? null : plan.breakEven.raw / Fx.scale,
          ),
        if (factory.making)
          Line(
            tr('factory.madeOf', {
              'made': _count(factory.madeThisMonth),
              'capacity': _count(capacity),
            }),
            percentOf((use * 100).round()),
          ),
        if (plan != null)
          Hint(
            tr('factory.paysFrom', {
              'use': percent(plan.breakEven, decimals: 0),
            }),
          ),
        const SizedBox(height: 6),
        Text(
          tr('factory.shiftsLabel'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var count = 0; count <= most; count++)
              ButtonSegment(value: count, label: Text('$count')),
          ],
          selected: {shifts},
          onSelectionChanged: (picked) => game.submit(
            SetFactoryShifts(
              game.player,
              factory: factory.id,
              shifts: picked.single,
            ),
          ),
        ),
        Hint(
          shifts == 0
              ? tr('factory.stoppedHint')
              : tr('factory.shiftCost', {
                  'units': _count(kind.shiftUnits),
                  'amount': money(
                    _shiftCost(game, kind, factory.country),
                    cents: false,
                  ),
                }),
        ),
      ],
    );
  }
}

/// How much of its capacity a factory used this month, with a red mark
/// where it starts to pay.
class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.use, this.breakEven});

  final double use;
  final double? breakEven;

  @override
  Widget build(BuildContext context) {
    final ledger = Ledger.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: ledger.ink, width: 0.6),
                ),
              ),
              FractionallySizedBox(
                widthFactor: use,
                child: Container(color: ledger.ink),
              ),
              if (breakEven case final mark? when mark < 1)
                Positioned(
                  left: box.maxWidth * mark - 1,
                  top: -3,
                  bottom: -3,
                  child: Container(width: 2, color: ledger.loss),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.factory,
    required this.kind,
    required this.shown,
  });

  final FactoryView factory;
  final FactoryKindDef kind;
  final (PeriodReport, FactoryReport)? shown;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final level = game.view.economy(factory.country).priceIndex;
    final part = shown?.$2;
    // What isn't materials, shared by what each line sold for.
    final fixed = part == null
        ? Money.zero
        : part.wages + part.occupancy + part.freight;
    final sold = part == null
        ? Money.zero
        : part.totalOwnGoods + part.totalRivalSales;
    return Section(
      title: tr('factory.lines'),
      children: [
        for (final product in content.products)
          if (product.category == kind.category)
            () {
              final units = part == null
                  ? 0
                  : part.madeForOwn(product.id) +
                        part.madeForRivals(product.id);
              final value = part == null
                  ? Money.zero
                  : part.ownGoods(product.id) + part.rivalSales(product.id);
              if (units == 0) {
                final quote = marketQuote(
                  content,
                  factory.country,
                  product,
                  kind.minOrderUnits,
                  level,
                );
                return Line(
                  product.name,
                  quote == null ? '—' : money(quote.price),
                  hint: tr('factory.notMadeYet'),
                );
              }
              final charged = Money(value.cents ~/ units);
              final share = sold == Money.zero
                  ? Money.zero
                  : Money(fixed.cents * value.cents ~/ sold.cents);
              final madeFor = Money(
                (part!.materials(product.id) + share).cents ~/ units,
              );
              return Line(
                product.name,
                tr('factory.priceToCost', {
                  'price': money(charged),
                  'cost': money(madeFor),
                }),
                hint: tr('factory.lineUnits', {'units': _count(units)}),
                color: gainColor(context, (charged - madeFor).cents.sign),
              );
            }(),
        Hint(tr('factory.linesHint')),
      ],
    );
  }
}

class _SellsTo extends StatelessWidget {
  const _SellsTo({
    required this.factory,
    required this.kind,
    required this.shown,
  });

  final FactoryView factory;
  final FactoryKindDef kind;
  final (PeriodReport, FactoryReport)? shown;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final terms = game.termsOf(factory);
    final shops = [
      for (final (_, store) in game.myStores)
        if (store.status != StoreStatus.closed &&
            content.formats[store.format.index].sells[kind.category.index] &&
            terms.serves[content.countryOf(store.market).index])
          store,
    ];
    void change({List<bool>? serves, Fx? discount, bool exclusive = false}) =>
        game.submit(
          SetFactoryTerms(
            game.player,
            factory: factory.id,
            serves: serves ?? terms.serves,
            rivalDiscount: exclusive ? null : (discount ?? terms.rivalDiscount),
          ),
        );
    final rivals = shown == null
        ? 0
        : [
            for (final product in content.products)
              if (product.category == kind.category)
                shown!.$2.madeForRivals(product.id),
          ].fold(0, (sum, units) => sum + units);
    final factories = content.factories!;
    return Section(
      title: tr('factory.sellsTo'),
      children: [
        Line(
          tr('factory.yourShops', {'count': shops.length}),
          terms.rivalDiscount == null
              ? tr('factory.exclusive')
              : tr('factory.andRivals'),
        ),
        if (content.countries.length > 1) ...[
          const SizedBox(height: 6),
          Text(
            tr('factory.deliversTo'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final country in content.countries)
                FilterChip(
                  label: Text(country.name),
                  selected: terms.serves[country.id.index],
                  onSelected: country.id == factory.country || !kind.exports
                      ? null
                      : (on) => change(
                          serves: [
                            for (final (i, serves) in terms.serves.indexed)
                              i == country.id.index ? on : serves,
                          ],
                        ),
                ),
            ],
          ),
          Hint(
            kind.exports
                ? tr('factory.abroadHint', {
                    'days': factories.abroadDays,
                    'freight': percent(factories.freight, decimals: 0),
                  })
                : tr('factory.localHint'),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('factory.sellToRivals')),
          subtitle: Text(tr('factory.rivalsHint')),
          value: terms.rivalDiscount != null,
          onChanged: (on) => on
              ? change(discount: terms.rivalDiscount ?? _discounts[1])
              : change(exclusive: true),
        ),
        if (terms.rivalDiscount case final discount?) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final option in _discounts)
                ChoiceChip(
                  label: Text(
                    option == Fx.zero
                        ? tr('factory.atTheirPrice')
                        : tr('factory.under', {
                            'discount': percent(option, decimals: 0),
                          }),
                  ),
                  selected: option == discount,
                  onSelected: (_) => change(discount: option),
                ),
            ],
          ),
          Line(
            tr('factory.rivalsBought'),
            _count(rivals),
            hint: tr('factory.canSpare', {'units': _count(factory.spare)}),
          ),
        ],
        const SizedBox(height: 8),
        if (game.closing(factory))
          Hint(tr('factory.closing'))
        else
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _close(context, game),
              child: Text(tr('factory.close')),
            ),
          ),
      ],
    );
  }

  Future<void> _close(BuildContext context, SimulationController game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('factory.close')),
        content: Text(tr('factory.closeConfirm', {'factory': factory.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('factory.closeAction')),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      game.submit(CloseFactory(game.player, factory: factory.id));
    }
  }
}

/// Building a factory: what it makes, where, what the player's shops would
/// give it to make at each number of shifts, what it costs and how to pay.
class BuildFactoryPage extends StatefulWidget {
  const BuildFactoryPage({super.key});

  @override
  State<BuildFactoryPage> createState() => _BuildFactoryPageState();
}

class _BuildFactoryPageState extends State<BuildFactoryPage> {
  FactoryKindId? _kind;
  CountryId? _country;
  int? _shifts;
  bool _newCompany = false;
  bool? _borrow;
  bool _named = false;
  bool _built = false;
  late int _months = longestTerm(context.game.content);
  final _name = TextEditingController();
  final _capital = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    super.dispose();
  }

  /// The kind the player's shops buy most of, at first.
  FactoryKindId _firstKind(SimulationController game) {
    final kinds = game.content.factories!.kinds;
    var best = kinds.first.id;
    var most = -1;
    for (final kind in kinds) {
      final units = factoryOutlook(
        game.view,
        game.content,
        kind.id,
        game.homeCountry,
      ).units;
      if (units > most) {
        best = kind.id;
        most = units;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final factories = content.factories!;
    final theme = Theme.of(context);
    final kindId = _kind ??= _firstKind(game);
    final kind = factories.kinds[kindId.index];
    final country = _country ?? game.homeCountry;
    final outlook = factoryOutlook(game.view, content, kindId, country);
    final shifts = _shifts ?? outlook.best.shifts;
    final plan = outlook.plans[shifts - 1];
    if (!_named) {
      _name.text = tr('factory.defaultName', {
        'kind': kind.name,
        'country': content.countries[country.index].name,
      });
    }
    final company = game.company;
    final hasCompany =
        company != null && company.status == CompanyStatus.active;
    final separate = _newCompany || !hasCompany;
    final cost = outlook.buildCost;
    final capital = _capital.text.isEmpty
        ? Money.zero
        : parseMoney(_capital.text);
    final view = game.view;
    final spare =
        (separate
            ? Money.zero
            : company.cash - company.committed - game.cushion(company)) +
        (capital ?? Money.zero);
    final short =
        cost - (separate ? Money.zero : company.cash) - (capital ?? Money.zero);
    final amount = roundedUp(cost - spare);
    final borrow = amount > Money.zero && (_borrow ?? short > Money.zero);
    final room = separate
        ? Money.zero
        : view.companyCredits[company.id.index] ?? Money.zero;
    final guarantee =
        view.guaranteeRoom -
        (capital ?? Money.zero).times(content.finance.guaranteeMultiple);
    final terms = LoanTerms(
      view: view,
      content: content,
      amount: amount,
      credit: room.isNegative ? Money.zero : room,
      guarantee: guarantee.isNegative ? Money.zero : guarantee,
      months: _months,
      onMonths: (months) => setState(() => _months = months),
      note: separate ? tr('market.newCompanyNote') : null,
    );
    final ready =
        !_built &&
        capital != null &&
        _name.text.trim().isNotEmpty &&
        (borrow ? terms.split != null : short <= Money.zero);
    String planValue(FactoryShiftPlan plan) => [
      percent(plan.use, decimals: 0),
      if (plan.boughtIn > 0)
        tr('factory.plusBought', {'units': _count(plan.boughtIn)}),
      money(plan.earned, cents: false),
    ].join(' · ');
    Widget picked({
      required bool selected,
      required VoidCallback onTap,
      required Widget child,
    }) => InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? Ledger.of(context).shade : null,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
    final products = [
      for (final product in content.products)
        if (product.category == kind.category) product.name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('factory.whatItMakes'),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final option in factories.kinds)
                  ChoiceChip(
                    label: Text(option.name),
                    selected: option.id == kindId,
                    onSelected: (_) => setState(() {
                      _kind = option.id;
                      _shifts = null;
                      if (!option.exports) _country = null;
                    }),
                  ),
              ],
            ),
            Hint(tr('factory.makes', {'products': products.join(', ')})),
          ],
        ),
        if (content.countries.length > 1)
          Section(
            title: tr('factory.where'),
            children: [
              for (final option in content.countries)
                if (kind.exports || option.id == game.homeCountry)
                  picked(
                    selected: option.id == country,
                    onTap: () => setState(() {
                      _country = option.id;
                      _shifts = null;
                    }),
                    child: Line(
                      option.name,
                      [
                        tr('factory.wages', {
                          'wages': percent(option.service, decimals: 0),
                        }),
                        if (content.taxesOf(option.id) case final taxes?)
                          tr('factory.tax', {
                            'rate': percent(taxes.corporateRate),
                          }),
                        if (option.id != game.homeCountry)
                          tr('factory.daysMore', {
                            'days': factories.abroadDays,
                          }),
                      ].join(' · '),
                    ),
                  ),
              if (!kind.exports) Hint(tr('factory.localHint')),
            ],
          ),
        Section(
          title: tr('factory.yourShopsBuy'),
          children: [
            if (outlook.units == 0)
              Hint(tr('factory.noShops'))
            else ...[
              Line(
                tr('factory.unitsMonth', {'count': outlook.shops}),
                _count(outlook.units),
              ),
              for (final option in outlook.plans)
                picked(
                  selected: option.shifts == shifts,
                  onTap: () => setState(() => _shifts = option.shifts),
                  child: Line(
                    tr('factory.shiftsCapacity', {
                      'count': option.shifts,
                      'capacity': _count(option.capacity),
                    }),
                    planValue(option),
                    color: gainColor(context, option.earned.cents.sign),
                  ),
                ),
              Hint(tr('factory.planHint')),
              Line(
                tr('factory.inRecession'),
                [
                  percent(outlook.recession.use, decimals: 0),
                  money(outlook.recession.earned, cents: false),
                ].join(' · '),
                color: gainColor(context, outlook.recession.earned.cents.sign),
              ),
              if (plan.earned > Money.zero)
                Line(
                  tr('factory.paysBack'),
                  tr('factory.paybackYears', {
                    'years': decimalText(
                      (cost.cents / (plan.earned.cents * 12)).toStringAsFixed(
                        1,
                      ),
                    ),
                  }),
                ),
            ],
          ],
        ),
        Section(
          title: tr('factory.cost'),
          children: [
            Line(tr('factory.buildingCost'), money(cost, cents: false)),
            Line(
              tr('factory.works'),
              tr('common.nDays', {'days': kind.buildDays}),
            ),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('factory.name')),
              onChanged: (_) => setState(() => _named = true),
            ),
            if (hasCompany)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('factory.asNewCompany')),
                subtitle: Text(
                  _newCompany
                      ? tr('market.ownBooks')
                      : tr('market.ownedBy', {
                          'company': game.companyName(company.id),
                        }),
                ),
                value: _newCompany,
                onChanged: (on) => setState(() => _newCompany = on),
              ),
            TextField(
              controller: _capital,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('market.capitalFromCash'),
                helperText: tr('market.youHave', {'cash': money(view.cash)}),
                errorText: capital == null ? tr('common.notAnAmount') : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (amount > Money.zero)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market.borrowFromBank')),
                subtitle: borrow
                    ? null
                    : Text(
                        short > Money.zero
                            ? tr('market.needsMore', {
                                'amount': money(short, cents: false),
                              })
                            : tr('market.keepCushion'),
                      ),
                value: borrow,
                onChanged: (on) => setState(() => _borrow = on),
              ),
            if (borrow) terms,
            const SizedBox(height: 8),
            if (_built)
              Hint(tr('factory.buildTomorrow'))
            else
              FilledButton(
                onPressed: !ready
                    ? null
                    : () {
                        game.submit(
                          BuildFactory(
                            game.player,
                            kind: kindId,
                            country: country,
                            name: _name.text.trim(),
                            company: separate ? null : company.id,
                            capital: capital,
                            borrow: borrow ? amount : Money.zero,
                            termMonths: borrow ? _months : 0,
                            shifts: shifts,
                            serves: outlook.serves,
                          ),
                        );
                        setState(() => _built = true);
                      },
                child: Text(
                  borrow
                      ? tr('factory.buildWithLoan')
                      : tr('factory.buildFor', {
                          'amount': money(cost, cents: false),
                        }),
                ),
              ),
            Text(tr('factory.buildNote'), style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
