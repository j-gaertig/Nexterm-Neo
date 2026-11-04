import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';

/// Minimal line chart for monitoring series (no external chart dependency).
class MonitoringLineChart extends StatelessWidget {
  final String title;
  final List<DateTime> times;
  final List<double?> values;
  final Color color;
  final String unit;

  /// Fixed upper bound (for example 100 for percentages); auto when null.
  final double? yMax;
  final double height;

  const MonitoringLineChart({
    super.key,
    required this.title,
    required this.times,
    required this.values,
    required this.color,
    this.unit = '',
    this.yMax,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final present = values.whereType<double>().toList();
    final last = present.isEmpty ? null : present.last;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (last != null)
                Text(
                  '${last.toStringAsFixed(last % 1 == 0 ? 0 : 1)}$unit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            child: present.length < 2
                ? Center(
                    child: Text(
                      'Not enough data yet',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  )
                : RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ChartPainter(
                        values: values,
                        color: color,
                        grid: appBorderColor(cs),
                        label: cs.outline,
                        yMax: yMax,
                        unit: unit,
                      ),
                    ),
                  ),
          ),
          if (times.length >= 2 && present.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _clock(times.first),
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                  Text(
                    _clock(times.last),
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _ChartPainter extends CustomPainter {
  final List<double?> values;
  final Color color;
  final Color grid;
  final Color label;
  final double? yMax;
  final String unit;

  _ChartPainter({
    required this.values,
    required this.color,
    required this.grid,
    required this.label,
    required this.yMax,
    required this.unit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 34.0;
    final plot = Rect.fromLTWH(
      leftPad,
      4,
      size.width - leftPad,
      size.height - 8,
    );
    final present = values.whereType<double>();
    var top =
        yMax ??
        (present.isEmpty ? 1.0 : present.reduce((a, b) => a > b ? a : b));
    if (top <= 0) top = 1;
    if (yMax == null) top *= 1.15;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final value = top * (1 - i / 4);
      final tp = TextPainter(
        text: TextSpan(
          text: value.toStringAsFixed(value >= 10 ? 0 : 1),
          style: TextStyle(fontSize: 10, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final count = values.length;
    final path = Path();
    final area = Path();
    var started = false;
    double? lastX;
    for (var i = 0; i < count; i++) {
      final v = values[i];
      if (v == null) {
        started = false;
        continue;
      }
      final x = plot.left + plot.width * (count == 1 ? 0 : i / (count - 1));
      final y = plot.bottom - plot.height * (v / top).clamp(0.0, 1.0);
      if (!started) {
        path.moveTo(x, y);
        area.moveTo(x, plot.bottom);
        area.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
      lastX = x;
    }
    if (lastX != null) {
      area.lineTo(lastX, plot.bottom);
      area.close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.values != values || old.color != color || old.yMax != yMax;
}
