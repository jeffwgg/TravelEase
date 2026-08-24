import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../viewmodels/profile_viewmodel.dart';

class ProfileSetupView extends StatefulWidget {
  const ProfileSetupView({super.key});

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late final ProfileViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel()..initializeFromAuthenticatedUser();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Up Your Profile')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell us a little about yourself',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This helps TravelEase personalize communication during your journey.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _viewModel.fullNameController,
                    enabled: !_viewModel.isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _viewModel.nationalityController,
                    enabled: !_viewModel.isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nationality',
                      prefixIcon: Icon(Icons.public),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _viewModel.primaryLanguageController,
                    enabled: !_viewModel.isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Primary Language',
                      prefixIcon: Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _viewModel.secondaryLanguageController,
                    enabled: !_viewModel.isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Secondary Language (Optional)',
                      prefixIcon: Icon(Icons.translate),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _viewModel.preferredCommunication,
                    decoration: const InputDecoration(
                      labelText: 'Preferred Communication',
                      prefixIcon: Icon(Icons.forum_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'text',
                        child: Text('Text / Chat'),
                      ),
                      DropdownMenuItem(
                        value: 'sign_language',
                        child: Text('Sign Language'),
                      ),
                      DropdownMenuItem(
                        value: 'speech_to_text',
                        child: Text('Speech to Text'),
                      ),
                    ],
                    onChanged: _viewModel.isLoading
                        ? null
                        : _viewModel.setPreferredCommunication,
                  ),
                  if (_viewModel.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _viewModel.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.emergency,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _viewModel.isLoading ? null : _saveProfile,
                    child: _viewModel.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue to TravelEase'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (await _viewModel.saveProfile() && mounted) {
      context.go('/home');
    }
  }
}
