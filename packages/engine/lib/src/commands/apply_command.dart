import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/credit.dart';
import '../state/director.dart';
import '../state/entities.dart';
import '../state/orders.dart';
import '../state/store.dart';
import '../observation/research.dart';
import '../state/valuation.dart';
import '../state/world_state.dart';
import '../systems/closure.dart';
import 'command.dart';
import 'refusal.dart';
import 'transfers.dart';

/// Validates and applies [command]. Returns null when it was applied, or the
/// reason it was rejected. The rules are the same for every actor.
Refusal? applyCommand(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Command command,
) {
  if (!_inRange(command.actor.index, world.persons.length)) {
    return const Refusal('unknownActor');
  }
  return switch (command) {
    // Done when it was submitted: see [Simulation.submit].
    WakeNeighbourhood() => null,
    SetPrice() => _setPrice(world, content, command),
    PlaceOrder() => _placeOrder(world, content, command),
    ListProduct() => _listProduct(world, content, command),
    DelistProduct() => _delistProduct(world, content, ledger, command),
    InjectCapital() => _injectCapital(world, ledger, command),
    PayDividend() => _payDividend(world, content, ledger, command),
    TakeLoan() => _takeLoan(world, content, ledger, command),
    RepayLoan() => _repayLoan(world, ledger, command),
    OpenStore() => _openStore(world, content, ledger, command),
    CloseStore() => _closeStore(world, ledger, command),
    SetStaffing() => _setStaffing(world, content, command),
    BuyResearch() => _buyResearch(world, content, ledger, command),
    HireManager() => _hireManager(world, content, command),
    FireManager() => _fireManager(world, command),
    ExpandStore() => _expandStore(world, content, ledger, command),
    RenameStore() => _renameStore(world, command),
    RenameCompany() => _renameCompany(world, command),
    SetCushion() => _setCushion(world, command),
    HireDirector() => _hireDirector(world, content, command),
    FireDirector() => _fireDirector(world, command),
    SetMarketing() => _setMarketing(world, command),
    ConvertStore() => _convertStore(world, content, ledger, command),
    BuyStore() => _buyStore(world, content, ledger, command),
    SellStore() => _sellStore(world, content, ledger, command),
    BuyCompany() => _buyCompany(world, content, ledger, command),
  };
}

/// The longest name a store or company may have.
const maxNameLength = 32;

/// Why [name] can't be a store or company name, or null if it can.
Refusal? _nameProblem(String name) =>
    name.trim() != name || name.isEmpty || name.length > maxNameLength
    ? const Refusal('nameRule', count: maxNameLength)
    : null;

Refusal? _renameStore(WorldState world, RenameStore command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  final problem = _nameProblem(command.name);
  if (problem != null) return problem;
  store.name = command.name;
  return null;
}

Refusal? _renameCompany(WorldState world, RenameCompany command) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final problem = _nameProblem(command.name);
  if (problem != null) return problem;
  company.name = command.name;
  return null;
}

Refusal? _setCushion(WorldState world, SetCushion command) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  if (command.days < 0 || command.days > maxCushionDays) {
    return const Refusal('cushionRange', count: maxCushionDays);
  }
  company.cushionDays = command.days;
  return null;
}

Refusal? _hireDirector(
  WorldState world,
  ContentDb content,
  HireDirector command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final directors = content.directors;
  if (directors == null) return const Refusal('noDirectors');
  if (!_inRange(command.grade.index, directors.grades.length)) {
    return const Refusal('unknownDirectorGrade');
  }
  if (!_inRange(command.strategy.index, content.strategies.length)) {
    return const Refusal('unknownStrategy');
  }
  if (!_inRange(command.managerGrade.index, content.managers.grades.length)) {
    return const Refusal('unknownManagerGrade');
  }
  final current = company.director;
  company.director = Director(
    grade: command.grade,
    strategy: command.strategy,
    managerGrade: command.managerGrade,
    growth: command.growth,
    payout: command.payout,
    borrows: command.borrows,
    hiredOn: current != null && current.grade == command.grade
        ? current.hiredOn
        : world.today,
  );
  return null;
}

Refusal? _fireDirector(WorldState world, FireDirector command) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  if (company.director == null) return const Refusal('noDirector');
  company.director = null;
  return null;
}

/// The store, or the reason [actor] can't act on it.
(Store?, Refusal?) _ownedStore(WorldState world, PersonId actor, StoreId id) {
  if (!_inRange(id.index, world.stores.length)) {
    return (null, const Refusal('unknownStore'));
  }
  final store = world.stores[id.index];
  if (world.companies[store.company.index].owner != actor) {
    return (null, const Refusal('notYourStore'));
  }
  if (!store.isTrading) return (null, const Refusal('storeClosed'));
  return (store, null);
}

/// The company, or the reason [actor] can't act on it.
(Company?, Refusal?) _ownedCompany(
  WorldState world,
  PersonId actor,
  CompanyId id,
) {
  if (!_inRange(id.index, world.companies.length)) {
    return (null, const Refusal('unknownCompany'));
  }
  final company = world.companies[id.index];
  if (company.owner != actor) {
    return (null, const Refusal('notYourCompany'));
  }
  if (!company.isActive) return (null, const Refusal('companyLiquidated'));
  return (company, null);
}

Refusal? _injectCapital(
  WorldState world,
  Ledger ledger,
  InjectCapital command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  if (command.amount <= Money.zero) return const Refusal('amountNotPositive');
  final person = world.persons[command.actor.index];
  if (person.accounts[AccountKind.cash] < command.amount) {
    return const Refusal('notEnoughPersonalCash');
  }
  injectCapital(ledger, person, company, command.amount);
  return null;
}

Refusal? _payDividend(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  PayDividend command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  if (command.amount <= Money.zero) return const Refusal('amountNotPositive');
  if (company.accounts[AccountKind.cash] < command.amount) {
    return const Refusal('notEnoughCompanyCash');
  }
  if (company.accounts.retainedEarnings < command.amount) {
    return const Refusal('dividendsFromProfits');
  }
  final owner = world.persons[command.actor.index];
  ledger.pay(
    payer: company,
    payerAccount: AccountKind.dividends,
    payee: owner,
    payeeAccount: AccountKind.dividends,
    amount: command.amount,
    reason: EntryReason.dividend,
  );
  if (content.taxes case final taxes?) {
    final tax = command.amount.times(taxes.dividendRate);
    if (tax > Money.zero) {
      ledger.pay(
        payer: owner,
        payerAccount: AccountKind.taxes,
        payee: world.government,
        payeeAccount: AccountKind.revenue,
        amount: tax,
        reason: EntryReason.dividendTax,
      );
    }
  }
  return null;
}

Refusal? _takeLoan(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  TakeLoan command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final refusal = _loanRefusal(
    world,
    content,
    command.amount,
    command.termMonths,
  );
  if (refusal != null) return refusal;
  final person = world.persons[command.actor.index];
  if (command.guarantee) {
    if (command.amount > guaranteeRoom(world, content, person)) {
      return const Refusal('cannotBackGuarantee');
    }
  } else {
    final credit = earningsCredit(world, content, company);
    if (command.amount > credit) {
      return credit == Money.zero
          ? const Refusal('bankWantsGuarantee')
          : Refusal('bankLendsAtMost', amount: credit);
    }
  }
  _lend(
    world,
    content,
    ledger,
    company,
    person,
    command.amount,
    command.termMonths,
    guarantor: command.guarantee ? person : null,
  );
  return null;
}

/// Why the bank won't lend [amount] over [termMonths] to anyone, or null.
Refusal? _loanRefusal(
  WorldState world,
  ContentDb content,
  Money amount,
  int termMonths,
) {
  final most = content.finance.maxTermMonths;
  if (amount <= Money.zero) return const Refusal('amountNotPositive');
  if (termMonths < 1 || termMonths > most) {
    return Refusal('termRange', count: most);
  }
  if (world.bank.accounts[AccountKind.cash] < amount) {
    return const Refusal('bankCannotLend');
  }
  return null;
}

/// The loan for a purchase of [amount] by [company], owned by [owner], as
/// [splitLoan] has the bank lend it; null when nothing is borrowed. The
/// owner spends [spent] of their cash on it, and the company buys a store
/// that earns [extra] a year.
({Money unsecured, Money guaranteed})? _purchaseLoan(
  WorldState world,
  ContentDb content,
  Company? company,
  Person owner,
  Money amount, {
  Money spent = Money.zero,
  Money extra = Money.zero,
}) => amount == Money.zero
    ? null
    : splitLoan(
        amount,
        credit: company == null
            ? Money.zero
            : earningsCredit(world, content, company, extra: extra),
        guarantee: guaranteeRoom(world, content, owner, spent: spent),
      );

/// Lends [amount] to [company] over [termMonths] at the bank's rate for its
/// [owner] today, guaranteed by [guarantor] if given.
void _lend(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Company company,
  Person owner,
  Money amount,
  int termMonths, {
  Person? guarantor,
}) {
  final rate = lendingRate(
    content,
    world.macro.policyRate,
    world.today,
    guaranteed: guarantor != null,
    lastBankruptcy: owner.lastBankruptcy,
  );
  world.loans.add(
    Loan(
      number: world.nextLoanNumber++,
      company: company.id,
      principal: amount,
      outstanding: amount,
      rate: rate,
      installmentsLeft: termMonths,
      guarantor: guarantor?.id,
      accruedTo: world.today,
    ),
  );
  ledger.pay(
    payer: world.bank,
    payerAccount: AccountKind.loans,
    payee: company,
    payeeAccount: AccountKind.loans,
    amount: amount,
    reason: EntryReason.loan,
  );
}

/// Lends [loan] to [company]: what its earnings carry, then what [owner]
/// guarantees, each as a loan of its own.
void _lendFor(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  Company company,
  Person owner,
  ({Money unsecured, Money guaranteed}) loan,
  int termMonths,
) {
  if (loan.unsecured > Money.zero) {
    _lend(world, content, ledger, company, owner, loan.unsecured, termMonths);
  }
  if (loan.guaranteed > Money.zero) {
    _lend(
      world,
      content,
      ledger,
      company,
      owner,
      loan.guaranteed,
      termMonths,
      guarantor: owner,
    );
  }
}

Refusal? _repayLoan(WorldState world, Ledger ledger, RepayLoan command) {
  final loan = world.loans.where((l) => l.number == command.loan).firstOrNull;
  if (loan == null) return const Refusal('unknownLoan');
  final (company, error) = _ownedCompany(world, command.actor, loan.company);
  if (company == null) return error;
  if (command.amount <= Money.zero) return const Refusal('amountNotPositive');
  if (command.amount > loan.outstanding) {
    return const Refusal('moreThanLoan');
  }
  final interest = loan.interestTo(world.today);
  if (company.accounts[AccountKind.cash] < interest + command.amount) {
    return const Refusal('notEnoughCompanyCash');
  }
  if (interest > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.interest,
      payee: world.bank,
      payeeAccount: AccountKind.revenue,
      amount: interest,
      reason: EntryReason.interest,
    );
  }
  ledger.pay(
    payer: company,
    payerAccount: AccountKind.loans,
    payee: world.bank,
    payeeAccount: AccountKind.loans,
    amount: command.amount,
    reason: EntryReason.loanRepayment,
  );
  loan
    ..accruedTo = world.today
    ..outstanding -= command.amount;
  if (loan.outstanding == Money.zero) world.loans.remove(loan);
  return null;
}

Refusal? _openStore(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  OpenStore command,
) {
  if (!_inRange(command.site.index, content.sites.length)) {
    return const Refusal('unknownSite');
  }
  final site = content.sites[command.site.index];
  if (world.storeAt(site.id) != null) return const Refusal('siteTaken');
  if (command.name.isEmpty) return const Refusal('storeNeedsName');
  if (!_inRange(command.format.index, content.formats.length)) {
    return const Refusal('unknownFormat');
  }
  final format = content.formats[command.format.index];
  if (format.minArea > site.area) {
    return Refusal('siteTooSmall', format: format.id);
  }
  if (command.capital.isNegative) return const Refusal('capitalNegative');
  final person = world.persons[command.actor.index];
  if (person.accounts[AccountKind.cash] < command.capital) {
    return const Refusal('notEnoughPersonalCash');
  }
  Company? company;
  if (command.company case final id?) {
    final (owned, error) = _ownedCompany(world, command.actor, id);
    if (owned == null) return error;
    company = owned;
  }
  final cash =
      (company?.accounts[AccountKind.cash] ?? Money.zero) +
      command.capital +
      command.borrow;
  final openingCost = site.openingCost
      .times(format.fitOut)
      .times(world.macro.priceIndex);
  if (cash < openingCost) {
    return Refusal('cannotPayOpening', amount: openingCost);
  }
  if (command.borrow != Money.zero) {
    final refusal = _loanRefusal(
      world,
      content,
      command.borrow,
      command.termMonths,
    );
    if (refusal != null) return refusal;
  }
  final loan = _purchaseLoan(
    world,
    content,
    company,
    person,
    command.borrow,
    spent: command.capital,
  );
  if (command.borrow != Money.zero && loan == null) {
    return const Refusal('bankWillNotLend');
  }
  company ??= world.addCompany(command.name, person.id);
  if (command.capital > Money.zero) {
    injectCapital(ledger, person, company, command.capital);
  }
  if (loan != null) {
    _lendFor(world, content, ledger, company, person, loan, command.termMonths);
  }
  final store = world.addStore(
    content,
    name: command.name,
    company: company.id,
    site: site,
    prices: List.filled(content.products.length, null),
    staff: List.filled(DaySlot.values.length, 0),
    opensOn: world.today + site.buildDays,
    format: format.id,
  );
  if (openingCost > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.openingCosts,
      payee: world.landlords,
      payeeAccount: AccountKind.revenue,
      amount: openingCost,
      reason: EntryReason.openingCosts,
      store: store.id,
    );
  }
  return null;
}

Refusal? _setStaffing(
  WorldState world,
  ContentDb content,
  SetStaffing command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (command.staff.length != DaySlot.values.length) {
    return Refusal('staffEachSlot', count: DaySlot.values.length);
  }
  final most = content.operations.maxStaffPerSlot;
  if (command.staff.any((count) => count < 0 || count > most)) {
    return Refusal('staffRange', count: most);
  }
  store.staff.setAll(0, command.staff);
  return null;
}

Refusal? _buyResearch(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  BuyResearch command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  if (!_inRange(command.market.index, content.markets.length)) {
    return const Refusal('unknownMarket');
  }
  if (!_inRange(command.tier.index, content.researchTiers.length)) {
    return const Refusal('unknownResearch');
  }
  final tier = content.researchTiers[command.tier.index];
  final cost = tier.cost.times(world.macro.priceIndex);
  if (company.accounts[AccountKind.cash] < cost) {
    return const Refusal('notEnoughCompanyCash');
  }
  if (cost > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.research,
      payee: world.services,
      payeeAccount: AccountKind.revenue,
      amount: cost,
      reason: EntryReason.research,
    );
  }
  world.reports.add(
    commissionStudy(
      world,
      content,
      buyer: command.actor,
      market: command.market,
      tier: tier,
    ),
  );
  return null;
}

Refusal? _hireManager(
  WorldState world,
  ContentDb content,
  HireManager command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (!_inRange(command.grade.index, content.managers.grades.length)) {
    return const Refusal('unknownManagerGrade');
  }
  if (!_inRange(command.strategy.index, content.strategies.length)) {
    return const Refusal('unknownStrategy');
  }
  if (command.duties.length != ManagerDuty.values.length) {
    return Refusal('eachDuty', count: ManagerDuty.values.length);
  }
  if (!command.duties.contains(true)) {
    return const Refusal('managerNeedsDuty');
  }
  final current = store.manager;
  store.manager = Manager(
    grade: command.grade,
    strategy: command.strategy,
    duties: List.unmodifiable(command.duties),
    hiredOn: current != null && current.grade == command.grade
        ? current.hiredOn
        : world.today,
  );
  return null;
}

Refusal? _fireManager(WorldState world, FireManager command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (store.manager == null) return const Refusal('noManager');
  store.manager = null;
  return null;
}

Refusal? _expandStore(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  ExpandStore command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (store.works != null) return const Refusal('alreadyEnlarging');
  final expansion = content.expansion;
  final area = store.area + expansion.stepArea;
  if (area > content.sites[store.site.index].maxArea) {
    return const Refusal('noRoomToGrow');
  }
  final company = world.companies[store.company.index];
  final cost = expansion.cost(world.macro.priceIndex);
  if (company.accounts[AccountKind.cash] < cost) {
    return Refusal('cannotPayWorks', amount: cost);
  }
  if (cost > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.openingCosts,
      payee: world.landlords,
      payeeAccount: AccountKind.revenue,
      amount: cost,
      reason: EntryReason.expansion,
      store: store.id,
    );
  }
  store.works = (
    area: area,
    done: world.today + expansion.buildDays,
    format: null,
  );
  return null;
}

Refusal? _closeStore(WorldState world, Ledger ledger, CloseStore command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  closeStore(world, ledger, store);
  return null;
}

Refusal? _setPrice(WorldState world, ContentDb content, SetPrice command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (!_inRange(command.product.index, content.products.length)) {
    return const Refusal('unknownProduct');
  }
  if (store.prices[command.product.index] == null) {
    return const Refusal('notListed');
  }
  if (command.price <= Money.zero) return const Refusal('priceNotPositive');
  store.prices[command.product.index] = command.price;
  return null;
}

Refusal? _placeOrder(WorldState world, ContentDb content, PlaceOrder command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (!_inRange(command.supplier.index, content.suppliers.length)) {
    return const Refusal('unknownSupplier');
  }
  final supplier = content.suppliers[command.supplier.index];
  if (command.lines.isEmpty) return const Refusal('orderEmpty');
  final seen = <int>{};
  for (final (:product, :quantity) in command.lines) {
    if (!_inRange(product.index, content.products.length)) {
      return const Refusal('unknownProduct');
    }
    if (!seen.add(product.index)) {
      return Refusal('productTwice', product: product);
    }
    if (!supplier.carries[product.index]) {
      return Refusal(
        'supplierDoesNotSell',
        supplier: supplier.id,
        product: product,
      );
    }
    if (store.prices[product.index] == null) {
      return Refusal('storeDoesNotList', product: product);
    }
    if (quantity < supplier.minOrderUnits) {
      return Refusal(
        'belowMinimum',
        product: product,
        supplier: supplier.id,
        count: supplier.minOrderUnits,
      );
    }
    if (quantity > store.storageUnits) {
      return Refusal('overCapacity', product: product);
    }
  }
  world.orders.add(
    PurchaseOrder(
      number: world.nextOrderNumber++,
      store: store.id,
      supplier: supplier.id,
      arrival: world.today + supplier.leadTimeDays,
      lines: [
        for (final (:product, :quantity) in command.lines)
          OrderLine(
            product: product,
            quantity: quantity,
            unitPrice: supplier.unitPrice(
              content.products[product.index],
              quantity,
              world.macro.priceIndex,
            ),
          ),
      ],
    ),
  );
  return null;
}

Refusal? _listProduct(
  WorldState world,
  ContentDb content,
  ListProduct command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (!_inRange(command.product.index, content.products.length)) {
    return const Refusal('unknownProduct');
  }
  if (store.prices[command.product.index] != null) {
    return const Refusal('alreadyListed');
  }
  final format = content.formats[store.format.index];
  final product = content.products[command.product.index];
  if (!format.sells[product.category.index]) {
    return Refusal('formatDoesNotSell', format: format.id, product: product.id);
  }
  if (store.listedProducts >= store.shelfSlots) {
    return const Refusal('shelvesFull');
  }
  if (command.price <= Money.zero) return const Refusal('priceNotPositive');
  store.prices[command.product.index] = command.price;
  return null;
}

Refusal? _delistProduct(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  DelistProduct command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (!_inRange(command.product.index, content.products.length)) {
    return const Refusal('unknownProduct');
  }
  if (store.prices[command.product.index] == null) {
    return const Refusal('notListed');
  }
  store.prices[command.product.index] = null;
  final cleared = store.stock[command.product.index].clear();
  if (cleared.units > 0) {
    ledger.post(
      world.companies[store.company.index],
      debit: AccountKind.writeOffs,
      credit: AccountKind.inventory,
      amount: cleared.cost,
      reason: EntryReason.delisting,
      store: store.id,
      product: command.product,
      units: cleared.units,
    );
  }
  return null;
}

bool _inRange(int index, int length) => index >= 0 && index < length;

/// The largest share of its sales a store may spend on marketing.
const Fx maxMarketingShare = Fx.raw(2500);

Refusal? _setMarketing(WorldState world, SetMarketing command) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (command.share.isNegative) return const Refusal('shareNegative');
  if (command.share > maxMarketingShare) {
    return const Refusal('marketingCap');
  }
  store.marketingShare = command.share;
  return null;
}

/// What turning a store of [from] with [area] on [site] into [to] costs at
/// [priceIndex]: the difference in fitting out, never less than nothing,
/// and the works to bring it to the format's least area.
Money conversionCost(
  ContentDb content,
  SiteDef site,
  FormatId from,
  int area,
  FormatDef to,
  Fx priceIndex,
) {
  final extraFit = to.fitOut - content.formats[from.index].fitOut;
  final fitting = extraFit.isNegative
      ? Money.zero
      : site.openingCost.times(extraFit);
  final extraArea = to.minArea > area ? to.minArea - area : 0;
  return (fitting + content.expansion.costPerSqm.timesInt(extraArea)).times(
    priceIndex,
  );
}

Refusal? _convertStore(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  ConvertStore command,
) {
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (store.status != StoreStatus.open) {
    return const Refusal('onlyOpenConverts');
  }
  if (store.works != null) return const Refusal('worksUnderWay');
  if (!_inRange(command.format.index, content.formats.length)) {
    return const Refusal('unknownFormat');
  }
  final from = content.formats[store.format.index];
  final to = content.formats[command.format.index];
  if (to.id == from.id) return Refusal('alreadyFormat', format: to.id);
  if (content.formatChannels[to.id.index] !=
      content.formatChannels[from.id.index]) {
    return Refusal('cannotBecome', format: from.id, toFormat: to.id);
  }
  final site = content.sites[store.site.index];
  if (to.minArea > site.maxArea) {
    return Refusal('siteTooSmall', format: to.id);
  }
  final cost = conversionCost(
    content,
    site,
    store.format,
    store.area,
    to,
    world.macro.priceIndex,
  );
  final company = world.companies[store.company.index];
  if (company.accounts[AccountKind.cash] < cost) {
    return Refusal('cannotPayWorks', amount: cost);
  }
  if (cost > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.openingCosts,
      payee: world.landlords,
      payeeAccount: AccountKind.revenue,
      amount: cost,
      reason: EntryReason.expansion,
      store: store.id,
    );
  }
  store.works = (
    area: to.minArea > store.area ? to.minArea : store.area,
    done: world.today + site.buildDays,
    format: to.id,
  );
  return null;
}

const _nothingForSale = Refusal('nothingForSale');

Refusal? _buyStore(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  BuyStore command,
) {
  if (content.acquisitions == null) return _nothingForSale;
  if (!_inRange(command.store.index, world.stores.length)) {
    return const Refusal('unknownStore');
  }
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final store = world.stores[command.store.index];
  if (!store.isTrading) return const Refusal('storeClosed');
  final owner = world.companies[store.company.index].owner;
  if (owner == command.actor) return const Refusal('alreadyOwnStore');
  if (owner == world.player) return const Refusal('ownerNotSelling');
  if (store.acquiredOn == world.today) {
    return const Refusal('justChangedHands');
  }
  final value = valueStore(world, content, store)!;
  final price = value.price;
  if (company.accounts[AccountKind.cash] + command.borrow < price) {
    return Refusal('cannotPayPrice', amount: price);
  }
  if (command.borrow != Money.zero) {
    final refusal = _loanRefusal(
      world,
      content,
      command.borrow,
      command.termMonths,
    );
    if (refusal != null) return refusal;
  }
  final buyer = world.persons[command.actor.index];
  final loan = _purchaseLoan(
    world,
    content,
    company,
    buyer,
    command.borrow,
    extra: value.earnings,
  );
  if (command.borrow != Money.zero && loan == null) {
    return const Refusal('bankWillNotLend');
  }
  if (loan != null) {
    _lendFor(world, content, ledger, company, buyer, loan, command.termMonths);
  }
  transferStore(world, ledger, store, company, price);
  return null;
}

Refusal? _sellStore(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  SellStore command,
) {
  if (content.acquisitions == null) return _nothingForSale;
  final (store, error) = _ownedStore(world, command.actor, command.store);
  if (store == null) return error;
  if (sellToBestBuyer(world, content, ledger, store) == null) {
    return const Refusal('noBuyer');
  }
  return null;
}

Refusal? _buyCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  BuyCompany command,
) {
  if (content.acquisitions == null) return _nothingForSale;
  if (!_inRange(command.company.index, world.companies.length)) {
    return const Refusal('unknownCompany');
  }
  final company = world.companies[command.company.index];
  if (!company.isActive) return const Refusal('companyLiquidated');
  if (company.owner == command.actor) {
    return const Refusal('alreadyOwnCompany');
  }
  if (company.owner == world.player) return const Refusal('ownerNotSelling');
  final price = companyPrice(world, content, company)!;
  final buyer = world.persons[command.actor.index];
  if (buyer.accounts[AccountKind.cash] + command.borrow < price) {
    return Refusal('personalCashShort', amount: price);
  }
  if (command.borrow != Money.zero) {
    final refusal = _loanRefusal(
      world,
      content,
      command.borrow,
      command.termMonths,
    );
    if (refusal != null) return refusal;
    if (command.borrow > price) {
      return const Refusal('borrowOverPrice');
    }
    final credit = earningsCredit(world, content, company);
    if (command.borrow > credit) {
      return credit == Money.zero
          ? const Refusal('noLoanOnEarnings')
          : Refusal('bankLendsItAtMost', amount: credit);
    }
    _lend(
      world,
      content,
      ledger,
      company,
      buyer,
      command.borrow,
      command.termMonths,
    );
  }
  transferCompany(
    world,
    content,
    ledger,
    company,
    buyer,
    price,
    financed: command.borrow,
  );
  return null;
}
