import 'package:flutter/material.dart';

import '../../core/theme.dart';

class HelpCenterView extends StatelessWidget {
  const HelpCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.82),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.support_agent, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How can we help?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Quick guidance for safer, more accessible travel.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Emergency Help'),
          Card(
            color: AppColors.emergency.withValues(alpha: 0.06),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emergency, color: AppColors.emergency),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'For immediate danger, contact local emergency services. Keep a verified primary contact and your Emergency Communication Card ready.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Frequently Asked Questions'),
          const Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _FaqItem(
                  question: 'How do I set up an emergency contact?',
                  answer:
                      'Open Profile, choose Emergency Contacts, then add and verify a contact. Only verified contacts can be made primary.',
                ),
                Divider(height: 1),
                _FaqItem(
                  question: 'How do I share my emergency card?',
                  answer:
                      'Open Emergency Card from Profile, confirm the saved details, and tap Share Card to use your phone\'s sharing options.',
                ),
                Divider(height: 1),
                _FaqItem(
                  question: 'How do accessible alerts work?',
                  answer:
                      'In Accessibility Preferences, enable visual, vibration, or flash alerts and use each test control to confirm it works on your device.',
                ),
                Divider(height: 1),
                _FaqItem(
                  question: 'Can I change my communication preference?',
                  answer:
                      'Yes. Open Edit Profile and select the communication method that works best for you.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Account & Profile'),
          const _HelpCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Manage your account',
            description:
                'Update personal details, change your password, or replace your profile photo from the Profile page.',
          ),
          const SizedBox(height: 12),
          const _SectionTitle('Accessibility Features'),
          const _HelpCard(
            icon: Icons.accessibility_new,
            title: 'Personalise your experience',
            description:
                'Adjust caption size and contrast, and configure full-screen, vibration, and flash alerts for your needs.',
          ),
          const SizedBox(height: 12),
          const _SectionTitle('Contact Support'),
          const _HelpCard(
            icon: Icons.contact_support_outlined,
            title: 'Need more help?',
            description:
                'Contact your TravelEase support administrator and include what you were doing, your device model, and any error message shown.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.help_outline, color: AppColors.primary),
    title: Text(
      question,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(answer)],
  );
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
