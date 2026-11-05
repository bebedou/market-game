import 'package:engine/engine.dart';
import 'package:engine/src/state/world_state.dart';
import 'package:engine/src/systems/logistics.dart';
import 'package:engine/src/systems/macro.dart';
import 'package:engine/src/systems/operations.dart';
import 'package:engine/src/systems/population.dart';
import 'package:engine/src/systems/report.dart';
import 'package:engine/src/systems/close.dart';
import 'package:engine/src/systems/sales.dart';
import 'package:engine/src/systems/settlement.dart';
import 'package:engine/src/systems/solvency.dart';
import 'package:engine/src/systems/spoilage.dart';
import 'package:engine/src/systems/tick_system.dart';

/// A minimal scenario: one market of 60 households of one segment, two milk
/// products, two suppliers, a player and a rival. The rival's store has one
/// slot, for budget milk, and the better location; the fresh supplier only
/// sells budget milk. Their sites are rent-free; a third site, the lane, is
/// vacant and charges rent.
const testScenarioJson = '''
{
  "id": "test",
  "startDate": "2026-01-01",
  "markets": [{ "id": "town", "name": "Town", "households": { "regulars": 60 } }],
  "sites": [
    { "id": "corner", "name": "Corner", "market": "town", "location": "0.50", "rent": "0.00",
      "shelfSlots": 2, "storageUnits": 400, "openingCost": "300.00", "buildDays": 7,
      "area": 100, "maxArea": 140 },
    { "id": "square", "name": "Square", "market": "town", "location": "0.60", "rent": "0.00",
      "shelfSlots": 1, "storageUnits": 200, "openingCost": "300.00", "buildDays": 7,
      "area": 100, "maxArea": 140 },
    { "id": "lane", "name": "Lane", "market": "town", "location": "0.40", "rent": "100.00",
      "shelfSlots": 2, "storageUnits": 300, "openingCost": "250.00", "buildDays": 5,
      "area": 80, "maxArea": 120 }
  ],
  "finance": { "bankReserves": "100000.00", "bankMargin": "0.02", "guaranteedSpread": "0.02",
    "unsecuredSpread": "0.04", "bankruptcySpread": "0.05", "reputationDays": 1825, "maxTermMonths": 60,
    "guaranteeMultiple": "2", "earningsMultiple": "2", "graceDays": 30 },
  "categories": [{ "id": "milk", "name": "Milk" }],
  "products": [
    { "id": "milk_budget", "name": "Value Milk", "category": "milk", "tier": "budget", "shelfLifeDays": 10,
      "baseCost": "0.55", "referencePrice": "0.99" },
    { "id": "milk_premium", "name": "Organic Milk", "category": "milk", "tier": "premium", "shelfLifeDays": 10,
      "baseCost": "1.05", "referencePrice": "1.79" }
  ],
  "segments": [
    { "id": "regulars", "name": "Regulars", "tripIntervalDays": 2,
      "priceSensitivity": "8", "convenienceWeight": "1", "loyaltyWeight": "1",
      "priceTolerance": "0.10", "wordOfMouth": "0.05",
      "missResponses": { "substitute": "0.40", "elsewhere": "0.30", "delay": "0.20", "skip": "0.10" },
      "categories": { "milk": { "dailyUnits": "0.50", "premiumShare": "0.30" } },
      "slots": { "morning": "0.25", "midday": "0.25", "evening": "0.40", "night": "0.10" },
      "serviceWeight": "1", "sizeWeight": "0" }
  ],
  "demand": { "neutralLoyalty": "0.50", "loyaltyRate": "0.20", "loyaltyDecay": "0.05", "substituteCredit": "0.50", "maxNeedDays": 7,
    "offHoursPenalty": "1.5", "halfSizeArea": 100 },
  "macro": { "startRegime": "steady", "neutralRate": "0.03", "inflationTarget": "0",
    "inflationResponse": "1.5", "gapResponse": "0.5", "minRate": "0", "retailFeedback": "0",
    "regimes": [
      { "id": "steady", "name": "Steady", "meanMonths": 12, "inflation": "0", "realWageGrowth": "0",
        "outputGap": "0", "demand": "1", "premiumShift": "0" }
    ] },
  "operations": { "slotWage": "0.00", "visitsPerStaff": 30, "maxStaffPerSlot": 4 },
  "research": [{ "id": "survey", "name": "Survey", "cost": "50.00", "error": "0.10" }],
  "expansion": { "stepArea": 20, "shelfSlots": 1, "storageUnits": 100, "costPerSqm": "10.00",
    "buildDays": 3 },
  "managers": { "forecastError": "0.50", "priceError": "0.20", "grades": [
    { "id": "clerk", "name": "Clerk", "skill": "0.50", "salary": "5.00" },
    { "id": "ace", "name": "Ace", "skill": "1.00", "salary": "9.00" }
  ] },
  "suppliers": [
    { "id": "bulk", "name": "Bulk", "leadTimeDays": 3, "paymentTermsDays": 0, "priceFactor": "1.00", "minOrderUnits": 48,
      "volumeDiscounts": [{ "minUnits": 96, "discount": "0.05" }],
      "products": ["milk_budget", "milk_premium"] },
    { "id": "fresh", "name": "Fresh", "leadTimeDays": 1, "paymentTermsDays": 14, "priceFactor": "1.10", "minOrderUnits": 12,
      "products": ["milk_budget"] }
  ],
  "strategies": [
    { "id": "steady", "name": "Steady", "markup": "0.40", "minMarkup": "0.10",
      "marketPosition": "0", "marketWeight": "0.50", "maxPriceStep": "0.05", "priceReviewDays": 7,
      "maxOverpricedShare": "0.10", "premiumBias": "1", "assortmentReviewDays": 28,
      "assortmentHysteresis": "0.25", "forecastDays": 14, "openingForecast": "10",
      "safetyDays": 2, "orderCycleDays": 3, "reserveDays": 30, "expansionPaybackMonths": 0,
      "expansionIntervalDays": 365, "marginPerHousehold": "0.30",
      "hours": ["morning", "midday", "evening"], "serviceTarget": "1.2", "openingTraffic": 10 }
  ],
  "persons": [
    { "id": "player", "name": "Player", "cash": "1000.00", "player": true },
    { "id": "rival", "name": "Rival", "cash": "2000.00" }
  ],
  "companies": [
    { "id": "player_co", "name": "Player Co", "owner": "player", "cash": "500.00" },
    { "id": "rival_co", "name": "Rival Co", "owner": "rival", "cash": "800.00" }
  ],
  "stores": [
    { "id": "player_store", "name": "Player Store", "company": "player_co", "site": "corner",
      "staff": { "morning": 1, "midday": 1, "evening": 1, "night": 1 },
      "prices": { "milk_budget": "0.95", "milk_premium": "1.69" } },
    { "id": "rival_store", "name": "Rival Store", "company": "rival_co", "site": "square",
      "staff": { "morning": 1, "midday": 1, "evening": 1, "night": 1 },
      "prices": { "milk_budget": "0.99" } }
  ]
}
''';

const player = PersonId(0);
const rival = PersonId(1);
const playerCompany = CompanyId(0);
const playerStore = StoreId(0);
const rivalStore = StoreId(1);
const milkBudget = ProductId(0);
const milkPremium = ProductId(1);
const bulk = SupplierId(0);
const fresh = SupplierId(1);
const regulars = SegmentId(0);
const steady = StrategyId(0);
const corner = SiteId(0);
const square = SiteId(1);
const lane = SiteId(2);

/// A stand-in for real demand: every store sells 10 to 20 units of each
/// product it lists a day, drawn from the keyed RNG, as far as stock allows.
final class ScriptedDemandSystem implements TickSystem {
  const ScriptedDemandSystem();

  static const stream = 999;

  @override
  void run(WorldState world, TickContext context) {
    for (final store in world.stores) {
      final rng = context.rng(stream, store.id.index);
      for (var product = 0; product < store.prices.length; product++) {
        final wanted = 10 + rng.nextInt(11);
        sellUnits(world, context.ledger, store, ProductId(product), wanted);
      }
    }
  }
}

/// The standard pipeline without demand: stock only changes through
/// deliveries, spoilage and delisting.
const quietSystems = <TickSystem>[
  MacroSystem(),
  PopulationSystem(),
  LogisticsSystem(),
  SpoilageSystem(),
  OperationsSystem(),
  SettlementSystem(),
  SolvencySystem(),
  CloseSystem(),
  ReportSystem(),
];

/// The standard pipeline with scripted demand in the demand phase.
const testSystems = <TickSystem>[
  MacroSystem(),
  PopulationSystem(),
  LogisticsSystem(),
  SpoilageSystem(),
  OperationsSystem(),
  ScriptedDemandSystem(),
  SettlementSystem(),
  SolvencySystem(),
  CloseSystem(),
  ReportSystem(),
];

/// Deterministic commands for [day]: regular orders from both suppliers by
/// both owners, price changes, delisting and relisting premium milk, and one
/// command that is always rejected (the player pricing the rival's store).
List<Command> scriptedCommands(Day day) {
  final n = day.number;
  return [
    if (n % 5 == 0)
      PlaceOrder(
        rival,
        store: rivalStore,
        supplier: fresh,
        lines: [(product: milkBudget, quantity: 60)],
      ),
    if (n % 7 == 0)
      PlaceOrder(
        player,
        store: playerStore,
        supplier: bulk,
        lines: [
          (product: milkBudget, quantity: 96),
          (product: milkPremium, quantity: 48),
        ],
      ),
    if (n % 3 == 0)
      PlaceOrder(
        player,
        store: playerStore,
        supplier: fresh,
        lines: [(product: milkBudget, quantity: 24)],
      ),
    if (n % 5 == 0)
      SetPrice(
        player,
        store: playerStore,
        product: milkBudget,
        price: Money(80 + n % 40),
      ),
    if (n % 60 == 0)
      DelistProduct(player, store: playerStore, product: milkPremium),
    if (n % 60 == 30)
      ListProduct(
        player,
        store: playerStore,
        product: milkPremium,
        price: Money(179),
      ),
    if (n % 11 == 0)
      SetPrice(
        player,
        store: rivalStore,
        product: milkBudget,
        price: Money(50),
      ),
  ];
}

/// Advances [simulation] by [days], submitting the scripted commands first.
void runScripted(Simulation simulation, int days) {
  for (var i = 0; i < days; i++) {
    scriptedCommands(simulation.today).forEach(simulation.submit);
    simulation.step();
  }
}
