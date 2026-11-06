import 'package:engine/engine.dart';

import 'format.dart';
import 'l10n.dart';

/// What [command] does, in a few words, for the list of pending changes and
/// for refusals.
String describeCommand(Command command, ContentDb content, Observation view) {
  String store(StoreId id) => view.shelves[id.index].name;
  String product(ProductId id) => content.products[id.index].name;
  String company(CompanyId id) => view.companyNames[id.index];
  return switch (command) {
    SetPrice(store: final s, product: final p, :final price) => tr(
      'commands.setPrice',
      {'product': product(p), 'price': money(price), 'store': store(s)},
    ),
    PlaceOrder(store: final s, :final supplier, :final lines) =>
      tr('commands.order', {
        'units': lines.fold<int>(0, (sum, line) => sum + line.quantity),
        'supplier': content.suppliers[supplier.index].name,
        'store': store(s),
      }),
    ListProduct(store: final s, product: final p, :final price) => tr(
      'commands.list',
      {'product': product(p), 'price': money(price), 'store': store(s)},
    ),
    DelistProduct(store: final s, product: final p) => tr('commands.delist', {
      'product': product(p),
      'store': store(s),
    }),
    InjectCapital(company: final c, :final amount) => tr('commands.inject', {
      'amount': money(amount),
      'company': company(c),
    }),
    PayDividend(company: final c, :final amount) => tr('commands.dividend', {
      'amount': money(amount),
      'company': company(c),
    }),
    TakeLoan(
      company: final c,
      :final amount,
      :final termMonths,
      :final guarantee,
    ) =>
      tr('commands.borrow', {
        'amount': money(amount),
        'term': termName(termMonths),
        'company': company(c),
        'guarantee': guarantee ? tr('commands.guaranteed') : '',
      }),
    RepayLoan(:final loan, :final amount) => tr('commands.repay', {
      'amount': money(amount),
      'loan': loan,
    }),
    OpenStore(
      :final site,
      :final name,
      :final format,
      :final borrow,
      :final termMonths,
    ) =>
      tr('commands.open', {
        'name': name,
        'format': aFormat(content.formats[format.index]),
        'site': content.sites[site.index].name,
        'loan': _loan(borrow, termMonths),
      }),
    WakeNeighbourhood() => '',
    SetMarketing(store: final s, :final share) =>
      share == Fx.zero
          ? tr('commands.stopMarketing', {'store': store(s)})
          : tr('commands.marketing', {
              'share': percent(share),
              'store': store(s),
            }),
    ConvertStore(store: final s, :final format) => tr('commands.convert', {
      'store': store(s),
      'format': aFormat(content.formats[format.index]),
    }),
    CloseStore(store: final s) => tr('commands.close', {'store': store(s)}),
    SetStaffing(store: final s, :final staff) => tr('commands.staff', {
      'store': store(s),
      'slots': [
        for (final slot in DaySlot.values)
          '${staff[slot.index]} ${slotName(slot).toLowerCase()}',
      ].join(', '),
    }),
    HireManager(store: final s, :final grade, :final strategy, :final duties) =>
      tr('commands.hireManager', {
        'manager': aManager(content.managers.grades[grade.index]),
        'store': store(s),
        'strategy': content.strategies[strategy.index].name.toLowerCase(),
        'duties': [
          for (final duty in ManagerDuty.values)
            if (duties[duty.index]) dutyName(duty),
        ].join(', '),
      }),
    FireManager(store: final s) => tr('commands.fireManager', {
      'store': store(s),
    }),
    HireDirector(
      company: final c,
      :final grade,
      :final growth,
      :final borrows,
    ) =>
      tr('commands.hireDirector', {
        'director': aDirector(content.directors!.grades[grade.index]),
        'company': company(c),
        'growth': growthName(growth),
        'borrows': borrows ? tr('commands.borrowing') : '',
      }),
    FireDirector(company: final c) => tr('commands.fireDirector', {
      'company': company(c),
    }),
    RenameStore(store: final s, :final name) => tr('commands.renameStore', {
      'store': store(s),
      'name': name,
    }),
    RenameCompany(company: final c, :final name) => tr(
      'commands.renameCompany',
      {'company': company(c), 'name': name},
    ),
    SetCushion(company: final c, :final days) => tr('commands.cushion', {
      'length': cushionLength(days),
      'company': company(c),
    }),
    ExpandStore(store: final s) => tr('commands.expand', {
      'store': store(s),
      'area': content.expansion.stepArea,
    }),
    BuyStore(
      store: final s,
      company: final c,
      :final borrow,
      :final termMonths,
    ) =>
      tr('commands.buyStore', {
        'store': store(s),
        'seller': company(view.shelves[s.index].company),
        'buyer': company(c),
        'price': _price(view.valuations[s.index]?.price),
        'loan': _loan(borrow, termMonths),
      }),
    SellStore(store: final s) => tr('commands.sellStore', {
      'store': store(s),
      'price': _price(view.valuations[s.index]?.price),
    }),
    BuyCompany(company: final c, :final borrow, :final termMonths) => tr(
      'commands.buyCompany',
      {
        'company': company(c),
        'price': _price(view.companyPrices[c.index]),
        'loan': borrow == Money.zero
            ? ''
            : tr('commands.boughtOnLoan', {
                'amount': money(borrow, cents: false),
                'term': termName(termMonths),
              }),
      },
    ),
    BuyResearch(:final market, :final tier) => tr('commands.buyResearch', {
      'study': aStudy(content.researchTiers[tier.index]),
      'market': content.markets[market.index].name,
    }),
  };
}

/// ", borrowing … over …", if anything is borrowed.
String _loan(Money borrow, int months) => borrow == Money.zero
    ? ''
    : tr('commands.loan', {
        'amount': money(borrow, cents: false),
        'term': termName(months),
      });

/// ", at its asking price of …" today, if it has one.
String _price(Money? price) => price == null
    ? ''
    : tr('commands.atAskingPrice', {'price': money(price, cents: false)});
