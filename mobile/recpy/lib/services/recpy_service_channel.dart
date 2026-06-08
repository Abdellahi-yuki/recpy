import 'package:flutter/services.dart';

/// Dart interface to the native RecpyService (Android foreground service).
/// All socket I/O runs in Kotlin — survives backgrounding, screen-off,
/// file picker transitions, and activity recreation.
class RecpyServiceChannel {
  static const _method = MethodChannel('io.recpy.app/service');
  static const _events = MethodChannel('io.recpy.app/service_events');

  static Function(String clientIp, String text)? _onTextReceived;
  static Function(String clientIp, String filename, String savedPath)? _onFileReceived;
  static Function(String clientIp, String info, double progress)? _onTransferProgress;
  static Function(String status)? _onStatusChanged;
  static Function(String error)? _onError;
  static Function(String name, double progress)? _onSendProgress;

  static bool _listening = false;

  static void _setupEventHandler() {
    _events.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTextReceived':
          final m = Map<String, dynamic>.from(call.arguments as Map);
          _onTextReceived?.call(m['clientIp'] as String, m['text'] as String);
        case 'onFileReceived':
          final m = Map<String, dynamic>.from(call.arguments as Map);
          _onFileReceived?.call(
              m['clientIp'] as String,
              m['filename'] as String,
              m['savedPath'] as String);
        case 'onTransferProgress':
          final m = Map<String, dynamic>.from(call.arguments as Map);
          _onTransferProgress?.call(
              m['clientIp'] as String,
              m['info'] as String,
              (m['progress'] as num).toDouble());
        case 'onStatusChanged':
          _onStatusChanged?.call(call.arguments as String);
        case 'onError':
          _onError?.call(call.arguments as String);
        case 'onSendProgress':
          final m = Map<String, dynamic>.from(call.arguments as Map);
          _onSendProgress?.call(
              m['name'] as String,
              (m['progress'] as num).toDouble());
      }
    });
  }

  // ── Receiver ─────────────────────────────────────────────────────────────

  static Future<void> startReceiver({
    required int port,
    required Function(String clientIp, String text) onTextReceived,
    required Function(String clientIp, String filename, String savedPath) onFileReceived,
    required Function(String clientIp, String info, double progress) onTransferProgress,
    required Function(String status) onStatusChanged,
    required Function(String error) onError,
  }) async {
    _onTextReceived     = onTextReceived;
    _onFileReceived     = onFileReceived;
    _onTransferProgress = onTransferProgress;
    _onStatusChanged    = onStatusChanged;
    _onError            = onError;
    _setupEventHandler();
    _listening = true;
    await _method.invokeMethod('startReceiver', {'port': port});
  }

  static Future<void> stopReceiver() async {
    _listening = false;
    await _method.invokeMethod('stopReceiver');
  }

  static Future<bool> get isListening async {
    return await _method.invokeMethod<bool>('isListening') ?? false;
  }

  // ── Send text ─────────────────────────────────────────────────────────────

  static Future<void> sendText({
    required String ip,
    required int port,
    required String text,
  }) async {
    await _method.invokeMethod('sendText', {'ip': ip, 'port': port, 'text': text});
  }

  // ── Send file ─────────────────────────────────────────────────────────────

  /// Returns true if completed, false if cancelled.
  static Future<bool> sendFile({
    required String ip,
    required int port,
    required String uri,
    required String name,
    required int size,
    required Function(double progress) onProgress,
  }) async {
    _onSendProgress = (n, p) { if (n == name) onProgress(p); };
    _setupEventHandler();
    final result = await _method.invokeMethod<bool>('sendFile', {
      'ip': ip,
      'port': port,
      'uri': uri,
      'name': name,
      'size': size,
    });
    _onSendProgress = null;
    return result ?? false;
  }

  static Future<void> cancelSend() async {
    await _method.invokeMethod('cancelSend');
  }
}
