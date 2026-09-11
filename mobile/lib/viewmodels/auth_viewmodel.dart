import 'dart:async';

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
  final registrationNationalityController = TextEditingController();
  final registrationEmailController = TextEditingController();
  final registrationPasswordController = TextEditingController();
  final registrationConfirmPasswordController = TextEditingController();
  final resetEmailController = TextEditingController();
  final resetPasswordController = TextEditingController();
  final resetConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  Timer? _errorTimer;
  bool _disposed = false;

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
    final nationality = registrationNationalityController.text.trim();
    final email = registrationEmailController.text.trim();
    final password = registrationPasswordController.text;
    final confirmPassword = registrationConfirmPasswordController.text;

    if (name.length < 2 || name.length > 80) {
      _setError('Full name must be between 2 and 80 characters.');
      return null;
    }
    if (nationality.isEmpty) {
      _setError('Please enter your nationality.');
      return null;
    }
    if (nationality.length > 80) {
      _setError('Nationality must be 80 characters or fewer.');
      return null;
    }
    final validationError =
        _validateEmail(email) ?? _validateNewPassword(password);
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
        nationality: nationality,
      );
      if (response.user != null &&
          (response.user!.identities?.isEmpty ?? false)) {
        _setError('An account with this email already exists.');
        return null;
      }
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

  Future<bool> sendPasswordResetEmail() async {
    final email = resetEmailController.text.trim();
    final validationError = _validateEmail(email);
    if (validationError != null) {
      _setError(validationError);
      return false;
    }
    _startRequest();
    try {
      await _repository.sendPasswordResetEmail(email);
      _isLoading = false;
      _successMessage =
          'If an account exists for this email, a password reset link has been sent.';
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      _setError(_friendlyPasswordResetError(error));
      return false;
    } catch (_) {
      _setError(
        'Unable to request a password reset. Check your connection and try again.',
      );
      return false;
    }
  }

  Future<bool> updatePassword() async {
    final password = resetPasswordController.text;
    final confirmation = resetConfirmPasswordController.text;
    final validationError = _validateNewPassword(password);
    if (validationError != null) {
      _setError(validationError);
      return false;
    }
    if (password != confirmation) {
      _setError('Passwords do not match.');
      return false;
    }
    _startRequest();
    try {
      final response = await _repository.updatePassword(password);
      if (response.user == null) {
        _setError(
          'The reset link is invalid or has expired. Request a new one.',
        );
        return false;
      }
      _isLoading = false;
      _successMessage = 'Your password has been updated successfully.';
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      _setError(_friendlyPasswordResetError(error));
      return false;
    } catch (_) {
      _setError('Unable to update your password. Check your connection.');
      return false;
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
    _errorTimer?.cancel();
    _errorTimer = null;
    if (_errorMessage == null && _successMessage == null) return;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  String? _validateCredentials(String email, String password) {
    final emailError = _validateEmail(email);
    if (emailError != null) return emailError;
    if (password.isEmpty) return 'Please enter your password.';
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Please enter your email address.';
    if (email.length > 254 || !_isValidEmail(email)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validateNewPassword(String password) {
    if (password.isEmpty) return 'Please enter your password.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include uppercase, lowercase, and a number.';
    }
    return null;
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already exists')) {
      return 'An account with this email already exists.';
    }
    if (message.contains('password')) {
      return 'Please use a password with at least 8 characters, including uppercase, lowercase, and a number.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'Authentication failed. Please try again.';
  }

  String _friendlyPasswordResetError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate limit') ||
        message.contains('too many') ||
        error.statusCode == '429') {
      return 'Too many reset requests. Please wait before trying again.';
    }
    if (message.contains('expired') ||
        message.contains('invalid') ||
        message.contains('session')) {
      return 'The password reset request is invalid or has expired.';
    }
    if (message.contains('email')) {
      return 'Supabase could not process this email address.';
    }
    return 'Unable to process the password reset request. Please try again.';
  }

  void _startRequest() {
    _errorTimer?.cancel();
    _errorTimer = null;
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
    _errorTimer?.cancel();
    _isLoading = false;
    _errorMessage = message;
    _successMessage = null;
    notifyListeners();
    _errorTimer = Timer(const Duration(seconds: 10), () {
      if (_disposed || _errorMessage != message) return;
      _errorMessage = null;
      _errorTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    loginEmailController.dispose();
    loginPasswordController.dispose();
    registrationNameController.dispose();
    registrationNationalityController.dispose();
    registrationEmailController.dispose();
    registrationPasswordController.dispose();
    registrationConfirmPasswordController.dispose();
    resetEmailController.dispose();
    resetPasswordController.dispose();
    resetConfirmPasswordController.dispose();
    super.dispose();
  }
}
