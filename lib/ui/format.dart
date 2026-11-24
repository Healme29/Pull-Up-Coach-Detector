/// Small formatting helpers shared by the screens.
library;

import 'package:flutter/services.dart';

import '../core/gateway.dart';
import '../core/pipeline.dart';

String fmtSeconds(double value, {int decimals = 2}) {
  if (!value.isFinite) return '—';
  return '${value.toStringAsFixed(decimals)} s';
}

String fmtDegrees(double value) {
  if (!value.isFinite) return '—';
  return '${value.toStringAsFixed(0)}°';
}

String fmtTorso(double value) {
  if (!value.isFinite) return '—';
  return '${value.toStringAsFixed(2)} torso';
}

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Turn an exception into something the athlete can read and act on.
String friendlyError(Object error) {
  if (error is GatewayException) return error.message;
  if (error is PipelineException) return error.message;
  if (error is PipelineCancelled) return 'Cancelled.';
  if (error is FormatException) return error.message;
  if (error is PlatformException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message;
    switch (error.code) {
      case 'transcode_failed':
        return 'This phone could not re-encode that clip. Try a shorter one.';
      case 'probe_failed':
        return 'That file could not be read as a video.';
      case 'cancelled':
        return 'Cancelled.';
      default:
        return 'Something went wrong (${error.code}).';
    }
  }
  final text = error.toString();
  if (text.startsWith('Exception: ')) return text.substring(11);
  return text;
}
