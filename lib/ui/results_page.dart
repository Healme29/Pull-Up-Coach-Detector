/// What the set added up to: the count, the range verdicts, the trace, and a
/// way back into the clip with the skeleton on top.
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'format.dart';
import 'replay_page.dart';
import 'theme.dart';
import 'widgets/displacement_chart.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, required this.run});

  final RunData run;

  @override
  Widget build(BuildContext context) {
    final analysis = run.analysis;
    final meta = run.meta;
    final (full, graded) = analysis.romTally;

    return Scaffold(
      appBar: AppBar(
        title: Text('${meta.mode.label} result'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                meta.anonymous ? 'Free tier' : 'Your key',
                style: const TextStyle(color: kMuted, fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            _hero(analysis, full, graded),
            const SizedBox(height: 12),
            _stats(analysis, run),
            if (analysis.count == 0) ...[
              const SizedBox(height: 14),
              _noReps(),
            ],
            const SizedBox(height: 14),
            _chartCard(analysis),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ReplayPage(run: run)),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: const Text('Watch with skeleton'),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Rep by rep'),
            if (analysis.count == 0)
              const Panel(
                child: Text(
                  'Nothing to list.',
                  style: TextStyle(color: kMuted),
                ),
              )
            else
              _repTable(context, analysis),
            if (analysis.offBarFrames > 0) ...[
              const SizedBox(height: 14),
              _offBarNote(analysis, meta.fps),
            ],
            const SizedBox(height: 22),
            _footnote(meta),
          ],
        ),
      ),
    );
  }

  Widget _hero(Analysis analysis, int full, int graded) {
    final complete = analysis.count == 0
        ? kMuted
        : full == graded
            ? kGood
            : kWarn;
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${analysis.count}',
                style: TextStyle(
                  fontSize: 62,
                  height: 0.95,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  color: complete,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  analysis.count == 1 ? 'rep' : 'reps',
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (graded > 0)
                _badge(
                  '$full/$graded full',
                  full == graded ? kGood : kWarn,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _summaryLine(analysis, full, graded),
            style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _summaryLine(Analysis analysis, int full, int graded) {
    if (analysis.count == 0) {
      return 'No complete pull reached the threshold. Check the clip covers '
          'the whole body and the bar.';
    }
    if (graded == 0) {
      return 'Chin-up mode: each rep counted only once the chin cleared the '
          'bar. Range of motion is not graded here.';
    }
    if (full == graded) {
      return 'Every counted rep reached a full hang and cleared the bar at the '
          'top.';
    }
    if (full == 0) {
      return 'Each rep was counted, but none reached both a full hang and a '
          'head over the bar.';
    }
    return '${graded - full} of $graded reps came up short at one end. The '
        'numbers below show which.';
  }

  Widget _stats(Analysis analysis, RunData run) {
    final meanPull = analysis.meanPull;
    final items = <Widget>[
      _stat(
        'Mean pull',
        fmtSeconds(meanPull),
        'onset to top',
        kAccent,
      ),
      _stat(
        'Fastest',
        _fastest(analysis),
        'whole rep',
        kGood,
      ),
      _stat(
        'Clip',
        '${run.meta.clipSeconds.toStringAsFixed(1)} s',
        '${run.meta.frames} frames',
        kMuted,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 9),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  String _fastest(Analysis analysis) {
    if (analysis.reps.isEmpty) return '—';
    final values = analysis.reps.map((r) => r.totalSeconds);
    return fmtSeconds(values.reduce((a, b) => a < b ? a : b));
  }

  Widget _stat(String label, String value, String sub, Color color) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kMuted, fontSize: 10.5),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: const TextStyle(color: kMuted, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _chartCard(Analysis analysis) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Body rise through the set',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const Spacer(),
            _legend(kAccent, 'rise'),
            const SizedBox(width: 10),
            _legend(kWarn, 'threshold'),
          ],
        ),
        const SizedBox(height: 4),
        DisplacementChart(analysis: analysis),
        Text(
          'Each marker is a counted rep. Height is relative to the deepest '
          'hang in this clip.',
          style: const TextStyle(color: kMuted, fontSize: 11, height: 1.4),
        ),
      ],
    ),
  );

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 2.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(color: kMuted, fontSize: 10),
      ),
    ],
  );

  Widget _repTable(BuildContext context, Analysis analysis) {
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < analysis.reps.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _repRow(context, analysis.reps[i]),
          ],
        ],
      ),
    );
  }

  Widget _repRow(BuildContext context, Rep rep) {
    final grade = rep.grade;
    final color = grade == null
        ? kMuted
        : grade.complete
            ? kGood
            : kBad;
    final detail = grade == null
        ? 'hang to top · ${fmtSeconds(rep.movingSeconds)} pull'
        : 'hang ${fmtDegrees(grade.hangDegrees)} (need '
            '${fmtDegrees(grade.hangRequired)}) · top '
            '${fmtTorso(grade.clearance)} (need '
            '${fmtTorso(grade.clearanceRequired)})';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${rep.number}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtSeconds(rep.movingSeconds)} pull · '
                  '${fmtSeconds(rep.totalSeconds, decimals: 1)} rep',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                if (grade != null && !grade.complete) ...[
                  const SizedBox(height: 4),
                  Text(
                    grade.reason,
                    style: const TextStyle(
                      color: kBad,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _badge(
              grade == null
                  ? 'counted'
                  : grade.complete
                      ? 'full ROM'
                      : 'partial',
              color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _noReps() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kWarn.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kWarn.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 17, color: kWarn),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'For a count, the camera needs to see you rise from a hang to the '
            'top. Film side-on with the feet and hands in frame.',
            style: const TextStyle(color: kWarn, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _offBarNote(Analysis analysis, double fps) {
    final seconds = analysis.offBarFrames / (fps <= 0 ? 30 : fps);
    return Text(
      'Hands left the bar for ${analysis.offBarFrames} frames '
      '(${seconds.toStringAsFixed(1)} s). Those frames were ignored so the '
      'count is not thrown off.',
      style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
    );
  }

  Widget _footnote(RunMeta meta) => Text(
    '${meta.anonymous ? 'Anonymous run' : 'Personal key'} · '
    '${fmtBytes(meta.uploadBytes)} uploaded · '
    '${meta.gatewaySeconds.toStringAsFixed(0)} s on the gateway. '
    'The clip and poses stay on this phone.',
    textAlign: TextAlign.center,
    style: const TextStyle(color: kMuted, fontSize: 10.5, height: 1.5),
  );
}
