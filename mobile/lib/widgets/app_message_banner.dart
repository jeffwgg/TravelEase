import 'package:flutter/material.dart';
import '../core/theme.dart';

enum AppMessageType { error, success, information }

class AppMessageBanner extends StatelessWidget {
  final String message;
  final AppMessageType type;
  final VoidCallback? onDismiss;

  const AppMessageBanner({
    super.key,
    required this.message,
    this.type = AppMessageType.information,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      AppMessageType.error => AppColors.emergency,
      AppMessageType.success => AppColors.success,
      AppMessageType.information => AppColors.primary,
    };
    final icon = switch (type) {
      AppMessageType.error => Icons.error_outline,
      AppMessageType.success => Icons.check_circle_outline,
      AppMessageType.information => Icons.info_outline,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
          if (onDismiss != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: color, size: 18),
            ),
        ],
      ),
    );
  }
}
