import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/repositories/auth_repository.dart';

enum RegistrationResult { authenticated, emailVerificationRequired }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({AuthRepository? repository})
      : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  final loginEmailController = TextEditingController();
  final loginPasswordController = TextEditingController();
  final registrationNameController = TextEditingController();
  final registrationEmailController = TextEditingController();
  final registrationPasswordController = TextEditingController();
  final registrationConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  User? get currentUser => _repository.currentUser;
  Session? get currentSession => _repository.currentSession;

  Future<bool> login() async {
    final email = loginEmailController.text.trim();
    final password = loginPasswordController.text;
    final validationError = _validateCredentials(email, password);
    if (validationError != null) {
      _setError(validationError);
      return false;
    }

    _startRequest();
    try {
      final response = await _repository.signIn(
        email: email,
        password: password,
      );
      if (response.session == null || response.user == null) {
        _setError('Sign in was not completed. Please try again.');
        return false;
      }
      _finishRequest();
      return true;
    } on AuthException catch (error) {
      _setError(_friendlyAuthError(error));
      return false;
    } catch (_) {
      _setError('Unable to sign in right now. Please check your connection.');
      return false;
    }
  }

  Future<RegistrationResult?> register() async {
    final name = registrationNameController.text.trim();
    final email = registrationEmailController.text.trim();
    final password = registrationPasswordController.text;
    final confirmPassword = registrationConfirmPasswordController.text;

    if (name.isEmpty) {
      _setError('Please enter your full name.');
      return null;
    }
    final validationError = _validateCredentials(email, password);
    if (validationError != null) {
      _setError(validationError);
      return null;
    }
    if (password != confirmPassword) {
      _setError('Passwords do not match.');
      return null;
    }

    _startRequest();
    try {
      final response = await _repository.register(
        email: email,
        password: password,
        fullName: name,
      );
      if (response.session != null) {
        _finishRequest();
        return RegistrationResult.authenticated;
      }

      _isLoading = false;
      _successMessage =
          'Account created. Please verify your email before signing in.';
      notifyListeners();
      return RegistrationResult.emailVerificationRequired;
    } on AuthException catch (error) {
      _setError(_friendlyAuthError(error));
      return null;
    } catch (_) {
      _setError(
        'Unable to create your account right now. Please check your connection.',
      );
      return null;
    }
  }

  Future<bool> logout() async {
    _startRequest();
    try {
      await _repository.signOut();
      _finishRequest();
      return true;
    } on AuthException catch (error) {
      _setError(_friendlyAuthError(error));
      return false;
    } catch (_) {
      _setError('Unable to sign out right now. Please try again.');
      return false;
    }
  }

  void clearMessages() {
    if (_errorMessage == null && _successMessage == null) return;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  String? _validateCredentials(String email, String password) {
    if (email.isEmpty) return 'Please enter your email address.';
    if (!_isValidEmail(email)) return 'Please enter a valid email address.';
    if (password.isEmpty) return 'Please enter your password.';
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  bool _isValidEmail(String email) => RegExp(
        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
      ).hasMatch(email);

  String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (message.contains('password')) {
      return 'Please use a stronger password with at least 6 characters.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'Authentication failed. Please try again.';
  }

  void _startRequest() {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  void _finishRequest() {
    _isLoading = false;
    notifyListeners();
  }

  void _setError(String message) {
    _isLoading = false;
    _errorMessage = message;
    _successMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    loginEmailController.dispose();
    loginPasswordController.dispose();
    registrationNameController.dispose();
    registrationEmailController.dispose();
    registrationPasswordController.dispose();
    registrationConfirmPasswordController.dispose();
    super.dispose();
  }
}
