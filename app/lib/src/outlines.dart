import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where each country's region outlines are, among the content's assets:
/// see `content/countries/build_outlines.py`.
const outlinesAsset = 'packages/market_content/countries/outlines.json';

/// A country's regions drawn for its ink map, in a frame [width] by
/// [height] units, with the box any inset region stands in.
final class CountryOutline {
  const CountryOutline({
    required this.width,
    required this.height,
    required this.inset,
    required this.regions,
  });

  final double width;
  final double height;
  final Rect? inset;

  /// By the national table's region key.
  final Map<String, RegionOutline> regions;
}

/// One region's shape, holes and all, to fill even-odd; where its figure
/// goes; and its area, smaller regions being drawn over larger ones.
final class RegionOutline {
  const RegionOutline({
    required this.path,
    required this.label,
    required this.area,
  });

  final Path path;
  final Offset label;
  final double area;
}

/// The outlines in [text], by country key.
Map<String, CountryOutline> parseOutlines(String text) {
  final root = jsonDecode(text) as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in root.entries)
      key: () {
        final country = value! as Map<String, Object?>;
        final inset = country['inset'] as List<Object?>?;
        return CountryOutline(
          width: (country['width']! as num).toDouble(),
          height: (country['height']! as num).toDouble(),
          inset: inset == null
              ? null
              : Rect.fromLTRB(
                  (inset[0]! as num).toDouble(),
                  (inset[1]! as num).toDouble(),
                  (inset[2]! as num).toDouble(),
                  (inset[3]! as num).toDouble(),
                ),
          regions: {
            for (final MapEntry(:key, :value)
                in (country['regions']! as Map<String, Object?>).entries)
              key: () {
                final region = value! as Map<String, Object?>;
                final label = region['label']! as List<Object?>;
                return RegionOutline(
                  path: _path(region['path']! as String),
                  label: Offset(
                    (label[0]! as num).toDouble(),
                    (label[1]! as num).toDouble(),
                  ),
                  area: (region['area']! as num).toDouble(),
                );
              }(),
          },
        );
      }(),
  };
}

/// A path of rings written `M x yLx y…Z`, filled even-odd so a ring inside
/// another is a hole.
Path _path(String text) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in text.split('Z')) {
    if (ring.isEmpty) continue;
    final points = ring.substring(1).split('L');
    for (final (i, point) in points.indexed) {
      final xy = point.split(' ');
      final x = double.parse(xy[0]);
      final y = double.parse(xy[1]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
  }
  return path;
}

Map<String, CountryOutline>? _outlines;

/// [country]'s outlines, by the national table's key, if they're loaded.
CountryOutline? outlineOf(String country) => _outlines?[country];

/// Makes [outlines] the ones the maps draw.
void useOutlines(Map<String, CountryOutline> outlines) => _outlines = outlines;

/// Loads the bundled outlines, once.
Future<void> loadOutlines() async {
  if (_outlines != null) return;
  useOutlines(parseOutlines(await rootBundle.loadString(outlinesAsset)));
}
