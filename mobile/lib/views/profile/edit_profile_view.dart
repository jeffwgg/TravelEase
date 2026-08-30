import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../viewmodels/profile_viewmodel.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final ProfileViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel()..loadProfile();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.isLoading && _viewModel.profile == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextField(
                  controller: _viewModel.fullNameController,
                  enabled: !_viewModel.isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(_viewModel.nationality),
                  initialValue: _viewModel.nationality.isEmpty
                      ? null
                      : _viewModel.nationality,
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    prefixIcon: Icon(Icons.public),
                  ),
                  items: _nationalityOptions(_viewModel.nationality)
                      .map(
                        (nationality) => DropdownMenuItem(
                          value: nationality,
                          child: Text(nationality),
                        ),
                      )
                      .toList(),
                  onChanged: _viewModel.isLoading
                      ? null
                      : (value) {
                          if (value != null) {
                            _viewModel.nationalityController.text = value;
                          }
                        },
                ),
                const SizedBox(height: 28),
                Text(
                  'Change Password',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _viewModel.currentPasswordController,
                  enabled: !_viewModel.isChangingPassword,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: Icon(Icons.lock_person_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _viewModel.newPasswordController,
                  enabled: !_viewModel.isChangingPassword,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _viewModel.confirmPasswordController,
                  enabled: !_viewModel.isChangingPassword,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _changePassword(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _viewModel.isChangingPassword
                      ? null
                      : _changePassword,
                  child: _viewModel.isChangingPassword
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                ),
                if (_viewModel.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _viewModel.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.emergency),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _viewModel.isLoading ? null : _save,
                  child: _viewModel.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<String> _nationalityOptions(String currentNationality) {
    const nationalities = [
      'Malaysian',
      'Australian',
      'Bangladeshi',
      'British',
      'Bruneian',
      'Cambodian',
      'Canadian',
      'Chinese',
      'Filipino',
      'French',
      'German',
      'Indian',
      'Indonesian',
      'Japanese',
      'Myanmar',
      'Nepalese',
      'New Zealander',
      'Pakistani',
      'Singaporean',
      'South Korean',
      'Sri Lankan',
      'Thai',
      'Vietnamese',
      'Other',
    ];
    if (currentNationality.isEmpty ||
        nationalities.contains(currentNationality)) {
      return nationalities;
    }
    return [currentNationality, ...nationalities];
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (await _viewModel.updateProfile() && mounted) context.pop();
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();
    if (await _viewModel.changePassword() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
    }
  }
}
