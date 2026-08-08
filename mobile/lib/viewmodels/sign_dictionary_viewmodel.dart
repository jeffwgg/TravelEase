import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../models/entities/sign_phrase_entity.dart';
import '../models/entities/search_history_entity.dart';
import '../models/repositories/sign_reference_repository.dart';

/// ViewModel for Sign Dictionary & Phrase Search (FR-M4-01 to FR-M4-04, FR-M4-13 to FR-M4-16, UC401)
class SignDictionaryViewModel extends ChangeNotifier {
  final SignReferenceRepository _repository;

  SignDictionaryViewModel({
    SignReferenceRepository? repository,
  }) : _repository = repository ?? SignReferenceRepository() {
    loadDictionary();
  }

  // State Properties
  SignLanguageType _selectedDialect = SignLanguageType.bim;
  String _selectedCategory = 'all';
  String _searchQuery = '';

  List<SignPhrase> _phrases = [];
  List<SearchHistoryItem> _searchHistory = [];
  Set<String> _favoritePhraseIds = {};

  bool _isLoading = true;
  bool _showHistoryDrawer = false;
  String? _errorMessage;

  // Getters
  SignLanguageType get selectedDialect => _selectedDialect;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  List<SignPhrase> get phrases => _phrases;
  List<SearchHistoryItem> get searchHistory => _searchHistory;
  Set<String> get favoritePhraseIds => _favoritePhraseIds;
  bool get isLoading => _isLoading;
  bool get showHistoryDrawer => _showHistoryDrawer;
  String? get errorMessage => _errorMessage;

  bool isFavorite(String phraseId) => _favoritePhraseIds.contains(phraseId);

  // Actions
  Future<void> loadDictionary() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await _repository.searchSignDictionary(
        query: _searchQuery.trim(),
        categoryId: _selectedCategory,
        signLanguage: _selectedDialect,
      );

      final history = await _repository.getSearchHistory('demo_user');
      final favorites = await _repository.getFavoritePhrases('demo_user');

      _phrases = results;
      _searchHistory = history;
      _favoritePhraseIds = favorites.map((f) => f.phraseId).toSet();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load dictionary: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    _searchQuery = query.trim();
    if (_searchQuery.isNotEmpty) {
      await _repository.addSearchHistoryItem(
        userId: 'demo_user',
        query: _searchQuery,
        categoryId: _selectedCategory,
        signLanguageId: _selectedDialect.code,
      );
    }
    loadDictionary();
  }

  void selectCategory(String categoryId) {
    _selectedCategory = categoryId;
    loadDictionary();
  }

  void switchDialect(SignLanguageType dialect) {
    _selectedDialect = dialect;
    loadDictionary();
  }

  Future<void> toggleFavorite(String phraseId) async {
    if (_favoritePhraseIds.contains(phraseId)) {
      _favoritePhraseIds.remove(phraseId);
      notifyListeners();
      await _repository.removeFavoritePhrase('demo_user', phraseId);
    } else {
      _favoritePhraseIds.add(phraseId);
      notifyListeners();
      await _repository.addFavoritePhrase('demo_user', phraseId);
    }
  }

  Future<void> clearSearchHistory() async {
    await _repository.clearSearchHistory('demo_user');
    _searchHistory.clear();
    _showHistoryDrawer = false;
    notifyListeners();
  }

  void toggleHistoryDrawer() {
    _showHistoryDrawer = !_showHistoryDrawer;
    notifyListeners();
  }
}
