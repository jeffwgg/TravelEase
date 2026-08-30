class EmergencyCommunicationCard {
  const EmergencyCommunicationCard({
    required this.hearingImpairmentNote,
    required this.preferredCommunicationMethod,
    required this.signLanguage,
    required this.languages,
    required this.bloodType,
    required this.allergyInformation,
    required this.medicalNotes,
  });

  final String hearingImpairmentNote;
  final String preferredCommunicationMethod;
  final String signLanguage;
  final String languages;
  final String bloodType;
  final String allergyInformation;
  final String medicalNotes;

  factory EmergencyCommunicationCard.fromJson(Map<String, dynamic> json) {
    return EmergencyCommunicationCard(
      hearingImpairmentNote:
          json['hearing_impairment_note'] as String? ??
          'I am deaf / hard of hearing',
      preferredCommunicationMethod:
          json['preferred_communication_method'] as String? ?? 'written_text',
      signLanguage: json['sign_language'] as String? ?? 'bim',
      languages: json['languages'] as String? ?? '',
      bloodType: json['blood_type'] as String? ?? 'unknown',
      allergyInformation: json['allergy_information'] as String? ?? '',
      medicalNotes: json['medical_notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'hearing_impairment_note': hearingImpairmentNote,
    'preferred_communication_method': preferredCommunicationMethod,
    'sign_language': signLanguage,
    'languages': languages,
    'blood_type': bloodType,
    'allergy_information': allergyInformation,
    'medical_notes': medicalNotes,
  };
}
