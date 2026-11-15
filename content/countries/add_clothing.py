# Adds clothing, the first of the new trades, to prototype.json and its
# translations: four categories that go out of fashion, their goods, what
# each kind of household buys of them, the clothing shop, three strategies,
# a collection supplier and a quick one in each country, what each place
# spends on clothes, and two rival clothing shops in each city. New entries
# go at the end of their lists, as saved games allow. Run once, after
# build_euro.py has put clothing in euro.json; it stops if clothing is there.
#
#   python add_clothing.py
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, '..', 'scenarios')
SCENARIO = os.path.join(SCENARIOS, 'prototype.json')

# Each category: its goods (name, base cost, normal price) by tier, and how
# fast they go out of fashion: days new, worth lost a month after that for
# the budget and the premium tier, the lowest it falls to, and what a jobber
# pays of their cost.
CATEGORIES = [
    ('womenswear', 'Womenswear', ("Women's basics", '8.40', '19.90'), ("Women's designer pieces", '37.00', '89.00'), (45, '0.12', '0.05', '0.35', '0.25')),
    ('menswear', 'Menswear', ("Men's basics", '9.60', '22.90'), ("Men's tailoring", '50.00', '119.00'), (60, '0.08', '0.04', '0.40', '0.25')),
    ('kidswear', 'Kidswear', ("Kids' clothes", '6.20', '14.90'), ("Kids' outerwear", '20.50', '49.00'), (60, '0.08', '0.05', '0.40', '0.25')),
    ('shoes', 'Shoes', ('Trainers', '15.50', '34.90'), ('Leather shoes', '46.00', '109.00'), (75, '0.06', '0.03', '0.45', '0.25')),
]

# What an average household buys a day of each category, and the share it
# buys premium: about 1,200 a year in all at normal prices, a French
# household's spending on clothes and shoes less VAT (euro.json), split as
# the budget survey splits it; times what the game's households buy against
# real ones, about a fifth, as the places' figures for clothing against
# their households say. Each place's figure then scales it, by about one.
HOUSEHOLD = 0.20
UNITS = {k: v * HOUSEHOLD for k, v in {'womenswear': 0.045, 'menswear': 0.020, 'kidswear': 0.019, 'shoes': 0.012}.items()}
PREMIUM = {'womenswear': 0.20, 'menswear': 0.18, 'kidswear': 0.15, 'shoes': 0.20}
# Each kind of household against that: how much it buys, of kids' clothes
# above all, how far it buys premium, and how much it minds goods going out
# of fashion.
SEGMENTS = {
    'families': (1.0, 3.0, 0.6, '0.70'),
    'professionals': (1.2, 0.3, 1.4, '0.90'),
    'students': (0.9, 0.02, 0.5, '1.00'),
    'retirees': (0.6, 0.4, 1.0, '0.40'),
    'singles': (1.0, 0.1, 1.0, '1.00'),
    'comfortable': (1.3, 2.0, 2.2, '0.80'),
}

FORMAT = {
    'id': 'clothing', 'overheads': '4.50', 'name': 'Clothing shop',
    'categories': [c[0] for c in CATEGORIES], 'fitOut': '2.0', 'visitsPerStaff': 8, 'wageFactor': '1.6',
    # A trade added after places were described: they keep the households
    # they had, clothing's figure only scaling what they buy of it, and a
    # district woken before it is rebuilt without it.
    'edition': 1,
}

STRATEGY = {
    'markup': '1.10', 'minMarkup': '0.25', 'marketPosition': '0', 'marketWeight': '0.50', 'maxPriceStep': '0.05',
    'priceReviewDays': 7, 'maxOverpricedShare': '0.10', 'premiumBias': '1.1', 'assortmentReviewDays': 28,
    'assortmentHysteresis': '0.25', 'forecastDays': 28, 'openingForecast': '1.5', 'safetyDays': 10,
    'orderCycleDays': 30, 'reserveDays': 45, 'expansionPaybackMonths': 10, 'expansionIntervalDays': 730,
    'marginPerHousehold': '0.10', 'hours': ['morning', 'midday', 'evening'], 'serviceTarget': '1.2',
    'openingTraffic': 15, 'marketingShare': '0.030',
}
STRATEGIES = [
    ('fastfashion', 'Fast fashion', {'markup': '0.90', 'minMarkup': '0.20', 'marketPosition': '-0.08', 'premiumBias': '0.6', 'safetyDays': 7, 'orderCycleDays': 21, 'openingForecast': '2', 'serviceTarget': '1.0'}),
    ('clothing', 'Clothing retail', {}),
    ('boutique', 'Boutique', {'markup': '1.40', 'minMarkup': '0.35', 'marketPosition': '0.08', 'premiumBias': '2.0', 'safetyDays': 14, 'orderCycleDays': 45, 'serviceTarget': '1.6', 'marketingShare': '0.040'}),
]

# A collection house, cheap but slow and in bulk, and a quick one, dearer
# by the piece, in each country.
SUPPLIERS = {
    None: ('modeline', 'Modeline Collections', 'pretexpress', 'Prêt Express'),
    'de': ('de_collection', 'Kollektion Nord', 'de_quick', 'Mode Express'),
    'it': ('it_collection', 'Collezioni Italia', 'it_quick', 'Moda Rapida'),
    'es': ('es_collection', 'Colecciones Ibéricas', 'es_quick', 'Moda Exprés'),
}

# Two rival shops a city: a fast-fashion one, and a balanced or boutique
# one. Shop name, street, owner.
SHOPS = {
    'neighborhood': [('Fil et Mode', "Rue d'Austerlitz", 'Léa Moreau'), ('Atelier Canut', 'Grande Rue de la Croix-Rousse', 'Hugo Lefèvre')],
    'montpellier': [('Tendances du Sud', "Rue de l'Aiguillerie", 'Camille Roux'), ('Maison Écusson', 'Rue Foch', 'Théo Fournier')],
    'bordeaux': [('Mode Garonne', 'Rue Sainte-Catherine', 'Inès Girard'), ('Boutique des Chartrons', 'Rue Notre-Dame', 'Louis Bonnet')],
    'reze': [('Tissus et Cie', 'Rue Alsace-Lorraine', 'Chloé Mercier'), ("L'Atelier Rezéen", 'Place du 8 Mai', 'Jules Lambert')],
    'lille': [('Mode du Nord', 'Rue de Béthune', 'Manon Faure'), ('Maison Vauban', 'Rue Esquermoise', 'Nathan Rousseau')],
    'marseille': [('Prix Doux Mode', 'Rue Saint-Ferréol', 'Zoé Blanc'), ('Atelier du Panier', 'Rue du Panier', 'Lucas Garnier')],
    'paris': [('Basiques Paris', 'Rue de Rivoli', 'Emma Chevalier'), ('Maison Marais', 'Rue des Francs-Bourgeois', 'Adam Perrin')],
    'berlin': [('Kiezmode', 'Bergmannstraße', 'Lena Schmidt'), ('Atelier Kreuzberg', 'Oranienstraße', 'Jonas Wagner')],
    'munich': [('Modestadl', 'Sendlinger Straße', 'Mia Becker'), ('Haus Lehel', 'Maximilianstraße', 'Felix Hoffmann')],
    'milan': [('Moda Navigli', 'Corso di Porta Ticinese', 'Giulia Ricci'), ('Sartoria Brera', 'Via Brera', 'Marco Conti')],
    'rome': [('Moda Trastevere', 'Viale di Trastevere', 'Sofia Greco'), ('Bottega Monti', 'Via del Boschetto', 'Luca Marino')],
    'madrid': [('Moda Malasaña', 'Calle de Fuencarral', 'Lucía Navarro'), ('Taller Salamanca', 'Calle de Serrano', 'Javier Ortega')],
    'barcelona': [('Moda Gràcia', 'Carrer Gran de Gràcia', 'Carmen Ruiz'), ('Taller Born', "Carrer de l'Argenteria", 'Pablo Molina')],
}
BOUTIQUES = {'paris', 'milan', 'munich', 'bordeaux', 'madrid'}
# What new clothing shops are called in each country, around a street name.
SHOP_WORDS = {
    'fr': ['Mode', 'Boutique', 'Atelier'],
    'de': ['Mode {}', 'Boutique {}', 'Modehaus {}'],
    'it': ['Moda', 'Boutique', 'Atelier'],
    'es': ['Moda', 'Boutique', 'Taller'],
}
# What a clothing shop's street costs a square metre against the city's
# dearest site so far.
PRIME = 1.6

TRANSLATIONS = {
    'en': {
        'formats': {'clothing': {'a': 'a clothing shop', 'blurb': 'Clothes and shoes: high margins and dear rents, collections ordered ahead, and stock that goes out of fashion if it sits.'}},
    },
    'fr': {
        'categories': {'womenswear': 'Mode femme', 'menswear': 'Mode homme', 'kidswear': 'Mode enfant', 'shoes': 'Chaussures'},
        'formats': {'clothing': {'name': 'Boutique de vêtements', 'a': 'une boutique de vêtements', 'blurb': 'Vêtements et chaussures : de fortes marges et des loyers chers, des collections commandées à l’avance, et un stock qui se démode s’il traîne.'}},
        'products': {
            'womenswear_budget': 'Basiques femme', 'womenswear_premium': 'Pièces de créateur femme',
            'menswear_budget': 'Basiques homme', 'menswear_premium': 'Costumes homme',
            'kidswear_budget': 'Vêtements enfant', 'kidswear_premium': 'Manteaux enfant',
            'shoes_budget': 'Baskets', 'shoes_premium': 'Chaussures en cuir',
        },
        'strategies': {'fastfashion': 'Mode rapide', 'clothing': 'Commerce de vêtements', 'boutique': 'Boutique'},
    },
    'es': {
        'categories': {'womenswear': 'Moda mujer', 'menswear': 'Moda hombre', 'kidswear': 'Moda infantil', 'shoes': 'Calzado'},
        'formats': {'clothing': {'name': 'Tienda de ropa', 'a': 'una tienda de ropa', 'blurb': 'Ropa y calzado: márgenes altos y alquileres caros, colecciones pedidas con antelación, y un stock que pasa de moda si se queda.'}},
        'products': {
            'womenswear_budget': 'Básicos de mujer', 'womenswear_premium': 'Piezas de diseño de mujer',
            'menswear_budget': 'Básicos de hombre', 'menswear_premium': 'Sastrería de hombre',
            'kidswear_budget': 'Ropa infantil', 'kidswear_premium': 'Abrigos infantiles',
            'shoes_budget': 'Zapatillas', 'shoes_premium': 'Zapatos de piel',
        },
        'strategies': {'fastfashion': 'Moda rápida', 'clothing': 'Comercio de ropa', 'boutique': 'Boutique'},
    },
}


def line(entry, indent='    '):
    return indent + json.dumps(entry, ensure_ascii=False, separators=(', ', ': '))


def list_span(text, key):
    """The top-level list [key]: the index of its '[' and of its ']'."""
    start = text.index(f'\n  "{key}": [')
    i = text.index('[', start)
    open_at = i
    depth = 0
    in_string = False
    while True:
        ch = text[i]
        if in_string:
            if ch == '\\':
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch in '[{':
            depth += 1
        elif ch in ']}':
            depth -= 1
            if depth == 0:
                return open_at, i
        i += 1


def entries(text, key):
    """The spans of the top-level list [key]'s entries, in order."""
    open_at, close_at = list_span(text, key)
    spans = []
    i = open_at + 1
    depth = 0
    in_string = False
    start = None
    while i < close_at:
        ch = text[i]
        if in_string:
            if ch == '\\':
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch == '{':
            if depth == 0:
                start = i
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                spans.append((start, i + 1))
        i += 1
    return spans


def append(text, key, new):
    _, close_at = list_span(text, key)
    body = text[:close_at].rstrip()
    rest = text[close_at:]
    return body + ',\n' + ',\n'.join(line(e) for e in new) + '\n  ' + rest.lstrip(' ')


def edit_entries(text, key, change):
    """[change] each of list [key]'s entries, given its text and its index."""
    spans = entries(text, key)
    for index in range(len(spans) - 1, -1, -1):
        start, end = spans[index]
        text = text[:start] + change(text[start:end], index) + text[end:]
    return text


def matching(text, i):
    """The index just past the bracket that closes the one at [i]."""
    depth = 0
    in_string = False
    while True:
        ch = text[i]
        if in_string:
            if ch == '\\':
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch in '[{':
            depth += 1
        elif ch in ']}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1


def fx(value, places=2):
    return f'{value:.{places}f}'


def per_household(country, trade):
    rows = country['classes']
    return sum(r['households'] * float(r['spending'][trade]) for r in rows) / sum(r['households'] for r in rows)


def main():
    with open(SCENARIO, encoding='utf-8', newline='') as f:
        raw = f.read()
    crlf = '\r\n' in raw
    text = raw.replace('\r\n', '\n')
    scenario = json.loads(text)
    if any(c['id'] == 'womenswear' for c in scenario['categories']):
        raise SystemExit('Clothing is in the scenario already')
    with open(os.path.join(HERE, 'euro.json'), encoding='utf-8') as f:
        euro = {c['id']: c for c in json.load(f)['countries']}
    # Clothes against electronics, which spread alike with income (0.89 and
    # 0.92 in euro.json), country by country.
    ratio = {key: per_household(c, 'clothing') / per_household(c, 'electronics') for key, c in euro.items()}

    def country(entry, index):
        key = scenario['countries'][index]['id']
        at = entry.index('"shops": {') + len('"shops": ')
        end = matching(entry, at)
        words = json.dumps(SHOP_WORDS[key], ensure_ascii=False, separators=(', ', ': '))
        return entry[:at] + entry[at:end - 1].rstrip() + f', "clothing": {words}' + '}' + entry[end:]

    text = edit_entries(text, 'countries', country)

    text = append(text, 'categories', [
        {'id': key, 'name': name, 'fashion': {'freshDays': fresh, 'fade': fade, 'premiumFade': premium_fade, 'floor': floor, 'clearance': clearance}}
        for key, name, _, _, (fresh, fade, premium_fade, floor, clearance) in CATEGORIES
    ])
    products = []
    for key, _, budget, premium, _ in CATEGORIES:
        for tier, (name, cost, price) in (('budget', budget), ('premium', premium)):
            products.append({'id': f'{key}_{tier}', 'name': name, 'category': key, 'tier': tier, 'baseCost': cost, 'referencePrice': price})
    text = append(text, 'products', products)

    keys = [s['id'] for s in scenario['segments']]

    def segment(entry, index):
        units, kids, premium, weight = SEGMENTS[keys[index]]
        at = entry.index('"categories": {') + len('"categories": ')
        end = matching(entry, at)
        habits = ''.join(
            f', "{c}": {{ "dailyUnits": "{fx(UNITS[c] * (kids if c == "kidswear" else units), 4)}", '
            f'"premiumShare": "{fx(min(PREMIUM[c] * premium, 0.6))}" }}'
            for c in UNITS
        )
        inner = entry[at:end - 1].rstrip()
        entry = entry[:at] + inner + habits + ' }' + entry[end:]
        match = re.search(r'"qualityWeight": "[^"]*"', entry)
        return entry[:match.end()] + f', "fashionWeight": "{weight}"' + entry[match.end():]

    text = edit_entries(text, 'segments', segment)

    # What a typical clothing shop of the districts run by formula sells and
    # keeps, measured by tool/national_shops.dart (seeds 1-2, 2026-11-15).
    national = {
        'fitOut': '60000.00',
        'sales': {'fr': '176000.00', 'de': '275000.00', 'it': '324000.00', 'es': '211000.00'},
        'staff': {'fr': '0.115', 'de': '0.122', 'it': '0.171', 'es': '0.232'},
        'premises': {'fr': '0.198', 'de': '0.142', 'it': '0.111', 'es': '0.163'},
    }
    text = append(text, 'formats', [dict(FORMAT, national=national)])

    strategies = []
    for key, name, changes in STRATEGIES:
        strategy = {'id': key, 'name': name, 'format': 'clothing'}
        strategy.update(STRATEGY)
        strategy.update(changes)
        strategies.append(strategy)
    text = append(text, 'strategies', strategies)

    goods = [p['id'] for p in products]
    suppliers = []
    for country, (slow, slow_name, quick, quick_name) in SUPPLIERS.items():
        for key, name, lead, terms, factor, minimum, discounts in (
            (slow, slow_name, 60, 60, '1.00', 60, [{'minUnits': 200, 'discount': '0.05'}, {'minUnits': 500, 'discount': '0.10'}]),
            (quick, quick_name, 10, 30, '1.35', 24, []),
        ):
            supplier = {'id': key, 'name': name, 'leadTimeDays': lead, 'paymentTermsDays': terms, 'priceFactor': factor, 'minOrderUnits': minimum}
            if discounts:
                supplier['volumeDiscounts'] = discounts
            supplier['products'] = goods
            if country:
                supplier['country'] = country
            suppliers.append(supplier)
    text = append(text, 'suppliers', suppliers)

    def place(entry, index, rows):
        row = rows[index]
        country = row.get('country', 'fr')
        amount = float(row['market']['electronics']) * ratio[country]
        return re.sub(r'("market": \{[^{}]*?)(\s*\})', lambda m: m.group(1) + f', "clothing": "{fx(amount)}"' + m.group(2), entry, count=1)

    text = edit_entries(text, 'markets', lambda e, i: place(e, i, scenario['markets']))
    text = edit_entries(text, 'neighbourhoods', lambda e, i: place(e, i, scenario['neighbourhoods']))

    sites, persons, companies, stores = [], [], [], []
    by_market = {}
    for site in scenario['sites']:
        by_market.setdefault(site['market'], []).append(site)
    markets = {m['id']: m for m in scenario['markets']}
    for market, shops in SHOPS.items():
        model = max(by_market[market], key=lambda s: float(s['rent']) / s['area'])
        # Clothes sell on the best streets: dearer than any site there yet.
        per_metre = float(model['rent']) / model['area'] * PRIME
        level = float(markets[market].get('priceLevel', '1.00'))
        for n, (name, street, owner) in enumerate(shops):
            strategy = 'fastfashion' if n == 0 else ('boutique' if market in BOUTIQUES else 'clothing')
            area = 140 if n == 0 else 120
            key = f'{market}_clothes_{n}'
            sites.append({
                'id': f'{key}_site', 'name': street, 'market': market, 'location': '0.60' if n == 0 else '0.55',
                'rent': fx(per_metre * area), 'shelfSlots': 8, 'storageUnits': 1800 if n == 0 else 1200,
                'openingCost': model['openingCost'], 'buildDays': 28, 'area': area, 'maxArea': area + 80,
            })
            persons.append({'id': f'{key}_owner', 'name': owner, 'cash': '90000.00', 'strategy': strategy})
            companies.append({'id': f'{key}_co', 'name': name, 'owner': f'{key}_owner', 'cash': '40000.00'})
            changes = dict(STRATEGIES[[s[0] for s in STRATEGIES].index(strategy)][2])
            position = 1 + float(changes.get('marketPosition', '0'))
            prices = {}
            for category, _, budget, premium, _ in CATEGORIES:
                for tier, (_, _, price) in (('budget', budget), ('premium', premium)):
                    prices[f'{category}_{tier}'] = fx(float(price) * level * position)
            stores.append({
                'id': f'{key}_shop', 'name': name, 'company': f'{key}_co', 'site': f'{key}_site', 'format': 'clothing',
                'staff': {'morning': 1, 'midday': 2, 'evening': 1}, 'prices': prices,
            })
    text = append(text, 'sites', sites)
    text = append(text, 'persons', persons)
    text = append(text, 'companies', companies)
    text = append(text, 'stores', stores)

    json.loads(text)
    with open(SCENARIO, 'w', encoding='utf-8', newline='') as f:
        f.write(text.replace('\n', '\r\n') if crlf else text)

    for language, additions in TRANSLATIONS.items():
        path = os.path.join(SCENARIOS, f'prototype.{language}.json')
        with open(path, encoding='utf-8', newline='') as f:
            raw = f.read()
        words = json.loads(raw)
        if json.dumps(words, ensure_ascii=False, indent=2) + '\n' == raw:
            for section, values in additions.items():
                words.setdefault(section, {}).update(values)
            out = json.dumps(words, ensure_ascii=False, indent=2) + '\n'
        else:
            # Laid out by hand: each entry goes at the end of its section.
            out = raw
            for section, values in additions.items():
                at = out.index(f'\n  "{section}": {{') + len(f'\n  "{section}": ')
                end = matching(out, at) - 1
                body = out[at:end].rstrip()
                added = ''.join(
                    ',\n    ' + json.dumps(key, ensure_ascii=False) + ': '
                    + json.dumps(value, ensure_ascii=False, indent=2).replace('\n', '\n    ')
                    for key, value in values.items()
                )
                out = out[:at] + body + added + '\n  ' + out[end:]
            json.loads(out)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(out)
    print('clothing added:', len(products), 'goods,', len(suppliers), 'suppliers,', len(stores), 'shops')


if __name__ == '__main__':
    main()
