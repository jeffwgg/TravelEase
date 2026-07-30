import 'package:flutter/material.dart';
import '../../core/theme.dart';

class NotificationHistoryView extends StatelessWidget {
  const NotificationHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: () {}, child: const Text('Mark All Read')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDateSection(context, 'Today'),
          _buildNotification(context, Icons.swap_horiz, 'Gate Change', 'Flight MH370 gate changed from A5 to B12', '2 min ago', AppColors.secondary, true),
          _buildNotification(context, Icons.flight_takeoff, 'Boarding Call', 'Flight AK123 now boarding at Gate C4', '8 min ago', AppColors.primary, true),
          _buildNotification(context, Icons.warning_rounded, 'Fire Alarm', 'Fire alarm detected in Terminal 1 Zone A', '15 min ago', AppColors.emergency, false),
          _buildNotification(context, Icons.confirmation_num, 'Queue Update', 'Your queue number A-042 is being served', '30 min ago', AppColors.success, false),
          _buildNotification(context, Icons.chat, 'Staff Reply', 'Airport staff replied to your request', '1 hr ago', AppColors.accent, false),
          const SizedBox(height: 16),
          _buildDateSection(context, 'Yesterday'),
          _buildNotification(context, Icons.campaign, 'Announcement', 'Terminal 1 WiFi maintenance 2:00-4:00 PM', 'Yesterday 3:00 PM', AppColors.textSecondary, false),
          _buildNotification(context, Icons.check_circle, 'Request Resolved', 'Your assistance request has been resolved', 'Yesterday 1:30 PM', AppColors.success, false),
          _buildNotification(context, Icons.location_on, 'Venue Connected', 'Connected to KLIA Terminal 1', 'Yesterday 10:00 AM', AppColors.primary, false),
        ],
      ),
    );
  }

  Widget _buildDateSection(BuildContext context, String date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(date, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textMuted)),
    );
  }

  Widget _buildNotification(BuildContext context, IconData icon, String title, String desc, String time, Color color, bool unread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: unread ? color.withValues(alpha: 0.03) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: unread ? BorderSide(color: color.withValues(alpha: 0.2)) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(title, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500, fontSize: 14))),
                        if (unread) Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(desc, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(time, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
