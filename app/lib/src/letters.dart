import 'package:engine/engine.dart';

import 'format.dart';
import 'l10n.dart';

/// A director's letter for one month: how the month before went, then what
/// they did, in their own words.
typedef Letter = ({Day month, List<String> paragraphs});

/// [company]'s letters, newest first: one for each month its directors did
/// something in, from its [months] reports, oldest first.
List<Letter> directorLetters(
  CompanyView company,
  List<PeriodReport> months,
  ContentDb content,
  Observation view,
) {
  final byMonth = <int, List<Memo>>{};
  for (final memo in company.memos) {
    (byMonth[ReportPeriod.month.startOf(memo.day).number] ??= []).add(memo);
  }
  PeriodReport? report(Day start) =>
      months.where((month) => month.start == start).firstOrNull;
  return [
    for (final MapEntry(key: start, value: memos)
        in byMonth.entries.toList().reversed)
      (
        month: Day(start),
        paragraphs: [
          ?_results(report, Day(start)),
          ..._sentences(memos, content, view),
        ],
      ),
  ];
}

/// How the month before [start] went, against the one before it; null
/// without its report.
String? _results(PeriodReport? Function(Day start) report, Day start) {
  final last = ReportPeriod.month.startOf(start + -1);
  final month = report(last);
  if (month == null) return null;
  final sales = -month.flow(AccountKind.revenue);
  final name = monthOnly(last);
  final previous = report(ReportPeriod.month.startOf(last + -1));
  var against = '';
  if (previous != null) {
    final before = -previous.flow(AccountKind.revenue);
    if (before > Money.zero) {
      final change = ((sales - before).cents * 100 / before.cents).round();
      against = tr(
        change == 0
            ? 'letters.levelWith'
            : change > 0
            ? 'letters.upOn'
            : 'letters.downOn',
        {'change': percentOf(change.abs()), 'month': monthOnly(previous.start)},
      );
    }
  }
  final profit = month.tradingProfit;
  return tr(
    profit.isNegative ? 'letters.resultsLost' : 'letters.resultsEarned',
    {
      'month': name,
      'sales': money(sales, cents: false),
      'against': against,
      'amount': money(profit.isNegative ? -profit : profit, cents: false),
    },
  );
}

/// [memos] as sentences, hires of one grade in a row as one.
List<String> _sentences(List<Memo> memos, ContentDb content, Observation view) {
  final sentences = <String>[];
  for (var i = 0; i < memos.length; i++) {
    final memo = memos[i];
    if (memo is ManagerHired) {
      final stores = [view.shelves[memo.store.index].name];
      while (i + 1 < memos.length) {
        final next = memos[i + 1];
        if (next is! ManagerHired || next.grade != memo.grade) break;
        stores.add(view.shelves[next.store.index].name);
        i++;
      }
      sentences.add(_hired(content, memo.grade, stores));
    } else {
      sentences.add(memoSentence(memo, content, view));
    }
  }
  return sentences;
}

/// What [memo] says, as one sentence in its director's words.
String memoSentence(Memo memo, ContentDb content, Observation view) {
  String store(StoreId id) => view.shelves[id.index].name;
  String site(SiteId id) {
    final place = content.sites[id.index];
    return content.markets.length == 1
        ? place.name
        : tr('common.siteIn', {
            'site': place.name,
            'market': content.markets[place.market.index].name,
          });
  }

  String amount(Money value) => money(value, cents: false);
  return switch (memo) {
    ManagerHired(store: final s, :final grade) => _hired(content, grade, [
      store(s),
    ]),
    StoreClosed(store: final s, :final sales, :final loss) =>
      sales > Money.zero
          ? tr('letters.closedWithSales', {
              'store': store(s),
              'loss': amount(loss),
              'sales': amount(sales),
            })
          : tr('letters.closed', {'store': store(s), 'loss': amount(loss)}),
    StoreEnlarged(store: final s, :final cost, :final borrowed) => tr(
      'letters.enlarged',
      {
        'store': store(s),
        'cost': amount(cost),
        'loan': _loan(borrowed, content),
      },
    ),
    StoreConverted(
      store: final s,
      :final format,
      :final cost,
      :final borrowed,
    ) =>
      tr('letters.converted', {
        'store': store(s),
        'format': aFormat(content.formats[format.index]),
        'cost': amount(cost),
        'loan': _loan(borrowed, content),
      }),
    StoreOpened(
      site: final at,
      :final format,
      :final cost,
      :final paybackMonths,
      :final borrowed,
    ) =>
      tr('letters.opened', {
        'format': aFormat(content.formats[format.index]),
        'site': site(at),
        'cost': amount(cost),
        'months': paybackMonths,
        'loan': _loan(borrowed, content),
      }),
    DistrictOpened(
      :final row,
      :final site,
      :final format,
      :final cost,
      :final paybackMonths,
      :final borrowed,
    ) =>
      tr('letters.openedInDistrict', {
        'shop':
            _districtShop(view, row, site) ??
            aFormat(content.formats[format.index]),
        'district': content.neighbourhoods[row].name,
        'cost': amount(cost),
        'months': paybackMonths,
        'loan': _loan(borrowed, content),
      }),
    DistrictBought(
      :final row,
      :final site,
      :final price,
      :final paybackMonths,
      :final borrowed,
    ) =>
      tr('letters.boughtInDistrict', {
        'shop': _districtShop(view, row, site) ?? tr('letters.aStore'),
        'district': content.neighbourhoods[row].name,
        'price': amount(price),
        'months': paybackMonths,
        'loan': _loan(borrowed, content),
      }),
    NationalOpened(
      :final region,
      :final format,
      :final count,
      :final cost,
      :final earns,
      :final paybackMonths,
      :final borrowed,
    ) =>
      tr('letters.openedNational', {
        'count': count,
        'format': count == 1
            ? aFormat(content.formats[format.index])
            : content.formats[format.index].name.toLowerCase(),
        'region': _regionNamed(content, region),
        'cost': amount(cost),
        'earns': amount(earns),
        'months': paybackMonths,
        'loan': _loan(borrowed, content),
      }),
    StoreBought(
      store: final s,
      :final price,
      :final paybackMonths,
      :final borrowed,
    ) =>
      tr('letters.bought', {
        'store': store(s),
        'price': amount(price),
        'months': paybackMonths,
        'loan': _loan(borrowed, content),
      }),
    ProfitPaid(amount: final paid) => tr('letters.paid', {
      'amount': amount(paid),
    }),
    ProfitKept(site: final at?, :final needed) => tr('letters.keptForStore', {
      'site': site(at),
      'amount': amount(needed),
    }),
    ProfitKept(store: final s, :final needed) => tr('letters.keptForWorks', {
      'target': s == null ? tr('letters.aStore') : store(s),
      'amount': amount(needed),
    }),
  };
}

/// The name of the shop on [site] of the district run by formula in [row],
/// while it sleeps.
String? _districtShop(Observation view, int row, int site) {
  for (final district in view.districts) {
    if (district.row != row) continue;
    for (final shop in district.shops) {
      if (shop.site == site) return shop.name;
    }
  }
  return null;
}

/// The name of the region the national table keys [key].
String _regionNamed(ContentDb content, String key) {
  for (final country in content.national?.countries ?? const []) {
    for (final region in country.regions) {
      if (region.key == key) return region.name;
    }
  }
  return key;
}

/// What a director says of what they [borrowed] for a store, if anything.
String _loan(Money borrowed, ContentDb content) => borrowed == Money.zero
    ? ''
    : tr('letters.loan', {
        'amount': money(borrowed, cents: false),
        'term': termName(content.finance.maxTermMonths),
      });

/// Hiring managers of [grade] for [stores].
String _hired(ContentDb content, ManagerGradeId grade, List<String> stores) {
  final hired = content.managers.grades[grade.index];
  return stores.length == 1
      ? tr('letters.hired', {
          'manager': aManager(hired),
          'store': stores.single,
        })
      : tr('letters.hiredMany', {
          'managers': managersOf(hired),
          'stores': listText(stores),
        });
}
