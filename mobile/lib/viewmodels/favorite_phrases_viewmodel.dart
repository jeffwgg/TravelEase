import 'package:flutter/foundation.dart';
import '../models/entities/favorite_phrase_entity.dart';
import '../models/repositories/sign_reference_repository.dart';

/// ViewModel for Bookmarked Favorite Phrases (FR-M4-17 to FR-M4-19)
class FavoritePhrasesViewModel extends ChangeNotifier {
  final SignReferenceRepository _repository;

  FavoritePhrasesViewModel({
    SignReferenceRepository? repository,
  }) : _repository = repository ?? SignReferenceRepository() {
    loadFavorites();
  }

  List<FavoritePhrase> _favorites = [];
  bool _isLoading = true;
  String? _statusMessage;

  List<FavoritePhrase> get favorites => _favorites;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  Future<void> loadFavorites() async {
    _isLoading = true;
    notifyListeners();

    try {
      final list = await _repository.getFavoritePhrases('demo_user');
      _favorites = list;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeFavorite(FavoritePhrase fav) async {
    _favorites.removeWhere((f) => f.id == fav.id);
    notifyListeners();

    await _repository.removeFavoritePhrase('demo_user', fav.phraseId);
  }

  Future<void> restoreFavorite(FavoritePhrase fav) async {
    await _repository.addFavoritePhrase('demo_user', fav.phraseId);
    loadFavorites();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _favorites.removeAt(oldIndex);
    _favorites.insert(newIndex, item);
    notifyListeners();

    await _repository.reorderFavorites('demo_user', oldIndex, newIndex);
  }
}
