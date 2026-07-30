import 'package:flutter/material.dart';
import '../../core/theme.dart';

class AnnouncementView extends StatelessWidget {
  const AnnouncementView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connected venue
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('KLIA Terminal 1', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.primary)),
                const Spacer(),
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('Live', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.success)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ..._announcements.map((a) => _buildAnnouncement(context, a)),
        ],
      ),
    );
  }

  Widget _buildAnnouncement(BuildContext context, _Announcement a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: a.urgent ? const BorderSide(color: AppColors.secondary, width: 1.5) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: a.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(a.icon, color: a.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (a.urgent)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.emergency.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('URGENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.emergency)),
                              ),
                            Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                          ],
                        ),
                        Text(a.time, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(a.description, style: Theme.of(context).textTheme.bodyMedium),
              if (a.area != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.pin_drop_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(a.area!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Announcement {
  final String title, description, time;
  final String? area;
  final IconData icon;
  final Color color;
  final bool urgent;
  const _Announcement(this.title, this.description, this.time, this.icon, this.color, this.urgent, {this.area});
}

final _announcements = [
  const _Announcement('Gate Change — MH370', 'Flight MH370 gate has been changed from A5 to B12. Please proceed to the new gate.', '2 min ago', Icons.swap_horiz, AppColors.secondary, true, area: 'Gate A5 → Gate B12'),
  const _Announcement('Boarding Call — AK123', 'Flight AK123 is now boarding at Gate C4. All passengers please proceed to the gate.', '8 min ago', Icons.flight_takeoff, AppColors.primary, false, area: 'Gate C4'),
  const _Announcement('Security Reminder', 'All passengers must go through security screening. Ensure liquids are in containers of 100ml or less.', '15 min ago', Icons.security, AppColors.accent, false),
  const _Announcement('WiFi Service Update', 'Free WiFi now available in Terminal 1. Connect to "KLIA-Free-WiFi".', '32 min ago', Icons.wifi, AppColors.textSecondary, false),
  const _Announcement('Delay Notice — MH456', 'Flight MH456 to Singapore is delayed by approximately 45 minutes. New departure: 16:30.', '1 hr ago', Icons.schedule, AppColors.emergency, true, area: 'Gate D2'),
];
