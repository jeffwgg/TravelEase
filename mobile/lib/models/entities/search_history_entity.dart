/// Sign Dictionary Search History Entry (FR-M4-15, FR-M4-16)
class SearchHistoryItem {
  final String id;
  final String userId;
  final String searchQuery;
  final String? signLanguageId;
  final String? categoryId;
  final int resultCount;
  final DateTime createdAt;

  const SearchHistoryItem({
    required this.id,
    required this.userId,
    required this.searchQuery,
    this.signLanguageId,
    this.categoryId,
    this.resultCount = 0,
    required this.createdAt,
  });

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return SearchHistoryItem(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      searchQuery: json['search_query'] as String? ?? '',
      signLanguageId: json['sign_language_id'] as String?,
      categoryId: json['category_id'] as String?,
      resultCount: (json['result_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'search_query': searchQuery,
      'sign_language_id': signLanguageId,
      'category_id': categoryId,
      'result_count': resultCount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
