import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../pairing/pairing_service.dart';

class ClipboardService {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  static String lastSyncedText = '';
  static void Function(String text)? onClipboardSynced;
  static Timer? _syncTimer;
  static bool _isSyncInProgress = false;

  static bool get isAutoSyncRunning => _syncTimer != null;

  /// Starts continuous bi-directional clipboard sync until stopped
  static void startAutoSync(PairedCompanion companion) {
    if (_syncTimer != null) return;
    debugPrint('⚡ Starting continuous clipboard sync with ${companion.baseUrl}');

    // Seed with current device clipboard so we don't immediately treat it as new
    readDeviceClipboard().then((initial) {
      if (initial != null && initial.isNotEmpty) {
        lastSyncedText = initial;
      }
    });

    _syncTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      await syncNow(companion);
    });
  }

  /// Trigger an immediate sync check (e.g. on app resume or user action)
  static Future<void> syncNow(PairedCompanion companion) async {
    if (_isSyncInProgress) return;
    _isSyncInProgress = true;

    try {
      // 1. Check local Android clipboard
      final localText = await readDeviceClipboard();
      if (localText != null &&
          localText.isNotEmpty &&
          localText != lastSyncedText) {
        lastSyncedText = localText;
        final success = await sendToCompanion(
          companion: companion,
          text: localText,
        );
        if (success) {
          onClipboardSynced?.call(localText);
          debugPrint('📋 Pushed local clipboard to Linux (${localText.length} chars)');
        }
        return;
      }

      // 2. Poll Linux companion as backup to direct TCP push
      final remoteText = await fetchFromCompanion(companion);
      if (remoteText != null &&
          remoteText.isNotEmpty &&
          remoteText != lastSyncedText) {
        lastSyncedText = remoteText;
        await writeDeviceClipboard(remoteText);
        onClipboardSynced?.call(remoteText);
        debugPrint('📋 Pulled remote clipboard from Linux (${remoteText.length} chars)');
      }
    } catch (e) {
      debugPrint('Clipboard sync tick error: $e');
    } finally {
      _isSyncInProgress = false;
    }
  }

  /// Called when Linux pushes a clipboard update via TCP directly to AndroidFileAgent
  static Future<void> applyIncomingClipboard(String text) async {
    if (text.isEmpty || text == lastSyncedText) return;
    lastSyncedText = text;
    await writeDeviceClipboard(text);
    onClipboardSynced?.call(text);
    debugPrint('📋 Live TCP clipboard applied on Android (${text.length} chars)');
  }

  /// Stops continuous clipboard sync
  static void stopAutoSync() {
    if (_syncTimer != null) {
      _syncTimer?.cancel();
      _syncTimer = null;
      debugPrint('🛑 Stopped continuous clipboard sync');
    }
  }

  /// Send text to the Linux companion's shared clipboard
  static Future<bool> sendToCompanion({
    required PairedCompanion companion,
    required String text,
  }) async {
    final uri = Uri.parse('${companion.baseUrl}/clipboard');
    try {
      final req = await _client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'token': companion.token,
        'text': text,
      }));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch the latest text from the Linux companion's shared clipboard
  static Future<String?> fetchFromCompanion(PairedCompanion companion) async {
    final uri = Uri.parse('${companion.baseUrl}/clipboard');
    try {
      final req = await _client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await utf8.decoder.bind(res).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['text'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get current text from Android device clipboard
  static Future<String?> readDeviceClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// Write text into Android device clipboard
  static Future<void> writeDeviceClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
