/// One run end to end: normalise the clip, ask the gateway, count the reps,
/// and keep everything on disk.
///
/// The order matters. The clip is trimmed and re-encoded on the phone first, so
/// the upload is a small 720p/30 file that fits the free frame cap. Only then
/// does anything leave the device.
library;

import 'dart:io';

import 'config.dart';
import 'gateway.dart';
import 'orientation.dart';
import 'pose.dart';
import 'signal.dart';
import 'store.dart';
import 'video_toolkit.dart';

enum PipelineStage { preparing, uploading, analyzing, saving }

class PipelineProgress {
  const PipelineProgress(this.stage, this.fraction, this.message);

  final PipelineStage stage;

  /// `0..1` within the stage.
  final double fraction;
  final String message;
}

/// Thrown when the user backs out mid-run. Nothing is kept.
class PipelineCancelled implements Exception {
  const PipelineCancelled();

  @override
  String toString() => 'Cancelled';
}

class PipelineResult {
  const PipelineResult({
    required this.run,
    required this.anonymous,
    required this.uploadBytes,
    required this.gatewaySeconds,
  });

  final RunData run;
  final bool anonymous;
  final int uploadBytes;
  final double gatewaySeconds;
}

class AnalysisPipeline {
  AnalysisPipeline({RunStore? store}) : store = store ?? RunStore();

  final RunStore store;

  GatewayClient? _gateway;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  /// Stop the run and release the network/encoder. Safe to call twice.
  void cancel() {
    _cancelled = true;
    _gateway?.cancel();
    VideoToolkit.cancel();
  }

  Future<PipelineResult> run({
    required String inputPath,
    required int startMs,
    required int endMs,
    required LiftMode mode,
    String apiKey = '',
    void Function(PipelineProgress)? onProgress,
  }) async {
    _cancelled = false;
    final gateway = GatewayClient(apiKey: apiKey.trim().isEmpty ? null : apiKey);
    _gateway = gateway;

    final runDir = await store.newRun();
    Directory? clipDir = runDir;
    try {
      _check();

      _report(onProgress, PipelineStage.preparing, 0.02, 'Reading the clip…');
      final source = await VideoToolkit.probe(inputPath);
      _check();

      if (source.durationMs <= 0) {
        throw const PipelineException('That clip has no video in it.');
      }

      var start = startMs.clamp(0, source.durationMs);
      var end = endMs <= start ? source.durationMs : endMs;
      end = end.clamp(start + 1, source.durationMs);
      final limitMs = (PipelineConfig.maxClipSeconds * 1000).round();
      if (end - start > limitMs) end = start + limitMs;

      final clipPath = '${runDir.path}/clip.mp4';
      _report(onProgress, PipelineStage.preparing, 0.05, 'Preparing 720p video…');
      final clip = await VideoToolkit.transcode(
        input: inputPath,
        output: clipPath,
        startMs: start,
        endMs: end,
        height: PipelineConfig.inferenceHeight,
        fps: PipelineConfig.inferenceFps.round(),
        onProgress: (percent) {
          final clamped = percent.clamp(0, 100).toDouble();
          _report(
            onProgress,
            PipelineStage.preparing,
            0.05 + 0.65 * clamped / 100.0,
            'Preparing 720p video… ${clamped.round()}%',
          );
        },
      );
      _check();

      final clipSeconds = clip.durationMs / 1000.0;
      final frames = PipelineConfig.framesFor(clipSeconds);

      _report(
        onProgress,
        PipelineStage.uploading,
        0.0,
        'Sending the clip to the gateway…',
      );
      final reply = await gateway.pose(
        video: File(clipPath),
        fps: PipelineConfig.inferenceFps,
        videoMaxFrames: frames,
      );
      _check();

      _report(
        onProgress,
        PipelineStage.analyzing,
        0.35,
        'Reading the poses…',
      );
      final parsed = parsePoseReply(reply.raw);
      if (parsed.frames.isEmpty) {
        throw const PipelineException(
          'The model found no frames it could read. Try a clip where the '
          'athlete is in view the whole time.',
        );
      }
      final oriented = normalizeOrientation(
        parsed.frames,
        clip.displayAspect,
      );

      _report(onProgress, PipelineStage.analyzing, 0.65, 'Counting reps…');
      final cfg = AnalysisConfig.forMode(mode);
      final analysis = RepAnalyzer.analyze(
        frames: oriented.frames,
        fps: PipelineConfig.inferenceFps,
        nSourceFrames: frames,
        cfg: cfg,
        aspect: oriented.aspect,
      );
      _check();

      _report(onProgress, PipelineStage.saving, 0.2, 'Saving the run…');
      final meta = RunMeta(
        id: _idOf(runDir),
        createdAt: DateTime.now(),
        mode: mode,
        reps: analysis.count,
        full: analysis.romTally.$1,
        graded: analysis.romTally.$2,
        clipSeconds: clipSeconds,
        fps: PipelineConfig.inferenceFps,
        frames: frames,
        aspect: clip.displayAspect,
        rotation: oriented.rotationDegrees,
        anonymous: gateway.anonymous,
        uploadBytes: reply.uploadBytes,
        gatewaySeconds: reply.seconds,
        offBarFrames: analysis.offBarFrames,
      );
      await store.savePoses(runDir, reply.raw);
      await store.saveAnalysis(runDir, analysis.toJson());
      await store.saveMeta(runDir, meta);
      _report(onProgress, PipelineStage.saving, 1.0, 'Done');

      final run = RunData(
        meta: meta,
        frames: oriented.frames,
        aspect: oriented.aspect,
        analysis: analysis,
        clipPath: clipPath,
      );
      clipDir = null; // keep the directory on success
      return PipelineResult(
        run: run,
        anonymous: gateway.anonymous,
        uploadBytes: reply.uploadBytes,
        gatewaySeconds: reply.seconds,
      );
    } on PipelineCancelled {
      rethrow;
    } on GatewayException {
      rethrow;
    } finally {
      _gateway = null;
      if (clipDir != null) {
        // Nothing usable was produced: do not leave a half clip in history.
        try {
          if (await clipDir.exists()) await clipDir.delete(recursive: true);
        } catch (_) {
          // Best effort.
        }
      }
    }
  }

  void _check() {
    if (_cancelled) throw const PipelineCancelled();
  }

  static String _idOf(Directory dir) {
    final parts = dir.path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? dir.path : parts.last;
  }

  static void _report(
    void Function(PipelineProgress)? onProgress,
    PipelineStage stage,
    double fraction,
    String message,
  ) {
    onProgress?.call(PipelineProgress(stage, fraction, message));
  }
}

/// A problem the user can act on: no video, no poses, a bad file.
class PipelineException implements Exception {
  const PipelineException(this.message);

  final String message;

  @override
  String toString() => message;
}
