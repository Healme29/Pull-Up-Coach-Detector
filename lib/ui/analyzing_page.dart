/// The wait: prepare the clip, wait for the gateway, count, save. Cancelling
/// leaves nothing behind.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/config.dart';
import '../core/pipeline.dart';
import '../core/prefs.dart';
import '../core/store.dart';
import 'format.dart';
import 'results_page.dart';
import 'theme.dart';

class AnalyzingPage extends StatefulWidget {
  const AnalyzingPage({
    super.key,
    required this.path,
    required this.startMs,
    required this.endMs,
    required this.mode,
    required this.prefs,
    required this.store,
  });

  final String path;
  final int startMs;
  final int endMs;
  final LiftMode mode;
  final Prefs prefs;
  final RunStore store;

  @override
  State<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends State<AnalyzingPage> {
  late final AnalysisPipeline _pipeline;
  PipelineProgress _progress = const PipelineProgress(
    PipelineStage.preparing,
    0,
    'Starting…',
  );
  Timer? _timer;
  int _elapsed = 0;
  bool _cancelled = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pipeline = AnalysisPipeline(store: widget.store);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    await WakelockPlus.enable();
    try {
      final result = await _pipeline.run(
        inputPath: widget.path,
        startMs: widget.startMs,
        endMs: widget.endMs,
        mode: widget.mode,
        apiKey: widget.prefs.apiKey,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      _stopClock();
      await WakelockPlus.disable();
      _done = true;
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultsPage(run: result.run)),
      );
    } catch (error) {
      _stopClock();
      await WakelockPlus.disable();
      if (!mounted) return;
      if (_cancelled || error is PipelineCancelled) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = friendlyError(error));
    }
  }

  void _stopClock() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _cancel() async {
    if (_cancelled || _done) return;
    setState(() => _cancelled = true);
    _pipeline.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _stopClock();
    _pipeline.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: _error != null ? _errorBody() : _runningBody(),
          ),
        ),
      ),
    );
  }

  Widget _runningBody() => Column(
    children: [
      const Spacer(),
      _pulse(),
      const SizedBox(height: 26),
      Text(
        _progress.message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        widget.mode.label == LiftMode.pullUp.label
            ? 'Pull-up set · ${_clock(_elapsed)} elapsed'
            : 'Chin-up set · ${_clock(_elapsed)} elapsed',
        style: const TextStyle(color: kMuted, fontSize: 12.5),
      ),
      const SizedBox(height: 26),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          minHeight: 6,
          backgroundColor: kLine,
          value: _progress.stage == PipelineStage.preparing
              ? _progress.fraction.clamp(0, 1)
              : _progress.stage == PipelineStage.saving
                  ? _progress.fraction.clamp(0, 1)
                  : null,
        ),
      ),
      const SizedBox(height: 30),
      _stages(),
      const Spacer(),
      if (_progress.stage == PipelineStage.uploading)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            'Pose estimation runs on the gateway. This is the slow part and it '
            'can take a minute.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
          ),
        ),
      TextButton(
        onPressed: _cancelled ? null : _cancel,
        child: Text(_cancelled ? 'Cancelling…' : 'Cancel'),
      ),
    ],
  );

  Widget _pulse() {
    final active = _progress.stage == PipelineStage.preparing;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              backgroundColor: kLine,
              value: active ? _progress.fraction.clamp(0, 1) : null,
            ),
          ),
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kAccent, kAccentDeep],
              ),
            ),
            child: Icon(
              active ? Icons.movie_filter_rounded : Icons.accessibility_new,
              size: 38,
              color: const Color(0xFF04161C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stages() {
    const stages = [
      (PipelineStage.preparing, 'Trim and normalise', Icons.cut_rounded),
      (PipelineStage.uploading, 'Estimate poses', Icons.cloud_upload_rounded),
      (PipelineStage.analyzing, 'Count reps', Icons.show_chart_rounded),
      (PipelineStage.saving, 'Save the run', Icons.save_alt_rounded),
    ];
    final current = stages.indexWhere((s) => s.$1 == _progress.stage);
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: i < current
                      ? const Icon(Icons.check_circle, size: 20, color: kGood)
                      : i == current
                          ? const Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              stages[i].$3,
                              size: 19,
                              color: kLine,
                            ),
                ),
                const SizedBox(width: 12),
                Text(
                  stages[i].$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    color: i <= current ? kText : kMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _errorBody() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kBad.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline_rounded, color: kBad, size: 32),
        ),
        const SizedBox(height: 18),
        const Text(
          'That run did not finish',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kMuted, height: 1.45, fontSize: 13),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _error = null;
              _elapsed = 0;
              _cancelled = false;
              _progress = const PipelineProgress(
                PipelineStage.preparing,
                0,
                'Starting…',
              );
            });
            _start();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
      ],
    ),
  );

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
