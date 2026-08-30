import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';

class AuthenticationView extends StatefulWidget {
  const AuthenticationView({super.key});

  @override
  State<AuthenticationView> createState() => _AuthenticationViewState();
}

class _AuthenticationViewState extends State<AuthenticationView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final AuthViewModel _viewModel;
  late final ProfileViewModel _profileViewModel;
  bool _obscurePassword = true;
  bool _obscureRegistrationPassword = true;
  bool _obscureConfirmationPassword = true;

  @override
  void initState() {
    super.initState();
    _viewModel = AuthViewModel();
    _profileViewModel = ProfileViewModel();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _viewModel.dispose();
    _profileViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              // Logo area
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/logo.png', width: 88, height: 88),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'TravelEase',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Accessible Travel for Everyone',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  onTap: (_) => setState(() {}),
                  indicator: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'Sign In'),
                    Tab(text: 'Register'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Form
              ListenableBuilder(
                listenable: Listenable.merge([_tabController, _viewModel]),
                builder: (context, _) {
                  return _tabController.index == 0
                      ? _buildLoginForm(context)
                      : _buildRegisterForm(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _viewModel.loginEmailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_viewModel.isLoading,
          decoration: const InputDecoration(
            hintText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _viewModel.loginPasswordController,
          textInputAction: TextInputAction.done,
          enabled: !_viewModel.isLoading,
          onSubmitted: (_) => _login(),
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: AppColors.textMuted,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textMuted,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _viewModel.isLoading ? null : _showForgotPasswordDialog,
            child: const Text('Forgot Password?'),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _viewModel.isLoading ? null : _login,
          child: _viewModel.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign In'),
        ),
        if (_viewModel.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_viewModel.errorMessage!, isError: true),
        ],
        if (_viewModel.successMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_viewModel.successMessage!),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'or continue with',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Expanded(child: Divider(color: AppColors.divider)),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showUnsupportedSocialLogin,
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Google'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showUnsupportedSocialLogin,
                icon: const Icon(Icons.apple, size: 20),
                label: const Text('Apple'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        // Accessibility note
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.accessibility_new,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TravelEase is designed for deaf and hard-of-hearing travelers',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _viewModel.registrationNameController,
          textInputAction: TextInputAction.next,
          enabled: !_viewModel.isLoading,
          decoration: const InputDecoration(
            hintText: 'Full Name',
            prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _viewModel.registrationEmailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_viewModel.isLoading,
          decoration: const InputDecoration(
            hintText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _viewModel.registrationPasswordController,
          textInputAction: TextInputAction.next,
          enabled: !_viewModel.isLoading,
          obscureText: _obscureRegistrationPassword,
          decoration: InputDecoration(
            hintText: 'Password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: AppColors.textMuted,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureRegistrationPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: AppColors.textMuted,
              ),
              onPressed: () => setState(() {
                _obscureRegistrationPassword = !_obscureRegistrationPassword;
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _viewModel.registrationConfirmPasswordController,
          textInputAction: TextInputAction.done,
          enabled: !_viewModel.isLoading,
          onSubmitted: (_) => _register(),
          obscureText: _obscureConfirmationPassword,
          decoration: InputDecoration(
            hintText: 'Confirm Password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: AppColors.textMuted,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmationPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: AppColors.textMuted,
              ),
              onPressed: () => setState(() {
                _obscureConfirmationPassword = !_obscureConfirmationPassword;
              }),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _viewModel.isLoading ? null : _register,
          child: _viewModel.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Account'),
        ),
        if (_viewModel.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_viewModel.errorMessage!, isError: true),
        ],
        if (_viewModel.successMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_viewModel.successMessage!),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (await _viewModel.login() && mounted) {
      final destination = await _profileViewModel.authenticatedDestination();
      if (mounted) context.go(destination);
    }
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final result = await _viewModel.register();
    if (!mounted || result == null) return;
    if (result == RegistrationResult.authenticated) {
      context.go('/profile-setup');
      return;
    }
    final email = Uri.encodeQueryComponent(
      _viewModel.registrationEmailController.text.trim(),
    );
    context.go('/check-email?email=$email');
  }

  void _showUnsupportedSocialLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Social sign in is not available yet.')),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    _viewModel.clearMessages();
    _viewModel.resetEmailController.text = _viewModel.loginEmailController.text
        .trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => AlertDialog(
          title: const Text('Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your account email and we will send you a secure reset link.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _viewModel.resetEmailController,
                enabled: !_viewModel.isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _requestPasswordReset(),
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              if (_viewModel.errorMessage != null) ...[
                const SizedBox(height: 12),
                _buildStatusMessage(_viewModel.errorMessage!, isError: true),
              ],
              if (_viewModel.successMessage != null) ...[
                const SizedBox(height: 12),
                _buildStatusMessage(_viewModel.successMessage!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _viewModel.isLoading
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: _viewModel.isLoading ? null : _requestPasswordReset,
              child: _viewModel.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Reset Link'),
            ),
          ],
        ),
      ),
    );
    _viewModel.clearMessages();
  }

  Future<void> _requestPasswordReset() async {
    FocusScope.of(context).unfocus();
    await _viewModel.sendPasswordResetEmail();
  }

  Widget _buildStatusMessage(String message, {bool isError = false}) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isError ? AppColors.emergency : AppColors.primaryDark,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
