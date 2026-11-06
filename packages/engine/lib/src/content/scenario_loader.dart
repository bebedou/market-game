import 'dart:convert';

import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/hash32.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/history.dart' show salesHistoryDays;
import 'content_db.dart';

/// A problem in a scenario file, with the JSON path where it was found.
final class ContentException implements Exception {
  ContentException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() {
    final where = path.isEmpty ? 'the root' : path;
    return 'Invalid scenario at $where: $message';
  }
}

/// Parses and validates a scenario file.
///
/// Decimal values must be JSON strings such as `"0.15"`: JSON numbers with a
/// fraction would become doubles. String IDs become dense integer IDs in file
/// order. Unknown fields are errors, to catch typos.
ContentDb loadScenario(String jsonText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException catch (e) {
    throw ContentException('', 'not valid JSON (${e.message})');
  }
  final root = _Node('', decoded);
  final marketKeys = _Keys();
  final siteKeys = _Keys();
  final categoryKeys = _Keys();
  final productKeys = _Keys();
  final segmentKeys = _Keys();
  final supplierKeys = _Keys();
  final strategyKeys = _Keys();
  final regimeKeys = _Keys();
  final tierKeys = _Keys();
  final gradeKeys = _Keys();
  final directorKeys = _Keys();
  final personKeys = _Keys();
  final companyKeys = _Keys();
  final storeKeys = _Keys();

  final scenarioId = root.string('id');
  final startDay = root.date('startDate');

  final categories = <CategoryDef>[];
  for (final node in root.objects('categories')) {
    final key = node.string('id');
    Diffusion? diffusion;
    if (node.optionalObject('diffusion') case final bass?) {
      diffusion = Diffusion(
        innovation: bass.fraction('innovation'),
        imitation: bass.nonNegativeFx('imitation'),
        launched: bass.date('launched'),
      );
      if (diffusion.innovation == Fx.zero) {
        bass._fail('innovation', 'must be above 0');
      }
      bass.finish();
    }
    categories.add(
      CategoryDef(
        id: CategoryId(categoryKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        diffusion: diffusion,
      ),
    );
    node.finish();
  }

  final products = <ProductDef>[];
  for (final node in root.objects('products')) {
    final key = node.string('id');
    final category = CategoryId(
      categoryKeys.resolve(node.string('category'), node.pathOf('category')),
    );
    final tier = node.choice('tier', ProductTier.values);
    if (products.any((p) => p.category == category && p.tier == tier)) {
      node._fail('tier', 'another product has this category and tier');
    }
    products.add(
      ProductDef(
        id: ProductId(productKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        category: category,
        tier: tier,
        shelfLifeDays: node.optionalPositiveInt('shelfLifeDays'),
        baseCost: node.positiveMoney('baseCost'),
        referencePrice: node.positiveMoney('referencePrice'),
      ),
    );
    node.finish();
  }

  final segments = <SegmentDef>[];
  for (final node in root.objects('segments')) {
    final key = node.string('id');
    final id = SegmentId(segmentKeys.add(key, node.pathOf('id')));
    final responseNode = node.object('missResponses');
    final missResponses = [
      for (final response in MissResponse.values)
        responseNode.fraction(response.name),
    ];
    responseNode.finish();
    if (missResponses.fold(Fx.zero, (sum, odds) => sum + odds) != Fx.one) {
      node._fail('missResponses', 'the odds must add up to 1');
    }
    final dailyUnits = List.filled(categories.length, Fx.zero);
    final premiumShare = List.filled(categories.length, Fx.zero);
    final categoryNode = node.object('categories');
    for (final categoryKey in categoryNode.keys.toList()) {
      final path = categoryNode.pathOf(categoryKey);
      final category = categoryKeys.resolve(categoryKey, path);
      final habits = categoryNode.object(categoryKey);
      dailyUnits[category] = habits.nonNegativeFx('dailyUnits');
      premiumShare[category] = habits.fraction('premiumShare');
      habits.finish();
    }
    for (final category in categories) {
      if (!categoryNode.keys.contains(category.key)) {
        node._fail('categories', 'missing category "${category.key}"');
      }
    }
    categoryNode.finish();
    final slotNode = node.object('slots');
    final slotShares = _perSlot(slotNode, slotNode.fraction, Fx.zero);
    if (slotShares.fold(Fx.zero, (sum, share) => sum + share) != Fx.one) {
      node._fail('slots', 'the shares must add up to 1');
    }
    if (node.has('incomeSpread') &&
        node.fraction('incomeSpread') > Fx.parse('0.9')) {
      node._fail('incomeSpread', 'must be at most 0.9');
    }
    segments.add(
      SegmentDef(
        id: id,
        key: key,
        name: node.string('name'),
        tripIntervalDays: node.positiveInt('tripIntervalDays'),
        priceSensitivity: node.nonNegativeFx('priceSensitivity'),
        convenienceWeight: node.nonNegativeFx('convenienceWeight'),
        loyaltyWeight: node.nonNegativeFx('loyaltyWeight'),
        priceTolerance: node.nonNegativeFx('priceTolerance'),
        wordOfMouth: node.fraction('wordOfMouth'),
        missResponses: List.unmodifiable(missResponses),
        dailyUnits: List.unmodifiable(dailyUnits),
        premiumShare: List.unmodifiable(premiumShare),
        slotShares: List.unmodifiable(slotShares),
        serviceWeight: node.nonNegativeFx('serviceWeight'),
        sizeWeight: node.nonNegativeFx('sizeWeight'),
        incomeSpread: node.has('incomeSpread')
            ? node.fraction('incomeSpread')
            : Fx.zero,
      ),
    );
    node.finish();
  }

  final markets = <MarketDef>[];
  for (final node in root.objects('markets')) {
    final key = node.string('id');
    final id = MarketId(marketKeys.add(key, node.pathOf('id')));
    final households = List.filled(segments.length, 0);
    final householdNode = node.object('households');
    for (final segmentKey in householdNode.keys.toList()) {
      final segment = segmentKeys.resolve(
        segmentKey,
        householdNode.pathOf(segmentKey),
      );
      households[segment] = householdNode.nonNegativeInt(segmentKey);
    }
    householdNode.finish();
    final growth = List.filled(segments.length, Fx.zero);
    if (node.optionalObject('growth') case final growthNode?) {
      for (final segmentKey in growthNode.keys.toList()) {
        final segment = segmentKeys.resolve(
          segmentKey,
          growthNode.pathOf(segmentKey),
        );
        growth[segment] = growthNode.yearlyRate(segmentKey);
      }
      growthNode.finish();
    }
    final agents = node.optionalPositiveInt('agents');
    final total = households.fold(0, (sum, count) => sum + count);
    if (agents != null && agents > total) {
      node._fail('agents', 'at most one cohort per household ($total)');
    }
    markets.add(
      MarketDef(
        id: id,
        key: key,
        name: node.string('name'),
        households: List.unmodifiable(households),
        growth: List.unmodifiable(growth),
        agents: agents,
        priceLevel: node.level('priceLevel'),
        wageLevel: node.level('wageLevel'),
        incomeLevel: node.level('incomeLevel'),
      ),
    );
    node.finish();
  }

  final sites = <SiteDef>[];
  for (final node in root.objects('sites')) {
    final key = node.string('id');
    sites.add(
      SiteDef(
        id: SiteId(siteKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        market: MarketId(
          marketKeys.resolve(node.string('market'), node.pathOf('market')),
        ),
        location: node.fraction('location'),
        rent: node.money('rent'),
        shelfSlots: node.positiveInt('shelfSlots'),
        storageUnits: node.positiveInt('storageUnits'),
        openingCost: node.money('openingCost'),
        buildDays: node.positiveInt('buildDays'),
        area: node.positiveInt('area'),
        maxArea: node.positiveInt('maxArea'),
      ),
    );
    if (sites.last.maxArea < sites.last.area) {
      node._fail('maxArea', 'must be at least the area');
    }
    node.finish();
  }

  final financeNode = root.object('finance');
  final finance = FinanceDef(
    bankReserves: financeNode.money('bankReserves'),
    bankMargin: financeNode.nonNegativeFx('bankMargin'),
    guaranteedSpread: financeNode.nonNegativeFx('guaranteedSpread'),
    unsecuredSpread: financeNode.nonNegativeFx('unsecuredSpread'),
    bankruptcySpread: financeNode.nonNegativeFx('bankruptcySpread'),
    reputationDays: financeNode.nonNegativeInt('reputationDays'),
    maxTermMonths: financeNode.positiveInt('maxTermMonths'),
    guaranteeMultiple: financeNode.nonNegativeFx('guaranteeMultiple'),
    earningsMultiple: financeNode.nonNegativeFx('earningsMultiple'),
    graceDays: financeNode.nonNegativeInt('graceDays'),
  );
  financeNode.finish();

  final demandNode = root.object('demand');
  final demand = DemandTuning(
    neutralLoyalty: demandNode.fraction('neutralLoyalty'),
    loyaltyRate: demandNode.fraction('loyaltyRate'),
    loyaltyDecay: demandNode.fraction('loyaltyDecay'),
    substituteCredit: demandNode.fraction('substituteCredit'),
    maxNeedDays: demandNode.positiveInt('maxNeedDays'),
    offHoursPenalty: demandNode.nonNegativeFx('offHoursPenalty'),
    halfSizeArea: demandNode.positiveInt('halfSizeArea'),
    incomeEffect: demandNode.has('incomeEffect')
        ? demandNode.fraction('incomeEffect')
        : Fx.zero,
    marketingWeight: demandNode.has('marketingWeight')
        ? demandNode.nonNegativeFx('marketingWeight')
        : Fx.zero,
    halfGoodwill: demandNode.has('halfGoodwill')
        ? demandNode.positiveMoney('halfGoodwill')
        : const Money(100000),
    goodwillDecay: demandNode.has('goodwillDecay')
        ? demandNode.fraction('goodwillDecay')
        : const Fx.raw(300),
    lossAversion: demandNode.has('lossAversion')
        ? demandNode.nonNegativeFx('lossAversion')
        : Fx.one,
    reputationWeight: demandNode.has('reputationWeight')
        ? demandNode.nonNegativeFx('reputationWeight')
        : Fx.zero,
    reputationDays: demandNode.has('reputationDays')
        ? demandNode.positiveInt('reputationDays')
        : 365,
    establishedReputation: demandNode.has('establishedReputation')
        ? demandNode.fraction('establishedReputation')
        : Fx.zero,
    openingReputation: demandNode.has('openingReputation')
        ? demandNode.fraction('openingReputation')
        : Fx.zero,
  );
  demandNode.finish();

  final macroNode = root.object('macro');
  final regimes = <RegimeDef>[];
  for (final node in macroNode.objects('regimes')) {
    final key = node.string('id');
    final demandFactor = node.nonNegativeFx('demand');
    regimes.add(
      RegimeDef(
        id: RegimeId(regimeKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        meanMonths: node.positiveInt('meanMonths'),
        inflation: node.fx('inflation'),
        realWageGrowth: node.fx('realWageGrowth'),
        outputGap: node.fx('outputGap'),
        demand: demandFactor,
        premiumShift: node.fx('premiumShift'),
        migration: node.has('migration')
            ? node.yearlyRate('migration')
            : Fx.zero,
      ),
    );
    node.finish();
  }
  if (regimes.isEmpty) macroNode._fail('regimes', 'needs at least one');
  final macro = MacroDef(
    startRegime: RegimeId(
      regimeKeys.resolve(
        macroNode.string('startRegime'),
        macroNode.pathOf('startRegime'),
      ),
    ),
    neutralRate: macroNode.fx('neutralRate'),
    inflationTarget: macroNode.fx('inflationTarget'),
    inflationResponse: macroNode.nonNegativeFx('inflationResponse'),
    gapResponse: macroNode.nonNegativeFx('gapResponse'),
    minRate: macroNode.fx('minRate'),
    retailFeedback: macroNode.fraction('retailFeedback'),
    regimes: List.unmodifiable(regimes),
    labour: _labour(macroNode),
  );
  macroNode.finish();

  final operationsNode = root.object('operations');
  final operations = OperationsDef(
    slotWage: operationsNode.money('slotWage'),
    visitsPerStaff: operationsNode.positiveInt('visitsPerStaff'),
    maxStaffPerSlot: operationsNode.positiveInt('maxStaffPerSlot'),
  );
  operationsNode.finish();

  // Without formats, every store sells everything.
  final formats = <FormatDef>[];
  final formatKeys = _Keys();
  if (!root.has('formats')) {
    formatKeys.add('store', 'formats');
    formats.add(
      FormatDef(
        id: const FormatId(0),
        key: 'store',
        name: 'Store',
        sells: List.filled(categories.length, true),
        fitOut: Fx.one,
        visitsPerStaff: operations.visitsPerStaff,
      ),
    );
  }
  for (final node
      in root.has('formats') ? root.objects('formats') : const <_Node>[]) {
    final key = node.string('id');
    final id = FormatId(formatKeys.add(key, node.pathOf('id')));
    final sells = List.filled(categories.length, false);
    final names = node.strings('categories');
    for (var i = 0; i < names.length; i++) {
      final category = categoryKeys.resolve(
        names[i],
        '${node.pathOf('categories')}[$i]',
      );
      sells[category] = true;
    }
    formats.add(
      FormatDef(
        id: id,
        key: key,
        name: node.string('name'),
        sells: List.unmodifiable(sells),
        fitOut: node.has('fitOut') ? node.nonNegativeFx('fitOut') : Fx.one,
        visitsPerStaff: node.has('visitsPerStaff')
            ? node.positiveInt('visitsPerStaff')
            : operations.visitsPerStaff,
        wageFactor: node.has('wageFactor')
            ? node.nonNegativeFx('wageFactor')
            : Fx.one,
        minArea: node.has('minArea') ? node.nonNegativeInt('minArea') : 0,
        slotBonus: node.has('slotBonus') ? node.nonNegativeInt('slotBonus') : 0,
        storageBonus: node.has('storageBonus')
            ? node.nonNegativeInt('storageBonus')
            : 0,
        overheads: node.has('overheads') ? node.money('overheads') : Money.zero,
      ),
    );
    node.finish();
  }
  for (final category in categories) {
    if (!formats.any((format) => format.sells[category.id.index])) {
      throw ContentException('formats', 'no format sells "${category.key}"');
    }
  }

  final researchTiers = <ResearchTierDef>[];
  for (final node in root.objects('research')) {
    final key = node.string('id');
    researchTiers.add(
      ResearchTierDef(
        id: ResearchTierId(tierKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        cost: node.money('cost'),
        error: node.fraction('error'),
      ),
    );
    node.finish();
  }

  final expansionNode = root.object('expansion');
  final expansion = ExpansionDef(
    stepArea: expansionNode.positiveInt('stepArea'),
    shelfSlots: expansionNode.nonNegativeInt('shelfSlots'),
    storageUnits: expansionNode.nonNegativeInt('storageUnits'),
    costPerSqm: expansionNode.money('costPerSqm'),
    buildDays: expansionNode.positiveInt('buildDays'),
  );
  expansionNode.finish();

  final managersNode = root.object('managers');
  final grades = <ManagerGradeDef>[];
  for (final node in managersNode.objects('grades')) {
    final key = node.string('id');
    grades.add(
      ManagerGradeDef(
        id: ManagerGradeId(gradeKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        skill: node.fraction('skill'),
        salary: node.money('salary'),
      ),
    );
    node.finish();
  }
  final managers = ManagersDef(
    forecastError: managersNode.fraction('forecastError'),
    priceError: managersNode.fraction('priceError'),
    grades: List.unmodifiable(grades),
  );
  managersNode.finish();

  DirectorsDef? directors;
  if (root.optionalObject('directors') case final node?) {
    final grades = <DirectorGradeDef>[];
    for (final grade in node.objects('grades')) {
      final key = grade.string('id');
      grades.add(
        DirectorGradeDef(
          id: DirectorGradeId(directorKeys.add(key, grade.pathOf('id'))),
          key: key,
          name: grade.string('name'),
          skill: grade.fraction('skill'),
          salary: grade.money('salary'),
        ),
      );
      grade.finish();
    }
    directors = DirectorsDef(
      judgmentError: node.fraction('judgmentError'),
      coaching: node.fraction('coaching'),
      grades: List.unmodifiable(grades),
    );
    node.finish();
  }

  final suppliers = <SupplierDef>[];
  for (final node in root.objects('suppliers')) {
    final key = node.string('id');
    final id = SupplierId(supplierKeys.add(key, node.pathOf('id')));
    final carries = List.filled(products.length, false);
    final carried = node.strings('products');
    for (var i = 0; i < carried.length; i++) {
      final path = '${node.pathOf('products')}[$i]';
      carries[productKeys.resolve(carried[i], path)] = true;
    }
    final discounts = <VolumeDiscount>[];
    for (final tier in node.objects('volumeDiscounts', optional: true)) {
      final minUnits = tier.positiveInt('minUnits');
      if (discounts.isNotEmpty && minUnits <= discounts.last.minUnits) {
        tier._fail('minUnits', 'must be larger than the previous tier');
      }
      final discount = tier.fx('discount');
      if (discount.isNegative || discount >= Fx.one) {
        tier._fail('discount', 'must be at least 0 and below 1');
      }
      discounts.add(VolumeDiscount(minUnits: minUnits, discount: discount));
      tier.finish();
    }
    final priceFactor = node.fx('priceFactor');
    if (priceFactor <= Fx.zero) node._fail('priceFactor', 'must be positive');
    suppliers.add(
      SupplierDef(
        id: id,
        key: key,
        name: node.string('name'),
        leadTimeDays: node.positiveInt('leadTimeDays'),
        paymentTermsDays: node.nonNegativeInt('paymentTermsDays'),
        priceFactor: priceFactor,
        minOrderUnits: node.positiveInt('minOrderUnits'),
        volumeDiscounts: List.unmodifiable(discounts),
        carries: List.unmodifiable(carries),
      ),
    );
    node.finish();
  }

  TaxDef? taxes;
  if (root.optionalObject('taxes') case final node?) {
    taxes = TaxDef(
      reducedRate: node.fraction('reducedRate'),
      reducedLimit: node.money('reducedLimit'),
      corporateRate: node.fraction('corporateRate'),
      dividendRate: node.fraction('dividendRate'),
    );
    node.finish();
  }

  AcquisitionDef? acquisitions;
  if (root.optionalObject('acquisitions') case final node?) {
    final capitalization = node.fraction('capitalization');
    if (capitalization == Fx.zero) {
      node._fail('capitalization', 'must be more than 0');
    }
    acquisitions = AcquisitionDef(
      tangibleReturn: node.fraction('tangibleReturn'),
      capitalization: capitalization,
      distressFloor: node.fraction('distressFloor'),
      fittingsLifeDays: node.positiveInt('fittingsLifeDays'),
      fittingsResidual: node.fraction('fittingsResidual'),
      buyerReserve: node.fraction('buyerReserve'),
      intervalDays: node.positiveInt('intervalDays'),
    );
    node.finish();
  }

  final strategies = <StrategyDef>[];
  for (final node in root.objects('strategies')) {
    final key = node.string('id');
    final id = StrategyId(strategyKeys.add(key, node.pathOf('id')));
    final forecastDays = node.positiveInt('forecastDays');
    if (forecastDays > salesHistoryDays) {
      node._fail('forecastDays', 'must be at most $salesHistoryDays');
    }
    final minMarkup = node.nonNegativeFx('minMarkup');
    final markup = node.nonNegativeFx('markup');
    if (markup < minMarkup) node._fail('markup', 'must be at least minMarkup');
    final hours = List.filled(DaySlot.values.length, false);
    final hourNames = node.strings('hours');
    for (var i = 0; i < hourNames.length; i++) {
      final slot = DaySlot.values.where((s) => s.name == hourNames[i]);
      if (slot.isEmpty) {
        throw ContentException(
          '${node.pathOf('hours')}[$i]',
          'expected one of: ${DaySlot.values.map((s) => s.name).join(', ')}',
        );
      }
      hours[slot.single.index] = true;
    }
    final marketPosition = node.fx('marketPosition');
    if (marketPosition <= -Fx.one) {
      node._fail('marketPosition', 'must be above -1');
    }
    strategies.add(
      StrategyDef(
        id: id,
        key: key,
        name: node.string('name'),
        markup: markup,
        minMarkup: minMarkup,
        marketPosition: marketPosition,
        marketWeight: node.fraction('marketWeight'),
        maxPriceStep: node.fraction('maxPriceStep'),
        priceReviewDays: node.positiveInt('priceReviewDays'),
        maxOverpricedShare: node.fraction('maxOverpricedShare'),
        premiumBias: node.nonNegativeFx('premiumBias'),
        assortmentReviewDays: node.positiveInt('assortmentReviewDays'),
        assortmentHysteresis: node.nonNegativeFx('assortmentHysteresis'),
        forecastDays: forecastDays,
        openingForecast: node.nonNegativeFx('openingForecast'),
        safetyDays: node.nonNegativeInt('safetyDays'),
        orderCycleDays: node.positiveInt('orderCycleDays'),
        reserveDays: node.nonNegativeInt('reserveDays'),
        expansionPaybackMonths: node.nonNegativeInt('expansionPaybackMonths'),
        expansionIntervalDays: node.nonNegativeInt('expansionIntervalDays'),
        marginPerHousehold: node.money('marginPerHousehold'),
        hours: List.unmodifiable(hours),
        serviceTarget: node.nonNegativeFx('serviceTarget'),
        openingTraffic: node.nonNegativeInt('openingTraffic'),
        format: switch (node.optionalString('format')) {
          final format? => FormatId(
            formatKeys.resolve(format, node.pathOf('format')),
          ),
          null => const FormatId(0),
        },
        marketingShare: node.has('marketingShare')
            ? node.fraction('marketingShare')
            : Fx.zero,
      ),
    );
    node.finish();
  }

  final persons = <PersonSetup>[];
  for (final node in root.objects('persons')) {
    final key = node.string('id');
    personKeys.add(key, node.pathOf('id'));
    final isPlayer = node.flag('player');
    final strategyKey = node.optionalString('strategy');
    if (isPlayer && strategyKey != null) {
      node._fail('strategy', 'the player has no AI strategy');
    }
    persons.add(
      PersonSetup(
        key: key,
        name: node.string('name'),
        cash: node.money('cash'),
        isPlayer: isPlayer,
        strategy: strategyKey == null
            ? null
            : StrategyId(
                strategyKeys.resolve(strategyKey, node.pathOf('strategy')),
              ),
        local: node.flag('local'),
      ),
    );
    node.finish();
  }
  if (persons.where((person) => person.isPlayer).length != 1) {
    throw ContentException(
      'persons',
      'exactly one person must have "player": true',
    );
  }

  final companies = <CompanySetup>[];
  for (final node in root.objects('companies')) {
    final key = node.string('id');
    companyKeys.add(key, node.pathOf('id'));
    companies.add(
      CompanySetup(
        key: key,
        name: node.string('name'),
        owner: PersonId(
          personKeys.resolve(node.string('owner'), node.pathOf('owner')),
        ),
        cash: node.money('cash'),
      ),
    );
    node.finish();
  }

  final stores = <StoreSetup>[];
  for (final node in root.objects('stores')) {
    final key = node.string('id');
    storeKeys.add(key, node.pathOf('id'));
    final name = node.string('name');
    final company = CompanyId(
      companyKeys.resolve(node.string('company'), node.pathOf('company')),
    );
    final site =
        sites[siteKeys.resolve(node.string('site'), node.pathOf('site'))];
    if (stores.any((store) => store.site == site.id)) {
      node._fail('site', 'another store already trades at "${site.key}"');
    }
    final shelfSlots = site.shelfSlots;
    final staffNode = node.object('staff');
    final staff = _perSlot(staffNode, staffNode.nonNegativeInt, 0);
    for (final slot in DaySlot.values) {
      if (staff[slot.index] > operations.maxStaffPerSlot) {
        staffNode._fail(
          slot.name,
          'at most ${operations.maxStaffPerSlot} staff per slot',
        );
      }
    }
    staffNode.finish();
    final format = switch (node.optionalString('format')) {
      final key? => formats[formatKeys.resolve(key, node.pathOf('format'))],
      null => formats.first,
    };
    final priceNode = node.object('prices');
    final prices = List<Money?>.filled(products.length, null);
    for (final productKey in priceNode.keys.toList()) {
      final product = productKeys.resolve(
        productKey,
        priceNode.pathOf(productKey),
      );
      if (!format.sells[products[product].category.index]) {
        priceNode._fail(productKey, 'a ${format.name} does not sell it');
      }
      prices[product] = priceNode.positiveMoney(productKey);
    }
    priceNode.finish();
    final listed = prices.where((price) => price != null).length;
    if (listed > shelfSlots) {
      node._fail('prices', 'lists $listed products but has $shelfSlots slots');
    }
    stores.add(
      StoreSetup(
        key: key,
        name: name,
        company: company,
        site: site.id,
        prices: List.unmodifiable(prices),
        staff: List.unmodifiable(staff),
        format: format.id,
      ),
    );
    node.finish();
  }
  final neighbourhoods = <NeighbourhoodRow>[];
  for (final node
      in root.has('neighbourhoods')
          ? root.objects('neighbourhoods')
          : const <_Node>[]) {
    final key = node.string('id');
    // Once it has woken, it's among the markets too.
    final woken = node.has('woken') && node.flag('woken');
    if ((!woken && markets.any((market) => market.key == key)) ||
        neighbourhoods.any((row) => row.key == key)) {
      node._fail('id', 'there is already a place called "$key"');
    }
    final households = List.filled(segments.length, 0);
    final householdNode = node.object('households');
    for (final segmentKey in householdNode.keys.toList()) {
      households[segmentKeys.resolve(
        segmentKey,
        householdNode.pathOf(segmentKey),
      )] = householdNode.nonNegativeInt(
        segmentKey,
      );
    }
    householdNode.finish();
    final growth = List.filled(segments.length, Fx.zero);
    if (node.optionalObject('growth') case final growthNode?) {
      for (final segmentKey in growthNode.keys.toList()) {
        growth[segmentKeys.resolve(segmentKey, growthNode.pathOf(segmentKey))] =
            growthNode.yearlyRate(segmentKey);
      }
      growthNode.finish();
    }
    neighbourhoods.add(
      NeighbourhoodRow(
        key: key,
        name: node.string('name'),
        households: List.unmodifiable(households),
        growth: List.unmodifiable(growth),
        priceLevel: node.level('priceLevel'),
        wageLevel: node.level('wageLevel'),
        incomeLevel: node.level('incomeLevel'),
        rent: node.money('rent'),
        typicalArea: node.positiveInt('typicalArea'),
        largestArea: node.positiveInt('largestArea'),
        room: node.positiveInt('room'),
      ),
    );
    node.finish();
  }
  root.finish();

  final structure = <ContentList>[
    for (final (name, keys) in [
      ('markets', markets.map((m) => m.key)),
      ('sites', sites.map((s) => s.key)),
      ('categories', categories.map((c) => c.key)),
      ('formats', formats.map((f) => f.key)),
      ('products', products.map((p) => p.key)),
      ('segments', segments.map((s) => s.key)),
      ('regimes', macro.regimes.map((r) => r.key)),
      ('research', researchTiers.map((t) => t.key)),
      ('managers', managers.grades.map((g) => g.key)),
      ('directors', directors?.grades.map((g) => g.key) ?? const <String>[]),
      ('suppliers', suppliers.map((s) => s.key)),
      ('strategies', strategies.map((s) => s.key)),
      ('persons', persons.map((p) => p.key)),
      ('companies', companies.map((c) => c.key)),
      ('stores', stores.map((s) => s.key)),
    ])
      (name: name, keys: List.unmodifiable(keys)),
  ];
  return ContentDb(
    scenarioId: scenarioId,
    fingerprint: (Hash32()..addBytes(utf8.encode(_canonicalJson(decoded))))
        .finish(),
    structure: List.unmodifiable(structure),
    markets: List.unmodifiable(markets),
    sites: List.unmodifiable(sites),
    categories: List.unmodifiable(categories),
    formats: List.unmodifiable(formats),
    products: List.unmodifiable(products),
    segments: List.unmodifiable(segments),
    demand: demand,
    suppliers: List.unmodifiable(suppliers),
    macro: macro,
    operations: operations,
    researchTiers: List.unmodifiable(researchTiers),
    managers: managers,
    expansion: expansion,
    finance: finance,
    taxes: taxes,
    acquisitions: acquisitions,
    directors: directors,
    strategies: List.unmodifiable(strategies),
    startDay: startDay,
    persons: List.unmodifiable(persons),
    companies: List.unmodifiable(companies),
    stores: List.unmodifiable(stores),
    neighbourhoods: List.unmodifiable(neighbourhoods),
    source: jsonText,
  );
}

/// JSON text with object keys sorted, so the fingerprint ignores formatting
/// and key order. (On the web, `jsonDecode` lists integer-like keys first.)
String _canonicalJson(Object? value) {
  switch (value) {
    case final Map<String, Object?> map:
      final keys = map.keys.toList()..sort();
      final fields = [
        for (final key in keys)
          '${jsonEncode(key)}:${_canonicalJson(map[key])}',
      ];
      return '{${fields.join(',')}}';
    case final List<Object?> list:
      return '[${list.map(_canonicalJson).join(',')}]';
    default:
      return jsonEncode(value);
  }
}

/// Values per [DaySlot] from an object keyed by slot name, [absent] for
/// slots it leaves out.
List<T> _perSlot<T>(_Node node, T Function(String key) read, T absent) {
  final values = List.filled(DaySlot.values.length, absent);
  for (final key in node.keys.toList()) {
    final slot = DaySlot.values.where((s) => s.name == key);
    if (slot.isEmpty) node._fail(key, 'not a slot of the day');
    values[slot.single.index] = read(key);
  }
  return values;
}

/// String IDs of one kind, mapped to dense indexes in order of declaration.
final class _Keys {
  final _indexes = <String, int>{};

  int add(String key, String path) {
    if (_indexes.containsKey(key)) {
      throw ContentException(path, 'duplicate id "$key"');
    }
    return _indexes[key] = _indexes.length;
  }

  int resolve(String key, String path) =>
      _indexes[key] ?? (throw ContentException(path, 'unknown id "$key"'));
}

/// A JSON object being read, which remembers its path for error messages and
/// which fields were read.
final class _Node {
  _Node(this.path, Object? value)
    : _map = switch (value) {
        final Map<String, Object?> map => map,
        _ => throw ContentException(path, 'expected an object'),
      };

  final String path;
  final Map<String, Object?> _map;
  final _read = <String>{};

  Iterable<String> get keys => _map.keys;

  String pathOf(String key) => path.isEmpty ? key : '$path.$key';

  Object? _value(String key) {
    _read.add(key);
    return _map[key];
  }

  Never _fail(String key, String message) =>
      throw ContentException(pathOf(key), message);

  String string(String key) => optionalString(key) ?? _fail(key, 'missing');

  String? optionalString(String key) => switch (_value(key)) {
    final String text => text,
    null => null,
    _ => _fail(key, 'expected a string'),
  };

  bool flag(String key) => switch (_value(key)) {
    null => false,
    final bool value => value,
    _ => _fail(key, 'expected true or false'),
  };

  int? optionalPositiveInt(String key) => switch (_value(key)) {
    null => null,
    final int value when value > 0 => value,
    _ => _fail(key, 'expected a positive whole number'),
  };

  int positiveInt(String key) =>
      optionalPositiveInt(key) ?? _fail(key, 'missing');

  int nonNegativeInt(String key) => switch (_value(key)) {
    final int value when value >= 0 => value,
    null => _fail(key, 'missing'),
    _ => _fail(key, 'expected a whole number, 0 or more'),
  };

  Fx fx(String key) {
    final text = switch (_value(key)) {
      final String text => text,
      null => _fail(key, 'missing'),
      _ => _fail(key, 'expected a decimal string such as "0.05"'),
    };
    try {
      return Fx.parse(text);
    } on FormatException catch (e) {
      _fail(key, e.message);
    }
  }

  Fx nonNegativeFx(String key) {
    final value = fx(key);
    if (value.isNegative) _fail(key, 'must not be negative');
    return value;
  }

  /// A share, rate or probability: a decimal from 0 to 1.
  Fx fraction(String key) {
    final value = fx(key);
    if (value.isNegative || value > Fx.one) _fail(key, 'must be from 0 to 1');
    return value;
  }

  List<String> strings(String key) => switch (_value(key)) {
    final List<Object?> list => [
      for (var i = 0; i < list.length; i++)
        switch (list[i]) {
          final String text => text,
          _ => throw ContentException(
            '${pathOf(key)}[$i]',
            'expected a string',
          ),
        },
    ],
    null => _fail(key, 'missing'),
    _ => _fail(key, 'expected a list'),
  };

  Money money(String key) {
    final text = switch (_value(key)) {
      final String text => text,
      null => _fail(key, 'missing'),
      _ => _fail(key, 'expected a decimal string such as "1.50"'),
    };
    try {
      return Money.parse(text);
    } on FormatException catch (e) {
      _fail(key, e.message);
    }
  }

  Money positiveMoney(String key) {
    final value = money(key);
    if (value <= Money.zero) _fail(key, 'must be positive');
    return value;
  }

  Day date(String key) {
    try {
      return Day.parse(string(key));
    } on FormatException catch (e) {
      _fail(key, e.message);
    }
  }

  T choice<T extends Enum>(String key, List<T> values) {
    final text = string(key);
    for (final value in values) {
      if (value.name == text) return value;
    }
    final allowed = values.map((value) => value.name).join(', ');
    _fail(key, 'expected one of: $allowed');
  }

  _Node object(String key) =>
      _Node(pathOf(key), _value(key) ?? _fail(key, 'missing'));

  _Node? optionalObject(String key) => switch (_value(key)) {
    null => null,
    final value => _Node(pathOf(key), value),
  };

  bool has(String key) => _map.containsKey(key);

  /// A multiplier on the usual, from 0.3 to 3; 1 if missing.
  Fx level(String key) {
    if (!has(key)) return Fx.one;
    final value = fx(key);
    if (value < Fx.parse('0.3') || value > Fx.fromInt(3)) {
      _fail(key, 'must be from 0.3 to 3');
    }
    return value;
  }

  /// A yearly rate of change, either way: a decimal from -0.5 to 0.5.
  Fx yearlyRate(String key) {
    final value = fx(key);
    if (value < Fx.parse('-0.5') || value > Fx.parse('0.5')) {
      _fail(key, 'must be from -0.5 to 0.5');
    }
    return value;
  }

  /// A list of objects. When [optional], a missing list is empty.
  List<_Node> objects(String key, {bool optional = false}) =>
      switch (_value(key)) {
        final List<Object?> list => [
          for (var i = 0; i < list.length; i++)
            _Node('${pathOf(key)}[$i]', list[i]),
        ],
        null when optional => const [],
        null => _fail(key, 'missing'),
        _ => _fail(key, 'expected a list'),
      };

  /// Fails on any field that wasn't read.
  void finish() {
    for (final key in _map.keys) {
      if (!_read.contains(key)) _fail(key, 'unknown field');
    }
  }
}

LabourDef? _labour(_Node macro) {
  final node = macro.optionalObject('labour');
  if (node == null) return null;
  final labour = LabourDef(
    naturalUnemployment: node.fraction('naturalUnemployment'),
    okunCoefficient: node.nonNegativeFx('okunCoefficient'),
    adjustment: node.fraction('adjustment'),
    phillipsSlope: node.nonNegativeFx('phillipsSlope'),
    confidence: node.nonNegativeFx('confidence'),
  );
  if (labour.okunCoefficient == Fx.zero) {
    node._fail('okunCoefficient', 'must be above 0');
  }
  node.finish();
  return labour;
}
