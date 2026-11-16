# Where to find X

Paths are relative to the repo root; search the named symbol in the file.
`engine/` stands for [packages/engine/lib/src](../packages/engine/lib/src).

## Rules of the economy

| I want to change… | Look in | Symbol |
|---|---|---|
| How households pick a shop and fill a basket | [engine/systems/demand.dart](../packages/engine/lib/src/systems/demand.dart) | `DemandSystem` |
| Demand tuning (loyalty, loss aversion, marketing pull) | [prototype.json](../content/scenarios/prototype.json) `demand`; [content_db.dart](../packages/engine/lib/src/content/content_db.dart) | `DemandTuning` |
| Deliveries, stockroom space | [engine/systems/logistics.dart](../packages/engine/lib/src/systems/logistics.dart) | `LogisticsSystem` |
| Wages, rent, overheads, loan installments, paying bills | [engine/systems/settlement.dart](../packages/engine/lib/src/systems/settlement.dart) | `SettlementSystem` |
| Liquidation | [engine/systems/solvency.dart](../packages/engine/lib/src/systems/solvency.dart), [engine/commands/transfers.dart](../packages/engine/lib/src/commands/transfers.dart) | `SolvencySystem`, `sellToBestBuyer` |
| The cycle, inflation, the central bank, unemployment | [engine/systems/macro.dart](../packages/engine/lib/src/systems/macro.dart), [engine/state/macro.dart](../packages/engine/lib/src/state/macro.dart) | `MacroSystem`, `MacroState` |
| Population growth, the census | [engine/systems/population.dart](../packages/engine/lib/src/systems/population.dart) | `PopulationSystem` |
| A store's reputation | [engine/systems/close.dart](../packages/engine/lib/src/systems/close.dart) | `CloseSystem` |
| Corporate and dividend tax | [engine/systems/taxes.dart](../packages/engine/lib/src/systems/taxes.dart), [engine/state/taxation.dart](../packages/engine/lib/src/state/taxation.dart) | `TaxSystem`, `companyTaxes` |
| What the bank lends, and at what rate | [engine/state/credit.dart](../packages/engine/lib/src/state/credit.dart) | `companyEarnings`, `earningsRoom`, `guaranteeRoom`, `lendingRate`, `splitLoan` |
| Asking prices of stores, companies, factories | [engine/state/valuation.dart](../packages/engine/lib/src/state/valuation.dart) | `valueStore`, `companyPrice`, `valueFactory` |
| Prices of national chains and blocks | [engine/state/national_value.dart](../packages/engine/lib/src/state/national_value.dart) | `valueChain`, `valueBlock` |
| Buying terms | [engine/state/buying_terms.dart](../packages/engine/lib/src/state/buying_terms.dart) | `buyingDiscount` |
| Districts asleep, by formula | [engine/systems/sleepers.dart](../packages/engine/lib/src/systems/sleepers.dart) | `SleeperSystem` |
| Countries by formula | [engine/countries/country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart), [engine/systems/national.dart](../packages/engine/lib/src/systems/national.dart) | `CountryEconomy`, `currentNational`, `NationalSystem` |
| Factories | [engine/state/factory.dart](../packages/engine/lib/src/state/factory.dart), [engine/state/factories.dart](../packages/engine/lib/src/state/factories.dart), [engine/systems/factories.dart](../packages/engine/lib/src/systems/factories.dart) | `Factory`, `factoryFor`, `FactorySystem` |

## Who decides

| I want to change… | Look in | Symbol |
|---|---|---|
| How AI owners run a store | [engine/policies/retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart) | `RetailPolicy`, `StorePlan` |
| Where entrepreneurs and chains open or buy | [engine/policies/entrepreneur_policy.dart](../packages/engine/lib/src/policies/entrepreneur_policy.dart) | `EntrepreneurPolicy` |
| Store managers | [engine/policies/manager.dart](../packages/engine/lib/src/policies/manager.dart) | `manage` |
| Directors, national growth, strain | [engine/policies/director.dart](../packages/engine/lib/src/policies/director.dart), [engine/systems/national.dart](../packages/engine/lib/src/systems/national.dart) | `nationalBudget`, `nationalChainShops`, `_strain` |
| The cash a company keeps aside | [engine/policies/cushion.dart](../packages/engine/lib/src/policies/cushion.dart) | `cashCushion` |
| What an actor may see | [engine/observation/observation.dart](../packages/engine/lib/src/observation/observation.dart) | `observe`, `PublicView`, `Observation` |
| The estimate for a new shop or factory | [engine/observation/outlook.dart](../packages/engine/lib/src/observation/outlook.dart), [engine/observation/factory_outlook.dart](../packages/engine/lib/src/observation/factory_outlook.dart) | `shopOutlook`, `factoryOutlook` |

## Commands, saves, content

| I want to… | Look in | Symbol |
|---|---|---|
| Add or change a command | [engine/commands/command.dart](../packages/engine/lib/src/commands/command.dart), [engine/commands/apply_command.dart](../packages/engine/lib/src/commands/apply_command.dart), [engine.dart](../packages/engine/lib/engine.dart), [app/lib/src/commands.dart](../app/lib/src/commands.dart) | `Command.read`, `applyCommand`, `describeCommand`; checklist in [engine-core.md](engine-core.md) |
| Add a refusal | [engine/commands/refusal.dart](../packages/engine/lib/src/commands/refusal.dart), [content/locales/en.json](../content/locales/en.json) | `Refusal`, `refusals.<key>` |
| Clothing: fashion, clearance | [engine/content/content_db.dart](../packages/engine/lib/src/content/content_db.dart), [engine/state/store.dart](../packages/engine/lib/src/state/store.dart), [engine/policies/retail_policy.dart](../packages/engine/lib/src/policies/retail_policy.dart), [app/lib/src/screens/rails.dart](../app/lib/src/screens/rails.dart) | `Fashion`, `Lot.arrived`, `Stock.fashionOn`, `ClearStock`, `StorePlan.clearance`, `Rails`, `LinesPage` |
| Labs, quality, key people | [engine/state/labs.dart](../packages/engine/lib/src/state/labs.dart), [engine/state/talent.dart](../packages/engine/lib/src/state/talent.dart), [engine/systems/labs.dart](../packages/engine/lib/src/systems/labs.dart) | `LabSystem`, `KeyPerson`, `factoryLead`, `Stock.quality` |
| Software: the market, a team's pace, churn and draw, worth and rounds | [engine/content/software_def.dart](../packages/engine/lib/src/content/software_def.dart), [engine/state/software.dart](../packages/engine/lib/src/state/software.dart), [engine/state/software_rules.dart](../packages/engine/lib/src/state/software_rules.dart), [engine/systems/software.dart](../packages/engine/lib/src/systems/software.dart) | `SoftwareDef`, `Software`, `SoftwareMarket`, `softwareBuildPower`, `softwarePull`, `softwareChurn`, `softwareWorth`, `SoftwareSystem` |
| The stock market: sectors, companies by formula, worth, moods, results, dividends, indices | [content/stocks/companies.json](../content/stocks/companies.json), [engine/content/stocks_def.dart](../packages/engine/lib/src/content/stocks_def.dart), [engine/state/stocks.dart](../packages/engine/lib/src/state/stocks.dart), [engine/systems/stocks.dart](../packages/engine/lib/src/systems/stocks.dart) | `StocksDef`, `ListingDef`, `StockRulesDef`, `StockMarket`, `Listing`, `currentStocks`, `StockMarketSystem`, `stockWorth`, `earningsMultiple` |
| Buying and selling shares, what they are taxed | [engine/commands/stock_trades.dart](../packages/engine/lib/src/commands/stock_trades.dart), [engine/systems/stocks.dart](../packages/engine/lib/src/systems/stocks.dart) | `buyShares`, `sellShares`, `orderValue`, `orderImpact`, `sellHolding` |
| Takeovers, control, raiders, the holding's loans, listing the player's companies | [engine/systems/takeovers.dart](../packages/engine/lib/src/systems/takeovers.dart), [engine/systems/stocks.dart](../packages/engine/lib/src/systems/stocks.dart), [engine/commands/stock_trades.dart](../packages/engine/lib/src/commands/stock_trades.dart) | `openBid`, `closeBids`, `acceptingUnits`, `freeFloatAccepting`, `moveRaiders`, `bidForPlayers`, `payShareLoans`, `loseControl`, `listOwnCompany`, `bidForCompany`, `runListed`, `buyRival`, `sellControlled`, `listCompany` |
| What the player sees of the market | [engine/observation/stocks_view.dart](../packages/engine/lib/src/observation/stocks_view.dart) | `stockMarketView`, `StockView`, `AnalystRating` |
| Factory sizes, tenders, contracts, rival producers, independents | [engine/content/factory_sales_def.dart](../packages/engine/lib/src/content/factory_sales_def.dart), [engine/state/factory_sales.dart](../packages/engine/lib/src/state/factory_sales.dart), [engine/systems/factory_sales.dart](../packages/engine/lib/src/systems/factory_sales.dart), [engine/observation/factory_sales_view.dart](../packages/engine/lib/src/observation/factory_sales_view.dart) | `FactorySizeDef`, `FactoriesDef.sized`, `FactorySalesDef`, `Tender`, `Contract`, `Producer`, `ChainPlant`, `FactorySalesSystem`, `weighBid`, `sellGoods`, `fairPrice`, `mostAccepted`, `retender`, `breakContract`, `FactorySalesView`, `ProducerView` |
| What chains' own plants save them | [engine/systems/national.dart](../packages/engine/lib/src/systems/national.dart), [engine/countries/country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart) | `_ownPlants`, `Chain.ownSaving` |
| Selling a software company, investors' share of payouts | [engine/commands/transfers.dart](../packages/engine/lib/src/commands/transfers.dart), [engine/state/software_rules.dart](../packages/engine/lib/src/state/software_rules.dart) | `sellSoftware`, `payInvestors` |
| What the owner sees of software | [engine/observation/software_view.dart](../packages/engine/lib/src/observation/software_view.dart) | `SoftwareView`, `SoftwareMarketView`, `softwareCandidatesOf` |
| Add saved state, bump the save format | [engine/persistence/state_io.dart](../packages/engine/lib/src/persistence/state_io.dart), [engine/persistence/save_file.dart](../packages/engine/lib/src/persistence/save_file.dart) | `currentStateVersion`, `SaveData` |
| Change how a scenario is read | [engine/content/scenario_loader.dart](../packages/engine/lib/src/content/scenario_loader.dart) | `loadScenario`, `_Node` |
| Add a product, format, city, person | [prototype.json](../content/scenarios/prototype.json) (append at the end), the words in `prototype.<lang>.json` | see [content-and-scenarios.md](content-and-scenarios.md) |
| Bring a grown scenario into an old save | [engine/state/growth.dart](../packages/engine/lib/src/state/growth.dart) | `growWorld` |
| Generate or wake a neighbourhood | [engine/neighbourhoods/neighbourhood_generator.dart](../packages/engine/lib/src/neighbourhoods/neighbourhood_generator.dart), [engine/simulation.dart](../packages/engine/lib/src/simulation.dart) | `withNeighbourhoods`, `withCitiesAsleep`, `Simulation._wake` |
| Start a new game, the holding start | [engine/state/game_start.dart](../packages/engine/lib/src/state/game_start.dart), [engine/state/world_state.dart](../packages/engine/lib/src/state/world_state.dart) | `GameStart.holding`, `WorldState.initial` |
| A new random stream | [engine/core/rng.dart](../packages/engine/lib/src/core/rng.dart) | `RngStream` |
| The state hash | [engine/simulation.dart](../packages/engine/lib/src/simulation.dart) | `stateHash` |
| Debug-build checks | [engine/state/invariants.dart](../packages/engine/lib/src/state/invariants.dart) | `invariantViolations` |

## The app

| I want to change… | Look in | Symbol |
|---|---|---|
| A word the player reads | [content/locales/en.json](../content/locales/en.json), then `fr.json`, `es.json` | the dotted key passed to `tr` |
| A scenario name in a language | [content/scenarios/prototype.fr.json](../content/scenarios/prototype.fr.json) and the others | |
| How numbers and dates read | [app/lib/src/format.dart](../app/lib/src/format.dart), `format` in the locale files | `money`, `percent`, `longDate` |
| The news and what pauses the clock | [app/lib/src/controller.dart](../app/lib/src/controller.dart) | `_news`, `AlertKind`, `pauseOn` |
| Clock speeds | [app/lib/src/controller.dart](../app/lib/src/controller.dart) | `Speed` |
| Net worth, holding profit | [app/lib/src/controller.dart](../app/lib/src/controller.dart) | `netWorth`, `onPaper`, `holdingProfits` |
| A factory's sales desk, bid and contract pages | [app/lib/src/screens/sales_desk.dart](../app/lib/src/screens/sales_desk.dart) | `SalesDeskEntry`, `SalesDeskPage`, `BidPage`, `ContractPage`, `openTendersFor` |
| The Market tab, a sector, a stock, buying and selling, bids, control, listing | [app/lib/src/screens/exchange.dart](../app/lib/src/screens/exchange.dart) | `ExchangeScreen`, `SectorPage`, `StockPage`, `ExchangePage`, `TradePage`, `PortfolioPage`, `BidSection`, `BidPage`, `ControlPage`, `ExchangeEntry`, `ListCompanyPage`, `ownerName` |
| A software company's pages | [app/lib/src/screens/software.dart](../app/lib/src/screens/software.dart) | `SoftwareSection`, `StartSoftwarePage`, `SoftwarePage`, `RaceChart`, `SoftwareFundingPage` |
| Company financials, ROIC | [app/lib/src/financials.dart](../app/lib/src/financials.dart), [app/lib/src/screens/financials.dart](../app/lib/src/screens/financials.dart) | `Financials`, `_fitOut`, `FinancialsSection` |
| A director's letter | [app/lib/src/letters.dart](../app/lib/src/letters.dart) | `memoSentence` |
| Colours, fonts, the ledger look | [app/lib/src/theme.dart](../app/lib/src/theme.dart) | `Ledger`, `gameTheme`, `Ledger.trade` |
| Charts and stamps | [app/lib/src/visuals.dart](../app/lib/src/visuals.dart) | `BarChart`, `TrendChart`, `Stamp` |
| The tab bar, clock bar, alerts | [app/lib/src/home.dart](../app/lib/src/home.dart) | `HomeScreen`, `HomeTab` |
| Starting a first business | [app/lib/src/screens/market.dart](../app/lib/src/screens/market.dart) | `NewBusiness` |
| The country page and its map | [app/lib/src/screens/national.dart](../app/lib/src/screens/national.dart), [app/lib/src/outlines.dart](../app/lib/src/outlines.dart) | `NationalMap`, `_InkMap`, `outlineOf` |
| The main menu and save slots | [app/lib/src/screens/menu.dart](../app/lib/src/screens/menu.dart), [app/lib/src/saves_io.dart](../app/lib/src/saves_io.dart) | `MainMenu`, `FileSaveSlots` |
| Loading the content at start-up | [app/lib/src/app.dart](../app/lib/src/app.dart) | `loadContent`, `openGame` |

## Data and tools

| I want to… | Look in |
|---|---|
| Rebuild the stock market's companies | [content/stocks/build_companies.py](../content/stocks/build_companies.py), then `dart run tool/stock_caps.dart` in `packages/engine` |
| Rebuild country statistics | [content/countries/build_euro.py](../content/countries/build_euro.py), then [build_regions.py](../content/countries/build_regions.py) |
| Refit the formula to the full simulation | [packages/engine/tool/calibrate_countries.dart](../packages/engine/tool/calibrate_countries.dart) |
| Redraw the maps | [content/countries/build_outlines.py](../content/countries/build_outlines.py) |
| Play many seeds headless | [packages/engine/tool/sim.dart](../packages/engine/tool/sim.dart) |
| See where a day's time goes | [packages/engine/tool/profile.dart](../packages/engine/tool/profile.dart) |
| Read why a design is the way it is | [Engine Architecture.md](<../Engine Architecture.md>), section *Decisions to confirm* and the balancing passes |
