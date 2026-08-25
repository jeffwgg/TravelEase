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
  Map<String, dynamic>? _profile;

  String? get preferredCommunication => _preferredCommunication;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get profile => _profile;
  String get fullName => (_profile?['full_name'] as String?) ??
      (_authRepository.currentUser?.userMetadata?['full_name'] as String?) ??
      '';
  String get email => _authRepository.currentUser?.email ?? '';
  String get nationality => (_profile?['nationality'] as String?) ?? '';
  String get preferredCommunicationValue =>
      (_profile?['preferred_communication'] as String?) ?? '';
  String get preferredCommunicationLabel {
    switch (preferredCommunicationValue) {
      case 'sign_language':
        return 'Sign Language';
      case 'speech_to_text':
        return 'Speech to Text';
      case 'text':
        return 'Text / Chat';
      default:
        return 'Not set';
    }
  }

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

  Future<void> loadProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _profile = await _profileRepository.getCurrentUserProfile();
      fullNameController.text = fullName;
      nationalityController.text = nationality;
      _preferredCommunication = preferredCommunicationValue.isEmpty
          ? null
          : preferredCommunicationValue;
    } catch (_) {
      _errorMessage = 'Unable to load your profile. Please try again.';
    }
    _isLoading = false;
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

  Future<bool> updateProfile() async {
    final fullName = fullNameController.text.trim();
    final nationality = nationalityController.text.trim();
    if (fullName.isEmpty) return _fail('Please enter your full name.');
    if (nationality.isEmpty) return _fail('Please enter your nationality.');
    if (_preferredCommunication == null) {
      return _fail('Please select your preferred communication method.');
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.updateCurrentUserProfile(
        fullName: fullName,
        nationality: nationality,
        preferredCommunication: _preferredCommunication!,
      );
      _profile = {
        ...?_profile,
        'full_name': fullName,
        'nationality': nationality,
        'preferred_communication': _preferredCommunication,
      };
      _isLoading = false;
      notifyListeners();
      return true;
    } on PostgrestException catch (error) {
      return _fail(_friendlyDatabaseError(error));
    } catch (_) {
      return _fail('Unable to update your profile. Please try again.');
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
