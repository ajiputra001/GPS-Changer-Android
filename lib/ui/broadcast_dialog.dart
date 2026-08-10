import 'package:flutter/material.dart';
import 'package:gps_mock/services/broadcast_service.dart';
import 'package:url_launcher/url_launcher.dart';

class BroadcastDialog extends StatelessWidget {
  final BroadcastInfo info;

  const BroadcastDialog({super.key, required this.info});

  static Future<void> show(
    BuildContext context, {
    required BroadcastInfo info,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => BroadcastDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Badge Icon with Cyan Gradient Glow
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00B4D8).withValues(alpha: 0.2),
                  const Color(0xFF0077B6).withValues(alpha: 0.3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00B4D8).withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 38,
              color: Color(0xFF00B4D8),
            ),
          ),
          const SizedBox(height: 14),

          // Category Chip Badge (e.g. "PENGUMUMAN", "UPDATE", "PENTING")
          if (info.badgeText.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                info.badgeText.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF00B4D8),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Title
          Text(
            info.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Message Card
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                info.message,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.88),
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons Row
          Row(
            children: [
              if (info.linkUrl.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final uri = Uri.parse(info.linkUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      "Buka Link",
                      style: TextStyle(
                        color: Color(0xFF00B4D8),
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      BroadcastService.markAsSeen(info.id);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      "Mengerti",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
