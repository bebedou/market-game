import 'package:engine/engine.dart';

import 'controller.dart';
import 'format.dart';
import 'l10n.dart';

/// What kind of business it is: a trade's shops, a kind of plant, or a
/// software product.
enum BusinessKind { trade, works, software }

/// A business's month: what it sold and made, and how many shops or plants
/// it had.
typedef BusinessMonth = ({Day start, Money sales, Money profit, int units});

/// One business of a company, the owner's design of 2026-11-17: a trade with
/// every shop of it, whatever the country and however the game works them
/// out; a kind of plant with every plant of it; or the company's software.
final class Business {
  const Business({
    required this.company,
    required this.kind,
    required this.key,
    required this.name,
    required this.months,
    this.format,
    this.factoryKind,
    this.stores = const [],
    this.blocks = const [],
    this.districtShops = const [],
    this.factories = const [],
    this.software,
  });

  final CompanyView company;
  final BusinessKind kind;

  /// Its trade's key, its kind of plant's, or `software`.
  final String key;
  final String name;

  /// Its last full months, oldest first, up to twelve.
  final List<BusinessMonth> months;

  /// A kind of shop of the trade, whose colour marks it.
  final FormatId? format;
  final FactoryKindId? factoryKind;

  /// Its shops the player or a director runs one by one, open or being
  /// fitted out.
  final List<StoreView> stores;

  /// Its shops across countries, by country.
  final List<(NationalCountryView, CompanyBlockView)> blocks;

  /// Its shops in districts the game doesn't play in full.
  final List<(DistrictView, DistrictShop)> districtShops;

  /// Its plants, running or being built.
  final List<FactoryView> factories;
  final SoftwareView? software;

  /// Its shops, or its plants.
  int get units => switch (kind) {
    BusinessKind.trade =>
      stores.length +
          districtShops.length +
          blocks.fold(0, (sum, entry) => sum + entry.$2.stores),
    BusinessKind.works => factories.length,
    BusinessKind.software => 0,
  };

  /// The countries its shops or plants are in.
  Set<CountryId> countries(ContentDb content) => {
    for (final store in stores) content.countryOf(store.market),
    for (final (country, _) in blocks) ?country.country,
    for (final (district, _) in districtShops) district.country,
    for (final factory in factories) factory.country,
  };
}

/// [format]'s trade: one business for every kind of shop of it.
String tradeOf(FormatDef format) => tradeKey(format);

/// The name of the business keyed [key] (see `tradeKey`, `plantsKey`): its
/// trade's, its kind of plant's, or software.
String businessName(ContentDb content, String key) {
  if (key == softwareBusiness) return tr('business.software');
  for (final kind in content.factories?.kinds ?? const <FactoryKindDef>[]) {
    if (plantsKey(kind) == key) return kind.name;
  }
  return tradeName(key, [
    for (final format in content.formats)
      if (tradeKey(format) == key) format,
  ]);
}

/// [business]'s key in its boss's brief (see `Director.goals`).
String briefKey(ContentDb content, Business business) =>
    switch (business.kind) {
      BusinessKind.trade => business.key,
      BusinessKind.works => plantsKey(
        content.factories!.kinds[business.factoryKind!.index],
      ),
      BusinessKind.software => softwareBusiness,
    };

/// A trade's name, its kinds of shop being [formats].
String tradeName(String key, List<FormatDef> formats) =>
    trMaybe('business.sectors.$key') ??
    (formats.isEmpty ? key : formats.first.name);

/// Months from [from]'s month to [to]'s.
int _monthsBetween(Day from, Day to) =>
    (to.date.year - from.date.year) * 12 + to.date.month - from.date.month;

/// [company]'s businesses: its trades, in the order their kinds of shop
/// come, then its kinds of plant, then its software. Its shops across
/// countries are read from [national], worked out once by the caller.
List<Business> businessesOf(
  SimulationController game,
  CompanyView company,
  List<NationalCountryView> national,
) {
  final content = game.content;
  final view = game.view;
  final current = ReportPeriod.month.startOf(game.today);
  final reports = [
    for (final report in game.reports(ReportPeriod.month, company: company.id))
      if (report.start != current) report,
  ];
  final recent = reports.length > 12
      ? reports.sublist(reports.length - 12)
      : reports;
  String shelfTrade(StoreId store) =>
      tradeOf(content.formats[view.shelves[store.index].format.index]);

  final businesses = <Business>[];
  // Trades, in the order of their kinds of shop.
  final seenTrades = <String>{};
  for (final format in content.formats) {
    final key = tradeOf(format);
    if (!seenTrades.add(key)) continue;
    final formats = [
      for (final other in content.formats)
        if (tradeOf(other) == key) other,
    ];
    final ids = {for (final f in formats) f.id};
    final stores = [
      for (final store in company.stores)
        if (store.status != StoreStatus.closed && ids.contains(store.format))
          store,
    ];
    final blocks = [
      for (final country in national)
        for (final block in country.blocks)
          if (block.company == company.id &&
              block.stores > 0 &&
              ids.contains(block.format))
            (country, block),
    ];
    final districtShops = [
      for (final district in view.districts)
        for (final shop in district.shops)
          if (shop.company == company.id && ids.contains(shop.format))
            (district, shop),
    ];
    final months = <BusinessMonth>[];
    for (final report in recent) {
      var sales = Money.zero;
      var profit = Money.zero;
      var units = 0;
      for (final part in report.stores) {
        if (shelfTrade(part.store) != key) continue;
        sales += part.totalRevenue;
        profit += part.profit;
        if (part.totalRevenue > Money.zero) units++;
      }
      for (final (_, block) in blocks) {
        for (final month in block.months) {
          if (month.start != report.start) continue;
          sales += month.sales;
          profit += month.profit;
          units += month.stores;
        }
      }
      final back = _monthsBetween(report.start, current);
      for (final (_, shop) in districtShops) {
        final at = shop.sales.length - back;
        if (at < 0 || at >= shop.sales.length) continue;
        sales += shop.sales[at];
        profit += shop.profits[at];
        units++;
      }
      months.add((
        start: report.start,
        sales: sales,
        profit: profit,
        units: units,
      ));
    }
    final hasAny =
        stores.isNotEmpty ||
        blocks.isNotEmpty ||
        districtShops.isNotEmpty ||
        months.any((month) => month.sales > Money.zero);
    if (!hasAny) continue;
    businesses.add(
      Business(
        company: company,
        kind: BusinessKind.trade,
        key: key,
        name: tradeName(key, formats),
        months: _trimmed(months),
        format:
            (stores.firstOrNull?.format ??
            blocks.firstOrNull?.$2.format ??
            districtShops.firstOrNull?.$2.format ??
            format.id),
        stores: stores,
        blocks: blocks,
        districtShops: districtShops,
      ),
    );
  }
  // Kinds of plant.
  if (content.factories case final factories?) {
    for (final kind in factories.kinds) {
      final plants = [
        for (final factory in company.factories)
          if (factory.kind == kind.id && factory.status != FactoryStatus.closed)
            factory,
      ];
      if (plants.isEmpty) continue;
      final ids = {for (final plant in plants) plant.id};
      final months = [
        for (final report in recent)
          () {
            var sales = Money.zero;
            var profit = Money.zero;
            var units = 0;
            for (final part in report.factories) {
              if (!ids.contains(part.factory)) continue;
              sales += part.totalOwnGoods + part.totalRivalSales;
              profit += part.profit;
              units++;
            }
            return (
              start: report.start,
              sales: sales,
              profit: profit,
              units: units,
            );
          }(),
      ];
      businesses.add(
        Business(
          company: company,
          kind: BusinessKind.works,
          key: kind.key,
          name: kind.name,
          months: _trimmed(months),
          factoryKind: kind.id,
          factories: plants,
        ),
      );
    }
  }

  // Its software while it runs: alone, the company's months are its own;
  // beside other businesses, its own months, each read as the month turned.
  if (company.software case final software? when software.running) {
    final alone = businesses.isEmpty;
    businesses.add(
      Business(
        company: company,
        kind: BusinessKind.software,
        key: 'software',
        name: software.name,
        months: _trimmed([
          if (alone)
            for (final report in recent)
              (
                start: report.start,
                sales: -report.flow(AccountKind.revenue),
                profit: report.profit,
                units: 0,
              )
          else
            for (final month in software.history)
              (
                start: ReportPeriod.month.startOf(Day(month.day.number - 1)),
                sales: month.revenue,
                profit: month.profit,
                units: 0,
              ),
        ]),
        software: software,
      ),
    );
  }
  return businesses;
}

/// [months] from the first with any sales or profit.
List<BusinessMonth> _trimmed(List<BusinessMonth> months) {
  final first = months.indexWhere(
    (month) => month.sales != Money.zero || month.profit != Money.zero,
  );
  return first < 0 ? const [] : List.unmodifiable(months.sublist(first));
}

/// How a page reads: going well, worth watching, or in trouble.
enum Tone { good, watch, trouble }

/// A page's verdict: its tone and why, in a sentence.
typedef Verdict = ({Tone tone, String text});

/// The change of the last three of [values] on the three before, in whole
/// percent; null with less than six, or nothing before.
int? quarterChange(List<Money> values) {
  if (values.length < 6) return null;
  Money sum(int from, int to) {
    var total = Money.zero;
    for (var i = from; i < to; i++) {
      total += values[i];
    }
    return total;
  }

  final n = values.length;
  final now = sum(n - 3, n);
  final before = sum(n - 6, n - 3);
  if (before <= Money.zero) return null;
  return ((now - before).cents * 100 / before.cents).round();
}

/// The total of the last three of [values].
Money lastQuarter(List<Money> values) {
  var total = Money.zero;
  for (var i = values.length - 3; i < values.length; i++) {
    if (i >= 0) total += values[i];
  }
  return total;
}

/// "+6%", "−4%".
String signedPercent(int change) =>
    change > 0 ? '+${percentOf(change)}' : percentOf(change);

/// [business]'s verdict, from its last months.
Verdict businessVerdict(Business business) {
  final months = business.months;
  if (months.length < 3) {
    return (tone: Tone.watch, text: tr('verdicts.young'));
  }
  final sales = [for (final month in months) month.sales];
  final profit = lastQuarter([for (final month in months) month.profit]);
  if (profit.isNegative) {
    return (
      tone: Tone.trouble,
      text: tr('verdicts.losing', {'amount': compactMoney(-profit)}),
    );
  }
  final change = quarterChange(sales);
  if (change == null) {
    return (tone: Tone.good, text: tr('verdicts.earning'));
  }
  if (change < -5) {
    return (
      tone: Tone.trouble,
      text: tr('verdicts.shrinking', {'change': signedPercent(change)}),
    );
  }
  if (business.kind == BusinessKind.trade) {
    final perShop = [
      for (final month in months)
        month.units == 0 ? Money.zero : Money(month.sales.cents ~/ month.units),
    ];
    final shopChange = quarterChange(perShop);
    if (change > 0 && shopChange != null && shopChange < -3) {
      return (
        tone: Tone.watch,
        text: tr('verdicts.perShopFalling', {
          'change': signedPercent(change),
          'shop': signedPercent(shopChange),
        }),
      );
    }
  }
  if (change < 2) {
    return (
      tone: Tone.watch,
      text: tr('verdicts.flat', {'change': signedPercent(change)}),
    );
  }
  return (
    tone: Tone.good,
    text: tr('verdicts.growing', {'change': signedPercent(change)}),
  );
}

/// [company]'s verdict from its [profits] by month, oldest first, and its
/// [businesses]' own, in its boss's words if it has one: [boss].
Verdict companyVerdict(
  List<Money> profits,
  List<Business> businesses, {
  String? boss,
}) {
  Verdict said(Tone tone, String text) => (
    tone: tone,
    text: boss == null
        ? text
        : tr('verdicts.bossSays', {'boss': boss, 'text': text}),
  );
  if (profits.length < 3) return said(Tone.watch, tr('verdicts.young'));
  final readings = [
    for (final business in businesses) (business, businessVerdict(business)),
  ];
  final profit = lastQuarter(profits);
  if (profit.isNegative) {
    return said(
      Tone.trouble,
      tr('verdicts.losing', {'amount': compactMoney(-profit)}),
    );
  }
  final troubled = readings
      .where((reading) => reading.$2.tone == Tone.trouble)
      .firstOrNull;
  if (troubled != null) {
    return said(
      Tone.watch,
      tr('verdicts.watchBusiness', {'business': troubled.$1.name}),
    );
  }
  final change = quarterChange(profits);
  if (change == null) return said(Tone.good, tr('verdicts.earning'));
  if (change < -5) {
    return said(
      Tone.watch,
      tr('verdicts.profitDown', {'change': signedPercent(change)}),
    );
  }
  // The business that earned most lately carries it.
  (Business, Money)? best;
  for (final business in businesses) {
    final earned = lastQuarter([
      for (final month in business.months) month.profit,
    ]);
    if (best == null || earned > best.$2) best = (business, earned);
  }
  return said(
    Tone.good,
    businesses.length > 1 && best != null
        ? tr('verdicts.profitUpCarried', {
            'change': signedPercent(change),
            'business': best.$1.name,
          })
        : tr('verdicts.profitUp', {'change': signedPercent(change)}),
  );
}

/// A trade [business] country by country: its shops there now, and its
/// sales there in the last full month and the one before.
typedef CountryPart = ({
  CountryId country,
  int units,
  Money sales,
  Money before,
});

/// [business]'s [CountryPart]s, the biggest seller first.
List<CountryPart> byCountry(SimulationController game, Business business) {
  final content = game.content;
  final view = game.view;
  final units = <CountryId, int>{};
  final sales = <CountryId, Money>{};
  final before = <CountryId, Money>{};
  void add(CountryId country, {int count = 0, Money? now, Money? then}) {
    units[country] = (units[country] ?? 0) + count;
    sales[country] = (sales[country] ?? Money.zero) + (now ?? Money.zero);
    before[country] = (before[country] ?? Money.zero) + (then ?? Money.zero);
  }

  for (final store in business.stores) {
    add(content.countryOf(store.market), count: 1);
  }
  for (final (country, block) in business.blocks) {
    if (country.country case final id?) add(id, count: block.stores);
  }
  for (final (district, _) in business.districtShops) {
    add(district.country, count: 1);
  }
  final current = ReportPeriod.month.startOf(game.today);
  final full = [
    for (final report in game.reports(
      ReportPeriod.month,
      company: business.company.id,
    ))
      if (report.start != current) report,
  ];
  for (final (back, report) in [
    if (full.isNotEmpty) (1, full.last),
    if (full.length > 1) (2, full[full.length - 2]),
  ]) {
    void put(CountryId country, Money amount) =>
        back == 1 ? add(country, now: amount) : add(country, then: amount);
    for (final part in report.stores) {
      final shelf = view.shelves[part.store.index];
      if (tradeOf(content.formats[shelf.format.index]) != business.key) {
        continue;
      }
      put(content.countryOf(shelf.market), part.totalRevenue);
    }
    for (final (country, block) in business.blocks) {
      final id = country.country;
      if (id == null) continue;
      for (final month in block.months) {
        if (month.start == report.start) put(id, month.sales);
      }
    }
    for (final (district, shop) in business.districtShops) {
      final at = shop.sales.length - back;
      if (at >= 0) put(district.country, shop.sales[at]);
    }
  }
  final parts = [
    for (final country in units.keys)
      if ((units[country] ?? 0) > 0 || sales[country]! > Money.zero)
        (
          country: country,
          units: units[country] ?? 0,
          sales: sales[country] ?? Money.zero,
          before: before[country] ?? Money.zero,
        ),
  ];
  parts.sort((a, b) => b.sales.cents.compareTo(a.sales.cents));
  return parts;
}
