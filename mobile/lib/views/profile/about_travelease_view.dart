import 'package:flutter/material.dart';

import '../../core/theme.dart';

class AboutTravelEaseView extends StatelessWidget {
  const AboutTravelEaseView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About TravelEase')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/logo.png', width: 80, height: 80),
                ),
                const SizedBox(height: 14),
                const Text(
                  'TravelEase',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Accessible Travel for Everyone',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Version 1.0.0',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _AboutCard(
            icon: Icons.explore_outlined,
            title: 'Our Purpose',
            body:
                'TravelEase makes journeys safer and clearer by bringing communication, assistance, alerts, and emergency information into one accessible travel companion.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: Icons.accessibility_new,
            title: 'Our Accessibility Mission',
            body:
                'We aim to reduce communication barriers and support confident, independent travel through visual, text-based, vibration, and assistive features.',
          ),
          const SizedBox(height: 20),
          Text(
            'Key Features',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const _FeatureGrid(),
          const SizedBox(height: 20),
          const _AboutCard(
            icon: Icons.groups_outlined,
            title: 'Designed For',
            body:
                'Deaf and hard-of-hearing travellers, their emergency contacts, and anyone who benefits from clearer and more accessible communication while travelling.',
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'TravelEase v1.0.0',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    childAspectRatio: 1.3,
    children: const [
      _FeatureTile(Icons.forum_outlined, 'Accessible Communication'),
      _FeatureTile(Icons.notifications_active_outlined, 'Accessible Alerts'),
      _FeatureTile(Icons.health_and_safety_outlined, 'Emergency Safety'),
      _FeatureTile(Icons.travel_explore, 'Travel Assistance'),
    ],
  );
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
