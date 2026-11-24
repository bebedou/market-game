part of 'apply_command.dart';

// Restructuring, the owner's design of 2026-11-18: inside the group at book
// value (down the tree as capital, sideways for cash, up as a dividend in
// kind at the dividend rate), and selling outside on the spot.

/// How something moves between two of the owner's companies.
enum _Way { down, sideways, up }

/// Whether [ancestor] holds [company], directly or through others.
bool _holds(WorldState world, CompanyId ancestor, CompanyId company) {
  var parent = world.companies[company.index].parent;
  while (parent != null) {
    if (parent == ancestor) return true;
    parent = world.companies[parent.index].parent;
  }
  return false;
}

/// The companies from [top]'s child down to [bottom], top first; [top] null
/// for the holding.
List<Company> _pathDown(WorldState world, CompanyId? top, Company bottom) {
  final path = <Company>[];
  Company? at = bottom;
  while (at != null && at.id != top) {
    path.insert(0, at);
    at = switch (at.parent) {
      final parent? => world.companies[parent.index],
      null => null,
    };
  }
  return path;
}

/// The way from [from] to [to], two companies of one owner.
_Way _way(WorldState world, CompanyId from, CompanyId to) =>
    _holds(world, from, to)
    ? _Way.down
    : _holds(world, to, from)
    ? _Way.up
    : _Way.sideways;

/// Whether [company] is listed, or has outside investors: what it holds is
/// then theirs too.
Refusal? _sharedRefusal(WorldState world, Company company) =>
    switch (sharedHoldings(world, company.id)) {
      final why? => Refusal(why),
      null => null,
    };

/// The dividend rate where [actor] lives, or none.
Fx _dividendRate(WorldState world, ContentDb content, PersonId actor) =>
    content.taxesOf(world.residence(content, actor))?.dividendRate ?? Fx.zero;

/// Posts [amount] for [party], the other way round if negative.
void _postSigned(
  Ledger ledger,
  LedgerParty party,
  AccountKind debit,
  AccountKind credit,
  Money amount,
) {
  if (amount > Money.zero) {
    ledger.post(
      party,
      debit: debit,
      credit: credit,
      amount: amount,
      reason: EntryReason.restructuring,
    );
  } else if (amount < Money.zero) {
    ledger.post(
      party,
      debit: credit,
      credit: debit,
      amount: -amount,
      reason: EntryReason.restructuring,
    );
  }
}

/// [payer] paying the dividend rate on [amount] received up the tree.
void _taxUp(
  WorldState world,
  Ledger ledger,
  LedgerParty payer,
  Money amount,
  Fx rate,
) {
  final tax = amount.times(rate);
  if (tax <= Money.zero) return;
  ledger.pay(
    payer: payer,
    payerAccount: AccountKind.taxes,
    payee: world.government,
    payeeAccount: AccountKind.revenue,
    amount: tax,
    reason: EntryReason.dividendTax,
  );
}

/// Books [value], at [account] in [from]'s books, moving to [to]'s along
/// [way]: down the tree, capital each company on the way puts in the next;
/// sideways, [to] paying [from] in cash; up, a dividend in kind each company
/// on the way pays up, the dividend rate [rate] paid on what each receives.
void _shift(
  WorldState world,
  Ledger ledger,
  Company from,
  Company to,
  AccountKind account,
  Money value,
  _Way way,
  Fx rate,
) {
  if (value <= Money.zero) return;
  switch (way) {
    case _Way.down:
      _postSigned(ledger, from, AccountKind.investments, account, value);
      for (final company in _pathDown(world, from.id, to)) {
        final last = company == to;
        _postSigned(
          ledger,
          company,
          last ? account : AccountKind.investments,
          AccountKind.equity,
          value,
        );
        company.injected += value;
      }
    case _Way.sideways:
      ledger.pay(
        payer: to,
        payerAccount: account,
        payee: from,
        payeeAccount: account,
        amount: value,
        reason: EntryReason.restructuring,
      );
    case _Way.up:
      _postSigned(ledger, from, AccountKind.dividends, account, value);
      // Each company between passes it up, paying the rate on it.
      for (final company in _pathDown(world, to.id, from).reversed.skip(1)) {
        _postSigned(
          ledger,
          company,
          AccountKind.dividends,
          AccountKind.dividendsReceived,
          value,
        );
        _taxUp(world, ledger, company, value, rate);
      }
      _postSigned(ledger, to, account, AccountKind.dividendsReceived, value);
      _taxUp(world, ledger, to, value, rate);
  }
}

/// What each company on the way up from [from] to [to] pays in tax on
/// [value], and whether every one can.
bool _canPayUp(
  WorldState world,
  Company from,
  Company to,
  Money value,
  Fx rate, {
  Money arriving = Money.zero,
}) {
  final tax = value.times(rate);
  for (final company in _pathDown(world, to.id, from).reversed.skip(1)) {
    if (company.accounts[AccountKind.cash] < tax) return false;
  }
  return to.accounts[AccountKind.cash] + arriving >= tax;
}

/// Hands [parts] to [to]: its shops of every scale, plants and software.
/// Shops across countries joining [to]'s own of their kind trade on beside
/// them under [from]'s name, as a chain bought does.
void _hand(WorldState world, BusinessParts parts, Company from, Company to) {
  for (final store in parts.stores) {
    store.company = to.id;
  }
  for (final (_, shop) in parts.sleeping) {
    shop.company = to.id;
  }
  if (world.national case final national?) {
    for (final (i, block) in parts.blocks) {
      final mine = national.blockOf(
        national.countries[i],
        company: to.id.index,
        trade: block.trade,
        format: block.format,
      );
      if (mine != null && block.name == null) block.name = from.name;
      block.company = to.id.index;
    }
  }
  for (final factory in parts.plants) {
    factory.company = to.id;
  }
  parts.software?.company = to.id;
}

/// [to]'s boss, if briefed with goals, taking on [business] as [from]'s
/// boss had it, or to hold.
void _briefFor(Company to, Company from, String business) {
  final director = to.director;
  if (director == null ||
      director.goals.isEmpty ||
      director.goals.containsKey(business)) {
    return;
  }
  to.director = director.withGoals({
    ...director.goals,
    business: from.director?.goalOf(business) ?? Goal.hold,
  });
}

Refusal? _moveBusiness(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  MoveBusiness command,
) {
  final (from, error) = _ownedCompany(world, command.actor, command.company);
  if (from == null) return error;
  final parts = businessParts(world, content, from.id, command.business);
  if (parts.isEmpty) return const Refusal('noSuchBusiness');
  Company? to;
  if (command.to case final id?) {
    final (owned, toError) = _ownedCompany(world, command.actor, id);
    if (owned == null) return toError;
    if (owned.id == from.id) return const Refusal('sameCompany');
    to = owned;
  } else {
    final problem = _nameProblem(command.name);
    if (problem != null) return problem;
  }
  for (final company in [from, ?to]) {
    final shared = _sharedRefusal(world, company);
    if (shared != null) return shared;
  }
  if (parts.software != null && to != null && holdsSoftware(world, to.id)) {
    return const Refusal('hasSoftware');
  }
  final (:stock, :bought) = businessBook(parts);
  final book = stock + bought;
  final rate = _dividendRate(world, content, command.actor);
  final way = to == null ? _Way.down : _way(world, from.id, to.id);
  if (to != null) {
    if (way == _Way.sideways && to.accounts[AccountKind.cash] < book) {
      return Refusal('notEnoughCashIn', amount: book);
    }
    if (way == _Way.up && !_canPayUp(world, from, to, book, rate)) {
      return const Refusal('notEnoughCashForTax');
    }
  }
  final receiver =
      to ?? (world.addCompany(command.name, command.actor)..parent = from.id);
  _shift(
    world,
    ledger,
    from,
    receiver,
    AccountKind.inventory,
    stock,
    way,
    rate,
  );
  _shift(
    world,
    ledger,
    from,
    receiver,
    AccountKind.businessAssets,
    bought,
    way,
    rate,
  );
  _hand(world, parts, from, receiver);
  _briefFor(receiver, from, command.business);
  return null;
}

Refusal? _moveCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  MoveCompany command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  Company? under;
  if (command.under case final id?) {
    final (owned, underError) = _ownedCompany(world, command.actor, id);
    if (owned == null) return underError;
    if (owned.id == company.id || _holds(world, company.id, owned.id)) {
      return const Refusal('underItsOwn');
    }
    final shared = _sharedRefusal(world, owned);
    if (shared != null) return shared;
    if (ownListing(world.stocks, company.id) != null) {
      return const Refusal('subsidiaryListed');
    }
    under = owned;
  }
  if (company.parent == under?.id) return const Refusal('alreadyThere');
  final value = company.injected;
  final rate = _dividendRate(world, content, command.actor);
  final from = switch (company.parent) {
    final parent? => world.companies[parent.index],
    null => null,
  };
  final holding = world.persons[command.actor.index];
  if (from == null) {
    // Down from the holding: its capital in the company now goes through
    // each company on the way.
    for (final each in _pathDown(world, null, under!)) {
      _postSigned(
        ledger,
        each,
        AccountKind.investments,
        AccountKind.equity,
        value,
      );
      each.injected += value;
    }
  } else if (under == null || _holds(world, under.id, from.id)) {
    // Up: a dividend in kind each company on the way pays, at the rate.
    final top = under;
    final tax = value.times(rate);
    final way = _pathDown(world, top?.id, from).reversed.skip(1);
    if (way.any((each) => each.accounts[AccountKind.cash] < tax) ||
        (top ?? holding).accounts[AccountKind.cash] < tax) {
      return const Refusal('notEnoughCashForTax');
    }
    _postSigned(
      ledger,
      from,
      AccountKind.dividends,
      AccountKind.investments,
      value,
    );
    for (final each in way) {
      _postSigned(
        ledger,
        each,
        AccountKind.dividends,
        AccountKind.dividendsReceived,
        value,
      );
      _taxUp(world, ledger, each, value, rate);
    }
    if (top != null) {
      _postSigned(
        ledger,
        top,
        AccountKind.investments,
        AccountKind.dividendsReceived,
        value,
      );
      _taxUp(world, ledger, top, value, rate);
    } else {
      _postSigned(
        ledger,
        holding,
        AccountKind.investments,
        AccountKind.dividends,
        value,
      );
      _taxUp(world, ledger, holding, value, rate);
    }
  } else if (_holds(world, from.id, under.id)) {
    // Down from its parent: capital each company on the way puts in.
    for (final each in _pathDown(world, from.id, under)) {
      _postSigned(
        ledger,
        each,
        AccountKind.investments,
        AccountKind.equity,
        value,
      );
      each.injected += value;
    }
  } else {
    // Sideways: its new parent buys it from the old at that.
    if (under.accounts[AccountKind.cash] < value) {
      return Refusal('notEnoughCashIn', amount: value);
    }
    if (value > Money.zero) {
      ledger.pay(
        payer: under,
        payerAccount: AccountKind.investments,
        payee: from,
        payeeAccount: AccountKind.investments,
        amount: value,
        reason: EntryReason.restructuring,
      );
    }
  }
  company.parent = under?.id;
  return null;
}

/// The balance-sheet accounts a merger hands over.
const _carried = [
  AccountKind.inventory,
  AccountKind.receivables,
  AccountKind.businessAssets,
  AccountKind.investments,
  AccountKind.payables,
  AccountKind.loans,
];

Refusal? _mergeCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  MergeCompany command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final (into, intoError) = _ownedCompany(world, command.actor, command.into);
  if (into == null) return intoError;
  if (into.id == company.id) return const Refusal('sameCompany');
  for (final each in [company, into]) {
    final shared = _sharedRefusal(world, each);
    if (shared != null) return shared;
  }
  final up = company.parent == into.id;
  if (!up && company.parent != into.parent) {
    return const Refusal('mergeWhere');
  }
  if (holdsSoftware(world, company.id) && holdsSoftware(world, into.id)) {
    return const Refusal('hasSoftware');
  }
  final kept = company.accounts.retainedEarnings;
  final rate = _dividendRate(world, content, command.actor);
  final tax = up && kept > Money.zero ? kept.times(rate) : Money.zero;
  if (into.accounts[AccountKind.cash] + company.accounts[AccountKind.cash] <
      tax) {
    return const Refusal('notEnoughCashForTax');
  }
  // What it has and owes, into the other's books; what it kept arrives
  // apart from the other's profit, as dividends received.
  final cash = company.accounts[AccountKind.cash];
  if (cash > Money.zero) {
    ledger.pay(
      payer: company,
      payerAccount: AccountKind.equity,
      payee: into,
      payeeAccount: AccountKind.dividendsReceived,
      amount: cash,
      reason: EntryReason.restructuring,
    );
  }
  for (final kind in _carried) {
    final balance = company.accounts[kind];
    _postSigned(ledger, company, AccountKind.equity, kind, balance);
    _postSigned(ledger, into, kind, AccountKind.dividendsReceived, balance);
  }
  final capital = company.injected;
  if (up) {
    // The parent's stake in it gives way to what it held.
    _postSigned(
      ledger,
      into,
      AccountKind.dividendsReceived,
      AccountKind.investments,
      capital,
    );
    _taxUp(world, ledger, into, kept, rate);
  } else {
    // Beside it: its capital becomes the other's, held by the same parent.
    _postSigned(
      ledger,
      into,
      AccountKind.dividendsReceived,
      AccountKind.equity,
      capital,
    );
    into.injected += capital;
  }
  // All it held follows: its businesses, subsidiaries, shares and debts.
  for (final key in businessKeysOf(world, content, company.id)) {
    final parts = businessParts(world, content, company.id, key);
    _hand(world, parts, company, into);
    _briefFor(into, company, key);
  }
  for (final other in world.companies) {
    if (other.parent == company.id) other.parent = into.id;
  }
  for (final holding in world.stocks?.holdings ?? const <Holding>[]) {
    if (holding.owner == company.id.index) holding.owner = into.id.index;
  }
  for (final loan in world.loans) {
    if (loan.company == company.id) loan.company = into.id;
  }
  into.payables.addAll(company.payables);
  company.payables.clear();
  company
    ..status = CompanyStatus.merged
    ..mergedInto = into.id
    ..director = null
    ..injected = Money.zero;
  return null;
}

/// Sells a business on the spot, each part to its buyer at its asking price
/// (see [businessSale]): shops asleep to their district's own shopkeepers,
/// plants to a rival producer who takes on their contracts. The money is
/// the company's, a gain taxed with its profit.
Refusal? _sellBusiness(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  SellBusiness command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final parts = businessParts(world, content, company.id, command.business);
  if (parts.isEmpty) return const Refusal('noSuchBusiness');
  if (!businessSale(world, content, parts).buyer) {
    return const Refusal('noBuyer');
  }
  for (final store in parts.stores) {
    sellToBestBuyer(world, content, ledger, store);
  }
  final month = monthsSinceStart(content, world.today);
  for (final (district, shop) in parts.sleeping) {
    final price =
        valueSleepingShop(
          world,
          content,
          sitesOf(world, content, district)[shop.site],
          shop,
          month,
          country: content.neighbourhoods[district.row].country,
        )?.price ??
        Money.zero;
    if (price > Money.zero) {
      ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.disposals,
        amount: price,
        reason: EntryReason.storeSale,
      );
    }
    shop
      ..company = null
      ..brand = null
      ..acquiredMonth = month;
  }
  if (world.national case final national?) {
    for (final (i, block) in parts.blocks) {
      final country = national.countries[i];
      final value = valueBlock(content, national, country, block);
      if (value == null) continue;
      final buyer = nationalBuyer(national, country, block, value.price);
      if (buyer == null) continue;
      _sellBlock(
        world,
        ledger,
        national,
        i,
        block,
        company,
        buyer,
        value.price,
      );
    }
  }
  for (final factory in parts.plants) {
    final price = valueFactory(world, content, factory)?.price ?? Money.zero;
    if (price > Money.zero) {
      ledger.pay(
        payer: world.elsewhere,
        payerAccount: AccountKind.spending,
        payee: company,
        payeeAccount: AccountKind.disposals,
        amount: price,
        reason: EntryReason.storeSale,
      );
    }
    // Its buyer takes on what it supplies chains.
    for (final contract in world.contracts) {
      if (contract.factory == factory.id) contract.ended = true;
    }
    factory.status = FactoryStatus.closed;
  }
  if (parts.software case final software?) {
    final rival = softwareBuyer(world)!;
    sellSoftwareBusiness(
      world,
      ledger,
      software,
      SoftwareOffer(
        rival: rival.id,
        price: softwareWorth(
          world,
          content,
          content.software!,
          software,
        ).business,
        expires: world.today,
      ),
    );
  }
  return null;
}

Refusal? _sellCompany(
  WorldState world,
  ContentDb content,
  Ledger ledger,
  SellCompany command,
) {
  final (company, error) = _ownedCompany(world, command.actor, command.company);
  if (company == null) return error;
  final (:buyer, :price, :refusal) = companySale(world, content, company);
  if (refusal != null || buyer == null) {
    return refusal == 'nothingForSale'
        ? _nothingForSale
        : Refusal(refusal ?? 'noBuyer');
  }
  if (company.parent case final id?) {
    // A subsidiary's price goes to its parent, a gain taxed with its profit.
    final parent = world.companies[id.index];
    ledger.pay(
      payer: buyer,
      payerAccount: AccountKind.investments,
      payee: parent,
      payeeAccount: AccountKind.disposals,
      amount: price,
      reason: EntryReason.companySale,
    );
    _postSigned(
      ledger,
      parent,
      AccountKind.disposals,
      AccountKind.investments,
      company.injected,
    );
    company
      ..owner = buyer.id
      ..parent = null
      ..injected = price;
  } else {
    transferCompany(world, content, ledger, company, buyer, price);
  }
  company.director = null;
  return null;
}
