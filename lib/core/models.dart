/// The data the analysis reads and writes: keypoints in, reps out.
library;

import 'dart:ui' show Rect;

/// One normalized keypoint, `[0, 1]` in both axes.
class Kpt {
  const Kpt(this.x, this.y);

  final double x;
  final double y;

  /// The model's "not visible" sentinel.
  bool get unseen => x == 0 && y == 0;

  @override
  bool operator ==(Object other) =>
      other is Kpt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// One detected body in one frame.
class Person {
  const Person({
    required this.kpts,
    required this.scores,
    required this.bbox,
    this.trackId,
  });

  final List<Kpt> kpts;
  final List<double> scores;
  final Rect bbox;
  final int? trackId;

  Map<String, dynamic> toJson() => {
    'kpts_xy': [
      for (final p in kpts) [p.x, p.y],
    ],
    'kpts_score': scores,
    'bbox_xywh': [bbox.left, bbox.top, bbox.width, bbox.height],
    if (trackId != null) 'track_id': trackId,
  };

  factory Person.fromJson(Map<String, dynamic> json) {
    final rawKpts = (json['kpts_xy'] as List?) ?? const [];
    final rawScores = (json['kpts_score'] as List?) ?? const [];
    final box = (json['bbox_xywh'] as List?) ?? const [0, 0, 1, 1];
    return Person(
      kpts: [
        for (final p in rawKpts)
          Kpt(
            ((p as List)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ),
      ],
      scores: [for (final s in rawScores) (s as num).toDouble()],
      bbox: Rect.fromLTWH(
        (box[0] as num).toDouble(),
        (box[1] as num).toDouble(),
        (box[2] as num).toDouble(),
        (box[3] as num).toDouble(),
      ),
      trackId: (json['track_id'] as num?)?.toInt(),
    );
  }
}

/// One frame of poses, keyed by its source-frame index.
class PoseFrame {
  const PoseFrame({required this.index, required this.persons});

  final int index;
  final List<Person> persons;

  Map<String, dynamic> toJson() => {
    'index': index,
    'persons': [for (final p in persons) p.toJson()],
  };

  factory PoseFrame.fromJson(Map<String, dynamic> json) => PoseFrame(
    index: (json['index'] as num).toInt(),
    persons: [
      for (final p in (json['persons'] as List? ?? const []))
        Person.fromJson(p as Map<String, dynamic>),
    ],
  );
}

/// One rep's two extremes, measured before any verdict.
class Measurement {
  const Measurement({
    required this.hangDegrees,
    required this.peakDegrees,
    required this.clearance,
  });

  final double hangDegrees;
  final double peakDegrees;
  final double clearance;
}

/// The verdict for one rep: full range or partial, with the numbers behind it.
class Grade {
  const Grade({
    required this.complete,
    required this.hangDegrees,
    required this.peakDegrees,
    required this.clearance,
    required this.bottomOk,
    required this.topOk,
    required this.hangRequired,
    required this.clearanceRequired,
  });

  final bool complete;
  final double hangDegrees;
  final double peakDegrees;
  final double clearance;
  final bool bottomOk;
  final bool topOk;
  final double hangRequired;
  final double clearanceRequired;

  String get reason {
    if (bottomOk && topOk) return 'full range';
    if (!bottomOk && topOk) return 'no full hang at the bottom';
    if (bottomOk && !topOk) return 'head did not clear the bar';
    return 'short at both ends';
  }
}

/// One valley-to-peak-to-valley cycle.
class Rep {
  Rep({
    required this.number,
    required this.valleyFrame,
    required this.peakFrame,
    required this.endFrame,
    required this.valleyTime,
    required this.peakTime,
    required this.endTime,
    required this.ascentSeconds,
    required this.descentSeconds,
    required this.totalSeconds,
    required this.height,
    required this.onsetTime,
    required this.onsetFrame,
    required this.movingSeconds,
    this.rom,
  });

  final int number;
  final int valleyFrame;
  final int peakFrame;
  final int endFrame;
  final double valleyTime;
  final double peakTime;
  final double endTime;
  final double ascentSeconds;
  final double descentSeconds;
  final double totalSeconds;
  final double height;
  final double onsetTime;
  final int onsetFrame;

  /// Onset to peak: the ascent minus any dead hang at the bottom.
  final double movingSeconds;

  /// A [Measurement] before grading, a [Grade] after, or null.
  Object? rom;

  bool get complete => rom is! Grade || (rom as Grade).complete;
  Grade? get grade => rom is Grade ? rom as Grade : null;

  Map<String, dynamic> toJson() => {
    'number': number,
    'valley_time': valleyTime,
    'peak_time': peakTime,
    'end_time': endTime,
    'ascent_seconds': ascentSeconds,
    'moving_seconds': movingSeconds,
    'onset_time': onsetTime,
    'descent_seconds': descentSeconds,
    'total_seconds': totalSeconds,
    'height': height,
    'frames': {
      'valley': valleyFrame,
      'onset': onsetFrame,
      'peak': peakFrame,
      'end': endFrame,
    },
    'rom': grade == null
        ? null
        : {
            'complete': grade!.complete,
            'hang_degrees': grade!.hangDegrees,
            'peak_degrees': grade!.peakDegrees,
            'clearance_torso_lengths': grade!.clearance,
            'hang_required_degrees': grade!.hangRequired,
            'clearance_required': grade!.clearanceRequired,
            'bottom_ok': grade!.bottomOk,
            'top_ok': grade!.topOk,
            'reason': grade!.reason,
          },
  };
}

/// What the analysis produced for a whole clip.
class Analysis {
  Analysis({
    required this.indices,
    required this.times,
    required this.displacement,
    required this.headMargin,
    required this.elbow,
    required this.leftElbow,
    required this.rightElbow,
    required this.clearance,
    required this.baseline,
    required this.amplitude,
    required this.reps,
    required this.countsBySourceFrame,
    required this.onBar,
    required this.hangRequired,
    required this.clearanceRequired,
    required this.calibrated,
  });

  final List<int> indices;
  final List<double> times;
  final List<double> displacement;
  final List<double> headMargin;
  final List<double> elbow;
  final List<double> leftElbow;
  final List<double> rightElbow;
  final List<double> clearance;
  final double baseline;
  final double amplitude;
  final List<Rep> reps;
  final List<int> countsBySourceFrame;
  final List<bool> onBar;
  final double hangRequired;
  final double clearanceRequired;
  final bool calibrated;

  int get count => reps.length;

  /// `(full-range reps, graded reps)`.
  (int, int) get romTally {
    final graded = reps.where((r) => r.grade != null).toList();
    return (graded.where((r) => r.grade!.complete).length, graded.length);
  }

  int get offBarFrames => onBar.where((v) => !v).length;

  int countAt(int frame) {
    if (frame < 0) return 0;
    if (frame >= countsBySourceFrame.length) return count;
    return countsBySourceFrame[frame];
  }

  double get meanPull {
    final graded = reps.where((r) => r.grade == null || r.grade!.complete);
    final source = graded.isEmpty ? reps : graded;
    if (source.isEmpty) return double.nan;
    return source.map((r) => r.movingSeconds).reduce((a, b) => a + b) /
        source.length;
  }

  double get meanElbowAtPeak {
    final values = reps
        .map((r) => r.grade?.peakDegrees ?? double.nan)
        .where((v) => v.isFinite)
        .toList();
    if (values.isEmpty) return double.nan;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Map<String, dynamic> summary() {
    if (reps.isEmpty) return {'reps': 0};
    final (full, graded) = romTally;
    final totals = reps.map((r) => r.totalSeconds).toList();
    double mean(Iterable<double> v) =>
        v.isEmpty ? double.nan : v.reduce((a, b) => a + b) / v.length;
    return {
      'reps': reps.length,
      'full_rom_reps': full,
      'graded_reps': graded,
      'calibrated': calibrated,
      'hang_required_degrees': hangRequired.isFinite ? hangRequired : null,
      'clearance_required': clearanceRequired.isFinite
          ? clearanceRequired
          : null,
      'baseline_signal': baseline,
      'peak_displacement': amplitude,
      'mean_ascent_seconds': mean(reps.map((r) => r.ascentSeconds)),
      'mean_descent_seconds': mean(reps.map((r) => r.descentSeconds)),
      'mean_rep_seconds': mean(totals),
      'fastest_rep_seconds': totals.reduce((a, b) => a < b ? a : b),
      'slowest_rep_seconds': totals.reduce((a, b) => a > b ? a : b),
      'reps_detail': [for (final r in reps) r.toJson()],
    };
  }

  Map<String, dynamic> toJson() => {
    'summary': summary(),
    'signal': {
      'indices': indices,
      'times': times,
      'displacement': displacement,
      'head_margin': headMargin,
      'elbow_degrees': elbow,
      'left_elbow_degrees': leftElbow,
      'right_elbow_degrees': rightElbow,
      'clearance_torso_lengths': clearance,
      'on_bar': onBar,
      'baseline': baseline,
      'amplitude': amplitude,
      'hang_required_degrees': hangRequired,
      'clearance_required': clearanceRequired,
    },
    'reps': [for (final r in reps) r.toJson()],
  };
}
