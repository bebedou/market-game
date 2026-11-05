import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

/// An amount that counts to its new value when it changes.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(
    this.amount, {
    super.key,
    this.prefix = '',
    this.signed = false,
    this.cents = true,
    this.colored = false,
    this.style,
  });

  final Money amount;
  final String prefix;

  /// With a `+` on gains.
  final bool signed;
  final bool cents;

  /// Green for gains, red for losses.
  final bool colored;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: amount.cents.toDouble()),
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) {
      final shown = Money(value.round());
      return Text(
        '$prefix${signed ? signedMoney(shown, cents: cents) : money(shown, cents: cents)}',
        style: figures(style).copyWith(
          color: colored ? gainTone(context, amount.cents.sign) : null,
        ),
      );
    },
  );
}

/// A small tag ruled in ink, or in [color]: a store's status, a kind of
/// product.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color});

  final String text;
  final IconData? icon;

  /// The ink; the muted ink if null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: 0.8),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: 4),
          ],
          // Shortened rather than overflowing a narrow row.
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rubber stamp in red ink, slightly askew: something needs seeing to.
class Stamp extends StatelessWidget {
  const Stamp(this.text, {super.key, this.color});

  final String text;

  /// The ink; red if null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = color ?? Ledger.of(context).loss;
    return Transform.rotate(
      angle: -0.06,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: ink, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: figures(
            theme.textTheme.labelSmall,
          ).copyWith(color: ink, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A thin rounded bar filled to [value], from 0 to 1, that glides to new
/// values.
class LevelBar extends StatelessWidget {
  const LevelBar(this.value, {super.key, this.color, this.height = 4});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => LinearProgressIndicator(
        value: shown,
        minHeight: height,
        color: color ?? scheme.primary,
        backgroundColor: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// A key figure: an icon, a label, a value and how it moved.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trend,
    this.trendSign = 0,
    this.color,
  });

  final IconData icon;
  final String label;
  final Widget value;

  /// A short note on the change, such as `+12% on last week`.
  final String? trend;
  final int trendSign;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color ?? theme.colorScheme.onSurface),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: figures(
              theme.textTheme.titleLarge,
            ).copyWith(fontSize: 22, fontWeight: FontWeight.w500),
            child: value,
          ),
          if (trend case final trend?)
            Text(
              trend,
              style: theme.textTheme.labelSmall?.copyWith(
                color: gainTone(context, trendSign),
              ),
            ),
        ],
      ),
    );
  }
}

/// A line over [values], filled beneath, drawn in on first show.
class Sparkline extends StatelessWidget {
  const Sparkline(
    this.values, {
    super.key,
    required this.color,
    this.height = 44,
  });

  final List<num> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) =>
          CustomPaint(painter: _SparklinePainter(values, color, progress)),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.progress);

  final List<num> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final doubles = [for (final value in values) value.toDouble()];
    final high = doubles.reduce(math.max);
    final low = doubles.reduce(math.min);
    final span = high - low == 0 ? 1.0 : high - low;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height -
              4 -
              (size.height - 8) * (values[i] - low) / span * progress,
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final middle = (previous.dx + point.dx) / 2;
      line.cubicTo(middle, previous.dy, middle, point.dy, point.dx, point.dy);
    }
    canvas
      ..drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(points.last, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color || old.progress != progress;
}

/// Bars for [values] around zero, gains up in green and losses down in
/// red; the [selected] one stands out, and a tap picks one.
class BarChart extends StatelessWidget {
  const BarChart(
    this.values, {
    super.key,
    this.selected,
    this.onSelect,
    this.height = 110,
  });

  final List<num> values;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Gains in plain ink, losses in red: the ledger shows trouble.
    final up = Theme.of(context).colorScheme.onSurfaceVariant;
    final down = gainTone(context, -1);
    final base = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onSelect == null || values.isEmpty
            ? null
            : (details) => onSelect!(
                (details.localPosition.dx /
                        constraints.maxWidth *
                        values.length)
                    .floor()
                    .clamp(0, values.length - 1),
              ),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (context, progress, _) => CustomPaint(
              painter: _BarPainter(values, selected, up, down, base, progress),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(
    this.values,
    this.selected,
    this.up,
    this.down,
    this.base,
    this.progress,
  );

  final List<num> values;
  final int? selected;
  final Color up;
  final Color down;
  final Color base;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final doubles = [for (final value in values) value.toDouble()];
    final high = math.max(0.0, doubles.reduce(math.max));
    final low = math.min(0.0, doubles.reduce(math.min));
    final span = high - low == 0 ? 1.0 : high - low;
    final zero = size.height * high / span;
    final slot = size.width / values.length;
    final width = math.min(slot * 0.5, 18.0);
    for (var i = 0; i < values.length; i++) {
      final value = values[i].toDouble();
      final length = size.height * value.abs() / span * progress;
      final x = slot * i + (slot - width) / 2;
      final rect = value >= 0
          ? Rect.fromLTWH(x, zero - length, width, length)
          : Rect.fromLTWH(x, zero, width, length);
      final faded = selected != null && selected != i;
      final color = (value >= 0 ? up : down).withValues(
        alpha: faded ? 0.35 : 1,
      );
      canvas.drawRect(rect, Paint()..color = color);
    }
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.progress != progress;
}

/// One bar split into coloured parts, with a legend: where money went.
class SplitBar extends StatelessWidget {
  const SplitBar(this.parts, {super.key});

  final List<({String label, int value, Color color})> parts;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final part in parts)
        if (part.value > 0) part,
    ];
    final total = shown.fold(0, (sum, part) => sum + part.value);
    if (total == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRect(
          child: SizedBox(
            height: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final part in shown)
                  Expanded(
                    flex: math.max(1, part.value * 1000 ~/ total),
                    child: ColoredBox(color: part.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final part in shown)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 9,
                    child: ColoredBox(color: part.color),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${part.label} ${share(part.value, total)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Fades and slides its child in the first time it is shown.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// One line of a [TrendChart].
typedef TrendSeries = ({String label, Color color, List<double> values});

/// Several series over the same months as lines on a shared scale, with
/// the latest value of each in its legend.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    this.unit = '',
    this.height = 120,
  });

  final List<TrendSeries> series;

  /// '%' to show values as percentages, '×' as multiples.
  final String unit;
  final double height;

  String _format(double value) => unit == '%'
      ? percentOf(decimalText(value.toStringAsFixed(1)))
      : '×${decimalText(value.toStringAsFixed(2))}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = [for (final s in series) ...s.values];
    if (all.isEmpty) return const SizedBox.shrink();
    final high = all.reduce(math.max);
    final low = all.reduce(math.min);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: height,
                child: CustomPaint(
                  painter: _TrendPainter(
                    series,
                    theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_format(high), style: theme.textTheme.labelSmall),
                  Text(_format(low), style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 3,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${s.label} ${s.values.isEmpty ? '' : _format(s.values.last)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.series, this.grid);

  final List<TrendSeries> series;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.values];
    if (all.isEmpty) return;
    var high = all.reduce(math.max);
    var low = all.reduce(math.min);
    if (high == low) {
      high += 1;
      low -= 1;
    }
    final span = high - low;
    double y(double value) => size.height - (value - low) / span * size.height;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final fraction in const [0.0, 0.5, 1.0]) {
      final at = size.height * fraction;
      canvas.drawLine(Offset(0, at), Offset(size.width, at), gridPaint);
    }
    if (low < 0 && high > 0) {
      canvas.drawLine(
        Offset(0, y(0)),
        Offset(size.width, y(0)),
        gridPaint..strokeWidth = 1.5,
      );
    }
    for (final s in series) {
      if (s.values.length < 2) continue;
      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final x = size.width * i / (s.values.length - 1);
        final point = Offset(x, y(s.values[i]));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.series != series || old.grid != grid;
}
