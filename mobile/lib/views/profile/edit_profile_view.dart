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
                TextField(
                  controller: _viewModel.nationalityController,
                  enabled: !_viewModel.isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    prefixIcon: Icon(Icons.public),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(_viewModel.preferredCommunication),
                  initialValue: _viewModel.preferredCommunication,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Communication',
                    prefixIcon: Icon(Icons.forum_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text / Chat')),
                    DropdownMenuItem(value: 'sign_language', child: Text('Sign Language')),
                    DropdownMenuItem(value: 'speech_to_text', child: Text('Speech to Text')),
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (await _viewModel.updateProfile() && mounted) context.pop();
  }
}
