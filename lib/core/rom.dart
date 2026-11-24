/// Grading each rep's range of motion: full or partial.
///
/// Port of `pull_ups/src/rom.py`. The bottom is judged against the clip's own
/// deepest hang (ViTPose puts the shoulder on the deltoid, so a dead hang reads
/// ~167 degrees, not 180); the top is the head above the hands, in torso
/// lengths, so camera distance cancels out.
library;

import 'dart:math' as math;

import 'config.dart';
import 'mathx.dart';
import 'models.dart';
import 'pose.dart';

math.Point<double>? _point(List<Kpt> kpts, String name, double aspect) {
  final i = kptIndex[name];
  if (i == null || i >= kpts.length) return null;
  final p = kpts[i];
  if (p.unseen) return null;
  // x is scaled by the aspect ratio so angles are not distorted on a
  // non-square frame.
  return math.Point(p.x * aspect, p.y);
}

/// Elbow angle per arm per frame, shape `[arms.length][frames.length]`.
List<List<double>> armAngles(
    List<PoseFrame> frames, double aspect, List<List<String>> arms) {
  final out = [
    for (var a = 0; a < arms.length; a++) List<double>.filled(frames.length, nan),
  ];
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].persons.isEmpty) continue;
    final kpts = frames[i].persons.first.kpts;
    for (var a = 0; a < arms.length; a++) {
      final (shoulder, elbow, wrist) = (
        arms[a][0],
        arms[a][1],
        arms[a][2],
      );
      final p0 = _point(kpts, shoulder, aspect);
      final p1 = _point(kpts, elbow, aspect);
      final p2 = _point(kpts, wrist, aspect);
      if (p0 != null && p1 != null && p2 != null) {
        out[a][i] = interiorAngle(p0, p1, p2);
      }
    }
  }
  return out;
}

/// Mean elbow angle per frame across the arms that were seen.
List<double> elbowAngles(List<List<double>> perArm) {
  final n = perArm.isEmpty ? 0 : perArm.first.length;
  final out = List<double>.filled(n, nan);
  for (var i = 0; i < n; i++) {
    var total = 0.0;
    var count = 0;
    for (final arm in perArm) {
      if (isFinite(arm[i])) {
        total += arm[i];
        count++;
      }
    }
    out[i] = count > 0 ? total / count : nan;
  }
  return out;
}

/// Shoulder-to-hip height per frame: the body's own ruler.
List<double> torsoLengths(List<PoseFrame> frames, List<String> torsoJoints,
    List<String> headJoints) {
  var shoulders = torsoJoints.where((j) => j.contains('shoulder')).toList();
  var hips = torsoJoints.where((j) => j.contains('hip')).toList();
  if (shoulders.isEmpty || hips.isEmpty) {
    shoulders = headJoints;
    hips = torsoJoints.where((j) => j.contains('shoulder')).toList();
  }
  final out = List<double>.filled(frames.length, nan);
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].persons.isEmpty) continue;
    final kpts = frames[i].persons.first.kpts;

    double meanY(List<String> names) {
      final values = <double>[];
      for (final name in names) {
        final idx = kptIndex[name];
        if (idx == null || idx >= kpts.length) continue;
        if (!kpts[idx].unseen) values.add(kpts[idx].y);
      }
      return values.isEmpty ? nan : mean(values);
    }

    final span = (meanY(hips) - meanY(shoulders)).abs();
    if (isFinite(span) && span > 1e-4) out[i] = span;
  }
  return out;
}

/// Median of `series` over a window centred on `center`, ignoring NaNs, so one
/// bad pose at a turnaround cannot decide a rep.
double windowMedian(List<double> series, int center, int width) {
  if (series.isEmpty) return nan;
  final half = math.max(0, width ~/ 2);
  final lo = math.max(0, center - half);
  final hi = math.min(series.length, center + half + 1);
  final window = [
    for (var i = lo; i < hi; i++)
      if (isFinite(series[i])) series[i],
  ];
  return window.isEmpty ? nan : median(window);
}

/// Measures each rep during counting, then grades them all together: the
/// bottom is held to the best hang in the whole set.
class Grader {
  Grader({
    required this._elbow,
    required this._clearance,
    required this.cfg,
  }) : hangRequired = cfg.romHangElbowDegrees,
       minClearance = cfg.romClearanceTorsoFraction;

  final List<double> _elbow;
  final List<double> _clearance;
  final AnalysisConfig cfg;
  double hangRequired;
  double minClearance;

  Measurement measure(int valleyIndex, int peakIndex) => Measurement(
    hangDegrees: windowMedian(_elbow, valleyIndex, cfg.romSampleFrames),
    peakDegrees: windowMedian(_elbow, peakIndex, cfg.romSampleFrames),
    clearance: windowMedian(_clearance, peakIndex, cfg.romSampleFrames),
  );

  /// The clip's own straight arm: the deepest hang in it.
  double _reference(List<Measurement> measurements) {
    final hangs = [
      for (final m in measurements)
        if (isFinite(m.hangDegrees)) m.hangDegrees,
    ];
    return hangs.isEmpty ? nan : hangs.reduce(math.max);
  }

  /// Replace every rep's [Measurement] with a [Grade]. Returns the hang cutoff.
  double grade(List<Rep> reps) {
    final measured = [
      for (final r in reps)
        if (r.rom is Measurement) r.rom as Measurement,
    ];
    final best = _reference(measured);
    var required = cfg.romHangElbowDegrees;
    if (isFinite(best)) {
      required = math.max(required, best - cfg.romHangToleranceDegrees);
    }
    hangRequired = required;

    for (final rep in reps) {
      final m = rep.rom;
      if (m is! Measurement) continue;
      // Unreadable is not passing: assuming a dead hang would flatter the athlete.
      final bottomOk = isFinite(m.hangDegrees) && m.hangDegrees >= required;
      final topOk = isFinite(m.clearance) && m.clearance >= minClearance;
      rep.rom = Grade(
        complete: bottomOk && topOk,
        hangDegrees: m.hangDegrees,
        peakDegrees: m.peakDegrees,
        clearance: m.clearance,
        bottomOk: bottomOk,
        topOk: topOk,
        hangRequired: hangRequired,
        clearanceRequired: minClearance,
      );
    }
    return hangRequired;
  }
}
