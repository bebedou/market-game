import 'dart:convert';

import '../content/content_db.dart';
import '../content/scenario_loader.dart';
import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../state/game_start.dart';
import '../state/sleepers.dart';

/// What the generator needs to know of a kind of site.
final class _SiteRule {
  _SiteRule({
    required this.slots,
    required this.storage,
    required String area,
    required String room,
    required String rent,
    required String opening,
  }) : area = Fx.parse(area),
       room = Fx.parse(room),
       rent = Fx.parse(rent),
       opening = Fx.parse(opening);

  final int slots;
  final int storage;

  /// Its area, room to grow, rent per m² and opening cost against a grocer's.
  final Fx area;
  final Fx room;
  final Fx rent;
  final Fx opening;
}

/// What the generator needs to know of a format other than a grocer's, whose
/// shops open only where they pay.
final class _ShopRule {
  _ShopRule({
    required this.format,
    required this.site,
    required this.settledStaff,
    required String spoiled,
  }) : spoiled = Fx.parse(spoiled);

  /// The format, and the strategy of the same name.
  final String format;
  final _SiteRule site;

  /// The staff such a shop settles at, whatever it opens with.
  final int settledStaff;

  /// The share of the goods it buys that it throws away.
  final Fx spoiled;
}

final _foodSite = _SiteRule(
  slots: 4,
  storage: 600,
  area: '0.85',
  room: '0.75',
  rent: '1.05',
  opening: '0.87',
);
final _techSite = _SiteRule(
  slots: 6,
  storage: 800,
  area: '0.90',
  room: '0.85',
  rent: '1.05',
  opening: '1',
);
final _restaurants = [
  _ShopRule(
    format: 'fastfood',
    site: _foodSite,
    settledStaff: 6,
    spoiled: '0.14',
  ),
  _ShopRule(
    format: 'steakhouse',
    site: _foodSite,
    settledStaff: 3,
    spoiled: '0.14',
  ),
  _ShopRule(
    format: 'finedining',
    site: _foodSite,
    settledStaff: 4,
    spoiled: '0.14',
  ),
];
final _electronics = _ShopRule(
  format: 'electronics',
  site: _techSite,
  settledStaff: 3,
  spoiled: '0',
);

/// The staff a shop opens with, per slot, by strategy.
const _openingStaff = {
  'discount': {'morning': 1, 'midday': 2, 'evening': 2},
  'balanced': {'morning': 1, 'midday': 1, 'evening': 2},
  'premium': {'morning': 1, 'midday': 1, 'evening': 2, 'night': 1},
  'fastfood': {'midday': 2, 'evening': 2, 'night': 1},
  'steakhouse': {'midday': 2, 'evening': 3},
  'finedining': {'midday': 3, 'evening': 4},
  'electronics': {'morning': 1, 'midday': 1, 'evening': 1},
};

/// What generated places and people are called: the same in every language,
/// like the scenario's own.
const _streets = [
  'Vivier', 'Servient', 'Brotteaux', 'Garibaldi', 'Dauphiné', 'Moncey', //
  'Lafayette', 'Bellecour', 'Massena', 'Tolozan', 'Gambetta', 'Carnot',
  'Jaurès', 'Voltaire', 'Pasteur', 'Hugo', 'Foch', 'Thiers', 'Mermoz',
  'Sévigné', 'Colbert', 'Diderot', 'Rameau', 'Lamartine', 'Montaigne',
];
const _streetKinds = ['Rue', 'Place', 'Cours', 'Avenue', 'Passage'];
const _shopNames = {
  'grocery': ['Épicerie', 'Marché', 'Halles', 'Comptoir', 'Panier', 'Prix'],
  'supermarket': ['Super', 'Grand Marché'],
  'fastfood': ['Burger', 'Snack', 'Frites'],
  'steakhouse': ['Le Grill', 'La Braise', 'Bœuf'],
  'finedining': ['Table', 'Maison', 'Le Comptoir'],
  'electronics': ['Tech', 'Hi-Fi', 'Mobile'],
};
const _firstNames = [
  'Nadia', 'Marc', 'Sophie', 'Karim', 'Julie', 'Antoine', 'Inès', 'Paul', //
  'Claire', 'Yanis', 'Léa', 'Hugo', 'Camille', 'Omar', 'Anne', 'Louis',
];
const _lastNames = [
  'Moreau', 'Benali', 'Girard', 'Fontaine', 'Roche', 'Lemoine', 'Perrin', //
  'Chevalier', 'Mercier', 'Blanc', 'Garnier', 'Faure', 'Rousset', 'Colin',
];

/// The strategies a neighbourhood's grocers follow in turn.
const _grocerStrategies = ['premium', 'balanced', 'discount'];

const _smallStorage = 800;
final _centre = Fx.parse('0.5');
final _step = Fx.parse('0.05');
final _lowest = Fx.parse('0.35');
final _top = Fx.parse('0.60');
final _shopBottom = Fx.parse('0.40');

final _openingSlope = Fx.parse('0.6');

/// Units of stock per m²: the player starts with a tighter stockroom than
/// a grocer who has been at it for years.
final _grocerStorage = Fx.parse('15');
final _playerStorage = Fx.parse('12.5');

/// Shares of what a shop starts with: of its opening cost for a grocer, and
/// of its fitting out for anyone else.
final _grocerCash = Fx.parse('0.65');
final _shopCash = Fx.parse('0.45');

/// When shops a neighbourhood starts with opened, in months since the game's
/// start.
const _veteran = -36;

/// What an owner holds against their company.
final _ownerCash = Fx.parse('2.3');

/// One more grocer for this much of a neighbourhood's yearly margin on
/// groceries: a rich one can carry more than its households alone would say.
final _marginPerGrocer = Money.parse('400000.00');

/// A shop opens where it should keep this share of its sales.
final _hurdle = Fx.parse('0.08');

/// How far the generator moves a site's area either way, in Fx raw units.
const _areaJitter = 500;

/// [scale] as a place's JSON writes it, by the first format of each channel,
/// leaving out channels at one.
Map<String, String> _scaleJson(ContentDb content, List<Fx> scale) => {
  for (final (channel, value) in scale.indexed)
    if (value != Fx.one)
      content.formats
          .firstWhere(
            (format) => content.formatChannels[format.id.index] == channel,
          )
          .key: value
          .toDecimalString(),
};

/// Reads a hand-made scenario's cities as rows: what the generator is allowed
/// to know of them. No site, shop or owner gets through, only totals.
List<NeighbourhoodRow> rowsFromScenario(ContentDb content) {
  final setup = playerSetup(content);
  final home = setup == null
      ? null
      : content.sites[content.stores[setup.store].site.index].market;
  return [
    for (final market in content.markets)
      () {
        final sites = [
          for (final site in content.sites)
            if (site.market == market.id && site.storageUnits > _smallStorage)
              site,
        ];
        var area = 0;
        var largest = 0;
        var room = 0;
        var rent = Money.zero;
        var weighted = Fx.zero;
        for (final site in sites) {
          area += site.area;
          if (site.area > largest) largest = site.area;
          room += site.maxArea - site.area;
          rent += site.rent;
          weighted += (Fx.one + site.location - _centre).timesInt(site.area);
        }
        return NeighbourhoodRow(
          key: market.key,
          name: market.name,
          households: market.households,
          growth: market.growth,
          scale: market.scale,
          priceLevel: market.priceLevel,
          wageLevel: market.wageLevel,
          incomeLevel: market.incomeLevel,
          rent: Money(mulDivRound(rent.cents, Fx.scale, weighted.raw)),
          typicalArea: mulDivRound(area, 1, sites.length),
          largestArea: largest,
          room: mulDivRound(room, 1, sites.length),
          playerStartsHere: market.id == home,
        );
      }(),
  ];
}

/// [scenarioJson] with its cities replaced by the neighbourhoods [rows] and
/// [seed] generate. Everything else stays: products, households' tastes, the
/// economy, the player, and the owners who hold no store yet.
String generateScenario(
  String scenarioJson,
  List<NeighbourhoodRow> rows, {
  required int seed,
}) {
  final content = loadScenario(scenarioJson);
  final root = jsonDecode(scenarioJson) as Map<String, dynamic>;
  final world = _World(content, root, seed);
  for (final (i, row) in rows.indexed) {
    world.add(i, row);
  }
  return jsonEncode(world.scenario());
}

/// [content] with every city but the one [start] is in, or else the one the
/// player starts in, run by formula: each becomes a row of
/// [ContentDb.neighbourhoods], after those already there, with its own
/// market, sites and stores ([NeighbourhoodRow.layout]); its businesses and
/// their owners stay, to trade there in their books, as a chain does in a
/// district. Returns that content, and [start] for it.
///
/// The player's store moves to [start]'s site if the scenario put it in a
/// city that sleeps, and the company keeps the cash it would have had.
(ContentDb, GameStart?) withCitiesAsleep(
  ContentDb content, {
  GameStart? start,
}) {
  final setup = playerSetup(content);
  final playerSite = setup == null
      ? null
      : content.sites[content.stores[setup.store].site.index];
  final keep = start != null
      ? content.sites[start.site.index].market
      : playerSite?.market ?? const MarketId(0);
  final root = jsonDecode(content.source) as Map<String, dynamic>;
  final figures = rowsFromScenario(content);
  final asleep = {
    for (final market in content.markets)
      if (market.id != keep) market.key,
  };
  final siteMarket = {
    for (final site in content.sites)
      site.key: content.markets[site.market.index].key,
  };
  List<Map<String, dynamic>> list(String name) => [
    for (final item in (root[name] as List?) ?? const [])
      item as Map<String, dynamic>,
  ];
  final markets = list('markets');
  final sites = list('sites');
  final stores = list('stores');
  final rows = <Object?>[...((root['neighbourhoods'] as List?) ?? const [])];
  // The player's store first, if it stood in a city that now sleeps.
  if (setup != null &&
      start != null &&
      playerSite != null &&
      playerSite.market != keep) {
    final json = stores.firstWhere(
      (store) => store['id'] == content.stores[setup.store].key,
    );
    final chosen = content.sites[start.site.index];
    json['site'] = chosen.key;
    final fitOut =
        content.formats[content.stores[setup.store].format.index].fitOut;
    final company = list('companies').firstWhere(
      (company) => company['id'] == content.companies[setup.company].key,
    );
    company['cash'] =
        (Money.parse(company['cash']! as String) +
                playerSite.openingCost.times(fitOut) -
                chosen.openingCost.times(fitOut))
            .toDecimalString();
  }
  for (final market in content.markets) {
    if (!asleep.contains(market.key)) continue;
    final row = figures[market.id.index];
    final own = [
      for (final site in sites)
        if (siteMarket[site['id']] == market.key) site,
    ];
    final ownKeys = {for (final site in own) site['id']};
    rows.add({
      'id': market.key,
      'name': market.name,
      'households': {
        for (final segment in content.segments)
          if (row.households[segment.id.index] > 0)
            segment.key: row.households[segment.id.index],
      },
      'growth': {
        for (final segment in content.segments)
          segment.key: row.growth[segment.id.index].toDecimalString(),
      },
      if (_scaleJson(content, row.scale) case final scale when scale.isNotEmpty)
        'scale': scale,
      'priceLevel': row.priceLevel.toDecimalString(),
      'wageLevel': row.wageLevel.toDecimalString(),
      'incomeLevel': row.incomeLevel.toDecimalString(),
      'rent': row.rent.toDecimalString(),
      'typicalArea': row.typicalArea,
      'largestArea': row.largestArea,
      'room': row.room,
      'layout': {
        'market': markets.firstWhere((json) => json['id'] == market.key),
        'sites': own,
        'stores': [
          for (final store in stores)
            if (ownKeys.contains(store['site'])) store,
        ],
      },
    });
  }
  root
    ..['markets'] = [
      for (final json in markets)
        if (!asleep.contains(json['id'])) json,
    ]
    ..['sites'] = [
      for (final json in sites)
        if (!asleep.contains(siteMarket[json['id']])) json,
    ]
    ..['stores'] = [
      for (final json in stores)
        if (!asleep.contains(siteMarket[json['site']])) json,
    ]
    ..['neighbourhoods'] = rows;
  final asleepContent = loadScenario(jsonEncode(root));
  return (
    asleepContent,
    start == null
        ? null
        : GameStart(
            site: asleepContent.sites
                .firstWhere(
                  (site) => site.key == content.sites[start.site.index].key,
                )
                .id,
            format: start.format,
            name: start.name,
          ),
  );
}

/// A neighbourhood as it stood when the player woke it: which row of
/// [ContentDb.neighbourhoods], on what day, the price index then, and its
/// households and shops as the formula had left them.
typedef WokenNeighbourhood = ({
  int row,
  Day day,
  Fx priceIndex,
  List<int> households,
  List<SleepingShop> shops,
});

/// [content] with the neighbourhoods of [woken] added at the end of its lists:
/// their sites as generated from their rows and [seed], always the same, and
/// their households and shops as they stood.
///
/// A chain's shop there isn't a business of its own: it's handed to
/// [onChain], with its site's key and what it lists and staffs, to become a
/// store of the chain's company; unless [withChains], for a plan to look at,
/// where it's written like any other.
ContentDb withNeighbourhoods(
  ContentDb content,
  List<WokenNeighbourhood> woken, {
  required int seed,
  bool withChains = false,
  ChainShelf? onChain,
}) {
  final root = jsonDecode(content.source) as Map<String, dynamic>;
  final world = _World.adding(content, root, seed)
    ..withChains = withChains
    ..onChain = onChain;
  final rows = root['neighbourhoods'] as List;
  for (final (:row, day: _, :priceIndex, :households, :shops) in woken) {
    (rows[row] as Map<String, dynamic>)['woken'] = true;
    world.add(
      row,
      content.neighbourhoods[row],
      prices: priceIndex,
      households: households,
      shops: shops,
    );
  }
  return loadScenario(jsonEncode(world.scenario()));
}

/// What a chain's shop of a woken district takes up as a store: its site's
/// key, and its prices and staff by [ProductId] and [DaySlot].
typedef ChainShelf =
    void Function(
      SleepingShop shop,
      String siteKey,
      List<Money?> prices,
      List<int> staff,
    );

/// The neighbourhood of [row] as it starts a game, to run by formula.
SleepingNeighbourhood newSleeper(
  ContentDb content,
  int row, {
  required int seed,
}) {
  final world = _World.bare(content, seed)
    ..add(row, content.neighbourhoods[row]);
  return SleepingNeighbourhood(
    row: row,
    households: List.of(content.neighbourhoods[row].households),
    shops: world.planned,
  )..sites = world.plannedSites;
}

/// The sites of the neighbourhood of [row]: always the same from its figures
/// and [seed].
List<PlannedSite> plannedSites(
  ContentDb content,
  int row, {
  required int seed,
}) => (_World.bare(
  content,
  seed,
)..add(row, content.neighbourhoods[row])).plannedSites;

/// A name for a shop of [format] opening later on.
String newShopName(FormatDef format, Rng rng) {
  final kinds = _shopNames[format.key] ?? _shopNames['grocery']!;
  return '${kinds[rng.nextInt(kinds.length)]} '
      '${_streets[rng.nextInt(_streets.length)]}';
}

/// A name for the owner of a shop opening later on.
String newOwnerName(Rng rng) =>
    '${_firstNames[rng.nextInt(_firstNames.length)]} '
    '${_lastNames[rng.nextInt(_lastNames.length)]}';

/// A generated site, before it holds a shop.
final class _Site {
  _Site(this.key, this.number, this.location, this.area, this.slots);

  final String key;
  final int number;
  final Fx location;
  final int area;
  final int slots;
}

final class _World {
  /// A world whose lists start from [root]'s, to add to.
  _World.adding(this.content, this.root, this.seed) {
    markets.addAll(root['markets'] as List);
    sites.addAll(root['sites'] as List);
    stores.addAll(root['stores'] as List);
    companies.addAll(root['companies'] as List);
    persons.addAll(root['persons'] as List);
  }

  /// A world for working out a neighbourhood alone.
  _World.bare(this.content, this.seed) : root = const {};

  /// A world with no cities yet, but for what [generateScenario] keeps.
  _World(this.content, this.root, this.seed) {
    final setup = playerSetup(content);
    if (setup != null) {
      _playerStore = (root['stores'] as List)[setup.store];
      companies.add((root['companies'] as List)[setup.company]);
    }
    final owners = {
      for (final store in content.stores)
        content.companies[store.company.index].owner,
    };
    for (final (i, person) in (root['persons'] as List).indexed) {
      final id = PersonId(i);
      if (id == content.player || !owners.contains(id)) persons.add(person);
    }
  }

  final ContentDb content;
  final Map<String, dynamic> root;
  final int seed;
  Object? _playerStore;

  /// What today's money is worth against the start's.
  Fx _prices = Fx.one;

  /// Where a neighbourhood's names come from, apart from its layout's draws.
  late Rng _names;
  late List<String> _unusedStreets;

  /// A street of this neighbourhood not used yet; after that, one used again.
  String _street() {
    final street = _unusedStreets.removeLast();
    _unusedStreets.insert(0, street);
    return street;
  }

  /// Whether chains' shops are written as businesses of their own, and
  /// where they go otherwise: see [withNeighbourhoods].
  bool withChains = true;
  ChainShelf? onChain;

  /// The latest neighbourhood's sites, and the shops it would start with.
  final plannedSites = <PlannedSite>[];
  final planned = <SleepingShop>[];
  final _sitesHere = <_Site>[];

  final markets = <Object?>[];
  final sites = <Object?>[];
  final stores = <Object?>[];
  final companies = <Object?>[];
  final persons = <Object?>[];

  Map<String, dynamic> scenario() => {
    ...root,
    'markets': markets,
    'sites': sites,
    'stores': stores,
    'companies': companies,
    'persons': persons,
  };

  FormatDef _format(String key) =>
      content.formats.firstWhere((format) => format.key == key);

  StrategyDef _strategy(String key) =>
      content.strategies.firstWhere((strategy) => strategy.key == key);

  /// Adds the neighbourhood of [row]: its layout always as generated, its
  /// [households] and [shops] as given, if they are, or else as it starts.
  void add(
    int index,
    NeighbourhoodRow row, {
    Fx? prices,
    List<int>? households,
    List<SleepingShop>? shops,
  }) {
    _prices = prices ?? Fx.one;
    plannedSites.clear();
    planned.clear();
    _sitesHere.clear();
    final people = households ?? row.households;
    _names = Rng.keyed(seed, RngStream.neighbourhoods, index, 1);
    _unusedStreets = List.of(_streets);
    _shuffle(_unusedStreets, _names);
    if (row.layout case final layout?) {
      _addOwn(row, layout, people);
    } else {
      _addGenerated(index, row, people);
    }
    final here = shops ?? planned;
    for (final shop in here) {
      final channel = content.formatChannels[shop.format.index];
      _emit(
        row,
        shop,
        sharing: shops == null
            ? null
            : here
                  .where(
                    (other) =>
                        content.formatChannels[other.format.index] == channel,
                  )
                  .length,
      );
    }
  }

  /// A place of the game's own, run by formula: its market, sites and shops
  /// as the scenario wrote them, its households as they stand. Its shops are
  /// its businesses', which stay in the game.
  void _addOwn(
    NeighbourhoodRow row,
    Map<String, Object?> layout,
    List<int> people,
  ) {
    // The households it has now, rather than the market it started with.
    markets.add({
      for (final MapEntry(:key, :value)
          in (layout['market']! as Map<String, Object?>).entries)
        if (!const {'market', 'mix', 'households', 'scale'}.contains(key))
          key: value,
      'households': {
        for (final segment in content.segments)
          if (people[segment.id.index] > 0)
            segment.key: people[segment.id.index],
      },
      if (_scaleJson(content, row.scale) case final scale when scale.isNotEmpty)
        'scale': scale,
    });
    final own = [
      for (final site in layout['sites']! as List) site as Map<String, Object?>,
    ];
    for (final (number, json) in own.indexed) {
      sites.add(json);
      final location = Fx.parse(json['location']! as String);
      final area = json['area']! as int;
      final slots = json['shelfSlots']! as int;
      _sitesHere.add(
        _Site(json['id']! as String, number, location, area, slots),
      );
      plannedSites.add(
        PlannedSite(
          number: number,
          location: location,
          rent: Money.parse(json['rent']! as String),
          openingCost: Money.parse(json['openingCost']! as String),
          area: area,
          maxArea: (json['maxArea'] as int?) ?? area,
          shelfSlots: slots,
          name: json['name']! as String,
        ),
      );
    }
    for (final store in layout['stores']! as List) {
      final json = store as Map<String, Object?>;
      final site = own.indexWhere((site) => site['id'] == json['site']);
      final company = content.companies.indexWhere(
        (company) => company.key == json['company'],
      );
      final owner = content.persons[content.companies[company].owner.index];
      final format = _format(
        (json['format'] as String?) ?? content.formats.first.key,
      );
      planned.add(
        SleepingShop(
          site: site,
          format: format.id,
          strategy: owner.strategy ?? _strategy(_usualKey(format)).id,
          name: json['name']! as String,
          owner: owner.name,
          area: (json['area'] as int?) ?? plannedSites[site].area,
          cash: Money.zero,
          ownerCash: Money.zero,
          openedMonth: _veteran,
          enlargedMonth: 0,
          company: CompanyId(company),
        ),
      );
    }
  }

  /// The key of the strategy a shop of [format] follows by default.
  static String _usualKey(FormatDef format) =>
      format.key == 'grocery' || format.key == 'supermarket'
      ? 'balanced'
      : format.key;

  /// A place generated from its figures.
  void _addGenerated(int index, NeighbourhoodRow row, List<int> people) {
    markets.add({
      'id': row.key,
      'name': row.name,
      'households': {
        for (final segment in content.segments)
          if (people[segment.id.index] > 0)
            segment.key: people[segment.id.index],
      },
      'growth': {
        for (final segment in content.segments)
          segment.key: row.growth[segment.id.index].toDecimalString(),
      },
      'agents': _agents(people.fold(0, (sum, count) => sum + count)),
      if (_scaleJson(content, row.scale) case final scale when scale.isNotEmpty)
        'scale': scale,
      'priceLevel': row.priceLevel.toDecimalString(),
      'wageLevel': row.wageLevel.toDecimalString(),
      'incomeLevel': row.incomeLevel.toDecimalString(),
    });
    final rng = Rng.keyed(seed, RngStream.neighbourhoods, index, 0);
    _addGrocers(row, rng);
    _addShops(row, rng);
  }

  /// A cohort stands for a few households, more in a bigger neighbourhood:
  /// fewer cohorts than that and one of them empties a shelf in one trip.
  static int _agents(int households) {
    final wanted = 250 + mulDivRound(households, 11, 100);
    final rounded = mulDivRound(wanted, 1, 50) * 50;
    return rounded > households ? households : rounded;
  }

  void _addGrocers(NeighbourhoodRow row, Rng rng) {
    final total = row.totalHouseholds;
    final balanced = _strategy('balanced');
    var margin = Money.zero;
    for (final product in content.products) {
      if (_format('grocery').sells[product.category.index]) {
        margin += _yearlyMargin(row, product, balanced);
      }
    }
    final grocers = 2 + mulDivRound(margin.cents, 1, _marginPerGrocer.cents);
    final vacant = 2 + mulDivRound(total, 1, 1500);
    final count = grocers + vacant + (row.playerStartsHere ? 1 : 0);
    final ladder = _ladder(count, _top, _shopBottom, rng);
    // The player takes a usual site, as the middle one is.
    var playerAt = -1;
    if (row.playerStartsHere) {
      var nearest = -1;
      for (final (i, location) in ladder.indexed) {
        final gap = (location - _centre).raw.abs();
        if (i > 0 && (nearest < 0 || gap < nearest)) {
          nearest = gap;
          playerAt = i;
        }
      }
    }
    final made = <_Site>[];
    for (final (i, location) in ladder.indexed) {
      final isPlayer = i == playerAt;
      final area = isPlayer
          ? row.typicalArea
          : i == 0
          ? row.largestArea
          : _areaAt(row.typicalArea, location, Fx.one, rng);
      final site = _addSite(
        row,
        made.length,
        isPlayer ? _centre : location,
        area,
        slots: _grocerSlots(area),
        storage: _rounded(
          (isPlayer ? _playerStorage : _grocerStorage)
              .timesInt(area)
              .roundToInt(),
          100,
        ),
        room: row.room,
        rent: Fx.one,
        opening: Fx.one,
        buildDays: 21,
      );
      made.add(site);
    }
    if (playerAt >= 0) {
      stores.add({
        ...(_playerStore! as Map<String, dynamic>),
        'site': made[playerAt].key,
      });
    }
    final supermarket = _format('supermarket');
    final bigEnough = made.first.area >= supermarket.minArea;
    final strategies = List.of(_grocerStrategies);
    _shuffle(strategies, rng);
    if (bigEnough) {
      strategies
        ..remove('discount')
        ..insert(0, 'discount');
    }
    // The player gets a fair start: rivals spread along the ladder rather than
    // holding its best sites, and none of them undercutting.
    final free = [
      for (final (i, site) in made.indexed)
        if (i != playerAt) site,
    ];
    for (var n = 0; n < grocers; n++) {
      final site = playerAt < 0
          ? free[n]
          : free[mulDivRound(n, free.length - 1, grocers - 1)];
      final wanted = strategies[n % strategies.length];
      _addShop(
        row,
        site,
        bigEnough && n == 0 ? supermarket : _format('grocery'),
        _strategy(playerAt >= 0 && wanted == 'discount' ? 'balanced' : wanted),
      );
    }
  }

  /// Shelves for a grocer's site of [area] m².
  static int _grocerSlots(int area) => area < 120
      ? 7
      : area < 150
      ? 8
      : 9;

  void _addShops(NeighbourhoodRow row, Rng rng) {
    final paying = [
      for (final rule in _restaurants)
        if (_pays(row, rule)) rule,
    ];
    _shuffle(paying, rng);
    final ladder = _ladder(paying.length + 1, _top, _shopBottom, rng);
    final grocerSites = sites.where((site) {
      return (site! as Map<String, dynamic>)['market'] == row.key;
    }).length;
    for (final (i, location) in ladder.indexed) {
      final site = _addSite(
        row,
        grocerSites + i,
        location,
        _areaAt(row.typicalArea, location, _foodSite.area, rng),
        slots: _foodSite.slots,
        storage: _foodSite.storage,
        room: _foodSite.room.timesInt(row.room).roundToInt(),
        rent: _foodSite.rent,
        opening: _foodSite.opening,
        buildDays: 28,
      );
      if (i < paying.length) {
        _addShop(
          row,
          site,
          _format(paying[i].format),
          _strategy(paying[i].format),
        );
      }
    }
    if (_pays(row, _electronics)) {
      final location = _top - _step;
      final site = _addSite(
        row,
        grocerSites + ladder.length,
        location,
        _areaAt(row.typicalArea, location, _techSite.area, rng),
        slots: _techSite.slots,
        storage: _techSite.storage,
        room: _techSite.room.timesInt(row.room).roundToInt(),
        rent: _techSite.rent,
        opening: _techSite.opening,
        buildDays: 28,
      );
      _addShop(
        row,
        site,
        _format(_electronics.format),
        _strategy(_electronics.format),
      );
    }
  }

  /// [count] locations from [top] down to [bottom], best first. All but the
  /// best may sit a step off.
  List<Fx> _ladder(int count, Fx top, Fx bottom, Rng rng) {
    final span = top - bottom;
    final ladder = <Fx>[];
    for (var i = 0; i < count; i++) {
      var location = count == 1
          ? top
          : top - Fx.raw(mulDivRound(span.raw, i, count - 1));
      location = Fx.raw(mulDivRound(location.raw, 1, _step.raw) * _step.raw);
      if (i > 0 && rng.nextInt(4) == 0) {
        location = rng.nextInt(2) == 0 ? location + _step : location - _step;
        if (location > top) location = top;
        if (location < _lowest) location = _lowest;
      }
      ladder.add(location);
    }
    return ladder..sort((a, b) => b.raw.compareTo(a.raw));
  }

  /// A site's area: [typical] times [share], more at a better location.
  int _areaAt(int typical, Fx location, Fx share, Rng rng) {
    final jitter = Fx.raw(rng.nextInt(2 * _areaJitter + 1) - _areaJitter);
    final factor = share * (Fx.one + location - _centre) * (Fx.one + jitter);
    return _rounded(factor.timesInt(typical).roundToInt(), 5);
  }

  /// What fitting out a usual site costs here, before its format: it rises
  /// with rents, and a site's size counts against the neighbourhood's usual.
  Money _opening(NeighbourhoodRow row, int area, Fx location, Fx share) {
    final usual = (Money(17000) + row.rent.timesInt(12)).timesInt(120);
    return usual
        .times(Fx.raw(mulDivRound(area, Fx.scale, row.typicalArea)))
        .times(Fx.one + _openingSlope * (location - _centre))
        .times(share);
  }

  _Site _addSite(
    NeighbourhoodRow row,
    int number,
    Fx location,
    int area, {
    required int slots,
    required int storage,
    required int room,
    required Fx rent,
    required Fx opening,
    required int buildDays,
  }) {
    final key = '${row.key}_site_$number';
    final monthly = row.rent
        .timesInt(area)
        .times(Fx.one + location - _centre)
        .times(rent);
    final cost = _opening(row, area, location, opening);
    final street =
        '${_streetKinds[_names.nextInt(_streetKinds.length)]} ${_street()}';
    sites.add({
      'id': key,
      'name': street,
      'market': row.key,
      'location': location.toDecimalString(),
      'rent': _money(monthly, 1000),
      'shelfSlots': slots,
      'storageUnits': storage,
      'openingCost': _money(cost, 100000),
      'buildDays': buildDays,
      'area': area,
      'maxArea': _rounded(area + room, 10),
    });
    final made = _Site(key, number, location, area, slots);
    _sitesHere.add(made);
    plannedSites.add(
      PlannedSite(
        number: number,
        location: location,
        rent: Money(_rounded(monthly.cents, 1000)),
        openingCost: Money(_rounded(cost.cents, 100000)),
        area: area,
        maxArea: _rounded(area + room, 10),
        shelfSlots: slots,
        name: street,
      ),
    );
    return made;
  }

  /// A shop [row] starts with on [site].
  void _addShop(
    NeighbourhoodRow row,
    _Site site,
    FormatDef format,
    StrategyDef strategy,
  ) {
    final opening = _opening(row, site.area, site.location, _siteRule(format));
    final grocer = format.key == 'grocery' || format.key == 'supermarket';
    final cash =
        (grocer
                ? opening.times(_grocerCash)
                : opening.times(format.fitOut).times(_shopCash))
            .times(_prices);
    final kinds = _shopNames[format.key]!;
    final name = '${kinds[_names.nextInt(kinds.length)]} ${_street()}';
    planned.add(
      SleepingShop(
        site: site.number,
        format: format.id,
        strategy: strategy.id,
        name: name,
        owner:
            '${_firstNames[_names.nextInt(_firstNames.length)]} '
            '${_lastNames[_names.nextInt(_lastNames.length)]}',
        area: site.area,
        cash: Money(_rounded(cash.cents, 100000)),
        ownerCash: Money(_rounded(cash.times(_ownerCash).cents, 100000)),
        // They have traded here for years.
        openedMonth: _veteran,
        enlargedMonth: 0,
      ),
    );
  }

  /// Puts [shop] into the scenario, on its site in the neighbourhood of [row].
  /// One that has traded for a while, [sharing] its trade with so many shops,
  /// charges its strategy's markup on what it pays; in a world just begun, with
  /// [sharing] null, shops charge around normal prices and soon move.
  void _emit(NeighbourhoodRow row, SleepingShop shop, {required int? sharing}) {
    final site = _sitesHere[shop.site];
    final format = content.formats[shop.format.index];
    final strategy = content.strategies[shop.strategy.index];
    final key = '${row.key}_${site.number}';
    Money price(ProductDef product) =>
        (sharing != null
                ? _usualCost(
                    row,
                    product,
                    strategy,
                    sharing,
                  ).times(Fx.one + strategy.markup)
                : product.referencePrice.times(
                    Fx.one + strategy.marketPosition,
                  ))
            .times(row.priceLevel)
            .times(_prices);
    final listed = _listing(format, strategy, site.slots);
    if (shop.company != null && !withChains) {
      final staff = _openingStaff[strategy.key] ?? const <String, int>{};
      onChain?.call(
        shop,
        site.key,
        [
          for (final product in content.products)
            listed.contains(product) ? price(product) : null,
        ],
        [for (final slot in DaySlot.values) staff[slot.name] ?? 0],
      );
      return;
    }
    stores.add({
      'id': '${key}_store',
      'name': shop.name,
      'company': '${key}_co',
      'site': site.key,
      'format': format.key,
      if (shop.area != site.area) 'area': shop.area,
      'staff': _openingStaff[strategy.key],
      'prices': {
        for (final product in listed)
          product.key: price(product).toDecimalString(),
      },
    });
    companies.add({
      'id': '${key}_co',
      'name': shop.name,
      'owner': '${key}_owner',
      'cash': _money(shop.cash.isNegative ? Money.zero : shop.cash, 1),
    });
    persons.add({
      'id': '${key}_owner',
      'name': shop.owner,
      'cash': _money(
        shop.ownerCash.isNegative ? Money.zero : shop.ownerCash,
        1,
      ),
      'strategy': strategy.key,
    });
  }

  Fx _siteRule(FormatDef format) => switch (format.key) {
    'grocery' || 'supermarket' => Fx.one,
    'electronics' => _techSite.opening,
    _ => _foodSite.opening,
  };

  /// What a shop lists to start with: everything it sells, as far as the
  /// shelves go, or else the staples, which the scenario lists first, leaving
  /// two slots for the owner to choose. A strategy that favours premium goods takes them first, and
  /// one that doesn't takes each category's cheaper line before any dearer
  /// one.
  List<ProductDef> _listing(FormatDef format, StrategyDef strategy, int slots) {
    final sold = [
      for (final product in content.products)
        if (format.sells[product.category.index]) product,
    ];
    if (sold.length <= slots) return sold;
    int rank(ProductDef product) {
      final premium = product.tier == ProductTier.premium;
      final category = product.category.index;
      if (strategy.premiumBias > Fx.one) {
        return category * 2 + (premium ? 0 : 1);
      }
      if (strategy.premiumBias < Fx.one) {
        return category + (premium ? sold.length : 0);
      }
      return category * 2 + (premium ? 1 : 0);
    }

    sold.sort((a, b) => rank(a).compareTo(rank(b)));
    return sold.sublist(0, slots - 2);
  }

  /// What a shop of [strategy] pays for [product], at a price index of 1, when
  /// [sharing] the trade here with so many: the best any supplier gives for its
  /// usual order.
  Money _usualCost(
    NeighbourhoodRow row,
    ProductDef product,
    StrategyDef strategy,
    int sharing,
  ) {
    var yearly = Fx.zero;
    for (final segment in content.segments) {
      yearly += _yearlyUnits(
        row,
        segment,
        product,
      ).timesInt(row.households[segment.id.index]);
    }
    final order = mulDivRound(
      yearly.raw,
      strategy.orderCycleDays,
      365 * sharing * Fx.scale,
    );
    Money? best;
    for (final supplier in content.suppliers) {
      if (!supplier.carries[product.id.index]) continue;
      final price = supplier.unitPrice(
        product,
        order > supplier.minOrderUnits ? order : supplier.minOrderUnits,
        Fx.one,
      );
      if (best == null || price < best) best = price;
    }
    return best ?? product.baseCost;
  }

  /// What households here would buy of [product] in a year, in units.
  Fx _yearlyUnits(
    NeighbourhoodRow row,
    SegmentDef segment,
    ProductDef product,
  ) {
    final category = product.category.index;
    var units = segment.dailyUnits[category].timesInt(365);
    final adoption = content.categories[category].diffusion?.adoption(
      content.startDay,
    );
    if (adoption != null) units *= adoption;
    units *= row.scaleOf(content.categoryChannels[category]);
    var share = segment.premiumShare[category] * row.incomeLevel;
    if (share > Fx.one) share = Fx.one;
    return units *
        (product.tier == ProductTier.premium ? share : Fx.one - share);
  }

  /// What a shop would earn on [product] in a year here, before its costs.
  Money _yearlyMargin(
    NeighbourhoodRow row,
    ProductDef product,
    StrategyDef strategy,
  ) {
    final unit =
        product.baseCost.times(Fx.one + strategy.markup).times(row.priceLevel) -
        product.baseCost;
    var total = Money.zero;
    for (final segment in content.segments) {
      final households = row.households[segment.id.index];
      if (households == 0) continue;
      total += unit.times(
        _yearlyUnits(row, segment, product).timesInt(households),
      );
    }
    return total;
  }

  /// Whether a shop of [rule] alone here should clear the hurdle: what it
  /// would earn in a year against its staff and premises.
  bool _pays(NeighbourhoodRow row, _ShopRule rule) {
    final format = _format(rule.format);
    final strategy = _strategy(rule.format);
    final area = rule.site.area.timesInt(row.typicalArea).roundToInt();
    var margin = Money.zero;
    var goods = Money.zero;
    for (final product in content.products) {
      if (!format.sells[product.category.index]) continue;
      margin += _yearlyMargin(row, product, strategy);
      for (final segment in content.segments) {
        goods += product.baseCost.times(
          _yearlyUnits(
            row,
            segment,
            product,
          ).timesInt(row.households[segment.id.index]),
        );
      }
    }
    final premises =
        row.rent.timesInt(area).times(rule.site.rent) +
        format.overheadsFor(area);
    final wages = content.operations.slotWage
        .times(row.wageLevel * format.wageFactor)
        .timesInt(rule.settledStaff * 365);
    final profit =
        margin - goods.times(rule.spoiled) - premises.timesInt(12) - wages;
    return profit >= (margin + goods).times(_hurdle);
  }

  void _shuffle<T>(List<T> list, Rng rng) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final swap = list[i];
      list[i] = list[j];
      list[j] = swap;
    }
  }

  static int _rounded(int value, int step) =>
      mulDivRound(value, 1, step) * step;

  /// [amount] to the nearest [cents], as the scenario writes money.
  static String _money(Money amount, int cents) =>
      Money(_rounded(amount.cents, cents)).toDecimalString();
}
