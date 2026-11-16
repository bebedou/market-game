# Builds companies.json: the stock market's sectors, exchanges, rules and
# listed companies. Each formula sector's size in each country is its output
# at basic prices in YEAR, from Eurostat's national accounts by industry
# (nama_10_a64, P1, current prices); its ten biggest companies are fictional,
# drawn here from a fixed seed. The game's own companies (chains, software
# rivals, rival producers) are listed by name and keep their own books.
#
#   python build_companies.py
#
# Running it again rewrites companies.json from scratch. To change a company,
# edit companies.json by hand afterwards; a mod can ship its own copy.
# Market caps and shares left null (the game's own companies) are set from
# their books when the game starts; `dart run tool/stock_caps.dart` in
# packages/engine fills them in here.
import json
import math
import os
import random
import urllib.request

BASE = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
YEAR = 2022
# The scenario's country ids, and Eurostat's codes for them.
COUNTRIES = {'fr': 'FR', 'de': 'DE', 'it': 'IT', 'es': 'ES'}
EXCHANGES = {
    'fr': ('Paris', 'Paris index'),
    'de': ('Frankfurt', 'Frankfurt index'),
    'it': ('Milan', 'Milan index'),
    'es': ('Madrid', 'Madrid index'),
}
# A country this size (output, billions a year) or more lists ten companies
# per sector; a smaller one fewer, down to three.
FULL_ECONOMY = 1000
PER_SECTOR = 10

# Sectors run by formula: the industries they take their output from (a
# share of an industry where the sector is a part of it), and their figures:
#   margin    margin on sales before tax, in a normal year
#   cycle     how far sales move with the economy's output gap
#   leverage  how far the margin moves with sales against normal
#   growth    yearly real growth beyond the country's
#   risk      how much of the market's risk it carries, 1 for the average
#   payout    the share of profit paid as dividends
#   debt      net debt, in years of profit
#   floor     what it is worth while losing money, as years of sales
#   top       the share of the sector its ten biggest hold together
FORMULA = [
    ('energy', 'Energy', {'B': 1, 'C19': 1},
     '0.06', '1.5', '3', '-0.010', '1.2', '0.55', '1.5', '0.25', '0.70'),
    ('utilities', 'Utilities', {'D35': 1, 'E36': 1, 'E37-E39': 1},
     '0.08', '0.3', '1.5', '0.005', '0.8', '0.70', '4.0', '0.60', '0.55'),
    ('materials', 'Materials', {'C16': 1, 'C17': 1, 'C23': 1, 'C24': 1},
     '0.06', '2.5', '3', '0', '1.3', '0.40', '1.5', '0.20', '0.30'),
    ('chemicals', 'Chemicals', {'C20': 1, 'C22': 1},
     '0.07', '1.8', '2.5', '0.010', '1.1', '0.45', '1.5', '0.30', '0.35'),
    ('pharma', 'Pharmaceuticals', {'C21': 1},
     '0.15', '0.2', '1.2', '0.020', '0.8', '0.45', '1.0', '1.00', '0.45'),
    ('food', 'Food and drink makers', {'C10-C12': 1},
     '0.07', '0.3', '1.5', '0.010', '0.7', '0.55', '2.0', '0.40', '0.25'),
    ('cars', 'Cars', {'C29': 1},
     '0.05', '3.0', '4', '0', '1.4', '0.35', '1.0', '0.10', '0.75'),
    ('machinery', 'Machinery', {'C27': 1, 'C28': 1},
     '0.07', '2.2', '3', '0.015', '1.2', '0.40', '1.0', '0.30', '0.20'),
    ('aerospace', 'Aerospace and defence', {'C30': 1},
     '0.07', '0.6', '2', '0.030', '0.9', '0.35', '1.0', '0.40', '0.70'),
    ('construction', 'Construction', {'F': 1},
     '0.04', '3.0', '4', '0.005', '1.3', '0.45', '1.5', '0.10', '0.15'),
    ('transport', 'Transport', {'H49': 1, 'H50': 1, 'H51': 1, 'H52': 1, 'H53': 1},
     '0.04', '2.0', '4', '0.010', '1.2', '0.35', '2.5', '0.15', '0.30'),
    ('telecoms', 'Telecoms', {'J61': 1},
     '0.08', '0.3', '1.5', '-0.005', '0.7', '0.70', '3.0', '0.60', '0.85'),
    ('media', 'Media', {'J58': 1, 'J59_J60': 1, 'M73': 1},
     '0.07', '1.5', '2.5', '-0.005', '1.0', '0.50', '1.5', '0.40', '0.35'),
    ('banks', 'Banks', {'K64': 1},
     '0.18', '1.5', '3', '0.005', '1.3', '0.50', '0', '0.60', '0.60'),
    ('insurance', 'Insurance', {'K65': 1},
     '0.08', '0.6', '2', '0.010', '0.9', '0.60', '0', '0.50', '0.60'),
    # Real estate without the rents owners impute to themselves.
    ('property', 'Real estate', {'L68': 1, 'L68A': -1},
     '0.25', '1.0', '2', '0.005', '1.0', '0.80', '6.0', '1.50', '0.08'),
    # Hotels are about a third of accommodation and food services; the rest
    # is restaurants, which are played.
    ('leisure', 'Hotels and leisure', {'I': 0.3, 'N79': 1, 'R93': 1},
     '0.06', '2.0', '4', '0.020', '1.3', '0.40', '2.0', '0.30', '0.15'),
    # Chips are about half of computer, electronic and optical products.
    ('chips', 'Chips', {'C26': 0.5},
     '0.14', '2.5', '3', '0.050', '1.5', '0.25', '0.5', '1.50', '0.50'),
]

# Sectors the game plays: their companies are its own, with their own books.
#   (id, name, link, growth, risk, payout, floor)
PLAYED = [
    ('grocers', 'Grocers', {'trade': 'grocery'}, '0.005', '0.7', '0.50', '0.10'),
    ('restaurants', 'Restaurants', {'trade': 'restaurants'}, '0.010', '1.0', '0.45', '0.30'),
    ('electronics', 'Electronics shops', {'trade': 'electronics'}, '0.010', '1.1', '0.40', '0.15'),
    ('clothing', 'Clothing shops', {'trade': 'clothing'}, '0.005', '1.1', '0.45', '0.25'),
    ('software', 'Software', {'software': True, 'margin': '0.45'}, '0.060', '1.3', '0.20', '2.00'),
]

RULES = {
    'termPremium': '0.005',
    'equityPremium': '0.055',
    'inflation': '0.020',
    'minEarningsMultiple': '5',
    'maxEarningsMultiple': '30',
    'moods': {'expansion': '0.06', 'slowdown': '-0.06', 'recession': '-0.30', 'recovery': '-0.10'},
    'euphoria': '0.006',
    'maxEuphoria': '0.25',
    'marketHalfLife': 120,
    'marketSpread': '0.009',
    'shared': '0.6',
    'stockHalfLife': 365,
    'stockSpread': '0.005',
    'reaction': '0.3',
    'maxSurprise': '0.4',
    'maxMood': '1.0',
    'analystSpread': '0.06',
    'analystHalfLife': 6,
    'analystsFollow': '0.8',
    'ratings': ['-0.20', '-0.07', '0.07', '0.20'],
    'fee': '0.002',
    'indexFee': '0.001',
    'impact': '2',
    'managementChange': '0.08',
    'managementMargin': '0.010',
    'managementGrowth': '0.003',
    'managementPull': '0.03',
    'marginSpread': '0.04',
    'unprovenMonths': 12,
    'chainReserveMonths': 3,
    'producerUse': '0.7',
    'indexBase': '1000',
}

MANAGEMENT = ['bad', 'poor', 'average', 'good', 'excellent']
MANAGEMENT_ODDS = [0.10, 0.20, 0.40, 0.20, 0.10]

# Words a company's name is made from, by language: stems and endings that
# join into a place or family name, and each sector's word and how a name is
# put together ({n} the name, {w} the sector's word).
STEMS = {
    'de': ['Alb', 'Bern', 'Dorn', 'Eich', 'Falk', 'Gold', 'Hag', 'Isen', 'Kalt', 'Lind',
           'Mark', 'Nord', 'Ost', 'Rab', 'Sand', 'Stein', 'Tann', 'Wald', 'Wester', 'Zell',
           'Brun', 'Hohen', 'Kron', 'Rosen', 'Sonn', 'Weiss', 'Birk', 'Erl', 'Fels', 'Lauter'],
    'fr': ['Beau', 'Bel', 'Clair', 'Fon', 'Grand', 'Haut', 'Mont', 'Ro', 'Val', 'Ver',
           'Lau', 'Mar', 'Cour', 'Bois', 'Mira', 'Sau', 'Bru', 'Char', 'Pré', 'Lor',
           'Arge', 'Bri', 'Cler', 'Duran', 'Esca', 'Fer', 'Gal', 'Jol', 'Mal', 'Sali'],
    'it': ['Bel', 'Bor', 'Cal', 'Fer', 'Gal', 'Lor', 'Mar', 'Mon', 'Ros', 'San',
           'Sol', 'Tor', 'Val', 'Ver', 'Al', 'Bru', 'Cas', 'Fio', 'Lan', 'Pal',
           'Ar', 'Bar', 'Cer', 'Dal', 'Gin', 'Lu', 'Man', 'Ner', 'Or', 'Ser'],
    'es': ['Al', 'Ar', 'Bel', 'Cas', 'Cor', 'Mon', 'Sol', 'Val', 'Vil', 'Ter',
           'Mar', 'San', 'Rio', 'Pe', 'Lo', 'Gua', 'Can', 'Cer', 'Fu', 'Na',
           'Ba', 'Ca', 'Do', 'Es', 'Ga', 'Hi', 'La', 'Ma', 'Ol', 'Ro'],
}
ENDINGS = {
    'de': ['au', 'bach', 'berg', 'burg', 'dorf', 'eck', 'feld', 'hof', 'hausen', 'heim',
           'stein', 'tal', 'wald', 'ingen', 'brück', 'mark', 'horst', 'stedt'],
    'fr': ['mont', 'val', 'champ', 'court', 'fort', 'lieu', 'mare', 'roche', 'sac', 'ville',
           'bourg', 'nac', 'ac', 'ières', 'mas', 'vert', 'lande', 'rieux'],
    'it': ['ani', 'ari', 'elli', 'enti', 'ezzi', 'ini', 'one', 'otti', 'uzzi', 'aro',
           'ello', 'ieri', 'ardi', 'oni', 'asso', 'ugi', 'eschi', 'elmi'],
    'es': ['ada', 'ar', 'edo', 'ena', 'era', 'illa', 'oza', 'uela', 'ares', 'anco',
           'aldo', 'ino', 'osa', 'ejo', 'ira', 'ales', 'ondo', 'arra'],
}
WORDS = {
    'energy': {'de': ('Energie', '{n} {w}'), 'fr': ('Énergie', '{n} {w}'), 'it': ('Energia', '{w} {n}'), 'es': ('Energía', '{w} {n}')},
    'utilities': {'de': ('Versorgung', '{n} {w}'), 'fr': ('Réseaux', '{w} {n}'), 'it': ('Servizi', '{w} {n}'), 'es': ('Redes', '{w} {n}')},
    'materials': {'de': ('Werkstoffe', '{n} {w}'), 'fr': ('Matériaux', '{w} {n}'), 'it': ('Materiali', '{w} {n}'), 'es': ('Materiales', '{w} {n}')},
    'chemicals': {'de': ('Chemie', '{n} {w}'), 'fr': ('Chimie', '{n} {w}'), 'it': ('Chimica', '{w} {n}'), 'es': ('Química', '{w} {n}')},
    'pharma': {'de': ('Pharma', '{n} {w}'), 'fr': ('Pharma', '{n} {w}'), 'it': ('Farmaceutici', '{w} {n}'), 'es': ('Farma', '{n} {w}')},
    'food': {'de': ('Nahrung', '{n} {w}'), 'fr': ('Alimentaire', '{n} {w}'), 'it': ('Alimentare', '{n} {w}'), 'es': ('Alimentación', '{w} {n}')},
    'cars': {'de': ('Motoren', '{n} {w}'), 'fr': ('Automobiles', '{w} {n}'), 'it': ('Automobili', '{w} {n}'), 'es': ('Motor', '{n} {w}')},
    'machinery': {'de': ('Maschinenbau', '{n} {w}'), 'fr': ('Mécanique', '{w} {n}'), 'it': ('Meccanica', '{w} {n}'), 'es': ('Maquinaria', '{w} {n}')},
    'aerospace': {'de': ('Luftfahrt', '{n} {w}'), 'fr': ('Aéronautique', '{n} {w}'), 'it': ('Aerospazio', '{n} {w}'), 'es': ('Aeronáutica', '{w} {n}')},
    'construction': {'de': ('Bau', '{n} {w}'), 'fr': ('Construction', '{n} {w}'), 'it': ('Costruzioni', '{w} {n}'), 'es': ('Construcciones', '{w} {n}')},
    'transport': {'de': ('Logistik', '{n} {w}'), 'fr': ('Transports', '{w} {n}'), 'it': ('Trasporti', '{w} {n}'), 'es': ('Transportes', '{w} {n}')},
    'telecoms': {'de': ('Netz', '{n} {w}'), 'fr': ('Télécom', '{n} {w}'), 'it': ('Telecomunicazioni', '{w} {n}'), 'es': ('Telecomunicaciones', '{w} {n}')},
    'media': {'de': ('Medien', '{n} {w}'), 'fr': ('Médias', '{n} {w}'), 'it': ('Media', '{n} {w}'), 'es': ('Medios', '{w} {n}')},
    'banks': {'de': ('Bank', '{n} {w}'), 'fr': ('Banque', '{w} {n}'), 'it': ('Banca', '{w} {n}'), 'es': ('Banco', '{w} {n}')},
    'insurance': {'de': ('Versicherung', '{n} {w}'), 'fr': ('Assurances', '{n} {w}'), 'it': ('Assicurazioni', '{w} {n}'), 'es': ('Seguros', '{w} {n}')},
    'property': {'de': ('Immobilien', '{n} {w}'), 'fr': ('Foncière', '{w} {n}'), 'it': ('Immobiliare', '{w} {n}'), 'es': ('Inmobiliaria', '{w} {n}')},
    'leisure': {'de': ('Hotels', '{n} {w}'), 'fr': ('Hôtels', '{w} {n}'), 'it': ('Hotel', '{w} {n}'), 'es': ('Hoteles', '{w} {n}')},
    'chips': {'de': ('Halbleiter', '{n} {w}'), 'fr': ('Semi-conducteurs', '{n} {w}'), 'it': ('Semiconduttori', '{w} {n}'), 'es': ('Semiconductores', '{w} {n}')},
}
# Where the game's software rivals are listed.
SOFTWARE_HOMES = {
    'Halvren Systems': 'de', 'Corvane': 'fr', 'Talmont': 'fr',
    'Brisk Orchard': 'es', 'Quellmark': 'de', 'Nerith': 'it',
}
CHAIN_SECTORS = {'grocery': 'grocers', 'restaurants': 'restaurants',
                 'electronics': 'electronics', 'clothing': 'clothing'}


def get(dataset, query):
    url = f'{BASE}{dataset}?format=JSON&lang=EN&{query}'
    request = urllib.request.Request(url, headers={'User-Agent': 'market-game-stats'})
    with urllib.request.urlopen(request, timeout=90) as response:
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


def output():
    """Each industry's output in YEAR, in millions of euros, by country."""
    geo = '&'.join(f'geo={g}' for g in COUNTRIES.values())
    rows = get('nama_10_a64', f'{geo}&unit=CP_MEUR&na_item=P1&time={YEAR}')
    table = {}
    for row, value in rows:
        if value is not None:
            table[(row['geo'], row['nace_r2'])] = value
    return table


def ticker(name, taken):
    """Up to four letters from [name], none of them used before."""
    letters = [c for c in name.upper() if 'A' <= c <= 'Z']
    first = letters[0]
    rest = [c for c in letters[1:] if c not in 'AEIOU'] + letters[1:]
    for a in range(len(rest)):
        for b in range(a + 1, len(rest)):
            for c in range(b + 1, len(rest)):
                code = first + rest[a] + rest[b] + rest[c]
                if code not in taken:
                    taken.add(code)
                    return code
    n = 1
    while f'{first}{n:03d}' in taken:
        n += 1
    taken.add(f'{first}{n:03d}')
    return f'{first}{n:03d}'


def fx(value, places=4):
    text = f'{value:.{places}f}'
    return '0' if float(text) == 0 else text


def shares_of(cap, rng):
    """A share count that prices a company at a usual sort of price, and
    never more than three billion shares."""
    price = math.exp(rng.uniform(math.log(8), math.log(160)))
    price = max(price, cap / 3e9)
    return max(1000000, int(round(cap / price / 100000)) * 100000)


# Long rates at the start: the scenario's rate in a normal year.
START_RATE = 0.04
# Each country's tax on companies' profit, as the scenario sets it.
TAX = {'fr': 0.25, 'de': 0.299, 'it': 0.279, 'es': 0.25}


def earnings_multiple(growth, risk):
    """As the game sets it at the start."""
    rate = (START_RATE + float(RULES['termPremium'])
            + float(RULES['equityPremium']) * risk
            - (float(RULES['inflation']) + growth))
    rate = max(rate, 1 / float(RULES['maxEarningsMultiple']))
    return min(1 / rate, float(RULES['maxEarningsMultiple']))


def main():
    rng = random.Random(YEAR)
    stats = output()
    names = set()
    scenario = json.load(open(os.path.join(ROOT, 'content/scenarios/prototype.json'), encoding='utf-8'))
    national = json.load(open(os.path.join(ROOT, 'content/countries/euro.json'), encoding='utf-8'))
    for country in national['countries']:
        for chain in country['chains']:
            names.add(chain['name'])
    for producer in scenario['factories']['sales']['producers']:
        names.add(producer['name'])
    taken = set()

    sectors = []
    totals = {c: stats[(code, 'TOTAL')] / 1000 for c, code in COUNTRIES.items()}
    for (key, name, industries, margin, cycle, leverage, growth, risk,
         payout, debt, floor, top) in FORMULA:
        size = {}
        for country, code in COUNTRIES.items():
            total = sum(stats.get((code, n), 0) * part for n, part in industries.items())
            size[country] = fx(total / 1000, 2)
        sectors.append({
            'id': key, 'name': name, 'margin': margin, 'cycle': cycle,
            'leverage': leverage, 'growth': growth, 'risk': risk,
            'payout': payout, 'debt': debt, 'floor': floor, 'output': size,
            '_top': float(top),
        })
    for key, name, link, growth, risk, payout, floor in PLAYED:
        sectors.append({'id': key, 'name': name, **link, 'growth': growth,
                        'risk': risk, 'payout': payout, 'floor': floor})

    companies = []
    for sector in sectors:
        if 'output' not in sector:
            continue
        top = sector.pop('_top')
        key = sector['id']
        for country in COUNTRIES:
            count = PER_SECTOR if totals[country] >= FULL_ECONOMY else max(
                3, round(PER_SECTOR * math.sqrt(totals[country] / FULL_ECONOMY)))
            # Shares fall off by rank, as in most industries.
            weights = [1 / (rank + 1) ** rng.uniform(0.8, 1.3) for rank in range(count)]
            scale = top / sum(weights)
            word, pattern = WORDS[key][country]
            for rank in range(count):
                while True:
                    stem = rng.choice(STEMS[country]) + rng.choice(ENDINGS[country])
                    full = pattern.format(n=stem, w=word)
                    if full not in names:
                        names.add(full)
                        break
                share = weights[rank] * scale
                grade = rng.choices(range(5), MANAGEMENT_ODDS)[0]
                margin = max(0.005, float(sector['margin']) * math.exp(rng.gauss(0, 0.25))
                             + (grade - 2) * float(RULES['managementMargin']))
                own_growth = rng.gauss(0, 0.01) + (grade - 2) * float(RULES['managementGrowth'])
                debt = float(sector['debt']) * math.exp(rng.gauss(0, 0.35))
                payout = min(0.9, max(0.0, float(sector['payout']) + rng.uniform(-0.1, 0.1)))
                sales = share * float(sector['output'][country]) * 1e9
                earnings = sales * margin * (1 - TAX[country])
                multiple = earnings_multiple(
                    float(sector['growth']) + own_growth, float(sector['risk']))
                # As the game values it: the larger of its earnings' worth
                # and its sales' floor, less its debt.
                worth = max(earnings * multiple, sales * float(sector['floor'])) - earnings * debt
                worth = max(worth, sales * float(sector['floor']) * 0.05)
                cap = worth * math.exp(rng.gauss(0, 0.15))
                companies.append({
                    'ticker': ticker(stem + word, taken),
                    'name': full,
                    'country': country,
                    'sector': key,
                    'share': fx(share, 6),
                    'cap': f'{round(cap, -5):.0f}',
                    'shares': shares_of(cap, rng),
                    'margin': fx(margin),
                    'debt': fx(debt, 2),
                    'growth': fx(own_growth),
                    'payout': fx(payout, 2),
                    'management': MANAGEMENT[grade],
                })

    # The game's own companies, which keep their own books.
    for country in national['countries']:
        game = country['id'].lower()
        for chain in country['chains']:
            if chain['name'].startswith('Independent'):
                continue
            companies.append({
                'ticker': ticker(chain['name'], taken),
                'name': chain['name'],
                'country': game,
                'sector': CHAIN_SECTORS[chain['trade']],
                'chain': chain['name'],
                'cap': None, 'shares': None, 'payout': None,
            })
    for rival in scenario['software']['rivals']:
        if rival.get('rest'):
            continue
        companies.append({
            'ticker': ticker(rival['name'], taken),
            'name': rival['name'],
            'country': SOFTWARE_HOMES[rival['name']],
            'sector': 'software',
            'software': rival['name'],
            'cap': None, 'shares': None, 'payout': None,
        })
    for producer in scenario['factories']['sales']['producers']:
        companies.append({
            'ticker': ticker(producer['name'], taken),
            'name': producer['name'],
            'country': producer['country'],
            'sector': 'food',
            'producer': producer['name'],
            'cap': None, 'shares': None, 'payout': None,
        })

    result = {
        'about': (
            'The stock market: its rules, sectors, exchanges and listed companies. '
            'Built by build_companies.py from Eurostat (nama_10_a64, output P1, '
            f'{YEAR}, billions of euros) and a fixed seed; edit by hand freely. '
            'A company with "chain", "software" or "producer" is the game\'s own '
            'and keeps its own books; the rest run by formula. "share" is its '
            'share of its sector\'s output in its country, "cap" its market '
            'value at the start in euros, "margin" its margin before tax in a '
            'normal year, "debt" its net debt in years of profit.'
        ),
        'year': YEAR,
        'rules': RULES,
        'exchanges': [
            {'country': c, 'name': n, 'index': i} for c, (n, i) in EXCHANGES.items()
        ],
        'sectors': sectors,
        'companies': companies,
    }
    text = json.dumps(result, ensure_ascii=False, indent=1)
    with open(os.path.join(HERE, 'companies.json'), 'w', encoding='utf-8', newline='\n') as file:
        file.write(text + '\n')
    print(f'{len(companies)} companies in {len(sectors)} sectors')


if __name__ == '__main__':
    main()
