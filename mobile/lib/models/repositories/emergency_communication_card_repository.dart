import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../emergency_communication_card.dart';
import '../emergency_contact.dart';

class EmergencyCommunicationCardRepository {
  EmergencyCommunicationCardRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('No authenticated user is available.');
    }
    return id;
  }

  Future<EmergencyCommunicationCard?> getCard() async {
    final response = await _client
        .from('emergency_communication_cards')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    return response == null
        ? null
        : EmergencyCommunicationCard.fromJson(response);
  }

  Future<EmergencyContact?> getVerifiedPrimaryContact() async {
    final response = await _client
        .from('emergency_contacts')
        .select()
        .eq('user_id', _userId)
        .eq('is_primary', true)
        .eq('is_verified', true)
        .maybeSingle();
    return response == null ? null : EmergencyContact.fromJson(response);
  }

  Future<void> saveCard(EmergencyCommunicationCard card) async {
    await _client.from('emergency_communication_cards').upsert({
      'user_id': _userId,
      ...card.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
