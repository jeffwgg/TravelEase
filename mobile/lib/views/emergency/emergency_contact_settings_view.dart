import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../models/emergency_contact.dart';
import '../../viewmodels/emergency_contact_viewmodel.dart';

class EmergencyContactSettingsView extends StatefulWidget {
  const EmergencyContactSettingsView({super.key});

  @override
  State<EmergencyContactSettingsView> createState() =>
      _EmergencyContactSettingsViewState();
}

class _EmergencyContactSettingsViewState
    extends State<EmergencyContactSettingsView> {
  late final EmergencyContactViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = EmergencyContactViewModel()..loadContacts();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Emergency Contacts'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            TextButton.icon(
              onPressed: _viewModel.isSaving ? null : () => _showContactForm(),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add'),
            ),
          ],
        ),
        body: _viewModel.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.secondaryLight.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.secondaryDark,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'These contacts will be notified during SOS emergencies with your location and emergency info.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.secondaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Emergency Contacts (${_viewModel.contacts.length}/5)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ..._viewModel.contacts.map(_buildContactCard),
                  if (_viewModel.errorMessage != null) ...[
                    Text(
                      _viewModel.errorMessage!,
                      style: const TextStyle(color: AppColors.emergency),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'SOS Message Preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.emergencyLight.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '🚨 EMERGENCY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emergency,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'I am deaf/hard-of-hearing and need help. I am at KLIA Terminal 1, Gate A5. Please contact me via text message.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Location will be shared',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildContactCard(EmergencyContact contact) {
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
                color: contact.isPrimary
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Primary',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: contact.isVerified
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          contact.isVerified ? 'Verified' : 'Unverified',
                          style: TextStyle(
                            fontSize: 10,
                            color: contact.isVerified
                                ? AppColors.primary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.relationship,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    contact.phoneNumber,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    contact.email,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
              onSelected: (action) => _handleAction(action, contact),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!contact.isVerified)
                  const PopupMenuItem(
                    value: 'verify',
                    child: Text('Verify Contact'),
                  ),
                const PopupMenuItem(
                  value: 'primary',
                  child: Text('Set as Primary'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete',
                    style: TextStyle(color: AppColors.emergency),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(String action, EmergencyContact contact) async {
    switch (action) {
      case 'edit':
        await _showContactForm(contact: contact);
        break;
      case 'primary':
        if (!contact.isVerified) {
          _showMessage('Verify this contact before setting it as Primary.');
          return;
        }
        if (contact.isPrimary) return;
        if (await _viewModel.setPrimary(contact.id)) {
          _showMessage('${contact.name} is now the primary contact.');
        } else {
          _showError();
        }
        break;
      case 'verify':
        await _showVerification(contact);
        break;
      case 'delete':
        await _confirmDelete(contact);
        break;
    }
  }

  Future<void> _showVerification(EmergencyContact contact) async {
    if (!await _viewModel.requestVerification(contact.id)) {
      _showError();
      return;
    }
    if (!mounted) return;
    final verified = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _OtpVerificationDialog(contact: contact, viewModel: _viewModel),
    );
    if (verified == true) {
      _showMessage('${contact.name} has been verified.');
    }
  }

  Future<void> _showContactForm({EmergencyContact? contact}) async {
    if (contact == null &&
        _viewModel.contacts.length >=
            EmergencyContactViewModel.maximumContacts) {
      _showMessage('You can save up to 5 emergency contacts.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _ContactFormSheet(
        contact: contact,
        viewModel: _viewModel,
        onError: _showError,
      ),
    );
  }

  Future<void> _confirmDelete(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Delete ${contact.name} from your emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.emergency),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await _viewModel.deleteContact(contact.id)) {
      _showMessage('${contact.name} was deleted.');
    } else {
      _showError();
    }
  }

  void _showError() => _showMessage(
    _viewModel.errorMessage ?? 'Unable to update emergency contacts.',
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ContactFormSheet extends StatefulWidget {
  const _ContactFormSheet({
    required this.contact,
    required this.viewModel,
    required this.onError,
  });

  final EmergencyContact? contact;
  final EmergencyContactViewModel viewModel;
  final VoidCallback onError;

  @override
  State<_ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends State<_ContactFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contact?.name);
    _relationshipController = TextEditingController(
      text: widget.contact?.relationship,
    );
    _phoneController = TextEditingController(text: widget.contact?.phoneNumber);
    _emailController = TextEditingController(text: widget.contact?.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.contact == null
                    ? 'Add Emergency Contact'
                    : 'Edit Emergency Contact',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Contact Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => _required(value, 'Enter a contact name.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _relationshipController,
                decoration: const InputDecoration(
                  hintText: 'Relationship',
                  prefixIcon: Icon(Icons.group_outlined),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => _required(value, 'Enter a relationship.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  hintText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) => _required(value, 'Enter a phone number.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  hintText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: const Text('Save Contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter an email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final contact = widget.contact;
    final succeeded = contact == null
        ? await widget.viewModel.addContact(
            name: _nameController.text.trim(),
            relationship: _relationshipController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            email: _emailController.text.trim().toLowerCase(),
          )
        : await widget.viewModel.updateContact(
            id: contact.id,
            name: _nameController.text.trim(),
            relationship: _relationshipController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            email: _emailController.text.trim().toLowerCase(),
          );
    if (!mounted) return;
    if (succeeded) {
      Navigator.pop(context);
    } else {
      setState(() => _isSubmitting = false);
      widget.onError();
    }
  }
}

class _OtpVerificationDialog extends StatefulWidget {
  const _OtpVerificationDialog({
    required this.contact,
    required this.viewModel,
  });

  final EmergencyContact contact;
  final EmergencyContactViewModel viewModel;

  @override
  State<_OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<_OtpVerificationDialog> {
  final _controller = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Contact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the 6-digit code sent to ${widget.contact.email}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '6-digit OTP',
              errorText: _errorMessage,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _verify,
          child: const Text('Verify'),
        ),
      ],
    );
  }

  Future<void> _verify() async {
    if (_controller.text.length != 6) {
      setState(() => _errorMessage = 'Enter all 6 digits.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final succeeded = await widget.viewModel.verifyContact(
      widget.contact.id,
      _controller.text,
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = widget.viewModel.errorMessage;
      });
    }
  }
}
