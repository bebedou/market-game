# Adds the countries beyond France to the prototype scenario: each country's
# taxes, how its economy takes the shared cycle, its suppliers, what it calls
# generated people, streets and shops, and its districts. Figures that differ
# between countries come from Eurostat's public API; the districts' own
# figures (who lives there, rents, how dear and well off they are against the
# country) are rough estimates written below. France stays as it is.
#
#   python build_places.py           writes places.json, for the step below
#   dart run tool/add_places.dart    (in packages/engine) puts it in the scenario
import json
import math
import os
import statistics as st
import urllib.request

BASE = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/'
HERE = os.path.dirname(os.path.abspath(__file__))
YEAR = 2022
# France first: places that name no country are its.
GEO = ['FR', 'DE', 'IT', 'ES']


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
    rows = {}
    for position, value in data['value'].items():
        position = int(position)
        labels = []
        for names, size in zip(reversed(categories), reversed(data['size'])):
            labels.append(names[position % size])
            position //= size
        rows[tuple(reversed(labels))] = value
    return ids, rows


def by(dataset, query, *keys):
    ids, rows = get(dataset, query)
    return {tuple(label[ids.index(k)] for k in keys): v for label, v in rows.items()}


def fx(value, places=2):
    return f'{value:.{places}f}'


GEOS = '&'.join(f'geo={g}' for g in GEO)

# How dear each country is against France, by Eurostat's price level indices:
# food for groceries, restaurants and hotels, and recreation for electronics,
# weighted as the prototype's French cities spend.
pli = by('prc_ppp_ind', f'{GEOS}&time={YEAR}&na_item=PLI_EU27_2020&ppp_cat=A0101&ppp_cat=A0111&ppp_cat=A0109', 'ppp_cat', 'geo')
WEIGHTS = {'A0101': 0.62, 'A0111': 0.30, 'A0109': 0.08}
prices = {g: sum(w * pli[(c, g)] / pli[(c, 'FR')] for c, w in WEIGHTS.items()) for g in GEO}

# What staff cost against France: hourly labour costs in retail (G) and in
# restaurants (I), weighted the same way.
labour = by('lc_lci_lev', f'{GEOS}&time={YEAR}&lcstruct=D1_D4_MD5&unit=EUR&nace_r2=G&nace_r2=I', 'nace_r2', 'geo')
wages = {g: 0.70 * labour[('G', g)] / labour[('G', 'FR')] + 0.30 * labour[('I', g)] / labour[('I', 'FR')] for g in GEO}

# The national table built by build_euro.py: its households.
with open(os.path.join(HERE, 'euro.json'), encoding='utf-8') as f:
    euro = {c['id'].upper(): c for c in json.load(f)['countries']}
households = {g: sum(r['households'] for r in euro[g]['classes']) for g in GEO}

# Shelf prices. Goods cost the same across the euro area, so each country's
# wholesalers charge what France's do; what a shop adds over its goods is
# mostly its staff's work, so it is paid at local wages (the Balassa-Samuelson
# effect): the game takes each product's normal price beyond its base cost at
# the country's wages, its `service`. Shops in poorer countries then sell for
# less over what their goods cost, which their cheaper staff make up for only
# in part, and a restaurant, mostly work, comes out cheaper still than a
# grocer. For Spain this gives a meal at 0.70 of France's (Eurostat: 0.74 for
# restaurants) and milk at 0.87 (0.94 for food: real Spanish grocers keep
# more over their goods than this leaves them). A place's own price level is then only
# how dear it is within its country.
costs = {g: 1.0 for g in GEO}

# The cycle, from household consumption volumes, 2000 to 2019: how often a
# country follows the euro area's turns (the correlation of their yearly
# changes), and how far it swings against France, softened by a square root as
# the game's downturns are already deeper than real ones.
years = '&'.join(f'time={y}' for y in range(2000, 2020))
volumes = by('nama_10_gdp', f'{GEOS}&geo=EA20&na_item=P31_S14_S15&unit=CLV_PCH_PRE&{years}', 'geo', 'time')
area = [volumes[('EA20', str(y))] for y in range(2000, 2020)]
series = {g: [volumes[(g, str(y))] for y in range(2000, 2020)] for g in GEO}
follows = {g: st.correlation(series[g], area) for g in GEO}
depth = {g: math.sqrt(st.pstdev(series[g]) / st.pstdev(series['FR'])) for g in GEO}

# Taxes: combined statutory corporate rates (OECD Tax Database, 2022) and the
# flat or typical rate on dividends paid to a resident.
TAXES = {
    'DE': {'reducedRate': '0.2990', 'reducedLimit': '0.00', 'corporateRate': '0.2990', 'dividendRate': '0.2638'},
    'IT': {'reducedRate': '0.2790', 'reducedLimit': '0.00', 'corporateRate': '0.2790', 'dividendRate': '0.26'},
    'ES': {'reducedRate': '0.25', 'reducedLimit': '0.00', 'corporateRate': '0.25', 'dividendRate': '0.23'},
}

NAMES = {
    'FR': {
        'first': ['Nadia', 'Marc', 'Sophie', 'Karim', 'Julie', 'Antoine', 'Inès', 'Paul', 'Claire', 'Yanis', 'Léa', 'Hugo', 'Camille', 'Omar', 'Anne', 'Louis'],
        'last': ['Moreau', 'Benali', 'Girard', 'Fontaine', 'Roche', 'Lemoine', 'Perrin', 'Chevalier', 'Mercier', 'Blanc', 'Garnier', 'Faure', 'Rousset', 'Colin'],
        'streets': ['Vivier', 'Servient', 'Brotteaux', 'Garibaldi', 'Dauphiné', 'Moncey', 'Lafayette', 'Bellecour', 'Massena', 'Tolozan', 'Gambetta', 'Carnot', 'Jaurès', 'Voltaire', 'Pasteur', 'Hugo', 'Foch', 'Thiers', 'Mermoz', 'Sévigné', 'Colbert', 'Diderot', 'Rameau', 'Lamartine', 'Montaigne'],
        'streetKinds': ['Rue', 'Place', 'Cours', 'Avenue', 'Passage'],
        'shops': {
            'grocery': ['Épicerie', 'Marché', 'Halles', 'Comptoir', 'Panier', 'Prix'],
            'supermarket': ['Super', 'Grand Marché'],
            'fastfood': ['Burger', 'Snack', 'Frites'],
            'steakhouse': ['Le Grill', 'La Braise', 'Bœuf'],
            'finedining': ['Table', 'Maison', 'Le Comptoir'],
            'electronics': ['Tech', 'Hi-Fi', 'Mobile'],
        },
    },
    'DE': {
        'first': ['Anna', 'Lukas', 'Mia', 'Jonas', 'Lena', 'Felix', 'Emre', 'Sophie', 'Paul', 'Leonie', 'Mehmet', 'Laura', 'Tim', 'Hannah', 'Jan', 'Elif'],
        'last': ['Müller', 'Schmidt', 'Schneider', 'Fischer', 'Weber', 'Wagner', 'Becker', 'Hoffmann', 'Schulz', 'Koch', 'Yılmaz', 'Richter', 'Klein', 'Wolf', 'Neumann', 'Braun'],
        'streets': ['Goethe', 'Schiller', 'Linden', 'Kastanien', 'Ahorn', 'Berg', 'Garten', 'Markt', 'Kirch', 'Mühlen', 'Hafen', 'Bahnhof', 'Wiesen', 'Rosen', 'Eichen', 'Brunnen', 'Sonnen', 'Kloster', 'Heine', 'Lessing', 'Kant', 'Humboldt', 'Bergmann', 'Wilhelm', 'Luisen'],
        'streetKinds': ['{}straße', '{}platz', '{}weg', '{}allee', '{}gasse'],
        'shops': {
            'grocery': ['{}-Markt', 'Feinkost {}', '{}-Laden', 'Frischmarkt {}', '{}-Kauf'],
            'supermarket': ['{}-Center', 'Großmarkt {}'],
            'fastfood': ['Imbiss {}', 'Döner {}', '{} Burger'],
            'steakhouse': ['Steakhaus {}', '{}-Grill'],
            'finedining': ['Restaurant {}', 'Gasthaus {}', '{}stube'],
            'electronics': ['Elektro {}', '{}-Technik', 'Funkhaus {}'],
        },
    },
    'IT': {
        'first': ['Giulia', 'Marco', 'Sofia', 'Luca', 'Chiara', 'Matteo', 'Francesca', 'Alessandro', 'Sara', 'Davide', 'Elena', 'Andrea', 'Martina', 'Giorgio', 'Anna', 'Paolo'],
        'last': ['Rossi', 'Russo', 'Ferrari', 'Esposito', 'Bianchi', 'Romano', 'Colombo', 'Ricci', 'Marino', 'Greco', 'Bruno', 'Gallo', 'Conti', 'De Luca', 'Costa', 'Fontana'],
        'streets': ['Garibaldi', 'Mazzini', 'Cavour', 'Verdi', 'Dante', 'Manzoni', 'Marconi', 'Venezia', 'Matteotti', 'Gramsci', 'Volta', 'Leopardi', 'Galilei', 'Carducci', 'Puccini', 'Foscolo', 'Pascoli', 'Petrarca', 'Tasso', 'Ariosto', 'Bellini', 'Rossini', 'Vespucci', 'Tiepolo', 'Canova'],
        'streetKinds': ['Via', 'Piazza', 'Corso', 'Viale', 'Largo'],
        'shops': {
            'grocery': ['Alimentari', 'Bottega', 'Mercato', 'Dispensa', 'Market'],
            'supermarket': ['Super', 'Ipermercato'],
            'fastfood': ['Panini', 'Piadineria', 'Burger'],
            'steakhouse': ['Braceria', 'Griglia'],
            'finedining': ['Ristorante', 'Osteria', 'Locanda'],
            'electronics': ['Elettronica', 'Tecno', 'Digitale'],
        },
    },
    'ES': {
        'first': ['Lucía', 'Hugo', 'Martina', 'Pablo', 'Sofía', 'Daniel', 'María', 'Alejandro', 'Paula', 'Javier', 'Carmen', 'Marc', 'Laia', 'Adrián', 'Elena', 'Youssef'],
        'last': ['García', 'Fernández', 'González', 'Rodríguez', 'López', 'Martínez', 'Sánchez', 'Pérez', 'Gómez', 'Martín', 'Jiménez', 'Ruiz', 'Hernández', 'Díaz', 'Moreno', 'Puig'],
        'streets': ['Mayor', 'Alcalá', 'Colón', 'Cervantes', 'Goya', 'Velázquez', 'Prado', 'Sol', 'Princesa', 'Luna', 'Rosales', 'Olivo', 'Laurel', 'Murillo', 'Quevedo', 'Machado', 'Zurbarán', 'Sorolla', 'Lorca', 'Gaudí', 'Ribera', 'Balmes', 'Verdi', 'Fuencarral', 'Atocha'],
        'streetKinds': ['Calle', 'Plaza', 'Paseo', 'Avenida', 'Travesía'],
        'shops': {
            'grocery': ['Ultramarinos', 'Colmado', 'Mercado', 'Despensa', 'Súper'],
            'supermarket': ['Hiper', 'Gran Mercado'],
            'fastfood': ['Bocatas', 'Burger', 'Tapas'],
            'steakhouse': ['Asador', 'Parrilla'],
            'finedining': ['Restaurante', 'Casa', 'Mesón'],
            'electronics': ['Electro', 'Tecno', 'Digital'],
        },
    },
}

NAMES_OF = {'FR': 'France', 'DE': 'Germany', 'IT': 'Italy', 'ES': 'Spain'}

# Each country's wholesalers, standing in for France's four: their names,
# delivery times and terms. In Italy and Spain suppliers wait longer to be
# paid, as they do there (Intrum, European Payment Report 2023).
SUPPLIERS = {
    'DE': [
        ('de_bulk', 'Vorrat Großmarkt', 3, 0, 'bulkway'),
        ('de_fresh', 'Frischdienst Weber', 1, 30, 'freshline'),
        ('de_chef', 'Gastro Kontor', 1, 30, 'chefsupply'),
        ('de_tech', 'TechVertrieb', 3, 30, 'techdistri'),
    ],
    'IT': [
        ('it_bulk', 'Ingrosso Lombardo', 3, 0, 'bulkway'),
        ('it_fresh', 'Fresco Distribuzione', 1, 60, 'freshline'),
        ('it_chef', 'CucinaPro Ingrosso', 2, 60, 'chefsupply'),
        ('it_tech', 'TecnoDistribuzione', 4, 60, 'techdistri'),
    ],
    'ES': [
        ('es_bulk', 'Mayorista Central', 3, 0, 'bulkway'),
        ('es_fresh', 'Distribuciones Frescas', 1, 30, 'freshline'),
        ('es_chef', 'HostelSur Suministros', 1, 60, 'chefsupply'),
        ('es_tech', 'TecnoDistribución Ibérica', 4, 60, 'techdistri'),
    ],
}

# Districts: a French place like it, whose market and mix it starts from,
# scaled by its size and by what the country's households spend on each trade
# against France's, and its own levels, rents and grocers' sites. The first of
# each city is played in full when the game starts there; the others sleep.
# Levels are against the usual (France's): prices and wages start from the
# country's and are adjusted for the city, incomes are how well off its
# households are. Rents are a month's per m² at a middling location.
PLACES = [
    # Germany
    ('berlin', 'Berlin, Kreuzberg', 'DE', 'neighborhood', 1.10, 1.00, 1.00, 1.02, 9.00, (115, 150, 40), True,
     {'families': .16, 'professionals': .20, 'students': .16, 'retirees': .08, 'singles': .34, 'comfortable': .06}),
    ('prenzlauerberg', 'Berlin, Prenzlauer Berg', 'DE', 'confluence', 1.05, 1.03, 1.02, 1.18, 11.00, (115, 150, 40), False,
     {'families': .30, 'professionals': .28, 'students': .06, 'retirees': .06, 'singles': .18, 'comfortable': .12}),
    ('neukolln', 'Berlin, Neukölln', 'DE', 'villeurbanne', 0.95, 0.96, 0.98, 0.84, 5.50, (110, 140, 40), False,
     {'families': .26, 'professionals': .10, 'students': .20, 'retirees': .10, 'singles': .32, 'comfortable': .02}),
    ('munich', 'Munich, Schwabing', 'DE', 'bordeaux', 1.00, 1.08, 1.10, 1.32, 16.00, (110, 140, 40), True,
     {'families': .16, 'professionals': .28, 'students': .10, 'retirees': .12, 'singles': .20, 'comfortable': .14}),
    ('maxvorstadt', 'Munich, Maxvorstadt', 'DE', 'presquile', 0.90, 1.06, 1.08, 1.12, 14.00, (105, 130, 40), False,
     {'families': .06, 'professionals': .26, 'students': .32, 'retirees': .06, 'singles': .24, 'comfortable': .06}),
    ('haidhausen', 'Munich, Haidhausen', 'DE', 'confluence', 1.00, 1.06, 1.08, 1.24, 12.00, (110, 140, 40), False,
     {'families': .28, 'professionals': .26, 'students': .06, 'retirees': .14, 'singles': .16, 'comfortable': .10}),
    # Italy
    ('milan', 'Milan, Navigli', 'IT', 'neighborhood', 1.05, 1.05, 1.08, 1.08, 12.00, (100, 130, 30), True,
     {'families': .16, 'professionals': .24, 'students': .14, 'retirees': .12, 'singles': .28, 'comfortable': .06}),
    ('brera', 'Milan, Brera', 'IT', 'presquile', 0.85, 1.12, 1.10, 1.42, 20.00, (90, 110, 30), False,
     {'families': .08, 'professionals': .30, 'students': .08, 'retirees': .14, 'singles': .22, 'comfortable': .18}),
    ('isola', 'Milan, Isola', 'IT', 'partdieu', 0.90, 1.06, 1.08, 1.12, 11.00, (100, 130, 30), False,
     {'families': .18, 'professionals': .30, 'students': .10, 'retirees': .10, 'singles': .26, 'comfortable': .06}),
    ('rome', 'Rome, Trastevere', 'IT', 'montpellier', 1.10, 1.02, 1.03, 0.96, 11.00, (95, 120, 30), True,
     {'families': .12, 'professionals': .16, 'students': .24, 'retirees': .16, 'singles': .28, 'comfortable': .04}),
    ('prati', 'Rome, Prati', 'IT', 'meriadeck', 1.00, 1.06, 1.04, 1.18, 10.00, (100, 130, 30), False,
     {'families': .24, 'professionals': .22, 'students': .06, 'retirees': .22, 'singles': .16, 'comfortable': .10}),
    ('pigneto', 'Rome, Pigneto', 'IT', 'villeurbanne', 0.85, 0.96, 0.98, 0.80, 5.00, (95, 120, 30), False,
     {'families': .26, 'professionals': .10, 'students': .22, 'retirees': .12, 'singles': .28, 'comfortable': .02}),
    # Spain
    ('madrid', 'Madrid, Malasaña', 'ES', 'neighborhood', 1.05, 1.03, 1.10, 1.00, 9.00, (100, 130, 30), True,
     {'families': .14, 'professionals': .22, 'students': .18, 'retirees': .10, 'singles': .32, 'comfortable': .04}),
    ('salamanca', 'Madrid, Salamanca', 'ES', 'passy', 0.80, 1.12, 1.12, 1.45, 16.00, (100, 130, 30), False,
     {'families': .20, 'professionals': .20, 'students': .04, 'retirees': .24, 'singles': .12, 'comfortable': .20}),
    ('lavapies', 'Madrid, Lavapiés', 'ES', 'belleville', 0.80, 0.96, 1.05, 0.78, 5.50, (90, 120, 30), False,
     {'families': .22, 'professionals': .10, 'students': .22, 'retirees': .12, 'singles': .32, 'comfortable': .02}),
    ('barcelona', 'Barcelona, Gràcia', 'ES', 'neighborhood', 1.00, 1.03, 1.08, 1.02, 8.50, (100, 130, 30), True,
     {'families': .22, 'professionals': .22, 'students': .14, 'retirees': .12, 'singles': .26, 'comfortable': .04}),
    ('eixample', 'Barcelona, Eixample', 'ES', 'presquile', 0.90, 1.08, 1.10, 1.20, 12.00, (110, 140, 30), False,
     {'families': .20, 'professionals': .28, 'students': .08, 'retirees': .16, 'singles': .20, 'comfortable': .08}),
    ('poblenou', 'Barcelona, Poblenou', 'ES', 'gerland', 0.95, 1.01, 1.06, 1.02, 7.50, (115, 150, 40), False,
     {'families': .26, 'professionals': .26, 'students': .12, 'retirees': .08, 'singles': .24, 'comfortable': .04}),
]

# How fast each kind of household grows a year, by country: households grow
# with the country's trend (build_euro.py), students and retirees as in France.
SEGMENTS = ['families', 'professionals', 'students', 'retirees', 'singles', 'comfortable']

# Which household spending makes up each of the game's trades, in the
# national table.
TRADE_OF = {'grocery': 'grocery', 'fastfood': 'restaurants', 'steakhouse': 'restaurants', 'finedining': 'restaurants', 'electronics': 'electronics'}


def per_household(geo, trade):
    rows = euro[geo]['classes']
    total = sum(r['households'] for r in rows)
    return sum(r['households'] * float(r['spending'][trade]) for r in rows) / total


def main():
    with open(os.path.join(HERE, '..', 'scenarios', 'prototype.json'), encoding='utf-8') as f:
        scenario = json.load(f)
    french = {m['id']: m for m in scenario['markets'] + scenario['neighbourhoods']}
    spends = {g: {t: per_household(g, t) / per_household('FR', t) for t in ('grocery', 'restaurants', 'electronics')} for g in GEO}

    countries = []
    for geo in GEO:
        entry = {'id': geo.lower(), 'name': NAMES_OF[geo]}
        if geo in TAXES:
            entry['taxes'] = TAXES[geo]
        entry['cycle'] = {'follows': fx(min(follows[geo], 0.95)), 'depth': fx(depth[geo] / depth['FR'])} if geo != 'FR' else {'follows': fx(min(follows[geo], 0.95))}
        entry['weight'] = fx(households[geo] / 1e6, 1)
        if geo != 'FR':
            entry['service'] = fx(wages[geo])
        entry['names'] = NAMES[geo]
        entry['national'] = geo.lower()
        countries.append(entry)

    suppliers = []
    by_id = {s['id']: s for s in scenario['suppliers']}
    for geo, rows in SUPPLIERS.items():
        for key, name, lead, terms, like in rows:
            model = by_id[like]
            supplier = dict(model)
            supplier.update({
                'id': key,
                'name': name,
                'country': geo.lower(),
                'leadTimeDays': lead,
                'paymentTermsDays': terms,
                'priceFactor': fx(float(model['priceFactor']) * costs[geo]),
            })
            suppliers.append(supplier)

    places = []
    for key, name, geo, twin, size, price, wage, income, rent, (area, largest, room), start, mix in PLACES:
        model = french[twin]
        market = {}
        for trade, amount in model['market'].items():
            market[trade] = fx(float(amount) * size * spends[geo][TRADE_OF[trade]])
        growth = {}
        trend = float(euro[geo]['householdGrowth'])
        for segment in SEGMENTS:
            base = float(model['growth'][segment])
            # France's district rates, moved by how much faster or slower the
            # country's households grow than France's.
            growth[segment] = fx(base + trend - float(euro['FR']['householdGrowth']), 3)
        total = sum(mix.values())
        places.append({
            'id': key,
            'name': name,
            'country': geo.lower(),
            'market': market,
            'mix': {s: fx(mix[s] / total, 4) for s in SEGMENTS},
            'growth': growth,
            'priceLevel': fx(price),
            'wageLevel': fx(wages[geo] * wage),
            'incomeLevel': fx(income),
            'rent': fx(rent),
            'typicalArea': area,
            'largestArea': largest,
            'room': room,
            'start': start,
        })

    out = {
        'sources': [
            'Price levels (for comparison only): Eurostat prc_ppp_ind, PLI_EU27_2020, 2022: food (A0101), restaurants and hotels (A0111) and recreation (A0109), weighted 0.62, 0.30 and 0.08.',
            'Wages: hourly labour costs, lc_lci_lev, 2022, retail (G) 0.70 and restaurants (I) 0.30.',
            "Shelf prices: each product's normal price beyond its base cost at the country's wages (service); wholesale as France's. A place's price level is how dear it is within its country.",
            'Cycle: household consumption volumes, nama_10_gdp, 2000 to 2019. Follows: the correlation of yearly changes with the euro area (at most 0.95). Depth: the square root of the spread of yearly changes against France\'s.',
            'Taxes: OECD Tax Database 2022 for corporate rates; dividends at the flat or typical rate for a resident.',
            'Districts: rough estimates, scaled from French places like them by what each country\'s households spend per trade (euro.json).',
        ],
        'prices': {g: fx(prices[g], 4) for g in GEO},
        'wages': {g: fx(wages[g], 4) for g in GEO},
        'costs': {g: fx(costs[g], 4) for g in GEO},
        'countries': countries,
        'suppliers': suppliers,
        'places': places,
    }
    with open(os.path.join(HERE, 'places.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    for geo in GEO:
        print(geo, 'prices', fx(prices[geo], 3), 'wages', fx(wages[geo], 3), 'costs', fx(costs[geo], 3),
              'follows', fx(follows[geo], 3), 'depth', fx(depth[geo] / depth['FR'], 3), 'spend', {t: fx(v, 2) for t, v in spends[geo].items()})


if __name__ == '__main__':
    main()
