/// Enum representing the supported sign languages in TravelEase (ASL First)
enum SignLanguageType {
  asl('ASL', 'American Sign Language', 'American Sign Language', 'US', 'United States', 'en', '🇺🇸'),
  bim('BIM', 'Malaysian Sign Language', 'Bahasa Isyarat Malaysia', 'MY', 'Malaysia', 'ms', '🇲🇾'),
  csl('CSL', 'Chinese Sign Language', '中国手语 (Zhongguo Shouyu)', 'CN', 'China', 'zh', '🇨🇳');

  final String code;
  final String displayName;
  final String nativeName;
  final String countryCode;
  final String countryName;
  final String spokenLangCode;
  final String flagEmoji;

  const SignLanguageType(
    this.code,
    this.displayName,
    this.nativeName,
    this.countryCode,
    this.countryName,
    this.spokenLangCode,
    this.flagEmoji,
  );

  static SignLanguageType fromCode(String? code) {
    if (code == null) return SignLanguageType.asl;
    final upper = code.toUpperCase().trim();
    return SignLanguageType.values.firstWhere(
      (e) => e.code == upper,
      orElse: () => SignLanguageType.asl,
    );
  }
}

/// Metadata information for a sign language
class SignLanguageInfo {
  final String id;
  final String name;
  final String nativeName;
  final String countryCode;
  final String countryName;
  final String primarySpokenLanguage;
  final String? description;
  final String? flagEmoji;
  final bool isActive;

  const SignLanguageInfo({
    required this.id,
    required this.name,
    required this.nativeName,
    required this.countryCode,
    required this.countryName,
    required this.primarySpokenLanguage,
    this.description,
    this.flagEmoji,
    this.isActive = true,
  });

  SignLanguageType get type => SignLanguageType.fromCode(id);

  factory SignLanguageInfo.fromJson(Map<String, dynamic> json) {
    return SignLanguageInfo(
      id: json['id'] as String? ?? 'ASL',
      name: json['name'] as String? ?? 'American Sign Language',
      nativeName: json['native_name'] as String? ?? 'American Sign Language',
      countryCode: json['country_code'] as String? ?? 'US',
      countryName: json['country_name'] as String? ?? 'United States',
      primarySpokenLanguage: json['primary_spoken_language'] as String? ?? 'en',
      description: json['description'] as String?,
      flagEmoji: json['flag_emoji'] as String? ?? '🇺🇸',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'native_name': nativeName,
      'country_code': countryCode,
      'country_name': countryName,
      'primary_spoken_language': primarySpokenLanguage,
      'description': description,
      'flag_emoji': flagEmoji,
      'is_active': isActive,
    };
  }
}
