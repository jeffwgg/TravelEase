import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../emergency_contact.dart';

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

  Future<EmergencyContact> addContact({
    required String name,
    required String relationship,
    required String phoneNumber,
  }) async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .insert({
            'user_id': _userId,
            'name': name,
            'relationship': relationship,
            'phone_number': phoneNumber,
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
    required bool resetVerification,
  }) async {
    try {
      final changes = <String, dynamic>{
        'name': name,
        'relationship': relationship,
        'phone_number': phoneNumber,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (resetVerification) {
        changes.addAll({'is_verified': false, 'is_primary': false});
      }
      final response = await _client
          .from('emergency_contacts')
          .update(changes)
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

  Future<EmergencyContact> markVerified(String id) async {
    try {
      final response = await _client
          .from('emergency_contacts')
          .update({
            'is_verified': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', _userId)
          .select()
          .single();
      return EmergencyContact.fromJson(response);
    } on PostgrestException catch (error) {
      _logSupabaseException('verify', error);
      rethrow;
    }
  }

  void _logSupabaseException(String operation, PostgrestException error) {
    debugPrint(
      '[EmergencyContactsRepository] Supabase $operation failed: '
      'code=${error.code} message=${error.message} '
      'details=${error.details} hint=${error.hint}',
    );
  }
}
