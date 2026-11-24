/// Rotate a reply's keypoints so the body reads upright on screen.
///
/// The phone stores portrait video as landscape pixels plus a rotation tag.
/// ExoPlayer applies that tag; a server-side decoder may or may not. Rather
/// than guess, read the geometry: a pull-up is always head-above-hips, so the
/// rotation that makes it so is the rotation the reply is in.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'config.dart';
import 'models.dart';
import 'pose.dart';

class OrientedPose {
  const OrientedPose({
    required this.frames,
    required this.aspect,
    required this.rotationDegrees,
  });

  final List<PoseFrame> frames;

  /// Width / height after rotation, so elbow angles are measured on the
  /// displayed frame.
  final double aspect;
  final int rotationDegrees;
}

Kpt _rotate(Kpt p, int degrees) {
  switch (degrees % 360) {
    case 90:
      return Kpt(1 - p.y, p.x);
    case 180:
      return Kpt(1 - p.x, 1 - p.y);
    case 270:
      return Kpt(p.y, 1 - p.x);
    default:
      return p;
  }
}

Rect _rotateRect(Rect r, int degrees) {
  final corners = [
    Kpt(r.left, r.top),
    Kpt(r.right, r.top),
    Kpt(r.left, r.bottom),
    Kpt(r.right, r.bottom),
  ].map((p) => _rotate(p, degrees)).toList();
  final xs = corners.map((p) => p.x);
  final ys = corners.map((p) => p.y);
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

Kpt? _meanKpt(Person person, List<String> names) {
  var x = 0.0;
  var y = 0.0;
  var n = 0;
  for (final name in names) {
    final i = kptIndex[name];
    if (i == null || i >= person.kpts.length) continue;
    final p = person.kpts[i];
    if (p.unseen) continue;
    x += p.x;
    y += p.y;
    n++;
  }
  return n == 0 ? null : Kpt(x / n, y / n);
}

double _medianOf(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Pick the rotation that puts the head above the hips, then apply it.
OrientedPose normalizeOrientation(List<PoseFrame> frames, double aspect) {
  final headNames = const ['nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear'];
  final dxs = <double>[];
  final dys = <double>[];
  for (final frame in frames) {
    if (frame.persons.isEmpty) continue;
    final person = frame.persons.first;
    final head = _meanKpt(person, headNames);
    final hips = _meanKpt(person, const ['left_hip', 'right_hip']);
    if (head == null || hips == null) continue;
    dxs.add(head.x - hips.x);
    dys.add(head.y - hips.y);
  }
  if (dxs.isEmpty) {
    return OrientedPose(frames: frames, aspect: aspect, rotationDegrees: 0);
  }
  final dx = _medianOf(dxs);
  final dy = _medianOf(dys);

  // Score each candidate by how clearly it puts the head above the hips.
  var best = 0;
  var bestScore = double.negativeInfinity;
  for (final candidate in const [0, 90, 180, 270]) {
    final rotated = _rotate(Kpt(dx, dy), candidate);
    // Screen y grows downwards: head above hips is negative y.
    final score = -rotated.y - 2 * rotated.x.abs();
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  if (best == 0) {
    return OrientedPose(frames: frames, aspect: aspect, rotationDegrees: 0);
  }

  final rotatedFrames = [
    for (final frame in frames)
      PoseFrame(
        index: frame.index,
        persons: [
          for (final person in frame.persons)
            Person(
              kpts: [for (final p in person.kpts) _rotate(p, best)],
              scores: person.scores,
              bbox: _rotateRect(person.bbox, best),
              trackId: person.trackId,
            ),
        ],
      ),
  ];
  // [aspect] is the clip's display aspect. Rotating the keypoints by the
  // missing rotation tag lands them in that same display orientation, so the
  // aspect does not change with the rotation: a portrait clip stays portrait.
  return OrientedPose(
    frames: rotatedFrames,
    aspect: aspect,
    rotationDegrees: best,
  );
}

/// The frame rate the app and the model share.
double poseFps() => PipelineConfig.inferenceFps;
