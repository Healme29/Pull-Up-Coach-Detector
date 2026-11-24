/// COCO-17 keypoints, the skeleton, and the shape of a gateway pose reply.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'models.dart';

/// The 17 keypoints, in the order the model returns them.
const List<String> kptNames = [
  'nose',
  'left_eye',
  'right_eye',
  'left_ear',
  'right_ear',
  'left_shoulder',
  'right_shoulder',
  'left_elbow',
  'right_elbow',
  'left_wrist',
  'right_wrist',
  'left_hip',
  'right_hip',
  'left_knee',
  'right_knee',
  'left_ankle',
  'right_ankle',
];

final Map<String, int> kptIndex = {
  for (var i = 0; i < kptNames.length; i++) kptNames[i]: i,
};

const Set<int> faceKpts = {0, 1, 2, 3, 4};

/// `(a, b, side)`; "H" edges touch a face keypoint and are dropped with it.
const List<(int, int, String)> skeletonEdges = [
  (15, 13, 'L'),
  (13, 11, 'L'),
  (16, 14, 'R'),
  (14, 12, 'R'),
  (11, 12, 'T'),
  (5, 11, 'L'),
  (6, 12, 'R'),
  (5, 6, 'T'),
  (5, 7, 'L'),
  (7, 9, 'L'),
  (6, 8, 'R'),
  (8, 10, 'R'),
  (0, 1, 'H'),
  (0, 2, 'H'),
  (1, 3, 'H'),
  (2, 4, 'H'),
  (3, 5, 'H'),
  (4, 6, 'H'),
];

const Map<String, Color> limbColors = {
  'left_arm': Color(0xFF22D3EE),
  'right_arm': Color(0xFF6366F1),
  'left_leg': Color(0xFFE879F9),
  'right_leg': Color(0xFFFB7185),
  'torso': Color(0xFFCBD5E1),
};

const Set<int> _torsoJoints = {5, 6, 11, 12};
const Map<String, Set<int>> _parts = {
  'left_arm': {5, 7, 9},
  'right_arm': {6, 8, 10},
  'left_leg': {11, 13, 15},
  'right_leg': {12, 14, 16},
};

String edgePart(int a, int b) {
  if (_torsoJoints.contains(a) && _torsoJoints.contains(b)) return 'torso';
  for (final entry in _parts.entries) {
    if (entry.value.contains(a) && entry.value.contains(b)) return entry.key;
  }
  return 'torso';
}

/// One model reply: frames sorted by index, plus how many duplicate boxes the
/// track handoff produced.
class PoseReply {
  PoseReply({required this.frames, required this.dropped, required this.raw});

  final List<PoseFrame> frames;
  final int dropped;
  final Map<String, dynamic> raw;

  Map<int, List<Person>> get byIndex =>
      {for (final f in frames) f.index: f.persons};

  int get maxFrameIndex =>
      frames.isEmpty ? 0 : frames.map((f) => f.index).reduce(math.max);
}

/// Group the flat person records by `frame_id` and collapse duplicate boxes.
///
/// Mirrors `src/pose.py`: the reply is a flat envelope with `content.items`,
/// and `content.frames` carries frames where nobody was found.
PoseReply parsePoseReply(Object? decoded,
    {int maxPersons = 1, double iou = 0.6}) {
  if (decoded is! Map) {
    throw const FormatException('The gateway reply was not a JSON object.');
  }
  final payload = Map<String, dynamic>.from(decoded);
  final content = payload['content'];
  if (content is! Map) {
    throw const FormatException('The gateway reply had no pose envelope.');
  }
  final object = content['object'];
  if (object != 'vid.pose.kpts') {
    throw FormatException(
      'Expected a video pose reply (vid.pose.kpts), got "$object".',
    );
  }
  final labels = content['kpts_labels'];
  if (labels is List && labels.join(',') != kptNames.join(',')) {
    throw FormatException(
      'The model returned ${labels.length} joints in an order this app does '
      'not know.',
    );
  }

  final byIndex = <int, List<Person>>{};
  for (final frame in (content['frames'] as List? ?? const [])) {
    final id = (frame as Map)['frame_id'];
    if (id is num) byIndex[id.toInt()] = <Person>[];
  }
  for (final item in (content['items'] as List? ?? const [])) {
    final map = item as Map;
    final id = map['frame_id'];
    if (id is! num) continue;
    byIndex
        .putIfAbsent(id.toInt(), () => <Person>[])
        .add(Person.fromJson(Map<String, dynamic>.from(map)));
  }

  final indices = byIndex.keys.toList()..sort();
  final frames = [
    for (final i in indices) PoseFrame(index: i, persons: byIndex[i]!),
  ];
  final dropped = dedupe(frames, maxPersons: maxPersons, iou: iou);
  return PoseReply(frames: frames, dropped: dropped, raw: payload);
}

double _area(Rect r) => r.width * r.height;

double _iou(Rect a, Rect b) {
  final x0 = math.max(a.left, b.left);
  final y0 = math.max(a.top, b.top);
  final x1 = math.min(a.left + a.width, b.left + b.width);
  final y1 = math.min(a.top + a.height, b.top + b.height);
  final inter = math.max(0.0, x1 - x0) * math.max(0.0, y1 - y0);
  final union = _area(a) + _area(b) - inter;
  return union > 0 ? inter / union : 0.0;
}

/// Collapse duplicate boxes per frame, keeping the best match to the previous
/// frame and then the larger box. Returns how many were dropped.
int dedupe(List<PoseFrame> frames,
    {required int maxPersons, required double iou}) {
  Rect? previous;
  var dropped = 0;
  for (final frame in frames) {
    final persons = frame.persons;
    if (persons.isEmpty) continue;
    final order = [...persons]..sort((a, b) {
        final ai = previous == null ? 0.0 : _iou(a.bbox, previous);
        final bi = previous == null ? 0.0 : _iou(b.bbox, previous);
        if (ai != bi) return bi.compareTo(ai);
        return _area(b.bbox).compareTo(_area(a.bbox));
      });
    final kept = <Person>[];
    for (final person in order) {
      if (kept.every((k) => _iou(person.bbox, k.bbox) < iou)) {
        kept.add(person);
      }
    }
    final trimmed = kept.take(maxPersons).toList();
    dropped += persons.length - trimmed.length;
    frame.persons
      ..clear()
      ..addAll(trimmed);
    if (trimmed.isNotEmpty) previous = trimmed.first.bbox;
  }
  return dropped;
}

/// A point in pixel space, for drawing.
Offset pixelOf(Kpt p, Size size) => Offset(p.x * size.width, p.y * size.height);
