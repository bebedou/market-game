# Adds each country's regions to euro.json, from Eurostat's public API: their
# population and households' disposable income per inhabitant, in 2022, and
# where each sits on the country's tile map. Also marks the chains' home
# regions, where their shops are thicker on the ground. Run after
# build_euro.py, which writes the rest of the file.
#
#   python build_regions.py
import json
import os
import urllib.request

BASE = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/'
HERE = os.path.dirname(os.path.abspath(__file__))
YEAR = '2022'

# Each region: its id, the NUTS codes it adds up (Trentino-Alto Adige is two
# provinces; Ceuta and Melilla join Andalusia, their neighbour by sea), its
# name, and its place on the tile map, column then row.
REGIONS = {
    'fr': [
        ('FRE', ['FRE'], 'Hauts-de-France', 2, 0),
        ('FRD', ['FRD'], 'Normandie', 1, 1),
        ('FR1', ['FR1'], 'Île-de-France', 2, 1),
        ('FRF', ['FRF'], 'Grand Est', 3, 1),
        ('FRH', ['FRH'], 'Bretagne', 0, 2),
        ('FRG', ['FRG'], 'Pays de la Loire', 1, 2),
        ('FRB', ['FRB'], 'Centre-Val de Loire', 2, 2),
        ('FRC', ['FRC'], 'Bourgogne-Franche-Comté', 3, 2),
        ('FRI', ['FRI'], 'Nouvelle-Aquitaine', 1, 3),
        ('FRK', ['FRK'], 'Auvergne-Rhône-Alpes', 2, 3),
        ('FRJ', ['FRJ'], 'Occitanie', 2, 4),
        ('FRL', ['FRL'], "Provence-Alpes-Côte d'Azur", 3, 4),
        ('FRM', ['FRM'], 'Corse', 4, 4),
    ],
    'de': [
        ('DEF', ['DEF'], 'Schleswig-Holstein', 2, 0),
        ('DE5', ['DE5'], 'Bremen', 1, 1),
        ('DE6', ['DE6'], 'Hamburg', 2, 1),
        ('DE8', ['DE8'], 'Mecklenburg-Vorpommern', 3, 1),
        ('DEA', ['DEA'], 'Nordrhein-Westfalen', 0, 2),
        ('DE9', ['DE9'], 'Niedersachsen', 1, 2),
        ('DEE', ['DEE'], 'Sachsen-Anhalt', 2, 2),
        ('DE3', ['DE3'], 'Berlin', 3, 2),
        ('DE4', ['DE4'], 'Brandenburg', 4, 2),
        ('DEB', ['DEB'], 'Rheinland-Pfalz', 0, 3),
        ('DE7', ['DE7'], 'Hessen', 1, 3),
        ('DEG', ['DEG'], 'Thüringen', 2, 3),
        ('DED', ['DED'], 'Sachsen', 3, 3),
        ('DEC', ['DEC'], 'Saarland', 0, 4),
        ('DE1', ['DE1'], 'Baden-Württemberg', 1, 4),
        ('DE2', ['DE2'], 'Bayern', 2, 4),
    ],
    'it': [
        ('ITC2', ['ITC2'], "Valle d'Aosta", 0, 0),
        ('ITH12', ['ITH1', 'ITH2'], 'Trentino-Alto Adige', 2, 0),
        ('ITH4', ['ITH4'], 'Friuli-Venezia Giulia', 3, 0),
        ('ITC1', ['ITC1'], 'Piemonte', 0, 1),
        ('ITC4', ['ITC4'], 'Lombardia', 1, 1),
        ('ITH3', ['ITH3'], 'Veneto', 2, 1),
        ('ITC3', ['ITC3'], 'Liguria', 0, 2),
        ('ITH5', ['ITH5'], 'Emilia-Romagna', 1, 2),
        ('ITI1', ['ITI1'], 'Toscana', 1, 3),
        ('ITI3', ['ITI3'], 'Marche', 2, 3),
        ('ITI4', ['ITI4'], 'Lazio', 1, 4),
        ('ITI2', ['ITI2'], 'Umbria', 2, 4),
        ('ITF1', ['ITF1'], 'Abruzzo', 3, 4),
        ('ITG2', ['ITG2'], 'Sardegna', 0, 5),
        ('ITF3', ['ITF3'], 'Campania', 2, 5),
        ('ITF2', ['ITF2'], 'Molise', 3, 5),
        ('ITF4', ['ITF4'], 'Puglia', 4, 5),
        ('ITF5', ['ITF5'], 'Basilicata', 3, 6),
        ('ITF6', ['ITF6'], 'Calabria', 3, 7),
        ('ITG1', ['ITG1'], 'Sicilia', 2, 8),
    ],
    'es': [
        ('ES11', ['ES11'], 'Galicia', 0, 0),
        ('ES12', ['ES12'], 'Asturias', 1, 0),
        ('ES13', ['ES13'], 'Cantabria', 2, 0),
        ('ES21', ['ES21'], 'País Vasco', 3, 0),
        ('ES22', ['ES22'], 'Navarra', 4, 0),
        ('ES41', ['ES41'], 'Castilla y León', 1, 1),
        ('ES23', ['ES23'], 'La Rioja', 3, 1),
        ('ES24', ['ES24'], 'Aragón', 4, 1),
        ('ES51', ['ES51'], 'Cataluña', 5, 1),
        ('ES43', ['ES43'], 'Extremadura', 0, 2),
        ('ES30', ['ES30'], 'Madrid', 2, 2),
        ('ES42', ['ES42'], 'Castilla-La Mancha', 3, 2),
        ('ES52', ['ES52'], 'Comunitat Valenciana', 4, 2),
        ('ES53', ['ES53'], 'Illes Balears', 5, 2),
        ('ES61', ['ES61', 'ES63', 'ES64'], 'Andalucía', 2, 3),
        ('ES62', ['ES62'], 'Región de Murcia', 3, 3),
        ('ES70', ['ES70'], 'Canarias', 0, 4),
    ],
}

# Where a chain's shops are thicker on the ground than the country's spending
# alone would put them: fictional chains, with the home regions their names
# suggest.
HOMES = {
    "Coop de l'Ouest": ['FRH', 'FRG', 'FRD'],
    'Supermercati Lombardi': ['ITC4'],
    'Cooperativa Nazionale': ['ITH5', 'ITI1'],
    'Mercado Levante': ['ES52', 'ES62'],
    'Norte Cooperativa': ['ES21', 'ES22', 'ES13'],
    'Rheinkauf': ['DEA', 'DEB'],
}


def fetch(dataset, query, codes):
    geo = '&'.join(f'geo={code}' for code in codes)
    url = f'{BASE}{dataset}?{geo}&{query}&time={YEAR}'
    with urllib.request.urlopen(url, timeout=120) as response:
        data = json.load(response)
    index = data['dimension']['geo']['category']['index']
    return {
        code: data['value'][str(position)]
        for code, position in index.items()
        if str(position) in data['value']
    }


def main():
    path = os.path.join(HERE, 'euro.json')
    with open(path, encoding='utf-8') as file:
        table = json.load(file)
    for country in table['countries']:
        regions = REGIONS[country['id']]
        codes = [code for _, parts, *_ in regions for code in parts]
        people = fetch('demo_r_pjanaggr3', 'sex=T&age=TOTAL', codes)
        income = fetch(
            'nama_10r_2hhinc', 'unit=EUR_HAB&direct=BAL&na_item=B6N', codes
        )
        rows = []
        for key, parts, name, col, row in regions:
            population = sum(people[code] for code in parts)
            # Income per inhabitant, weighted by population where regions join.
            per_head = sum(income[code] * people[code] for code in parts)
            rows.append({
                'id': key,
                'name': name,
                'population': population,
                'income': f'{per_head / population:.2f}',
                'tile': [col, row],
            })
        country['regions'] = rows
        for chain in country['chains']:
            home = HOMES.get(chain['name'])
            if home:
                chain['home'] = home
            else:
                chain.pop('home', None)
        print(country['id'], len(rows), 'regions,',
              sum(r['population'] for r in rows), 'people')
    # How a region's wages and rents follow its income against the
    # country's (a region a tenth richer pays wages 7% and rents 15% higher),
    # how much thicker a chain's shops are in its home regions, and how
    # crowded a region gets for one chain: its per-shop draw halves once it
    # has this share of the trade's shops there.
    table['regional'] = {
        'wages': '0.70',
        'rents': '1.50',
        'home': '3.00',
        'saturation': '0.10',
    }
    # How a company's marketing across a country builds its pull: up to 30%
    # more shoppers, half that once its goodwill is 0.05% of the trade's
    # yearly market, goodwill losing 8% a month. A share of sales buys a big
    # chain far more than a small one.
    table['brands'] = {
        'pull': '0.30',
        'half': '0.0005',
        'decay': '0.08',
    }
    with open(path, 'w', encoding='utf-8', newline='\n') as file:
        json.dump(table, file, ensure_ascii=False, indent=1)
        file.write('\n')


if __name__ == '__main__':
    main()
