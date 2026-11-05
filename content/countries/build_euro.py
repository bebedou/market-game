# Builds euro.json from Eurostat's public API, for the formula layer in
# packages/engine/lib/src/countries. Only the chains below are written by hand.
# To add a euro country, add it to COUNTRIES, VAT and CHAINS and run this again.
#
#   python build_euro.py
import json
import math
import os
import statistics as st
import urllib.request

BASE = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/'
HERE = os.path.dirname(os.path.abspath(__file__))
YEAR = 2022
COUNTRIES = {'DE': 'Germany', 'FR': 'France', 'IT': 'Italy', 'ES': 'Spain'}
GEO = '&'.join(f'geo={g}' for g in COUNTRIES)
QUINTILES = ['QU1', 'QU2', 'QU3', 'QU4', 'QU5']
CLASSES = [
    ('lowest', 'Lowest 20%', '1.4'),
    ('lower', 'Lower 20%', '1.2'),
    ('middle', 'Middle 20%', '1.0'),
    ('upper', 'Upper 20%', '0.8'),
    ('highest', 'Highest 20%', '0.6'),
]

# Which household spending makes up each trade.
SPENDING = {
    'grocery': ['CP01', 'CP02', 'CP056'],
    'restaurants': ['CP111'],
    'electronics': ['CP091', 'CP082'],
}
TRADES = {
    'grocery': ('Groceries', 'Food, drink, tobacco and household goods'),
    'restaurants': ('Restaurants', 'Restaurants, cafes and takeaways'),
    'electronics': ('Electronics', 'Computers, TVs, audio and phones'),
}
# The business statistics that report the same trades from the sellers' side.
TURNOVER = {
    'grocery': ['G4711', 'G472'],
    'restaurants': ['I56'],
    'electronics': ['G474', 'G4754'],
}
STORE_COUNTS = {
    'grocery': ['G471', 'G472'],
    'restaurants': ['I56'],
    'electronics': ['G474'],
}
# Spending includes VAT and sellers' turnover doesn't. Rates in force in 2022;
# Italian and Spanish food mixes the 4% and 10% bands.
VAT = {
    'DE': {'CP01': .07, 'CP02': .19, 'CP056': .19, 'CP111': .07, 'CP091': .19, 'CP082': .19},
    'FR': {'CP01': .055, 'CP02': .20, 'CP056': .20, 'CP111': .10, 'CP091': .20, 'CP082': .20},
    'IT': {'CP01': .08, 'CP02': .22, 'CP056': .22, 'CP111': .10, 'CP091': .22, 'CP082': .22},
    'ES': {'CP01': .08, 'CP02': .21, 'CP056': .21, 'CP111': .10, 'CP091': .21, 'CP082': .21},
}
# Combined statutory corporate tax (OECD Tax Database).
CORPORATE_TAX = {'DE': '0.2990', 'FR': '0.2583', 'IT': '0.2781', 'ES': '0.2500'}
# Food and drink are a typical restaurant's bought-in goods; the statistics
# only split purchases of goods for resale, which restaurants hardly have.
RESTAURANT_GOODS = 0.30

# Fictional chains. Grocery shares follow published estimates for the real
# market's structure: Germany's top four 76% (Lebensmittelpraxis, 2022), France
# from Kantar periods of 2022, Italy from Mediobanca (2021), Spain from Kantar
# (December 2022). Store counts, restaurant and electronics shares and every
# price position are rough estimates. What's left of each trade is its
# independents.
CHAINS = {
    'DE': {
        'grocery': [
            ('Hansemarkt', 11000, '0.26', '1.02'),
            ('Rheinkauf', 8000, '0.19', '1.00'),
            ('Preisfels', 4000, '0.18', '0.95'),
            ('Knauser', 4100, '0.13', '0.92'),
        ],
        'restaurants': [('Burger Eck', 1400, '0.05', '0.95'), ('Kaffeehaus Krone', 2500, '0.02', '1.05')],
        'electronics': [('Technohalle', 450, '0.30', '0.98'), ('Bitladen', 300, '0.05', '1.00')],
    },
    'FR': {
        'grocery': [
            ('Marché Central', 720, '0.22', '0.97'),
            ('Bellevue', 6000, '0.20', '1.02'),
            ('Commerçants Unis', 1800, '0.16', '0.99'),
            ("Coop de l'Ouest", 1600, '0.11', '1.00'),
            ('Grand Panier', 600, '0.09', '1.00'),
            ('Petit Prix', 1550, '0.08', '0.93'),
        ],
        'restaurants': [('Le Burger', 1500, '0.07', '0.95'), ('Brasserie Dumas', 800, '0.02', '1.05')],
        'electronics': [('Numéra', 500, '0.30', '1.00'), ('Maison Volt', 200, '0.08', '0.98')],
    },
    'IT': {
        'grocery': [
            ('Consorzio Italia', 3300, '0.15', '1.00'),
            ('Gruppo Aurora', 3000, '0.145', '1.00'),
            ('Cooperativa Nazionale', 1100, '0.123', '1.02'),
            ('Supermercati Lombardi', 180, '0.083', '1.06'),
            ('Mercato Verde', 3500, '0.075', '1.00'),
            ('Risparmio', 1300, '0.069', '0.92'),
            ('Prezzo Giusto', 700, '0.047', '0.93'),
        ],
        'restaurants': [('Panino Veloce', 700, '0.02', '0.95'), ('Trattoria Roma', 300, '0.01', '1.05')],
        'electronics': [('Elettrocasa', 500, '0.15', '0.98'), ('Tecnomondo', 150, '0.12', '1.00')],
    },
    'ES': {
        'grocery': [
            ('Mercado Levante', 1620, '0.254', '0.98'),
            ('Hiper Iberia', 1250, '0.097', '1.02'),
            ('Ahorra', 650, '0.059', '0.94'),
            ('Barrio', 2300, '0.048', '0.99'),
            ('Norte Cooperativa', 1000, '0.042', '1.02'),
        ],
        'restaurants': [('Burger Sol', 600, '0.02', '0.95'), ('Taberna Real', 300, '0.01', '1.05')],
        'electronics': [('Electromundo', 110, '0.25', '0.98'), ('Tecnoplaza', 200, '0.08', '1.00')],
    },
}


def get(dataset, query):
    url = f'{BASE}{dataset}?format=JSON&lang=EN&{query}'
    request = urllib.request.Request(url, headers={'User-Agent': 'market-game-stats'})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = json.load(response)
    ids = data['id']
    categories = []
    for key in ids:
        index = data['dimension'][key]['category']['index']
        categories.append(sorted(index, key=index.get))
    rows = []
    for position, value in data['value'].items():
        position = int(position)
        labels = []
        for names, size in zip(reversed(categories), reversed(data['size'])):
            labels.append(names[position % size])
            position //= size
        rows.append((dict(zip(ids, reversed(labels))), value))
    return rows


def table(dataset, query, *keys):
    """Rows of a dataset as a dictionary keyed by the given dimensions."""
    if len(keys) == 1:
        return {row[keys[0]]: value for row, value in get(dataset, query)}
    return {tuple(row[k] for k in keys): value for row, value in get(dataset, query)}


def years(first, last):
    return '&'.join(f'time={y}' for y in range(first, last + 1))


def fx(value):
    return f'{value:.4f}'


def money(value):
    return f'{value:.2f}'


def slope(xs, ys):
    return sum(x * y for x, y in zip(xs, ys)) / sum(x * x for x in xs)


def main():
    households = table('lfst_hhnhtych', f'{GEO}&time={YEAR}&agechild=TOTAL&n_child=TOTAL&phhcomp=TOTAL', 'geo')
    then_now = table('lfst_hhnhtych', f'{GEO}&time=2015&time=2023&agechild=TOTAL&n_child=TOTAL&phhcomp=TOTAL', 'geo', 'time')
    population = table('demo_gind', f'{GEO}&indic_de=JAN&time={YEAR}', 'geo')
    income = table('nasa_10_nf_tr', f'{GEO}&unit=CP_MEUR&na_item=B6G&sector=S14_S15&direct=RECV&time={YEAR}', 'geo')
    shares = table('ilc_di01', f'{GEO}&time={YEAR}&statinfo=SHARE&unit=EUR&' + '&'.join(f'quant_inc={q}' for q in QUINTILES), 'geo', 'quant_inc')
    codes = [c for group in SPENDING.values() for c in group]
    spent = table('nama_10_co3_p3', f'{GEO}&unit=CP_MEUR&time={YEAR}&' + '&'.join(f'coicop={c}' for c in codes), 'geo', 'coicop')
    structure = table('hbs_str_t223', f'{GEO}&time=2020&unit=PM&' + '&'.join(f'quant_inc={q}' for q in QUINTILES) + '&' + '&'.join(f'coicop={c}' for c in codes), 'geo', 'coicop', 'quant_inc')
    budget = table('hbs_exp_t133', f'{GEO}&time=2020&unit=PPS_HH&' + '&'.join(f'quant_inc={q}' for q in QUINTILES), 'geo', 'quant_inc')
    nace = sorted({n for group in TURNOVER.values() for n in group})
    indicators = ['NETTUR_MEUR', 'GM_GD_RS_MEUR', 'WAGE_MEUR', 'SS_COST_MEUR', 'GOS_MEUR']
    business = table('sbs_ovw_act', f'{GEO}&time={YEAR}&' + '&'.join(f'nace_r2={n}' for n in nace) + '&' + '&'.join(f'indic_sbs={i}' for i in indicators), 'geo', 'nace_r2', 'indic_sbs')
    # The latest census of local units is 2020, or 2019 before the pandemic for
    # restaurants, and Germany's 2019 is missing for the rest.
    units = {}
    for code in sorted({n for group in STORE_COUNTS.values() for n in group}):
        for (geo, time), value in table('sbs_r_nuts06_r2', f'{GEO}&time=2019&time=2020&nace_r2={code}&indic_sb=V11210', 'geo', 'time').items():
            wanted = '2019' if code == 'I56' else '2020'
            if time == wanted:
                units[(geo, code)] = value

    # How much each economy and trade moves with the euro area, 2000 to 2019.
    span = years(2000, 2019)
    volumes = table('nama_10_gdp', f'{GEO}&geo=EA20&na_item=P31_S14_S15&unit=CLV_PCH_PRE&{span}', 'geo', 'time')
    area = {t: v for (g, t), v in volumes.items() if g == 'EA20'}
    area_mean = st.mean(area.values())
    betas, trends = {}, {}
    for geo in COUNTRIES:
        series = {t: v for (g, t), v in volumes.items() if g == geo}
        mean = st.mean(series.values())
        betas[geo] = slope([area[t] - area_mean for t in area], [series[t] - mean for t in area])
        growth = (then_now[(geo, '2023')] / then_now[(geo, '2015')]) ** (1 / 8) - 1
        trends[geo] = (mean / 100 - growth, growth)
    by_trade = table('nama_10_co3_p3', f'{GEO}&unit=CLV_PCH_PRE&{span}&coicop=CP01&coicop=CP111&coicop=CP091&coicop=TOTAL', 'geo', 'coicop', 'time')
    trade_beta = {}
    for trade, code in {'grocery': 'CP01', 'restaurants': 'CP111', 'electronics': 'CP091'}.items():
        xs, ys = [], []
        for geo in COUNTRIES:
            time = [t for (g, c, t) in by_trade if g == geo and c == code]
            mx = st.mean(by_trade[(geo, 'TOTAL', t)] for t in time)
            my = st.mean(by_trade[(geo, code, t)] for t in time)
            xs += [by_trade[(geo, 'TOTAL', t)] - mx for t in time]
            ys += [by_trade[(geo, code, t)] - my for t in time]
        trade_beta[trade] = slope(xs, ys)

    # The prototype's business cycle, scaled to the size of real ones.
    with open(os.path.join(HERE, '..', 'scenarios', 'prototype.json'), encoding='utf-8') as f:
        regimes = json.load(f)['macro']['regimes']
    weight = sum(r['meanMonths'] for r in regimes)
    mean_demand = sum(r['meanMonths'] * float(r['demand']) for r in regimes) / weight
    spread = math.sqrt(sum(r['meanMonths'] * (float(r['demand']) - mean_demand) ** 2 for r in regimes) / weight)
    amplitude = st.pstdev(area.values()) / 100 / spread

    # Which class spends what: the survey's split of each kind of spending,
    # applied to the national accounts' total. Italy hasn't reported the survey
    # since 2005, so it takes the others' average split.
    split = {}
    for geo in COUNTRIES:
        for code in codes:
            if (geo, code, 'QU1') not in structure:
                continue
            weights = [structure[(geo, code, q)] * budget[(geo, q)] for q in QUINTILES]
            split[(geo, code)] = [w / sum(weights) for w in weights]
    for geo in COUNTRIES:
        for code in codes:
            if (geo, code) not in split:
                others = [split[(g, code)] for g in COUNTRIES if (g, code) in split]
                split[(geo, code)] = [st.mean(o[i] for o in others) for i in range(5)]

    countries = []
    fits = {trade: ([], []) for trade in SPENDING}
    for geo, name in COUNTRIES.items():
        total = round(households[geo] * 1000)
        per_class = total // 5
        counts = [per_class] * 4 + [total - per_class * 4]
        rows = []
        for i, (key, _, _) in enumerate(CLASSES):
            earned = income[geo] * 1e6 * shares[(geo, QUINTILES[i])] / 100 / counts[i]
            spending = {}
            for trade, group in SPENDING.items():
                amount = sum(spent[(geo, c)] * 1e6 / (1 + VAT[geo][c]) * split[(geo, c)][i] for c in group)
                spending[trade] = amount / counts[i]
            rows.append({'class': key, 'households': counts[i], 'income': money(earned), 'spending': {t: money(v) for t, v in spending.items()}})
            for trade in SPENDING:
                fits[trade][0].append(math.log(earned))
                fits[trade][1].append(math.log(spending[trade]))
        trades = {}
        for trade, group in TURNOVER.items():
            turnover = sum(business[(geo, n, 'NETTUR_MEUR')] for n in group)
            staff = sum(business[(geo, n, 'WAGE_MEUR')] + business[(geo, n, 'SS_COST_MEUR')] for n in group)
            surplus = sum(business[(geo, n, 'GOS_MEUR')] for n in group)
            if trade == 'restaurants':
                goods = turnover * RESTAURANT_GOODS
            else:
                goods = turnover - sum(business[(geo, n, 'GM_GD_RS_MEUR')] for n in group)
            trades[trade] = {
                'goods': fx(goods / turnover),
                'staff': fx(staff / turnover),
                'other': fx(1 - goods / turnover - staff / turnover - surplus / turnover),
                'stores': round(sum(units[(geo, n)] for n in STORE_COUNTS[trade])),
                'turnover': money(turnover * 1e6),
            }
        chains = []
        for trade, group in CHAINS[geo].items():
            taken = sum(float(c[2]) for c in group)
            stores = sum(c[1] for c in group)
            for chain, count, share, price in group:
                chains.append({'name': chain, 'trade': trade, 'stores': count, 'share': share, 'price': price})
            chains.append({'name': f'Independent {TRADES[trade][0].lower()}', 'trade': trade, 'stores': trades[trade]['stores'] - stores, 'share': fx(1 - taken), 'price': '1.00', 'independent': True})
        countries.append({
            'id': geo.lower(),
            'name': name,
            'population': round(population[geo]),
            'cycle': fx(betas[geo]),
            'householdGrowth': fx(trends[geo][1]),
            'realGrowth': fx(trends[geo][0]),
            'corporateTax': CORPORATE_TAX[geo],
            'classes': rows,
            'trades': trades,
            'chains': chains,
        })

    # Income elasticity of each trade, across classes within each country.
    elasticity = {}
    for trade, (xs, ys) in fits.items():
        dx, dy = [], []
        for i in range(0, len(xs), 5):
            mx, my = st.mean(xs[i:i + 5]), st.mean(ys[i:i + 5])
            dx += [x - mx for x in xs[i:i + 5]]
            dy += [y - my for y in ys[i:i + 5]]
        elasticity[trade] = slope(dx, dy)

    out = {
        'id': 'euro',
        'asOf': YEAR,
        'startDate': f'{YEAR + 1}-01-01',
        'sources': [
            'Households: Eurostat lfst_hhnhtych. Population: demo_gind.',
            'Income: disposable income of households, nasa_10_nf_tr (B6G, S14_S15), split by the survey shares in ilc_di01. It includes imputed rents, so it runs above what surveys report.',
            'Spending: national accounts, nama_10_co3_p3, less VAT, split between classes by the budget survey, hbs_str_t223 and hbs_exp_t133 (2020). Italy takes the average split of the others.',
            'Margins and turnover: structural business statistics, sbs_ovw_act. Restaurants\' goods are assumed at 30% of sales.',
            'Stores: local units, sbs_r_nuts06_r2.',
            'Cycle: household consumption volumes, 2000 to 2019, nama_10_gdp and nama_10_co3_p3. Amplitude is the euro area\'s spread over the spread of the prototype\'s regimes.',
            'Chains are fictional. See build_euro.py for what their shares follow and which figures are rough estimates.',
        ],
        'amplitude': fx(amplitude),
        'storeResponse': '2.0',
        'fitOut': '0.25',
        'startRegime': 'expansion',
        'regimes': [
            {'id': r['id'], 'name': r['name'], 'meanMonths': r['meanMonths'], 'inflation': r['inflation'], 'realWageGrowth': r['realWageGrowth'], 'demand': r['demand']}
            for r in regimes
        ],
        'classes': [{'id': k, 'name': n, 'priceFactor': p} for k, n, p in CLASSES],
        'trades': [
            {'id': t, 'name': TRADES[t][0], 'description': TRADES[t][1], 'cycle': fx(trade_beta[t]), 'incomeElasticity': fx(elasticity[t])}
            for t in SPENDING
        ],
        'countries': countries,
    }
    with open(os.path.join(HERE, 'euro.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    for c in countries:
        print(c['name'], 'households', sum(r['households'] for r in c['classes']), 'cycle', c['cycle'], 'growth', c['householdGrowth'], 'real', c['realGrowth'])
    print('amplitude', out['amplitude'], 'trades', out['trades'])


if __name__ == '__main__':
    main()
