/// Saved runs on the phone: the normalised clip, the pose reply, and what the
/// analysis made of it. A second look at a saved set costs no network at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'models.dart';
import 'orientation.dart';
import 'pose.dart';
import 'signal.dart';

class RunMeta {
  const RunMeta({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.reps,
    required this.full,
    required this.graded,
    required this.clipSeconds,
    required this.fps,
    required this.frames,
    required this.aspect,
    required this.rotation,
    required this.anonymous,
    required this.uploadBytes,
    required this.gatewaySeconds,
    required this.offBarFrames,
  });

  final String id;
  final DateTime createdAt;
  final LiftMode mode;
  final int reps;
  final int full;
  final int graded;
  final double clipSeconds;
  final double fps;
  final int frames;
  final double aspect;
  final int rotation;
  final bool anonymous;
  final int uploadBytes;
  final double gatewaySeconds;
  final int offBarFrames;

  String get title => '${mode.label} · $reps reps';

  String get subtitle {
    final date = createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when =
        '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
    if (graded == 0) return '$when · $clipSeconds s';
    return '$when · $full/$graded full ROM · $clipSeconds s';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'mode': mode.name,
    'reps': reps,
    'full': full,
    'graded': graded,
    'clipSeconds': clipSeconds,
    'fps': fps,
    'frames': frames,
    'aspect': aspect,
    'rotation': rotation,
    'anonymous': anonymous,
    'uploadBytes': uploadBytes,
    'gatewaySeconds': gatewaySeconds,
    'offBarFrames': offBarFrames,
  };

  factory RunMeta.fromJson(Map<String, dynamic> json) => RunMeta(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    mode: json['mode'] == 'chinUp' ? LiftMode.chinUp : LiftMode.pullUp,
    reps: (json['reps'] as num).toInt(),
    full: (json['full'] as num).toInt(),
    graded: (json['graded'] as num).toInt(),
    clipSeconds: (json['clipSeconds'] as num).toDouble(),
    fps: (json['fps'] as num).toDouble(),
    frames: (json['frames'] as num).toInt(),
    aspect: (json['aspect'] as num).toDouble(),
    rotation: (json['rotation'] as num).toInt(),
    anonymous: json['anonymous'] as bool? ?? true,
    uploadBytes: (json['uploadBytes'] as num?)?.toInt() ?? 0,
    gatewaySeconds: (json['gatewaySeconds'] as num?)?.toDouble() ?? 0,
    offBarFrames: (json['offBarFrames'] as num?)?.toInt() ?? 0,
  );
}

/// A saved run, reopened: the same analysis the results screen showed.
class RunData {
  const RunData({
    required this.meta,
    required this.frames,
    required this.aspect,
    required this.analysis,
    required this.clipPath,
  });

  final RunMeta meta;

  /// Keypoints already rotated into display orientation.
  final List<PoseFrame> frames;
  final double aspect;
  final Analysis analysis;
  final String clipPath;
}

class RunStore {
  RunStore({Directory? root}) : _override = root;

  final Directory? _override;
  Directory? _cachedRoot;

  Future<Directory> root() async {
    if (_override != null) return _override;
    final support = await getApplicationSupportDirectory();
    _cachedRoot ??= Directory('${support.path}/runs');
    final dir = _cachedRoot!;
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String stamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<Directory> newRun() async {
    final base = await root();
    final id = stamp(DateTime.now());
    var dir = Directory('${base.path}/$id');
    var n = 2;
    while (await dir.exists()) {
      dir = Directory('${base.path}/$id-$n');
      n++;
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> savePoses(Directory run, Map<String, dynamic> envelope) =>
      File('${run.path}/poses.json').writeAsString(jsonEncode(envelope));

  Future<void> saveAnalysis(Directory run, Map<String, dynamic> json) =>
      File('${run.path}/analysis.json').writeAsString(jsonEncode(json));

  Future<void> saveMeta(Directory run, RunMeta meta) =>
      File('${run.path}/meta.json').writeAsString(jsonEncode(meta.toJson()));

  Future<List<RunMeta>> history() async {
    final base = await root();
    final out = <RunMeta>[];
    await for (final entity in base.list()) {
      if (entity is! Directory) continue;
      final metaFile = File('${entity.path}/meta.json');
      if (!await metaFile.exists()) continue;
      try {
        final json = jsonDecode(await metaFile.readAsString());
        out.add(RunMeta.fromJson(Map<String, dynamic>.from(json as Map)));
      } catch (_) {
        // A half-written run from a killed process: ignore it.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<RunData?> load(String id) async {
    final base = await root();
    final dir = Directory('${base.path}/$id');
    final metaFile = File('${dir.path}/meta.json');
    final posesFile = File('${dir.path}/poses.json');
    if (!await metaFile.exists() || !await posesFile.exists()) return null;

    final meta = RunMeta.fromJson(
      Map<String, dynamic>.from(jsonDecode(await metaFile.readAsString()) as Map),
    );
    final envelope = Map<String, dynamic>.from(
      jsonDecode(await posesFile.readAsString()) as Map,
    );
    final reply = parsePoseReply(envelope);
    final oriented = normalizeOrientation(reply.frames, meta.aspect);
    final analysis = RepAnalyzer.analyze(
      frames: oriented.frames,
      fps: meta.fps,
      nSourceFrames: meta.frames,
      cfg: AnalysisConfig.forMode(meta.mode),
      aspect: oriented.aspect,
    );
    return RunData(
      meta: meta,
      frames: oriented.frames,
      aspect: oriented.aspect,
      analysis: analysis,
      clipPath: '${dir.path}/clip.mp4',
    );
  }

  Future<int> totalBytes() async {
    final base = await root();
    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear() async {
    final base = await root();
    if (await base.exists()) await base.delete(recursive: true);
    _cachedRoot = null;
  }

  Future<void> delete(String id) async {
    final base = await root();
    final dir = Directory('${base.path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
