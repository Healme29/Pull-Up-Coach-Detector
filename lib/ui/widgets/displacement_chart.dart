/// The displacement trace: how far the body rose over the clip, with each
/// counted rep marked where it peaked.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';

class DisplacementChart extends StatelessWidget {
  const DisplacementChart({
    super.key,
    required this.analysis,
    this.height = 172,
    this.cursorSeconds,
  });

  final Analysis analysis;
  final double height;
  final double? cursorSeconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(
          analysis: analysis,
          cursorSeconds: cursorSeconds,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.analysis,
    required this.textDirection,
    this.cursorSeconds,
  });

  final Analysis analysis;
  final TextDirection textDirection;
  final double? cursorSeconds;

  static const double _left = 6;
  static const double _right = 8;
  static const double _top = 16;
  static const double _bottom = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final points = <Offset>[];
    var maxY = 0.0001;
    var maxT = 0.0;
    for (var i = 0; i < analysis.displacement.length; i++) {
      final t = analysis.times[i];
      final v = analysis.displacement[i];
      if (t.isFinite) maxT = math.max(maxT, t);
      if (!v.isFinite) continue;
      maxY = math.max(maxY, v);
    }
    final threshold = analysis.amplitude * 0.60;
    maxY = math.max(maxY, threshold) * 1.12;
    if (maxT <= 0) maxT = 1;

    double xFor(double t) => plot.left + (t / maxT) * plot.width;
    double yFor(double v) => plot.bottom - (v / maxY) * plot.height;

    // Horizontal guides.
    final grid = Paint()
      ..color = kLine.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    // Threshold line: reps confirm above this.
    final thresholdPaint = Paint()
      ..color = kWarn.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    _dashedLine(
      canvas,
      Offset(plot.left, yFor(threshold)),
      Offset(plot.right, yFor(threshold)),
      thresholdPaint,
    );

    // The signal itself.
    for (var i = 0; i < analysis.displacement.length; i++) {
      final v = analysis.displacement[i];
      if (!v.isFinite) continue;
      points.add(Offset(xFor(analysis.times[i]), yFor(v)));
    }
    if (points.isEmpty) return;

    final area = Path()..moveTo(points.first.dx, plot.bottom);
    for (final p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, plot.bottom)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kAccent.withValues(alpha: 0.28),
            kAccent.withValues(alpha: 0.01),
          ],
        ).createShader(plot),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = kAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Rep peaks.
    for (final rep in analysis.reps) {
      final p = Offset(xFor(rep.peakTime), yFor(rep.height));
      canvas.drawCircle(
        p,
        6,
        Paint()..color = kBg.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        p,
        4,
        Paint()..color = rep.complete ? kGood : kBad,
      );
      _label(
        canvas,
        '${rep.number}',
        Offset(p.dx, p.dy - 13),
        color: kText,
        size: 9,
        align: TextAlign.center,
      );
    }

    // Playhead.
    final cursor = cursorSeconds;
    if (cursor != null && cursor.isFinite) {
      final x = xFor(cursor.clamp(0, maxT));
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = kText.withValues(alpha: 0.65)
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(Offset(x, plot.top), 2.5, Paint()..color = kText);
    }

    // Time axis ends.
    _label(canvas, '0s', Offset(plot.left, plot.bottom + 4),
        color: kMuted, size: 9, align: TextAlign.left);
    _label(canvas, '${maxT.toStringAsFixed(1)}s',
        Offset(plot.right - 26, plot.bottom + 4),
        color: kMuted, size: 9, align: TextAlign.left);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      final end = math.min(x + dash, b.dx);
      canvas.drawLine(Offset(x, a.dy), Offset(end, a.dy), paint);
      x = end + gap;
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    required Color color,
    required double size,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: textDirection,
      textAlign: align,
    )..layout();
    painter.paint(canvas, Offset(at.dx - painter.width / 2, at.dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.analysis != analysis || old.cursorSeconds != cursorSeconds;
}
