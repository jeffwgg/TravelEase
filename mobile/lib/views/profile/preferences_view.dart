import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../viewmodels/accessibility_preferences_viewmodel.dart';

/// Accessibility preferences in two sections — Alert Preferences governs
/// important sound alerts, General Notification Preference governs
/// announcements, queue updates and messages together. Each section carries
/// the same three toggles: push notification, vibration and flash. Toggles
/// persist the moment they are flipped; there is no save button.
class PreferencesView extends StatefulWidget {
  const PreferencesView({super.key});

  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  late final AccessibilityPreferencesViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AccessibilityPreferencesViewModel()..load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessibility Preferences'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader('Alert Preferences'),
              Card(
                child: Column(
                  children: [
                    _buildSwitch(
                      'Enable Alert Notification',
                      'Push alert notifications when you are not in the app',
                      Icons.notifications_active,
                      _viewModel.alertNotification,
                      _viewModel.setAlertNotification,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Enable Vibration',
                      'Vibrate for alert notifications',
                      Icons.vibration,
                      _viewModel.alertVibration,
                      _viewModel.setAlertVibration,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Enable Flash',
                      'Camera torch flash for alert notifications',
                      Icons.flash_on,
                      _viewModel.alertFlash,
                      _viewModel.setAlertFlash,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('General Notification Preference'),
              Card(
                child: Column(
                  children: [
                    _buildSwitch(
                      'Enable Alert Notification',
                      'Push notifications (announcements, queue updates and '
                          'messages) when you are not in the app',
                      Icons.notifications_active,
                      _viewModel.generalNotification,
                      _viewModel.setGeneralNotification,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Enable Vibration',
                      'Vibrate for announcements, queue updates and messages',
                      Icons.vibration,
                      _viewModel.generalVibration,
                      _viewModel.setGeneralVibration,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Enable Flash',
                      'Camera torch flash for announcements, queue updates '
                          'and messages',
                      Icons.flash_on,
                      _viewModel.generalFlash,
                      _viewModel.setGeneralFlash,
                    ),
                  ],
                ),
              ),
              if (_viewModel.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _viewModel.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.emergency),
                ),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSwitch(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      secondary: Icon(icon, color: AppColors.primary, size: 22),
      value: value,
      activeThumbColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}
