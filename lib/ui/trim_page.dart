/// Pick the part of the clip to analyse, then hand it to the pipeline.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/config.dart';
import '../core/prefs.dart';
import '../core/store.dart';
import '../core/video_toolkit.dart';
import 'analyzing_page.dart';
import 'format.dart';
import 'theme.dart';

class TrimPage extends StatefulWidget {
  const TrimPage({
    super.key,
    required this.path,
    required this.info,
    required this.mode,
    required this.prefs,
    required this.store,
  });

  final String path;
  final VideoInfo info;
  final LiftMode mode;
  final Prefs prefs;
  final RunStore store;

  @override
  State<TrimPage> createState() => _TrimPageState();
}

class _TrimPageState extends State<TrimPage> {
  late final VideoPlayerController _controller;
  late RangeValues _range;
  bool _ready = false;
  bool _seeking = false;
  String? _error;

  double get _duration => widget.info.durationSeconds;

  /// The gateway's anonymous tier accepts 900 frames at 30 fps.
  double get _maxSpan =>
      _duration < PipelineConfig.maxClipSeconds
          ? _duration
          : PipelineConfig.maxClipSeconds;

  @override
  void initState() {
    super.initState();
    final initialEnd =
        _duration < PipelineConfig.maxClipSeconds ? _duration : _maxSpan;
    _range = RangeValues(0, initialEnd < 0.6 ? _duration : initialEnd);
    _controller = VideoPlayerController.file(File(widget.path));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          _controller
            ..setLooping(false)
            ..setVolume(0)
            ..addListener(_onTick);
          setState(() => _ready = true);
          _controller.seekTo(_startOf(_range));
          _controller.play();
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = friendlyError(error));
        });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  Duration _startOf(RangeValues r) =>
      Duration(milliseconds: (r.start * 1000).round());

  Duration _endOf(RangeValues r) =>
      Duration(milliseconds: (r.end * 1000).round());

  /// Keep the preview inside the chosen window.
  void _onTick() {
    if (!_ready || _seeking) return;
    final position = _controller.value.position.inMilliseconds / 1000.0;
    if (position > _range.end + 0.05) {
      _seeking = true;
      _controller.seekTo(_startOf(_range)).whenComplete(() {
        _seeking = false;
      });
    }
  }

  void _onRangeChanged(RangeValues next) {
    var start = next.start.clamp(0.0, _duration);
    var end = next.end.clamp(0.0, _duration);
    if (end - start > _maxSpan) {
      // Move whichever handle the user just moved.
      if ((next.start - _range.start).abs() > 0.001) {
        start = end - _maxSpan;
      } else {
        end = start + _maxSpan;
      }
    }
    if (end - start < 0.6) {
      if ((next.start - _range.start).abs() > 0.001) {
        start = (end - 0.6).clamp(0.0, _duration);
      } else {
        end = (start + 0.6).clamp(0.0, _duration);
      }
    }
    start = start.clamp(0.0, _duration);
    end = end.clamp(0.0, _duration);
    setState(() => _range = RangeValues(start, end));
    _controller.seekTo(_startOf(_range));
    if (!_controller.value.isPlaying) _controller.play();
  }

  void _analyze() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AnalyzingPage(
          path: widget.path,
          startMs: (_range.start * 1000).round(),
          endMs: (_range.end * 1000).round(),
          mode: widget.mode,
          prefs: widget.prefs,
          store: widget.store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trim the clip')),
      body: SafeArea(
        child: _error != null
            ? _errorBody()
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _preview(),
                  const SizedBox(height: 18),
                  if (_duration > PipelineConfig.maxClipSeconds)
                    _limitNote(),
                  _rangePanel(),
                  const SizedBox(height: 16),
                  _modeNote(),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _ready ? _analyze : null,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Analyse this set'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The clip is resized to 720p and 30 fps on the phone, then '
                    'only that small copy is sent for pose estimation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _preview() {
    final aspect = _ready && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : (widget.info.displayAspect > 0 ? widget.info.displayAspect : 9 / 16);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready)
                VideoPlayer(_controller)
              else if (_error == null)
                const Center(child: CircularProgressIndicator()),
              Positioned(
                left: 10,
                top: 10,
                child: _badge(widget.mode.label),
              ),
              if (_ready)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (_, value, _) => _badge(
                      _clock(value.position),
                      mono: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, {bool mono = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: kText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
      ),
    ),
  );

  Widget _limitNote() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: kWarn.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kWarn.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.content_cut_rounded, size: 15, color: kWarn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This clip is ${widget.info.durationSeconds.toStringAsFixed(1)} s. '
            'Keep ${PipelineConfig.maxClipSeconds.round()} s or less so it fits '
            'the free tier.',
            style: const TextStyle(color: kWarn, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _rangePanel() {
    final selected = _range.end - _range.start;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 17, color: kAccent),
              const SizedBox(width: 8),
              const Text(
                'Which part to count',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Text(
                '${selected.toStringAsFixed(1)} s',
                style: const TextStyle(
                  color: kAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 9,
              ),
              trackHeight: 5,
            ),
            child: RangeSlider(
              min: 0,
              max: _duration,
              values: _range,
              labels: RangeLabels(
                _clock(_startOf(_range)),
                _clock(_endOf(_range)),
              ),
              divisions: (_duration * 2).round().clamp(2, 1200),
              onChanged: _ready ? _onRangeChanged : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _clock(_startOf(_range)),
                style: const TextStyle(
                  color: kMuted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${_clock(_endOf(_range))}  ·  of ${_clock(Duration(seconds: _duration.round()))}',
                style: const TextStyle(
                  color: kMuted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeNote() {
    final text = widget.mode == LiftMode.pullUp
        ? 'Every pull counts. A rep is full range when the arms straighten at '
              'the bottom and the head clears the bar at the top.'
        : 'Only reps where the eyes rise above the bar are counted. Range of '
              'motion is not graded in this mode.';
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            widget.mode == LiftMode.pullUp
                ? Icons.sports_gymnastics
                : Icons.front_hand_rounded,
            size: 18,
            color: kAccentDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: kMuted, fontSize: 12.2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, size: 40, color: kBad),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Choose another clip'),
          ),
        ],
      ),
    ),
  );

  static String _clock(Duration d) {
    final total = d.inMilliseconds / 1000.0;
    final minutes = (total ~/ 60);
    final seconds = total - minutes * 60;
    final padded = seconds.toStringAsFixed(1).padLeft(4, '0');
    return '$minutes:$padded';
  }
}
