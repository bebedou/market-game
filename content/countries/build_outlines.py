# Draws each country's regions for the country page's ink map: their
# outlines from Eurostat's GISCO boundaries (NUTS 2021, at 1:20 million),
# each country in a frame of its own a thousand units wide, simplified to
# what a phone shows, with the Canary Islands set smaller in the empty
# corner where Portugal would be, and specks of island left out. A region
# with another inside it, as Brandenburg holds Berlin, keeps it as a hole,
# for the map to fill even-odd. Writes outlines.json, which the app reads.
#
#   python build_outlines.py
import json
import math
import os
import urllib.request

from build_regions import REGIONS

GISCO = ('https://gisco-services.ec.europa.eu/distribution/v2/nuts/geojson/'
         'NUTS_RG_20M_2021_4326_LEVL_{}.geojson')
HERE = os.path.dirname(os.path.abspath(__file__))

# The frame's width; its height follows the country's shape.
WIDTH = 1000
# Room around the country, in frame units.
MARGIN = 12
# How far a simplified line may stray from the true one, in frame units.
TOLERANCE = 1.6
# Islands smaller than this, in square frame units, are left out.
MIN_AREA = 60
# Regions drawn in a box of their own in a corner, as maps do, and the
# most of their own size they keep there.
INSETS = {'ES70'}
INSET_SCALE = 0.6


def fetch(level):
    with urllib.request.urlopen(GISCO.format(level), timeout=120) as response:
        data = json.load(response)
    return {f['properties']['NUTS_ID']: f for f in data['features']}


def polygons(feature):
    """A feature's polygons, each its outer ring and its holes, as lists of
    (lon, lat)."""
    geometry = feature['geometry']
    shapes = (geometry['coordinates'] if geometry['type'] == 'MultiPolygon'
              else [geometry['coordinates']])
    return [(shape[0], shape[1:]) for shape in shapes]


def area(ring):
    total = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        total += x1 * y2 - x2 * y1
    return total / 2


def centroid(ring):
    a = area(ring)
    if a == 0:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        return sum(xs) / len(xs), sum(ys) / len(ys)
    cx = cy = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        cross = x1 * y2 - x2 * y1
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    return cx / (6 * a), cy / (6 * a)


def inside(point, ring):
    x, y = point
    hit = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > y) != (y2 > y):
            if x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                hit = not hit
    return hit


def within(point, outer, holes):
    return inside(point, outer) and not any(inside(point, h) for h in holes)


def label(outer, holes):
    """Where a region's figure goes: its centroid if that is in it, or else
    the point of a fine grid over it farthest from its edges."""
    c = centroid(outer)
    if within(c, outer, holes):
        return c
    xs = [p[0] for p in outer]
    ys = [p[1] for p in outer]
    edges = outer + [p for h in holes for p in h]
    best, best_d = c, -1.0
    for i in range(1, 24):
        for j in range(1, 24):
            p = (min(xs) + (max(xs) - min(xs)) * i / 24,
                 min(ys) + (max(ys) - min(ys)) * j / 24)
            if not within(p, outer, holes):
                continue
            d = min(math.dist(p, q) for q in edges)
            if d > best_d:
                best, best_d = p, d
    return best


def simplify(points, tolerance):
    """Douglas-Peucker on an open line."""
    if len(points) < 3:
        return points
    (x1, y1), (x2, y2) = points[0], points[-1]
    length = math.hypot(x2 - x1, y2 - y1) or 1e-9
    far, index = 0.0, 0
    for i, (x, y) in enumerate(points[1:-1], 1):
        d = abs((y2 - y1) * x - (x2 - x1) * y + x2 * y1 - y2 * x1) / length
        if d > far:
            far, index = d, i
    if far <= tolerance:
        return [points[0], points[-1]]
    return (simplify(points[:index + 1], tolerance)[:-1] +
            simplify(points[index:], tolerance))


def simplify_ring(ring):
    # Split at the point farthest from the first, so both halves are lines.
    start = ring[0]
    far = max(range(len(ring)), key=lambda i: math.dist(start, ring[i]))
    a = simplify(ring[:far + 1], TOLERANCE)
    b = simplify(ring[far:] + [start], TOLERANCE)
    return a[:-1] + b[:-1]


def path(ring):
    return 'M' + 'L'.join('%.1f %.1f' % (x, y) for x, y in ring) + 'Z'


def country_map(regions, features):
    # Each region's polygons in degrees, by the NUTS part they come from.
    raw = {rid: [(part, poly) for part in parts
                 for poly in polygons(features[part])]
           for rid, parts, *_ in regions}
    # Specks of island go before framing, so they don't stretch it: each
    # region keeps its biggest piece and those a two-thousandth of the
    # country or more.
    whole = sum(abs(area(poly[0])) for items in raw.values()
                for _, poly in items)
    for rid, items in raw.items():
        biggest = max(items, key=lambda item: abs(area(item[1][0])))
        raw[rid] = [item for item in items if item is biggest
                    or abs(area(item[1][0])) * 2000 >= whole]
    lats = [lat for items in raw.values() for part, (outer, _) in items
            if part not in INSETS for _, lat in outer]
    squeeze = math.cos(math.radians((min(lats) + max(lats)) / 2))

    def project(ring):
        return [(lon * squeeze, -lat) for lon, lat in ring]

    mainland = [project(outer) for items in raw.values()
                for part, (outer, _) in items if part not in INSETS]
    xs = [x for ring in mainland for x, _ in ring]
    ys = [y for ring in mainland for _, y in ring]
    scale = (WIDTH - 2 * MARGIN) / (max(xs) - min(xs))
    height = (max(ys) - min(ys)) * scale + 2 * MARGIN

    def frame(ring):
        return [((x - min(xs)) * scale + MARGIN, (y - min(ys)) * scale + MARGIN)
                for x, y in ring]

    framed_mainland = [frame(ring) for ring in mainland]

    # Insets: smaller, in the bottom left corner, clear of the mainland.
    inset_rings = [frame(project(outer)) for items in raw.values()
                   for part, (outer, _) in items if part in INSETS]
    place = None
    box = None
    if inset_rings:
        ixs = [x for r in inset_rings for x, _ in r]
        iys = [y for r in inset_rings for _, y in r]
        w, h = max(ixs) - min(ixs), max(iys) - min(iys)
        s = INSET_SCALE
        pad = 8
        while True:
            top = height - MARGIN - h * s
            band = [x for r in framed_mainland for x, y in r
                    if y >= top - 2 * pad]
            room = (min(band) if band else WIDTH) - 2 * pad - MARGIN
            if w * s <= room or s < 0.2:
                break
            s *= 0.9
        left, bottom = MARGIN + pad, height - MARGIN - pad

        def place(ring):
            return [(left + (x - min(ixs)) * s, bottom - (max(iys) - y) * s)
                    for x, y in ring]
        box = [round(left - pad, 1), round(bottom - h * s - pad, 1),
               round(left + w * s + pad, 1), round(bottom + pad, 1)]

    drawn = {}
    for rid, items in raw.items():
        shapes = []
        for part, (outer, holes) in items:
            def put(ring):
                f = frame(project(ring))
                return place(f) if part in INSETS else f
            o = simplify_ring(put(outer))
            hs = [simplify_ring(put(h)) for h in holes]
            hs = [h for h in hs if len(h) >= 3 and abs(area(h)) >= MIN_AREA / 4]
            if len(o) >= 3:
                shapes.append((o, hs))
        biggest = max(shapes, key=lambda shape: abs(area(shape[0])))
        shapes = [shape for shape in shapes
                  if shape is biggest or abs(area(shape[0])) >= MIN_AREA]
        spot = label(*biggest)
        drawn[rid] = {
            'path': ''.join(path(o) + ''.join(path(h) for h in hs)
                            for o, hs in shapes),
            'label': [round(spot[0], 1), round(spot[1], 1)],
            # Smaller regions are drawn over larger ones and touched first.
            'area': round(sum(abs(area(o)) - sum(abs(area(h)) for h in hs)
                              for o, hs in shapes)),
        }
    return {
        'width': WIDTH,
        'height': round(height, 1),
        # The box an inset stands in, ruled off on the map.
        'inset': box,
        'regions': drawn,
    }


def main(fetched=None):
    features = fetched or {**fetch(1), **fetch(2)}
    out = {country: country_map(regions, features)
           for country, regions in REGIONS.items()}
    with open(os.path.join(HERE, 'outlines.json'), 'w', encoding='utf-8',
              newline='\n') as file:
        json.dump(out, file, ensure_ascii=False, indent=1)
        file.write('\n')


if __name__ == '__main__':
    main()
