/// The skeleton drawn over the replay: limb-coloured bones, bright joints, and
/// the bar line the wrists make.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/pose.dart';
import '../theme.dart';

class PoseOverlay extends StatelessWidget {
  const PoseOverlay({super.key, required this.person});

  final Person? person;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SkeletonPainter(person: person),
    size: Size.infinite,
  );
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({required this.person});

  final Person? person;

  static const double _minScore = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    final p = person;
    if (p == null || p.kpts.isEmpty) return;

    Kpt? at(int i) {
      if (i >= p.kpts.length) return null;
      final k = p.kpts[i];
      if (k.unseen) return null;
      if (i < p.scores.length && p.scores[i] < _minScore) return null;
      return k;
    }

    Offset? offsetOf(int i) {
      final k = at(i);
      return k == null ? null : Offset(k.x * size.width, k.y * size.height);
    }

    // The bar: a line across the two wrists, when both are seen.
    final leftWrist = offsetOf(9);
    final rightWrist = offsetOf(10);
    if (leftWrist != null && rightWrist != null) {
      final bar = Paint()
        ..color = kText.withValues(alpha: 0.35)
        ..strokeWidth = math.max(2, size.height * 0.005)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(leftWrist, rightWrist, bar);
    }

    // Bones.
    for (final (a, b, _) in skeletonEdges) {
      final pa = offsetOf(a);
      final pb = offsetOf(b);
      if (pa == null || pb == null) continue;
      final color = limbColors[edgePart(a, b)] ?? kText;
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = color
          ..strokeWidth = math.max(2.4, size.height * 0.006)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Joints.
    final joint = Paint()..color = kText;
    final halo = Paint()..color = kBg.withValues(alpha: 0.6);
    for (var i = 0; i < kptNames.length; i++) {
      final o = offsetOf(i);
      if (o == null) continue;
      final r = math.max(2.6, size.height * 0.0075);
      canvas.drawCircle(o, r + 1.6, halo);
      canvas.drawCircle(o, r, joint);
    }

    // A soft ring around the head so it reads at a glance.
    final head = <Offset>[];
    for (final i in faceKpts) {
      final o = offsetOf(i);
      if (o != null) head.add(o);
    }
    if (head.isNotEmpty) {
      final cx = head.map((o) => o.dx).reduce((a, b) => a + b) / head.length;
      final cy = head.map((o) => o.dy).reduce((a, b) => a + b) / head.length;
      canvas.drawCircle(
        Offset(cx, cy),
        math.max(10, size.height * 0.035),
        Paint()
          ..color = kText.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.person != person;
}
