// Hand-rolled line chart — faithful port of the web app's drawLineChart
// (~/workspace/health-app/app.js). CustomPaint: grid + y labels, sparse x
// labels, dots, legend, auto min/max, empty state 'မှတ်တမ်း မရှိသေးပါ'.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One point on a series. [y] may be null — the line breaks there, exactly
/// as the web chart skips null points.
class ChartPoint {
  const ChartPoint(this.x, this.y);
  final String x;
  final double? y;
}

/// One plotted series: label + color + points.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });
  final String label;
  final Color color;
  final List<ChartPoint> points;
}

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.series,
    this.unit = '',
    this.showDots = true,
    this.min,
    this.max,
    this.height = 220,
  });

  final List<ChartSeries> series;
  final String unit;
  final bool showDots;
  final double? min;
  final double? max;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _LineChartPainter(
          series: series,
          unit: unit,
          showDots: showDots,
          minOverride: min,
          maxOverride: max,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.unit,
    required this.showDots,
    required this.minOverride,
    required this.maxOverride,
  });

  final List<ChartSeries> series;
  final String unit;
  final bool showDots;
  final double? minOverride;
  final double? maxOverride;

  // Web paddings: padL 44, padR 10, padT 14, padB 28.
  static const double _padL = 44;
  static const double _padR = 10;
  static const double _padT = 14;
  static const double _padB = 28;

  static const Color _gridColor = Color(0xFFE3E9F2);
  static const Color _axisTextColor = Color(0xFF66707E);
  static const Color _legendTextColor = Color(0xFF1C232B);

  TextPainter _textPainter(String text, double fontSize, Color color,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    return tp;
  }

  /// Draw [text] so its alphabetic baseline sits at [baselineY].
  void _drawAtBaseline(Canvas canvas, TextPainter tp, double x, double baselineY) {
    final baseline =
        tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(x, baselineY - baseline));
  }

  /// Web y-label: (Math.round(v * 10) / 10) + unit — integers print without '.0'.
  String _fmtY(double v) {
    final r = (v * 10).round() / 10;
    if (r == r.truncateToDouble()) return '${r.toInt()}$unit';
    return '$r$unit';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final allY = <double>[];
    for (final s in series) {
      for (final p in s.points) {
        if (p.y != null) allY.add(p.y!);
      }
    }
    if (allY.isEmpty) {
      final tp = _textPainter('မှတ်တမ်း မရှိသေးပါ', 14, _axisTextColor,
          align: TextAlign.center);
      _drawAtBaseline(canvas, tp, w / 2 - tp.width / 2, h / 2);
      return;
    }

    var minV = minOverride ?? allY.reduce(math.min);
    var maxV = maxOverride ?? allY.reduce(math.max);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }

    final iw = w - _padL - _padR;
    final ih = h - _padT - _padB;
    final n = series.fold<int>(0, (m, s) => math.max(m, s.points.length));
    double xAt(int i) => _padL + (n == 1 ? iw / 2 : (i / (n - 1)) * iw);
    double yAt(double v) => _padT + ih - ((v - minV) / (maxV - minV)) * ih;

    // Grid + y labels (5 lines, g = 0..4).
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final v = minV + (maxV - minV) * g / 4;
      final y = yAt(v);
      canvas.drawLine(
        Offset(_padL, y),
        Offset(w - _padR, y),
        gridPaint,
      );
      final tp = _textPainter(_fmtY(v), 11, _axisTextColor,
          align: TextAlign.right);
      _drawAtBaseline(canvas, tp, _padL - 6 - tp.width, y + 4);
    }

    // X labels (sparse: every ceil(n / 6)th point, from the first series).
    if (series.isNotEmpty && n > 0) {
      final step = (n / 6).ceil();
      for (var i = 0; i < n; i += step) {
        final lbl = i < series[0].points.length ? series[0].points[i].x : '';
        if (lbl.isEmpty) continue;
        final tp = _textPainter(lbl, 11, _axisTextColor,
            align: TextAlign.center);
        _drawAtBaseline(canvas, tp, xAt(i) - tp.width / 2, h - 8);
      }
    }

    // Series lines + dots.
    for (final s in series) {
      final linePaint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        if (p.y == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(xAt(i), yAt(p.y!));
          started = true;
        } else {
          path.lineTo(xAt(i), yAt(p.y!));
        }
      }
      canvas.drawPath(path, linePaint);
      if (showDots) {
        final dotPaint = Paint()..color = s.color;
        for (var i = 0; i < s.points.length; i++) {
          final p = s.points[i];
          if (p.y == null) continue;
          canvas.drawCircle(Offset(xAt(i), yAt(p.y!)), 3.5, dotPaint);
        }
      }
    }

    // Legend (top row, starting at padL).
    var lx = _padL;
    for (final s in series) {
      canvas.drawRect(
        Rect.fromLTWH(lx, 6, 14, 4),
        Paint()..color = s.color,
      );
      final tp = _textPainter(s.label, 12, _legendTextColor);
      _drawAtBaseline(canvas, tp, lx + 18, 12);
      lx += tp.width + 44;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series ||
      old.unit != unit ||
      old.showDots != showDots ||
      old.minOverride != minOverride ||
      old.maxOverride != maxOverride;
}
