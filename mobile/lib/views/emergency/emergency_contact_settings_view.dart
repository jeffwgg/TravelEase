import 'package:flutter/material.dart';
import '../../core/theme.dart';

class EmergencyContactSettingsView extends StatelessWidget {
  const EmergencyContactSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final contacts = [
      _Contact('Sarah Wong', 'Mother', '+60 12-345 6789', true),
      _Contact('David Wong', 'Father', '+60 13-456 7890', true),
      _Contact('Malaysian Deaf Association', 'Organization', '+60 3-7956 3700', false),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton.icon(
            onPressed: () => _showAddContact(context),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.secondaryLight.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.secondaryDark, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'These contacts will be notified during SOS emergencies with your location and emergency info.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Emergency Contacts (${contacts.length}/5)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...contacts.map((c) => _buildContactCard(context, c)),
          const SizedBox(height: 24),
          // SOS Message Preview
          Text('SOS Message Preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emergencyLight.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('🚨 EMERGENCY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emergency)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'I am deaf/hard-of-hearing and need help. I am at KLIA Terminal 1, Gate A5. Please contact me via text message.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('Location will be shared', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(BuildContext context, _Contact contact) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: contact.isPrimary
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                contact.isPrimary ? Icons.person : Icons.business,
                color: contact.isPrimary ? AppColors.primary : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Primary', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(contact.relation, style: Theme.of(context).textTheme.bodySmall),
                  Text(contact.phone, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'primary', child: Text('Set as Primary')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.emergency))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddContact(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Emergency Contact', style: Theme.of(ctx).textTheme.headlineMedium),
            const SizedBox(height: 24),
            const TextField(decoration: InputDecoration(hintText: 'Contact Name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(hintText: 'Relationship', prefixIcon: Icon(Icons.group_outlined))),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(hintText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)), keyboardType: TextInputType.phone),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Save Contact')),
          ],
        ),
      ),
    );
  }
}

class _Contact {
  final String name, relation, phone;
  final bool isPrimary;
  const _Contact(this.name, this.relation, this.phone, this.isPrimary);
}
