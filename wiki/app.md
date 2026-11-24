# The app

The Flutter app is in [app/](../app), package `market_game`. It runs the
engine on the main isolate (the web has no isolates) and talks to it only
through commands in and observations out. Design detail: *Flutter
integration* in [Engine Architecture.md](<../Engine Architecture.md>).

## Start-up

- [main.dart](../app/lib/main.dart) registers the fonts' licences and runs
  `MarketGameApp`.
- [app.dart](../app/lib/src/app.dart): `MarketGameApp` picks the language
  (the one saved, else the phone's if offered, else English), calls
  `useLanguage`, then `loadContent()`: `loadOutlines()`, then
  `loadScenario(localizedScenario(prototype.json, words), national:
  loadCountryTable(euro.json, calibration.json))`. Asset paths are the
  `scenarioAsset`, `nationalAsset` and `calibrationAsset` constants.
- `openGame(content, store)` loads a slot's save into a
  `SimulationController`, or sets the save aside on a `FormatException`.
- `ScreenMargins` keeps 5% of the screen height clear top and bottom.
- `newSeed()` is the only place a seed comes from the clock.

## `SimulationController`

[controller.dart](../app/lib/src/controller.dart), a `ChangeNotifier` handed
to widgets by `GameScope` (an `InheritedNotifier` in
[widgets.dart](../app/lib/src/widgets.dart); `GameScope.of(context)` to
listen, `GameScope.read(context)` in `initState`).

- **Holds** the `Simulation`, the player's latest `Observation` (`view`),
  pending commands, alerts (up to `alertsKept`, 100) and the clock.
- **Clock.** `Speed` (paused, slow 2 s, normal 1 s, fast 250 ms per day),
  `setSpeed`, `advanceWeek` (seven days fast, then pause). A
  `Timer.periodic` calls `step()`.
- **Pending changes.** `submit` replaces an earlier change to the same thing
  (`_changeKey`) and drops one that changes nothing (`_changesNothing`).
  Getters such as `priceOf`, `staffOf`, `managerOf`, `directorOf`,
  `shiftsOf` show values as they will be tomorrow.
- **Step.** `step()` submits the pending commands, steps the engine, takes a
  new observation, builds news with `_news(result, before, after,
  submitted)`, pauses if any alert's kind is in `pauseOn`, and saves on the
  first of the month.
- **News.** `AlertKind` (refused, overdue, bankruptcy, stockout,
  deliveryRefused, stores, economy, monthEnd, manager, director, milestone,
  offer). `_news` compares the observations before and after and reads
  `TickResult.events`.
- **Immediate actions.** `wake(row)` and `createBrand(name, format)` go to
  the engine at once, as the engine applies them on submit.
- **Derived figures.** `netWorth` (the holding's cash and shares at their price, plus `companiesWorth`, less `shareLoans`), `holdingProfits`, `cushion`, `myStores`,
  `myFactories`, `homeCountry`, `residence`, `economyAt`, `plan`,
  `national`.

## The six tabs

[home.dart](../app/lib/src/home.dart): `HomeScreen`, `HomeTab` (holding,
shop, finance, world, market, books), the clock bar, the pending bar, `AlertTile`,
and an `AppLifecycleListener` that saves when the app goes to the
background.

| Tab | File | Main widgets |
|---|---|---|
| Holding | [screens/holding.dart](../app/lib/src/screens/holding.dart), [screens/company.dart](../app/lib/src/screens/company.dart) | `HoldingScreen`, the desk (the owner's layout A of 2026-11-18, mail first): a `VerdictBox` counting the mail waiting and a `FigureGrid` (net worth, profit a month with its line, cash, debt), `DeskMail` in [screens/desk.dart](../app/lib/src/screens/desk.dart) (each `Mail` from [mail.dart](../app/lib/src/mail.dart) ruled red until answered, then `toDoItems`, Reports opening every CEO's `LettersSection`, last week's story; a mail opens as a `MailPage`), `DeskNews` (the latest three alerts), `_Companies` (the companies it holds directly, with who runs them and how many subsidiaries, worth and last month's trend, each opening its page; starting a business makes a company of its own once there is one), `_HoldingBooks` (its balance sheet, then its own result this year and its months as a line, and renaming the holding, `_RenameHoldingDialog`), `_Portfolio`, `_Profits`. `CompanyDashboard` in [screens/company.dart](../app/lib/src/screens/company.dart) (`openCompanyDashboard`, layout B): a verdict in its boss's words, worth, profit, cash and debt, its to-dos, its businesses (`_BusinessLine`) and adding one to it (`openStartBusiness(company:)`, carried to the shop, plant and software pages), its subsidiaries and founding one (`_Subsidiaries`, `_FoundDialog`), the restructuring levers (`companyRestructureRows` in [screens/restructure.dart](../app/lib/src/screens/restructure.dart): merge, move under, sell; a business page's `MoveOrSellSection`: move, make it a company of its own, sell), its boss (the personnel file, `DirectorSection`, as a page) and the levers (its money in Finance, renaming) |
| Businesses (`HomeTab.shop`, named Businesses since 2026-11-16) | [screens/businesses.dart](../app/lib/src/screens/businesses.dart), [screens/business_page.dart](../app/lib/src/screens/business_page.dart), [screens/shop.dart](../app/lib/src/screens/shop.dart), [screens/orders.dart](../app/lib/src/screens/orders.dart) | `BusinessesScreen` (the owner's layout A list: the companies, each opening its page). A business's page, `BusinessPage` (`openBusinessPage`, layout B): a verdict and four figures, then for a trade its countries (`byCountry`), kinds of shop and brands (`CreateBrandDialog`) and, run by hand, its shops (`StoreLine`, each opening `ShopScreen` as a whole page with `openStorePage`); for plants each `FactoryLine`; software opens its own page. Nothing on these pages says how the game works a shop out |
| Finance | [screens/finance.dart](../app/lib/src/screens/finance.dart), [screens/financials.dart](../app/lib/src/screens/financials.dart) | `FinanceScreen`: the companies' money (the holding's is on Holding), company pages, the boss's brief (the owner's brief B: who, a goal per business with what it means, the two money rules; `_DirectorSheetState`, `_Choice`, `_goalSentence`) and letters, borrowing, cushion, taxes, bargains; `DirectorSection`, the owner's layout A, a personnel file (`PersonHeader`: portrait, name, title and character; their saying, record and what their character does), and the sheet's shortlist (`_CandidateTile`); `FinancialsSection`: key figures, P&L, balance sheet, years |
| World | [screens/world.dart](../app/lib/src/screens/world.dart), [screens/national.dart](../app/lib/src/screens/national.dart) | `WorldScreen`: economy, countries, competitors, cities; `NewBusiness` (a shop of a kind already chosen: country, city and neighbourhood chips, the city read from a place's name as "City, Neighbourhood" by `placeParts`, then the vacant sites big enough, opening one waking its neighbourhood) and `freeSites`; `NationalMap`: the country page and its ink map |
| Market | [screens/exchange.dart](../app/lib/src/screens/exchange.dart) | `ExchangeScreen` (the owner's layout A): exchanges today, the portfolio, sectors with their price to earnings; `SectorPage`, `StockPage` (price and chart, what it rests on, analysts and management, who holds it, buy and sell, opened by `openStock`), `ScreenerPage` in [screens/screener.dart](../app/lib/src/screens/screener.dart) (the owner's three mockups as three views: ready-made screens, criteria and results, a table sorted by column; `screen`, `figuresOf`, `meets` and `limitText` are pure, for tests), `ExchangePage` (an index, bought whole), `TradePage`, `PortfolioPage` (with the holding's loans); phase 2: `BidSection` on a stock's page, `TakeoverBidPage` (mockup 1), `ControlPage` (mockup 2), `ExchangeEntry` on a company's page in Finance and `ListCompanyPage` (mockup 3), raiders and bids open on the tab (mockup 4) |
| Books | [screens/books.dart](../app/lib/src/screens/books.dart) | `BooksScreen`: periods, what changed, results, shoppers, products, research |

Other screens: [menu.dart](../app/lib/src/screens/menu.dart) (`MainMenu`:
three slots, continue, new game, delete, language),
[new_game.dart](../app/lib/src/screens/new_game.dart) (`NewGameScreen`: only
the holding's name), [start.dart](../app/lib/src/screens/start.dart)
(`StartBusinessPage`, the owner's layout A, 2026-11-16: a line per sector,
the trades' shops grouped by `formatTrades`, then factories and software,
each opening its kinds with what limits them, a pitch and the least it
costs; a kind opens `NewBusiness`, `BuildFactoryPage` or
`StartSoftwarePage`; `openStartBusiness`, also for a subsidiary, which is a
shop or a factory), [factory.dart](../app/lib/src/screens/factory.dart)
(`FactoriesSection`, `FactoryPage`, `BuildFactoryPage`),
[sales_desk.dart](../app/lib/src/screens/sales_desk.dart) (a factory's
sales desk in the owner's layout B: `SalesDeskEntry` on the factory page,
`SalesDeskPage` with its market, contracts, open tenders, what lately won,
independents and rival producers, `TenderBidPage`, and `ContractPage` in the
owner's layout A: terms, a chain's request, asking a new price, breaking),
[software.dart](../app/lib/src/screens/software.dart) (`SoftwareSection` on
the holding, `StartSoftwarePage`, and a software company's page in the
owner's layout B: `SoftwarePage` with its four figures and `RaceChart`, then
`SoftwareProductPage`, `SoftwarePeoplePage`, `SoftwareCustomersPage`,
`SoftwareMarketPage`, `SoftwareFundingPage`),
[guide.dart](../app/lib/src/screens/guide.dart) (`HowToPlayScreen`).

Layout pattern: each tab has a summary on top and index lines (`IndexRow`)
that open pages within the tab (`SubPages`). The top bar's arrow is the only
way back (as is the phone's back gesture): out of a page, then from the tab
to the main menu. A forward arrow beside the bell returns to the page last
gone back from (`_ahead` in `HomeScreen`), until another page is opened. Pages are laid out whole, not lazily, because a lazy list under
a closing dialog trips Flutter's semantics.

## Support files

| File | What it does |
|---|---|
| [business.dart](../app/lib/src/business.dart) | A company's businesses (`businessesOf`): one per trade (`tradeOf`, `tradeName`), whatever the country and however its shops are worked out, one per kind of plant, and its software, each with up to twelve full months of sales, profit and shops (`BusinessMonth`); `byCountry`; the verdicts (`businessVerdict`, `companyVerdict`, `Tone`) |
| [financials.dart](../app/lib/src/financials.dart) | Company financials worked out in the app from month reports and balances: `Financials`, margins, ROIC, money tied up (`_tiedUp`, `_fitOut`) |
| [commands.dart](../app/lib/src/commands.dart) | `describeCommand`: a pending command in words |
| [letters.dart](../app/lib/src/letters.dart) | `directorLetters`, `memoSentence`: the director's monthly letter from memos, signed by the director in place since they came, with a line in their voice |
| [directors.dart](../app/lib/src/directors.dart) | A director as a person: `directorPerson`, `directorTitle` and `characterName` (in the agreement of their sex), `directorLine`, `motto`, `pastLine`, `characterPitch` (what their character changes, with figures), `voiceLine`, `shopsOf`, `salesSince` (the ink portraits were removed on 2026-11-17; `DirectorPerson.looks` still picks a saying and a line) |
| [loans.dart](../app/lib/src/loans.dart) | `loanTerms` (12 to 84 months), `firstPayment`, `newBusinessFunding` (what a new shop or factory borrows), and the widgets of a purchase: `LoanTerms`, `CapitalField` (the holding's cash, or a subsidiary's parent's), `BorrowSwitch`, `CompanyPicker` (which company a new shop or plant goes in, `currentCompany` by default) |
| [format.dart](../app/lib/src/format.dart) | `money`, `percent`, dates, `refusalText`, `parseMoney`, names with articles (`aFormat`, `aManager`, …), `stanceAdvice`, `balancedStrategy` (the strategy a brief starts on) |
| [widgets.dart](../app/lib/src/widgets.dart) | `GameScope`, `Section`, `SubPages`, `IndexRow`, `TradeMark`, `Line`, `Hint`, `CountStepper`; `confirm` (every yes-or-no question), `askAmount`; `showGameSheet`, `SheetFrame` and `ChoiceTile` for the director's, manager's and order sheets |
| [visuals.dart](../app/lib/src/visuals.dart) | `AnimatedMoney`, `Pill`, `Stamp`, `Sparkline`, `BarChart`, `SplitBar`, `TrendChart`, `FadeSlideIn` |
| [outlines.dart](../app/lib/src/outlines.dart) | `parseOutlines`, `loadOutlines`, `outlineOf`, `CountryOutline`, `RegionOutline` |
| [saves.dart](../app/lib/src/saves.dart) | Save slots; see [state-and-saves.md](state-and-saves.md) |

## The ledger theme

[theme.dart](../app/lib/src/theme.dart): one design system, an account book.

- `Ledger`, a `ThemeExtension` with `paper`, `shade`, `ink`, `muted`,
  `rule`, `gain` (green ink), `loss` (red ink); `Ledger.day` and
  `Ledger.nightEdition` for dark mode. `Ledger.of(context)`.
- `gameTheme(brightness)` builds the `ThemeData`.
- Fonts: Fraunces for titles (`titleFont`, `displayFont`), IBM Plex Sans for
  text (`textFont`), IBM Plex Mono for every figure (`figuresFont`). Bundled
  in [app/assets/fonts](../app/assets/fonts) with their OFL licences.
- `Ledger.trade(format)` gives each kind of business its colour;
  `formatIcon`, `categoryIcon`, `slotIcon` give icons. `Ledger.works` is the
  factories' slate.
- Sections are a serif title over a rule, not cards; warnings are red
  stamps (`Stamp`).

The owner chooses looks from mockups; the app's look is the ledger.

## Words: `tr()`

[l10n.dart](../app/lib/src/l10n.dart). No string the player reads is in the
code.

- [content/locales/en.json](../content/locales/en.json),
  [fr.json](../content/locales/fr.json), [es.json](../content/locales/es.json)
  hold the interface, nested by screen; `Strings` flattens them to dotted
  keys. [languages.json](../content/locales/languages.json) lists the
  languages.
- `tr('store.sell', {'store': name})` looks a key up and fills
  `{placeholders}`. An entry given as an object holds plural forms (`one`,
  exact counts, `other`), picked by `args['count']`; `format.singular` says
  which counts take `one`.
- `trMaybe` returns null for a missing key; `trList` reads a list (month
  names, weekdays).
- Missing keys fall back on English, then show the key itself.
- `useLanguage(code)` loads a language; `useStrings` sets one directly
  (tests). The language is a global, chosen on the main menu only.
- The scenario's words come from `prototype.<lang>.json` under `scenario.`
  and are swapped into the scenario by `localizedScenario` before the engine
  loads it.
- Refusals: `refusalText` in [format.dart](../app/lib/src/format.dart) words
  `refusals.<key>`.

Flutter's own strings follow through `flutter_localizations`.

## Outlines and ink maps

[content/countries/outlines.json](../content/countries/outlines.json), built
by [build_outlines.py](../content/countries/build_outlines.py) from GISCO
NUTS 2021 boundaries, holds per country a frame 1,000 units wide, an
optional inset box (the Canary Islands), and per region an even-odd path, a
label point and an area. Region keys match the national table's.

[outlines.dart](../app/lib/src/outlines.dart) parses it once into a global
map (`loadOutlines` at start-up, `useOutlines` in tests); `outlineOf(country)`
returns a `CountryOutline`. `_InkMap` and `_InkPainter` in
[screens/national.dart](../app/lib/src/screens/national.dart) draw the
regions shaded by the player's share, smaller regions over larger ones, and
find the tapped region with `Path.contains`, smallest first.
