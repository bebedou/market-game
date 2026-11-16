import 'dart:convert';

import '../core/calendar.dart';
import '../core/decimal.dart';
import '../core/fx.dart';
import '../core/hash32.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../state/history.dart' show salesHistoryDays;
import '../countries/country_table.dart';
import 'content_db.dart';
import 'factory_sales_def.dart';
import 'software_def.dart';
import 'stocks_def.dart';
import 'household_demand.dart';

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
///
/// [national] is the countries' national statistics, if the game runs them
/// beside the scenario; a country's `national` must name one of them.
/// [stocks] is the stock market's table (see [StocksDef]), if it has one.
ContentDb loadScenario(
  String jsonText, {
  CountryTable? national,
  String? stocks,
}) {
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
  final countryKeys = _Keys();

  final scenarioId = root.string('id');
  final startDay = root.date('startDate');

  // Countries come first, as places and suppliers name theirs.
  final countries = <CountryDef>[];
  for (final node in root.objects('countries', optional: true)) {
    final key = node.string('id');
    final id = CountryId(countryKeys.add(key, node.pathOf('id')));
    var follows = Fx.one;
    var depth = Fx.one;
    if (node.optionalObject('cycle') case final cycle?) {
      if (cycle.has('follows')) follows = cycle.fraction('follows');
      if (cycle.has('depth')) depth = cycle.nonNegativeFx('depth');
      cycle.finish();
    }
    final service = node.level('service');
    var weight = Fx.one;
    if (node.has('weight')) {
      weight = node.fx('weight');
      if (weight <= Fx.zero) node._fail('weight', 'must be positive');
    }
    countries.add(
      CountryDef(
        id: id,
        key: key,
        name: node.string('name'),
        taxes: switch (node.optionalObject('taxes')) {
          final taxes? => _taxes(taxes),
          null => null,
        },
        follows: follows,
        depth: depth,
        weight: weight,
        service: service,
        names: switch (node.optionalObject('names')) {
          final names? => _placeNames(names),
          null => null,
        },
        national: node.optionalString('national'),
      ),
    );
    node.finish();
  }
  if (countries.isEmpty) countries.add(CountryDef.only);
  if (national != null) {
    for (final (i, country) in countries.indexed) {
      final key = country.national;
      if (key != null && !national.countries.any((c) => c.key == key)) {
        throw ContentException(
          'countries[$i].national',
          'the national table has no country "$key"',
        );
      }
    }
  }

  /// The country [node] names, or the first.
  CountryId countryIn(_Node node) => node.has('country')
      ? CountryId(
          countryKeys.resolve(node.string('country'), node.pathOf('country')),
        )
      : const CountryId(0);

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
    Fashion? fashion;
    if (node.optionalObject('fashion') case final style?) {
      fashion = Fashion(
        freshDays: style.nonNegativeInt('freshDays'),
        fade: style.fraction('fade'),
        premiumFade: style.fraction('premiumFade'),
        floor: style.fraction('floor'),
        clearance: style.fraction('clearance'),
      );
      style.finish();
    }
    categories.add(
      CategoryDef(
        id: CategoryId(categoryKeys.add(key, node.pathOf('id'))),
        key: key,
        name: node.string('name'),
        diffusion: diffusion,
        fashion: fashion,
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
        qualityWeight: node.has('qualityWeight')
            ? node.nonNegativeFx('qualityWeight')
            : Fx.zero,
        fashionWeight: node.has('fashionWeight')
            ? node.fraction('fashionWeight')
            : Fx.one,
      ),
    );
    node.finish();
  }

  // A market's households follow from what it spends on each trade, so
  // markets are made once the formats are read.
  final pendingMarkets =
      <
        ({
          _Node node,
          MarketId id,
          String key,
          String name,
          _Sizing sizing,
          List<Fx> growth,
          int? agents,
          Fx priceLevel,
          Fx wageLevel,
          Fx incomeLevel,
          CountryId country,
        })
      >[];
  for (final node in root.objects('markets')) {
    final key = node.string('id');
    final id = MarketId(marketKeys.add(key, node.pathOf('id')));
    final sizing = _readSizing(node, segmentKeys, segments.length);
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
    pendingMarkets.add((
      node: node,
      id: id,
      key: key,
      name: node.string('name'),
      sizing: sizing,
      growth: List.unmodifiable(growth),
      agents: node.optionalPositiveInt('agents'),
      priceLevel: node.level('priceLevel'),
      wageLevel: node.level('wageLevel'),
      incomeLevel: node.level('incomeLevel'),
      country: countryIn(node),
    ));
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
        edition: node.has('edition') ? node.nonNegativeInt('edition') : 0,
        national: switch (node.optionalObject('national')) {
          final national? => () {
            final sales = national.object('sales');
            final first = sales.money(countries.first.key);
            // Shares by country, those not given as the first country's.
            List<Fx> shares(String key) {
              final node = national.object(key);
              final first = node.fraction(countries.first.key);
              final list = List<Fx>.unmodifiable([
                for (final country in countries)
                  node.has(country.key) ? node.fraction(country.key) : first,
              ]);
              node.finish();
              return list;
            }

            final format = FormatNational(
              fitOut: national.money('fitOut'),
              sales: List.unmodifiable([
                for (final country in countries)
                  sales.has(country.key) ? sales.money(country.key) : first,
              ]),
              staff: shares('staff'),
              premises: shares('premises'),
            );
            sales.finish();
            national.finish();
            return format;
          }(),
          null => null,
        },
      ),
    );
    node.finish();
  }
  for (final category in categories) {
    if (!formats.any((format) => format.sells[category.id.index])) {
      throw ContentException('formats', 'no format sells "${category.key}"');
    }
  }

  // Filled in once the suppliers are read: each country's normal prices.
  late final List<List<Money>> references;
  ({List<int> households, List<Fx> scale}) sized(
    _Sizing sizing, {
    required Fx incomeLevel,
    required Fx priceLevel,
    required CountryId country,
  }) => _resolveSizing(
    sizing,
    segments: segments,
    products: products,
    categories: categories,
    formats: formats,
    formatKeys: formatKeys,
    today: startDay,
    incomeLevel: incomeLevel,
    priceLevel: priceLevel,
    references: references[country.index],
  );
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
          // Without a figure of its own, in proportion to their skill.
          growth: grade.has('growth')
              ? grade.fraction('growth')
              : grade.fraction('skill') * Fx.raw(600),
        ),
      );
      grade.finish();
    }
    directors = DirectorsDef(
      judgmentError: node.fraction('judgmentError'),
      coaching: node.fraction('coaching'),
      grades: List.unmodifiable(grades),
      criticalShare: node.has('criticalShare')
          ? node.fraction('criticalShare')
          : Fx.raw(500),
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
        country: countryIn(node),
      ),
    );
    node.finish();
  }

  FactoriesDef? factories;
  final factoryKeys = _Keys();
  if (root.optionalObject('factories') case final node?) {
    final freight = node.fraction('freight');
    final kinds = <FactoryKindDef>[];
    for (final kind in node.objects('kinds')) {
      final key = kind.string('id');
      kinds.add(
        FactoryKindDef(
          id: FactoryKindId(factoryKeys.add(key, kind.pathOf('id'))),
          key: key,
          name: kind.string('name'),
          category: CategoryId(
            categoryKeys.resolve(
              kind.string('category'),
              kind.pathOf('category'),
            ),
          ),
          buildCost: kind.money('buildCost'),
          buildDays: kind.positiveInt('buildDays'),
          shiftUnits: kind.positiveInt('shiftUnits'),
          shiftWage: kind.money('shiftWage'),
          site: kind.money('site'),
          materials: kind.fraction('materials'),
          leadTimeDays: kind.positiveInt('leadTimeDays'),
          minOrderUnits: kind.positiveInt('minOrderUnits'),
          freight: kind.has('freight') ? kind.fraction('freight') : freight,
          exports: !kind.flag('local'),
        ),
      );
      kind.finish();
    }
    LabsDef? labs;
    if (node.optionalObject('labs') case final lab?) {
      final levels = <TalentLevelDef>[];
      var shares = Fx.zero;
      for (final level in lab.objects('levels')) {
        final share = level.fraction('share');
        shares += share;
        levels.add(
          TalentLevelDef(
            share: share,
            power: level.fx('power'),
            salary: level.money('salary'),
          ),
        );
        level.finish();
      }
      if (shares != Fx.one) lab._fail('levels', 'shares must sum to 1');
      final firstNames = lab.strings('firstNames');
      final lastNames = lab.strings('lastNames');
      if (firstNames.isEmpty) lab._fail('firstNames', 'must not be empty');
      if (lastNames.isEmpty) lab._fail('lastNames', 'must not be empty');
      labs = LabsDef(
        generationWork: lab.money('generationWork'),
        leadHardness: lab.fx('leadHardness'),
        gain: lab.fraction('gain'),
        gainSpread: lab.fraction('gainSpread'),
        saving: lab.fraction('saving'),
        maxSaving: lab.fraction('maxSaving'),
        catchUp: lab.fraction('catchUp'),
        maxBudget: lab.money('maxBudget'),
        maxPeople: lab.positiveInt('maxPeople'),
        candidates: lab.positiveInt('candidates'),
        candidateDays: lab.positiveInt('candidateDays'),
        revealMonths: lab.positiveInt('revealMonths'),
        nationalPull: lab.fx('nationalPull'),
        levels: List.unmodifiable(levels),
        firstNames: List.unmodifiable(firstNames),
        lastNames: List.unmodifiable(lastNames),
      );
      lab.finish();
    }
    final sizes = [
      for (final size in node.objects('sizes', optional: true))
        () {
          final def = FactorySizeDef(
            key: size.string('id'),
            name: size.string('name'),
            capacity: size.nonNegativeFx('capacity'),
            cost: size.nonNegativeFx('cost'),
            wages: size.nonNegativeFx('wages'),
            site: size.nonNegativeFx('site'),
            buildDays: size.nonNegativeInt('buildDays'),
          );
          size.finish();
          return def;
        }(),
    ];
    if (sizes.isNotEmpty && sizes.first.capacity != Fx.one) {
      node._fail('sizes', 'the first must be a workshop, of capacity 1');
    }
    final sales = switch (node.optionalObject('sales')) {
      final sales? => _factorySales(sales, factoryKeys, countryIn),
      null => null,
    };
    factories = FactoriesDef(
      kinds: List.unmodifiable(kinds),
      abroadDays: node.nonNegativeInt('abroadDays'),
      freight: freight,
      paymentTermsDays: node.nonNegativeInt('paymentTermsDays'),
      maxShifts: node.positiveInt('maxShifts'),
      labs: labs,
      sizes: sizes.isEmpty
          ? const [FactorySizeDef.workshop]
          : List.unmodifiable(sizes),
      sales: sales,
    );
    node.finish();
  }

  final software = switch (root.optionalObject('software')) {
    final node? => _software(node, factories?.labs),
    null => null,
  };

  // Places are sized at their country's normal prices, which follow its
  // suppliers' prices.
  references = countryReferences(
    products,
    countries,
    countryCostLevels(products, suppliers, countries),
  );
  final markets = <MarketDef>[];
  for (final pending in pendingMarkets) {
    final (:households, :scale) = sized(
      pending.sizing,
      incomeLevel: pending.incomeLevel,
      priceLevel: pending.priceLevel,
      country: pending.country,
    );
    final total = households.fold(0, (sum, count) => sum + count);
    if (pending.agents case final agents? when agents > total) {
      pending.node._fail('agents', 'at most one cohort per household ($total)');
    }
    markets.add(
      MarketDef(
        id: pending.id,
        key: pending.key,
        name: pending.name,
        households: households,
        growth: pending.growth,
        agents: pending.agents,
        priceLevel: pending.priceLevel,
        wageLevel: pending.wageLevel,
        incomeLevel: pending.incomeLevel,
        scale: scale,
        country: pending.country,
      ),
    );
  }

  final taxes = switch (root.optionalObject('taxes')) {
    final node? => _taxes(node),
    null => null,
  };
  for (final (i, country) in countries.indexed) {
    for (final format in country.names?.shops.keys ?? const <String>[]) {
      formatKeys.resolve(format, 'countries[$i].names.shops.$format');
    }
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

  BuyingTermsDef? buyingTerms;
  if (root.optionalObject('buyingTerms') case final node?) {
    buyingTerms = BuyingTermsDef(
      most: node.fraction('most'),
      half: node.money('half'),
    );
    if (buyingTerms.half <= Money.zero) {
      node._fail('half', 'must be more than 0');
    }
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
        country: node.has('country') ? countryIn(node) : null,
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
    final area = node.has('area') ? node.positiveInt('area') : null;
    if (area != null && (area < site.area || area > site.maxArea)) {
      node._fail('area', 'must be within what "${site.key}" allows');
    }
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
        area: area,
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
    final growth = List.filled(segments.length, Fx.zero);
    if (node.optionalObject('growth') case final growthNode?) {
      for (final segmentKey in growthNode.keys.toList()) {
        growth[segmentKeys.resolve(segmentKey, growthNode.pathOf(segmentKey))] =
            growthNode.yearlyRate(segmentKey);
      }
      growthNode.finish();
    }
    final priceLevel = node.level('priceLevel');
    final incomeLevel = node.level('incomeLevel');
    final (:households, :scale) = sized(
      _readSizing(node, segmentKeys, segments.length),
      incomeLevel: incomeLevel,
      priceLevel: priceLevel,
      country: countryIn(node),
    );
    neighbourhoods.add(
      NeighbourhoodRow(
        key: key,
        name: node.string('name'),
        households: households,
        growth: List.unmodifiable(growth),
        scale: scale,
        priceLevel: priceLevel,
        wageLevel: node.level('wageLevel'),
        incomeLevel: incomeLevel,
        rent: node.money('rent'),
        typicalArea: node.positiveInt('typicalArea'),
        largestArea: node.positiveInt('largestArea'),
        room: node.positiveInt('room'),
        layout: switch (node._value('layout')) {
          null => null,
          final Map<String, Object?> layout => layout,
          _ => node._fail('layout', 'expected an object'),
        },
        country: countryIn(node),
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
      ('countries', countryKeys._indexes.keys),
      ('factories', factoryKeys._indexes.keys),
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
    buyingTerms: buyingTerms,
    directors: directors,
    factories: factories,
    software: software,
    strategies: List.unmodifiable(strategies),
    startDay: startDay,
    persons: List.unmodifiable(persons),
    companies: List.unmodifiable(companies),
    stores: List.unmodifiable(stores),
    neighbourhoods: List.unmodifiable(neighbourhoods),
    countries: List.unmodifiable(countries),
    national: national,
    stocks: stocks == null
        ? null
        : _stocks(
            stocks,
            countries: countryKeys,
            macro: macro,
            national: national,
            gameCountries: countries,
            software: software,
            producers: factories?.sales?.producers ?? const [],
          ),
    source: jsonText,
  );
}

/// The stock market's table: its rules, exchanges, sectors and listed
/// companies, each country named as the scenario names it, and each of the
/// game's own companies by its name in the game.
StocksDef _stocks(
  String text, {
  required _Keys countries,
  required MacroDef macro,
  required CountryTable? national,
  required List<CountryDef> gameCountries,
  required SoftwareDef? software,
  required List<ProducerDef> producers,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw ContentException('stocks', 'not valid JSON (${e.message})');
  }
  final root = _Node('stocks', decoded);
  root.optionalString('about');
  root.nonNegativeInt('year');
  final rulesNode = root.object('rules');
  final moodsNode = rulesNode.object('moods');
  final moods = [
    for (final regime in macro.regimes)
      moodsNode.has(regime.key) ? moodsNode.fx(regime.key) : Fx.zero,
  ];
  moodsNode.finish();
  final ratings = [
    for (final step in rulesNode.strings('ratings')) Fx.parse(step),
  ];
  if (ratings.length != 4) rulesNode._fail('ratings', 'expected four steps');
  for (var i = 1; i < ratings.length; i++) {
    if (ratings[i] <= ratings[i - 1]) {
      rulesNode._fail('ratings', 'must rise step by step');
    }
  }
  final rules = StockRulesDef(
    termPremium: rulesNode.fx('termPremium'),
    equityPremium: rulesNode.nonNegativeFx('equityPremium'),
    inflation: rulesNode.fx('inflation'),
    minEarningsMultiple: rulesNode.nonNegativeFx('minEarningsMultiple'),
    maxEarningsMultiple: rulesNode.nonNegativeFx('maxEarningsMultiple'),
    moods: List.unmodifiable(moods),
    euphoria: rulesNode.nonNegativeFx('euphoria'),
    maxEuphoria: rulesNode.nonNegativeFx('maxEuphoria'),
    marketHalfLife: rulesNode.positiveInt('marketHalfLife'),
    marketSpread: rulesNode.nonNegativeFx('marketSpread'),
    shared: rulesNode.fraction('shared'),
    stockHalfLife: rulesNode.positiveInt('stockHalfLife'),
    stockSpread: rulesNode.nonNegativeFx('stockSpread'),
    reaction: rulesNode.nonNegativeFx('reaction'),
    maxSurprise: rulesNode.nonNegativeFx('maxSurprise'),
    maxMood: rulesNode.nonNegativeFx('maxMood'),
    analystSpread: rulesNode.nonNegativeFx('analystSpread'),
    analystHalfLife: rulesNode.positiveInt('analystHalfLife'),
    analystsFollow: rulesNode.fraction('analystsFollow'),
    ratings: List.unmodifiable(ratings),
    fee: rulesNode.fraction('fee'),
    indexFee: rulesNode.fraction('indexFee'),
    impact: rulesNode.nonNegativeFx('impact'),
    managementChange: rulesNode.fraction('managementChange'),
    managementMargin: rulesNode.nonNegativeFx('managementMargin'),
    managementGrowth: rulesNode.nonNegativeFx('managementGrowth'),
    managementPull: rulesNode.fraction('managementPull'),
    marginSpread: rulesNode.fraction('marginSpread'),
    unprovenMonths: rulesNode.nonNegativeInt('unprovenMonths'),
    chainReserveMonths: rulesNode.nonNegativeInt('chainReserveMonths'),
    producerUse: rulesNode.fraction('producerUse'),
    indexBase: rulesNode.nonNegativeFx('indexBase'),
    offerDays: rulesNode.positiveInt('offerDays'),
    acceptFrom: rulesNode.fx('acceptFrom'),
    acceptSpan: rulesNode.nonNegativeFx('acceptSpan'),
    acceptMost: rulesNode.fraction('acceptMost'),
    squeezeOut: rulesNode.fraction('squeezeOut'),
    raiderStakes: rulesNode.nonNegativeInt('raiderStakes'),
    raiderBuy: rulesNode.fraction('raiderBuy'),
    raiderMaxStake: rulesNode.fraction('raiderMaxStake'),
    raiderBidStake: rulesNode.fraction('raiderBidStake'),
    raiderPremium: rulesNode.nonNegativeFx('raiderPremium'),
    raiderLeverage: rulesNode.nonNegativeFx('raiderLeverage'),
    raiderSell: rulesNode.nonNegativeFx('raiderSell'),
  );
  if (rules.acceptSpan <= Fx.zero) {
    rulesNode._fail('acceptSpan', 'must be above 0');
  }
  if (rules.maxEarningsMultiple <= rules.minEarningsMultiple) {
    rulesNode._fail('maxEarningsMultiple', 'must be above the least');
  }
  rulesNode.finish();

  CountryId countryOf(_Node node) => CountryId(
    countries.resolve(node.string('country'), node.pathOf('country')),
  );

  final exchanges = <ExchangeDef>[];
  for (final node in root.objects('exchanges')) {
    final country = countryOf(node);
    if (exchanges.any((e) => e.country == country)) {
      node._fail('country', 'already has an exchange');
    }
    exchanges.add(
      ExchangeDef(
        country: country,
        name: node.string('name'),
        index: node.string('index'),
      ),
    );
    node.finish();
  }

  final sectorKeys = _Keys();
  final sectors = <SectorDef>[];
  for (final node in root.objects('sectors')) {
    final key = node.string('id');
    sectorKeys.add(key, node.pathOf('id'));
    final name = node.string('name');
    final growth = node.yearlyRate('growth');
    final risk = node.nonNegativeFx('risk');
    final payout = node.fraction('payout');
    final floor = node.nonNegativeFx('floor');
    if (node.optionalObject('output') case final outputNode?) {
      final output = List.filled(gameCountries.length, Money.zero);
      for (final country in outputNode.keys.toList()) {
        final id = countries.resolve(country, outputNode.pathOf(country));
        // Billions of euros a year.
        output[id] = outputNode.money(country).timesInt(1000000000);
      }
      outputNode.finish();
      sectors.add(
        SectorDef(
          key: key,
          name: name,
          margin: node.fx('margin'),
          cycle: node.nonNegativeFx('cycle'),
          leverage: node.nonNegativeFx('leverage'),
          growth: growth,
          risk: risk,
          payout: payout,
          debt: node.fx('debt'),
          floor: floor,
          output: List.unmodifiable(output),
        ),
      );
    } else {
      final trade = node.optionalString('trade');
      final isSoftware = node.flag('software');
      if ((trade == null) == !isSoftware) {
        node._fail('id', 'needs an output, a trade, or software');
      }
      if (trade != null &&
          national != null &&
          !national.trades.any((t) => t.key == trade)) {
        node._fail('trade', 'the national table has no trade "$trade"');
      }
      sectors.add(
        SectorDef(
          key: key,
          name: name,
          // For software: what its rivals keep of their sales before
          // marketing.
          margin: node.has('margin') ? node.fx('margin') : Fx.zero,
          growth: growth,
          risk: risk,
          payout: payout,
          floor: floor,
          trade: trade,
          software: isSoftware,
        ),
      );
    }
    node.finish();
  }

  final tickers = <String>{};
  final listings = <ListingDef>[];
  for (final node in root.objects('companies')) {
    final ticker = node.string('ticker');
    if (!tickers.add(ticker)) {
      node._fail('ticker', 'duplicate ticker "$ticker"');
    }
    final country = countryOf(node);
    if (!exchanges.any((e) => e.country == country)) {
      node._fail('country', 'has no exchange');
    }
    final sector = sectorKeys.resolve(
      node.string('sector'),
      node.pathOf('sector'),
    );
    final def = sectors[sector];
    var kind = ListingKind.formula;
    var link = -1;
    if (node.optionalString('chain') case final name?) {
      kind = ListingKind.chain;
      final key = gameCountries[country.index].national;
      final table = national?.countries.where((c) => c.key == key).firstOrNull;
      link = table?.chains.indexWhere((c) => c.name == name) ?? -1;
      if (link < 0 || table!.chains[link].independent) {
        node._fail('chain', "no chain \"$name\" in its country's table");
      }
      if (def.trade != national!.trades[table.chains[link].trade].key) {
        node._fail('sector', "is not the chain's trade");
      }
    } else if (node.optionalString('software') case final name?) {
      kind = ListingKind.software;
      link =
          software?.rivals.indexWhere((r) => r.name == name && !r.rest) ?? -1;
      if (link < 0) node._fail('software', 'no software rival "$name"');
      if (!def.software) node._fail('sector', 'is not software');
    } else if (node.optionalString('producer') case final name?) {
      kind = ListingKind.producer;
      link = producers.indexWhere((p) => p.name == name);
      if (link < 0) node._fail('producer', 'no producer "$name"');
    } else if (!def.byFormula) {
      node._fail('sector', "is played: name the game's company");
    }
    final formula = kind == ListingKind.formula;
    final cap = switch (node.optionalString('cap')) {
      final text? => Money.parse(text),
      null => null,
    };
    if (cap != null && cap <= Money.zero) node._fail('cap', 'must be positive');
    final shares = node.optionalPositiveInt('shares');
    if (shares != null && shares > maxListedShares) {
      node._fail('shares', 'must be at most $maxListedShares');
    }
    if (formula && (cap == null || shares == null)) {
      node._fail('cap', 'a company by formula needs its cap and shares');
    }
    var management = averageManagement;
    var share = 0;
    var margin = Fx.zero;
    var debt = Fx.zero;
    var growth = Fx.zero;
    if (formula) {
      final grade = node.string('management');
      management = managementGrades.indexOf(grade);
      if (management < 0) {
        node._fail(
          'management',
          'expected one of ${managementGrades.join(', ')}',
        );
      }
      try {
        share = parseDecimal(node.string('share'), 6);
      } on FormatException catch (e) {
        node._fail('share', e.message);
      }
      if (share < 0 || share > 1000000) {
        node._fail('share', 'must be from 0 to 1');
      }
      margin = node.fx('margin');
      debt = node.fx('debt');
      growth = node.yearlyRate('growth');
    }
    final payout = node.optionalString('payout') == null
        ? def.payout
        : node.fraction('payout');
    listings.add(
      ListingDef(
        ticker: ticker,
        name: node.string('name'),
        country: country,
        sector: sector,
        kind: kind,
        link: link,
        share: share,
        cap: cap,
        shares: shares,
        margin: margin,
        debt: debt,
        growth: growth,
        payout: payout,
        management: management,
      ),
    );
    node.finish();
  }
  final raiders = <RaiderDef>[];
  for (final node in root.objects('raiders', optional: true)) {
    raiders.add(
      RaiderDef(
        name: node.string('name'),
        style: node.choice('style', RaiderStyle.values),
        funds: node.positiveMoney('funds'),
      ),
    );
    node.finish();
  }
  root.finish();
  return StocksDef(
    source: text,
    rules: rules,
    exchanges: List.unmodifiable(exchanges),
    sectors: List.unmodifiable(sectors),
    listings: List.unmodifiable(listings),
    raiders: List.unmodifiable(raiders),
  );
}

/// The software market, its people named from the labs' names if it lists
/// none of its own.
SoftwareDef _software(_Node node, LabsDef? labs) {
  final levels = <TalentLevelDef>[];
  var shares = Fx.zero;
  for (final level in node.objects('levels')) {
    final share = level.fraction('share');
    shares += share;
    levels.add(
      TalentLevelDef(
        share: share,
        power: level.nonNegativeFx('power'),
        salary: level.money('salary'),
      ),
    );
    level.finish();
  }
  if (shares != Fx.one) node._fail('levels', 'shares must sum to 1');
  final firstNames = node.has('firstNames')
      ? node.strings('firstNames')
      : labs?.firstNames ?? const <String>[];
  final lastNames = node.has('lastNames')
      ? node.strings('lastNames')
      : labs?.lastNames ?? const <String>[];
  if (firstNames.isEmpty) node._fail('firstNames', 'must not be empty');
  if (lastNames.isEmpty) node._fail('lastNames', 'must not be empty');
  final rivals = <SoftwareRivalDef>[];
  var rivalShares = Fx.zero;
  for (final rival in node.objects('rivals')) {
    final share = rival.fraction('share');
    rivalShares += share;
    rivals.add(
      SoftwareRivalDef(
        name: rival.string('name'),
        share: share,
        lead: rival.fx('lead'),
        price: rival.nonNegativeFx('price'),
        marketing: rival.fraction('marketing'),
        rest: rival.has('rest') && rival.flag('rest'),
      ),
    );
    rival.finish();
  }
  if (rivalShares != Fx.one) node._fail('rivals', 'shares must sum to 1');
  if (rivals.where((r) => r.rest).length != 1 || !rivals.last.rest) {
    node._fail('rivals', 'the last, and only the last, must be the rest');
  }
  final startupNames = node.strings('startupNames');
  if (startupNames.isEmpty) node._fail('startupNames', 'must not be empty');
  final software = SoftwareDef(
    customers: node.positiveInt('customers'),
    price: node.positiveMoney('price'),
    growth: node.fx('growth'),
    cycle: node.nonNegativeFx('cycle'),
    standard: node.nonNegativeFx('standard'),
    rise: node.nonNegativeFx('rise'),
    startGap: node.nonNegativeFx('startGap'),
    launchGap: node.nonNegativeFx('launchGap'),
    progress: node.nonNegativeFx('progress'),
    designerBuild: node.fraction('designerBuild'),
    decay: node.fraction('decay'),
    hardness: node.nonNegativeFx('hardness'),
    appeal: node.nonNegativeFx('appeal'),
    draw: node.nonNegativeFx('draw'),
    drawFloor: node.fx('drawFloor'),
    drawCap: node.fx('drawCap'),
    priceElasticity: node.nonNegativeInt('priceElasticity'),
    churn: node.fraction('churn'),
    churnSteepness: node.nonNegativeFx('churnSteepness'),
    minChurn: node.fraction('minChurn'),
    maxChurn: node.fraction('maxChurn'),
    wordOfMouth: node.money('wordOfMouth'),
    marketingScale: node.positiveMoney('marketingScale'),
    serving: node.fraction('serving'),
    office: node.money('office'),
    maxPeople: node.positiveInt('maxPeople'),
    candidates: node.positiveInt('candidates'),
    candidateDays: node.positiveInt('candidateDays'),
    revealMonths: node.positiveInt('revealMonths'),
    levels: List.unmodifiable(levels),
    firstNames: List.unmodifiable(firstNames),
    lastNames: List.unmodifiable(lastNames),
    baseMultiple: node.nonNegativeFx('baseMultiple'),
    growthMultiple: node.nonNegativeFx('growthMultiple'),
    minMultiple: node.nonNegativeFx('minMultiple'),
    maxMultiple: node.nonNegativeFx('maxMultiple'),
    valuationCycle: node.nonNegativeFx('valuationCycle'),
    teamMonths: node.nonNegativeInt('teamMonths'),
    teamPaceCap: node.nonNegativeFx('teamPaceCap'),
    maxRoundShare: node.fraction('maxRoundShare'),
    roundMonths: node.nonNegativeInt('roundMonths'),
    offerChance: node.fraction('offerChance'),
    offerRevenue: node.money('offerRevenue'),
    minPremium: node.nonNegativeFx('minPremium'),
    maxPremium: node.nonNegativeFx('maxPremium'),
    offerDays: node.positiveInt('offerDays'),
    foundingChance: node.fraction('foundingChance'),
    startupTeam: node.positiveInt('startupTeam'),
    startupMarketing: node.money('startupMarketing'),
    startupPrice: node.nonNegativeFx('startupPrice'),
    foldMonths: node.positiveInt('foldMonths'),
    foldCustomers: node.nonNegativeInt('foldCustomers'),
    startupNames: List.unmodifiable(startupNames),
    paceSpread: node.fraction('paceSpread'),
    response: node.nonNegativeFx('response'),
    rivals: List.unmodifiable(rivals),
  );
  if (software.maxPremium < software.minPremium) {
    node._fail('maxPremium', 'must not be under minPremium');
  }
  if (software.maxChurn < software.minChurn) {
    node._fail('maxChurn', 'must not be under minChurn');
  }
  if (software.drawCap < software.drawFloor) {
    node._fail('drawCap', 'must not be under drawFloor');
  }
  node.finish();
  return software;
}

TaxDef _taxes(_Node node) {
  final taxes = TaxDef(
    reducedRate: node.fraction('reducedRate'),
    reducedLimit: node.money('reducedLimit'),
    corporateRate: node.fraction('corporateRate'),
    dividendRate: node.fraction('dividendRate'),
  );
  node.finish();
  return taxes;
}

PlaceNames _placeNames(_Node node) {
  List<String> words(_Node node, String key) {
    final list = node.strings(key);
    if (list.isEmpty) node._fail(key, 'needs at least one');
    return List.unmodifiable(list);
  }

  final shopsNode = node.object('shops');
  final shops = <String, List<String>>{
    for (final format in shopsNode.keys.toList())
      format: words(shopsNode, format),
  };
  if (shops.isEmpty) node._fail('shops', 'needs at least one format');
  shopsNode.finish();
  final names = PlaceNames(
    first: words(node, 'first'),
    last: words(node, 'last'),
    streets: words(node, 'streets'),
    streetKinds: words(node, 'streetKinds'),
    shops: Map.unmodifiable(shops),
  );
  node.finish();
  return names;
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

/// How a scenario sizes a place: by its market, what it spends a year on each
/// trade's goods, and the mix of who lives there; or, as generated content
/// writes it, by its households by segment and the scale of what they buy of
/// each trade against their habits. Trades are named by any of their formats.
typedef _Sizing = ({
  _Node node,
  List<int>? households,
  Map<String, Fx>? scale,
  Map<String, Money>? market,
  List<Fx>? mix,
});

_Sizing _readSizing(_Node node, _Keys segmentKeys, int segmentCount) {
  final byHouseholds = node.has('households');
  if (byHouseholds == node.has('market')) {
    node._fail(
      'market',
      byHouseholds ? 'give a market or households, not both' : 'missing',
    );
  }
  if (byHouseholds) {
    final households = List.filled(segmentCount, 0);
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
    Map<String, Fx>? scale;
    if (node.optionalObject('scale') case final scaleNode?) {
      scale = {
        for (final trade in scaleNode.keys.toList())
          trade: scaleNode.nonNegativeFx(trade),
      };
      scaleNode.finish();
    }
    return (
      node: node,
      households: households,
      scale: scale,
      market: null,
      mix: null,
    );
  }
  final marketNode = node.object('market');
  final market = <String, Money>{};
  for (final trade in marketNode.keys.toList()) {
    final amount = marketNode.money(trade);
    if (amount.isNegative) marketNode._fail(trade, 'must not be negative');
    market[trade] = amount;
  }
  marketNode.finish();
  final mix = List.filled(segmentCount, Fx.zero);
  final mixNode = node.object('mix');
  for (final segmentKey in mixNode.keys.toList()) {
    mix[segmentKeys.resolve(segmentKey, mixNode.pathOf(segmentKey))] = mixNode
        .fraction(segmentKey);
  }
  mixNode.finish();
  if (mix.every((share) => share == Fx.zero)) {
    node._fail('mix', 'someone must live here');
  }
  return (node: node, households: null, scale: null, market: market, mix: mix);
}

/// A place's households and scale by channel, from [sizing].
({List<int> households, List<Fx> scale}) _resolveSizing(
  _Sizing sizing, {
  required List<SegmentDef> segments,
  required List<ProductDef> products,
  required List<CategoryDef> categories,
  required List<FormatDef> formats,
  required _Keys formatKeys,
  required Day today,
  required Fx incomeLevel,
  required Fx priceLevel,
  required List<Money> references,
}) {
  final channels = formatChannelsOf(formats, categories.length);
  final channelCount = channels.fold(0, (most, c) => c >= most ? c + 1 : most);
  // Each trade named by one of its formats, and given once.
  Map<int, T> byChannel<T>(Map<String, T> values, String field) {
    final result = <int, T>{};
    for (final MapEntry(:key, :value) in values.entries) {
      final path = '${sizing.node.pathOf(field)}.$key';
      final channel = channels[formatKeys.resolve(key, path)];
      if (result.containsKey(channel)) {
        throw ContentException(path, 'this trade is already given');
      }
      result[channel] = value;
    }
    return result;
  }

  if (sizing.households case final households?) {
    final scale = List.filled(channelCount, Fx.one);
    for (final MapEntry(:key, :value) in byChannel(
      sizing.scale ?? const <String, Fx>{},
      'scale',
    ).entries) {
      scale[key] = value;
    }
    return (
      households: List.unmodifiable(households),
      scale: List.unmodifiable(scale),
    );
  }
  final market = byChannel(sizing.market!, 'market');
  final (:households, :scale, :unbought) = placeSize(
    segments,
    products,
    categories,
    formats,
    market: market,
    mix: sizing.mix!,
    incomeLevel: incomeLevel,
    priceLevel: priceLevel,
    today: today,
    references: references,
  );
  if (unbought.isNotEmpty) {
    final trade = sizing.market!.keys.firstWhere(
      (key) => channels[formatKeys.resolve(key, key)] == unbought.first,
    );
    sizing.node._fail('market.$trade', 'nobody here buys from this trade');
  }
  return (households: households, scale: scale);
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

/// How factories sell to other companies, their rival producers' kinds
/// and countries by key.
FactorySalesDef _factorySales(
  _Node node,
  _Keys factoryKeys,
  CountryId Function(_Node node) countryIn,
) {
  List<Fx> fxList(String key) => [
    for (final text in node.strings(key)) Fx.parse(text),
  ];
  final lotShares = fxList('lotShares');
  final floors = fxList('qualityFloors');
  final terms = [
    for (final text in node.strings('termMonths')) int.parse(text),
  ];
  if (lotShares.isEmpty) node._fail('lotShares', 'must not be empty');
  if (floors.isEmpty) node._fail('qualityFloors', 'must not be empty');
  if (terms.isEmpty || terms.any((months) => months <= 0)) {
    node._fail('termMonths', 'must be positive whole months');
  }
  final producers = <ProducerDef>[];
  for (final producer in node.objects('producers')) {
    producers.add(
      ProducerDef(
        name: producer.string('name'),
        kind: FactoryKindId(
          factoryKeys.resolve(producer.string('kind'), producer.pathOf('kind')),
        ),
        country: countryIn(producer),
        lead: producer.fx('lead'),
        discount: producer.fx('discount'),
      ),
    );
    producer.finish();
  }
  final sales = FactorySalesDef(
    producerPrice: node.fraction('producerPrice'),
    tenderChance: node.fraction('tenderChance'),
    lotShares: List.unmodifiable(lotShares),
    termMonths: List.unmodifiable(terms),
    openDays: node.positiveInt('openDays'),
    qualityFloors: List.unmodifiable(floors),
    qualityWeight: node.nonNegativeFx('qualityWeight'),
    shortfallPenalty: node.fraction('shortfallPenalty'),
    reliabilityLoss: node.nonNegativeFx('reliabilityLoss'),
    reliabilityGain: node.fraction('reliabilityGain'),
    reliabilityWeight: node.nonNegativeFx('reliabilityWeight'),
    independentResponse: node.nonNegativeFx('independentResponse'),
    independentMove: node.fraction('independentMove'),
    independentDelivery: node.fraction('independentDelivery'),
    producerSpread: node.fraction('producerSpread'),
    producerPushBack: node.fraction('producerPushBack'),
    minDiscount: node.fx('minDiscount'),
    maxDiscount: node.fx('maxDiscount'),
    resultMonths: node.positiveInt('resultMonths'),
    producers: List.unmodifiable(producers),
    producerCapacity: node.fraction('producerCapacity'),
    capacityGrowth: node.fraction('capacityGrowth'),
    capacityUse: node.fraction('capacityUse'),
    aimPull: node.fraction('aimPull'),
    leadSpread: node.fraction('leadSpread'),
    aimResponse: node.fraction('aimResponse'),
    minAim: node.fx('minAim'),
    maxAim: node.fx('maxAim'),
    plantChance: node.fraction('plantChance'),
    plantShares: List.unmodifiable(fxList('plantShares')),
    plantSpare: node.fraction('plantSpare'),
    plantSaving: node.fraction('plantSaving'),
    plantDiscount: node.fraction('plantDiscount'),
    plantMinGoods: node.money('plantMinGoods'),
    breakMonths: node.nonNegativeInt('breakMonths'),
    breakReliability: node.fraction('breakReliability'),
    drift: node.fraction('drift'),
    answerDays: node.positiveInt('answerDays'),
  );
  node.finish();
  return sales;
}
