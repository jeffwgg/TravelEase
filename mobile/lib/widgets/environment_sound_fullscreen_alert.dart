import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/entities/environment_sound.dart';
import '../models/repositories/environment_sound_repository.dart';
import '../services/environment_sound_detector.dart';

/// App-level alert surface for important environmental sounds. It remains
/// available while navigating between pages; background delivery is handled
/// separately by the local notification service.
class EnvironmentSoundFullscreenAlert extends StatefulWidget {
  const EnvironmentSoundFullscreenAlert({super.key, required this.child});

  final Widget child;

  @override
  State<EnvironmentSoundFullscreenAlert> createState() =>
      _EnvironmentSoundFullscreenAlertState();
}

class _EnvironmentSoundFullscreenAlertState
    extends State<EnvironmentSoundFullscreenAlert> {
  final EnvironmentSoundDetector _detector = EnvironmentSoundDetector();
  StreamSubscription<EnvironmentSoundDetection>? _subscription;
  EnvironmentSoundDetection? _detection;

  @override
  void initState() {
    super.initState();
    _subscription = _detector.alerts.listen(_show);
  }

  void _show(EnvironmentSoundDetection detection) {
    if (_detection != null ||
        detection.type == EnvironmentSoundType.speechAnnouncement) {
      return;
    }
    setState(() => _detection = detection);
    unawaited(HapticFeedback.heavyImpact());
  }

  void _dismiss() => setState(() => _detection = null);

  Future<void> _turnOff(EnvironmentSoundType type) async {
    final preferences = EnvironmentSoundPreferences();
    final types = await preferences.loadTypes();
    types.remove(type);
    await preferences.saveSettings(
      enabled: await preferences.loadEnabled(),
      types: types,
      sensitivity: await preferences.loadSensitivity(),
    );
    _detector.updateConfiguration(
      enabledTypes: types,
      sensitivity: await preferences.loadSensitivity(),
    );
    if (mounted) _dismiss();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detection = _detection;
    if (detection == null) return widget.child;
    final color = _colorFor(detection.type);
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: 0.76),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    color: color,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconFor(detection.type),
                            color: Colors.white,
                            size: 62,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '${detection.type.title.toUpperCase()} DETECTED',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'TravelEase heard ${detection.modelLabel.toLowerCase()} nearby. Check your surroundings and follow visible safety instructions.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _dismiss,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: color,
                            ),
                            child: const Text('I understand'),
                          ),
                          TextButton(
                            onPressed: () => _turnOff(detection.type),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            child: Text('Turn off ${detection.type.title}'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(EnvironmentSoundType type) => switch (type) {
    EnvironmentSoundType.alarm => Icons.notification_important_outlined,
    EnvironmentSoundType.siren => Icons.emergency_outlined,
    EnvironmentSoundType.vehicleHorn => Icons.directions_car_outlined,
    EnvironmentSoundType.doorbell => Icons.doorbell_outlined,
    EnvironmentSoundType.speechAnnouncement => Icons.campaign_outlined,
  };

  Color _colorFor(EnvironmentSoundType type) => switch (type) {
    EnvironmentSoundType.alarm ||
    EnvironmentSoundType.siren => AppColors.emergency,
    EnvironmentSoundType.vehicleHorn => AppColors.secondaryDark,
    EnvironmentSoundType.doorbell => AppColors.accent,
    EnvironmentSoundType.speechAnnouncement => AppColors.primary,
  };
}
