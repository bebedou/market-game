# Numbers and limits

How big each kind of number in the game can get, what grows as a game ages,
and where the limits bite first. Written 2026-11-20, after the owner's game
stopped on 1 July 2053; the figures come from that save (Bebedou, net worth
108.8 billion, 147 companies) played on with assertions on.

## What stopped the game on 1 July 2053

`mulDivRound(a, b, d)` works out `a × b ÷ d` without any intermediate passing
2^53. It split the larger factor as `q·d + r` and then multiplied `r` by the
smaller one, so it asserted that `2·d·min(a, b)` stay under 2^53. A CEO
deciding whether to open shops across a country (`newShopOutlook` in
[country_economy.dart](../packages/engine/lib/src/countries/country_economy.dart))
shares the country's spending, about 3 × 10^12 cents, by a new shop's weight
(14.9 million) against everyone's (302.5 million): the answer fits easily,
but `2 × 302.5 million × 14.9 million` is just over 2^53. The app on the
phone is a debug build, so the assertion threw, and the clock retried the
same day for ever without a word (D39 in the debt register, now paid).
The 2047 freeze was the same kind.

Fixed in [safe_int.dart](../packages/engine/lib/src/core/safe_int.dart):
past that bound, `_productOver` builds `r × s ÷ d` a bit at a time as a
quotient and a remainder below `d`, so nothing passes `2·d`. Where the old
way worked the result is the same to the cent, so play and the pinned state
hashes don't move. `mulDivTruncated` does the same for `(a * b) ~/ d`, now
used for creditors' shares in a bankruptcy
([solvency.dart](../packages/engine/lib/src/systems/solvency.dart)), which
multiplied two sums of money: two of a million each already pass 2^53.

A day that throws now stops the clock there and says so in the clock bar
(`SimulationController.stopped`); it isn't retried, and nothing is saved over
the last good day, as the day was left half done.

## What stopped it next, played on

Played on from that save with assertions on, the game ran to February 2073,
when an exchange's listed companies together passed 2^53 cents (Paris at
10.2 × 10^15 by 2074). The index only divides one such sum by another, so
past 2^53 it now counts in thousands of cents, or more (`_Worth` in
[stocks.dart](../packages/engine/lib/src/systems/stocks.dart)); while the
sum fits, nothing changes. A share's price, a company's worth times its
mood, now works in one division when that product wouldn't fit (`_price`).

It then stopped on 22 September 2074, and that one wasn't arithmetic: a
single company's market value passed 90 trillion. The software rivals'
worth, a year's revenue times a multiple, grew 9 to 13% a year, far faster
than the economy, because the market's customers grew 8% a year for ever
(78.6 billion by 2074, eight people's worth for each one alive):

| Company | Worth, 1 Jul 2053 | Worth, 1 Jan 2074 |
|---|---|---|
| Brisk Orchard | 5.8 trillion | 73.4 trillion |
| Corvane | 6.3 trillion | 55.2 trillion |
| Nerith | 3.6 trillion | 41.2 trillion |
| Halvren Systems | 5.1 trillion | 27.6 trillion |

Since 2026-11-26 the market fills toward a ceiling (`SoftwareDef.ceiling`,
8 billion customers): its growth slows in proportion as it fills and stops
there (`softwareTrend`), so revenue then grows with prices and investors'
multiples fall as growth does. A save already past the ceiling stops
growing rather than shrinking.

## The number types

| Kind | Stored as | Range | Steps |
|---|---|---|---|
| Money (`Money`) | integer cents | ±2^53 cents, ±90 trillion | 1 cent |
| Rates, shares, weights (`Fx`) | integer × 10,000 | ±9 × 10^11 | 0.0001 |
| Dates (`Day`) | days since 1970 | any year for 10^13 years | a day |
| Counts (units, households, staff) | plain integers | ±2^53 | 1 |
| Ids (`StoreId`, `CompanyId`…) | positions in their list | ±2^53 | |
| Random draws (`Rng`) | 32-bit words, xoshiro128** | `nextInt` bound up to 2^21 | |
| State hash | 32-bit, over the save's bytes | | |
| Names | UTF-8 text | 32 characters (`maxNameLength`) | |

Every number that affects the game is kept within ±2^53 (`maxSafeInt`), the
largest whole number the web holds exactly, so a game plays the same on a
phone, a desktop and in a browser. `checkedSafe` asserts it on every sum and
product of money and rates.

**Debug and release differ.** In a debug build (the phone's, today) every
such check is an assertion, and a day that breaks one throws. In a release
build the checks are off; the phone's integers are 64-bit, so a sum past
2^53 carries on exactly up to 2^63 and only then wraps, silently. But the
save reader refuses any integer past 2^53 (`StateReader.readInt`), so a
release game that passed it would save a file it can't load back.

**In the save,** integers are variable-length: one byte holds a sign and
6 bits, each further byte 7 more, so a cent amount in the billions takes 6
bytes and the largest allowed 8. Text is UTF-8 after its length.

## Headroom in the owner's game

The biggest balances in any company's or person's books, which are
lifetime totals (revenue, cost of goods, wages, dividends are never reset):

| Date | Biggest balance | Times over it fits in 2^53 |
|---|---|---|
| 1 Jul 2053 | Corner Stop's revenue, 93.1 billion | 967 |
| 1 Jan 2054 | 110.1 billion | 818 |
| 1 Jan 2064 | 673.7 billion | 133 |
| 1 Jan 2074 | 1.32 trillion | 68 |

They grow by about 60 to 70 billion a year, so the books have centuries of
room; what runs out first is the stock market's worth, above.

The money supply (22.4 million) and the countries' markets (France's
groceries, about 450 billion a year in 2047, 4.5 × 10^13 cents) are further
below.

## Where the limits bite first

1. **Products in `mulDivRound` and `mulDivTruncated`.** Fixed: exact past
   the old bound. The divisor itself must stay under 2^52 (asserted); a
   country's market in cents, the biggest sum the game keeps, is about 2^45.
2. **Two sums of money multiplied directly.** The bankruptcy shares were the
   one that could bite (fixed). The rest multiply money by small counts
   (months, units of capacity, 1,000) and have room for centuries.
3. **Lifetime balances.** They only grow, by tens of billions a year in
   the owner's game: centuries of room.
4. **A single company's worth.** The software rivals' grew 9 to 13% a year
   and passed 90 trillion in September 2074 in the owner's game. With the
   market's ceiling it grows about with prices once the market is full.
5. **`Rng.nextInt` bounds.** At most 2^21. A shopper choosing among a
   trade's open shops draws against the sum of their weights, up to 10,000
   a shop ([demand.dart](../packages/engine/lib/src/systems/demand.dart)
   `_choose`), so a neighbourhood with more than about 209 open shops of one
   trade would trip it. Others draw among short lists or months.
6. **A day isn't all or nothing.** A day that throws has applied its
   commands and part of its systems; it can't be resumed, only loaded again
   from the last save.

## What grows as a game ages

| What | Kept | In the 2053 save |
|---|---|---|
| Period reports | 13 weeks and 24 months a company | 5,402, 4.4 of the save's 5 MB (5.9 MB in all by 2074) |
| Holding's months | 36 | |
| Stock prices | 60 months a stock | 443 KB for the stock market |
| Economic history | 240 months a country | 240 |
| Tax filings | 10 years | |
| A director's memos | 240 | |
| Sales history | 28 days a shop | |
| Orders, loans | until delivered or repaid | 457 orders, 0 loans |
| App alerts | 100 | |
| Companies, shops, people, brands, factories | for ever: ids are list positions | 147 companies (146 trading), 89 shops (76), 148 people, 40 brands, 37 factories |
| The command log | every player command, for replays | 159 commands, 3 KB |

So a save grows with the number of companies, not with the years: each
company keeps 37 period reports. The 2053 save is 5 MB. Played on headless on
a desktop, a year of it takes about 20 to 30 seconds.

## Tools

- `dart run --enable-asserts tool/long_run.dart --save slot1.mgsave --until
  2080-01-01 [--out end.mgsave]` in `packages/engine` plays a save on (or a
  new game, without `--save`), says where a day throws, and prints the
  biggest balance each year.
- `dart run tool/save_report.dart slot1.mgsave` says what a save holds: each
  part's size, how many of each thing, and the biggest balances against
  2^53.
- A debug build on the phone lets `adb exec-out run-as
  com.marketgame.market_game cat files/slot1.mgsave` copy the save off it.
