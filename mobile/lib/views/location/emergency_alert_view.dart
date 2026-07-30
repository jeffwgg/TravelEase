import 'package:flutter/material.dart';
import '../../core/theme.dart';

class EmergencyAlertView extends StatelessWidget {
  const EmergencyAlertView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Alerts'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        backgroundColor: AppColors.emergency.withValues(alpha: 0.05),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active alert
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.emergency, AppColors.emergency.withValues(alpha: 0.85)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: AppColors.emergency.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text('FIRE ALARM DETECTED', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('A fire alarm has been triggered in your area. Please follow evacuation procedures.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.location_on, color: Colors.white, size: 20),
                            SizedBox(height: 4),
                            Text('Terminal 1\nZone A', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.access_time, color: Colors.white, size: 20),
                            SizedBox(height: 4),
                            Text('Detected\n30 sec ago', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.sos),
                    label: const Text('Activate SOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.emergency,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sound detection
          Text('Sound Detection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Monitoring environmental sounds in your area', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          _buildSoundCard(context, Icons.notifications_active, 'Fire Alarm', 'High frequency alarm', AppColors.emergency, 0.92),
          _buildSoundCard(context, Icons.campaign, 'PA System', 'Public announcement', AppColors.secondary, 0.45),
          _buildSoundCard(context, Icons.warning_amber, 'Siren', 'Emergency vehicle', AppColors.emergency, 0.12),
          _buildSoundCard(context, Icons.sensor_door, 'Door Knock', 'Knocking detected', AppColors.accent, 0.0),
          _buildSoundCard(context, Icons.volume_up, 'Horn', 'Vehicle horn', AppColors.textSecondary, 0.0),

          const SizedBox(height: 24),
          Text('Alert History', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildAlertHistory(context, 'PA Announcement', 'Flight boarding call detected', '10 min ago', Icons.campaign),
          _buildAlertHistory(context, 'Door Knock', 'Knocking detected at Room 302', '45 min ago', Icons.sensor_door),
          _buildAlertHistory(context, 'Vehicle Horn', 'Horn detected near entrance', '2 hrs ago', Icons.directions_car),
        ],
      ),
    );
  }

  Widget _buildSoundCard(BuildContext context, IconData icon, String title, String desc, Color color, double level) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(desc, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: level,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation(level > 0.7 ? AppColors.emergency : level > 0.3 ? AppColors.secondary : AppColors.primary),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            if (level > 0.7)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('ALERT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.emergency)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertHistory(BuildContext context, String title, String desc, String time, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(desc, style: Theme.of(context).textTheme.bodySmall),
        trailing: Text(time, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
