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
