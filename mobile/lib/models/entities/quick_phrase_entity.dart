/// Context-aware predefined phrase for instant dialogue insertion (FR-M3-16)
class DialogueQuickPhrase {
  final String id;
  final String category;
  final String textEn;
  final String textMs;
  final String textZh;
  final String? iconName;
  final int displayOrder;

  const DialogueQuickPhrase({
    required this.id,
    required this.category,
    required this.textEn,
    required this.textMs,
    required this.textZh,
    this.iconName = 'chat',
    this.displayOrder = 0,
  });

  String getText(String langCode) {
    switch (langCode.toLowerCase()) {
      case 'ms':
      case 'my':
        return textMs;
      case 'zh':
      case 'cn':
        return textZh;
      default:
        return textEn;
    }
  }

  factory DialogueQuickPhrase.fromJson(Map<String, dynamic> json) {
    return DialogueQuickPhrase(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      textEn: json['text_en'] as String? ?? '',
      textMs: json['text_ms'] as String? ?? '',
      textZh: json['text_zh'] as String? ?? '',
      iconName: json['icon_name'] as String? ?? 'chat',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'text_en': textEn,
      'text_ms': textMs,
      'text_zh': textZh,
      'icon_name': iconName,
      'display_order': displayOrder,
    };
  }
}
