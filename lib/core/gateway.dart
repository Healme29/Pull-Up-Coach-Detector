/// The gateway call: one video in, one pose envelope out.
///
/// The request mirrors `pull_ups/src/pose.py` exactly: the clip goes as a
/// base64 `video_url` in an OpenAI-compatible chat completion, with the pose
/// options in the JSON body. Anonymous runs need no account at all.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

class GatewayException implements Exception {
  GatewayException(this.message, {this.statusCode, this.quota = false});

  final String message;
  final int? statusCode;
  final bool quota;

  @override
  String toString() => message;
}

class PoseResponse {
  const PoseResponse({
    required this.raw,
    required this.usage,
    required this.seconds,
    required this.uploadBytes,
  });

  final Map<String, dynamic> raw;
  final Map<String, dynamic> usage;
  final double seconds;
  final int uploadBytes;
}

class GatewayClient {
  GatewayClient({this.apiKey});

  /// Null (or the published anonymous spelling) means the free tier.
  final String? apiKey;

  http.Client? _active;

  bool get anonymous =>
      apiKey == null || apiKey!.isEmpty || apiKey == PipelineConfig.anonymousKey;

  String get _key => anonymous ? PipelineConfig.anonymousKey : apiKey!;

  /// Abort an in-flight request. Safe to call when nothing is running.
  void cancel() {
    _active?.close();
    _active = null;
  }

  Future<PoseResponse> pose({
    required File video,
    required double fps,
    required int videoMaxFrames,
    void Function(int bytes)? onUploadStart,
  }) async {
    final started = DateTime.now();
    final bytes = await video.readAsBytes();
    onUploadStart?.call(bytes.length);

    final encoded = base64Encode(bytes);
    final body = jsonEncode({
      'model': PipelineConfig.poseModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'video_url',
              'video_url': {'url': 'data:video/mp4;base64,$encoded'},
            },
          ],
        },
      ],
      'response_format': {'type': 'json_object'},
      'method': 'pose',
      'video_fps': fps,
      'precision': 4,
      'video_max_frames': videoMaxFrames,
    });

    final client = http.Client();
    _active = client;
    try {
      final request = http.Request(
        'POST',
        Uri.parse('${PipelineConfig.gatewayBaseUrl}/chat/completions'),
      )
        ..headers['Authorization'] = 'Bearer $_key'
        ..headers['Content-Type'] = 'application/json'
        ..body = body;

      final streamed = await client
          .send(request)
          .timeout(PipelineConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(PipelineConfig.requestTimeout);

      final seconds = DateTime.now().difference(started).inMilliseconds / 1000.0;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFor(response);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw GatewayException('The gateway sent an unexpected reply.');
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['error'] != null) {
        throw GatewayException(_errorMessage(map['error']));
      }

      final choices = (map['choices'] as List?)?.cast<dynamic>();
      final choice = (choices == null || choices.isEmpty) ? null : choices.first;
      final message = (choice as Map?)?['message'] as Map?;
      final content = message?['content'];
      final Map<String, dynamic> envelope;
      if (content is String) {
        final parsed = jsonDecode(content);
        if (parsed is! Map) {
          throw GatewayException('The model reply was not a JSON object.');
        }
        envelope = Map<String, dynamic>.from(parsed);
      } else if (content is Map) {
        envelope = Map<String, dynamic>.from(content);
      } else {
        throw GatewayException('The model reply had no content.');
      }

      return PoseResponse(
        raw: envelope,
        usage: Map<String, dynamic>.from((map['usage'] as Map?) ?? const {}),
        seconds: seconds,
        uploadBytes: bytes.length,
      );
    } on TimeoutException {
      throw GatewayException(
        'The gateway took longer than ${PipelineConfig.requestTimeout.inMinutes} '
        'minutes. Check your connection and try a shorter clip.',
      );
    } on SocketException {
      throw GatewayException(
        'No connection to the gateway. Check your internet and try again.',
      );
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }
  }

  GatewayException _errorFor(http.Response response) {
    final body = response.body;
    String detail = '';
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['error'] != null) {
        detail = _errorMessage(parsed['error']);
      }
    } catch (_) {
      detail = body.trim();
    }
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';

    switch (response.statusCode) {
      case 401:
      case 403:
        return GatewayException(
          'That API key was rejected. Clear it in Settings to use the free tier.',
          statusCode: response.statusCode,
        );
      case 413:
        return GatewayException(
          'The clip was too large for one request. Trim it shorter and try again.',
          statusCode: response.statusCode,
        );
      case 429:
        return GatewayException(
          'The free tier is used up for this network (${PipelineConfig.anonymousLimits}). '
          'Try another Wi-Fi, wait a while, or add your own key in Settings.',
          statusCode: response.statusCode,
          quota: true,
        );
      case 400:
        return GatewayException(
          'The gateway refused the request${detail.isEmpty ? '' : ': $detail'}',
          statusCode: response.statusCode,
        );
      default:
        return GatewayException(
          'The gateway failed (${response.statusCode})'
          '${detail.isEmpty ? '' : ': $detail'}',
          statusCode: response.statusCode,
        );
    }
  }

  String _errorMessage(Object? error) {
    if (error is String) return error;
    if (error is Map) {
      return (error['message'] ?? error['detail'] ?? error.toString()).toString();
    }
    return error.toString();
  }
}
