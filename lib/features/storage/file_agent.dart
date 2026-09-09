import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../clipboard/clipboard_service.dart';
import '../pairing/pairing_service.dart';

/// Lightweight HTTP/TCP file server running on Android to serve files
/// to the Linux interactive terminal, companion bridge, or another mobile phone.
class AndroidFileAgent {
  static HttpServer? _server;
  static int currentPort = 7879;
  static bool get isRunning => _server != null;

  /// Privacy setting: whether remote peers (Linux or other phones) are allowed to browse the phone's directory tree.
  /// When false (default / Privacy Mode), remote /fs/list and download requests are blocked so peers cannot view phone folders.
  static bool allowRemoteBrowsing = false;

  /// Active session token for verifying incoming requests
  static String? currentToken;

  /// Display name of this device in the LinLink network
  static String? currentDeviceName;

  /// Callback when a peer initiates a handshake (e.g. phone-to-phone pairing)
  static void Function(PairedCompanion peer)? onPeerPaired;

  /// Callback when a file is received from another device
  static void Function(String filename, String path)? onFileReceived;

  /// Callback triggered when the Linux companion sends a disconnect notification.
  /// The UI should use this to immediately clear the paired state.
  static void Function()? onLinuxDisconnected;

  /// Discovers local IPv4 addresses (e.g. Wi-Fi or Hotspot LAN IP).
  static Future<List<String>> getLocalIpv4Addresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prioritize Wi-Fi (wlan) and Hotspot (ap, swlan) interfaces
      interfaces.sort((a, b) {
        final nameA = a.name.toLowerCase();
        final nameB = b.name.toLowerCase();
        bool isPriority(String n) =>
            n.contains('wlan') || n.contains('ap') || n.contains('eth');
        if (isPriority(nameA) && !isPriority(nameB)) return -1;
        if (!isPriority(nameA) && isPriority(nameB)) return 1;
        return nameA.compareTo(nameB);
      });

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      debugPrint('Error discovering local IP: $e');
    }
    return ips;
  }

  /// Discovers the primary local IPv4 address
  static Future<String?> getPrimaryLocalIp() async {
    final ips = await getLocalIpv4Addresses();
    if (ips.isEmpty) return null;
    return ips.first;
  }

  /// Generates a random 8-character hex pairing token
  static String generateSessionToken() {
    final random = Random.secure();
    final values = List<int>.generate(4, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Starts the Android TCP file agent server
  static Future<int?> startServer({
    PairedCompanion? companion,
    String? token,
    String? deviceName,
    int port = 7879,
  }) async {
    if (token != null) currentToken = token;
    if (deviceName != null) currentDeviceName = deviceName;

    if (companion != null) {
      currentToken = companion.token;
      currentDeviceName = companion.deviceName;
    }

    if (_server != null) {
      if (companion != null) {
        await _registerWithCompanion(companion, currentPort);
      }
      return currentPort;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      currentPort = _server!.port;
      debugPrint('🟢 AndroidFileAgent listening on TCP port $currentPort');

      _server!.listen(
        (request) => _handleRequest(request),
        onError: (e) {
          debugPrint('AndroidFileAgent error: $e');
        },
      );

      if (companion != null) {
        await _registerWithCompanion(companion, currentPort);
      }
      return currentPort;
    } catch (e) {
      debugPrint('Failed to bind AndroidFileAgent on port $port: $e');
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        currentPort = _server!.port;
        _server!.listen((req) => _handleRequest(req));
        if (companion != null) {
          await _registerWithCompanion(companion, currentPort);
        }
        return currentPort;
      } catch (e2) {
        debugPrint('Failed to bind ephemeral port: $e2');
        return null;
      }
    }
  }

  /// Stop the TCP agent server
  static Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    debugPrint('🛑 AndroidFileAgent stopped');
  }

  static Future<void> _registerWithCompanion(
    PairedCompanion companion,
    int port,
  ) async {
    try {
      final uri = Uri.parse('${companion.baseUrl}/api/device/register');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final payload = jsonEncode({
        'token': companion.token,
        'agent_port': port,
      });
      final bytes = utf8.encode(payload);
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      debugPrint('Registered Android agent port $port with companion (HTTP ${res.statusCode})');
    } catch (e) {
      debugPrint('Could not register agent port with companion: $e');
    }
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final token = request.uri.queryParameters['token'] ??
        request.uri.queryParameters['t'] ??
        request.headers.value('x-session-token');

    // Health check & status
    if (path == '/fs/ping' || path == '/status') {
      await _writeJson(request.response, {
        'status': 'ok',
        'device': 'Android',
        'name': currentDeviceName ?? 'LinLink Android',
        'port': currentPort,
        'privacy_mode': !allowRemoteBrowsing,
      });
      return;
    }

    // P2P Pairing scan notification
    if (path == '/pair/scan') {
      await _writeJson(request.response, {
        'status': 'ok',
        'message': 'Pairing scan acknowledged',
      });
      return;
    }

    // P2P Pairing handshake
    if (path == '/pair/handshake') {
      await _handleHandshake(request);
      return;
    }

    // Session unlinking
    if (path == '/pair/unlink') {
      await _writeJson(request.response, {
        'status': 'ok',
        'message': 'Unlinked',
      });
      return;
    }

    // Linux companion stopping — notify app immediately
    if (path == '/fs/disconnect') {
      await _writeJson(request.response, {
        'status': 'ok',
        'message': 'Disconnect acknowledged',
      });
      debugPrint('🔌 Linux companion sent disconnect notification');
      onLinuxDisconnected?.call();
      return;
    }

    // Authorization check for secure endpoints
    final expectedToken = currentToken;
    if (expectedToken != null && expectedToken.isNotEmpty) {
      if (token != null && token != expectedToken) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write('Unauthorized');
        await request.response.close();
        return;
      }
    }

    try {
      switch (path) {
        case '/fs/list':
        case '/api/fs/list':
          if (!allowRemoteBrowsing) {
            await _writeJson(request.response, {
              'status': 'restricted',
              'message': 'Remote directory browsing is disabled on this phone for privacy. To transfer files, please share them directly from the LinLink mobile app.',
              'current_path': '',
              'entries': [],
            }, status: HttpStatus.forbidden);
            break;
          }
          await _handleList(request);
          break;

        case '/fs/download':
        case '/api/fs/download':
          if (!allowRemoteBrowsing) {
            await _writeJson(request.response, {
              'status': 'restricted',
              'message': 'Remote file downloads are disabled by the phone for privacy. To transfer files, please share them directly from the LinLink mobile app.',
            }, status: HttpStatus.forbidden);
            break;
          }
          await _handleDownload(request);
          break;

        case '/fs/upload':
        case '/api/fs/upload':
          await _handleUpload(request);
          break;

        case '/files/upload':
          await _handleJsonFileUpload(request);
          break;

        case '/fs/mkdir':
        case '/api/fs/mkdir':
          if (!allowRemoteBrowsing) {
            await _writeJson(request.response, {
              'status': 'restricted',
              'message': 'Remote folder creation is disabled by the phone for privacy.',
            }, status: HttpStatus.forbidden);
            break;
          }
          await _handleMkdir(request);
          break;

        case '/fs/delete':
        case '/api/fs/delete':
          if (!allowRemoteBrowsing) {
            await _writeJson(request.response, {
              'status': 'restricted',
              'message': 'Remote deletions are disabled by the phone for privacy.',
            }, status: HttpStatus.forbidden);
            break;
          }
          await _handleDelete(request);
          break;

        case '/fs/clipboard':
          await _handleClipboard(request, expectedToken ?? '');
          break;

        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found');
          await request.response.close();
      }
    } catch (e) {
      debugPrint('Error handling $path: $e');
      try {
        await _writeJson(request.response, {
          'status': 'error',
          'message': e.toString(),
        }, status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  static Future<void> _handleHandshake(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      Map<String, dynamic> data = {};
      if (body.isNotEmpty) {
        data = jsonDecode(body) as Map<String, dynamic>;
      }
      final token = data['token']?.toString() ?? request.uri.queryParameters['token'];
      final clientDeviceName = data['device_name']?.toString() ?? 'Mobile Peer';

      if (currentToken != null && token != null && token != currentToken) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write('Invalid pairing token');
        await request.response.close();
        return;
      }

      var clientIp = request.connectionInfo?.remoteAddress.address ?? '';
      if (clientIp.startsWith('::ffff:')) {
        clientIp = clientIp.substring(7);
      }

      await _writeJson(request.response, {
        'status': 'ok',
        'device_name': currentDeviceName ?? 'Android Phone',
        'device': 'Android',
        'port': currentPort,
      });

      if (clientIp.isNotEmpty) {
        final peerCompanion = PairedCompanion(
          host: clientIp,
          port: 7879,
          token: token ?? currentToken ?? '',
          deviceName: clientDeviceName,
          pairedAt: DateTime.now(),
          status: 'Connected',
        );
        onPeerPaired?.call(peerCompanion);
      }
    } catch (e) {
      debugPrint('Handshake error on AndroidFileAgent: $e');
      await _writeJson(request.response, {
        'status': 'error',
        'message': e.toString(),
      }, status: HttpStatus.internalServerError);
    }
  }

  static Future<void> _writeJson(
    HttpResponse response,
    Map<String, dynamic> data, {
    int status = HttpStatus.ok,
  }) async {
    final bytes = utf8.encode(jsonEncode(data));
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..contentLength = bytes.length
      ..add(bytes);
    await response.close();
  }

  static Future<void> _handleList(HttpRequest request) async {
    String requestedPath = request.uri.queryParameters['path'] ?? '/storage/emulated/0';
    if (requestedPath.isEmpty || requestedPath == '~') {
      requestedPath = '/storage/emulated/0';
    }

    final dir = Directory(requestedPath);
    final entries = <Map<String, dynamic>>[];

    bool permissionDenied = false;
    String? permissionError;

    try {
      if (await dir.exists()) {
        final list = dir.listSync(followLinks: false);
        for (final entity in list) {
          try {
            final stat = entity.statSync();
            final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
            if (name.startsWith('.')) continue;

            final isDir = stat.type == FileSystemEntityType.directory;
            entries.add({
              'name': name,
              'is_dir': isDir,
              'size': isDir ? 0 : stat.size,
              'modified': stat.modified.toIso8601String().substring(0, 19).replaceAll('T', ' '),
            });
          } catch (_) {}
        }
      } else {
        await _writeJson(request.response, {
          'status': 'error',
          'message': 'Directory does not exist: $requestedPath',
          'current_path': requestedPath,
          'entries': [],
        }, status: HttpStatus.notFound);
        return;
      }
    } catch (e) {
      permissionDenied = true;
      permissionError = e.toString();
      debugPrint('Listing error on $requestedPath: $e');
    }

    // If root /storage/emulated/0 failed due to Scoped Storage permissions,
    // probe standard accessible user directories so user still sees contents
    if (permissionDenied && (requestedPath == '/storage/emulated/0' || requestedPath == '/storage/emulated/0/')) {
      final standardDirs = ['Download', 'Documents', 'DCIM', 'Pictures', 'Music', 'Movies'];
      for (final folder in standardDirs) {
        final sub = Directory('/storage/emulated/0/$folder');
        try {
          if (sub.existsSync()) {
            entries.add({
              'name': folder,
              'is_dir': true,
              'size': 0,
              'modified': DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' '),
            });
          }
        } catch (_) {}
      }
    }

    if (permissionDenied && entries.isEmpty) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': 'Storage permission denied: $permissionError',
        'permission_needed': true,
        'current_path': requestedPath,
        'entries': [],
      });
      return;
    }

    // Sort: directories first, then alphabetical
    entries.sort((a, b) {
      if (a['is_dir'] != b['is_dir']) {
        return (b['is_dir'] as bool) ? 1 : -1;
      }
      return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
    });

    final parent = dir.parent.path != dir.path ? dir.parent.path : null;

    await _writeJson(request.response, {
      'status': 'ok',
      'current_path': requestedPath,
      'parent_path': parent,
      'entries': entries,
    });
  }

  static Future<void> _handleDownload(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    if (filePath == null || filePath.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing path');
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found: $filePath');
      await request.response.close();
      return;
    }

    final filename = file.uri.pathSegments.last;
    final length = await file.length();

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..headers.set(HttpHeaders.contentDisposition, 'attachment; filename="$filename"')
      ..contentLength = length;

    await file.openRead().cast<List<int>>().pipe(request.response);
  }

  static Future<void> _handleUpload(HttpRequest request) async {
    String targetDir = request.uri.queryParameters['dest_dir'] ??
        request.uri.queryParameters['path'] ??
        '/storage/emulated/0/Download/LinLink';
    if (targetDir.startsWith('~')) {
      targetDir = '/storage/emulated/0/Download/LinLink';
    }
    final filename = request.uri.queryParameters['filename'] ??
        'file_${DateTime.now().millisecondsSinceEpoch}.dat';

    Directory dir;
    try {
      dir = Directory(targetDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      try {
        dir = Directory('/storage/emulated/0/Download/LinLink');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (_) {
        try {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } catch (_) {
          dir = Directory.systemTemp;
        }
      }
    }

    final destPath = '${dir.path}/$filename';
    final destFile = File(destPath);
    final sink = destFile.openWrite();

    try {
      await request.cast<List<int>>().pipe(sink);
      await _writeJson(request.response, {
        'status': 'ok',
        'path': destPath,
        'message': 'File uploaded successfully',
      });
      onFileReceived?.call(filename, destPath);
    } catch (e) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': 'Failed to save file: $e',
      }, status: HttpStatus.internalServerError);
    }
  }

  static Future<void> _handleJsonFileUpload(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final filename = data['filename'] as String? ?? 'note_${DateTime.now().millisecondsSinceEpoch}.txt';
      final content = data['content'] as String? ?? '';

      Directory dir;
      try {
        dir = Directory('/storage/emulated/0/Download/LinLink');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (_) {
        try {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } catch (_) {
          dir = Directory.systemTemp;
        }
      }

      final destPath = '${dir.path}/$filename';
      final destFile = File(destPath);
      await destFile.writeAsString(content);

      await _writeJson(request.response, {
        'status': 'ok',
        'path': destPath,
        'message': 'Note file saved successfully',
      });
      onFileReceived?.call(filename, destPath);
    } catch (e) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': e.toString(),
      }, status: HttpStatus.internalServerError);
    }
  }

  static Future<void> _handleMkdir(HttpRequest request) async {
    final path = request.uri.queryParameters['path'];
    if (path == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing path');
      await request.response.close();
      return;
    }

    try {
      final dir = Directory(path);
      await dir.create(recursive: true);
      await _writeJson(request.response, {'status': 'ok', 'created': path});
    } catch (e) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': e.toString(),
      }, status: HttpStatus.internalServerError);
    }
  }

  static Future<void> _handleDelete(HttpRequest request) async {
    final path = request.uri.queryParameters['path'];
    if (path == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing path');
      await request.response.close();
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      } else {
        final dir = Directory(path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
      await _writeJson(request.response, {'status': 'ok', 'deleted': path});
    } catch (e) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': e.toString(),
      }, status: HttpStatus.internalServerError);
    }
  }

  static Future<void> _handleClipboard(HttpRequest request, String expectedToken) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final text = data['text'] as String?;
      final token = data['token'] as String?;

      if (token != null && token != expectedToken) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write('Unauthorized');
        await request.response.close();
        return;
      }

      if (text != null && text.isNotEmpty) {
        await ClipboardService.applyIncomingClipboard(text);
      }

      await _writeJson(request.response, {
        'status': 'ok',
        'message': 'Clipboard updated on Android',
      });
    } catch (e) {
      debugPrint('Error handling clipboard push on Android: $e');
      await _writeJson(request.response, {
        'status': 'error',
        'message': e.toString(),
      }, status: HttpStatus.internalServerError);
    }
  }
}
