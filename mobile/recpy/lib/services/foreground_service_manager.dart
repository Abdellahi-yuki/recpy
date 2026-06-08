import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Simple reference-counted wrapper around FlutterForegroundTask.
/// Multiple callers can request the service independently — it only
/// stops when all callers have released it.
class ForegroundServiceManager {
  static int _refCount = 0;

  static Future<void> acquire({
    String title = 'recpy',
    String text = 'Transfer in progress…',
  }) async {
    _refCount++;
    if (_refCount == 1) {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: title,
        notificationText: text,
      );
    } else {
      // Already running — just update the notification text
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  static Future<void> release() async {
    if (_refCount <= 0) return;
    _refCount--;
    if (_refCount == 0) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> forceStop() async {
    _refCount = 0;
    await FlutterForegroundTask.stopService();
  }
}
