import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PreferencesView extends StatefulWidget {
  const PreferencesView({super.key});

  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  bool _visualAlerts = true;
  bool _vibrationAlerts = true;
  bool _flashAlerts = false;
  bool _autoCaption = true;
  bool _largeCaptions = false;
  bool _highContrast = false;
  double _captionSize = 16;
  String _language = 'en';
  String _signLanguage = 'bim';
  String _commMethod = 'sign';

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Communication Method
          _buildSectionHeader('Communication Method'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRadioOption('Sign Language', 'sign', _commMethod, (v) => setState(() => _commMethod = v!)),
                  _buildRadioOption('Written Text', 'text', _commMethod, (v) => setState(() => _commMethod = v!)),
                  _buildRadioOption('Speech-to-Text', 'stt', _commMethod, (v) => setState(() => _commMethod = v!)),
                  _buildRadioOption('Combined (All)', 'all', _commMethod, (v) => setState(() => _commMethod = v!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign Language
          _buildSectionHeader('Sign Language'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDropdown('Primary Sign Language', _signLanguage, [
                    const DropdownMenuItem(value: 'bim', child: Text('BIM (Malaysian Sign Language)')),
                    const DropdownMenuItem(value: 'asl', child: Text('ASL (American Sign Language)')),
                  ], (v) => setState(() => _signLanguage = v!)),
                  const SizedBox(height: 16),
                  _buildDropdown('Display Language', _language, [
                    const DropdownMenuItem(value: 'en', child: Text('English')),
                    const DropdownMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
                    const DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ], (v) => setState(() => _language = v!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Alert Preferences
          _buildSectionHeader('Alert Preferences'),
          Card(
            child: Column(
              children: [
                _buildSwitch('Visual Alerts', 'On-screen visual notifications', Icons.visibility, _visualAlerts, (v) => setState(() => _visualAlerts = v)),
                const Divider(height: 1, indent: 56),
                _buildSwitch('Vibration Alerts', 'Haptic feedback for alerts', Icons.vibration, _vibrationAlerts, (v) => setState(() => _vibrationAlerts = v)),
                const Divider(height: 1, indent: 56),
                _buildSwitch('Flash Alerts', 'Camera flash for emergencies', Icons.flash_on, _flashAlerts, (v) => setState(() => _flashAlerts = v)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Caption Settings
          _buildSectionHeader('Caption Settings'),
          Card(
            child: Column(
              children: [
                _buildSwitch('Auto-Caption', 'Automatically caption speech', Icons.closed_caption, _autoCaption, (v) => setState(() => _autoCaption = v)),
                const Divider(height: 1, indent: 56),
                _buildSwitch('Large Captions', 'Increase caption text size', Icons.text_increase, _largeCaptions, (v) => setState(() => _largeCaptions = v)),
                const Divider(height: 1, indent: 56),
                _buildSwitch('High Contrast', 'Bold text on dark background', Icons.contrast, _highContrast, (v) => setState(() => _highContrast = v)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Caption Size', style: Theme.of(context).textTheme.bodyMedium),
                          Text('${_captionSize.round()}px', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Slider(
                        value: _captionSize,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _captionSize = v),
                      ),
                      // Preview
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _highContrast ? Colors.black : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Caption preview text',
                          style: TextStyle(
                            fontSize: _captionSize,
                            fontWeight: _largeCaptions ? FontWeight.w700 : FontWeight.w400,
                            color: _highContrast ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Save Preferences'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildSwitch(String title, String subtitle, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      secondary: Icon(icon, color: AppColors.primary, size: 22),
      value: value,
      activeColor: AppColors.primary,
      onChanged: onChanged,
    );
  }

  Widget _buildRadioOption(String title, String value, String groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      value: value,
      groupValue: groupValue,
      activeColor: AppColors.primary,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildDropdown(String label, String value, List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}
