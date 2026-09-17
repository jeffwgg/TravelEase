import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../models/entities/environment_sound.dart';
import '../../viewmodels/environment_sound_alert_viewmodel.dart';
import '../../widgets/app_message_banner.dart';

class EnvironmentSoundAlertView extends StatefulWidget {
  const EnvironmentSoundAlertView({super.key});

  @override
  State<EnvironmentSoundAlertView> createState() =>
      _EnvironmentSoundAlertViewState();
}

class _EnvironmentSoundAlertViewState extends State<EnvironmentSoundAlertView> {
  static const _alertTypes = <EnvironmentSoundType>[
    EnvironmentSoundType.alarm,
    EnvironmentSoundType.siren,
    EnvironmentSoundType.vehicleHorn,
    EnvironmentSoundType.doorbell,
    EnvironmentSoundType.speechAnnouncement,
  ];

  final _viewModel = EnvironmentSoundAlertViewModel();
  Set<EnvironmentSoundType> get _enabledTypes => _viewModel.enabledTypes;
  List<EnvironmentSoundDetection> get _history => _viewModel.history;
  StreamSubscription<EnvironmentSoundDetection>? _displayAlertSubscription;

  SoundSensitivity get _sensitivity => _viewModel.sensitivity;
  SoundDetectionSnapshot get _snapshot => _viewModel.snapshot;
  bool get _enabled => _viewModel.enabled;
  bool get _loading => _viewModel.loading;
  bool get _changingMonitoring => _viewModel.changingMonitoring;
  String? get _message => _viewModel.message;
  AppMessageType get _messageType => switch (_viewModel.messageType) {
    EnvironmentSoundMessageType.error => AppMessageType.error,
    EnvironmentSoundMessageType.success => AppMessageType.success,
    EnvironmentSoundMessageType.information => AppMessageType.information,
  };

  @override
  void initState() {
    super.initState();
    _displayAlertSubscription = _viewModel.displayAlerts.listen(
      _showDetectionAlert,
    );
    _viewModel.initialize();
  }

  Future<void> _showDetectionAlert(EnvironmentSoundDetection detection) async {
    if (!mounted) return;
    for (var pulse = 0; pulse < 3; pulse++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _colorFor(detection.type),
        icon: Icon(_iconFor(detection.type), color: Colors.white, size: 52),
        title: Text(
          '${detection.type.title.toUpperCase()} DETECTED',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'TravelEase heard ${detection.modelLabel.toLowerCase()} nearby. Check your surroundings and follow visible safety instructions.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _colorFor(detection.type),
            ),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_displayAlertSubscription?.cancel());
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Environment Sound Detection')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildIntroduction(),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    AppMessageBanner(
                      message: _message!,
                      type: _messageType,
                      onDismiss: _viewModel.dismissMessage,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildMonitoringCard(),
                  const SizedBox(height: 12),
                  _buildAnnouncementCaptureGuide(),
                  const SizedBox(height: 20),
                  _sectionTitle('Sounds to Detect'),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: _alertTypes.indexed.map((entry) {
                        final (index, type) = entry;
                        return Column(
                          children: [
                            if (index > 0) const Divider(height: 1),
                            SwitchListTile(
                              value: _enabledTypes.contains(type),
                              onChanged: (value) =>
                                  _viewModel.setSoundEnabled(type, value),
                              secondary: Icon(
                                _iconFor(type),
                                color: _enabledTypes.contains(type)
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                              title: Text(type.title),
                              subtitle: Text(type.description),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Detection Sensitivity'),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: DropdownButtonFormField<SoundSensitivity>(
                        initialValue: _sensitivity,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          filled: false,
                        ),
                        items: SoundSensitivity.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('${value.title} sensitivity'),
                              ),
                            )
                            .toList(),
                        onChanged: _viewModel.setSensitivity,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Recent Alerts'),
                      if (_history.isNotEmpty)
                        TextButton(
                          onPressed: _viewModel.clearHistory,
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.history, color: AppColors.textMuted),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Detected sounds will appear here.'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._history.take(10).map(_buildHistoryItem),
                  const SizedBox(height: 20),
                  Text(
                    'Sound recognition runs on this device and does not save microphone recordings. Monitoring continues while the app is in the background, but stops if the operating system terminates the app. Detection may be affected by background noise and should not replace official safety systems.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _buildIntroduction() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hearing_disabled, color: AppColors.primary, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Receive visual and vibration alerts when important sounds are detected around you.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCaptureGuide() {
    return Card(
      color: AppColors.accent.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: const Text(
                'Spoken announcements are captured on this device and appear in Spoken Announcements. No venue session is needed.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _changingMonitoring ? null : _viewModel.setMonitoring,
              secondary: _changingMonitoring
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Icon(
                      _enabled ? Icons.mic : Icons.mic_off_outlined,
                      color: _enabled ? AppColors.primary : AppColors.textMuted,
                    ),
              title: Text(
                _enabled
                    ? 'Listening for important sounds'
                    : 'Sound detection is off',
              ),
              subtitle: Text(
                _enabled
                    ? 'On-device monitoring is active'
                    : 'Switch on to begin monitoring',
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _enabled
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  const Divider(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.graphic_eq,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _snapshot.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: _snapshot.inputLevel,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(6),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(_snapshot.score * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(EnvironmentSoundDetection detection) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: _colorFor(detection.type).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _iconFor(detection.type),
            color: _colorFor(detection.type),
            size: 21,
          ),
        ),
        title: Text(
          detection.type.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${detection.modelLabel} • ${(detection.score * 100).round()}% match',
        ),
        trailing: Text(
          _timeLabel(detection.detectedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium);

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

  String _timeLabel(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
