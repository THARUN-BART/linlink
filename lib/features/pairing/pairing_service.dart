import 'dart:convert';
import 'dart:io';

class PairingTarget {
  final String host;
  final int port;
  final String token;

  const PairingTarget({
    required this.host,
    required this.port,
    required this.token,
  });

  /// Parse URLs in format: linlink://HOST:PORT?t=TOKEN or http://HOST:PORT?t=TOKEN or HOST:PORT?t=TOKEN
  static PairingTarget? tryParse(String raw) {
    try {
      var trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      if (!trimmed.contains('://')) {
        trimmed = 'linlink://$trimmed';
      }

      final uri = Uri.parse(trimmed);
      if (uri.scheme != 'linlink' && uri.scheme != 'http' && uri.scheme != 'https') {
        return null;
      }
      final host = uri.host;
      if (host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 7878;
      final token = uri.queryParameters['t'] ?? uri.queryParameters['token'] ?? '';
      if (token.isEmpty) return null;

      return PairingTarget(host: host, port: port, token: token);
    } catch (_) {
      return null;
    }
  }
}

class PairedCompanion {
  final String host;
  final int port;
  final String token;
  final String deviceName;
  final DateTime pairedAt;
  String status;

  PairedCompanion({
    required this.host,
    required this.port,
    required this.token,
    required this.deviceName,
    required this.pairedAt,
    this.status = 'Connected',
  });

  String get baseUrl => 'http://$host:$port';
}

class PairingService {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  /// Pair with the companion: sends scan notification and then handshake
  static Future<PairedCompanion> pair({
    required PairingTarget target,
    required String deviceName,
  }) async {
    // 1. Send scan notification
    final scanUri = Uri.parse('http://${target.host}:${target.port}/pair/scan');
    try {
      final scanReq = await _client.postUrl(scanUri);
      scanReq.headers.contentType = ContentType.json;
      scanReq.write(jsonEncode({'token': target.token}));
      final scanRes = await scanReq.close();
      if (scanRes.statusCode != 200) {
        throw HttpException(
          'Pairing scan failed with code ${scanRes.statusCode}',
          uri: scanUri,
        );
      }
    } catch (e) {
      throw Exception(
        'Could not connect to Linux Companion at ${target.host}:${target.port}.\n\n'
        'Ensure both devices are on the same Wi-Fi network and `linlink pair` is running.\n\nError: $e',
      );
    }

    // 2. Send handshake with device name
    final handshakeUri = Uri.parse('http://${target.host}:${target.port}/pair/handshake');
    try {
      final hsReq = await _client.postUrl(handshakeUri);
      hsReq.headers.contentType = ContentType.json;
      hsReq.write(jsonEncode({
        'token': target.token,
        'device_name': deviceName,
      }));
      final hsRes = await hsReq.close();
      final bodyStr = await utf8.decoder.bind(hsRes).join();

      if (hsRes.statusCode != 200) {
        throw Exception('Handshake rejected (${hsRes.statusCode}): $bodyStr');
      }

      return PairedCompanion(
        host: target.host,
        port: target.port,
        token: target.token,
        deviceName: deviceName,
        pairedAt: DateTime.now(),
        status: 'Connected',
      );
    } catch (e) {
      throw Exception('Failed to complete handshake: $e');
    }
  }

  /// Check companion status
  static Future<Map<String, dynamic>?> checkStatus(PairedCompanion companion) async {
    final statusUri = Uri.parse('${companion.baseUrl}/status');
    try {
      final req = await _client.getUrl(statusUri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await utf8.decoder.bind(res).join();
        return jsonDecode(body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Unlink device from companion
  static Future<bool> unlink(PairedCompanion companion) async {
    final unlinkUri = Uri.parse('${companion.baseUrl}/pair/unlink');
    try {
      final req = await _client.postUrl(unlinkUri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'token': companion.token}));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
