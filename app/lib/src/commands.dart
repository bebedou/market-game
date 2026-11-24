import 'package:engine/engine.dart';

import 'business.dart' show businessName;
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
    PayDividend(company: final c, :final amount) => switch (view.companies
        .where((each) => each.id == c)
        .firstOrNull
        ?.parent) {
      final parent? => tr('commands.dividendToParent', {
        'amount': money(amount),
        'company': company(c),
        'parent': company(parent),
      }),
      null => tr('commands.dividend', {
        'amount': money(amount),
        'company': company(c),
      }),
    },
    MoveBusiness(company: final c, :final business, :final to, :final name) =>
      to == null
          ? tr('commands.spinOff', {
              'business': businessName(content, business),
              'company': company(c),
              'name': name,
            })
          : tr('commands.moveBusiness', {
              'business': businessName(content, business),
              'company': company(c),
              'to': company(to),
            }),
    MoveCompany(company: final c, :final under) => tr('commands.moveCompany', {
      'company': company(c),
      'under': under == null ? tr('common.theHolding') : company(under),
    }),
    MergeCompany(company: final c, :final into) => tr('commands.merge', {
      'company': company(c),
      'into': company(into),
    }),
    SellBusiness(company: final c, :final business) => tr(
      'commands.sellBusiness',
      {'business': businessName(content, business), 'company': company(c)},
    ),
    SellCompany(company: final c) => tr('commands.sellCompany', {
      'company': company(c),
    }),
    FoundCompany(:final name, :final capital, :final parent) =>
      tr('commands.foundCompany', {
        'name': name,
        'capital': money(capital, cents: false),
        'holder': parent == null ? tr('common.theHolding') : company(parent),
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
    CreateBrand() => '',
    // A director's, for the player's company.
    OpenInDistrict(:final row, :final format) => tr('commands.openInDistrict', {
      'format': aFormat(content.formats[format.index]),
      'district': content.neighbourhoods[row].name,
    }),
    BuyInDistrict(:final row, :final site) => tr('commands.buyInDistrict', {
      'shop':
          [
            for (final district in view.districts)
              if (district.row == row)
                for (final shop in district.shops)
                  if (shop.site == site) shop.name,
          ].firstOrNull ??
          '',
      'district': content.neighbourhoods[row].name,
    }),
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
      :final person,
    ) =>
      tr('commands.hireDirector', {
        'director':
            person?.name ?? aDirector(content.directors!.grades[grade.index]),
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
    RenameHolding(:final name) => tr('commands.renameHolding', {'name': name}),
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
    BuildFactory(
      :final kind,
      :final country,
      :final name,
      :final borrow,
      :final termMonths,
    ) =>
      tr('commands.buildFactory', {
        'name': name,
        'kind': content.factories!.kinds[kind.index].name.toLowerCase(),
        'country': content.countries[country.index].name,
        'loan': _loan(borrow, termMonths),
      }),
    SetFactoryShifts(:final factory, :final shifts) => tr(
      shifts == 0 ? 'commands.stopFactory' : 'commands.factoryShifts',
      {'factory': _factoryName(view, factory), 'count': shifts},
    ),
    SetFactoryTerms(:final factory, :final rivalDiscount) => tr(
      rivalDiscount == null
          ? 'commands.factoryExclusive'
          : 'commands.factoryRivals',
      {
        'factory': _factoryName(view, factory),
        'discount': rivalDiscount == null ? '' : percent(rivalDiscount),
      },
    ),
    CloseFactory(:final factory) => tr('commands.closeFactory', {
      'factory': _factoryName(view, factory),
    }),
    SetLab(:final factory, :final budget, project: final p) =>
      p == null || budget == Money.zero
          ? tr('commands.labPause', {'factory': _factoryName(view, factory)})
          : tr('commands.labBudget', {
              'factory': _factoryName(view, factory),
              'budget': money(budget, cents: false),
              'product': product(p),
            }),
    HireKeyPerson(:final person, :final factory) => tr(
      'commands.hireKeyPerson',
      {
        'person': _keyPersonName(view, person),
        'factory': _factoryName(view, factory),
      },
    ),
    DismissKeyPerson(:final person) => tr('commands.dismissKeyPerson', {
      'person': _keyPersonName(view, person),
    }),
    StartSoftware(:final name) => tr('commands.startSoftware', {'name': name}),
    BidTender(:final tender, :final factory, :final price) =>
      price == null
          ? tr('commands.withdrawBid', {'number': tender})
          : tr('commands.bidTender', {
              'factory': _factoryName(view, factory),
              'price': money(price),
              'number': tender,
            }),
    BreakContract(:final contract) => tr('commands.breakContract', {
      'number': contract,
    }),
    AnswerContract(:final contract, :final accept) => tr(
      accept ? 'commands.acceptCut' : 'commands.refuseCut',
      {'number': contract},
    ),
    AskPrice(:final contract, :final price) => tr('commands.askPrice', {
      'number': contract,
      'price': money(price),
    }),
    BidForCompany(:final stock, :final premium) => tr('commands.bidFor', {
      'name': _listed(content, stock, index: false, view: view),
      'premium': percent(premium, decimals: 0),
    }),
    AnswerBid(:final tender) => tr(
      tender ? 'commands.tender' : 'commands.keepShares',
    ),
    RunListed(:final stock) => tr('commands.runListed', {
      'name': _listed(content, stock, index: false, view: view),
    }),
    BuyRival(:final via, :final stock) => tr('commands.buyRival', {
      'name': _listed(content, via, index: false, view: view),
      'rival': _listed(content, stock, index: false, view: view),
    }),
    SellControlled(:final stock) => tr('commands.sellControlled', {
      'name': _listed(content, stock, index: false, view: view),
    }),
    ListCompany(:final company, :final share) => tr('commands.listCompany', {
      'name': view.companyNames[company.index],
      'share': percent(share, decimals: 0),
    }),
    BuyShares(:final of, :final units, :final index) => tr(
      index ? 'commands.buyIndex' : 'commands.buyShares',
      {
        'units': compactCount(units),
        'name': _listed(content, of, index: index, view: view),
      },
    ),
    SellShares(:final of, :final units, :final index) => tr(
      index ? 'commands.sellIndex' : 'commands.sellShares',
      {
        'units': compactCount(units),
        'name': _listed(content, of, index: index, view: view),
      },
    ),
    EnlargeFactory(:final factory) => tr('commands.enlargeFactory', {
      'factory': _factoryName(view, factory),
    }),
    SetSoftwarePrice(:final software, :final price) => tr(
      'commands.setSoftwarePrice',
      {'name': _softwareName(view, software), 'price': money(price)},
    ),
    SetSoftwareMarketing(:final software, :final budget) => tr(
      'commands.setSoftwareMarketing',
      {
        'name': _softwareName(view, software),
        'amount': money(budget, cents: false),
      },
    ),
    HireSoftwarePerson(:final software, :final person) =>
      tr('commands.hireSoftwarePerson', {
        'person': _softwarePersonName(view, person),
        'name': _softwareName(view, software),
      }),
    RaiseRound(:final software, :final share) => tr('commands.raiseRound', {
      'name': _softwareName(view, software),
      'share': percent(share, decimals: 0),
    }),
    AcceptSoftwareOffer(:final software) => tr('commands.acceptSoftwareOffer', {
      'name': _softwareName(view, software),
    }),
    DeclineSoftwareOffer(:final software) => tr(
      'commands.declineSoftwareOffer',
      {'name': _softwareName(view, software)},
    ),
    ShutDownSoftware(:final software) => tr('commands.shutDownSoftware', {
      'name': _softwareName(view, software),
    }),
    ClearStock(store: final s, product: final p) => tr('commands.clearStock', {
      'product': product(p),
      'store': store(s),
    }),
    OrderFromFactory(store: final s, :final factory, :final lines) =>
      tr('commands.order', {
        'units': lines.fold<int>(0, (sum, line) => sum + line.quantity),
        'supplier': _factoryName(view, factory),
        'store': store(s),
      }),
    BuyNationalChain(
      :final country,
      :final chain,
      :final borrow,
      :final termMonths,
    ) =>
      tr('commands.buyNationalChain', {
        'chain': _chainName(view, country, chain),
        'country': content.countries[country.index].name,
        'loan': _loan(borrow, termMonths),
      }),
    SellNational(:final country) => tr('commands.sellNational', {
      'country': content.countries[country.index].name,
    }),
    AcceptNationalOffer() => tr('commands.acceptOffer'),
    DeclineNationalOffer() => tr('commands.declineOffer'),
    OpenNational(
      :final country,
      :final region,
      :final format,
      :final count,
      :final borrow,
      :final termMonths,
    ) =>
      tr('commands.openNational', {
        'count': count,
        'format': count == 1
            ? aFormat(content.formats[format.index])
            : content.formats[format.index].name.toLowerCase(),
        'region': _regionName(content, country, region),
        'loan': _loan(borrow, termMonths),
      }),
  };
}

/// The name of [chain] of the game's [country] in the national table.
/// A listed company's name, or an exchange's index's.
String _listed(
  ContentDb content,
  int of, {
  required bool index,
  required Observation view,
}) {
  final stocks = content.stocks;
  if (stocks == null) return '';
  if (index) {
    return of < stocks.exchanges.length ? stocks.exchanges[of].index : '';
  }
  final market = view.stocks;
  if (market != null && of < market.stocks.length) {
    return market.stocks[of].name;
  }
  return of < stocks.listings.length ? stocks.listings[of].name : '';
}

String _chainName(Observation view, CountryId country, int chain) {
  for (final national in view.national) {
    if (national.country != country) continue;
    for (final view in national.chains) {
      if (view.index == chain) return view.name;
    }
  }
  return '';
}

/// The name of region [region] of [country] in the national table.
String _regionName(ContentDb content, CountryId country, int region) {
  final key = content.countries[country.index].national;
  for (final national in content.national?.countries ?? const []) {
    if (national.key == key && region < national.regions.length) {
      return national.regions[region].name;
    }
  }
  return '';
}

/// The name of the actor's factory [id].
String _factoryName(Observation view, FactoryId id) {
  for (final company in view.companies) {
    for (final factory in company.factories) {
      if (factory.id == id) return factory.name;
    }
  }
  return '';
}

/// The name of key person [id], a candidate or one of the actor's.
String _keyPersonName(Observation view, KeyPersonId id) {
  for (final person in view.candidates) {
    if (person.id == id) return person.name;
  }
  for (final company in view.companies) {
    for (final factory in company.factories) {
      for (final person in factory.lab?.people ?? const <KeyPersonView>[]) {
        if (person.id == id) return person.name;
      }
    }
  }
  return _softwarePersonName(view, id);
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

/// The name of the actor's software company [id], or nothing if it isn't
/// theirs.
String _softwareName(Observation view, SoftwareId id) {
  for (final company in view.companies) {
    if (company.software case final software? when software.id == id) {
      return software.name;
    }
  }
  return '';
}

/// The name of [id], a software person on the market or in a team.
String _softwarePersonName(Observation view, KeyPersonId id) {
  for (final person in view.softwareCandidates) {
    if (person.id == id) return person.name;
  }
  for (final company in view.companies) {
    for (final person in company.software?.team ?? const <KeyPersonView>[]) {
      if (person.id == id) return person.name;
    }
  }
  return '';
}
