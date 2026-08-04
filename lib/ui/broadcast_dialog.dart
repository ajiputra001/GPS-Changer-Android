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
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00B4D8).withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 34,
              color: Color(0xFF00B4D8),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            info.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              child: Text(
                info.message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (info.linkUrl.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final uri = Uri.parse(info.linkUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00B4D8)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      "Buka Link",
                      style: TextStyle(color: Color(0xFF00B4D8), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                    ),
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Mengerti",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
