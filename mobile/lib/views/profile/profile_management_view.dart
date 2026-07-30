import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class ProfileManagementView extends StatelessWidget {
  const ProfileManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Profile header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Profile',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.settings, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Avatar
                    Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            color: AppColors.primaryLight.withValues(alpha: 0.3),
                          ),
                          child: const Icon(Icons.person, size: 48, color: Colors.white),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Jeff Wong',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'jeff.wong@email.com',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hearing_disabled, size: 14, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Hard of Hearing',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Menu items
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildMenuSection(context, 'Account', [
                      _MenuItem(Icons.person_outline, 'Edit Profile', () => context.push('/profile/edit')),
                      _MenuItem(Icons.tune, 'Accessibility Preferences', () => context.push('/preferences')),
                      _MenuItem(Icons.language, 'Language', () {}),
                    ]),
                    const SizedBox(height: 16),
                    _buildMenuSection(context, 'Safety', [
                      _MenuItem(Icons.contact_phone, 'Emergency Contacts', () => context.push('/emergency-contacts')),
                      _MenuItem(Icons.badge, 'Emergency Card', () => context.push('/emergency-card')),
                      _MenuItem(Icons.privacy_tip_outlined, 'Privacy & Data', () {}),
                    ]),
                    const SizedBox(height: 16),
                    _buildMenuSection(context, 'Communication', [
                      _MenuItem(Icons.sign_language, 'Sign Language Pref.', () {}),
                      _MenuItem(Icons.record_voice_over, 'TTS Voice Settings', () {}),
                      _MenuItem(Icons.closed_caption, 'Caption Settings', () {}),
                    ]),
                    const SizedBox(height: 16),
                    _buildMenuSection(context, 'Support', [
                      _MenuItem(Icons.help_outline, 'Help Center', () {}),
                      _MenuItem(Icons.feedback_outlined, 'Send Feedback', () {}),
                      _MenuItem(Icons.info_outline, 'About TravelEase', () {}),
                    ]),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset('assets/logo.png', width: 32, height: 32),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TravelEase v1.0.0',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                            Text(
                              'Accessible Travel for Everyone',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/auth'),
                        icon: const Icon(Icons.logout, color: AppColors.emergency),
                        label: const Text('Sign Out', style: TextStyle(color: AppColors.emergency)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.emergency),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context, String title, List<_MenuItem> items) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            final isLast = entry.key == items.length - 1;
            return Column(
              children: [
                ListTile(
                  leading: Icon(item.icon, color: AppColors.primary, size: 22),
                  title: Text(item.title, style: const TextStyle(fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                  onTap: item.onTap,
                ),
                if (!isLast)
                  const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _MenuItem(this.icon, this.title, this.onTap);
}
