import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../entities/emergency_contact.dart';

class EmergencyContactRepository {
  EmergencyContactRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('No authenticated user is available.');
    }
    return id;
  }

  Future<List<EmergencyContact>> getContacts() async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .select()
          .eq('user_id', _userId)
          .order('is_primary', ascending: false)
          .order('created_at');
      return response
          .map((row) => EmergencyContact.fromJson(row))
          .toList(growable: false);
    } on PostgrestException catch (error) {
      _logSupabaseException('load', error);
      rethrow;
    }
  }

  Future<EmergencyContact?> getPreferredVerifiedContact() async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .select()
          .eq('user_id', _userId)
          .eq('is_verified', true)
          .order('is_primary', ascending: false)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      return response == null ? null : EmergencyContact.fromJson(response);
    } on PostgrestException catch (error) {
      _logSupabaseException('load preferred verified contact', error);
      rethrow;
    }
  }

  Future<void> sendSosNotification({
    required String contactId,
    required DateTime triggeredAt,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _invokeFunction(
      'send-sos-contact',
      body: {
        'contact_id': contactId,
        'triggered_at': triggeredAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      },
      fallbackMessage: 'Unable to notify the emergency contact.',
    );
    _throwForFunctionError(
      response,
      fallbackMessage: 'Unable to notify the emergency contact.',
    );
    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw const EmergencyContactRepositoryException(
        'The emergency contact notification was not confirmed.',
      );
    }
  }

  Future<EmergencyContact> addContact({
    required String name,
    required String relationship,
    required String phoneNumber,
    required String email,
  }) async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .insert({
            'user_id': _userId,
            'name': name,
            'relationship': relationship,
            'phone_number': phoneNumber,
            'email': email,
          })
          .select()
          .single();
      return EmergencyContact.fromJson(response);
    } on PostgrestException catch (error) {
      _logSupabaseException('add', error);
      rethrow;
    }
  }

  Future<EmergencyContact> updateContact({
    required String id,
    required String name,
    required String relationship,
    required String phoneNumber,
    required String email,
  }) async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .update({
            'name': name,
            'relationship': relationship,
            'phone_number': phoneNumber,
            'email': email,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', _userId)
          .select()
          .single();
      return EmergencyContact.fromJson(response);
    } on PostgrestException catch (error) {
      _logSupabaseException('edit', error);
      rethrow;
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      await _client
          .from('emergency_contacts')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
    } on PostgrestException catch (error) {
      _logSupabaseException('delete', error);
      rethrow;
    }
  }

  Future<void> setPrimary(String id) async {
    try {
      await _client.rpc(
        'set_primary_emergency_contact',
        params: {'contact_id': id},
      );
    } on PostgrestException catch (error) {
      _logSupabaseException('set primary', error);
      rethrow;
    }
  }

  Future<void> requestVerification(String id) async {
    final response = await _invokeFunction(
      'request-emergency-contact-otp',
      body: {'contact_id': id},
    );
    _throwForFunctionError(response);
  }

  Future<EmergencyContact> verifyContact({
    required String id,
    required String code,
  }) async {
    final response = await _invokeFunction(
      'verify-emergency-contact-otp',
      body: {'contact_id': id, 'code': code},
    );
    _throwForFunctionError(response);
    final data = Map<String, dynamic>.from(response.data as Map);
    return EmergencyContact.fromJson(
      Map<String, dynamic>.from(data['contact'] as Map),
    );
  }

  Future<FunctionResponse> _invokeFunction(
    String name, {
    required Map<String, dynamic> body,
    String fallbackMessage = 'Unable to verify this contact.',
  }) async {
    try {
      return await _client.functions.invoke(name, body: body);
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : fallbackMessage;
      throw EmergencyContactRepositoryException(message);
    }
  }

  void _throwForFunctionError(
    FunctionResponse response, {
    String fallbackMessage = 'Unable to verify this contact.',
  }) {
    if (response.status < 400) return;
    final data = response.data;
    final message = data is Map && data['error'] is String
        ? data['error'] as String
        : fallbackMessage;
    throw EmergencyContactRepositoryException(message);
  }

  void _logSupabaseException(String operation, PostgrestException error) {
    debugPrint(
      '[EmergencyContactsRepository] Supabase $operation failed: '
      'code=${error.code} message=${error.message} '
      'details=${error.details} hint=${error.hint}',
    );
  }
}

class EmergencyContactRepositoryException implements Exception {
  const EmergencyContactRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
