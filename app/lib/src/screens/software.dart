import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../business.dart';
import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'restructure.dart' show MoveOrSellSection;
import 'lab.dart' show PersonRow, points;

/// The shares a round may sell, as choices.
final _roundShares = [
  for (final share in ['0.10', '0.15', '0.20', '0.25']) Fx.parse(share),
];

/// [count] people, as a count with the language's separators.
String _count(int count) => money(Money(count * 100), cents: false);

/// [level], a level or pace in hundredths of a point, as points to one
/// decimal.
String _pointsText(Fx level) {
  final tenths = (level.raw.abs() + 5) ~/ 10;
  final sign = level.raw < 0 && tenths > 0 ? '−' : '';
  return '$sign${tenths ~/ 10}${tr('format.decimal')}${tenths % 10}';
}

/// Opens [software]'s page within the current tab.
void openSoftwarePage(BuildContext context, SoftwareView software) =>
    context.openPage(software.name, (_) => [SoftwarePage(id: software.id)]);

/// What [software] is doing, in a few words.
String softwareStatus(SoftwareView software) => switch (software.status) {
  SoftwareStatus.building => tr('software.building'),
  SoftwareStatus.selling => tr('software.sellingSince', {
    'date': shortDate(software.launchedOn!),
  }),
  SoftwareStatus.closed => tr('software.closed'),
  SoftwareStatus.sold => tr('software.sold'),
};

/// The months [software]'s company's cash lasts at this month's loss, or
/// null if it makes money.
int? _runway(CompanyView company, SoftwareView software) {
  final loss = -software.monthProfit.cents;
  if (loss <= 0) return null;
  final cash = company.cash.cents;
  return cash <= 0 ? 0 : cash ~/ loss;
}

/// Starting a software company: its name, where it works from, the money
/// put in, and how the business works.
class StartSoftwarePage extends StatefulWidget {
  const StartSoftwarePage({super.key, this.company});

  /// The company it starts in, picked already; a company of its own if
  /// null, unless the player picks one of theirs.
  final CompanyId? company;

  @override
  State<StartSoftwarePage> createState() => _StartSoftwarePageState();
}

class _StartSoftwarePageState extends State<StartSoftwarePage> {
  final _name = TextEditingController();
  final _capital = TextEditingController();
  CountryId? _country;
  bool _started = false;

  /// The company picked to start it in; a company of its own if null.
  late CompanyId? _company = widget.company;

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final content = game.content;
    final def = content.software!;
    // Beside the businesses of a company without software, or on its own.
    final homes = [
      for (final company in game.activeCompanies)
        if (company.software == null) company,
    ];
    final home = homes.where((c) => c.id == _company).firstOrNull;
    // Its capital comes from whoever holds that company.
    final parent = game.view.companies
        .where((c) => c.id == home?.parent)
        .firstOrNull;
    final cash = parent?.cash ?? game.view.cash;
    if (_capital.text.isEmpty && !_started) {
      _capital.text = home == null ? moneyInput(cash) : '0';
    }
    final country = _country ?? game.homeCountry;
    final capital = parseMoney(_capital.text);
    final name = _name.text.trim();
    final valid =
        name.isNotEmpty &&
        name.length <= maxNameLength &&
        capital != null &&
        capital >= Money.zero &&
        capital <= cash;
    String pay(int level) => money(def.levels[level].salary, cents: false);
    return Section(
      title: tr('software.start'),
      mark: Ledger.of(context).software,
      children: [
        if (_started)
          Hint(tr('software.starting', {'name': name}))
        else ...[
          TextField(
            controller: _name,
            maxLength: maxNameLength,
            decoration: InputDecoration(labelText: tr('software.name')),
            onChanged: (_) => setState(() {}),
          ),
          if (homes.isNotEmpty) ...[
            DropdownButtonFormField<CompanyId?>(
              initialValue: home?.id,
              decoration: InputDecoration(labelText: tr('software.where')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(tr('software.ownCompany')),
                ),
                for (final company in homes)
                  DropdownMenuItem(
                    value: company.id,
                    child: Text(game.companyName(company.id)),
                  ),
              ],
              // Beside a company's businesses, its own cash pays first.
              onChanged: (value) => setState(() {
                _company = value;
                _capital.text = value == null
                    ? moneyInput(game.view.cash)
                    : '0';
              }),
            ),
            Hint(
              home == null
                  ? tr('software.ownCompanyHint')
                  : tr('software.besideHint', {
                      'company': game.companyName(home.id),
                    }),
            ),
          ],
          if (content.countries.length > 1) ...[
            DropdownButtonFormField<CountryId>(
              initialValue: country,
              decoration: InputDecoration(labelText: tr('software.country')),
              items: [
                for (final c in content.countries)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (value) => setState(() => _country = value),
            ),
            Hint(tr('software.countryHint')),
          ],
          TextField(
            controller: _capital,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('software.capital')),
            onChanged: (_) => setState(() {}),
          ),
          Hint(
            tr(
              parent == null
                  ? 'software.capitalHint'
                  : 'software.capitalHintParent',
              {
                'company': ?parent == null ? null : game.companyName(parent.id),
                'cash': money(cash, cents: false),
                'low': pay(0),
                'high': pay(def.levels.length - 1),
              },
            ),
          ),
          const SizedBox(height: 8),
          Hint(
            tr('software.howProduct', {
              'gap': points(def.startGap).replaceAll('+', ''),
              'launch': points(def.launchGap).replaceAll('+', ''),
            }),
          ),
          Hint(tr('software.howPeople')),
          Hint(tr('software.howMoney')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: valid
                  ? () {
                      game.submit(
                        StartSoftware(
                          game.player,
                          name: name,
                          country: country,
                          capital: capital,
                          company: home?.id,
                        ),
                      );
                      setState(() => _started = true);
                    }
                  : null,
              child: Text(
                tr('software.startButton', {
                  'name': name.isEmpty ? tr('software.title') : name,
                }),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A software company's page, the owner's layout B: four headline figures
/// and the race against the standard, then pages for the product and team,
/// customers and price, the market, and owners and funding.
class SoftwarePage extends StatelessWidget {
  const SoftwarePage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final found = game.softwareWith(id);
    if (found == null) return Hint(tr('software.gone'));
    final (company, software) = found;
    final theme = Theme.of(context);
    final ledger = Ledger.of(context);
    final runway = _runway(company, software);
    final market = game.view.softwareMarket!;
    final rivals = market.rivals
        .where((r) => r.status != RivalStatus.folded && !r.rest)
        .length;
    final team = game.teamOf(software);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: software.name,
          mark: ledger.software,
          children: [
            Hint(softwareStatus(software)),
            if (software.running) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.people_outline,
                      label: tr('software.customers'),
                      value: Text(compactCount(software.customers)),
                      trend: software.growth > Fx.zero
                          ? tr('software.growthYear', {
                              'growth': percent(software.growth, decimals: 0),
                            })
                          : null,
                      trendSign: software.growth.raw.sign,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.payments_outlined,
                      label: tr('software.revenue'),
                      value: Text(compactMoney(software.revenue)),
                      trend: tr('software.profitLine', {
                        'profit': compactMoney(software.monthProfit),
                      }),
                      trendSign: software.monthProfit.cents.sign,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.hourglass_bottom,
                      label: tr('software.runway'),
                      value: Text(
                        runway == null
                            ? tr('software.runwayProfitable')
                            : tr('software.runwayMonths', {'count': runway}),
                      ),
                      color: runway != null && runway < 6 ? ledger.loss : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.pie_chart_outline,
                      label: tr('software.yourShare', {
                        'stake': percent(software.stake, decimals: 0),
                      }),
                      value: Text(compactMoney(software.yourWorth)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RaceChart(software: software),
              Hint(
                software.status == SoftwareStatus.building
                    ? tr('software.buildingLine', {
                        'gap': points(software.toLaunch).replaceAll('+', ''),
                      })
                    : tr('software.aheadLine', {
                        'lead': points(software.lead),
                        'rival': points(
                          software.history.lastOrNull?.bestRival ?? Fx.zero,
                        ),
                      }),
              ),
            ],
            IndexRow(
              title: tr('software.productAndTeam'),
              subtitle: tr('software.productAndTeamSub', {
                'people': tr('software.people', {'count': team}),
                'pace': _pointsText(software.pace),
              }),
              onTap: () => context.openPage(
                tr('software.productAndTeam'),
                (_) => [SoftwareProductPage(id: id)],
              ),
            ),
            IndexRow(
              title: tr('software.customersAndPrice'),
              subtitle: tr('software.customersAndPriceSub', {
                'price': money(game.softwarePriceOf(software)),
                'churn': percent(software.churn),
              }),
              onTap: () => context.openPage(
                tr('software.customersAndPrice'),
                (_) => [SoftwareCustomersPage(id: id)],
              ),
            ),
            IndexRow(
              title: tr('software.theMarket'),
              subtitle: tr('software.theMarketSub', {
                'rivals': rivals,
                'customers': compactCount(market.customers),
              }),
              onTap: () => context.openPage(
                tr('software.theMarket'),
                (_) => [SoftwareMarketPage(id: id)],
              ),
            ),
            IndexRow(
              title: tr('software.funding'),
              subtitle: tr('software.fundingSub', {
                'stake': percent(software.stake, decimals: 0),
              }),
              stamp: software.offer != null ? tr('software.offerStamp') : null,
              onTap: () => context.openPage(
                tr('software.funding'),
                (_) => [SoftwareFundingPage(id: id)],
              ),
            ),
          ],
        ),
        if (!software.running)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(tr('software.gone'), style: theme.textTheme.bodySmall),
          ),
        if (software.running)
          if (businessesOf(
                game,
                company,
                game.view.national,
              ).where((each) => each.kind == BusinessKind.software).firstOrNull
              case final business?)
            MoveOrSellSection(company: company, business: business),
      ],
    );
  }
}

/// The race against the market's standard month by month: the product's
/// lead in the company's colour, the best rival's in muted ink, the
/// standard a rule.
class RaceChart extends StatelessWidget {
  const RaceChart({super.key, required this.software, this.height = 96});

  final SoftwareView software;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ledger = Ledger.of(context);
    final theme = Theme.of(context);
    final history = software.history;
    if (history.length < 2) return Hint(tr('software.chartEmpty'));
    return Semantics(
      label: tr('software.chartHint'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _RacePainter(
                yours: [for (final m in history) m.lead.raw / Fx.scale],
                rival: [for (final m in history) m.bestRival.raw / Fx.scale],
                you: ledger.software,
                other: ledger.muted,
                rule: ledger.rule,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: [
              for (final (label, color) in [
                (tr('software.chartYou'), ledger.software),
                (tr('software.chartRival'), ledger.muted),
                (tr('software.chartStandard'), ledger.rule),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 3, color: color),
                    const SizedBox(width: 4),
                    Text(label, style: theme.textTheme.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RacePainter extends CustomPainter {
  _RacePainter({
    required this.yours,
    required this.rival,
    required this.you,
    required this.other,
    required this.rule,
  });

  final List<double> yours;
  final List<double> rival;
  final Color you;
  final Color other;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...yours, ...rival, 0.0];
    final high = math.max(all.reduce(math.max), 0.02);
    final low = math.min(all.reduce(math.min), -0.02);
    final span = high - low;
    double y(double lead) => size.height - size.height * (lead - low) / span;
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );
    void line(List<double> values, Color color, double width) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final point = Offset(
          size.width * i / (values.length - 1),
          y(values[i]),
        );
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line(rival, other, 1.2);
    line(yours, you, 2);
  }

  @override
  bool shouldRepaint(_RacePainter old) =>
      old.yours != yours || old.rival != rival || old.you != you;
}

/// The product against the standard, what the team builds, and the team.
class SoftwareProductPage extends StatelessWidget {
  const SoftwareProductPage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final found = game.softwareWith(id);
    if (found == null || !found.$2.running) return Hint(tr('software.gone'));
    final software = found.$2;
    final def = game.content.software!;
    final joining = [
      for (final person in game.view.softwareCandidates)
        if (game.hiringFor(software, person.id)) person,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('software.product'),
          children: [
            Line(
              tr('software.lead'),
              tr('software.points', {'points': points(software.lead)}),
              color: gainColor(context, software.lead.raw.sign),
            ),
            Line(
              tr('software.pace'),
              tr('software.paceValue', {'pace': _pointsText(software.pace)}),
            ),
            Line(
              tr('software.marketMoves'),
              tr('software.paceValue', {'pace': _pointsText(software.rise)}),
            ),
            if (software.appeal > Fx.zero)
              Line(
                tr('software.appeal'),
                tr('software.points', {'points': points(software.appeal)}),
              ),
            if (software.status == SoftwareStatus.building)
              Hint(switch (software.monthsToLaunch) {
                final months? => tr('software.launchIn', {'count': months}),
                null => tr('software.launchNever'),
              }),
            Hint(tr('software.productHint')),
          ],
        ),
        Section(
          title: tr('software.team', {
            'count': game.teamOf(software),
            'most': software.maxPeople,
          }),
          children: [
            if (software.team.isEmpty && joining.isEmpty)
              Hint(tr('software.noTeam')),
            for (final person in software.team)
              PersonRow(
                software: true,
                person: person,
                pay: person.salary,
                status: game.dismissing(person.id)
                    ? tr('lab.leaving')
                    : person.known
                    ? tr('lab.shown')
                    : tr('lab.reputed', {
                        'count': math.max(
                          1,
                          def.revealMonths - person.monthsWorked,
                        ),
                      }),
                action: game.dismissing(person.id)
                    ? null
                    : TextButton(
                        onPressed: () => game.submit(
                          DismissKeyPerson(game.player, person: person.id),
                        ),
                        child: Text(tr('lab.letGo')),
                      ),
              ),
            for (final person in joining)
              PersonRow(
                software: true,
                person: person,
                pay: person.salary.times(software.wageLevel),
                status: tr('lab.joins'),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => context.openPage(
                  tr('software.peopleMarket'),
                  (_) => [SoftwarePeoplePage(id: id)],
                ),
                child: Text(tr('software.peopleMarket')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The people on the market for software work, for [id] to hire.
class SoftwarePeoplePage extends StatelessWidget {
  const SoftwarePeoplePage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final found = game.softwareWith(id);
    if (found == null || !found.$2.running) return Hint(tr('software.gone'));
    final software = found.$2;
    final def = game.content.software!;
    final full = game.teamOf(software) >= software.maxPeople;
    final candidates = game.view.softwareCandidates;
    return Section(
      title: tr('software.peopleMarket'),
      children: [
        Hint(tr('software.marketHint', {'months': def.revealMonths})),
        if (candidates.isEmpty) Hint(tr('lab.noCandidates')),
        if (full) Hint(tr('software.full')),
        for (final person in candidates)
          PersonRow(
            software: true,
            person: person,
            pay: person.salary.times(software.wageLevel),
            status: game.hiringFor(software, person.id)
                ? tr('lab.joins')
                : tr('lab.leaves', {'date': shortDate(person.leaves!)}),
            action: game.hiringFor(software, person.id)
                ? TextButton(
                    onPressed: () => game.cancel(
                      game.pending.firstWhere(
                        (command) =>
                            command is HireSoftwarePerson &&
                            command.person == person.id,
                      ),
                    ),
                    child: Text(tr('common.cancel')),
                  )
                : full || game.hiring(person.id)
                ? null
                : TextButton(
                    onPressed: () => game.submit(
                      HireSoftwarePerson(
                        game.player,
                        software: software.id,
                        person: person.id,
                      ),
                    ),
                    child: Text(tr('lab.hire')),
                  ),
          ),
      ],
    );
  }
}

/// Customers, the price and marketing, and a month as it stands.
class SoftwareCustomersPage extends StatelessWidget {
  const SoftwareCustomersPage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final found = game.softwareWith(id);
    if (found == null || !found.$2.running) return Hint(tr('software.gone'));
    final software = found.$2;
    final ledger = Ledger.of(context);
    final price = game.softwarePriceOf(software);
    final marketing = game.softwareMarketingOf(software);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('software.customersTitle'),
          children: [
            Line(tr('software.customers'), _count(software.customers)),
            if (software.history.length >= 2)
              Sparkline([
                for (final month in software.history) month.customers,
              ], color: ledger.software),
            Line(tr('software.churn'), percent(software.churn)),
            if (software.growth > Fx.zero)
              Line(
                tr('software.growth'),
                percent(software.growth, decimals: 0),
              ),
          ],
        ),
        Section(
          title: tr('software.price'),
          children: [
            Line(
              tr('software.price'),
              money(price),
              hint: tr('software.priceHint', {
                'reference': money(software.referencePrice),
              }),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final chosen = await askAmount(
                    context,
                    title: tr('software.price'),
                    initial: price,
                  );
                  if (chosen != null) {
                    game.submit(
                      SetSoftwarePrice(
                        game.player,
                        software: software.id,
                        price: chosen,
                      ),
                    );
                  }
                },
                child: Text(tr('software.change')),
              ),
            ),
            Line(
              tr('software.marketing'),
              money(marketing, cents: false),
              hint: tr('software.marketingHint'),
            ),
            if (software.status == SoftwareStatus.selling &&
                marketing == software.marketing &&
                marketing > Money.zero)
              Hint(
                tr('software.fromMarketing', {
                  'count': compactCount(software.fromMarketing),
                }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final chosen = await askAmount(
                    context,
                    title: tr('software.marketing'),
                    initial: marketing,
                  );
                  if (chosen != null) {
                    game.submit(
                      SetSoftwareMarketing(
                        game.player,
                        software: software.id,
                        budget: chosen,
                      ),
                    );
                  }
                },
                child: Text(tr('software.change')),
              ),
            ),
          ],
        ),
        Section(
          title: tr('software.month'),
          children: [
            Line(tr('software.revenue'), money(software.revenue, cents: false)),
            Line(
              tr('software.serving'),
              money(-software.revenue.times(software.serving), cents: false),
            ),
            if (software.status == SoftwareStatus.selling)
              Line(
                tr('software.marketing'),
                money(-software.marketing, cents: false),
              ),
            Line(tr('software.offices'), money(-software.office, cents: false)),
            Line(
              tr('software.teamPay'),
              money(-software.payroll, cents: false),
            ),
            Line(
              tr('software.monthProfit'),
              money(software.monthProfit, cents: false),
              strong: true,
              color: gainColor(context, software.monthProfit.cents.sign),
            ),
            Hint(
              tr('software.breakEven', {
                'customers': _count(software.breakEven),
              }),
            ),
          ],
        ),
      ],
    );
  }
}

/// The world market: its size, its price and every rival's share.
class SoftwareMarketPage extends StatelessWidget {
  const SoftwareMarketPage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final market = game.view.softwareMarket!;
    final mine = game.softwareWith(id)?.$2;
    final rows =
        <({String name, int customers, Fx lead, Money price, String? tag})>[
          for (final rival in market.rivals)
            if (rival.status != RivalStatus.folded)
              (
                name: rival.rest ? tr('software.everyoneElse') : rival.name,
                customers: rival.customers,
                lead: rival.lead,
                price: rival.price,
                tag: rival.status == RivalStatus.building
                    ? tr('software.buildingTag')
                    : rival.startup
                    ? tr('software.startupTag')
                    : null,
              ),
          if (mine != null && mine.status == SoftwareStatus.selling)
            (
              name: tr('software.you', {'name': mine.name}),
              customers: mine.customers,
              lead: mine.lead,
              price: mine.price,
              tag: null,
            ),
        ]..sort((a, b) {
          final byCustomers = b.customers.compareTo(a.customers);
          return byCustomers != 0 ? byCustomers : a.name.compareTo(b.name);
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('software.marketTitle'),
          children: [
            Line(
              tr('software.marketCustomers'),
              compactCount(market.customers),
            ),
            Line(tr('software.averagePrice'), money(market.referencePrice)),
            Hint(tr('software.standardRises')),
          ],
        ),
        Section(
          title: tr('software.rivals'),
          children: [
            for (final row in rows)
              Line(
                [row.name, ?row.tag].join(' · '),
                tr('software.rivalLine', {
                  'share': share(row.customers, market.customers),
                  'lead': points(row.lead),
                  'price': money(row.price),
                }),
              ),
            Hint(tr('software.marketHint2')),
          ],
        ),
      ],
    );
  }
}

/// Who owns the company, what it is worth, its rounds, an offer, and the
/// way out.
class SoftwareFundingPage extends StatelessWidget {
  const SoftwareFundingPage({super.key, required this.id});

  final SoftwareId id;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final found = game.softwareWith(id);
    if (found == null || !found.$2.running) return Hint(tr('software.gone'));
    final software = found.$2;
    final ledger = Ledger.of(context);
    final worth = software.worth;
    final soon = software.nextRound > game.today;
    final offer = software.offer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('software.owners'),
          children: [
            SplitBar([
              (
                label: tr('software.ownersYou'),
                value: software.stake.raw,
                color: ledger.software,
              ),
              (
                label: tr('software.investors'),
                value: software.investors.raw,
                color: ledger.rule,
              ),
            ]),
            const SizedBox(height: 8),
            Line(tr('software.worth'), compactMoney(worth.worth), strong: true),
            Line(tr('software.yours'), compactMoney(software.yourWorth)),
            Hint(
              worth.yearRevenue.times(worth.multiple) >= worth.team
                  ? tr('software.worthRevenue', {
                      'revenue': compactMoney(worth.yearRevenue),
                      'multiple': fxText(worth.multiple),
                    })
                  : tr('software.worthTeam', {
                      'team': compactMoney(worth.team),
                    }),
            ),
          ],
        ),
        if (offer != null)
          Section(
            title: tr('software.offer'),
            children: [
              Hint(
                tr(
                  offer.whole
                      ? 'software.offerLine'
                      : 'software.offerLineAlone',
                  {
                    'rival': offer.rivalName,
                    'name': software.name,
                    'company': game.companyName(software.company),
                    'price': compactMoney(offer.price),
                  },
                ),
              ),
              Hint(
                tr('software.offerYours', {
                  'yours': compactMoney(offer.yours),
                  'date': shortDate(offer.expires),
                }),
              ),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _accept(context, game, software, offer),
                    child: Text(tr('software.accept')),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => game.submit(
                      DeclineSoftwareOffer(game.player, software: software.id),
                    ),
                    child: Text(tr('software.decline')),
                  ),
                ],
              ),
            ],
          ),
        Section(
          title: tr('software.rounds'),
          children: [
            if (software.rounds.isEmpty) Hint(tr('software.noRounds')),
            for (final round in software.rounds)
              Line(
                shortDate(round.day),
                tr('software.roundLine', {
                  'money': compactMoney(round.money),
                  'share': percent(round.share, decimals: 0),
                }),
              ),
            Hint(
              tr('software.raiseHint', {
                'max': percent(software.maxRoundShare, decimals: 0),
                'months': game.content.software!.roundMonths,
              }),
            ),
            if (soon)
              Hint(
                tr('software.nextRound', {
                  'date': shortDate(software.nextRound),
                }),
              )
            else if (worth.worth <= Money.zero)
              Hint(tr('software.cannotRaise'))
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final share in _roundShares)
                    if (share <= software.maxRoundShare)
                      OutlinedButton(
                        onPressed: () => _raise(context, game, software, share),
                        child: Text(percent(share, decimals: 0)),
                      ),
                ],
              ),
          ],
        ),
        Section(
          title: tr('software.shutDown'),
          children: [
            Hint(tr('software.shutDownBody')),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _shutDown(context, game, software),
                child: Text(tr('software.shutDown')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _raise(
    BuildContext context,
    SimulationController game,
    SoftwareView software,
    Fx share,
  ) async {
    final raised = roundMoney(software.worth.worth, share);
    final ok = await confirm(
      context,
      title: tr('software.raiseQuestion', {
        'share': percent(share, decimals: 0),
      }),
      body: tr('software.raiseBody', {
        'money': compactMoney(raised),
        'worth': compactMoney(software.worth.worth),
        'stake': percent(software.stake * (Fx.one - share), decimals: 0),
      }),
      action: tr('software.raiseConfirm'),
    );
    if (ok) {
      game.submit(RaiseRound(game.player, software: software.id, share: share));
    }
  }

  Future<void> _accept(
    BuildContext context,
    SimulationController game,
    SoftwareView software,
    SoftwareOfferView offer,
  ) async {
    final ok = await confirm(
      context,
      title: tr('software.acceptQuestion', {
        'name': software.name,
        'rival': offer.rivalName,
      }),
      body: offer.whole
          ? tr('software.acceptBody', {
              'yours': compactMoney(offer.yours),
              'rival': offer.rivalName,
            })
          : tr('software.acceptBodyAlone', {
              'company': game.companyName(software.company),
              'price': compactMoney(offer.price),
              'rival': offer.rivalName,
            }),
      action: tr('software.accept'),
    );
    if (ok) {
      game.submit(AcceptSoftwareOffer(game.player, software: software.id));
    }
  }

  Future<void> _shutDown(
    BuildContext context,
    SimulationController game,
    SoftwareView software,
  ) async {
    final ok = await confirm(
      context,
      title: tr('software.shutDownQuestion', {'name': software.name}),
      body: tr('software.shutDownBody'),
      action: tr('software.shutDown'),
    );
    if (ok) game.submit(ShutDownSoftware(game.player, software: software.id));
  }
}
