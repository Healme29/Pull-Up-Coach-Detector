/// Vertical displacement, rep counting, and per-rep range of motion.
///
/// Port of `pull_ups/src/reps.py`. Counting and grading are separate: every
/// pull is counted, short ones included, then graded full or partial in
/// `rom.dart`.
library;

import 'dart:math' as math;

import 'config.dart';
import 'mathx.dart';
import 'models.dart';
import 'pose.dart';
import 'rom.dart';

class RepAnalyzer {
  RepAnalyzer._();

  /// Build the displacement signal, count reps off it, and grade each one.
  ///
  /// [aspect] is width / height, which undoes the per-axis normalization for
  /// elbow angles. There is no calibration profile on the phone, so the clip is
  /// graded against its own deepest hang, exactly like the web app's tab.
  static Analysis analyze({
    required List<PoseFrame> frames,
    required double fps,
    required int nSourceFrames,
    required AnalysisConfig cfg,
    double aspect = 1.0,
  }) {
    final indices = [for (final f in frames) f.index];
    final times = [for (final i in indices) i / fps];

    final torso = fillGaps(_jointY(frames, cfg.torsoJoints));
    final hands = fillGaps(_jointY(frames, cfg.handJoints));
    final head = fillGaps(
      _weightedY(frames, cfg.headJoints, cfg.headMinScore),
    );

    // Body height relative to the hands on the bar, falling back to screen
    // position if the wrists were never found.
    var onBar = List<bool>.filled(torso.length, true);
    List<double> raw;
    if (cfg.referenceToHands && hands.any(isFinite)) {
      raw = [for (var i = 0; i < hands.length; i++) hands[i] - torso[i]];
      final bar = median(hands);
      // Hands off the bar break the fixed-point assumption and spike the
      // signal, so those frames are excluded.
      onBar = [
        for (final h in hands) (h - bar).abs() <= cfg.handOffBarTolerance,
      ];
    } else {
      raw = [for (final t in torso) -t];
    }

    final smooth = boxFilter(
      medianFilter(raw, cfg.smoothMedianFrames),
      cfg.smoothMeanFrames,
    );

    // Relative zero is the hanging plateau, a low percentile rather than the
    // minimum, so one bad frame cannot define it.
    final usable = onBar.contains(true)
        ? [
            for (var i = 0; i < smooth.length; i++)
              if (onBar[i]) smooth[i],
          ]
        : smooth;
    final baseline = percentile(usable, cfg.baselinePercentile);
    final displacement = [for (final v in smooth) v - baseline];
    final amplitude = _robustAmplitude(displacement, onBar);

    // Positive when the head is above the hands, the head-over-bar criterion.
    final headMargin = [
      for (var i = 0; i < hands.length; i++) hands[i] - head[i],
    ];

    final arms = armAngles(frames, aspect, cfg.armJoints);
    final elbow = elbowAngles(arms);
    final torsoSpan = torsoLengths(frames, cfg.torsoJoints, cfg.headJoints);
    final clearance = [
      for (var i = 0; i < headMargin.length; i++)
        isFinite(torsoSpan[i]) && torsoSpan[i] > 0
            ? headMargin[i] / torsoSpan[i]
            : nan,
    ];

    final grader = cfg.gradeRom
        ? Grader(elbow: elbow, clearance: clearance, cfg: cfg)
        : null;

    final reps = _count(
      displacement: displacement,
      headMargin: headMargin,
      times: times,
      indices: indices,
      amplitude: amplitude,
      onBar: onBar,
      cfg: cfg,
      grader: grader,
    );
    // Graded only now: the bottom is judged against the deepest hang in the
    // set, so no rep can be called short until every rep has been measured.
    final hangRequired = grader?.grade(reps) ?? nan;
    final clearanceRequired = grader?.minClearance ?? nan;

    final counts = List<int>.filled(math.max(nSourceFrames, 1), 0);
    for (final rep in reps) {
      if (rep.peakFrame < counts.length) {
        for (var i = rep.peakFrame; i < counts.length; i++) {
          counts[i] = rep.number;
        }
      }
    }

    return Analysis(
      indices: indices,
      times: times,
      displacement: displacement,
      headMargin: headMargin,
      elbow: elbow,
      leftElbow: arms.isNotEmpty ? arms[0] : const [],
      rightElbow: arms.length > 1 ? arms[1] : const [],
      clearance: clearance,
      baseline: baseline,
      amplitude: amplitude,
      reps: reps,
      countsBySourceFrame: counts,
      onBar: onBar,
      hangRequired: hangRequired,
      clearanceRequired: clearanceRequired,
      calibrated: false,
    );
  }

  /// Mean y of the named joints on the first tracked person, per frame.
  /// `(0, 0)` is the model's "not visible" sentinel and is excluded.
  static List<double> _jointY(List<PoseFrame> frames, List<String> names) {
    final out = List<double>.filled(frames.length, nan);
    for (var i = 0; i < frames.length; i++) {
      final persons = frames[i].persons;
      if (persons.isEmpty) continue;
      final kpts = persons.first.kpts;
      final values = <double>[];
      for (final name in names) {
        final idx = kptIndex[name];
        if (idx == null || idx >= kpts.length) continue;
        if (!kpts[idx].unseen) values.add(kpts[idx].y);
      }
      if (values.isNotEmpty) out[i] = mean(values);
    }
    return out;
  }

  /// Confidence-weighted mean y of the named joints, per frame. For the head:
  /// whichever points the model sees (ears from behind, face from the front)
  /// carry it.
  static List<double> _weightedY(
      List<PoseFrame> frames, List<String> names, double minScore) {
    final out = List<double>.filled(frames.length, nan);
    for (var i = 0; i < frames.length; i++) {
      final persons = frames[i].persons;
      if (persons.isEmpty) continue;
      final person = persons.first;
      final kpts = person.kpts;
      final scores = person.scores.isEmpty
          ? List<double>.filled(kpts.length, 1.0)
          : person.scores;
      var weighted = 0.0;
      var total = 0.0;
      for (final name in names) {
        final j = kptIndex[name];
        if (j == null || j >= kpts.length) continue;
        if (kpts[j].unseen) continue;
        final score = j < scores.length ? scores[j] : 1.0;
        if (score < minScore) continue;
        weighted += kpts[j].y * score;
        total += score;
      }
      if (total > 0) out[i] = weighted / total;
    }
    return out;
  }

  /// Where the pull begins: the foot of the rise, not the lowest point.
  static int _onsetIndex(
    List<double> displacement,
    int valley,
    int peak, {
    required double amplitude,
    required AnalysisConfig cfg,
  }) {
    if (peak <= valley) return valley;

    if (cfg.repOnsetMethod == 'threshold') {
      for (var i = valley; i <= peak; i++) {
        if (displacement[i] > displacement[valley] + cfg.repOnsetFraction * amplitude) {
          return i;
        }
      }
      return valley;
    }

    final segment = displacement.sublist(valley, peak + 1);
    if (segment.length < 3) return valley;
    final velocity = gradient(segment);
    var fastest = 0;
    for (var i = 1; i < velocity.length; i++) {
      if (velocity[i] > velocity[fastest]) fastest = i;
    }
    if (velocity[fastest] <= 0) return valley;

    final floor = cfg.repOnsetVelocityFraction * velocity[fastest];
    var i = fastest;
    while (i > 0 && velocity[i] > floor) {
      i--;
    }
    return valley + i;
  }

  /// Typical rep height, as the median of the peaks rather than the max, so one
  /// bad pose cannot move every threshold downstream.
  static double _robustAmplitude(List<double> displacement, List<bool> valid) {
    final usable = [
      for (var i = 0; i < displacement.length; i++)
        if (valid[i]) displacement[i],
    ];
    if (usable.isEmpty) return 0;
    final top = usable.reduce(math.max);
    if (top <= 0) return 0;

    final peaks = <double>[];
    for (var i = 1; i < displacement.length - 1; i++) {
      if (valid[i] &&
          displacement[i] >= displacement[i - 1] &&
          displacement[i] > displacement[i + 1] &&
          displacement[i] > 0.3 * top) {
        peaks.add(displacement[i]);
      }
    }
    if (peaks.length >= 3) return median(peaks);
    return percentile(usable, 95);
  }

  /// Hysteresis state machine: valley arms, peak confirms, return to baseline
  /// closes.
  static List<Rep> _count({
    required List<double> displacement,
    required List<double> headMargin,
    required List<double> times,
    required List<int> indices,
    required double amplitude,
    required List<bool> onBar,
    required AnalysisConfig cfg,
    Grader? grader,
  }) {
    if (amplitude <= 0 || displacement.length < 3) return [];

    final low = cfg.repResetFraction * amplitude;
    final high = cfg.repPeakFraction * amplitude;

    bool confirms(int i, double d) => d > high;

    final reps = <Rep>[];
    var state = 'down';
    var valley = 0;
    var peak = 0;
    var peakValue = double.negativeInfinity;
    var lastOnBar = 0;

    void close(int endIndex) {
      reps.add(
        _makeRep(
          number: reps.length + 1,
          valleyIndex: valley,
          peakIndex: peak,
          endIndex: endIndex,
          times: times,
          indices: indices,
          displacement: displacement,
          onsetIndex: _onsetIndex(
            displacement,
            valley,
            peak,
            amplitude: amplitude,
            cfg: cfg,
          ),
          rom: grader?.measure(valley, peak),
        ),
      );
    }

    for (var i = 0; i < displacement.length; i++) {
      if (!onBar[i]) continue; // hands off the bar: this frame says nothing
      lastOnBar = i;
      final gate = !cfg.requireHeadAboveHands || headMargin[i] > 0;
      if (state == 'down') {
        if (displacement[i] < displacement[valley]) valley = i;
        if (gate && confirms(i, displacement[i])) {
          state = 'up';
          peak = i;
          peakValue = displacement[i];
        }
      } else {
        if (displacement[i] > peakValue) {
          peak = i;
          peakValue = displacement[i];
        }
        if (displacement[i] < low) {
          close(i);
          state = 'down';
          valley = i;
        }
      }
    }

    if (state == 'up') {
      // Clip ended mid-rep: close on the last on-bar frame, not the clip's
      // end, so a release is not timed as a descent.
      close(lastOnBar);
    }
    return reps;
  }

  static Rep _makeRep({
    required int number,
    required int valleyIndex,
    required int peakIndex,
    required int endIndex,
    required List<double> times,
    required List<int> indices,
    required List<double> displacement,
    required int onsetIndex,
    Object? rom,
  }) {
    return Rep(
      number: number,
      valleyFrame: indices[valleyIndex],
      peakFrame: indices[peakIndex],
      endFrame: indices[endIndex],
      valleyTime: times[valleyIndex],
      peakTime: times[peakIndex],
      endTime: times[endIndex],
      ascentSeconds: times[peakIndex] - times[valleyIndex],
      descentSeconds: times[endIndex] - times[peakIndex],
      totalSeconds: times[endIndex] - times[valleyIndex],
      height: displacement[peakIndex],
      onsetTime: times[onsetIndex],
      onsetFrame: indices[onsetIndex],
      movingSeconds: times[peakIndex] - times[onsetIndex],
      rom: rom,
    );
  }
}
