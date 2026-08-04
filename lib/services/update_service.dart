import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final String pageUrl;

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.pageUrl,
  });
}

class UpdateService {
  static const String repoOwner = 'ajiputra001';
  static const String repoName = 'GPS-Changer-Android';
  static const String currentVersion = '2.1.0';

  /// Checks GitHub latest release API for any newer version.
  static Future<UpdateInfo?> checkLatestRelease() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String tagName = (data['tag_name'] ?? '').toString();
        final String body = (data['body'] ?? 'Pembaruan aplikasi terbaru telah rilis di GitHub.').toString();
        final String htmlUrl = (data['html_url'] ?? 'https://github.com/$repoOwner/$repoName/releases').toString();

        String directDownloadUrl = 'https://github.com/$repoOwner/$repoName/releases/latest/download/Ajiputra-project-GPS.apk';
        
        final assets = data['assets'] as List?;
        if (assets != null) {
          for (final asset in assets) {
            if (asset is Map) {
              final name = (asset['name'] ?? '').toString();
              if (name.endsWith('.apk')) {
                directDownloadUrl = (asset['browser_download_url'] ?? directDownloadUrl).toString();
                break;
              }
            }
          }
        }

        // Compare version tag with current installed version
        final prefs = await SharedPreferences.getInstance();
        final lastSeenTag = prefs.getString('last_installed_tag') ?? '';

        if (tagName.isNotEmpty && tagName != lastSeenTag) {
          return UpdateInfo(
            version: tagName,
            releaseNotes: body,
            downloadUrl: directDownloadUrl,
            pageUrl: htmlUrl,
          );
        }
      }
    } catch (_) {
      // Network failure or timeout - silent catch
    }
    return null;
  }

  /// Opens the download link or browser installer.
  static Future<void> launchDownload(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  /// Save installed version tag after updating.
  static Future<void> saveCurrentTag(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_installed_tag', tag);
  }
}
