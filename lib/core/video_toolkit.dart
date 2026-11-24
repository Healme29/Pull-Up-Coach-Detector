/// The Android side of clip preparation: probe, trim and normalise to 720p/30.
library;

import 'package:flutter/services.dart';

class VideoInfo {
  const VideoInfo({
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
    required this.fps,
    required this.frameCount,
  });

  final String path;
  final int durationMs;
  final int width;
  final int height;
  final int rotation;
  final double fps;
  final int frameCount;

  double get durationSeconds => durationMs / 1000.0;

  /// Width / height as displayed, rotation applied.
  double get displayAspect {
    final swapped = rotation % 180 != 0;
    final w = swapped ? height : width;
    final h = swapped ? width : height;
    return h == 0 ? 1.0 : w / h;
  }

  static VideoInfo fromMap(Map<dynamic, dynamic> map) => VideoInfo(
    path: map['path'] as String,
    durationMs: (map['durationMs'] as num).toInt(),
    width: (map['width'] as num).toInt(),
    height: (map['height'] as num).toInt(),
    rotation: (map['rotation'] as num).toInt(),
    fps: (map['fps'] as num).toDouble(),
    frameCount: (map['frameCount'] as num?)?.toInt() ?? 0,
  );
}

class VideoToolkit {
  VideoToolkit._();

  static const MethodChannel _channel =
      MethodChannel('dev.visiondemos.pullups/video');

  static void Function(double percent)? onTranscodeProgress;
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'transcodeProgress') {
        final args = call.arguments as Map?;
        final percent = (args?['percent'] as num?)?.toDouble() ?? 0;
        onTranscodeProgress?.call(percent);
      }
      return null;
    });
  }

  static Future<VideoInfo> probe(String path) async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('probe', {
      'path': path,
    });
    if (map == null) throw const FormatException('Could not read that clip.');
    return VideoInfo.fromMap(map);
  }

  /// Trim to [startMs, endMs], scale so the stored frame is [height] tall and
  /// resample to [fps], H.264, no audio.
  static Future<VideoInfo> transcode({
    required String input,
    required String output,
    required int startMs,
    required int endMs,
    int height = 720,
    int fps = 30,
    void Function(double percent)? onProgress,
  }) async {
    _listen();
    onTranscodeProgress = onProgress;
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'transcode',
        {
          'input': input,
          'output': output,
          'startMs': startMs,
          'endMs': endMs,
          'height': height,
          'fps': fps,
        },
      );
      if (map == null) throw const FormatException('The clip could not be prepared.');
      return VideoInfo.fromMap(map);
    } finally {
      onTranscodeProgress = null;
    }
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // Nothing was running.
    }
  }
}
