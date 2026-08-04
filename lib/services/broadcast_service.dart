import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BroadcastInfo {
  final String id;
  final bool active;
  final String title;
  final String message;
  final String linkUrl;

  const BroadcastInfo({
    required this.id,
    required this.active,
    required this.title,
    required this.message,
    required this.linkUrl,
  });
}

class BroadcastService {
  static const String repoOwner = 'ajiputra001';
  static const String repoName = 'GPS-Changer-Android';
  static const String rawBroadcastUrl =
      'https://raw.githubusercontent.com/$repoOwner/$repoName/main/broadcast.json';

  /// Fetches developer broadcast message from GitHub raw storage.
  static Future<BroadcastInfo?> checkLatestBroadcast() async {
    try {
      final url = Uri.parse(rawBroadcastUrl);
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String id = (data['id'] ?? '').toString();
        final bool active = data['active'] == true;
        final String title = (data['title'] ?? 'Pesan dari Developer').toString();
        final String message = (data['message'] ?? '').toString();
        final String linkUrl = (data['linkUrl'] ?? '').toString();

        if (active && id.isNotEmpty && message.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final lastSeenId = prefs.getString('last_seen_broadcast_id') ?? '';

          if (id != lastSeenId) {
            return BroadcastInfo(
              id: id,
              active: active,
              title: title,
              message: message,
              linkUrl: linkUrl,
            );
          }
        }
      }
    } catch (_) {
      // Network offline or timeout - silent catch
    }
    return null;
  }

  /// Saves broadcast ID as seen so it doesn't prompt again.
  static Future<void> markAsSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_seen_broadcast_id', id);
  }
}
