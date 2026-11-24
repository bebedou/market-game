import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../business.dart';
import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'factory.dart';
import 'holding.dart' show recentAverage;
import 'shop.dart';
import 'software.dart' show openSoftwarePage;
import 'restructure.dart' show MoveOrSellSection;
import 'start.dart' show openSector;
import 'world.dart' show openCountryPage;

/// The ink of [tone].
Color toneColor(BuildContext context, Tone tone) {
  final ledger = Ledger.of(context);
  return switch (tone) {
    Tone.good => ledger.gain,
    Tone.watch => ledger.watch,
    Tone.trouble => ledger.loss,
  };
}

/// "▲" or "▼" for [now] against [before], or nothing while they are equal or
/// there was nothing before.
String arrow(Money now, Money before) {
  if (before <= Money.zero || now == before) return '';
  return now > before ? ' ▲' : ' ▼';
}

/// What marks [business]: its trade's colour, the works' slate, or
/// software's teal.
Color businessMark(BuildContext context, Business business) {
  final ledger = Ledger.of(context);
  return switch (business.kind) {
    BusinessKind.trade => ledger.trade(
      context.game.content.formats[business.format!.index],
    ),
    BusinessKind.works => ledger.works,
    BusinessKind.software => ledger.software,
  };
}

/// Opens [business] within the current tab; software opens its own page.
void openBusinessPage(BuildContext context, Business business) {
  if (business.software case final software?) {
    openSoftwarePage(context, software);
    return;
  }
  context.openPage(
    business.name,
    (_) => [
      BusinessPage(
        company: business.company.id,
        kind: business.kind,
        name: business.key,
      ),
    ],
  );
}

/// A business, the owner's layout B (2026-11-17): a verdict, four key
/// figures with their lines, then its parts. A trade shows its countries,
/// its kinds of shop and brands, and, run by hand, its shops; plants show
/// each plant. Under a director, figures only.
class BusinessPage extends StatelessWidget {
  const BusinessPage({
    super.key,
    required this.company,
    required this.kind,
    required this.name,
  });

  final CompanyId company;
  final BusinessKind kind;

  /// Its key: its trade's or its kind of plant's.
  final String name;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final owner = game.view.companies
        .where((each) => each.id == company)
        .firstOrNull;
    final business = owner == null
        ? null
        : businessesOf(
            game,
            owner,
            game.view.national,
          ).where((each) => each.kind == kind && each.key == name).firstOrNull;
    if (owner == null || business == null) {
      return Hint(tr('businesses.gone'));
    }
    final verdict = businessVerdict(business);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VerdictBox(verdict.text, color: toneColor(context, verdict.tone)),
        FigureGrid(_figures(game, business)),
        if (business.kind == BusinessKind.trade) ...[
          _Countries(business: business),
          _Kinds(business: business),
          if (game.directorOf(owner) == null) _Shops(business: business),
        ],
        if (business.kind == BusinessKind.works) _Plants(business: business),
        MoveOrSellSection(company: owner, business: business),
      ],
    );
  }

  static List<Figure> _figures(SimulationController game, Business business) {
    final months = business.months;
    final last = months.lastOrNull;
    final sales = [for (final month in months) month.sales.cents];
    final profits = [for (final month in months) month.profit.cents];
    String moneyOf(Money? amount) =>
        amount == null ? '–' : compactMoney(amount);
    switch (business.kind) {
      case BusinessKind.trade:
        // What it kept of its sales, in tenths of a percent, by month.
        final margins = [
          for (final month in months)
            month.sales <= Money.zero
                ? 0
                : month.profit.cents * 1000 ~/ month.sales.cents,
        ];
        final perShop = [
          for (final month in months)
            month.units == 0 ? 0 : month.sales.cents ~/ month.units,
        ];
        final quarterSales = lastQuarter([for (final m in months) m.sales]);
        final quarterProfit = lastQuarter([for (final m in months) m.profit]);
        return [
          (
            label: tr('businesses.figures.sales'),
            value: moneyOf(last?.sales),
            values: sales,
          ),
          (
            label: tr('businesses.figures.margin'),
            value: quarterSales <= Money.zero
                ? '–'
                : percentOf(
                    (quarterProfit.cents * 1000 ~/ quarterSales.cents / 10)
                        .toStringAsFixed(1),
                  ),
            values: margins,
          ),
          (
            label: tr('businesses.figures.shops'),
            value: '${business.units}',
            values: [for (final month in months) month.units],
          ),
          (
            label: tr('businesses.figures.perShop'),
            value: last == null || last.units == 0
                ? '–'
                : compactMoney(Money(last.sales.cents ~/ last.units)),
            values: perShop,
          ),
        ];
      case BusinessKind.works:
        // Its last four weeks' output against what its shifts can make.
        var capacity = 0;
        var made = 0;
        for (final plant in business.factories) {
          if (!plant.making) continue;
          capacity += plant.monthCapacity;
          made += plant.recentOwnUnits + plant.recentRivalUnits;
        }
        return [
          (
            label: tr('businesses.figures.sales'),
            value: moneyOf(last?.sales),
            values: sales,
          ),
          (
            label: tr('businesses.figures.profit'),
            value: last == null ? '–' : signedMoney(last.profit, cents: false),
            values: profits,
          ),
          (
            label: tr('businesses.figures.plants'),
            value: '${business.units}',
            values: null,
          ),
          (
            label: tr('businesses.figures.use'),
            value: capacity == 0
                ? '–'
                : percentOf((made * 100 ~/ capacity).clamp(0, 100)),
            values: null,
          ),
        ];
      case BusinessKind.software:
        return const [];
    }
  }
}

/// A trade's countries, a line each with its shops there and last month's
/// sales, opening the country's page; then where it isn't yet.
class _Countries extends StatelessWidget {
  const _Countries({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final parts = byCountry(game, business);
    final here = {for (final part in parts) part.country};
    final elsewhere = [
      for (final country in content.countries)
        if (!here.contains(country.id)) country.name,
    ];
    return Section(
      title: tr('businesses.byCountry'),
      children: [
        for (final part in parts)
          IndexRow(
            title: content.countries[part.country.index].name,
            subtitle: tr('common.stores', {'count': part.units}),
            value:
                '${compactMoney(part.sales)}${arrow(part.sales, part.before)}',
            onTap: () =>
                openCountryPage(context, content.countries[part.country.index]),
          ),
        if (elsewhere.isNotEmpty)
          Hint(tr('businesses.notYet', {'countries': elsewhere.join(', ')})),
      ],
    );
  }
}

/// A trade's kinds of shop with how many it has of each, then its brands
/// and the way to start one.
class _Kinds extends StatelessWidget {
  const _Kinds({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final ledger = Ledger.of(context);
    final counts = <FormatId, int>{};
    void count(FormatId format, int n) =>
        counts[format] = (counts[format] ?? 0) + n;
    for (final store in business.stores) {
      count(store.format, 1);
    }
    for (final (_, block) in business.blocks) {
      count(block.format, block.stores);
    }
    for (final (_, shop) in business.districtShops) {
      count(shop.format, 1);
    }
    final brands = [
      for (final brand in game.myBrands)
        if (tradeOf(content.formats[brand.format.index]) == business.key) brand,
    ];
    return Section(
      title: tr('businesses.kinds'),
      children: [
        for (final format in content.formats)
          if ((counts[format.id] ?? 0) > 0)
            IndexRow(
              mark: ledger.trade(format),
              title: format.name,
              value: '${counts[format.id]}',
              onTap: null,
            ),
        for (final brand in brands)
          IndexRow(
            icon: Icons.sell_outlined,
            title: brand.name,
            subtitle:
                '${content.formats[brand.format.index].name} · '
                '${tr('common.stores', {'count': brand.shops})}',
            onTap: null,
          ),
        IndexRow(
          icon: Icons.add,
          title: tr('dashboard.createBrand'),
          subtitle: tr('dashboard.createBrandPitch'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => GameScope(
              controller: game,
              child: CreateBrandDialog(trade: business.key),
            ),
          ),
        ),
      ],
    );
  }
}

/// The shops of a trade its owner runs by hand, a line each that opens it,
/// and the way to open another.
class _Shops extends StatelessWidget {
  const _Shops({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return Section(
      title: business.stores.length == 1
          ? tr('dashboard.yourStore')
          : tr('common.yourStores'),
      children: [
        for (final store in business.stores)
          StoreLine(
            company: business.company,
            store: store,
            onTap: () {
              game.selectStore(store.id);
              openStorePage(context);
            },
          ),
        IndexRow(
          icon: Icons.add,
          title: tr('businesses.openShop'),
          onTap: () => openSector(context, business.key),
        ),
      ],
    );
  }
}

/// A kind of plant's plants, a line each that opens it, and the way to
/// build another.
class _Plants extends StatelessWidget {
  const _Plants({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: tr('businesses.plants'),
      children: [
        for (final plant in business.factories) FactoryLine(factory: plant),
        IndexRow(
          icon: Icons.add,
          title: tr('businesses.buildPlant'),
          onTap: () => context.openPage(
            business.name,
            (_) => [BuildFactoryPage(kind: business.factoryKind)],
          ),
        ),
      ],
    );
  }
}

/// One of the player's stores on a line: its kind and place, shoppers,
/// this week's sales, and the worst of its troubles, stamped.
class StoreLine extends StatelessWidget {
  const StoreLine({
    super.key,
    required this.company,
    required this.store,
    required this.onTap,
  });

  final CompanyView company;
  final StoreView store;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final week = game
        .reports(ReportPeriod.week, company: company.id)
        .lastOrNull
        ?.store(store.id);
    var sales = Money.zero;
    if (week != null) {
      for (final product in content.products) {
        sales += week.revenue(product.id);
      }
    }
    final (shoppers, _) = recentAverage(store.sales.dailyVisits);
    final (sold, _) = recentAverage(store.sales.dailySold);
    final listed = [
      for (final product in content.products)
        if (store.prices[product.id.index] != null) product.id.index,
    ];
    final stock = store.stock.fold(0, (sum, units) => sum + units);
    final coming = store.onOrder.fold(0, (sum, units) => sum + units);
    final cover = sold == null || sold == 0 ? null : (stock + coming) ~/ sold;
    final soldOut = listed.where((i) => store.stock[i] == 0).length;
    final open = store.status == StoreStatus.open;
    final trouble = [
      if (store.status == StoreStatus.closed) tr('common.closed'),
      if (open &&
          game.staffOf(store).every((staff) => staff == 0) &&
          !game.delegates(store, ManagerDuty.staffing))
        tr('dashboard.stampNoStaff'),
      if (open && listed.isNotEmpty && stock == 0) tr('dashboard.stampEmpty'),
      if (open && soldOut > 0 && soldOut < listed.length)
        tr('dashboard.stampSoldOut', {'count': soldOut}),
      if (open && cover != null && cover < 3)
        tr('common.daysOfStock', {'cover': cover}),
    ];
    final format = content.formats[store.format.index];
    return IndexRow(
      mark: Ledger.of(context).trade(format),
      title: game.storeName(store.id),
      subtitle: [
        format.name,
        if (content.markets.length > 1)
          content.markets[store.market.index].name,
        if (store.status == StoreStatus.building)
          tr('common.opensOn', {'date': shortDate(store.opensOn)})
        else if (shoppers != null)
          tr('dashboard.shoppersLine', {'shoppers': shoppers}),
        if (store.manager case final manager?)
          managerOf(content.managers.grades[manager.grade.index]),
        if (store.works != null) tr('dashboard.worksUnderWay'),
      ].join(' · '),
      stamp: trouble.firstOrNull,
      value: store.status == StoreStatus.building
          ? null
          : money(sales, cents: false),
      onTap: onTap,
    );
  }
}

/// A brand's name and its one kind of shop, of [trade] when started from a
/// trade's page.
class CreateBrandDialog extends StatefulWidget {
  const CreateBrandDialog({super.key, this.trade});

  final String? trade;

  @override
  State<CreateBrandDialog> createState() => _CreateBrandDialogState();
}

class _CreateBrandDialogState extends State<CreateBrandDialog> {
  final _name = TextEditingController();
  FormatId? _format;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final theme = Theme.of(context);
    final formats = [
      for (final format in game.content.formats)
        if (widget.trade == null || tradeOf(format) == widget.trade) format,
    ];
    final format = _format ?? formats.first.id;
    final name = _name.text.trim();
    final taken = game.view.brands.any(
      (brand) => brand.name.toLowerCase() == name.toLowerCase(),
    );
    return AlertDialog(
      title: Text(tr('dashboard.newBrand')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('dashboard.brandName'),
                errorText: taken ? tr('dashboard.brandTaken') : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              tr('dashboard.brandFormat'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in formats)
                  ChoiceChip(
                    avatar: Icon(formatIcon(option), size: 18),
                    label: Text(option.name),
                    selected: option.id == format,
                    onSelected: (_) => setState(() => _format = option.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Hint(tr('dashboard.brandHint')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: name.isEmpty || taken
              ? null
              : () {
                  game.createBrand(name, format);
                  Navigator.pop(context);
                },
          child: Text(tr('dashboard.createBrandButton')),
        ),
      ],
    );
  }
}
