# Puts what tool/add_places.dart laid out (places_built.json) into
# prototype.json: the countries after the start date, and everything else at
# the end of its list, as saved games allow. The rest of the file keeps its
# layout. Run once; it stops if the scenario has countries already.
#
#   python insert_places.py
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIO = os.path.join(HERE, '..', 'scenarios', 'prototype.json')
LISTS = ['suppliers', 'markets', 'sites', 'persons', 'companies', 'stores', 'neighbourhoods']


def line(entry):
    return '    ' + json.dumps(entry, ensure_ascii=False, separators=(', ', ': '))


def list_end(text, key):
    """Where the top-level list [key] closes: the index of its ']'."""
    start = text.index(f'\n  "{key}": [')
    i = text.index('[', start)
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
                return i
        i += 1


def main():
    with open(SCENARIO, encoding='utf-8') as f:
        text = f.read()
    if '"countries"' in text:
        raise SystemExit('prototype.json has countries already')
    with open(os.path.join(HERE, 'places_built.json'), encoding='utf-8') as f:
        built = json.load(f)
    for key in LISTS:
        end = list_end(text, key)
        # The list's last entry ends just before its closing line.
        body_end = text.rindex('\n', 0, end)
        before = text[:body_end].rstrip()
        added = ',\n'.join(line(entry) for entry in built[key])
        text = before + ',\n' + added + text[body_end:]
    countries = ',\n'.join(line(entry) for entry in built['countries'])
    marker = '\n  "markets": ['
    text = text.replace(marker, f'\n  "countries": [\n{countries}\n  ],{marker}', 1)
    json.loads(text)
    with open(SCENARIO, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('added', {key: len(built[key]) for key in ['countries'] + LISTS})


if __name__ == '__main__':
    main()
