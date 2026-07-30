import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class AssistanceRequestView extends StatefulWidget {
  const AssistanceRequestView({super.key});

  @override
  State<AssistanceRequestView> createState() => _AssistanceRequestViewState();
}

class _AssistanceRequestViewState extends State<AssistanceRequestView> {
  String? _selectedType;
  int _urgency = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Assistance'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connected venue
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Requesting help from:', style: Theme.of(context).textTheme.bodySmall),
                        const Text('KLIA Terminal 1', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () {}, child: const Text('Change')),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Request type
            Text('What do you need help with?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('Communication', Icons.chat_bubble_outline, 'communication'),
                _buildTypeChip('Finding Location', Icons.location_on_outlined, 'location'),
                _buildTypeChip('Check-in / Boarding', Icons.confirmation_number_outlined, 'checkin'),
                _buildTypeChip('Luggage Issue', Icons.luggage_outlined, 'luggage'),
                _buildTypeChip('Accessibility', Icons.accessible_outlined, 'accessibility'),
                _buildTypeChip('Emergency Info', Icons.warning_amber_outlined, 'emergency'),
                _buildTypeChip('General Help', Icons.help_outline, 'general'),
              ],
            ),
            const SizedBox(height: 24),

            // Description
            Text('Describe your situation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tell us what you need help with...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Urgency
            Text('Urgency Level', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildUrgencyOption(0, 'Low', AppColors.success),
                const SizedBox(width: 8),
                _buildUrgencyOption(1, 'Medium', AppColors.secondary),
                const SizedBox(width: 8),
                _buildUrgencyOption(2, 'High', AppColors.emergency),
              ],
            ),
            const SizedBox(height: 24),

            // Communication preference
            Text('How should staff reach you?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  RadioListTile(title: const Text('In-app Chat', style: TextStyle(fontSize: 14)), value: 'chat', groupValue: 'chat', activeColor: AppColors.primary, onChanged: (_) {}),
                  const Divider(height: 1, indent: 16),
                  RadioListTile(title: const Text('Come to my location', style: TextStyle(fontSize: 14)), value: 'location', groupValue: 'chat', activeColor: AppColors.primary, onChanged: (_) {}),
                  const Divider(height: 1, indent: 16),
                  RadioListTile(title: const Text('SMS / Text Message', style: TextStyle(fontSize: 14)), value: 'sms', groupValue: 'chat', activeColor: AppColors.primary, onChanged: (_) {}),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Share location toggle
            Card(
              child: SwitchListTile(
                title: const Text('Share my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('Helps staff find you faster', style: Theme.of(context).textTheme.bodySmall),
                secondary: const Icon(Icons.my_location, color: AppColors.primary),
                value: true,
                activeColor: AppColors.primary,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 32),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _showSubmitted(context);
                },
                icon: const Icon(Icons.send),
                label: const Text('Submit Request'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => context.push('/request-tracking'),
                child: const Text('View My Requests'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, IconData icon, String value) {
    final selected = _selectedType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgencyOption(int level, String label, Color color) {
    final selected = _urgency == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _urgency = level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.cardBorder, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? color : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubmitted(BuildContext context) {
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
            const Text('Request Submitted!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('KLIA Terminal 1 staff will respond shortly.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Request ID: #REQ-2847', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/request-tracking');
              },
              child: const Text('Track Request'),
            ),
          ),
        ],
      ),
    );
  }
}
