/// The clip with its skeleton, played back at whatever speed helps: the live
/// count, the phase, and the elbow angle at that frame.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/pose_overlay.dart';

class ReplayPage extends StatefulWidget {
  const ReplayPage({super.key, required this.run});

  final RunData run;

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier(0);

  VideoPlayerController? _controller;
  Person? Function(int frame) _personAt = (_) => null;
  ValueGetter<double> _elbowAt = () => double.nan;
  ValueGetter<double> _clearanceAt = () => double.nan;

  int _lastFrame = 0;
  double _anchorPos = 0;
  DateTime _anchorWall = DateTime.now();
  double _speed = 1.0;
  bool _ready = false;
  String? _error;

  double get _duration {
    final value = _controller?.value;
    if (value != null && value.isInitialized) {
      return value.duration.inMilliseconds / 1000.0;
    }
    return widget.run.meta.clipSeconds;
  }

  double get _aspect {
    final ratio = _controller?.value.aspectRatio ?? 0;
    if (ratio > 0.01) return ratio;
    final fallback = widget.run.aspect;
    return fallback > 0.01 ? fallback : 9 / 16;
  }

  @override
  void initState() {
    super.initState();
    _indexPoses();
    _ticker = createTicker((_) => _tick())..start();
    _open();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _controller?.removeListener(_syncAnchor);
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _indexPoses() {
    final run = widget.run;
    var maxIndex = -1;
    for (final frame in run.frames) {
      maxIndex = math.max(maxIndex, frame.index);
    }
    _lastFrame = math.max(
      maxIndex,
      math.max(0, run.analysis.countsBySourceFrame.length - 1),
    );

    final dense = List<Person?>.filled(_lastFrame + 1, null);
    for (final frame in run.frames) {
      if (frame.index < 0 || frame.index > _lastFrame) continue;
      if (frame.persons.isNotEmpty) dense[frame.index] = frame.persons.first;
    }
    _personAt = (frame) {
      if (frame < 0) return null;
      if (frame > _lastFrame) frame = _lastFrame;
      for (var i = frame; i >= 0 && i > frame - 4; i--) {
        final person = dense[i];
        if (person != null) return person;
      }
      return null;
    };

    final seriesAt = <int, int>{
      for (var i = 0; i < run.analysis.indices.length; i++)
        run.analysis.indices[i]: i,
    };
    double seriesValue(int frame, List<double> values) {
      final exact = seriesAt[frame];
      if (exact != null && exact < values.length) return values[exact];
      for (var delta = 1; delta <= 3; delta++) {
        final before = seriesAt[frame - delta];
        if (before != null && before < values.length) return values[before];
        final after = seriesAt[frame + delta];
        if (after != null && after < values.length) return values[after];
      }
      return double.nan;
    }

    _elbowAt = () => seriesValue(_frameAt(_clock.value), run.analysis.elbow);
    _clearanceAt = () =>
        seriesValue(_frameAt(_clock.value), run.analysis.clearance);
  }

  Future<void> _open() async {
    final file = File(widget.run.clipPath);
    if (!await file.exists()) {
      if (mounted) {
        setState(() => _error = 'The saved clip is missing from this phone.');
      }
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      controller.addListener(_syncAnchor);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
      _anchorPos = 0;
      _anchorWall = DateTime.now();
      await WakelockPlus.enable();
      await controller.play();
      if (mounted) setState(() {});
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    }
  }

  /// The player only reports a position a couple of times a second. Re-anchor
  /// the estimate on every report so the skeleton stays on the body.
  void _syncAnchor() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    _anchorPos = value.position.inMilliseconds / 1000.0;
    _anchorWall = DateTime.now();
    if (!value.isPlaying && _clock.value != _anchorPos) {
      _clock.value = _anchorPos;
    }
  }

  void _tick() {
    final controller = _controller;
    if (controller == null || !_ready || !controller.value.isPlaying) return;
    final elapsed = DateTime.now().difference(_anchorWall).inMilliseconds /
        1000.0;
    var position = _anchorPos + elapsed * _speed;
    final duration = _duration;
    if (duration > 0 && position >= duration) {
      position = 0;
      _anchorPos = 0;
      _anchorWall = DateTime.now();
    }
    if ((_clock.value - position).abs() > 0.0005) _clock.value = position;
  }

  int _frameAt(double seconds) =>
      (seconds * widget.run.meta.fps).round().clamp(0, _lastFrame);

  Future<void> _seekTo(double seconds) async {
    final controller = _controller;
    if (controller == null) return;
    final target = seconds.clamp(0.0, _duration);
    _anchorPos = target;
    _anchorWall = DateTime.now();
    _clock.value = target;
    await controller.seekTo(
      Duration(milliseconds: (target * 1000).round()),
    );
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      _syncAnchor();
    } else {
      _anchorPos = controller.value.position.inMilliseconds / 1000.0;
      _anchorWall = DateTime.now();
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _cycleSpeed() async {
    final next = _speed == 1.0
        ? 0.5
        : _speed == 0.5
            ? 0.25
            : 1.0;
    final controller = _controller;
    if (controller != null) {
      _anchorPos = controller.value.position.inMilliseconds / 1000.0;
      _anchorWall = DateTime.now();
      await controller.setPlaybackSpeed(next);
    }
    if (mounted) setState(() => _speed = next);
  }

  Rep? _activeRep(int frame) {
    for (final rep in widget.run.analysis.reps) {
      if (frame >= rep.valleyFrame && frame <= rep.endFrame) return rep;
    }
    return null;
  }

  String _phase(Rep? rep, int frame) {
    if (rep == null) {
      final reps = widget.run.analysis.reps;
      if (reps.isNotEmpty && frame > reps.last.endFrame) return 'Set complete';
      return 'Hang';
    }
    if (frame < rep.onsetFrame) return 'Dead hang';
    if (frame < rep.peakFrame - 1) return 'Pulling';
    if (frame <= rep.peakFrame + 1) return 'Top';
    return 'Lowering';
  }

  Color _phaseColor(String phase) {
    switch (phase) {
      case 'Pulling':
        return kAccent;
      case 'Top':
        return kGood;
      case 'Lowering':
        return kAccentDeep;
      case 'Set complete':
        return kMuted;
      default:
        return kWarn;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Replay · ${widget.run.meta.mode.label}'),
        actions: [
          TextButton(
            onPressed: _cycleSpeed,
            child: Text(
              _speed == 1.0 ? '1×' : _speed == 0.5 ? '0.5×' : '0.25×',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: kAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? _errorBody()
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : _body(),
      ),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: _aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(_controller!),
                  ValueListenableBuilder<double>(
                    valueListenable: _clock,
                    builder: (context, seconds, _) {
                      final frame = _frameAt(seconds);
                      final rep = _activeRep(frame);
                      final phase = _phase(rep, frame);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          PoseOverlay(person: _personAt(frame)),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: _countBadge(frame),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: _phaseColor(phase)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                phase,
                                style: TextStyle(
                                  color: _phaseColor(phase),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _controls(),
        const SizedBox(height: 14),
        ValueListenableBuilder<double>(
          valueListenable: _clock,
          builder: (context, seconds, _) {
            final frame = _frameAt(seconds);
            final rep = _activeRep(frame);
            final analysis = widget.run.analysis;
            final count = analysis.countAt(frame);
            return Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  _metric(
                    'Rep',
                    analysis.count == 0 ? '0' : '$count/${analysis.count}',
                    kText,
                  ),
                  _divider(),
                  _metric('Elbow', fmtDegrees(_elbowAt()), kAccent),
                  _divider(),
                  _metric(
                    'Chin over bar',
                    fmtTorso(_clearanceAt()),
                    rep == null ? kMuted : kGood,
                  ),
                ],
              ),
            );
          },
        ),
        if (widget.run.analysis.reps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('Jump to a rep'),
          _repChips(),
        ],
        const SizedBox(height: 16),
        Text(
          widget.run.meta.mode == LiftMode.pullUp
              ? 'Green reps reached a full hang and cleared the bar. Red ones '
                  'were counted but came up short.'
              : 'Every rep shown cleared the bar with the chin. Range of motion '
                  'is not graded in chin-up mode.',
          style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.45),
        ),
      ],
    );
  }

  Widget _countBadge(int frame) {
    final analysis = widget.run.analysis;
    final count = analysis.countAt(frame);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            analysis.count == 0 ? 'reps' : '/ ${analysis.count}',
            style: const TextStyle(
              color: kMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final controller = _controller!;
    return Row(
      children: [
        IconButton(
          onPressed: _togglePlay,
          iconSize: 34,
          color: kText,
          icon: Icon(
            controller.value.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: _clock,
            builder: (context, seconds, _) {
              final duration = _duration;
              return Slider(
                min: 0,
                max: duration <= 0 ? 1 : duration,
                value: seconds.clamp(0, duration <= 0 ? 1 : duration),
                onChanged: (value) => _seekTo(value),
              );
            },
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _clock,
          builder: (context, seconds, _) => Text(
            '${_clockText(seconds)} / ${_clockText(_duration)}',
            style: const TextStyle(
              color: kMuted,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kMuted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: kLine,
  );

  Widget _repChips() => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: widget.run.analysis.reps.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final rep = widget.run.analysis.reps[index];
        final color = rep.grade == null
            ? kMuted
            : rep.grade!.complete
                ? kGood
                : kBad;
        return ActionChip(
          onPressed: () => _seekTo(rep.valleyTime),
          avatar: CircleAvatar(
            radius: 9,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              '${rep.number}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          label: Text(fmtSeconds(rep.movingSeconds, decimals: 1)),
        );
      },
    ),
  );

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
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );

  static String _clockText(double seconds) {
    if (!seconds.isFinite) return '0:00.0';
    final minutes = seconds ~/ 60;
    final rest = seconds - minutes * 60;
    return '$minutes:${rest.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
