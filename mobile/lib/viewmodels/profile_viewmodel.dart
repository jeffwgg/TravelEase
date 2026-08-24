import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/repositories/auth_repository.dart';
import '../models/repositories/profile_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    ProfileRepository? profileRepository,
    AuthRepository? authRepository,
  })  : _profileRepository = profileRepository ?? ProfileRepository(),
        _authRepository = authRepository ?? AuthRepository();

  final ProfileRepository _profileRepository;
  final AuthRepository _authRepository;

  final fullNameController = TextEditingController();
  final nationalityController = TextEditingController();
  final primaryLanguageController = TextEditingController();
  final secondaryLanguageController = TextEditingController();

  String? _preferredCommunication;
  bool _isLoading = false;
  String? _errorMessage;

  String? get preferredCommunication => _preferredCommunication;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void initializeFromAuthenticatedUser() {
    final metadata = _authRepository.currentUser?.userMetadata;
    final fullName = metadata?['full_name'];
    if (fullName is String && fullNameController.text.isEmpty) {
      fullNameController.text = fullName;
    }
  }

  void setPreferredCommunication(String? value) {
    _preferredCommunication = value;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String> authenticatedDestination() async {
    if (_authRepository.currentUser == null ||
        _authRepository.currentSession == null) {
      return '/auth';
    }

    try {
      final isComplete =
          await _profileRepository.isCurrentUserProfileComplete();
      return isComplete ? '/home' : '/profile-setup';
    } catch (_) {
      // A missing profile or a profile that predates completion tracking must
      // go through setup rather than bypassing required traveller data.
      return '/profile-setup';
    }
  }

  Future<bool> saveProfile() async {
    final fullName = fullNameController.text.trim();
    final nationality = nationalityController.text.trim();
    final primaryLanguage = primaryLanguageController.text.trim();
    final secondaryLanguage = secondaryLanguageController.text.trim();

    if (fullName.isEmpty) return _fail('Please enter your full name.');
    if (nationality.isEmpty) return _fail('Please enter your nationality.');
    if (primaryLanguage.isEmpty) {
      return _fail('Please enter your primary language.');
    }
    if (_preferredCommunication == null) {
      return _fail('Please select your preferred communication method.');
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _profileRepository.saveTravellerProfile(
        fullName: fullName,
        nationality: nationality,
        primaryLanguage: primaryLanguage,
        secondaryLanguage:
            secondaryLanguage.isEmpty ? null : secondaryLanguage,
        preferredCommunication: _preferredCommunication!,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on PostgrestException catch (error) {
      debugPrint('POSTGREST ERROR');
      debugPrint('Message: ${error.message}');
      debugPrint('Code: ${error.code}');
      debugPrint('Details: ${error.details}');
      debugPrint('Hint: ${error.hint}');
      return _fail(_friendlyDatabaseError(error));
    } on AuthException {
      return _fail('Your session has expired. Please sign in again.');
    } catch (_) {
      return _fail('Unable to save your profile. Please try again.');
    }
  }

  bool _fail(String message) {
    _isLoading = false;
    _errorMessage = message;
    notifyListeners();
    return false;
  }

  String _friendlyDatabaseError(PostgrestException error) {
    if (error.code == '42703') {
      return 'Profile setup is not configured yet. Please contact support.';
    }
    return 'Unable to save your profile. Please try again.';
  }

  @override
  void dispose() {
    fullNameController.dispose();
    nationalityController.dispose();
    primaryLanguageController.dispose();
    secondaryLanguageController.dispose();
    super.dispose();
  }
}
