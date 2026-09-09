import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../features/pairing/pairing_service.dart';

class ForegroundSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.example.linlink/foreground_service');

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// Request POST_NOTIFICATIONS permission on Android 13+ (API 33+)
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('Notification permission error: $e');
      return false;
    }
  }

  /// Start the background foreground service with an ongoing pop-up notification
  static Future<bool> start(PairedCompanion companion) async {
    if (!Platform.isAndroid) return false;

    try {
      await requestNotificationPermission();

      final success = await _channel.invokeMethod<bool>(
        'startForegroundService',
        {
          'deviceName': companion.deviceName,
          'host': companion.host,
        },
      );

      _isRunning = success ?? false;
      debugPrint('ForegroundSyncService started: $_isRunning');
      return _isRunning;
    } catch (e) {
      debugPrint('Failed to start ForegroundSyncService: $e');
      return false;
    }
  }

  /// Update the active notification text (e.g. when clipboard snippet is synchronized)
  static Future<void> update({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid || !_isRunning) return;

    try {
      await _channel.invokeMethod('updateNotification', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      debugPrint('Failed to update ForegroundSyncService notification: $e');
    }
  }

  /// Stop the background foreground service and remove notification
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('stopForegroundService');
      _isRunning = false;
      debugPrint('ForegroundSyncService stopped');
    } catch (e) {
      debugPrint('Failed to stop ForegroundSyncService: $e');
    }
  }
}
