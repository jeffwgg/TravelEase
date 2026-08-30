import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/emergency_contact.dart';
import '../models/repositories/emergency_contact_repository.dart';

class EmergencyContactViewModel extends ChangeNotifier {
  EmergencyContactViewModel({EmergencyContactRepository? repository})
    : _repository = repository ?? EmergencyContactRepository();

  static const maximumContacts = 5;
  final EmergencyContactRepository _repository;

  List<EmergencyContact> contacts = const [];
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  bool _isDisposed = false;

  Future<void> loadContacts() async {
    debugPrint('[EmergencyContacts] Loading contacts');
    isLoading = true;
    errorMessage = null;
    _notifyListeners();
    try {
      contacts = await _repository.getContacts();
      debugPrint('[EmergencyContacts] Loaded ${contacts.length} contacts');
    } catch (error, stackTrace) {
      debugPrint('[EmergencyContacts] Load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage = _messageFor(error, 'Unable to load emergency contacts.');
    }
    isLoading = false;
    _notifyListeners();
  }

  Future<bool> addContact({
    required String name,
    required String relationship,
    required String phoneNumber,
    required String email,
  }) async {
    if (contacts.length >= maximumContacts) {
      return _fail('You can save up to 5 emergency contacts.');
    }
    return _save('add', () async {
      final contact = await _repository.addContact(
        name: name,
        relationship: relationship,
        phoneNumber: phoneNumber,
        email: email,
      );
      contacts = [...contacts, contact];
    });
  }

  Future<bool> updateContact({
    required String id,
    required String name,
    required String relationship,
    required String phoneNumber,
    required String email,
  }) {
    return _save('edit', () async {
      final updated = await _repository.updateContact(
        id: id,
        name: name,
        relationship: relationship,
        phoneNumber: phoneNumber,
        email: email,
      );
      contacts = [
        for (final item in contacts)
          if (item.id == id) updated else item,
      ];
    });
  }

  Future<bool> deleteContact(String id) {
    return _save('delete', () async {
      await _repository.deleteContact(id);
      contacts = contacts.where((item) => item.id != id).toList();
    });
  }

  Future<bool> setPrimary(String id) {
    final contact = contacts.where((item) => item.id == id).firstOrNull;
    if (contact == null || !contact.isVerified) {
      return Future.value(
        _fail('Verify this contact before setting it as Primary.'),
      );
    }
    return _save('set primary', () async {
      await _repository.setPrimary(id);
      contacts = [
        for (final item in contacts) item.copyWith(isPrimary: item.id == id),
      ];
      contacts = [...contacts]
        ..sort(
          (a, b) => a.isPrimary == b.isPrimary ? 0 : (a.isPrimary ? -1 : 1),
        );
    });
  }

  Future<bool> requestVerification(String contactId) {
    return _save('request verification', () async {
      await _repository.requestVerification(contactId);
    });
  }

  Future<bool> verifyContact(String contactId, String enteredCode) async {
    return _save('verify', () async {
      final verified = await _repository.verifyContact(
        id: contactId,
        code: enteredCode.trim(),
      );
      contacts = [
        for (final item in contacts)
          if (item.id == contactId) verified else item,
      ];
    });
  }

  Future<bool> _save(
    String operationName,
    Future<void> Function() operation,
  ) async {
    debugPrint('[EmergencyContacts] Starting $operationName');
    isSaving = true;
    errorMessage = null;
    _notifyListeners();
    try {
      await operation();
      debugPrint('[EmergencyContacts] Completed $operationName');
      isSaving = false;
      _notifyListeners();
      return true;
    } catch (error, stackTrace) {
      debugPrint('[EmergencyContacts] $operationName failed: $error');
      if (error is PostgrestException) {
        debugPrint(
          '[EmergencyContacts] Supabase code=${error.code} '
          'message=${error.message} details=${error.details} hint=${error.hint}',
        );
      }
      debugPrintStack(stackTrace: stackTrace);
      return _fail(_messageFor(error, 'Unable to update emergency contacts.'));
    }
  }

  bool _fail(String message) {
    isSaving = false;
    errorMessage = message;
    _notifyListeners();
    return false;
  }

  String _messageFor(Object error, String fallback) {
    if (error is AuthException) {
      return 'Please sign in to manage emergency contacts.';
    }
    if (error is PostgrestException && error.code == '42P01') {
      return 'Emergency contacts are not configured in Supabase yet.';
    }
    if (error is EmergencyContactRepositoryException) return error.message;
    return fallback;
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
