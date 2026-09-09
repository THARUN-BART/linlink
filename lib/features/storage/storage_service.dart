import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pairing/pairing_service.dart';

class StorageService {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  /// Check whether full storage or media permissions are granted
  static Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 11+ (API 30+) uses Manage External Storage
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      // Android 10 and below uses Storage
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      // Android 13+ granular media
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isGranted) return true;
    }
    return false;
  }

  /// Request storage permissions based on Android version
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // First try Manage External Storage (Android 11+)
      var manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      // Try regular storage
      var storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // Request media permissions for Android 13+
      Map<Permission, PermissionStatus> statuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      return statuses.values.any((s) => s.isGranted);
    }
    return false;
  }

  /// List items in an Android storage path
  static Future<List<FileSystemEntity>> listStorageDirectory({
    String path = '/storage/emulated/0/Download',
  }) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        return dir.listSync();
      }
    } catch (_) {}
    return [];
  }

  /// Send a file or note to the Linux companion
  static Future<bool> uploadFileToCompanion({
    required PairedCompanion companion,
    required String filename,
    required String content,
  }) async {
    final uri = Uri.parse('${companion.baseUrl}/files/upload');
    try {
      final req = await _client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'token': companion.token,
        'filename': filename,
        'content': content,
      }));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send any binary file (photo, video, document) from phone directly to Linux companion
  static Future<bool> uploadBinaryFile({
    required PairedCompanion companion,
    required PlatformFile file,
    String destDir = '~/Downloads/LinLink',
  }) async {
    final filename = file.name;
    final uploadUri = Uri.parse(
      '${companion.baseUrl}/api/fs/upload?token=${companion.token}&dest_dir=${Uri.encodeComponent(destDir)}&filename=${Uri.encodeComponent(filename)}',
    );

    final client = HttpClient()..connectionTimeout = const Duration(minutes: 5);
    try {
      final req = await client.postUrl(uploadUri);
      req.headers.contentType = ContentType.binary;
      final size = await file.length();
      req.contentLength = size;

      if (file.path != null && File(file.path!).existsSync()) {
        final localFile = File(file.path!);
        await localFile.openRead().cast<List<int>>().pipe(req);
      } else {
        await file.readAsByteStream().cast<List<int>>().pipe(req);
      }

      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
