# Economic Sandbox — Game Design Brief
**Version 0.4 | November 2026**

## Vision

A premium, mobile-first economic simulation combining the entrepreneurial progression of Big Ambitions, the financial complexity of Wall Street Raider, and the interconnected industries of Capitalism Lab.

The player starts with a small business and can eventually become a multinational business owner, industrialist, technology innovator, or corporate investor.

**A Warren Buffett simulator.** Money is only the score. How rich the player gets depends on how good they are at spotting value and at running their businesses. A mistake costs time: expanding too fast just before a crisis, being overtaken by an innovation, or buying a stock that goes south sets the player back years. Only the player's own ruin ends the game.

**Core philosophy:** The player operates within a living economy rather than a collection of disconnected business minigames.

## Fundamental gameplay principles

1. **Start small, grow indefinitely.** From a convenience store to a diversified corporate empire.
2. **A living economy.** Consumers, suppliers, competitors, and markets function independently of the player.
3. **One interconnected simulation.** Production, retail, services, brands, innovation, finance, and macroeconomics affect each other.
4. **Multiple paths to wealth.** Entrepreneurship, industrial production, technological innovation, intellectual property, investments, and acquisitions.
5. **Emergent innovation.** A dynamic, realistic technology system instead of a predetermined historical research tree.
6. **Strategic management over busywork.** No manual shelf restocking, walking between locations, or arbitrary waiting mechanics.
7. **Designed for mobile.** Primarily dashboards, financial reports, charts, contextual decisions, and an accessible interface.
8. **Premium experience.** A proposed price of approximately $4.99, without energy systems or pay-to-win mechanics.
9. **Same rules for everyone.** AI companies use the same engine, costs, and constraints as the player. They can expand, and they can go bankrupt.
10. **Legible causality.** The player can always find out *why* a number changed. Hidden information is fine; unexplainable outcomes are not.
11. **Extremely moddable.** Company names, countries, cities, products, balance and every line of text are data anyone can change or replace, without touching the code (see Modding).

## Player experience

**Identity.** The player is a person with personal wealth (cash, assets, reputation) distinct from the companies they own. Each company has its own balance sheet and, at launch, is wholly owned by the player. Personal wealth funds new ventures and is shielded from a company's failure, except for debts the player personally guaranteed.

**Money flow.** The player injects capital into their companies; companies pay dividends back, taxed and only out of retained profits. There are no other transfers, so a failing company cannot be drained into personal wealth.

**Personal guarantees.** The bank lends a company on what its stores earn; beyond that, only on the player's personal guarantee. A new business has no earnings, so the early game is personally risky; a grown empire borrows on its own.

**Borrowing to grow.** Borrowing is a lever for growth, not a side feature. The bank lends without a guarantee up to a year and a half of a company's earnings, and says how much on each company's accounts. Opening a store or buying a rival without the cash, the player is offered the rest there and then, with what it costs a month; buying a store, its own earnings count, so a profitable rival can largely pay for itself. A whole company can borrow part of its own price on its earnings, so buying out a rival chain takes less of the player's own cash. Long loans keep the payments small, and the cash cushion keeps the next one aside. A director can borrow too, if their brief lets them.

**Goals.** A sandbox with money as the score: no set goal, but how rich the player gets, and how fast, measures how well they play. Replayability comes from new businesses, sectors and markets added in updates, and from choosing where and how to start. Goals, achievements and challenge seeds come after launch (see Roadmap).

**Failure.** A company's bankruptcy costs time, not the game. The company is liquidated and its creditors are paid from its assets. The player keeps their personal assets minus any debt they guaranteed, takes a reputation hit (worse borrowing terms, harder deals), and can start again in the same world. The player's own bankruptcy ends the game: when the debts they personally guaranteed are more than everything they own.

**Sessions.** The game must work for both short and long sessions:
- *Short (5–15 min):* review the dashboard, react to what changed, adjust a few policies, advance time.
- *Long (30–90 min):* expand into new markets, restructure, analyze reports, buy or sell businesses.

Time controls should support both, e.g. "advance one week" and pausing on important events.

## Setting and world

**Real-world, modern day.** Real countries and cities; all companies, brands, and products are fictional.

**Abstract markets.** There is no map and no walking. A market is a city (later a region or country) described by its statistics: what its shoppers spend a year on each trade, in euros, the mix of who lives there, income, price level, rents, and competition. A market in euros stays meaningful without perfect data: one figure per trade, from any source. The mix only says how people shop (when, how much price matters, how loyal they are), and income only what they buy (dearer goods), not how much they spend, so a rich place's wealth isn't counted twice. Location inside a market is an abstract attribute of a business (a location-quality tier that trades rent against convenience).

**Countries.** Markets belong to countries: France, Germany, Italy and Spain, with Berlin, Munich, Milan, Rome, Madrid and Barcelona beside the seven French cities. A game can start in any of them. Each country has its own economy: its booms and recessions, mostly in step with the others but not always (Germany often goes its own way, Spain swings hardest), its own inflation, prices, wages and unemployment. One central bank sets the rate for every country on its currency, from their inflation and output weighted by size, so a recession in Spain alone doesn't cut Spanish borrowing costs much. Each country has its own wholesalers, with their names, delivery times, payment terms (Italian and Spanish suppliers give 60 days) and prices. Each taxes what a company's shops make there at its own rates, sharing what isn't any shop's (interest, a director) by sales, with losses carried there; dividends are taxed where the owner lives, the player where their game began. Goods cost the same across the euro area, but what a shop adds over them is paid at local wages, so shelves are cheaper where wages are low, a meal more than a pint of milk, and poorer countries earn less over their goods than their cheaper staff make up for. Spreading across countries is a hedge, and choosing where to grow a decision: Spanish households spend twice as much on restaurants and Italian ones more on everything, but Spain earns a little less and its recessions cut deepest; Germany follows its own cycle and swings least. Every country also runs whole by formula from its national statistics, with its fictional national chains, for the national view; they are figures only, not businesses to buy or meet, until zooming in.

**Start points are data.** A scenario is an initial world state: date, markets, firms, macroeconomic parameters, and technology frontier. Launch ships one modern start. Historical start points are possible future content, not an engine feature.

**Languages.** The game plays in English, French and Spanish, in the phone's language by default, with a choice on the main menu. A saved game opens in any of them.

## Modding

The game must be extremely moddable. A player should be able to rename, replace or rebuild almost everything they see, and installing a world someone else made should be as easy as opening a saved game. A long life for a solo-developed game depends on it: players bring the countries, the brands and the languages that one developer never will.

**What a mod can change:**
- *Names:* companies, brands, people, stores, suppliers and products, including real ones the base game must not use.
- *Places:* countries, cities and sites, with their households, incomes, prices and rents, so the game can move anywhere in the world.
- *Trades:* kinds of business, product ranges, customer segments, strategies, and the grades of manager and director.
- *The economy:* every balance number: costs, wages, rents, taxes, lending, the business cycle.
- *Words:* every line of text, and whole new languages.
- *The look:* each trade's colour and icon.

**Design rules:**
1. **World facts live in data.** Code knows what a thing does, never what it is called or where it is. Nothing about a particular country, city, company or product is written in code; a feature that needs a new fact adds it to the scenario.
2. **Text lives in data.** Everything the player reads comes from JSON files, including what the engine refuses and why. A new language needs no build, and a partial one falls back on English.
3. **Ids, not names.** Rules and saves refer to stable ids; a name is only ever shown. Renaming something never breaks a save or changes how the game plays.
4. **Gaps don't break.** A mod says only what it changes; what it leaves out comes from what it builds on. A scenario with no translation still plays, in its own words.
5. **Mods are data, not scripts.** The same mod, seed and commands give the same game on every platform, so determinism, replays and seeds keep working. Scripting is not planned.
6. **The base game is a mod.** France ships through the same files and loader a mod uses, so the way in is always tested.

**Where it stands.** The scenario already holds the world and its balance, its countries included (taxes, how each takes the cycle, its suppliers, and the names its people, streets and shops are given), and all text and languages are in JSON. A country's national statistics come in a table of their own, built from Eurostat. Still to build: loading mods from a folder, with a simple format and a load order, and a screen to pick them. A few facts are still in code and should move to data: each trade's colour and icon, chosen by name in `theme.dart`, the loan lengths offered, the net-worth milestones in the news, rule limits such as the most a store may spend on marketing, and which national trade each kind of business counts under.

## Three economic layers

**Real economy:** Stores, factories, products, consumers, workers, suppliers, software, services, marketing, research, patents, and intellectual property.

**Financial economy:** Cash, loans, equity, corporate ownership, investments, mergers, acquisitions, and financial markets.

**Macroeconomic environment:** Inflation, interest rates, employment, wages, consumer purchasing power, economic growth, recessions, and regulation.

## Business sectors

- Retail: Convenience stores, specialist retailers, luxury stores.
- Raw materials: Mining, agriculture, energy.
- Industrial goods: Electronics, components, automotive, aerospace, defense.
- Food and beverages: Consumer food products, manufacturing, brands.
- Software: SaaS, applications, platforms, video games.
- Services: Logistics, consulting, financial and professional services.
- Marketing: Advertising agencies, campaigns, research.
- Entertainment: Film, music, publishing, intellectual property.

Companies can participate in multiple sectors and own different kinds of assets.

## Launch scope

**Production context:** solo developer, no fixed deadline. Scope decisions favor systems that reuse the same engine primitives.

**Launch ($4.99):**
- Retail (several store formats) across multiple real-world markets.
- Wholesale suppliers.
- Managers and policies (see below).
- Finance basics: loans, buying and selling whole businesses (100% ownership only).
- Personal wealth layer: capital injections, dividends, personal guarantees.
- Taxes: per-country corporate profit tax and dividend tax, so "reinvest or pay out" is a real choice, and where to grow one too. No other regulation.
- Hybrid macroeconomy: business cycles, interest rates, inflation.

**Post-launch (free updates):** production chains (raw materials → manufacturing → retail), stock market and equity (IPOs, partial stakes, takeovers), R&D, patents and IP, the remaining sectors, and additional start points.

## Roadmap

Next, in this order: owning the chain, the new trades, then the stock market. Household sizes came first and became markets in euros, then the euro countries (see Setting and world), then the first rung of owning the chain, a factory making the grocers' goods. The rest, not part of the first release, in no fixed order:

- **Goals and milestones.** Net-worth tiers, first acquisition, leading a city's market, a first factory: marked on a timeline of the player's empire.
- **Achievements.** For feats and odd paths: surviving a recession without a loan, a fine-dining empire, buying out the chain that beat you.
- **Seeds.** Every world comes from a seed, so it can be shared. A weekly challenge seed puts everyone in the same world and the same economic shocks, ranked on a leaderboard; each run is checked by replaying its commands, which the deterministic engine makes cheap and cheat-proof.
- **Challenge scenarios.** A set start with a goal and a deadline ("turn around a failing chain in two years"), including ones built on real crises (2008, the 2022 inflation) through the macroeconomic engine.
- **Showing the size of the empire.** The interface should make growth felt: the cities and sites the holding spans, its stores by trade colour, and its history over the years, not only longer lists.
- **Events** (the owner's idea, 2026-11-13). The world sends shocks the player hears of, and sometimes must answer: an oil crisis that lifts transport and energy costs, a war that cuts a country's demand and its supplies, a pandemic that shuts restaurants, a heatwave that sells drinks, a strike at a wholesaler, a new tax. Each moves the economy through the macroeconomic engine for a while (its phase, prices, wages, rates and what each trade sells), and news tells of it. Some ask the player to choose between two outcomes, each with its price: pass a cost rise on to shoppers or absorb it, take a government contract or keep the capacity for one's own shops, close in a crisis or keep paying the staff. Events come from the world's seed, so a challenge seed shares them, and the economic history marks them. AI owners face the same events under the same rules.
- **Lending and savings.** Credit priced from a business's risk (it is already sized on its earnings), fixed or variable rates, an overdraft line, deposit interest and government bonds; rival owners who borrow.
- **Owning the chain.** Each trade climbs its own ladder upstream: making its own goods, farms, a lab and a factory (see Owning the chain).
- **Selling to businesses.** Businesses that sell to retailers or to other industries, by formula from each country's input-output table, and starts as a factory or a service business (see Selling to businesses).
- **Clothing, cosmetics and luxury goods.** Three new trades, each with its own shops, shoppers and ladder upstream. Clothing sells by season: a collection is bought months ahead and loses value when the season turns, so a shop marks it down or carries it, and the sales are a high point of its year. Cosmetics sell often and in small baskets, in perfumeries and beauty shops, where brands and advice draw shoppers. Luxury sells rarely and dear, mostly to the comfortable, on a city's best streets, where the name counts for more than the price and a discount hurts it. All three keep goods that don't spoil but go out of fashion, and earn high margins against dear rents. What the engine lacks for them: seasons and markdowns, stock that ages rather than spoils, and a brand's prestige as well as its reputation. Their ladders: a workshop making its own clothes, a lab for cosmetics, a house making its own goods for luxury.
- **Countries by formula.** Countries described by real statistics (households by income class, what each earns and spends per trade, margins, the cycle), with fictional chains as blocks, cheap enough to run many at once. France, Germany, Italy and Spain are in the game, for the national view; see Engine Architecture.md. The euro countries come first, in the first release; then the USA, the UK, Japan and Canada, which need currencies; then the BRICS, once the demo is out. The aim: a player can stay local, shop by shop, or rise to run businesses across a whole world.
- **Neighbourhoods from figures.** A neighbourhood's sites, shops and owners generated from its households and costs and a seed. Cities now hold more neighbourhoods than the seven simulated from the start. They run by formula every month, at next to no cost: households come and go, shops of each trade share what they spend, make money or lose it, and open and close. When the player opens a shop there, the place comes to life as its history left it. A new game plays only the player's city in full: the six others run by formula too, with their own sites and shops, while their businesses stay in the game, trading in their books, and their chains can open and buy anywhere. See Engine Architecture.md. Still to come: zooming in from a country.
- **City plan.** A drawn plan of each city once the engine is hardened: neighbourhoods as blocks sized by their households, shaded by spending, rent or rivals, with the player's shops marked. It would take the game a step away from being fully textual. It needs a plan for every generated city, so it comes after neighbourhoods run by formula.
- **Executives.** Named people with strengths and characters, hired and fired, who run whole layers of the holding (see Managing at scale). Directors, one per company, are the first step.
- **Talent.** A small company of exceptional people can grow very fast and change the world, as Google, Nvidia, SpaceX or Anthropic did. Employees' skills should count, and poaching a gifted engineer, designer or financier should change the course of a business. Today only managers' and directors' grades do. Executives are a first step (see Talent).

## Owning the chain

Growing should not only mean more of the same store. Each trade can own more of its own chain, one rung at a time, until the player supplies themselves and, if they choose, their rivals. This is how the sectors connect: production comes in through the trades the player already runs, not as separate games.

**Ladders by trade.** Each rung is a business unit of its own, with its costs, staff and capacity:
- *Convenience store and supermarket:* a factory making goods the chain used to buy (cheaper, at a quality the player picks), then a distribution centre (shorter delivery times, less spoilage), then a dairy or market garden for fresh produce.
- *Restaurants:* a central kitchen, then a farm or ranch for meat and vegetables, then the house dishes sold as frozen meals in supermarkets, which takes the player into food manufacturing.
- *Electronics:* a repair workshop, then an R&D lab that invents the player's own gadgets and phones (see Post-launch direction), then a factory making the brand.

**Design rules:**
1. **Real trade-offs, not a discount button.** A rung costs a lot up front and must run near capacity to pay. In a recession, idle capacity is a weight a supplier would not be; a supplier's flexibility is what integration gives up.
2. **Sell to rivals, or keep it exclusive.** A farm or factory can sell to competitors: income and scale, at the price of helping them. AI owners buy from it under the same rules as from any supplier, and can climb ladders of their own.
3. **One rung at a time.** Each rung should pay for itself before the next is worth building.
4. **Legible.** Reports show what a rung saves or earns against buying from the market, and at what transfer price.
5. **Made or bought, never both.** Goods the chain makes replace the ones it bought, outright: a shop never sells its own version beside the bought one, so there is no second line to price, stock or compare.

**First step.** Own goods: a factory of the player's takes over a product the chain used to buy, and its goods replace the bought ones on the chain's shelves. It is the smallest ladder to build and the best test of whether integration is fun. Prove it before building the others. Built as approved on 2026-11-12:
- *What it makes.* One category, both its lines: a bakery, a drinks plant, a snack factory or a household-goods plant, kinds of factory in the data. Milk and fruit wait for the dairy and the market garden.
- *Building it.* From the holding, by any of the player's companies or a new one, in any of the countries: its staff are paid at that country's wages and its profit is taxed there. A drinks plant costs about 120,000 and 90 days of works, and the bank lends towards it as towards a shop. The build page shows what the player's shops sell of its goods and what one, two or three shifts would make and earn a month, in a recession too, and how soon it pays back.
- *Shifts.* One to three, or none. Each shift makes about what three corner shops sell, and its staff are paid whether it has work or not; the site's rent and running are paid whatever it makes. In a recession the player can drop a shift but not the site: that is the idle capacity a supplier would not be.
- *Made to order.* It makes what the shops order, up to the month's capacity; what they order beyond that comes from their wholesalers at their price, which earns it nothing. It keeps no stock, so it never leaves a shop short. It delivers on the terms of the wholesaler it replaces (three days, a day for bread), no better: faster deliveries are the distribution centre's.
- *Made or bought, never both.* Once it runs, every shop of the player's that sells its category, in every company and every country it serves, buys those goods only from it.
- *Where it delivers.* Its own country always, and any other the player ticks, two days slower and paying freight by what its goods weigh against their price: 12% of the price for drinks, 6% for snacks, 3% for household goods (decided 2026-11-12). So bottling stays near the shops, as a drinks plant abroad earns about what one at home does, while light or dear goods still pay to make where wages are low. Bread doesn't travel.
- *Transfer price* (open question 6): what each shop's wholesalers would charge it. The shops' books are the same as when they bought, and what the factory makes is exactly what it saves against buying, taxed where it stands, as tax authorities require of prices between related companies.
- *Rivals.* A switch, with a price under the wholesalers' (up to a fifth off). Rival shops in the places played in full buy from it, under the same rules as from any supplier, when it is their cheapest, and only from what the player's shops leave it: more use of it and more income, and cheaper goods for the rivals too. Places run by formula don't buy from it yet.
- *Not yet.* Quality is as bought for now; picking one comes next, with its own balance pass, as it changes what shoppers will pay. AI chains don't build factories yet: they buy from the player's, and climb their own ladders in a later step, with their shops run by formula. A factory can be closed, not sold.
- *Legible.* Its page leads with the month against buying: what the shops would have paid their wholesalers, less materials, staff, site and freight, down to what it earned; then its capacity used against the point where it pays, its shifts, what each line sells for and costs to make, and whom it sells to. The holding lists it with its use and earnings, the shelves mark what it makes, and a company's accounts show what it made for the shops as a line of its own. News tells when it opens and of a month it lost money. The bank lends on its earnings and a company's price counts it.

## Selling to businesses (roadmap)

Owning the chain brings businesses that sell to other businesses, and a player may run only those, selling to retailers or to other industries. They work by formula, as the places beyond the player's city do, rather than simulating every company in the world.

- *Market size.* Each sector's market is what other industries buy from it, plus what households, governments, investment and exports buy. That is a country's input-output table, which national statistics publish: the OECD and Eurostat have one for every country planned, by about 45 industries. Shops are only the households' part. A change carries through every step at once, so a chemicals maker four steps from the shops feels a recession through the chain, a little later. A supplier to a cyclical industry is a cyclical business itself, which a good player sees before buying one. Markets with no shops, such as space or defence, take their size from government budgets and investment. The game's sectors can be finer than the data's: space is a fixed part of a broader industry.
- *Rivals.* A few named producers per sector, as figures: a share, a price to their buyers, a quality, a capacity. They follow the player's rules: they cut prices, invest, and innovate through R&D. They are natural companies to list on the stock market.
- *Share.* The player's share follows what their product offers: value (quality for the price), appeal (brand, design talent, marketing to buyers) and reach (the countries they sell in). Buyers change suppliers slowly, for contracts and listings, so a share moves over months. Shares count within a sector only. Where buyers are few, as in space, defence or large industrial contracts, sales come as tenders instead: a few large contracts a year, each won or lost on the offer.
- *Meeting the shops.* Only consumer goods meet shops directly, in the city played in full, where the player's factory is one more supplier under the rules shops already use. Everything further upstream is by formula, except the player's own chain, which goes through their books at a transfer price (see Open questions).
- *Decisions.* Price to buyers, quality, capacity (a weight when idle in a downturn), marketing to buyers, and which countries to sell in. The player sees the market's size, their share against their rivals', and why it moved.
- *Cost.* About 45 industries a country, once a month: next to nothing beside the shops.

**Starts.** A player needn't start with a shop.
- *A holding* is how every game begins (since 2026-11-14): the player names it and holds the starting money, then starts their first business from the dashboard, in any city of any country, as a company of its own.
- *A factory* (a chemicals company, or any industry) has a burn rate until its first product is made. First the build: a small site, rented or bought, and its fitting out, as a shop's. Then development: staff and rent every month with nothing to sell yet, and the runway shown ("14 months of cash at this rate"); talented engineers shorten it (see Talent). Then the first product: production starts small and ramps up, and the player looks for buyers, a share of the sector or a first tender. With no earnings yet, the bank lends only on the player's guarantee, so a slow development or a lost tender can bring the one bankruptcy that ends the game.
- *A service business* (an advertising agency, or any service) sells no product: it builds a portfolio of customers and grows its staff to serve them. The founder and one or two people in a small office win their first clients by pitching, each pitch's chance following their reputation, their people's talent and their price. Each client pays a monthly fee, takes some of the staff's time and has a satisfaction level. The player hires as clients come: idle staff are a cost, and overloaded staff let quality slip, so clients leave. Leaning on a few large clients is the risk, and losing the largest costs time. The market is what businesses spend on the service, from the input-output table. An agency's is close at hand: the marketing every company in the game pays goes to an abstract services account today, and an agency would win a share of it, its clients including the chains the player competes with.
- *Fundraising* grows out of the factory start: selling part of the company to investors for the cash to cover its burn rate, at a price set by how far it has got, its people and its market. It needs part-ownership, which comes with the stock market, so private rounds are the first step of the stock market, before listing. Until then a factory is funded by the founder's cash and the loans they guarantee.

## Growing nationally

Designed on 2026-11-12. All three phases are built: the regions, a national chain opened by a director's brief with each region filling up, the country page's map, directors' branches in districts asleep, and what compounds (buying terms, national marketing, factories supplying national shops, chains bought whole and offers from them, the bank lending on it all, and rivals who place their shops where they pay). Districts played by hand are where the game begins, not where it ends: a chain must be able to grow to hundreds of shops across a country, so that success compounds. Three scales, played as close to the ground as the player likes:

1. **Shops run by hand**, in districts played in full, as now.
2. **Branches in districts asleep.** A company with a director may open and buy in districts run by formula, as AI chains do; its shops trade by formula in its books and wake nothing. The player can still wake a district to take a shop in hand.
3. **A national chain in each country.** Beyond the districts, the company becomes a block in the country's figures, region by region: its shops, kind of shop, price stance, brand and marketing.

- *Regions.* Each country is split into its real regions (France 13, Germany 16, Italy 20, Spain 17, from Eurostat), each with its households, income, wages and rents. The country's spending on each trade is shared by region, national chains have their shops spread across them, heavier in their home regions, and today's districts sit inside them.
- *Who opens.* Only a director, from a brief: how many shops a month at most, which regions, which kind of shop, whether to borrow. The director picks where a new shop pays back soonest and misjudges by their skill. The player runs strategy, not sites.
- *How a national shop earns.* Monthly, by formula: its region's spending on the trade, shared among the chains there by shops, pull (brand, marketing, price stance) and price. It costs an average fitting out at the region's prices, and wages and rent at its levels; it takes two years to win its custom, and closes, as district shops do, when it keeps losing money.
- *What compounds.* Each shop added in a region earns a little less than the last (saturation), so growth is quick early and then a choice of where. Against that: buying terms that improve with the chain's total volume, for every shop of it, hand-run ones included; national marketing spread over more shops; the chain's own factories supplying its national shops, so they run near capacity; the bank lending on bigger earnings; and national chains, figures today, becoming companies to buy whole at their earnings' value, or to be bought by.
- *What can go wrong.* A recession hits hardest a chain grown on loans in one country; rivals open where the player does; a weak director overbuilds where it's crowded.
- *What the player sees.* A country page with an ink map: each region drawn as it is, shaded by the player's share of the trade picked and showing their shops; then where a new shop would earn most, and the region's figures on tapping it (households, market, share, rivals, what a new shop earns). The director's brief shows the year's openings, closings, fitting out, what those shops earned and the buying terms reached.
- *Underneath.* The national figures stop being a replay and become saved state, as companies' books depend on them, still at microseconds a month. AI chains of the scenario may grow nationally under the same rules.
- *Growth that compounds* (the owner's direction, 2026-11-13; built the same day). A chain's growth compounds until it reaches critical mass, at a pace the player sets or leaves to the director, and a skilled director compounds better:
  - The brief sets a rate: new shops a month as a share of the chain's shops in each country, at least one (off, 1%, 2%, 4%, 6% or 10%, or as they judge). At 3% a month, a chain of 100 opens 3 and one of 1,000 opens 30, so it grows like money at interest.
  - Each grade runs a rate well up to their limit: 1.5% a month for a promoted manager, 3.5% for a seasoned director, 6% for a star, who doubles a chain each year. As they judge, they grow at that. Pushed beyond it, they misjudge where to open and every shop of the chain is run worse, the further past the more: a weak director forced to grow fast loses money, and even a star pushed hard earns no more, on thinner margins.
  - Critical mass is a share of the trade in a country: at 5% the rate there halves, and growth turns from compounding to steady. A new country starts compounding again; beyond critical mass, the leaps come from buying chains.
  - Only directors open shops across a country. It is paid from earnings and loans, so the cushion, the bank's limit and a recession keep it honest: a chain compounding on debt is the one a crisis hurts most.

## Managing at scale

Any business unit can be run by a manager who follows player-set policies:
- price stance (discount, match the market, premium) and target margin;
- stock coverage (days of stock to hold);
- supplier preference and assortment;
- budget limits.

The player intervenes by changing policies or taking direct control of a unit.

Managers have a skill level and a salary. Skill determines how closely they hit policy targets and how well they forecast demand; better managers cost more. Their mistakes come from imperfect forecasting, never from random blunders.

**AI competitors run on the same policy engine,** each with its own strategy. One decision system serves both player delegation and the living economy.

**Brands.** A chain trades under a brand, as Carrefour's shops do. A brand is a name for one type of business, owned by a person and usable by any of their companies. Every shop opened under it is named after it and its district ("Marché Plus Part-Dieu"), with its street added when the brand already has a shop there, and starts as well known as the brand's shops in the same city. An AI owner's new and bought shops always go under its brand, which it names after its company the first time it opens or buys a shop, and its other shops of that type then join it. The player creates brands from the holding, and their shops of its type join it at once, the first one included, while their company keeps its own name, as a holding's; when opening or buying a shop, they pick one of their brands or none. A branded shop can't be renamed on its own, and a shop that becomes another type of business, or changes hands, leaves its brand. This is a shop sign (an enseigne), not the goods a chain makes itself (see Owning the chain). Chains reach the districts beyond those played in full the same way, opening and buying there under their brands; those shops trade by formula in the chain's own books until the player arrives, when they become its stores there.

### Executives (roadmap)

Above the store managers, the holding gets a board, so the player can rise from running stores to running the empire: where to grow, what to buy or build, when to borrow.

**Roles.** Each takes a layer of decisions off the player, following the player's policies:
- *Head of operations:* every store's prices, stock, staff and assortment.
- *Finance director:* cash, borrowing, repayments and dividends within the limits set.
- *Marketing director:* marketing budgets and where they go.
- *Head of purchasing, later of production:* suppliers, terms, and the farms and factories of the chain.
- *R&D director:* what the lab works on.

**People, not grades.** Each executive is a named person with a face (ink portraits, in the ledger's style), a career history, strengths in operations, finance, marketing or production, and a character (frugal, bold, cautious, charismatic and so on) that changes how they apply the player's policies. They come from a pool of candidates in each city, through a recruiter for a fee. They ask for raises, grow better with time, can be poached by rivals, and cost severance to let go, as French labour law has it.

**Memos.** Executives report in their own words, and this is how the game explains itself at scale: "I cut night staff at three stores; sales dipped 1% and wages fell 6%." Every decision an executive takes can be traced and asked about.

**First step: directors.** Each company can have a director, hired from its page in Finance at one of three grades. The director sits above the store managers: they hire a manager for any store without one, close stores that keep losing money, as the AI chains do, and grow the company as far as the player allows (keep the stores as they are, enlarge and convert them, also open new stores, also buy struggling rivals), paying for growth from the company's cash, never the player's, and if the player lets them, by borrowing on its earnings, never on the player's guarantee. Allowed to buy and to borrow, they also go for profitable rivals that repay their price within four years. The player also says whether the profit stays in the company or comes to them each month; a director saving for a new store keeps it and says so. Skill shows as judgment: a better director sharpens their managers' forecasts and prices, and a cheaper one misjudges what a new site would earn, opening more stores that later close. Each month the director writes a letter: how the month before went, then each decision with its figures ("I closed Grill du Port: it lost 4,210 over the year on 38,900 of sales"). Names, characters and one executive over several companies come next.

**Rules.**
1. Delegating changes what the player decides; it never leaves them with nothing to decide.
2. Mistakes come from skill and character, never from random blunders, as with managers.
3. Executives decide through the same policy engine as managers and AI owners, with a wider remit and a personality.

### Talent (roadmap)

A small company of exceptional people can grow very fast. Talent sits in a company's key people, not in every employee: shop staff stay headcounts with wages, as they are.

- *Key people.* A few named people per company: engineers and researchers, designers, financiers, operators and marketers. Five to twenty names can be followed on a phone; skills for every cashier would be busywork. Executives are key people who also decide: a finance director is a financier with a remit.
- *Rare and lopsided.* Most are average, a few are worth ten ordinary ones. Talent multiplies what a company does rather than adding to it, so a small team of the best can beat a big budget.
- *What each moves.* Engineers and researchers: the odds and size of R&D breakthroughs, budget and talent both counting. Designers: how many shoppers a shop or product draws. Financiers: borrowing terms, and how well the player reads a business's real value before buying it. Operators: running costs, as managers do today. Marketers: what advertising buys.
- *A market for people.* A person's price follows their track record. The player poaches by paying more, and loses people to a rival who does. The best go where companies win, so success draws talent, and talent more success. Losing the best person is the risk, and it costs time.
- *Same rules for everyone.* AI companies hire and poach too, the player's people included.
- *Legible.* Each person's track record is shown, and their true level shows over time.

Talent and R&D go together: R&D without talent is only money, and talent without R&D has little to change. In shops, talent makes a chain better and quicker to grow, not world-changing. Growth like Nvidia's or Anthropic's needs a trade where one breakthrough sells everywhere at once, such as chips, software or platforms (see Business sectors).

## Simulation model

The game uses continuous time with discrete daily economic ticks.

The player can pause or accelerate time. Daily revenue, inventory movements, expenses, company decisions, and changing demand are resolved through the economic engine.

**Time scale:** a typical 30-minute session covers one to two in-game years. Decisions run on a weekly-to-monthly cadence, and a 40-year empire takes roughly 10–20 hours of play.

**Macroeconomy (hybrid):** an exogenous business cycle and a central-bank rule set interest rates and baseline inflation. Aggregate simulated activity (prices, wages, demand) nudges them. Each country has its own cycle, following a shared one by its own chance, and one central bank per currency sets a single rate from them all.

The simulation must be deterministic for a given starting seed and identical player decisions, across platforms. It must also support thousands of days of headless testing.

## Initial playable prototype

**World:** one market of approximately 1,000 households represented by consumer segments (differing in income, price sensitivity, loyalty, and basket), three competing convenience stores (the player and two AI firms under the same rules), two wholesale suppliers, and eight consumer products: four categories (e.g. milk, bread, snacks, drinks), each in a budget and a premium tier, mixing perishable and non-perishable goods.

The player controls one store.

**Player decisions:**
- prices per product;
- ordering: supplier, quantity, timing;
- assortment, within shelf capacity;
- staffing level (staffed hours and headcount; caps opening hours and affects service; wages follow the macro wage level, with no individual employees);
- opening hours (location tier is fixed per store in the prototype);
- market research purchases.

**Demand model.** Each segment chooses where to shop based on:
- *Price:* basket price relative to the segment's price sensitivity.
- *Convenience:* location tier, opening hours, service (staffing).
- *Availability:* a stockout loses the sale and erodes future visits.
- *Loyalty and reputation:* habit and word of mouth create inertia, so customers don't switch over a one-cent difference. Each store also has a reputation everyone knows: it builds over months from keeping the shelves stocked with what shoppers ask for and serving them without queues. A new store opens with less of it than one the city has known for years, so a well-run store's custom grows over its first years.
- *Marketing:* advertising builds goodwill that draws shoppers from rivals, with diminishing returns: each extra point of sales spent buys less pull. The store screen shows what each share costs and the pull it builds, so the player can find where more stops paying, often a few percent of sales.

**Market share.** A shop's share only ever counts against the shops that compete with it: a restaurant takes nothing from a convenience store. Convenience stores and supermarkets share one trade; fast food, steakhouses and fine dining don't take customers from each other, so each is its own.

**Substitution.** When a product is out of stock or overpriced, each segment has its own odds to substitute the other tier of the same category in-store, buy it at another store, delay the purchase, or skip it. A price too dear can't be waited out and is never answered by paying more: households take a cheaper tier, try another store or go without. So even a shop with no rival in its city can only charge so much. Every outcome also nudges loyalty.

**Entry and exit.** AI entrepreneurs periodically evaluate the market and open a store when expected profit is attractive. A bankrupt store's location becomes available to any firm, including the player.

**Information.** Competitor shelf prices are visible. True demand, elasticities, and segment preferences are hidden. The player infers them from their own sales or reveals them through paid market research.

**Supply frictions:**
- lead times per supplier;
- spoilage of perishables;
- supplier terms (minimum order quantities, volume discounts, payment terms);
- shelf capacity.

**Calm news.** Only what needs the player stops the clock: a change refused, a bill unpaid, a bankruptcy. The rest is news to read when they like, and it includes the good: a record month, net worth milestones, a store making a name for itself.

**Growth you can feel.** The game is balanced so that sensible play grows: towns gain households every year, stores build a name, and a store run well, even by a manager, earns more each year. Investment is not a setback: fitting out and works are shown apart from what the stores earn, so a month of building reads as a month of building, not a loss. Failure comes from clear mistakes, flagged early.

**Legibility.** Every change in revenue must be traceable to a cause. Reports attribute gained and lost visits and sales to price, stockouts, substitution, convenience, and loyalty (e.g. "lost 40 visits to Store B: your milk is 12% above theirs").

Profitability must be the consequence of simulated business activity.

### Prototype success criteria

The prototype is done when all four hold:

1. **Stable economy.** Thousands of headless days across many seeds with no collapse, runaway prices, or degenerate equilibrium.
2. **Multiple strategies.** At least two distinct strategies (e.g. discount/volume vs. premium/convenience) are each profitable against the AI. Verified with headless strategy bots and with playtesters.
3. **Legible decisions.** Playtesters can correctly explain why their profit changed in a given week.
4. **Fun.** Playtesters voluntarily keep playing past 30 minutes.

## Technical direction

Flutter for the interface, with a separate pure Dart economic simulation engine. The engine design is in [Engine Architecture.md](<Engine Architecture.md>).

Android-first, offline single-player, with Flutter Web for development and testing.

The architecture must accommodate future industries and systems without requiring the convenience-store simulation to be discarded: a store is one kind of business unit, and firms, products, and markets are data-driven.

**Cross-platform determinism.** The same seed and player commands must produce identical results on Android (Dart VM) and the web (compiled to JavaScript), where Dart integers are JavaScript numbers and `dart:math` functions may return different results. Rules for the engine:
- Money in integer minor units (cents).
- Integer or fixed-point math for anything that affects state; no `double` in simulation logic and no `dart:math` transcendentals (`exp`, `log`, `pow`). Use lookup tables or integer approximations instead.
- All values stay within ±2^53.
- A custom seeded PRNG, with separate streams per subsystem so adding a system does not shift the others' randomness.
- Insertion-ordered collections only; never iterate over unordered hash sets or maps.
- A save is a seed plus a player command log, plus periodic snapshots.
- A test runs identical seeds on the Dart VM and on the JavaScript build and compares a daily state hash.

## Development priority

Build the smallest functioning **market**, rather than an isolated shop simulator.

Validate consumer demand, inventory, pricing, competition, cash flow, and the daily clock before expanding into manufacturing, R&D, patents, or financial markets.

**The goal is not maximum complexity. It is maximum strategic depth from interacting systems.**

## Post-launch direction

**Innovation: stochastic discovery.** R&D spending buys chances at breakthroughs, and knowledge spills over between firms. Breakthrough odds must be visible to the player (legible causality). The product data model must allow new products and technologies to appear at runtime.

**First iteration: an R&D budget, no tree.** A company spends on R&D as it does on marketing, and the spending turns into an innovation from time to time. There is no technology tree to design.
- *Budget.* A share of sales, set for each company. AI chains spend what their strategy says.
- *Knowledge.* Spending builds it up, and it fades slowly when spending stops. Each month it gives a chance of a breakthrough, and the odds are shown: "about one every four years at this budget".
- *Breakthroughs.* Each takes a name from a list kept by trade in the data (for grocers: self-service tills, same-day delivery, a loyalty card). The name is flavour, so it needs no foresight, and when a list runs out it carries on as the next generation. A breakthrough makes the company's shops of that trade cheaper to run, or draws them more shoppers.
- *Spreading.* Rivals in the trade catch up after a few years, faster if they spend on R&D themselves. Until they do, they lose shoppers to whoever has it.
- *Disruption* is a rival's breakthrough. It is in the news, the player's share of the trade slips, and sales are lost until they catch up or sell up. The same rules hit rivals when the player innovates.
- Places run by formula, districts and countries, take the same effect on shoppers and costs.

## Open questions

1. **AI owners.** Under "same rules for everyone", do AI firms have AI owners with personal wealth who inject capital and take dividends? Where do AI entrepreneurs get the capital to enter a market? *(Provisional: AI owners are persons with scenario-given wealth; see Engine Architecture.md.)*
2. **Guarantee threshold.** What makes a company "large enough" to borrow without a personal guarantee: revenue, equity, credit history? *(Provisional: earnings. Without a guarantee, a company may owe up to a year and a half of its stores' earnings; see Engine Architecture.md.)*
3. **Manager hiring.** Where do managers come from (a pool per market?), and is their skill visible or revealed over time? *(Provisional at launch: the scenario offers grades of manager with visible skill and salary; see Engine Architecture.md. Later, executives come from a candidate pool per city, their strengths shown and their character revealed over time; see Executives.)*
4. **Discovery details.** How are breakthrough odds shown, how fast does knowledge spill over, and how do patents protect against spillover?
5. **Store model (decide near launch).** Paid upfront, or a free demo with a one-time $4.99 unlock?
6. **Transfer prices.** When the player's farm or factory supplies their own stores, at what price: cost, market, or a price the player sets? It moves profit between companies, and so tax. *(Decided 2026-11-12: market, what each shop's wholesalers would charge it, so a rung's profit is what it saves against buying; see Owning the chain.)*
7. **Executives' character.** How many traits, how strongly they bend policies, and how much is visible before hiring?
8. **Era.** A start in today's world, where innovation is invented by companies' R&D as play goes on, or a start in the 1950s with a technology tree by sector that follows history? *(Decided: today's world. A tree of future technologies would need foresight nobody has, and history is known to players.)*
