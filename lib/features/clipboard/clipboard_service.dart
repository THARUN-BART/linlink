import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../pairing/pairing_service.dart';

class ClipboardService {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

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
