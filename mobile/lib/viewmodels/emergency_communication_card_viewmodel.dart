import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/emergency_communication_card.dart';
import '../models/entities/emergency_contact.dart';
import '../models/repositories/emergency_communication_card_repository.dart';

class EmergencyCommunicationCardViewModel extends ChangeNotifier {
  EmergencyCommunicationCardViewModel({
    EmergencyCommunicationCardRepository? repository,
  }) : _repository = repository ?? EmergencyCommunicationCardRepository();

  final EmergencyCommunicationCardRepository _repository;

  final languagesController = TextEditingController();
  final allergiesController = TextEditingController();
  final medicalNotesController = TextEditingController();

  String hearingImpairmentNote = 'I am deaf / hard of hearing';
  String communicationMethod = 'written_text';
  String signLanguage = 'bim';
  String bloodType = 'unknown';
  EmergencyContact? primaryContact;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final results = await Future.wait([
        _repository.getCard(),
        _repository.getVerifiedPrimaryContact(),
      ]);
      final card = results[0] as EmergencyCommunicationCard?;
      primaryContact = results[1] as EmergencyContact?;
      if (card != null) {
        hearingImpairmentNote = card.hearingImpairmentNote;
        communicationMethod = card.preferredCommunicationMethod;
        signLanguage = card.signLanguage;
        bloodType = card.bloodType;
        languagesController.text = card.languages;
        allergiesController.text = card.allergyInformation;
        medicalNotesController.text = card.medicalNotes;
      }
    } on AuthException {
      errorMessage = 'Please sign in to access your emergency card.';
    } on PostgrestException catch (error) {
      errorMessage = error.code == '42P01'
          ? 'Emergency communication cards are not configured in Supabase yet.'
          : 'Unable to load your emergency card.';
    } catch (_) {
      errorMessage = 'Unable to load your emergency card.';
    }
    isLoading = false;
    _notify();
  }

  void update(VoidCallback change) {
    change();
    errorMessage = null;
    _notify();
  }

  Future<bool> save() async {
    isSaving = true;
    errorMessage = null;
    _notify();
    try {
      await _repository.saveCard(_currentCard);
      isSaving = false;
      _notify();
      return true;
    } catch (_) {
      isSaving = false;
      errorMessage = 'Unable to save your emergency card.';
      _notify();
      return false;
    }
  }

  Future<void> share({Rect? sharePositionOrigin}) async {
    await SharePlus.instance.share(
      ShareParams(
        subject: 'TravelEase Emergency Communication Card',
        text: shareText,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  EmergencyCommunicationCard get _currentCard => EmergencyCommunicationCard(
    hearingImpairmentNote: hearingImpairmentNote,
    preferredCommunicationMethod: communicationMethod,
    signLanguage: signLanguage,
    languages: languagesController.text.trim(),
    bloodType: bloodType,
    allergyInformation: allergiesController.text.trim(),
    medicalNotes: medicalNotesController.text.trim(),
  );

  String get communicationMethodLabel => switch (communicationMethod) {
    'sign_language' => 'Sign language',
    'speech_to_text' => 'Speech-to-text',
    'combined' => 'Combined methods',
    _ => 'Written text / typing',
  };

  String get signLanguageLabel => switch (signLanguage) {
    'asl' => 'ASL (American Sign Language)',
    'none' => 'Not specified',
    _ => 'BIM (Malaysian Sign Language)',
  };

  String get bloodTypeLabel => bloodType == 'unknown' ? 'Unknown' : bloodType;
  String get languagesLabel => languagesController.text.trim().isEmpty
      ? 'Not specified'
      : languagesController.text.trim();
  String get medicalInfoLabel {
    final allergy = allergiesController.text.trim();
    final notes = medicalNotesController.text.trim();
    if (allergy.isEmpty && notes.isEmpty) {
      return 'No medical information provided';
    }
    return [
      if (allergy.isNotEmpty) 'Allergies: $allergy',
      if (notes.isNotEmpty) notes,
    ].join(' · ');
  }

  String get contactLabel => primaryContact == null
      ? 'No verified Primary Emergency Contact'
      : '${primaryContact!.name} — ${primaryContact!.phoneNumber}';

  String get shareText =>
      '''
TRAVELEASE EMERGENCY COMMUNICATION CARD

$hearingImpairmentNote
Preferred communication: $communicationMethodLabel
Sign language: $signLanguageLabel
Languages: $languagesLabel
Blood type: $bloodTypeLabel
Allergies: ${allergiesController.text.trim().isEmpty ? 'None provided' : allergiesController.text.trim()}
Important medical notes: ${medicalNotesController.text.trim().isEmpty ? 'None provided' : medicalNotesController.text.trim()}
Emergency contact: $contactLabel
'''
          .trim();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    languagesController.dispose();
    allergiesController.dispose();
    medicalNotesController.dispose();
    super.dispose();
  }
}
