import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pullup_app/core/config.dart';
import 'package:pullup_app/core/models.dart';
import 'package:pullup_app/core/pose.dart';
import 'package:pullup_app/core/signal.dart';

/// Proves the Dart port agrees with the Python pipeline on every synthetic
/// clip `tools/gen_fixtures.py` produced: same reps, same times, same grades,
/// same per-frame series.
void main() {
  final dir = Directory('test/fixtures');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures exist', () {
    expect(files, isNotEmpty,
        reason: 'run `python tools/gen_fixtures.py` first');
  });

  for (final file in files) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final name = fixture['name'] as String;

    test('golden: $name', () {
      final mode = fixture['mode'] == 'chinUp' ? LiftMode.chinUp : LiftMode.pullUp;
      final cfg = AnalysisConfig.forMode(mode);
      final pixels = (fixture['aspect'] as num).toDouble();
      final fps = (fixture['fps'] as num).toDouble();
      final nSource = (fixture['n_source_frames'] as num).toInt();
      final frames = [
        for (final f in fixture['frames'] as List)
          PoseFrame.fromJson(Map<String, dynamic>.from(f as Map)),
      ];

      final analysis = RepAnalyzer.analyze(
        frames: frames,
        fps: fps,
        nSourceFrames: nSource,
        cfg: cfg,
        aspect: pixels,
      );
      final expected = fixture['expected'] as Map<String, dynamic>;

      void close(num? actual, num? want, String label) {
        final a = (actual ?? double.nan).toDouble();
        final w = (want ?? double.nan).toDouble();
        if (w.isNaN) {
          expect(a.isNaN, isTrue, reason: '$label should be NaN, got $a');
          return;
        }
        expect(a.isFinite, isTrue, reason: '$label should be finite, got $a');
        final tolerance = 1e-6 * (w.abs() > 1 ? w.abs() : 1.0);
        expect((a - w).abs() <= tolerance, isTrue,
            reason: '$label: got $a, want $w (tolerance $tolerance)');
      }

      void series(List<double> actual, List<dynamic> want, String label) {
        expect(actual.length, want.length, reason: '$label length');
        for (var i = 0; i < want.length; i++) {
          close(actual[i], want[i] as num?, '$label[$i]');
        }
      }

      close(analysis.baseline, expected['baseline'] as num?, 'baseline');
      close(analysis.amplitude, expected['amplitude'] as num?, 'amplitude');
      close(analysis.hangRequired, expected['hang_required'] as num?,
          'hang_required');
      close(analysis.clearanceRequired, expected['clearance_required'] as num?,
          'clearance_required');

      expect(analysis.indices, [for (final v in expected['indices']) v as int]);
      series(analysis.times, expected['times'] as List, 'times');
      series(analysis.displacement, expected['displacement'] as List,
          'displacement');
      series(analysis.headMargin, expected['head_margin'] as List, 'head_margin');
      series(analysis.elbow, expected['elbow'] as List, 'elbow');
      series(analysis.clearance, expected['clearance'] as List, 'clearance');
      expect(analysis.onBar, [for (final v in expected['on_bar']) v as bool]);
      expect(analysis.countsBySourceFrame,
          [for (final v in expected['counts']) v as int]);

      final wantReps = expected['reps'] as List;
      expect(analysis.reps.length, wantReps.length,
          reason: 'rep count ${analysis.reps.map((r) => r.number)}');
      for (var i = 0; i < wantReps.length; i++) {
        final rep = analysis.reps[i];
        final want = wantReps[i] as Map<String, dynamic>;
        final tag = 'rep ${i + 1}';
        expect(rep.number, want['number']);
        expect(rep.valleyFrame, want['valley_frame'], reason: '$tag valley');
        expect(rep.onsetFrame, want['onset_frame'], reason: '$tag onset');
        expect(rep.peakFrame, want['peak_frame'], reason: '$tag peak');
        expect(rep.endFrame, want['end_frame'], reason: '$tag end');
        close(rep.valleyTime, want['valley_time'] as num?, '$tag valley_time');
        close(rep.onsetTime, want['onset_time'] as num?, '$tag onset_time');
        close(rep.peakTime, want['peak_time'] as num?, '$tag peak_time');
        close(rep.endTime, want['end_time'] as num?, '$tag end_time');
        close(rep.ascentSeconds, want['ascent_seconds'] as num?, '$tag ascent');
        close(rep.movingSeconds, want['moving_seconds'] as num?, '$tag moving');
        close(rep.descentSeconds, want['descent_seconds'] as num?,
            '$tag descent');
        close(rep.totalSeconds, want['total_seconds'] as num?, '$tag total');
        close(rep.height, want['height'] as num?, '$tag height');

        final wantRom = want['rom'] as Map<String, dynamic>?;
        if (wantRom == null) {
          expect(rep.grade, isNull, reason: '$tag should be ungraded');
          continue;
        }
        final grade = rep.grade;
        expect(grade, isNotNull, reason: '$tag should be graded');
        expect(grade!.complete, wantRom['complete'], reason: '$tag complete');
        expect(grade.bottomOk, wantRom['bottom_ok'], reason: '$tag bottom_ok');
        expect(grade.topOk, wantRom['top_ok'], reason: '$tag top_ok');
        close(grade.hangDegrees, wantRom['hang_degrees'] as num?,
            '$tag hang');
        close(grade.peakDegrees, wantRom['peak_degrees'] as num?,
            '$tag peak');
        close(grade.clearance, wantRom['clearance'] as num?, '$tag clearance');
        close(grade.hangRequired, wantRom['hang_required'] as num?,
            '$tag hang_required');
        close(grade.clearanceRequired, wantRom['clearance_required'] as num?,
            '$tag clearance_required');
      }
    });
  }

  test('parsePoseReply groups frames and drops duplicate boxes', () {
    final reply = parsePoseReply({
      'content': {
        'object': 'vid.pose.kpts',
        'kpts_labels': kptNames,
        'frames': [
          {'frame_id': 0},
          {'frame_id': 1},
          {'frame_id': 2},
        ],
        'items': [
          {
            'frame_id': 0,
            'track_id': 0,
            'kpts_xy': [
              for (var i = 0; i < 17; i++) [0.5, 0.5],
            ],
            'kpts_score': [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9,
              0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9],
            'bbox_xywh': [0.2, 0.2, 0.3, 0.5],
          },
          {
            'frame_id': 0,
            'track_id': 1,
            'kpts_xy': [
              for (var i = 0; i < 17; i++) [0.5, 0.5],
            ],
            'kpts_score': [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9,
              0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9],
            'bbox_xywh': [0.2, 0.2, 0.3, 0.5],
          },
        ],
      },
    });
    expect(reply.frames.map((f) => f.index), [0, 1, 2]);
    expect(reply.dropped, 1);
    expect(reply.frames[0].persons, hasLength(1));
    expect(reply.frames[1].persons, isEmpty);
  });

  test('a non-pose envelope is refused', () {
    expect(
      () => parsePoseReply({'content': {'object': 'something.else'}}),
      throwsFormatException,
    );
  });
}
