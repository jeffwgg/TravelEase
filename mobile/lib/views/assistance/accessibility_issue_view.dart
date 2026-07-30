import 'package:flutter/material.dart';
import '../../core/theme.dart';

class AccessibilityIssueView extends StatefulWidget {
  const AccessibilityIssueView({super.key});

  @override
  State<AccessibilityIssueView> createState() => _AccessibilityIssueViewState();
}

class _AccessibilityIssueViewState extends State<AccessibilityIssueView> {
  String? _issueType;
  int _severity = 1;

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
            const TextField(
              decoration: InputDecoration(
                hintText: 'e.g., Gate A5, Reception Counter',
                prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
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
            Text('Attach Photo (Optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
                color: AppColors.surfaceVariant,
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo, color: AppColors.textMuted, size: 28),
                  SizedBox(height: 8),
                  Text('Tap to add photo', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.report),
                label: const Text('Submit Report'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, String value) {
    final selected = _issueType == value;
    return GestureDetector(
      onTap: () => setState(() => _issueType = value),
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
    final selected = _severity == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _severity = level),
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
