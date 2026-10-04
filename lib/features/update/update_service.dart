import 'dart:convert';
import 'dart:io';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final bool hasUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.htmlUrl,
    this.apkDownloadUrl,
    required this.hasUpdate,
  });
}

class UpdateService {
  static const String currentAppVersion = "1.0.0";
  static const String repoOwner = "THARUN-BART";
  static const String repoName = "linlink";

  /// Checks for online updates from GitHub releases
  static Future<UpdateInfo> checkForUpdates({String? customRepo}) async {
    final repo = customRepo ?? '$repoOwner/$repoName';
    final url = Uri.parse('https://api.github.com/repos/$repo/releases/latest');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'LinLink-Android-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;

        final tagName = json['tag_name'] as String? ?? 'v1.0.0';
        final latestVersion = tagName.replaceAll(RegExp(r'^v'), '');
        final releaseName = json['name'] as String? ?? tagName;
        final releaseNotes = json['body'] as String? ?? '';
        final htmlUrl = json['html_url'] as String? ?? 'https://github.com/$repo';

        String? apkUrl;
        if (json['assets'] is List) {
          for (final asset in json['assets']) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk') || name.contains('android')) {
              apkUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
        }

        final isNewer = _isVersionNewer(currentAppVersion, latestVersion);

        return UpdateInfo(
          currentVersion: currentAppVersion,
          latestVersion: latestVersion,
          tagName: tagName,
          releaseName: releaseName,
          releaseNotes: releaseNotes,
          htmlUrl: htmlUrl,
          apkDownloadUrl: apkUrl,
          hasUpdate: isNewer,
        );
      } else {
        // Return current status when no release object exists
        return UpdateInfo(
          currentVersion: currentAppVersion,
          latestVersion: currentAppVersion,
          tagName: 'v$currentAppVersion',
          releaseName: 'LinLink v$currentAppVersion',
          releaseNotes: 'You are on the latest version.',
          htmlUrl: 'https://github.com/$repo',
          hasUpdate: false,
        );
      }
    } catch (_) {
      return UpdateInfo(
        currentVersion: currentAppVersion,
        latestVersion: currentAppVersion,
        tagName: 'v$currentAppVersion',
        releaseName: 'LinLink v$currentAppVersion',
        releaseNotes: 'Offline or up to date.',
        htmlUrl: 'https://github.com/$repo',
        hasUpdate: false,
      );
    }
  }

  static bool _isVersionNewer(String current, String candidate) {
    final currParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final candParts = candidate.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < currParts.length && i < candParts.length; i++) {
      if (candParts[i] > currParts[i]) return true;
      if (candParts[i] < currParts[i]) return false;
    }

    return candParts.length > currParts.length;
  }
}
