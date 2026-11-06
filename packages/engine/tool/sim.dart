// Headless runner: plays a scenario for many seeds with a strategy bot in the
// player's seat, writes daily metrics per store as CSV, and summarizes
// stability, profitability, entry and bankruptcy. A bot named
// `<strategy>@<grade>` leaves the player's store to a manager of that grade
// with every duty, and makes only the owner's calls: enlarging, dividends
// and topping the company up. A bot named `<strategy>#<grade>-<growth>`
// hires a director of that grade, growing as far as that, who pays the
// profit out and hires experienced managers; the owner only tops the
// company up. A bot named `<strategy>+credit` runs its stores itself, keeps
// the profit in the company and grows on credit; `<strategy>+cash` grows
// the same way from its own cash only (see [CreditOwner]). A director's bot
// ending in `+borrow` lets them borrow.
//
//   dart run tool/sim.dart --scenario prototype --seeds 1-20 --days 1825 \
//       --player idle,discount,balanced,premium,discount@expert --out runs
import 'dart:io';
import 'dart:isolate';

import 'package:engine/engine.dart';
import 'package:engine/src/core/safe_int.dart';
import 'package:engine/src/state/world_state.dart';

/// Days after a store opens that the stability checks ignore.
const warmupDays = 60;

/// Days at the end of a run that the shares and price levels describe.
const finalDays = 365;

/// Daily price index bounds outside which a store is flagged as runaway.
final lowestPriceIndex = Fx.parse('0.70');
final highestPriceIndex = Fx.parse('1.40');

/// Consecutive open days without a sale after which a store is flagged.
const deadDays = 30;

/// A share of a market's visits in the final year above which one company
/// dominates it.
final dominantShare = Fx.parse('0.70');

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final scenario = options['scenario'] ?? 'prototype';
  final path = scenario.endsWith('.json')
      ? scenario
      : Platform.script
            .resolve('../../../content/scenarios/$scenario.json')
            .toFilePath();
  final json = File(path).readAsStringSync();
  final content = loadScenario(json);
  final seeds = _parseSeeds(options['seeds'] ?? '1-10');
  final days = int.parse(options['days'] ?? '1095');
  final bots = (options['player'] ?? 'idle').split(',');
  final out = options['out'] ?? 'runs';
  final parallel = int.parse(
    options['jobs'] ?? '${Platform.numberOfProcessors}',
  );
  for (final bot in bots) {
    if (bot.contains('#')) continue;
    final [strategy, ...grade] = bot.split('+').first.split('@');
    if (bot != 'idle' && !content.strategies.any((s) => s.key == strategy)) {
      stderr.writeln('Unknown strategy "$strategy"');
      exitCode = 64;
      return;
    }
    if (grade.isNotEmpty &&
        !content.managers.grades.any((g) => g.key == grade.single)) {
      stderr.writeln('Unknown manager grade "${grade.single}"');
      exitCode = 64;
      return;
    }
  }

  final jobs = [
    for (final bot in bots)
      for (final seed in seeds)
        Job(scenarioJson: json, bot: bot, seed: seed, days: days, out: out),
  ];
  final results = <JobResult>[];
  final queue = List.of(jobs.reversed);
  final clock = Stopwatch()..start();
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final job = queue.removeLast();
      results.add(await Isolate.run(() => runJob(job, writeCsv: true)));
    }
  }

  await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  results.sort(
    (a, b) => a.bot != b.bot ? a.bot.compareTo(b.bot) : a.seed - b.seed,
  );
  File('$out/companies.csv').writeAsStringSync(companiesCsv(results));
  File('$out/stores.csv').writeAsStringSync(storesCsv(results));
  File('$out/evolution.csv').writeAsStringSync(evolutionCsv(results));
  stdout
    ..writeln(
      '${jobs.length} runs of $days days in '
      '${clock.elapsedMilliseconds ~/ 1000} s; CSV in $out/',
    )
    ..write(summaryText(content, results));
}

/// One simulation run.
final class Job {
  const Job({
    required this.scenarioJson,
    required this.bot,
    required this.seed,
    required this.days,
    required this.out,
  });

  final String scenarioJson;

  /// The strategy playing for the player, or `idle`.
  final String bot;
  final int seed;
  final int days;
  final String out;
}

/// What one run produced.
final class JobResult {
  const JobResult(
    this.bot,
    this.seed,
    this.days,
    this.companies,
    this.stores,
    this.flags,
    this.regimeDays,
    this.priceIndex,
    this.years,
    this.markets,
    this.purchases,
    this.rescues,
  );

  final String bot;
  final int seed;
  final int days;

  /// Each whole year of the run, in order.
  final List<YearRecord> years;

  /// Days spent in each regime of the business cycle, indexed by [RegimeId].
  final List<int> regimeDays;

  /// The price index at the end.
  final Fx priceIndex;

  /// Every company, indexed by [CompanyId].
  final List<CompanySummary> companies;

  /// Every store, indexed by [StoreId].
  final List<StoreSummary> stores;

  /// Problems with a market as a whole, empty if none.
  final Set<String> flags;

  /// Stores that changed hands, and how many of those were sold by a
  /// company being wound up.
  final int purchases;
  final int rescues;

  /// Each market at the end, indexed by [MarketId].
  final List<MarketRecord> markets;
}

/// A market at the end of a run.
typedef MarketRecord = ({int households, int stores, int opened});

/// One year of a run, from one anniversary of the start to the next.
typedef YearRecord = ({
  /// Households in every market at the year's end.
  int households,

  /// Stores trading at the year's end.
  int stores,
  Fx priceIndex,

  /// The player's companies' net profit over the year.
  Money playerProfit,

  /// The player's stores' share of the year's shopping trips.
  Fx playerShare,
  int recessionDays,

  /// The player's stores open at the year's end, what their companies owe
  /// the bank, and the player's net worth: personal cash and the
  /// companies' net assets.
  int playerStores,
  Money playerDebt,
  Money playerWorth,
});

final class CompanySummary {
  CompanySummary({
    required this.name,
    required this.owner,
    required this.isPlayer,
    required this.founded,
    required this.liquidated,
    required this.revenue,
    required this.grossProfit,
    required this.netProfit,
    required this.dividends,
    required this.cash,
  });

  final String name;
  final String owner;
  final bool isPlayer;

  /// Run days.
  final int founded;
  final int? liquidated;
  final Money revenue;

  /// Sales less cost of goods and stock written off.
  final Money grossProfit;

  /// Gross profit less wages, salaries, rent, interest, research, opening costs and
  /// debts written off.
  final Money netProfit;
  final Money dividends;
  final Money cash;

  int lifetime(int days) => (liquidated ?? days) - founded;

  Money netProfitPerYear(int days) => _perYear(netProfit, lifetime(days));
}

final class StoreSummary {
  StoreSummary(
    this.name,
    this.company,
    this.market,
    this.opened, {
    this.format = '',
  });

  final String name;

  /// The format's key when it opened.
  final String format;
  final CompanyId company;
  final MarketId market;

  /// Run days.
  final int opened;
  int? closed;
  Money revenue = Money.zero;
  Money writeOffs = Money.zero;
  Money costOfGoods = Money.zero;
  int sold = 0;
  int outOfStock = 0;
  int lastSale = 0;

  /// Enlargements finished.
  int enlargements = 0;

  /// Over the last [finalDays] days.
  int finalVisits = 0;
  int finalMarketVisits = 0;
  int finalDaysOpen = 0;
  Fx finalPriceIndexSum = Fx.zero;

  /// Stability problems found, empty if none.
  final flags = <String>{};

  Fx get finalShare => _rate(finalVisits, finalMarketVisits);

  Fx get finalPriceIndex => finalDaysOpen == 0
      ? Fx.zero
      : Fx.raw(finalPriceIndexSum.raw ~/ finalDaysOpen);

  Fx get stockoutRate => _rate(outOfStock, sold + outOfStock);

  Fx get writeOffRate => _rate(writeOffs.cents, costOfGoods.cents);
}

/// Runs [job] and returns its summary; with [writeCsv], also writes its
/// daily metrics to `<out>/<bot>/seed-<seed>.csv`.
JobResult runJob(Job job, {bool writeCsv = false}) {
  final content = loadScenario(job.scenarioJson);
  final policies = standardPolicies(content);
  final [strategyKey, ...gradeKey] = job.bot
      .split('#')
      .first
      .split('+')
      .first
      .split('@');
  final directed = job.bot.contains('#');
  final strategy = content.strategies
      .where((s) => s.key == strategyKey)
      .firstOrNull;
  if (strategy != null) {
    policies[content.player] = directed
        ? OwnerDecisions(RetailPolicy(strategy), dividends: false)
        : job.bot.endsWith('+credit') || job.bot.endsWith('+cash')
        ? CreditOwner(strategy, borrows: job.bot.endsWith('+credit'))
        : gradeKey.isEmpty
        ? ownerPolicy(strategy)
        : OwnerDecisions(RetailPolicy(strategy));
  }
  final simulation = Simulation.newGame(
    content,
    seed: job.seed,
    policies: policies,
  );
  if (strategy != null && directed) {
    final [grade, growth] = job.bot.split('#').last.split('+').first.split('-');
    simulation.submit(
      HireDirector(
        content.player,
        company: CompanyId(
          content.companies.indexWhere(
            (company) => company.owner == content.player,
          ),
        ),
        grade: content.directors!.grades
            .firstWhere((option) => option.key == grade)
            .id,
        strategy: strategy.id,
        managerGrade: content.managers.grades
            .firstWhere((option) => option.key == 'experienced')
            .id,
        growth: Growth.values.byName(growth),
        payout: true,
        borrows: job.bot.endsWith('+borrow'),
      ),
    );
  }
  if (strategy != null && gradeKey.isNotEmpty) {
    simulation.submit(
      HireManager(
        content.player,
        store: StoreId(
          content.stores.indexWhere(
            (store) =>
                content.companies[store.company.index].owner == content.player,
          ),
        ),
        grade: content.managers.grades
            .firstWhere((grade) => grade.key == gradeKey.single)
            .id,
        strategy: strategy.id,
        duties: [for (final _ in ManagerDuty.values) true],
      ),
    );
  }
  final world = simulation.world;
  final stores = <StoreSummary>[];
  final liquidated = <CompanyId, int>{};
  final owners = [for (final store in world.stores) store.company];
  var purchases = 0;
  var rescues = 0;
  final regimeDays = List.filled(content.macro.regimes.length, 0);
  // Visits in the final year, by market, channel and company: stores only take
  // shoppers from those of their own channel.
  final channelOf = content.formatChannels;
  final finalCompanyVisits = <(int, int, CompanyId), int>{};
  final finalChannelVisits = <(int, int), int>{};
  // An idle player's store never stocks anything, by design.
  final unchecked = job.bot == 'idle' ? content.player : null;
  final csv = StringBuffer(
    'day,date,regime,store,company,status,area,listed,staff,price_index,visits,'
    'sold,revenue,cost_of_goods,write_offs,wages,rent,overheads,out_of_stock,'
    'not_listed,overpriced,stock,cash,reputation\n',
  );

  final years = <YearRecord>[];
  var yearTrips = 0;
  var yearPlayerTrips = 0;
  var yearRecessionDays = 0;
  var playerProfitSoFar = Money.zero;
  for (var day = 0; day < job.days; day++) {
    final result = simulation.step();
    regimeDays[world.macro.regime.index]++;
    final regime = content.macro.regimes[world.macro.regime.index];
    if (regime.key == 'recession') yearRecessionDays++;
    for (final store in world.stores) {
      final trips = result.attribution.visits[store.id.index];
      yearTrips += trips;
      if (world.companies[store.company.index].owner == content.player) {
        yearPlayerTrips += trips;
      }
    }
    if (day % 365 == 364) {
      final playerProfit = [
        for (final company in world.companies)
          if (company.owner == content.player)
            _companySummary(world, content, company.id, null).netProfit,
      ].fold(Money.zero, (sum, profit) => sum + profit);
      bool mine(CompanyId id) {
        final company = world.companies[id.index];
        return company.owner == content.player && company.isActive;
      }

      years.add((
        households: world.cohorts.fold(0, (sum, c) => sum + c.weight),
        stores: world.stores.where((s) => s.status == StoreStatus.open).length,
        priceIndex: world.macro.priceIndex,
        playerProfit: playerProfit - playerProfitSoFar,
        playerShare: _rate(yearPlayerTrips, yearTrips),
        recessionDays: yearRecessionDays,
        playerStores: world.stores
            .where((s) => s.status == StoreStatus.open && mine(s.company))
            .length,
        playerDebt: world.loans
            .where((loan) => mine(loan.company))
            .fold(Money.zero, (sum, loan) => sum + loan.outstanding),
        playerWorth: world.companies
            .where((company) => mine(company.id))
            .fold(
              world.persons[content.player.index].accounts[AccountKind.cash],
              (sum, company) => sum + company.accounts.netAssets,
            ),
      ));
      playerProfitSoFar = playerProfit;
      yearTrips = 0;
      yearPlayerTrips = 0;
      yearRecessionDays = 0;
    }
    for (var i = stores.length; i < world.stores.length; i++) {
      final store = world.stores[i];
      stores.add(
        StoreSummary(
          store.name,
          store.company,
          store.market,
          day,
          format: content.formats[store.format.index].key,
        ),
      );
    }
    for (final event in result.events.whereType<CompanyLiquidated>()) {
      liquidated[event.company] = day;
    }
    rescues += result.events.whereType<StoreSold>().length;
    for (final store in world.stores) {
      if (store.id.index >= owners.length) {
        owners.add(store.company);
      } else if (owners[store.id.index] != store.company) {
        owners[store.id.index] = store.company;
        purchases++;
      }
    }
    final count = world.stores.length;
    final sold = List.filled(count, 0);
    final revenue = List.filled(count, Money.zero);
    final costOfGoods = List.filled(count, Money.zero);
    final writeOffs = List.filled(count, Money.zero);
    final rent = List.filled(count, Money.zero);
    final overheads = List.filled(count, Money.zero);
    final wages = List.filled(count, Money.zero);
    for (final entry in result.entries) {
      final store = entry.store?.index;
      if (entry.party.type != PartyType.company || store == null) continue;
      switch (entry.reason) {
        case EntryReason.sale:
          sold[store] += entry.units;
          revenue[store] += entry.amount;
        case EntryReason.costOfSale:
          costOfGoods[store] += entry.amount;
        case EntryReason.spoilage ||
            EntryReason.delisting ||
            EntryReason.closure:
          writeOffs[store] += entry.amount;
        case EntryReason.rent when entry.debit == AccountKind.rent:
          rent[store] += entry.amount;
        case EntryReason.overheads when entry.debit == AccountKind.overheads:
          overheads[store] += entry.amount;
        case EntryReason.wages when entry.debit == AccountKind.wages:
          wages[store] += entry.amount;
        default:
          break;
      }
    }
    final missed = [
      for (var i = 0; i < count; i++) List.filled(MissReason.values.length, 0),
    ];
    for (final MapEntry(key: miss, value: units)
        in result.attribution.misses.entries) {
      missed[miss.store.index][miss.reason.index] += units;
    }
    final visits = result.attribution.visits;
    final channelVisits = <(int, int), int>{};
    for (final store in world.stores) {
      final key = (store.market.index, channelOf[store.format.index]);
      channelVisits[key] = (channelVisits[key] ?? 0) + visits[store.id.index];
    }
    final inFinalYear = day >= job.days - finalDays;
    if (inFinalYear) {
      for (final store in world.stores) {
        final channel = channelOf[store.format.index];
        final key = (store.market.index, channel, store.company);
        finalChannelVisits[(store.market.index, channel)] =
            (finalChannelVisits[(store.market.index, channel)] ?? 0) +
            visits[store.id.index];
        finalCompanyVisits[key] =
            (finalCompanyVisits[key] ?? 0) + visits[store.id.index];
      }
    }

    for (final store in world.stores) {
      final i = store.id.index;
      final summary = stores[i];
      if (summary.closed != null) continue;
      if (store.status == StoreStatus.closed) summary.closed = day;
      final index = _priceIndex(
        content,
        store.prices,
        world.macro.priceIndex * content.markets[store.market.index].priceLevel,
      );
      final cash =
          world.companies[store.company.index].accounts[AccountKind.cash];
      summary
        ..enlargements =
            (store.area - content.sites[store.site.index].area) ~/
            content.expansion.stepArea
        ..revenue += revenue[i]
        ..writeOffs += writeOffs[i]
        ..costOfGoods += costOfGoods[i]
        ..sold += sold[i]
        ..outOfStock += missed[i][MissReason.outOfStock.index];
      final open = store.status == StoreStatus.open;
      if (sold[i] > 0 || !open) summary.lastSale = day;
      final daysOpen = day - (store.opensOn.number - content.startDay.number);
      final checked =
          open &&
          daysOpen >= warmupDays &&
          world.companies[store.company.index].owner != unchecked;
      if (checked) {
        if (index != null &&
            (index < lowestPriceIndex || index > highestPriceIndex)) {
          summary.flags.add('runaway price');
        }
        if (day - summary.lastSale >= deadDays) summary.flags.add('no sales');
      }
      if (inFinalYear && open) {
        summary
          ..finalVisits += visits[i]
          ..finalMarketVisits +=
              channelVisits[(
                store.market.index,
                channelOf[store.format.index],
              )]!
          ..finalDaysOpen += 1;
        if (index != null) summary.finalPriceIndexSum += index;
      }
      if (writeCsv) {
        csv.writeln(
          [
            day,
            result.day.toIsoString(),
            content.macro.regimes[world.macro.regime.index].key,
            _csvText(store.name),
            _csvText(world.companies[store.company.index].name),
            store.status.name,
            store.area,
            store.listedProducts,
            store.staff.fold(0, (sum, count) => sum + count),
            index?.toDecimalString() ?? '',
            visits[i],
            sold[i],
            revenue[i].toDecimalString(),
            costOfGoods[i].toDecimalString(),
            writeOffs[i].toDecimalString(),
            wages[i].toDecimalString(),
            rent[i].toDecimalString(),
            overheads[i].toDecimalString(),
            ...missed[i],
            store.unitsOnHand,
            cash.toDecimalString(),
            store.reputation.toDecimalString(),
          ].join(','),
        );
      }
    }
  }

  // A failing company's stores stop selling as its cash runs out: that is
  // how it dies, not a fault.
  for (final summary in stores) {
    if (liquidated.containsKey(summary.company)) {
      summary.flags.remove('no sales');
    }
  }
  final flags = <String>{};
  // A shop alone in its trade has all of it, which is no one dominating.
  final companiesIn = <(int, int), int>{};
  for (final (market, channel, _) in finalCompanyVisits.keys) {
    companiesIn[(market, channel)] = (companiesIn[(market, channel)] ?? 0) + 1;
  }
  for (final MapEntry(key: (market, channel, _), value: visits)
      in finalCompanyVisits.entries) {
    if (companiesIn[(market, channel)]! > 1 &&
        _rate(visits, finalChannelVisits[(market, channel)]!) > dominantShare) {
      flags.add('one company dominates ${content.markets[market].key}');
    }
  }
  final markets = [
    for (final market in content.markets)
      (
        households: world.cohorts
            .where((c) => c.market == market.id)
            .fold(0, (sum, c) => sum + c.weight),
        stores: world.stores
            .where((s) => s.market == market.id && s.status == StoreStatus.open)
            .length,
        opened: world.stores
            .skip(content.stores.length)
            .where((s) => s.market == market.id)
            .length,
      ),
  ];
  for (final (i, market) in markets.indexed) {
    if (market.stores < 2) {
      flags.add('fewer than two stores in ${content.markets[i].key}');
    }
  }
  if (writeCsv) {
    final file = File('${job.out}/${job.bot}/seed-${job.seed}.csv');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(csv.toString());
  }
  return JobResult(
    job.bot,
    job.seed,
    job.days,
    [
      for (final company in world.companies)
        _companySummary(world, content, company.id, liquidated[company.id]),
    ],
    stores,
    flags,
    regimeDays,
    world.macro.priceIndex,
    years,
    markets,
    purchases,
    rescues,
  );
}

CompanySummary _companySummary(
  WorldState world,
  ContentDb content,
  CompanyId id,
  int? liquidated,
) {
  final company = world.companies[id.index];
  Money balance(AccountKind kind) => company.accounts[kind];
  final gross =
      -balance(AccountKind.revenue) -
      balance(AccountKind.costOfGoods) -
      balance(AccountKind.writeOffs);
  return CompanySummary(
    name: company.name,
    owner: world.persons[company.owner.index].name,
    isPlayer: company.owner == content.player,
    founded: company.founded.number - content.startDay.number,
    liquidated: liquidated,
    revenue: -balance(AccountKind.revenue),
    grossProfit: gross,
    netProfit:
        gross -
        balance(AccountKind.rent) -
        balance(AccountKind.overheads) -
        balance(AccountKind.interest) -
        balance(AccountKind.openingCosts) -
        balance(AccountKind.debtRelief) -
        balance(AccountKind.wages) -
        balance(AccountKind.salaries) -
        balance(AccountKind.research) -
        balance(AccountKind.marketing) -
        balance(AccountKind.taxes) -
        balance(AccountKind.disposals),
    dividends: balance(AccountKind.dividends),
    cash: balance(AccountKind.cash),
  );
}

/// The mean of shelf price over reference price, scaled to today's price
/// level, across listed products; null if nothing is listed.
Fx? _priceIndex(ContentDb content, List<Money?> prices, Fx priceLevel) {
  var sum = Fx.zero;
  var listed = 0;
  for (final product in content.products) {
    final price = prices[product.id.index];
    if (price == null) continue;
    final reference = product.referencePrice.times(priceLevel);
    sum += Fx.raw(mulDivRound(price.cents, Fx.scale, reference.cents));
    listed++;
  }
  return listed == 0 ? null : Fx.raw(sum.raw ~/ listed);
}

/// One row per run and company.
String companiesCsv(List<JobResult> results) {
  final csv = StringBuffer(
    'player,seed,company,owner,founded,liquidated,revenue,gross_profit,'
    'net_profit,net_profit_per_year,dividends,cash\n',
  );
  for (final result in results) {
    for (final company in result.companies) {
      csv.writeln(
        [
          result.bot,
          result.seed,
          _csvText(company.name),
          _csvText(company.owner),
          company.founded,
          company.liquidated ?? '',
          company.revenue.toDecimalString(),
          company.grossProfit.toDecimalString(),
          company.netProfit.toDecimalString(),
          company.netProfitPerYear(result.days).toDecimalString(),
          company.dividends.toDecimalString(),
          company.cash.toDecimalString(),
        ].join(','),
      );
    }
  }
  return csv.toString();
}

/// One row per run and store.
String storesCsv(List<JobResult> results) {
  final csv = StringBuffer(
    'player,seed,store,format,company,opened,closed,revenue,write_off_rate,'
    'stockout_rate,final_share,final_price_index,flags\n',
  );
  for (final result in results) {
    for (final store in result.stores) {
      csv.writeln(
        [
          result.bot,
          result.seed,
          _csvText(store.name),
          store.format,
          _csvText(result.companies[store.company.index].name),
          store.opened,
          store.closed ?? '',
          store.revenue.toDecimalString(),
          store.writeOffRate.toDecimalString(),
          store.stockoutRate.toDecimalString(),
          store.finalShare.toDecimalString(),
          store.finalPriceIndex.toDecimalString(),
          store.flags.join(' / '),
        ].join(','),
      );
    }
  }
  return csv.toString();
}

/// Per player bot: how the scenario's companies fared across seeds, how
/// much entry and failure there was, and the verdict on the prototype's
/// first two success criteria.
String summaryText(ContentDb content, List<JobResult> results) {
  final text = StringBuffer();
  final bots = {for (final result in results) result.bot};
  var flagged = 0;
  final playerSucceeded = <String>[];
  for (final bot in bots) {
    final runs = results.where((r) => r.bot == bot).toList();
    text
      ..writeln('\nplayer: $bot (${runs.length} seeds)')
      ..writeln(
        '  ${'company'.padRight(20)}${'city'.padRight(13)}${'net/yr'.padLeft(9)}'
        '${'min'.padLeft(9)}${'max'.padLeft(9)}${'failed'.padLeft(8)}'
        '${'share'.padLeft(7)}${'price'.padLeft(8)}${'stockout'.padLeft(10)}'
        '${'spoiled'.padLeft(9)}  flags',
      );
    for (var i = 0; i < content.companies.length; i++) {
      final companies = [for (final run in runs) run.companies[i]];
      final profits = [
        for (final run in runs) run.companies[i].netProfitPerYear(run.days),
      ]..sort((a, b) => a.cents - b.cents);
      final failed = companies.where((c) => c.liquidated != null).length;
      // The scenario's first store for this company.
      final store = content.stores.indexWhere((s) => s.company.index == i);
      final stores = [for (final run in runs) run.stores[store]];
      final flags = <String, int>{};
      for (final summary in stores) {
        for (final flag in summary.flags) {
          flags[flag] = (flags[flag] ?? 0) + 1;
        }
      }
      if (companies.first.isPlayer &&
          bot != 'idle' &&
          failed == 0 &&
          profits.first > Money.zero) {
        playerSucceeded.add(bot);
      }
      final city = content
          .markets[content.sites[content.stores[store].site.index].market.index]
          .key;
      text.writeln(
        '  ${companies.first.name.padRight(20)}'
        '${city.padRight(13)}'
        '${_money(_mean(profits)).padLeft(9)}'
        '${_money(profits.first).padLeft(9)}'
        '${_money(profits.last).padLeft(9)}'
        '${'$failed'.padLeft(8)}'
        '${_percent(_meanFx(stores, (s) => s.finalShare)).padLeft(7)}'
        '${_meanFx(stores, (s) => s.finalPriceIndex).toDecimalString().padLeft(8)}'
        '${_percent(_meanFx(stores, (s) => s.stockoutRate)).padLeft(10)}'
        '${_percent(_meanFx(stores, (s) => s.writeOffRate)).padLeft(9)}'
        '  ${[for (final e in flags.entries) '${e.key} ×${e.value}'].join(', ')}',
      );
    }
    final entrants = [
      for (final run in runs)
        for (final company in run.companies.skip(content.companies.length))
          (run, company),
    ];
    final opened = [
      for (final run in runs) run.stores.length - content.stores.length,
    ].fold(0, (a, b) => a + b);
    final failures = [
      for (final run in runs)
        run.companies.where((c) => c.liquidated != null).length,
    ].fold(0, (a, b) => a + b);
    final entrantProfits = [
      for (final (run, company) in entrants)
        if (company.lifetime(run.days) >= 365)
          company.netProfitPerYear(run.days),
    ];
    final enlarged = [
      for (final run in runs)
        for (final store in run.stores) store.enlargements,
    ].fold(0, (a, b) => a + b);
    final purchases = runs.fold(0, (sum, run) => sum + run.purchases);
    final rescues = runs.fold(0, (sum, run) => sum + run.rescues);
    text.writeln(
      '  entry: $opened stores opened, ${entrants.length} companies founded, '
      '$failures liquidations, $enlarged enlargements, $purchases stores '
      'bought ($rescues from liquidations)'
      '${entrantProfits.isEmpty ? '' : '; entrants net/yr ${_money(_mean(entrantProfits))}'}',
    );
    final cycle = [
      for (final regime in content.macro.regimes)
        runs.fold(0, (sum, run) => sum + run.regimeDays[regime.id.index]),
    ];
    final allDays = cycle.fold(0, (a, b) => a + b);
    final prices = Fx.raw(
      runs.fold(0, (sum, run) => sum + run.priceIndex.raw) ~/ runs.length,
    );
    text.writeln(
      '  economy: '
      '${[for (final regime in content.macro.regimes) '${regime.key} ${_percent(_rate(cycle[regime.id.index], allDays))}'].join(', ')}'
      '; prices ×${prices.toDecimalString()} by the end',
    );
    text.write(_evolutionText(runs));
    if (content.markets.length > 1) {
      text.writeln('  by city    households  stores  opened');
      for (final market in content.markets) {
        final records = [for (final run in runs) run.markets[market.id.index]];
        int mean10(int Function(MarketRecord) of) =>
            records.fold(0, (sum, r) => sum + of(r)) * 10 ~/ records.length;
        final stores = mean10((r) => r.stores);
        final opened = mean10((r) => r.opened);
        text.writeln(
          '  ${market.key.padRight(12)}'
          '${'${mean10((r) => r.households) ~/ 10}'.padLeft(9)}'
          '${'${stores ~/ 10}.${stores % 10}'.padLeft(8)}'
          '${'${opened ~/ 10}.${opened % 10}'.padLeft(8)}',
        );
      }
    }
    final marketFlags = <String, int>{};
    for (final run in runs) {
      for (final store in run.stores) {
        if (store.flags.isNotEmpty) flagged++;
      }
      for (final flag in run.flags) {
        marketFlags[flag] = (marketFlags[flag] ?? 0) + 1;
        flagged++;
      }
    }
    if (marketFlags.isNotEmpty) {
      text.writeln(
        '  market: '
        '${[for (final e in marketFlags.entries) '${e.key} ×${e.value}'].join(', ')}',
      );
    }
  }
  text
    ..writeln()
    ..writeln(
      'Criterion 1, stability: '
      '${flagged == 0 ? 'nothing flagged' : '$flagged problems flagged'}',
    )
    ..writeln(
      'Criterion 2, strategies with a net profit and no bankruptcy in every '
      'seed: ${playerSucceeded.isEmpty ? 'none' : playerSucceeded.join(', ')}',
    );
  return text.toString();
}

Money _perYear(Money total, int days) =>
    Money(total.cents * 365 ~/ (days < 1 ? 1 : days));

Money _mean(List<Money> values) => values.isEmpty
    ? Money.zero
    : Money(values.fold(0, (sum, v) => sum + v.cents) ~/ values.length);

Fx _meanFx(List<StoreSummary> stores, Fx Function(StoreSummary) of) =>
    stores.isEmpty
    ? Fx.zero
    : Fx.raw(stores.fold(0, (sum, s) => sum + of(s).raw) ~/ stores.length);

Fx _rate(int part, int whole) =>
    whole == 0 ? Fx.zero : Fx.raw(mulDivRound(part, Fx.scale, whole));

String _percent(Fx share) => '${(share.raw + 50) ~/ 100}%';

String _money(Money amount) => '${amount.cents ~/ 100}';

String _csvText(String text) =>
    text.contains(',') ? '"${text.replaceAll('"', '""')}"' : text;

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) {
      throw ArgumentError('Expected --option value, got ${args[i]}');
    }
    options[args[i].substring(2)] = args[i + 1];
  }
  return options;
}

/// Seeds as a range (`1-20`) or a list (`1,5,9`).
List<int> _parseSeeds(String text) {
  if (text.contains('-')) {
    final [first, last] = text.split('-').map(int.parse).toList();
    return [for (var seed = first; seed <= last; seed++) seed];
  }
  return text.split(',').map(int.parse).toList();
}

/// One row per run and year: households, stores, prices, and how the player
/// did.
String evolutionCsv(List<JobResult> results) {
  final csv = StringBuffer(
    'player,seed,year,households,stores,price_index,player_profit,'
    'player_share,recession_days,player_stores,player_debt,player_worth\n',
  );
  for (final result in results) {
    for (final (i, year) in result.years.indexed) {
      csv.writeln(
        [
          result.bot,
          result.seed,
          i + 1,
          year.households,
          year.stores,
          year.priceIndex.toDecimalString(),
          year.playerProfit.toDecimalString(),
          year.playerShare.toDecimalString(),
          year.recessionDays,
          year.playerStores,
          year.playerDebt.toDecimalString(),
          year.playerWorth.toDecimalString(),
        ].join(','),
      );
    }
  }
  return csv.toString();
}

/// Averages across [runs] for a few years of the game: how the market grew
/// and how the player fared.
String _evolutionText(List<JobResult> runs) {
  final length = runs
      .map((run) => run.years.length)
      .reduce((a, b) => a < b ? a : b);
  if (length == 0) return '';
  final shown = [
    for (final year in const [1, 2, 3, 5, 10, 15, 20, 25, 30, 35, 40])
      if (year <= length) year,
    if (!const [1, 2, 3, 5, 10, 15, 20, 25, 30, 35, 40].contains(length))
      length,
  ];
  final text = StringBuffer(
    '  by year   households  stores  prices  player net/yr  share  recession'
    '  yours      debt     worth\n',
  );
  for (final year in shown) {
    final records = [for (final run in runs) run.years[year - 1]];
    final households =
        records.fold(0, (sum, r) => sum + r.households) ~/ records.length;
    final stores =
        records.fold(0, (sum, r) => sum + r.stores) * 10 ~/ records.length;
    final prices = Fx.raw(
      records.fold(0, (sum, r) => sum + r.priceIndex.raw) ~/ records.length,
    );
    final profit = _mean([for (final r in records) r.playerProfit]);
    final share = Fx.raw(
      records.fold(0, (sum, r) => sum + r.playerShare.raw) ~/ records.length,
    );
    final recession =
        records.fold(0, (sum, r) => sum + r.recessionDays) ~/ records.length;
    final yours =
        records.fold(0, (sum, r) => sum + r.playerStores) *
        10 ~/
        records.length;
    final debt = _mean([for (final r in records) r.playerDebt]);
    final worth = _mean([for (final r in records) r.playerWorth]);
    text.writeln(
      '  ${'$year'.padLeft(7)}'
      '${'$households'.padLeft(13)}'
      '${'${stores ~/ 10}.${stores % 10}'.padLeft(8)}'
      '${'×${prices.toDecimalString()}'.padLeft(8)}'
      '${_money(profit).padLeft(15)}'
      '${_percent(share).padLeft(7)}'
      '${'${recession}d'.padLeft(11)}'
      '${'${yours ~/ 10}.${yours % 10}'.padLeft(7)}'
      '${_money(debt).padLeft(10)}'
      '${_money(worth).padLeft(10)}',
    );
  }
  return text.toString();
}

/// An owner keen to grow (`<strategy>+credit`, or `<strategy>+cash` without
/// the bank): runs its stores as [RetailPolicy] does but keeps the profit in
/// the company, and on the first of each month, once its latest store has
/// traded [intervalDays], makes the move that repays soonest, if within
/// the strategy's payback for a new site (as AI owners judge it) or four
/// years for a rival's store at the asking price and its present earnings. What the company lacks for it beyond its
/// cash cushion (a new store's starting capital, or the price), it borrows
/// over seven years, rounded up to a thousand, if [borrows] and the bank
/// lends that much on its earnings; it never guarantees a loan.
final class CreditOwner implements Policy {
  CreditOwner(this.strategy, {this.borrows = true, this.intervalDays = 120})
    : _retail = RetailPolicy(strategy),
      _entrepreneur = EntrepreneurPolicy(strategy);

  final StrategyDef strategy;
  final bool borrows;
  final int intervalDays;
  final RetailPolicy _retail;
  final EntrepreneurPolicy _entrepreneur;

  static const storeMonths = 48;

  @override
  List<Command> decide(Observation view, ContentDb content) {
    final commands = [
      for (final command in _retail.decide(view, content))
        if (command is! PayDividend) command,
    ];
    if (!view.today.isFirstOfMonth) return commands;
    final company = view.companies
        .where((company) => company.status == CompanyStatus.active)
        .firstOrNull;
    if (company == null || company.retainedEarnings <= Money.zero) {
      return commands;
    }
    var latest = company.founded.number;
    for (final store in company.stores) {
      final since = (store.acquiredOn ?? store.opensOn).number;
      if (since > latest) latest = since;
    }
    if (view.today.number - latest < intervalDays) return commands;
    final multiple = content.finance.earningsMultiple;

    // The best new site and the best rival store, by months to repay.
    SiteDef? site;
    var months = strategy.expansionPaybackMonths + 1;
    for (final id in view.vacantSites) {
      final candidate = content.sites[id.index];
      if (candidate.area < content.formats[strategy.format.index].minArea) {
        continue;
      }
      final payback = _entrepreneur.paybackMonths(view, content, candidate);
      if (payback != null && payback < months) {
        site = candidate;
        months = payback;
      }
    }
    ShelfView? store;
    var storePayback = storeMonths + 1;
    for (final shelf in view.shelves) {
      if (shelf.status == StoreStatus.closed ||
          shelf.format != strategy.format ||
          view.companyOwners[shelf.company.index] == view.actor) {
        continue;
      }
      final value = view.valuations[shelf.id.index];
      if (value == null || value.earnings <= Money.zero) continue;
      final payback = value.price.cents * 12 ~/ value.earnings.cents;
      if (payback < storePayback) {
        store = shelf;
        storePayback = payback;
      }
    }
    final buying = store != null && (site == null || storePayback <= months);
    if (!buying && site == null) return commands;

    final value = buying ? view.valuations[store.id.index]! : null;
    final cost = buying
        ? value!.price
        : _entrepreneur.startingCapital(view, content, site!);
    final free =
        company.cash - company.committed - cashCushion(view, content, company);
    final lacking = cost - free;
    final thousand = Money.parse('1000.00').cents;
    final borrow = lacking <= Money.zero
        ? Money.zero
        : Money((lacking.cents + thousand - 1) ~/ thousand * thousand);
    if (borrow > Money.zero) {
      final room =
          (view.companyCredits[company.id.index] ?? Money.zero) +
          (buying ? value!.earnings.times(multiple) : Money.zero);
      if (!borrows || borrow > room) return commands;
    }
    final term = borrow == Money.zero ? 0 : 84;
    return [
      ...commands,
      if (buying)
        BuyStore(
          view.actor,
          store: store.id,
          company: company.id,
          borrow: borrow,
          termMonths: term,
        )
      else
        OpenStore(
          view.actor,
          site: site!.id,
          name: site.name,
          company: company.id,
          format: strategy.format,
          borrow: borrow,
          termMonths: term,
        ),
    ];
  }
}

/// The owner's own calls, moving money between the owner and the company,
/// for a player who leaves the rest, enlarging included, to a manager.
final class OwnerDecisions implements Policy {
  const OwnerDecisions(this.policy, {this.dividends = true});

  final Policy policy;

  /// Whether the owner takes dividends, or leaves them to a director.
  final bool dividends;

  @override
  List<Command> decide(Observation view, ContentDb content) => [
    for (final command in policy.decide(view, content))
      if ((dividends && command is PayDividend) || command is InjectCapital)
        command,
  ];
}
