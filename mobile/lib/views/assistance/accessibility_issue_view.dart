import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../viewmodels/accessibility_issue_viewmodel.dart';

class AccessibilityIssueView extends StatefulWidget {
  const AccessibilityIssueView({super.key});

  @override
  State<AccessibilityIssueView> createState() => _AccessibilityIssueViewState();
}

class _AccessibilityIssueViewState extends State<AccessibilityIssueView> {
  final _viewModel = AccessibilityIssueViewModel();
  XFile? _selectedPhoto;
  bool _analyticsConsent = false; // FR-M5-27

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    super.dispose();
  }

  // FR-M5-24: Pick photo from gallery or camera
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1280);
      if (file != null) {
        setState(() => _selectedPhoto = file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick photo: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.gallery); },
            ),
            if (_selectedPhoto != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.emergency),
                title: const Text('Remove Photo', style: TextStyle(color: AppColors.emergency)),
                onTap: () { Navigator.pop(ctx); setState(() => _selectedPhoto = null); },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    // FR-M5-27: Consent required
    if (!_analyticsConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please consent to share data for analytics to submit.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final success = await _viewModel.submitReport(venueName: 'Current Venue');
    if (success && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Report Submitted!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Thank you for reporting this accessibility barrier. The venue will be notified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _viewModel.reset();
                  setState(() { _selectedPhoto = null; _analyticsConsent = false; });
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Accessibility Issue'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Report barriers that don\'t need immediate help — like missing visual announcements or sound-only queue systems.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Issue Type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip('No Visual Announcement', Icons.volume_off_outlined, 'visual'),
                _buildChip('Sound-Only Queue', Icons.campaign_outlined, 'queue'),
                _buildChip('No Sign Language', Icons.sign_language_outlined, 'sign'),
                _buildChip('Missing Visual Alert', Icons.warning_amber_outlined, 'alert'),
                _buildChip('Inaccessible Area', Icons.accessible_forward_outlined, 'access'),
                _buildChip('Other Issue', Icons.note_alt_outlined, 'other'),
              ],
            ),
            const SizedBox(height: 24),
            Text('Location of Issue', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _viewModel.locationController,
              decoration: const InputDecoration(
                hintText: 'e.g., Gate A5, Reception Counter',
                prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _viewModel.descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe the accessibility barrier...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Severity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSeverity(0, 'Minor', 'Inconvenient but manageable', AppColors.success),
                const SizedBox(width: 8),
                _buildSeverity(1, 'Moderate', 'Significant barrier', AppColors.secondary),
                const SizedBox(width: 8),
                _buildSeverity(2, 'Severe', 'Prevents access entirely', AppColors.emergency),
              ],
            ),
            const SizedBox(height: 24),

            // FR-M5-24: Photo Upload
            Text('Attach Photo (Optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_selectedPhoto != null) ...[
              // Preview
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.file(
                      File(_selectedPhoto!.path),
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPhoto = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: GestureDetector(
                        onTap: _showPhotoOptions,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: const Text('Change', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              GestureDetector(
                onTap: _showPhotoOptions,
                child: Container(
                  width: double.infinity,
                  height: 110,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cardBorder, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surfaceVariant,
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, color: AppColors.primary, size: 32),
                      SizedBox(height: 8),
                      Text('Tap to add photo evidence', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      SizedBox(height: 2),
                      Text('Camera or Gallery', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],

            // FR-M5-27: Analytics Consent
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _analyticsConsent ? AppColors.primary.withValues(alpha: 0.5) : AppColors.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _analyticsConsent,
                    onChanged: (v) => setState(() => _analyticsConsent = v ?? false),
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _analyticsConsent = !_analyticsConsent),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'I consent to sharing this anonymised report for institutional accessibility analytics to help improve accessibility for all travellers.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Error message
            if (_viewModel.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.emergency, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _viewModel.errorMessage!,
                        style: const TextStyle(color: AppColors.emergency, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // FR-M5-27: Disabled if no consent
                onPressed: (_viewModel.isSubmitting || !_analyticsConsent) ? null : _handleSubmit,
                icon: _viewModel.isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.report),
                label: Text(_viewModel.isSubmitting ? 'Submitting...' : 'Submit Report'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            if (!_analyticsConsent)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'Consent required to submit',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, String value) {
    final selected = _viewModel.issueType == value;
    return GestureDetector(
      onTap: () => _viewModel.setIssueType(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.accent : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverity(int level, String title, String desc, Color color) {
    final selected = _viewModel.severity == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => _viewModel.setSeverity(level),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.cardBorder, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
