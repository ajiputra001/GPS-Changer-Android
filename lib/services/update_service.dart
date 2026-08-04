import 'dart:convert';
import 'package:http/http.dart' as http;
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

  /// This value is automatically replaced at build time by the GitHub Actions
  /// workflow. When running locally it stays as the literal placeholder and
  /// the update check is skipped so developers are never bothered.
  static const String buildTag = 'LOCAL_DEV';

  /// Checks GitHub latest release API for any newer version.
  /// Returns non-null only when the remote tag differs from the embedded
  /// [buildTag] *and* buildTag is not the local-dev placeholder.
  static Future<UpdateInfo?> checkLatestRelease() async {
    // Skip update checks for local/debug builds that were never stamped.
    if (buildTag == 'LOCAL_DEV') return null;

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
        final String body = (data['body'] ??
                'Pembaruan aplikasi terbaru telah rilis di GitHub.')
            .toString();
        final String htmlUrl = (data['html_url'] ??
                'https://github.com/$repoOwner/$repoName/releases')
            .toString();

        String directDownloadUrl =
            'https://github.com/$repoOwner/$repoName/releases/latest/download/Ajiputra-project-GPS.apk';

        final assets = data['assets'] as List?;
        if (assets != null) {
          for (final asset in assets) {
            if (asset is Map) {
              final name = (asset['name'] ?? '').toString();
              if (name.endsWith('.apk')) {
                directDownloadUrl =
                    (asset['browser_download_url'] ?? directDownloadUrl)
                        .toString();
                break;
              }
            }
          }
        }

        // Only prompt when the remote tag is genuinely different from the
        // tag that was baked into this APK at build time.
        if (tagName.isNotEmpty && tagName != buildTag) {
          return UpdateInfo(
            version: tagName,
            releaseNotes: body,
            downloadUrl: directDownloadUrl,
            pageUrl: htmlUrl,
          );
        }
      }
    } catch (_) {
      // Network failure or timeout — silent catch
    }
    return null;
  }

  /// Opens the download link in the external browser / package installer.
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
}
