import 'sign_phrase_entity.dart';

/// User Favorite Phrase Bookmark Entity
class FavoritePhrase {
  final String id;
  final String userId;
  final String phraseId;
  final int orderIndex;
  final DateTime createdAt;
  final SignPhrase? phrase;

  const FavoritePhrase({
    required this.id,
    required this.userId,
    required this.phraseId,
    this.orderIndex = 0,
    required this.createdAt,
    this.phrase,
  });

  factory FavoritePhrase.fromJson(Map<String, dynamic> json) {
    SignPhrase? nestedPhrase;
    if (json['sign_dictionary_phrases'] != null && json['sign_dictionary_phrases'] is Map) {
      nestedPhrase = SignPhrase.fromJson(
        Map<String, dynamic>.from(json['sign_dictionary_phrases'] as Map),
      );
    }

    return FavoritePhrase(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      phraseId: json['phrase_id'] as String? ?? '',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      phrase: nestedPhrase,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'phrase_id': phraseId,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }

  FavoritePhrase copyWith({
    String? id,
    String? userId,
    String? phraseId,
    int? orderIndex,
    DateTime? createdAt,
    SignPhrase? phrase,
  }) {
    return FavoritePhrase(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      phraseId: phraseId ?? this.phraseId,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      phrase: phrase ?? this.phrase,
    );
  }
}
