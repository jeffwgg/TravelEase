import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';

class ProfileManagementView extends StatefulWidget {
  const ProfileManagementView({super.key});

  @override
  State<ProfileManagementView> createState() => _ProfileManagementViewState();
}

class _ProfileManagementViewState extends State<ProfileManagementView> {
  late final ProfileViewModel _profileViewModel;
  final _alertPreferencesTourKey = GlobalKey();
  final _emergencyContactsTourKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _profileViewModel = ProfileViewModel();
    _loadProfile();
  }

  @override
  void dispose() {
    _profileViewModel.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    await _profileViewModel.loadProfile();
    if (mounted) setState(() {});
  }

  Future<void> _chooseAvatarSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _uploadAvatar(source);
  }

  Future<void> _uploadAvatar(ImageSource source) async {
    final uploaded = await _profileViewModel.pickAndUploadAvatar(source);
    if (!mounted) return;
    setState(() {});
    if (uploaded) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile image updated.')));
    } else if (_profileViewModel.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_profileViewModel.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
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
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(color: Colors.white),
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
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                color: AppColors.primaryLight.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              child: _profileViewModel.isUploadingAvatar
                                  ? const Padding(
                                      padding: EdgeInsets.all(32),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : _profileViewModel.avatarUrl.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      size: 48,
                                      color: Colors.white,
                                    )
                                  : ClipOval(
                                      child: Image.network(
                                        _profileViewModel.avatarUrl,
                                        fit: BoxFit.cover,
                                        width: 96,
                                        height: 96,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.person,
                                          size: 48,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _profileViewModel.isUploadingAvatar
                                    ? null
                                    : _chooseAvatarSource,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _profileViewModel.fullName.isEmpty
                              ? 'Traveller'
                              : _profileViewModel.fullName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _profileViewModel.email,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.hearing_disabled,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_profileViewModel.nationality.isEmpty ? 'Not set' : _profileViewModel.nationality}',
                                style: const TextStyle(
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
                          _MenuItem(
                            Icons.person_outline,
                            'Edit Profile',
                            () async {
                              await context.push('/profile/edit');
                              await _loadProfile();
                            },
                          ),
                          _MenuItem(
                            Icons.tune,
                            'Accessibility Preferences',
                            () => context.push('/preferences'),
                            key: _alertPreferencesTourKey,
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildMenuSection(context, 'Safety', [
                          _MenuItem(
                            Icons.contact_phone,
                            'Emergency Contacts',
                            () => context.push('/emergency-contacts'),
                            key: _emergencyContactsTourKey,
                          ),
                          _MenuItem(
                            Icons.badge,
                            'Emergency Card',
                            () => context.push('/emergency-card'),
                          ),
                          _MenuItem(
                            Icons.graphic_eq,
                            'Environment Sound Detection',
                            () => context.push('/environment-sound-alert'),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildMenuSection(context, 'How to use TravelEase', [
                          _MenuItem(
                            Icons.home_outlined,
                            'Home & Announcements',
                            () => AppTourController.instance
                                .startHomeAnnouncementsGuide(context),
                          ),
                          _MenuItem(
                            Icons.forum_outlined,
                            'Communication',
                            () => AppTourController.instance
                                .startCommunicationGuide(context),
                          ),
                          _MenuItem(
                            Icons.health_and_safety_outlined,
                            'Assistance & Safety',
                            () => AppTourController.instance
                                .startAssistanceSafetyGuide(context),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildMenuSection(context, 'Support', [
                          _MenuItem(
                            Icons.help_outline,
                            'Help Center',
                            () => context.push('/help-center'),
                          ),
                          _MenuItem(
                            Icons.info_outline,
                            'About TravelEase',
                            () => context.push('/about'),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 32,
                                height: 32,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TravelEase v1.0.0',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  'Accessible Travel for Everyone',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final viewModel = AuthViewModel();
                              final didSignOut = await viewModel.logout();
                              final errorMessage = viewModel.errorMessage;
                              viewModel.dispose();
                              if (!context.mounted) return;
                              if (didSignOut) {
                                context.go('/auth');
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      errorMessage ?? 'Unable to sign out.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.logout,
                              color: AppColors.emergency,
                            ),
                            label: const Text(
                              'Sign Out',
                              style: TextStyle(color: AppColors.emergency),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.emergency,
                              ),
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
        ),
        Positioned.fill(
          child: AppTourCoachmark(
            feature: AppTourFeature.alertPreferencesMenu,
            targetKey: _alertPreferencesTourKey,
            title: 'Alert settings',
            message: 'Open Accessibility Preferences to configure alerts.',
          ),
        ),
        Positioned.fill(
          child: AppTourCoachmark(
            feature: AppTourFeature.emergencyContactsMenu,
            targetKey: _emergencyContactsTourKey,
            title: 'Emergency Contacts',
            message: 'Open this page to add the people we can notify.',
          ),
        ),
      ],
    );
  }

  Widget _buildMenuSection(
    BuildContext context,
    String title,
    List<_MenuItem> items,
  ) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.textMuted, letterSpacing: 0.5),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            final isLast = entry.key == items.length - 1;
            return Column(
              children: [
                ListTile(
                  key: item.key,
                  leading: Icon(item.icon, color: AppColors.primary, size: 22),
                  title: Text(item.title, style: const TextStyle(fontSize: 15)),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
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
  final Key? key;
  const _MenuItem(this.icon, this.title, this.onTap, {this.key});
}
