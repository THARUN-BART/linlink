import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../pairing/pairing_service.dart';

/// Lightweight HTTP/TCP file server running on Android to serve files
/// to the Linux interactive terminal and companion bridge.
class AndroidFileAgent {
  static HttpServer? _server;
  static int currentPort = 7879;
  static bool get isRunning => _server != null;

  /// Starts the Android TCP file agent server
  static Future<int?> startServer({
    required PairedCompanion companion,
    int port = 7879,
  }) async {
    if (_server != null) {
      return currentPort;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      currentPort = _server!.port;
      debugPrint('🟢 AndroidFileAgent listening on TCP port $currentPort');

      _server!.listen(
        (request) => _handleRequest(request, companion.token),
        onError: (e) {
          debugPrint('AndroidFileAgent error: $e');
        },
      );

      await _registerWithCompanion(companion, currentPort);
      return currentPort;
    } catch (e) {
      debugPrint('Failed to bind AndroidFileAgent on port $port: $e');
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        currentPort = _server!.port;
        _server!.listen((req) => _handleRequest(req, companion.token));
        await _registerWithCompanion(companion, currentPort);
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

  static Future<void> _handleRequest(HttpRequest request, String expectedToken) async {
    final token = request.uri.queryParameters['token'] ??
        request.headers.value('x-session-token');

    // Allow ping without token for quick health checks
    if (request.uri.path == '/fs/ping') {
      await _writeJson(request.response, {
        'status': 'ok',
        'device': 'Android',
        'port': currentPort,
      });
      return;
    }

    if (token != null && token != expectedToken) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Unauthorized');
      await request.response.close();
      return;
    }

    try {
      switch (request.uri.path) {
        case '/fs/list':
          await _handleList(request);
          break;

        case '/fs/download':
          await _handleDownload(request);
          break;

        case '/fs/upload':
          await _handleUpload(request);
          break;

        case '/fs/mkdir':
          await _handleMkdir(request);
          break;

        case '/fs/delete':
          await _handleDelete(request);
          break;

        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found');
          await request.response.close();
      }
    } catch (e) {
      debugPrint('Error handling ${request.uri.path}: $e');
      try {
        await _writeJson(request.response, {
          'status': 'error',
          'message': e.toString(),
        }, status: HttpStatus.internalServerError);
      } catch (_) {}
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
    String targetDir = request.uri.queryParameters['path'] ?? '/storage/emulated/0/Download';
    final filename = request.uri.queryParameters['filename'] ?? 'uploaded_from_linux.dat';

    Directory dir = Directory(targetDir);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      // Fallback to Download folder if target directory is not writable
      targetDir = '/storage/emulated/0/Download';
      dir = Directory(targetDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
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
    } catch (e) {
      await _writeJson(request.response, {
        'status': 'error',
        'message': 'Failed to save file: $e',
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
}
