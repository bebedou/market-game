# Retail economy: model version 1

This milestone implements the headless economy, not the playable dashboard.
All amounts below and in engine APIs are **integer cents**. Catalog, segment
parameters, and decision order are part of snapshot schema version 1; change the
schema when changing their meaning. These are transparent starting assumptions,
not an attempt to estimate a particular real neighborhood.

## Population and starting capital

The neighborhood contains 1,000 households, represented by four segments:

| Segment | Households | Monthly income per household | Convenience budget / income | Price sensitivity |
| --- | ---: | ---: | ---: | ---: |
| Budget | 300 | $1,800 | 6.5% | 5 |
| Working | 350 | $3,400 | 6.5% | 4 |
| Comfortable | 250 | $6,000 | 6.5% | 3 |
| Affluent | 100 | $10,000 | 6.5% | 2 |

Each segment receives `floor(households × monthlyIncome / 30)` daily income.
Its convenience-shopping budget is `floor(dailyIncome × 650 / 10000)`. Unspent
income stays in the segment's cash balance, but does not increase tomorrow's
spending allowance. We model neither other household purchases nor consumption
utility. A month is always 30 days for income accounting.

Corner & Co. is player-controlled; Quick Stop and Neighborhood Mart are AI stores.
Each starts with $25,000 cash and approximately three days of stock at an equal
one-third share of baseline demand. Daily operating costs are $80, $90, and $85;
store appeal is 100, 105, and 95. Two suppliers start with $10,000 cash each and
four days of stock at an equal half share of baseline wholesale demand.

Opening inventory is contributed capital with its recorded FIFO cost; it is not
an opening cash purchase or free profit. There is no tax, debt, interest,
depreciation, expiry, population growth, rent inflation, or corporate finance.

## Eight products

| Product | Reference retail price | Base wholesale cost | Supplier procurement cost | Intentions / 1,000 households / day |
| --- | ---: | ---: | ---: | ---: |
| Bottled water | $1.50 | $0.80 | $0.55 | 400 |
| Milk | $2.40 | $1.55 | $1.10 | 200 |
| Bread | $2.80 | $1.70 | $1.20 | 250 |
| Soft drinks | $2.20 | $1.10 | $0.75 | 300 |
| Snacks | $1.80 | $0.90 | $0.60 | 350 |
| Coffee | $3.50 | $1.50 | $0.95 | 250 |
| Household soap | $5.20 | $3.10 | $2.10 | 50 |
| Fresh fruit | $1.90 | $1.15 | $0.80 | 300 |

Demand parameters differ by product. Households have no brand substitution or
cross-product utility model yet; product order is shuffled to avoid always
spending the budget on water first.

## Daily order

1. Audit the previous state, start a bounded daily journal, and credit incomes.
2. Suppliers set quotes and replenish from the outside economy.
3. Competitors adjust their retail prices using yesterday's sales and shelves.
4. In a seeded shuffled store order, solvent stores pay operating costs and
   automatically restock toward configured targets, cheapest supplier first.
5. In seeded shuffled segment and product orders, households attempt purchases.
6. Settle aggregated purchases, record stockout/closure notifications, and audit
   every business's cash, inventory, and income statement.

A store unable to pay the full operating cost closes permanently before trading
that day. It retains cash and inventory but incurs no new expense and receives
no bailout. This is a deliberately simple failure policy; liquidation/reopening
is a future feature. Suppliers buy only inventory they can afford. Empty
suppliers remain in the model and can replenish using retained cash later.

## Demand and choice

Expected units for a segment/product are:

```
segment households × intentions per 1,000 / 1,000
  × weekday multiplier × daily demand shock
```

Day 1 is Monday. Weekday percentages are `[100, 100, 100, 105, 115, 130, 110]`.
The segment/product shock is a seeded integer percentage from 90 through 110.
Fractional expected units are stochastically rounded using their remainder, so
small segments still generate occasional soap purchases.

For each requested unit, eligible stores must be open, stocked, affordable from
that day's remaining segment budget, and below the segment's reservation price:

```
reservation price = floor(referencePrice × (100 + floor(120 / sensitivity)) / 100)
```

Store choice uses integer weights approximating:

```
1000 × (referencePrice / retailPrice)^sensitivity × appeal / 100
```

For exact results, start at 1,000 and repeat
`weight = clamp(floor(weight × referencePrice / price), 1, 1,000,000)` once per
sensitivity point, then apply appeal with integer division. There is also a
constant outside-option weight of 350, representing postponing the purchase or
shopping elsewhere. Choice is a seeded draw over eligible weights plus the
outside option. Thus sales can fall even when all local prices rise together.
A rejected intention is not retried that day. No money changes hands for an
outside choice. Stock and remaining budget are reserved while allocating units;
settlement is batched by segment/product/store to keep the journal small.

Revenue market share is retail revenue divided by total local retail revenue.
If there are no sales, every store's share is zero. This is a revenue measure,
not household reach or unit share.

## Suppliers, restocking, and pricing AI

Supplier quotes are base wholesale cost multiplied by a percentage composed of
100%, alternating product advantages of −4/+4 points, a seeded −2..+2 point
shock, and a +5 point scarcity premium when pre-replenishment stock is below one
whole-neighborhood baseline day of demand. Each supplier then refills toward
`2 × whole-neighborhood daily demand`, paying the fixed procurement cost. This
is wholesale purchasing from an external source, not a manufacturing system.

Stores buy only the gap to their target, with no delivery fee or delay, limited
by supplier quantity and available cash. Products are restocked in catalog order;
this gives essential products priority when working capital is low. Supplier
price ties break by ID. The player starts with automatic restocking enabled and
can disable it or set per-product targets (0..10,000 units).

AI stores start at 97% and 104% of reference retail prices. From day 2:

- A product sold out yesterday with positive sales: increase by about 2%.
- Otherwise, sales below 80% of an equal market share, or a price more than 10%
  above the cheapest open store: decrease by about 2%.
- Otherwise, move one cent toward reference price.

Clamp the result between 120% of the cheapest current wholesale quote and 125%
of reference retail price. Competitors evaluate in stable store order. The
player's prices are never changed by AI; valid player prices are 1..1,000,000
cents. There is no profit-maximizing solver or predictive intelligence yet.

## Accounting and invariants

The ledger contains one cash account per segment, store, and supplier plus an
explicit `outside` account. Every transfer has equal debit and credit effects.
Only `outside` may go negative: it represents external employers and the wider
economy. This is an open neighborhood model, not a closed macroeconomy.

- Incomes: outside → segments.
- Retail purchases: segments → stores.
- Wholesale purchases: stores → suppliers.
- Supplier procurement and store operating expenses: businesses → outside.

Total cash including outside must equal initial total cash forever. All local
balances must stay nonnegative. The journal is replayed against daily opening
balances during every audit. Only the current day's journal and report are
retained; no 10,000-day transaction list accumulates in memory.

FIFO inventory purchases increase carrying value. Sales remove their exact
recorded purchase cost, independently of current supplier quotes:

```
profit = revenue − cost of goods sold − operating expenses
cash change = revenue − inventory purchases − operating expenses
closing inventory value = opening value + purchases − cost of goods sold
profit = cash change + change in inventory value
```

These equations apply separately to all three stores and both suppliers. No
money is transferred for COGS: the corresponding purchase was already paid.
Tests compare retail transfers with household spending and store revenue, and
wholesale transfers with store purchases. Overselling and unaffordable transfers
throw before changing inventory or balances. The engine owns the mutable domain
state; callers should use its player-control methods rather than edit fields or
post arbitrary ledger entries during gameplay.

## Determinism and snapshots

The explicit Park–Miller generator uses modulus 2,147,483,647 and multiplier
16,807. Seed normalization is `seed % (modulus − 1) + 1`. `nextInt(n)` advances
state and returns `(state − 1) % n`; the tiny modulus bias is accepted for this
prototype. All decision arithmetic is integer-based and intermediate products
stay below JavaScript's exact integer limit for supported controls.

Snapshots include day, random state, cash accounts, current journal, FIFO lots,
prices, targets, prior sales, closure flags, and the last report. JSON round-trip
and resumed-future equivalence are tested. Invalid schema versions are rejected.
There is no disk or browser persistence adapter yet. Snapshots currently assume
the same version-1 catalog and population, not arbitrary custom scenarios.

## Run and assess

```
dart tool/simulate.dart --days 30 --seed 42
dart tool/simulate.dart --days 10000 --seed 42
flutter test test/economy_test.dart
```

The CLI imports only Dart engine files and Dart standard libraries; Flutter is
not used by the simulation. It prints cumulative store revenue/profit, final
cash, inventory value, open/closed status, market shares, retained journal size,
and cash conservation. Both automated tests and the CLI audit every day for
10,000 days in CI. The baseline seed must keep all stores open, profitable over
the full run, and active in the market. This is a regression check, not proof
that all strategies or seeds are balanced. No speed or wall-clock timer is part
of this engine milestone.
