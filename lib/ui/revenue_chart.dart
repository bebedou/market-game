import 'package:flutter/material.dart';

import '../domain/economy.dart';
import 'format.dart';

class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key, required this.reports, required this.storeId});
  final List<DailyReport> reports;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(Icons.show_chart, size: 32, color: Color(0xFF718378)),
            SizedBox(height: 12),
            Text(
              'Your first trading day starts the story.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              'Press Play or advance one day to see real revenue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF66776D)),
            ),
          ],
        ),
      );
    }
    final values = [for (final r in reports) r.businesses[storeId]!.revenue];
    final peak = values.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Daily revenue from day ${reports.first.day} to day ${reports.last.day}. '
              'Latest ${money(values.last)}. Peak ${money(peak)}.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 150,
              child: CustomPaint(
                painter: _RevenuePainter(
                  values,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Day ${reports.first.day} → ${reports.last.day}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Peak ${money(peak)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _RevenuePainter extends CustomPainter {
  _RevenuePainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final height = size.height - inset * 2;
    final width = size.width - inset * 2;
    final maxValue = values.fold<int>(1, (a, b) => a > b ? a : b);
    final grid = Paint()
      ..color = const Color(0xFFE7ECE7)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = inset + height * i / 3;
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), grid);
    }
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          inset +
              (values.length == 1
                  ? width / 2
                  : width * i / (values.length - 1)),
          inset + height * (1 - values[i] / maxValue * 0.9),
        ),
    ];
    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      final area = Path.from(line)
        ..lineTo(points.last.dx, size.height - inset)
        ..lineTo(points.first.dx, size.height - inset)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.08));
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.drawCircle(points.last, 5, Paint()..color = color);
    canvas.drawCircle(points.last, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RevenuePainter oldDelegate) => true;
}
