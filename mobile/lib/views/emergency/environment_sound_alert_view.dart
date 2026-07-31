import 'package:flutter/material.dart';
import '../../core/theme.dart';

class EnvironmentSoundAlertView extends StatefulWidget {
  const EnvironmentSoundAlertView({super.key});

  @override
  State<EnvironmentSoundAlertView> createState() => _EnvironmentSoundAlertViewState();
}

class _EnvironmentSoundAlertViewState extends State<EnvironmentSoundAlertView> {
  bool _enabled = true;
  bool _alarms = true;
  bool _sirens = true;
  bool _vehicleHorns = true;
  bool _doorbells = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Environment Sound Alert')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hearing_disabled, color: AppColors.primary, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Receive visual and vibration alerts when important sounds are detected around you.')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              secondary: const Icon(Icons.graphic_eq, color: AppColors.primary),
              title: const Text('Sound Detection'),
              subtitle: const Text('Monitor the surrounding environment'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Sounds to Detect', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                _soundSwitch('Alarms', 'Smoke alarms and warning beeps', Icons.notification_important_outlined, _alarms, (value) => setState(() => _alarms = value)),
                const Divider(height: 1),
                _soundSwitch('Emergency Sirens', 'Emergency vehicle and venue sirens', Icons.emergency_outlined, _sirens, (value) => setState(() => _sirens = value)),
                const Divider(height: 1),
                _soundSwitch('Vehicle Horns', 'Nearby car and transport horns', Icons.directions_car_outlined, _vehicleHorns, (value) => setState(() => _vehicleHorns = value)),
                const Divider(height: 1),
                _soundSwitch('Doorbells', 'Doorbells and entrance chimes', Icons.doorbell_outlined, _doorbells, (value) => setState(() => _doorbells = value)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundSwitch(String title, String subtitle, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: _enabled ? onChanged : null,
      secondary: Icon(icon, color: _enabled ? AppColors.primary : AppColors.textMuted),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
