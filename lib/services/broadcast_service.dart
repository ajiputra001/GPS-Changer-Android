import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BroadcastInfo {
  final String id;
  final bool active;
  final String title;
  final String message;
  final String linkUrl;
  final String notificationType; // "status_bar", "dialog", "both"
  final String badgeText; // e.g. "PENGUMUMAN", "UPDATE", "PENTING"
  final String priority; // "high", "normal"

  const BroadcastInfo({
    required this.id,
    required this.active,
    required this.title,
    required this.message,
    required this.linkUrl,
    this.notificationType = 'both',
    this.badgeText = 'PENGUMUMAN',
    this.priority = 'high',
  });
}

class BroadcastService {
  static const String repoOwner = 'ajiputra001';
  static const String repoName = 'GPS-Changer-Android';
  static const String rawBroadcastUrl =
      'https://raw.githubusercontent.com/$repoOwner/$repoName/main/broadcast.json';
  static const MethodChannel _platform = MethodChannel('com.mockgps/service');

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
        final String notificationType =
            (data['notificationType'] ?? 'both').toString();
        final String badgeText = (data['badgeText'] ?? 'PENGUMUMAN').toString();
        final String priority = (data['priority'] ?? 'high').toString();

        if (active && id.isNotEmpty && message.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final lastSeenId = prefs.getString('last_seen_broadcast_id') ?? '';
          final lastNotifiedId =
              prefs.getString('last_notified_broadcast_id') ?? '';

          final info = BroadcastInfo(
            id: id,
            active: active,
            title: title,
            message: message,
            linkUrl: linkUrl,
            notificationType: notificationType,
            badgeText: badgeText,
            priority: priority,
          );

          // 1. Post to system Notification Bar if not notified yet
          if ((notificationType == 'status_bar' || notificationType == 'both') &&
              id != lastNotifiedId) {
            try {
              if (await Permission.notification.isDenied) {
                await Permission.notification.request();
              }
              await _platform.invokeMethod('showBroadcastNotification', {
                'id': id,
                'title': title,
                'message': message,
                'linkUrl': linkUrl,
                'badgeText': badgeText,
              });
              await prefs.setString('last_notified_broadcast_id', id);
            } catch (_) {
              // Ignore platform channel failures
            }
          }

          // 2. Return BroadcastInfo for in-app Dialog if requested and not seen yet
          if ((notificationType == 'dialog' || notificationType == 'both') &&
              id != lastSeenId) {
            return info;
          }
        }
      }
    } catch (_) {
      // Network offline or timeout - silent catch
    }
    return null;
  }

  /// Saves broadcast ID as seen so in-app dialog doesn't prompt again.
  static Future<void> markAsSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_seen_broadcast_id', id);
  }
}
