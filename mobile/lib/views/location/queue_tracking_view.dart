import 'package:flutter/material.dart';
import '../../core/theme.dart';

class QueueTrackingView extends StatelessWidget {
  const QueueTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue Tracking'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Your queue status
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                const Text('Your Queue Number', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('A-047', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 4)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: _buildQueueStat('Now Serving', 'A-042')),
                    Container(width: 1, height: 40, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                    Expanded(child: _buildQueueStat('People Ahead', '5')),
                    Container(width: 1, height: 40, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                    Expanded(child: _buildQueueStat('Est. Wait', '~15 min')),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.vibration, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('You will be notified when it\'s your turn', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Queue line information
          Text('Queue Line Information', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow(Icons.confirmation_number_outlined, 'Queue Line', 'A Series'),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.support_agent_outlined, 'Service', 'General Ticketing & Check-in'),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.meeting_room_outlined, 'Counter', 'Counter #1 — Main Service Desk'),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.location_on_outlined, 'Service Area', 'Departure Hall A, Level 3'),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.schedule_outlined, 'Operating Hours', '6:00 AM – 11:00 PM'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildQueueStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  static Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
