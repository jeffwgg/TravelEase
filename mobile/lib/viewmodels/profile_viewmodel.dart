import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/repositories/auth_repository.dart';
import '../models/repositories/profile_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    ProfileRepository? profileRepository,
    AuthRepository? authRepository,
    ImagePicker? imagePicker,
  }) : _profileRepository = profileRepository ?? ProfileRepository(),
       _authRepository = authRepository ?? AuthRepository(),
       _imagePicker = imagePicker ?? ImagePicker();

  final ProfileRepository _profileRepository;
  final AuthRepository _authRepository;
  final ImagePicker _imagePicker;

  final fullNameController = TextEditingController();
  final nationalityController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isChangingPassword = false;
  bool _isUploadingAvatar = false;
  String? _errorMessage;
  Map<String, dynamic>? _profile;

  bool get isLoading => _isLoading;
  bool get isChangingPassword => _isChangingPassword;
  bool get isUploadingAvatar => _isUploadingAvatar;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get profile => _profile;
  String get fullName =>
      (_profile?['full_name'] as String?) ??
      (_authRepository.currentUser?.userMetadata?['full_name'] as String?) ??
      '';
  String get email => _authRepository.currentUser?.email ?? '';
  String get nationality => (_profile?['nationality'] as String?) ?? '';
  String get avatarUrl =>
      (_profile?['avatar_url'] as String?) ??
      (_authRepository.currentUser?.userMetadata?['avatar_url'] as String?) ??
      '';

  void initializeFromAuthenticatedUser() {
    final fullName = _authRepository.currentUser?.userMetadata?['full_name'];
    if (fullName is String && fullNameController.text.isEmpty) {
      fullNameController.text = fullName;
    }
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _profile = await _profileRepository.getCurrentUserProfile();
      fullNameController.text = fullName;
      nationalityController.text = nationality;
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
    return '/home';
  }

  Future<bool> saveProfile() async {
    final fullName = fullNameController.text.trim();
    final nationality = nationalityController.text.trim();
    if (fullName.isEmpty) return _fail('Please enter your full name.');
    if (nationality.isEmpty) return _fail('Please enter your nationality.');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.saveTravellerProfile(
        fullName: fullName,
        nationality: nationality,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      return _fail('Your session has expired. Please sign in again.');
    } on PostgrestException catch (error) {
      return _fail(_friendlyDatabaseError(error));
    } catch (_) {
      return _fail('Unable to save your profile. Please try again.');
    }
  }

  Future<bool> updateProfile() async {
    final fullName = fullNameController.text.trim();
    final nationality = nationalityController.text.trim();
    if (fullName.isEmpty) return _fail('Please enter your full name.');
    if (nationality.isEmpty) return _fail('Please enter your nationality.');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.updateCurrentUserProfile(
        fullName: fullName,
        nationality: nationality,
      );
      _profile = {
        ...?_profile,
        'full_name': fullName,
        'nationality': nationality,
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

  Future<bool> changePassword() async {
    final currentPassword = currentPasswordController.text;
    final password = newPasswordController.text;
    final confirmation = confirmPasswordController.text;
    if (currentPassword.isEmpty) {
      return _passwordFail('Please enter your current password.');
    }
    if (password.length < 8) {
      return _passwordFail('Use at least 8 characters for your new password.');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return _passwordFail(
        'New password must include uppercase, lowercase, and a number.',
      );
    }
    if (password == currentPassword) {
      return _passwordFail(
        'New password must be different from your current password.',
      );
    }
    if (password != confirmation) {
      return _passwordFail('The password confirmation does not match.');
    }
    _isChangingPassword = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.changePassword(
        currentPassword: currentPassword,
        newPassword: password,
      );
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      _isChangingPassword = false;
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      return _passwordFail(
        message.contains('invalid login credentials')
            ? 'Your current password is incorrect.'
            : message.contains('session')
            ? 'Please sign in again before changing your password.'
            : message.contains('same')
            ? 'New password must be different from your current password.'
            : 'Unable to change your password. Check the password requirements.',
      );
    } catch (_) {
      return _passwordFail('Unable to change your password.');
    }
  }

  Future<bool> pickAndUploadAvatar(ImageSource source) async {
    debugPrint('[AvatarUpload] Opening ${source.name} image picker');
    final XFile? image;
    try {
      image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
    } catch (error, stackTrace) {
      debugPrint('[AvatarUpload] Image selection failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _errorMessage = 'Unable to open the image picker.';
      notifyListeners();
      return false;
    }
    if (image == null) {
      debugPrint('[AvatarUpload] Image selection cancelled');
      return false;
    }
    debugPrint('[AvatarUpload] Image selected: name=${image.name}');
    _isUploadingAvatar = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final extension = image.name.split('.').last.toLowerCase();
      final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
      final bytes = await image.readAsBytes();
      debugPrint(
        '[AvatarUpload] Image bytes ready: bytes=${bytes.length} '
        'contentType=$contentType',
      );
      final url = await _profileRepository.uploadAvatar(
        bytes: bytes,
        contentType: contentType,
      );
      _profile = {...?_profile, 'avatar_url': url};
      _isUploadingAvatar = false;
      notifyListeners();
      debugPrint('[AvatarUpload] Avatar flow completed successfully: $url');
      return true;
    } on StorageException catch (error) {
      _isUploadingAvatar = false;
      _errorMessage =
          'Storage upload failed (${error.statusCode ?? 'unknown'}): '
          '${error.message}';
      debugPrint(
        '[AvatarUpload] Storage failure surfaced to ViewModel: $error',
      );
      notifyListeners();
      return false;
    } catch (error, stackTrace) {
      _isUploadingAvatar = false;
      _errorMessage = 'Unable to upload your profile image.';
      debugPrint('[AvatarUpload] Avatar flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      notifyListeners();
      return false;
    }
  }

  bool _fail(String message) {
    _isLoading = false;
    _errorMessage = message;
    notifyListeners();
    return false;
  }

  bool _passwordFail(String message) {
    _isChangingPassword = false;
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
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
