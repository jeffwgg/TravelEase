import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../services/accessibility_alert_service.dart';
import '../../viewmodels/accessibility_preferences_viewmodel.dart';

class PreferencesView extends StatefulWidget {
  const PreferencesView({super.key});

  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  late final AccessibilityPreferencesViewModel _viewModel;
  final _alertService = AccessibilityAlertService();

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
                      'Full-Screen Visual Alerts',
                      'On-screen visual notifications',
                      Icons.visibility,
                      _viewModel.fullScreenAlerts,
                      (value) => _viewModel.update(
                        () => _viewModel.fullScreenAlerts = value,
                      ),
                    ),
                    _buildTestButton(
                      label: 'Test full-screen alert',
                      icon: Icons.fullscreen,
                      onPressed: _viewModel.fullScreenAlerts
                          ? _testFullScreenAlert
                          : null,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Vibration Alerts',
                      'Haptic feedback for alerts',
                      Icons.vibration,
                      _viewModel.vibration,
                      (value) =>
                          _viewModel.update(() => _viewModel.vibration = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _viewModel.vibrationStrength,
                        decoration: const InputDecoration(
                          labelText: 'Vibration Strength',
                          prefixIcon: Icon(Icons.graphic_eq),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'light',
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: 'medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(
                            value: 'strong',
                            child: Text('Strong'),
                          ),
                        ],
                        onChanged: _viewModel.vibration
                            ? (value) {
                                if (value != null) {
                                  _viewModel.update(
                                    () => _viewModel.vibrationStrength = value,
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                    _buildTestButton(
                      label: 'Test vibration',
                      icon: Icons.vibration,
                      onPressed: _viewModel.vibration ? _testVibration : null,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'Flash Alerts',
                      'Camera flash for emergencies',
                      Icons.flash_on,
                      _viewModel.flashAlerts,
                      (value) => _viewModel.update(
                        () => _viewModel.flashAlerts = value,
                      ),
                    ),
                    _buildTestButton(
                      label: 'Test flash',
                      icon: Icons.flash_on,
                      onPressed: _viewModel.flashAlerts ? _testFlash : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Caption Settings'),
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.text_increase,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 18),
                              const Expanded(
                                child: Text(
                                  'Caption Size',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '${_viewModel.captionSize.round()} px',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _viewModel.captionSize,
                            min: 12,
                            max: 28,
                            divisions: 8,
                            activeColor: AppColors.primary,
                            label: '${_viewModel.captionSize.round()} px',
                            onChanged: (value) => _viewModel.update(
                              () => _viewModel.captionSize = value,
                            ),
                          ),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Small · 12 px'),
                              Text('Large · 28 px'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitch(
                      'High Contrast',
                      'Bold text on dark background',
                      Icons.contrast,
                      _viewModel.highContrast,
                      (value) => _viewModel.update(
                        () => _viewModel.highContrast = value,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _viewModel.highContrast
                                  ? Colors.black
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Caption preview text',
                              style: TextStyle(
                                fontSize: _viewModel.captionSize,
                                fontWeight: _viewModel.highContrast
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: _viewModel.highContrast
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
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
              ElevatedButton(
                onPressed: _viewModel.isSaving ? null : _save,
                child: _viewModel.isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Preferences'),
              ),
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

  Widget _buildTestButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  void _testFullScreenAlert() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: AppColors.emergency,
        child: SafeArea(
          child: InkWell(
            onTap: () => Navigator.pop(dialogContext),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 96,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'VISUAL ALERT TEST',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _viewModel.captionSize + 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap anywhere to dismiss',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testVibration() async {
    await _runHardwareTest(
      () => _alertService.testVibration(_viewModel.vibrationStrength),
      'Vibration test sent (${_viewModel.vibrationStrength}).',
    );
  }

  Future<void> _testFlash() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (!status.isGranted) {
      _showMessage('Allow camera permission to test the flashlight.');
      return;
    }
    await _runHardwareTest(
      _alertService.testFlash,
      'Flashlight test started for 1 second.',
    );
  }

  Future<void> _runHardwareTest(
    Future<void> Function() test,
    String successMessage,
  ) async {
    try {
      await test();
      _showMessage(successMessage);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'This test is unavailable on this device.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (await _viewModel.save() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accessibility preferences saved.')),
      );
      context.pop();
    }
  }
}
