import 'package:flutter/material.dart';

import '../domain/economy.dart';
import 'format.dart';

const storeColors = [Color(0xFF226C52), Color(0xFF4D73B4), Color(0xFFAA7834)];

enum TrendMetric {
  revenue('Revenue'),
  profit('Profit'),
  share('Revenue share');

  const TrendMetric(this.label);
  final String label;

  double value(DailyReport report, String storeId) => switch (this) {
    revenue => report.businesses[storeId]!.revenue.toDouble(),
    profit => report.businesses[storeId]!.profit.toDouble(),
    share => (report.marketShares[storeId] ?? 0) * 100,
  };

  String format(double value) =>
      this == share ? '${value.toStringAsFixed(1)}%' : money(value.round());
}

/// All shops use the same axis and completed-day window.
class CompetitionChart extends StatefulWidget {
  const CompetitionChart({
    super.key,
    required this.reports,
    required this.stores,
  });
  final List<DailyReport> reports;
  final List<Store> stores;

  @override
  State<CompetitionChart> createState() => _CompetitionChartState();
}

class _CompetitionChartState extends State<CompetitionChart> {
  TrendMetric _metric = TrendMetric.revenue;

  @override
  Widget build(BuildContext context) {
    final reports = widget.reports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          child: DropdownButton<TrendMetric>(
            value: _metric,
            isExpanded: true,
            itemHeight: null,
            items: [
              for (final metric in TrendMetric.values)
                DropdownMenuItem(
                  value: metric,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(metric.label),
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _metric = value!),
          ),
        ),
        if (reports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'No completed days yet\nPress Play or Next day to start measuring.',
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final series = [
                for (final store in widget.stores)
                  [for (final r in reports) _metric.value(r, store.id)],
              ];
              final values = series.expand((s) => s);
              final min = values.fold<double>(0, (a, b) => a < b ? a : b);
              final max = values.fold<double>(0, (a, b) => a > b ? a : b);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Axis ${_metric.format(min)} → ${_metric.format(max)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    label:
                        '${_metric.label}, days ${reports.first.day} to ${reports.last.day}. '
                        '${[for (var i = 0; i < widget.stores.length; i++) '${widget.stores[i].name}: ${_metric.format(series[i].last)}'].join('. ')}',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 160,
                        child: CustomPaint(
                          painter: _TrendPainter(series, min, max),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Day ${reports.first.day} → ${reports.last.day} · daily values',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < widget.stores.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            '${i + 1}. ${widget.stores[i].name}',
                            style: TextStyle(
                              color: storeColors[i],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(_metric.format(series[i].last)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.series, this.min, this.max);
  final List<List<double>> series;
  final double min;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final height = size.height - inset * 2;
    final width = size.width - inset * 2;
    final range = max == min ? 1.0 : max - min;
    double y(double value) => inset + height * (1 - (value - min) / range);
    final grid = Paint()
      ..color = const Color(0xFFE7ECE7)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final dy = inset + height * i / 4;
      canvas.drawLine(Offset(inset, dy), Offset(size.width - inset, dy), grid);
    }
    canvas.drawLine(
      Offset(inset, y(0)),
      Offset(size.width - inset, y(0)),
      Paint()..color = const Color(0xFF9CAAA0),
    );
    for (var s = 0; s < series.length; s++) {
      final values = series[s];
      final points = [
        for (var i = 0; i < values.length; i++)
          Offset(
            inset +
                (values.length == 1
                    ? width / 2
                    : width * i / (values.length - 1)),
            y(values[i]),
          ),
      ];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final paint = Paint()
        ..color = storeColors[s]
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      // Solid, dashed, dotted lines remain distinguishable without color.
      if (s == 0) {
        canvas.drawPath(path, paint);
      } else {
        for (final metric in path.computeMetrics()) {
          final dash = s == 1 ? 8.0 : 2.0;
          for (var d = 0.0; d < metric.length; d += dash + 4) {
            canvas.drawPath(metric.extractPath(d, d + dash), paint);
          }
        }
      }
      canvas.drawCircle(points.last, 4, Paint()..color = storeColors[s]);
      final label = TextPainter(
        text: TextSpan(
          text: '${s + 1}',
          style: TextStyle(
            fontSize: 11,
            color: storeColors[s],
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(points.last.dx - label.width - 5, points.last.dy - 16),
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) => true;
}
